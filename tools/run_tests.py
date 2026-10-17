"""Run muted game/plugin and charter regression suites on either platform."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import sys

from sync_core import sync
from godot_path import default_godot
from test_results import classify

ROOT = Path(__file__).resolve().parents[1]
GAME_CASES = [("autoplay_test", [])]
for song in ("fixture_dense", "_demo"):
    GAME_CASES += [(name, [song]) for name in ("one_chart", "home_keys_song", "fat_finger_test")]
GAME_CASES += [(name, []) for name in ("autoplay_double_test", "hold_rules_test", "extap_test", "snap_test", "track_any_key_test", "track_chord_test", "chord_gap_test", "ranks_test", "human_keys_test")]
# replay_log: cut=0 so the replay uses the default game rules (no midpoint cut; guard, same-track and landing flags left at their defaults)
GAME_CASES += [("replay_log", [str(ROOT / "game/tests/fixtures/replay_synthetic.json"), "fixture_dense", "0"])]
CHARTER_CASES = ["charter_model", "charter_tools", "charter_http", "charter_ui", "charter_versions", "charter_auth", "charter_library", "charter_timing", "charter_plugins", "charter_agent_io", "charter_agent_http", "charter_layout"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    default = default_godot()
    parser.add_argument("--godot", default=os.environ.get("GODOT", default))
    parser.add_argument("--suite", choices=["all", "game", "charter"], default="all")
    parser.add_argument("--visual", action="store_true", help="Render the two charter visual suites offscreen (use xvfb on Linux)")
    a = parser.parse_args()
    sync()
    subprocess.run([sys.executable, str(ROOT / "charter/tests/fixtures/generate_osu.py")], check=True)
    env = os.environ.copy()
    out = ROOT / "dist/test-results"
    out.mkdir(parents=True, exist_ok=True)
    env["APPDATA"] = str(out / "userdata")
    env["LOCALAPPDATA"] = str(out / "localdata")
    env["XDG_DATA_HOME"] = str(out / "xdg-data")
    env["XDG_CONFIG_HOME"] = str(out / "xdg-config")
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    failed = []
    for project in ("game", "charter"):
        if a.suite not in ("all", project): continue
        result = subprocess.run([a.godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / project), "--import"], env=env, capture_output=True)
        (out / (project + "-import.log")).write_bytes(result.stdout + result.stderr)
        if result.returncode: raise SystemExit(f"Import failed: {project}")
        cases = list(GAME_CASES) if project == "game" else [(name, []) for name in CHARTER_CASES]
        if project == "game":
            # Focused runtime/plugin tests, without capture, diagnostic, or external-service probes.
            already = {name for name, _ in cases}
            for p in sorted((ROOT / "game/tests").glob("*_test.gd")):
                focused = any(token in p.stem for token in ("shape", "motion", "fall_speed", "plugin_", "affine_", "projection_"))
                if p.stem not in already and focused and p.stem != "song_plugin_ui_test":
                    cases.append((p.stem, ["--isolated-test-user", "--songs-root=" + str(ROOT / "songs")]))
        if project == "charter" and a.visual:
            cases += [(name, []) for name in ("charter_plugins_visual", "charter_visual")]
        summaries = []
        for index, (name, args) in enumerate(cases):
            graphics = name in ("charter_plugins_visual", "charter_visual") or (name == "charter_layout" and a.visual)
            flags = ["--position", "-5000,-5000", "--rendering-driver", "opengl3"] if graphics else ["--headless"]
            cmd = [a.godot, "--audio-driver", "Dummy", "--path", str(ROOT / project), *flags, "-s", f"res://tests/{name}.gd", "--", *args]
            result = subprocess.run(cmd, env=env, capture_output=True, timeout=360)
            text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
            label = f"{project}-{index:02d}-{name}"
            (out / (label + ".log")).write_text(text, encoding="utf-8")
            failures, diagnostics = classify(name, text)
            bad = result.returncode or failures
            if bad: failed.append(label)
            lines = [line for line in text.splitlines() if re.search(r"autoplay:|home-key|fat-finger|RULES|TRACK|CHORD GAP|PASS|FAIL|TOTAL|bad charts|^OK |^BAD |^replay|checks=", line)]
            summaries += ["== " + label, *lines]
            print(label, "FAIL" if bad else "PASS", f"({len(diagnostics)} retained engine diagnostics)", flush=True)
        (ROOT / project / "tests/out").mkdir(parents=True, exist_ok=True)
        (ROOT / project / "tests/out/results.txt").write_text("\n".join(summaries) + "\n", encoding="utf-8")
    print(f"Results: {out}; failed suites: {len(failed)}", *failed, sep="\n")
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main())
