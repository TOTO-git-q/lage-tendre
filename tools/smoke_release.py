"""Smoke-test extracted local release archives; never touches source songs or publishes."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/restructure/smoke"


def nonblack(path):
    from PIL import Image
    image = Image.open(path).convert("RGB")
    assert max(v[1] for v in image.getextrema()) > 30, f"Black image: {path}"
    return list(image.size)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    unpacked = OUT / ("unpacked-" + str(time.time_ns()))
    unpacked.mkdir()
    env = os.environ.copy()
    env["APPDATA"] = str(unpacked / "userdata")
    env["LOCALAPPDATA"] = str(unpacked / "localdata")
    Path(env["APPDATA"]).mkdir(exist_ok=True)
    Path(env["LOCALAPPDATA"]).mkdir(exist_ok=True)
    report = {}
    for name in ("LAgeTendre", "LAgeTendreCharter"):
        archive = ROOT / "release" / (name + "-win64.zip")
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            required = {name + "/LAgeTendre.exe", name + "/KeyGuard.exe", name + "/songs/index.json"}
            if name == "LAgeTendreCharter": required |= {name + "/LAgeTendreCharter.exe", name + "/README.md"}
            assert required.issubset(z.namelist())
            assert not any(p.endswith("override.cfg") for p in z.namelist())
            for member in z.namelist():
                prefix = name + "/songs/"
                if member.startswith(prefix):
                    rel = member.removeprefix(prefix)
                    assert z.read(member) == (ROOT / "songs" / rel).read_bytes(), member
            z.extractall(unpacked)
        report[name] = {"zip_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "bytes": archive.stat().st_size}
    game = unpacked / "LAgeTendre"
    screenshot = OUT / "game.png"
    result = subprocess.run([str(game / "LAgeTendre.exe"), "--position", "-5000,-5000", "--audio-driver", "Dummy", "--", "--mute", "--autoplay", "--song=demo", "--from=20", "--shot=" + str(screenshot), "--shot-at=2"], cwd=game, env=env, capture_output=True, timeout=100)
    text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    (OUT / "game.log").write_text(text, encoding="utf-8")
    assert result.returncode == 0 and "SCRIPT ERROR" not in text, text
    report["LAgeTendre"]["screenshot"] = nonblack(screenshot)
    print("EXTRACTED_GAME PASS: non-black screenshot", flush=True)
    charter = unpacked / "LAgeTendreCharter"
    assert (game / "LAgeTendre.exe").read_bytes() == (charter / "LAgeTendre.exe").read_bytes()
    log = OUT / "charter.log"
    with log.open("wb") as stream:
        process = subprocess.Popen([str(charter / "LAgeTendreCharter.exe"), "--position", "-5000,-5000", "--audio-driver", "Dummy", "--", "--silent", "--shots=" + str(OUT / "charter-shots")], cwd=charter, env=env, stdout=stream, stderr=subprocess.STDOUT)
        try:
            ready = None
            for _ in range(400):
                text = log.read_text(encoding="utf-8", errors="replace")
                ready = re.search(r"CHARTER_READY songs=(\d+) notes=(\d+) mcp=(\d+)", text)
                if ready: break
                if process.poll() is not None: raise RuntimeError(text)
                time.sleep(.1)
            assert ready and int(ready[1]) >= 4, text
            session = None
            def rpc(method, params):
                nonlocal session
                headers = {"Content-Type": "application/json"}
                if session: headers["Mcp-Session-Id"] = session
                request = urllib.request.Request(f"http://127.0.0.1:{ready[3]}/mcp", data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(), headers=headers)
                with urllib.request.urlopen(request, timeout=30) as response:
                    session = response.headers["Mcp-Session-Id"]
                    return json.load(response)["result"]
            rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "restructure-smoke", "version": "1"}})
            tools = rpc("tools/list", {})["tools"]
            info = json.loads(rpc("tools/call", {"name": "song_info", "arguments": {}})["content"][0]["text"])
            assert Path(info["path"]).resolve().is_relative_to((charter / "songs").resolve()), info
            standard = json.loads(rpc("tools/call", {"name": "plugin_standard", "arguments": {"section": "manifest"}})["content"][0]["text"])
            assert standard.get("content"), standard
            process.wait(timeout=180)
            text = log.read_text(encoding="utf-8", errors="replace")
            assert process.returncode == 0 and "SCRIPT ERROR" not in text and "CHARTER_SHOTS" in text, text[-5000:]
            report["LAgeTendreCharter"].update(songs=int(ready[1]), notes=int(ready[2]), tools=len(tools), song_info=info,
                screenshot=nonblack(OUT / "charter-shots/preview.png"), plugin_help=True, pid=process.pid)
            print("EXTRACTED_CHARTER PASS: songs beside exe, MCP song_info, plugin help, non-black preview and UI captures", flush=True)
        finally:
            if process.poll() is None: process.terminate()
            process.wait(timeout=10)
    (OUT / "receipt.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("SMOKE RELEASE PASS", flush=True)


if __name__ == "__main__":
    main()
