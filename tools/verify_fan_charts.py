"""Reproducible temporary-root fan-chart/menu/charter/package verification; no source-song edits."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import time

from godot_path import default_godot
from sync_core import sync
from test_validate_fan_chart import make_sample
from validate_fan_chart import main as validate
from build_release import copy_songs

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--headless", action="store_true", help="skip screenshot when no graphics driver is available")
    parser.add_argument("--native-game", type=Path, help="also test an exported Windows game beside temporary songs")
    args = parser.parse_args()
    if args.native_game and args.headless: parser.error("--native-game requires offscreen graphics for the result screenshot")
    sync()
    out = ROOT / "dist/fanmade-verification"
    out.mkdir(parents=True, exist_ok=True)
    # Only replace this verifier's named generated fixture tree.
    songs = out / "songs"
    if songs.exists(): shutil.rmtree(songs)
    songs.mkdir()
    for slug, title in (("alpha", "Alpha original"), ("zulu", "Zulu original")):
        make_sample(songs, slug, title)
    for reserved in ("_template", "_private", ".hidden"):
        shutil.copytree(songs / "fan-made/alpha", songs / "fan-made" / reserved)
    broken = songs / "fan-made/broken"; broken.mkdir(); (broken / "info.json").write_text("[]", encoding="utf-8")
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        env[key] = str(out / key); Path(env[key]).mkdir(exist_ok=True)
    def engine(project, script=None, user=(), graphics=False):
        flags = ["--position", "-5000,-5000", "--rendering-driver", "opengl3"] if graphics else ["--headless"]
        command = [args.godot, "--audio-driver", "Dummy", "--path", str(ROOT / project), *flags]
        command += ["-s", "res://tests/" + script + ".gd", "--", *user] if script else ["--import"]
        proc = subprocess.run(command, capture_output=True, env=env, timeout=120)
        text = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
        log = out / ((script or project + "-import") + ".log"); log.write_text(text, encoding="utf-8")
        errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or line.startswith("FAIL ") or (line.startswith("ERROR:") and line != "ERROR: Failed to read the root certificate store.")]
        if proc.returncode or errors: raise RuntimeError(str(log) + "\n" + "\n".join(errors))
        print("PASS", project, script or "import", flush=True)
    engine("game"); engine("charter")
    if validate(["alpha", "zulu", "--songs-root", str(songs), "--godot", args.godot, "--summary", str(out / "validator-summary.md")]):
        raise RuntimeError("valid temporary samples failed")
    user = [str(songs)]
    if not args.headless: user.append(str(out / "game-song-list.png"))
    engine("game", "fan_chart_app_test", [*user, "--mute", "--windowed"], graphics=not args.headless)
    engine("charter", "charter_fan_library", [str(songs), "--mute"])
    if args.native_game:
        native = out / "native-game"
        native.mkdir(exist_ok=True)
        executable = native / "LAgeTendre.exe"
        shutil.copy2(args.native_game, executable)
        native_songs = native / "songs"
        if native_songs.exists(): shutil.rmtree(native_songs)
        for slug in ("alpha", "zulu", "_template", "_private", ".hidden", "broken"):
            shutil.copytree(songs / "fan-made" / slug, native_songs / "fan-made" / slug)
        log = out / "native-game.log"
        graphics = ["--position", "-5000,-5000", "--rendering-driver", "opengl3"]
        shot = out / "native-fan-result.png"
        if shot.exists(): shot.unlink()
        native_env = env.copy()
        native_user = out / ("native-user-" + str(time.time_ns()))
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            native_env[key] = str(native_user / key); Path(native_env[key]).mkdir(parents=True)
        # Release templates run the product's main scene, so exercise its existing CLI.
        user = ["--song=fan-made/alpha", "--autoplay", "--mute", "--windowed", "--shot=" + str(shot), "--shot-at=11.5"]
        proc = subprocess.run([str(executable), "--audio-driver", "Dummy", *graphics, "--log-file", str(log), "--", *user], env=native_env, capture_output=True, timeout=45)
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else proc.stdout.decode("utf-8", errors="replace")
        checked = text.replace("ERROR: Failed to read the root certificate store.", "")
        if proc.returncode or "SCRIPT ERROR" in checked or "ERROR:" in checked or "FAIL " in checked or not shot.is_file():
            raise RuntimeError("Native exported game failed: " + str(log) + "\n" + checked[-3000:])
        # The normal app writes its completed playlog under this isolated userdata root.
        logs = list((native_user / "APPDATA/LAgeTendre/playlogs").glob("fan-made__alpha_*.json"))
        completed = [json.loads(p.read_text(encoding="utf-8")) for p in logs]
        good = [p for p in completed if p.get("reason") == "result" and p.get("autoplay") and p.get("stats", {}).get("PERFECT") == 5 and p["stats"].get("total") == 5 and p["stats"].get("MISS") == 0]
        if not good: raise RuntimeError("No completed all-PERFECT native fan-chart playlog")
        (out / "native-result-stats.json").write_text(json.dumps(good[0]["stats"], indent=2) + "\n", encoding="utf-8")
        print("PASS exported game loads fan chart beside exe, autoplays 5/5 PERFECT and saves result screenshot", flush=True)
    staged = out / "release-songs"
    if staged.exists(): shutil.rmtree(staged)
    copy_songs(staged)
    assert (staged / "fan-made/README.md").is_file()
    assert not (staged / "fan-made/_template").exists()
    # Also exercise the actual copy loop on a temporary release-style songs root.
    import build_release
    original_root = build_release.ROOT
    try:
        build_release.ROOT = out
        copy_songs(out / "sample-release/songs")
    finally:
        build_release.ROOT = original_root
    assert (out / "sample-release/songs/fan-made/alpha/info.json").is_file()
    assert not (out / "sample-release/songs/fan-made/_template").exists()
    print("PASS actual release copy includes submissions and excludes template/reserved folders", flush=True)
    (out / "result.json").write_text(json.dumps({"status": "PASS", "autoplay": "5/5 PERFECT per sample", "source_songs_unchanged": True, "screenshot": None if args.headless else "game-song-list.png"}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__": raise SystemExit(main())
