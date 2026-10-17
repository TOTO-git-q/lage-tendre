"""Bounded agent-IO validation; all runtime state is confined to repo/dist."""
from pathlib import Path
import os
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = r"E:\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"


def main():
    from sync_core import sync
    sync()
    out = ROOT / "dist/agent-io"
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key, folder in (("APPDATA", "userdata"), ("LOCALAPPDATA", "localdata"), ("XDG_DATA_HOME", "xdg"), ("XDG_CONFIG_HOME", "config")):
        env[key] = str(out / folder)
        Path(env[key]).mkdir(exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / "charter/tests/fixtures/generate_osu.py")], check=True)
    cases = sys.argv[1:] or ["charter_agent_io"]
    failed = False
    for case in cases:
        visual = case.endswith("visual")
        flags = ["--position", "-5000,-5000", "--rendering-driver", "opengl3"] if visual else ["--headless"]
        log = out / f"{case}.log"
        command = [GODOT, "--audio-driver", "Dummy", "--path", str(ROOT / "charter"), *flags, "-s", f"res://tests/{case}.gd"]
        with log.open("wb") as stream:
            process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
            print(f"{case} owned PID={process.pid}", flush=True)
            deadline = time.monotonic()+240
            while process.poll() is None:
                time.sleep(.2)
                content = log.read_text(encoding="utf-8", errors="replace")
                if "SCRIPT ERROR" in content or time.monotonic()>deadline:
                    process.kill()
                    break
            process.wait()
        text = log.read_text(encoding="utf-8", errors="replace")
        result = process
        ok = not result.returncode and "SCRIPT ERROR" not in text and "FAIL " not in text
        print(case, "PASS" if ok else "FAIL", flush=True)
        print(text[-12000:] if not ok else "\n".join(line for line in text.splitlines() if line.startswith(("PASS ", "CHARTER_"))))
        failed |= not ok
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
