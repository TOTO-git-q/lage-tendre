"""Run the menu integration test with isolated saves, muted offscreen rendering."""
from pathlib import Path
import os
import subprocess
import sys

from test_results import classify

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/menu-keys"

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key, folder in (("APPDATA", "userdata"), ("LOCALAPPDATA", "localdata"),
                        ("XDG_DATA_HOME", "xdg-data"), ("XDG_CONFIG_HOME", "xdg-config")):
        path = OUT / folder
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    cmd = [r"E:\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe",
           "--path", str(ROOT / "game"), "--audio-driver", "Dummy",
           "--position", "-5000,-5000", "--rendering-driver", "opengl3",
           "-s", "res://tests/menu_keys_test.gd", "--", "--mute", "--windowed",
           "--isolated-test-user", "--ui-shots=" + str(OUT)]
    result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, timeout=180)
    text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    (OUT / "integration.log").write_text(text, encoding="utf-8")
    print(text)
    failures, _ = classify("menu_keys_test", text)
    return int(bool(result.returncode or failures or "MENU KEYS: PASS" not in text))

if __name__ == "__main__":
    sys.exit(main())
