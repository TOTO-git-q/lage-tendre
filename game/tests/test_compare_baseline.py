#!/usr/bin/env python3
"""Exercise the comparator at and beyond each acceptance boundary."""
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from PIL import Image
import compare_baseline as compare


class CompareBaselineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="lage-compare-test-")
        self.addCleanup(self.directory.cleanup)
        self.a = Path(self.directory.name) / "a"
        self.b = Path(self.directory.name) / "b"
        self.a.mkdir(); self.b.mkdir()

    def write(self, folder, name, value):
        (folder / name).write_text(json.dumps(value))
        return folder / name

    def numbers(self):
        return {"numeric_capture_complete": True, "godot": "4.7.2", "tests": {
            name: {"script": name.split("__")[0], "args": [], "exit_code": 0,
                   "lines": ["fixture result 42"], "errors": []} for name in compare.EXPECTED_TESTS}}

    def performance(self, value=100.0):
        return {"duration_seconds": 30, "wall_duration_seconds": 30, "frames": 1800,
                "scope": "GameCore.update+Renderer.frame+Renderer.draw_callbacks",
                "song": "fixture_dense", "fps": 60, "seed": 20261017, "resolution": [1600, 900],
                "godot": "4.7.2", "rendering_method": "gl_compatibility", "rendering_device": "test fixture",
                "draw_callbacks": 12600, "mean_usec": value, "p95_usec": value,
                "samples_usec": [value] * 1800, "update_samples_usec": [value] * 1800,
                "frame_samples_usec": [0] * 1800, "draw_samples_usec": [0] * 1800}

    def test_numeric_exact_and_difference(self):
        a = self.numbers(); b = copy.deepcopy(a)
        pa = self.write(self.a, "numbers.json", a); pb = self.write(self.b, "numbers.json", b)
        self.assertTrue(compare.compare_numbers(pa, pb)["passed"])
        b["tests"]["human_keys_test"]["lines"] = ["fixture result 41"]
        self.write(self.b, "numbers.json", b)
        self.assertFalse(compare.compare_numbers(pa, pb)["passed"])

    def test_numeric_missing_and_same_failure_are_rejected(self):
        for mutation in ("missing", "incomplete", "error", "exit", "reported_failure"):
            data = self.numbers()
            if mutation == "missing": data["tests"].pop("snap_test")
            if mutation == "incomplete": data["numeric_capture_complete"] = False
            if mutation == "error": data["tests"]["snap_test"]["errors"] = ["ERROR: fixture"]
            if mutation == "exit": data["tests"]["snap_test"]["exit_code"] = 1
            if mutation == "reported_failure": data["tests"]["snap_test"]["lines"] = ["SNAP RULES: FAIL"]
            pa = self.write(self.a, "numbers.json", data); pb = self.write(self.b, "numbers.json", data)
            with self.subTest(mutation=mutation):
                self.assertFalse(compare.compare_numbers(pa, pb)["passed"])

    def test_pixel_boundaries(self):
        pa, pb = self.a / "image.png", self.b / "image.png"
        image = Image.new("RGBA", (1600, 900), (0, 0, 0, 255)); image.save(pa)
        for count, channel, expected in ((0, 0, True), (1440, 2, True), (1441, 2, False), (1, 3, False)):
            candidate = image.copy()
            for index in range(count): candidate.putpixel((index % 1600, index // 1600), (channel, 0, 0, 255))
            candidate.save(pb)
            result = compare.image_difference(pa, pb)
            with self.subTest(count=count, channel=channel):
                self.assertEqual(result["passed"], expected)
                self.assertEqual(result["different_pixels"], count)
        Image.new("RGB", (800, 450)).save(pb)
        self.assertFalse(compare.image_difference(pa, pb)["passed"])

    def test_performance_five_percent_boundary(self):
        pa = self.write(self.a, "performance.json", self.performance())
        for value, expected in ((100, True), (105, True), (105.0001, False)):
            pb = self.write(self.b, "performance.json", self.performance(value))
            with self.subTest(value=value):
                self.assertEqual(compare.compare_performance(pa, pb)["passed"], expected)

    def test_performance_missing_evidence(self):
        pa = self.write(self.a, "performance.json", self.performance())
        for field, value in (("duration_seconds", 29.99), ("wall_duration_seconds", 29.99),
                             ("frames", 1799), ("samples_usec", []), ("draw_callbacks", 0),
                             ("draw_samples_usec", []), ("rendering_device", "different"),
                             ("mean_usec", float("nan")), ("p95_usec", 100.1)):
            data = self.performance(); data[field] = value
            pb = self.write(self.b, "performance.json", data)
            with self.subTest(field=field):
                self.assertFalse(compare.compare_performance(pa, pb)["passed"])

    def test_full_evidence_and_source_override(self):
        self.write(self.a, "baseline_tests.json", self.numbers())
        self.write(self.a, "performance.json", self.performance())
        overrides = {"source_commit": "fixture", "owner_accepted_replacements": [{
            "path": "assets/fixture.png", "repository_git_blob": "original", "replacement_git_blob": "accepted",
            "replacement_bytes": 100, "authorization_utc": "2026-10-16T15:03:32Z", "scope": "fixture"}]}
        self.write(self.a, "source_overrides.json", overrides)
        shots = []
        for song in ("fixture_dense", "_demo", "demo"):
            for index in range(6):
                name = f"{song}-{index}.png"
                Image.new("RGBA", (1600, 900), (0, 0, 0, 255)).save(self.a / name)
                shots.append({"song": song, "file": name})
        self.write(self.a, "screenshots.json", {"shots": shots})
        shutil.copytree(self.a, self.b, dirs_exist_ok=True)
        self.assertTrue(compare.compare(self.a, self.b)["passed"])
        overrides["owner_accepted_replacements"][0]["replacement_git_blob"] = "changed"
        self.write(self.b, "source_overrides.json", overrides)
        self.assertFalse(compare.compare(self.a, self.b)["passed"])
        (self.b / "source_overrides.json").unlink()
        self.assertFalse(compare.compare(self.a, self.b)["passed"])
        shutil.copy2(self.a / "source_overrides.json", self.b / "source_overrides.json")
        (self.b / shots[0]["file"]).unlink()
        self.assertFalse(compare.compare(self.a, self.b)["passed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
