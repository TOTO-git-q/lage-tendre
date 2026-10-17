#!/usr/bin/env python3
"""Capture real, deterministic Xvfb render evidence with the shipped gameplay code."""
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
import platform
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parent
POINTS = {
    "fixture_dense": [("intro", 3.0), ("dense", 20.0), ("chord", 31.0), ("hold", 35.1), ("yellow_chain", 36.0), ("ending", 102.0)],
    "_demo": [("intro", 2.5), ("dense", 54.5), ("chorus", 50.5), ("hold", 43.0), ("yellow_cue", 14.0), ("ending", 63.5)],
    "demo": [("intro", 2.5), ("dense", 54.5), ("chorus", 50.5), ("hold", 43.0), ("yellow_cue", 14.0), ("ending", 63.5)],
}


def git_blob(path):
    data = Path(path).read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--mode", choices=("screenshots", "performance", "all"), default="all")
    parser.add_argument("--only-song", choices=tuple(POINTS), help="recapture just one chart's six images")
    args = parser.parse_args()
    if os.name != "nt" and not os.environ.get("DISPLAY"):
        raise SystemExit("Run under Xvfb; no real display is used.")
    out = args.out.resolve()
    (out / "logs").mkdir(parents=True, exist_ok=True)
    (out / "screenshots").mkdir(exist_ok=True)
    overrides = json.loads((PROJECT / "tests/baselines/source_overrides.json").read_text())
    for item in overrides["owner_accepted_replacements"]:
        if git_blob(ROOT / item["path"]) != item["replacement_git_blob"]:
            raise SystemExit("Accepted replacement bytes changed: " + item["path"])
    (out / "source_overrides.json").write_text(json.dumps(overrides, indent=2) + "\n")
    with TemporaryWorkspace(dir=Path(__file__).resolve().parents[2] / "dist", prefix="lage-render-") as home:
        env = dict(os.environ, APPDATA=home, LOCALAPPDATA=home, HOME=home, XDG_DATA_HOME=home + "/data",
                   XDG_CACHE_HOME=home + "/cache", XDG_CONFIG_HOME=home + "/config")
        for folder in ("data", "cache", "config"):
            Path(home, folder).mkdir()

        def run(name, extra):
            command = [args.godot, "--audio-driver", "Dummy", "--rendering-driver", "opengl3",
                       "--position", "-5000,-5000", "--path", str(PROJECT), "-s", "res://tests/capture_render.gd", "--", *extra]
            print("RUN", name, flush=True)
            result = subprocess.run(command, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
            text = (result.stdout + result.stderr).replace("ERROR: Failed to read the root certificate store.", "")
            (out / "logs" / (name + ".txt")).write_text(text.replace(str(ROOT), "<repo>"), encoding="utf-8")
            print(text, end="", flush=True)
            if result.returncode or re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", text, re.M):
                raise RuntimeError(f"Render evidence failed: {name}, exit={result.returncode}")

        if args.mode in ("screenshots", "all"):
            shots = []
            for song, points in POINTS.items():
                for category, at in points:
                    name = f"{song}__{category}"
                    relative = "screenshots/" + name + ".png"
                    if not args.only_song or song == args.only_song:
                        run(name, ["--song=" + song, f"--time={at}", "--out=" + str(out / relative)])
                    if not (out / relative).is_file():
                        raise RuntimeError("A complete 18-image set is required: missing " + relative)
                    shots.append({"song": song, "category": category, "chart_time": at, "file": relative})
            manifest = {"schema": 1, "resolution": [1600, 900], "seed": 20261017, "fps": 60,
                        "warmup_seconds": 2.0, "shots": shots,
                        "protocol": "Real gameplay Renderer; fixed chart clock and seeded particles; identical default settings; no audio clock drift.",
                        "demo_note": "The unmodified built-in demo has yellow pedal cues but no ExTap chain. Its fifth capture covers the yellow cue; no notes were invented."}
            (out / "screenshots.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if args.mode in ("performance", "all"):
            environment = {"platform": platform.platform(), "machine": platform.machine(),
                           "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else [],
                           "loadavg_before": list(os.getloadavg()) if hasattr(os, "getloadavg") else [],
                           "renderer_environment": {key: env.get(key, "<default>") for key in
                                                    ("LP_NUM_THREADS", "LIBGL_ALWAYS_SOFTWARE", "MESA_LOADER_DRIVER_OVERRIDE")}}
            run("performance", ["--mode=performance", "--song=fixture_dense",
                                "--out=" + str(out / "performance.json")])
            environment["loadavg_after"] = list(os.getloadavg()) if hasattr(os, "getloadavg") else []
            (out / "performance_environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    print("RENDER EVIDENCE COMPLETE", args.mode, flush=True)


if __name__ == "__main__":
    main()
