"""Bounded silent verification. --visual renders offscreen; --claude requires live CLI login.

Does not rewrite source charts. All receipts are under charter/evidence.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from godot_path import default_godot

ROOT = Path(__file__).resolve().parent
GODOT = default_godot()
EVIDENCE = ROOT / "evidence"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--claude", action="store_true")
    parser.add_argument("--game", action="store_true")
    args = parser.parse_args()
    subprocess.run(["python", str(ROOT.parent / "tools/sync_core.py")], check=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["APPDATA"] = str(ROOT / "runtime")
    paths = [p for p in (ROOT.parent / "songs").rglob("*") if p.is_file() and p.suffix in (".json", ".wav")]
    before = {str(p): digest(p) for p in paths}
    repos_before = {str(p.parent): (p.parent / '.git').exists() for p in paths}
    checks = []

    def run(name, cmd, timeout=100):
        result = subprocess.run(cmd, env=env, capture_output=True, timeout=timeout)
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        (EVIDENCE / f"{name}.log").write_text(output, encoding="utf-8")
        ok = result.returncode == 0 and "SCRIPT ERROR" not in output and "failures=1" not in output
        checks.append(dict(name=name, exit_code=result.returncode, passed=ok))
        print(name, "PASS" if ok else "FAIL", flush=True)
        return ok

    base = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT)]
    for name in ("charter_model", "charter_tools", "charter_http", "charter_ui", "charter_versions", "charter_auth", "charter_library", "charter_timing"):
        run(name, base + ["-s", f"res://tests/{name}.gd"], 260 if name == "charter_ui" else 100)
    if args.game:
        for name in ("one_chart", "home_keys_song", "fat_finger_test", "hold_rules_test", "extap_test", "snap_test", "autoplay_test"):
            cmd = [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT.parent / "game"), "-s", f"res://tests/{name}.gd"]
            if name in ("one_chart", "home_keys_song", "fat_finger_test"):
                cmd += ["--", "fixture_dense"]
            run(name, cmd, 150)
    if args.visual:
        display = [GODOT, "--audio-driver", "Dummy", "--path", str(ROOT), "--position", "-5000,-5000"]
        run("charter_visual", display + ["-s", "res://tests/charter_visual.gd"])
        run("charter_shots", display + ["res://charter_main.tscn", "--", f"--shots={ROOT / 'shots'}"])
        # the same editor at the owner's screen (2880 x 1800, about 1.8x the design size) and at 1920 x 1080,
        # with the proportional UI scale switched on
        run("charter_shots_scaled", display + ["res://charter_main.tscn", "--", f"--shots={ROOT / 'shots/scaled'}", "--shots-scaled"])
    if args.claude:
        run("charter_claude", base + ["-s", "res://tests/charter_claude.gd", "--", "--silent"], 170)
    after = {str(p): digest(p) for p in paths}
    repos_after = {str(p.parent): (p.parent / '.git').exists() for p in paths}
    preservation = before == after and repos_before == repos_after
    (EVIDENCE / "source_integrity.json").write_text(json.dumps(dict(before=before, after=after, repos_before=repos_before, repos_after=repos_after, identical=preservation), indent=2), encoding="utf-8")
    checks.append(dict(name="source chart and audio preservation", passed=preservation))
    (EVIDENCE / "verification.json").write_text(json.dumps(checks, indent=2), encoding="utf-8")
    raise SystemExit(0 if all(c["passed"] for c in checks) else 1)


if __name__ == "__main__":
    main()
