#!/usr/bin/env python3
"""Capture unmodified game checks, retaining outputs that run_tests.sh filters out."""
from __future__ import annotations

import argparse
import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[2] / "tools"))
from godot_path import default_godot
from workspace_temp import TemporaryWorkspace
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
SCRIPTS = [
    "autoplay_double_test", "hold_rules_test", "extap_test", "snap_test",
    "track_any_key_test", "track_chord_test", "chord_gap_test", "ranks_test",
    "human_keys_test",
]


def cases():
    yield "autoplay_test", "autoplay_test", []
    for song in ("fixture_dense", "_demo"):
        for script in ("one_chart", "home_keys_song", "fat_finger_test"):
            yield f"{script}__{song}", script, [song]
    for script in SCRIPTS:
        yield script, script, []
    fixture = str(PROJECT / "tests/fixtures/replay_synthetic.json")
    yield "replay_log__construction_command", "replay_log", [fixture, "fixture_dense"]
    # The shipped replay harness overrides cut_same_track to false without arg 5.
    # Preserve that command AND measure the current GameCore default explicitly.
    yield "replay_log__game_defaults", "replay_log", [fixture, "fixture_dense", "1", "1", "track"]


def result_lines(output):
    return [line.rstrip() for line in output.splitlines()
            if line.strip() and not line.startswith("Godot Engine v")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--pack", type=Path, help="exercise the compiled exported PCK, retaining external test scripts")
    parser.add_argument("--only", action="append", help="rerun a named case, retaining other completed evidence")
    args = parser.parse_args()
    out = args.out.resolve()
    logs = out / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    run = {"schema": 1, "scope": "numeric", "source_commit": args.source_commit, "tests": {}}
    if args.only:
        known = {name for name, _, _ in cases()}
        if set(args.only) - known:
            parser.error("unknown case: " + str(set(args.only) - known))
        if (out / "baseline_tests.json").exists():
            run = json.loads((out / "baseline_tests.json").read_text())
            if run["source_commit"] != args.source_commit:
                parser.error("cannot mix source commits in a partial rerun")
    if args.pack:
        args.pack = args.pack.resolve()
        pack_sha = hashlib.sha256(args.pack.read_bytes()).hexdigest()
        if run.get("runtime_pack_sha256", pack_sha) != pack_sha:
            parser.error("cannot mix exported packs in a partial rerun")
        run["runtime_pack_sha256"] = pack_sha
    with TemporaryWorkspace(dir=Path(__file__).resolve().parents[2] / "dist", prefix="lage-baseline-") as home:
        env = dict(os.environ, APPDATA=home, LOCALAPPDATA=home, HOME=home, XDG_DATA_HOME=home + "/data",
                   XDG_CACHE_HOME=home + "/cache", XDG_CONFIG_HOME=home + "/config")
        for path in ("data", "cache", "config"):
            Path(home, path).mkdir()
        version = subprocess.run([args.godot, "--headless", "--audio-driver", "Dummy", "--version"],
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, check=True)
        run["godot"] = version.stdout.strip()
        if not run["godot"].startswith("4.7.2."):
            raise SystemExit("P0 requires Godot 4.7.2; got " + run["godot"])
        for name, script, extra in cases():
            if args.only and name not in args.only:
                continue
            cmd = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(PROJECT)]
            if args.pack:
                cmd += ["--main-pack", str(args.pack)]
            script_path = str(PROJECT / "tests" / (script + ".gd")) if args.pack else "res://tests/" + script + ".gd"
            cmd += ["-s", script_path, "--", *extra]
            print("RUN", name, flush=True)
            completed = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=600)
            output = completed.stdout + completed.stderr
            (logs / (name + ".txt")).write_text(output)
            errors = [line for line in output.splitlines()
                      if line != "ERROR: Failed to read the root certificate store." and re.search(r"(?:SCRIPT ERROR|Parse Error|^ERROR:|^LOAD FAIL|^BAD\b|^FAIL\b|:\s*FAIL\b|^bad charts:\s*[1-9])", line)]
            lines = result_lines(completed.stdout)
            run["tests"][name] = {"script": script, "args": [x.replace(str(PROJECT), "<project>") for x in extra],
                                  "exit_code": completed.returncode, "lines": lines,
                                  "errors": errors, "stdout_sha256": hashlib.sha256(completed.stdout.encode()).hexdigest()}
            (out / "baseline_tests.json").write_text(json.dumps(run, ensure_ascii=False, indent=2) + "\n")
            print("RESULT", name, "exit", completed.returncode, "errors", len(errors), flush=True)
    run["numeric_capture_complete"] = len(run["tests"]) == 18 and all(
        item["exit_code"] == 0 and item["lines"] and not item["errors"] for item in run["tests"].values())
    run.pop("complete", None)
    run["scope"] = "numeric"
    run["replay_note"] = "The construction command uses cut_same_track=false; game_defaults explicitly uses true. No game rule was changed."
    (out / "baseline_tests.json").write_text(json.dumps(run, ensure_ascii=False, indent=2) + "\n")
    print("NUMERIC CAPTURE", "COMPLETE" if run["numeric_capture_complete"] else "FAILED")
    print("P0 remains incomplete until independent numeric, 18-image and 30-second performance comparisons pass.")
    return 0 if run["numeric_capture_complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
