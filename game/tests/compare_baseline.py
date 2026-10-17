#!/usr/bin/env python3
"""Fail-closed P0/P1+ regression comparison. Default requires every evidence type."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re

EXPECTED_TESTS = {
    "autoplay_test", "autoplay_double_test", "hold_rules_test", "extap_test", "snap_test",
    "track_any_key_test", "track_chord_test", "chord_gap_test", "ranks_test", "human_keys_test",
    "replay_log__construction_command", "replay_log__game_defaults",
    *(f"{test}__{song}" for test in ("one_chart", "home_keys_song", "fat_finger_test")
      for song in ("fixture_dense", "_demo")),
}


def read_json(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def image_difference(reference, candidate):
    from PIL import Image, ImageChops
    with Image.open(reference) as a, Image.open(candidate) as b:
        if a.size != b.size:
            return {"passed": False, "error": "image dimensions differ"}
        if a.size != (1600, 900):
            return {"passed": False, "error": "expected 1600x900"}
        delta = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
        maximum = max(hi for lo, hi in delta.getextrema())
        channels = delta.split()
        changed_mask = channels[0]
        for channel in channels[1:]:
            changed_mask = ImageChops.lighter(changed_mask, channel)
        changed = a.width * a.height - changed_mask.histogram()[0]
        ratio = changed / (a.width * a.height)
        return {"passed": maximum <= 2 and ratio <= 0.001,
                "max_channel_difference": maximum, "different_pixels": changed,
                "different_pixel_ratio": ratio}


def compare_numbers(reference, candidate):
    a, b = read_json(reference), read_json(candidate)
    differences = []
    if not a.get("numeric_capture_complete") or not b.get("numeric_capture_complete"):
        differences.append("numeric capture incomplete")
    if a.get("godot") != b.get("godot"):
        differences.append("Godot versions differ")
    if set(a.get("tests", {})) != set(b.get("tests", {})):
        differences.append("test set differs")
    if set(a.get("tests", {})) != EXPECTED_TESTS:
        differences.append("expected 18 specified and supplemental numeric checks")
    for label, data in (("reference", a), ("candidate", b)):
        for key, case in data.get("tests", {}).items():
            if case.get("exit_code") != 0 or case.get("errors") != [] or not case.get("lines"):
                differences.append(label + " " + key + ": failed or incomplete process")
            if any(re.search(r"^BAD\b|^FAIL\b|:\s*FAIL\b|^bad charts:\s*[1-9]", line) for line in case.get("lines", [])):
                differences.append(label + " " + key + ": test reported failure")
    for key in sorted(set(a.get("tests", {})) | set(b.get("tests", {}))):
        if key not in a.get("tests", {}) or key not in b.get("tests", {}):
            continue
        for field in ("script", "args", "exit_code", "lines", "errors"):
            if a["tests"][key].get(field) != b["tests"][key].get(field):
                differences.append(key + ": " + field + " differs")
    return {"passed": not differences, "differences": differences}


def compare_performance(reference, candidate):
    a, b = read_json(reference), read_json(candidate)
    reasons = []
    for data in (a, b):
        if data.get("duration_seconds", 0) < 30 or data.get("frames", 0) < 1800:
            reasons.append("at least 30 seconds of actual update+draw measurements required")
        if data.get("wall_duration_seconds", 0) < 30:
            reasons.append("at least 30 wall seconds of real rendering required")
        if data.get("scope") != "GameCore.update+Renderer.frame+Renderer.draw_callbacks":
            reasons.append("unexpected measurement scope")
        samples = data.get("samples_usec", [])
        if len(samples) != data.get("frames") or any(not isinstance(s, (int, float)) or not math.isfinite(s) or s <= 0 for s in samples):
            reasons.append("missing or invalid per-frame samples")
        elif samples:
            ordered = sorted(samples)
            if not math.isclose(sum(samples) / len(samples), data.get("mean_usec", 0), rel_tol=1e-9):
                reasons.append("mean does not match recorded samples")
            if ordered[math.ceil(len(samples) * 0.95) - 1] != data.get("p95_usec"):
                reasons.append("p95 does not match recorded samples")
            components = [data.get(key, []) for key in ("update_samples_usec", "frame_samples_usec", "draw_samples_usec")]
            if any(len(values) != len(samples) for values in components):
                reasons.append("component measurements are missing")
            elif any(any(not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 for value in values) for values in components):
                reasons.append("invalid component measurements")
            elif any(sum(values) != total for values, total in zip(zip(*components), samples)):
                reasons.append("frame totals do not match measured update+frame+draw")
        if data.get("draw_callbacks", 0) < data.get("frames", 0):
            reasons.append("no real draw callbacks recorded")
    for key in ("song", "fps", "seed", "resolution", "godot", "rendering_method", "rendering_device"):
        if not a.get(key) or a.get(key) != b.get(key):
            reasons.append("performance environment differs or missing: " + key)
    changes = {}
    for key in ("mean_usec", "p95_usec"):
        x, y = a.get(key, 0), b.get(key, 0)
        if not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or not math.isfinite(x) or not math.isfinite(y) or x <= 0 or y <= 0:
            reasons.append("invalid " + key)
        else:
            changes[key] = y / x - 1
            if y > x * 1.05:
                reasons.append(key + " regressed more than 5%")
    return {"passed": not reasons, "relative_changes": changes, "errors": reasons}


def compare(reference, candidate, numbers_only=False):
    reference, candidate = Path(reference), Path(candidate)
    report = {"scope": "numbers_only" if numbers_only else "full", "checks": {}, "passed": False}
    try:
        report["checks"]["numbers"] = compare_numbers(reference / "baseline_tests.json", candidate / "baseline_tests.json")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        report["checks"]["numbers"] = {"passed": False, "error": str(exc)}
    if not numbers_only:
        try:
            a = read_json(reference / "source_overrides.json")
            b = read_json(candidate / "source_overrides.json")
            if a != b or not a.get("source_commit") or "owner_accepted_replacements" not in a:
                raise ValueError("source override declarations differ or are missing")
            for replacement in a["owner_accepted_replacements"]:
                for key in ("path", "repository_git_blob", "replacement_git_blob", "replacement_bytes", "authorization_utc", "scope"):
                    if not replacement.get(key):
                        raise ValueError("incomplete accepted source replacement: " + key)
            report["checks"]["source_overrides"] = {"passed": True}
        except (OSError, ValueError, TypeError, KeyError) as exc:
            report["checks"]["source_overrides"] = {"passed": False, "error": str(exc)}
        try:
            a, b = read_json(reference / "screenshots.json"), read_json(candidate / "screenshots.json")
            if a != b or len(a.get("shots", [])) != 18:
                raise ValueError("18 matching screenshot entries are required")
            songs = {}
            image_checks = {}
            for shot in a["shots"]:
                song = shot["song"]
                songs[song] = songs.get(song, 0) + 1
                path = Path(shot["file"])
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("screenshot paths must be relative and contained")
                if str(path) in image_checks:
                    raise ValueError("duplicate screenshot path")
                image_checks[str(path)] = image_difference(reference / path, candidate / path)
            if songs != {"fixture_dense": 6, "_demo": 6, "demo": 6}:
                raise ValueError("exactly six screenshots for each required chart are required")
            report["checks"]["screenshots"] = {"passed": all(c["passed"] for c in image_checks.values()), "images": image_checks}
        except (OSError, ValueError, TypeError, KeyError) as exc:
            report["checks"]["screenshots"] = {"passed": False, "error": str(exc)}
        try:
            report["checks"]["performance"] = compare_performance(reference / "performance.json", candidate / "performance.json")
        except (OSError, ValueError, TypeError, KeyError) as exc:
            report["checks"]["performance"] = {"passed": False, "error": str(exc)}
    report["passed"] = all(check["passed"] for check in report["checks"].values())
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--numbers-only", action="store_true", help="partial evidence only; never claims P0 passed")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = compare(args.reference, args.candidate, args.numbers_only)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n")
    print(rendered)
    print(("数字一致（部分验收）" if args.numbers_only else "全部一致") if report["passed"] else "验收未通过")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
