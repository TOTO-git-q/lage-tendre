"""Original generated good/bad fan-chart fixtures. Stdlib only; engine tests use installed Godot."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import unittest

from workspace_temp import TemporaryWorkspace
import validate_fan_chart as validator

ROOT = validator.ROOT


def make_sample(songs_root, slug="original-tone", title="Original synthetic silence"):
    folder = songs_root / "fan-made" / slug
    shutil.copytree(ROOT / "songs/fan-made/_template", folder)
    # Original MPEG-1 Layer III zero-data frames, 128 kbit/s at 44100 Hz.
    # No sampled/music content and no external encoder or fixture dependency.
    (folder / "audio.mp3").write_bytes((b"\xff\xfb\x90\x00" + bytes(413)) * 200)
    info = validator.read_json(folder / "info.json")
    info.update(title=title, artist="Generated fixture", audio="audio.mp3", chart_author="Fixture generator",
                audio_license={"id": "CC0-1.0", "url": "https://creativecommons.org/publicdomain/zero/1.0/", "evidence": "https://github.com/TOTO-git-q/lage-tendre/blob/fan-made/tools/test_validate_fan_chart.py"})
    (folder / "info.json").write_text(json.dumps(info), encoding="utf-8")
    chart = validator.read_json(folder / "chart.json")
    chart.update(title=title, audio="audio.mp3")
    chart["meta"].update(title=title, artist=info["artist"])
    chart["notes"] = [{"t": 1 + i * 0.5, "light": 0, "u": 0.5, "kind": "tap"} for i in range(5)]
    (folder / "chart.json").write_text(json.dumps(chart), encoding="utf-8")
    (folder / "CREDITS.md").write_text("# Generated original fixture\n\nChart: Fixture generator, CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/\n\nAudio: original generated silent MPEG frames, CC0-1.0, https://creativecommons.org/publicdomain/zero/1.0/\nEvidence: tools/test_validate_fan_chart.py in this repository. No conversion or cover.\n", encoding="utf-8")
    return folder


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.workspace = TemporaryWorkspace(prefix="fan-fixtures-")
        self.root = self.workspace.path / "songs"
        self.folder = make_sample(self.root)

    def tearDown(self): self.workspace.cleanup()

    def info(self, **changes):
        info = validator.read_json(self.folder / "info.json"); info.update(changes)
        (self.folder / "info.json").write_text(json.dumps(info), encoding="utf-8")

    def errors(self): return validator.inspect_folder(self.folder)["errors"]

    def test_original_good(self): self.assertEqual(self.errors(), [])

    def test_licence_failures(self):
        for changes in ({"audio_license": {}}, {"audio_license": {"id": "All rights reserved", "url": "x", "evidence": ""}}, {"chart_license": "CC-BY-NC-4.0"}, {"chart_license": []}, {"audio_license": {"id": [], "url": "https://example.org/", "evidence": "https://example.org/"}}):
            with self.subTest(changes=changes):
                make = validator.read_json(self.folder / "info.json")
                self.info(**changes); self.assertTrue(self.errors()); self.info(**make)

    def test_conversion_permission(self):
        self.info(source={"type": "osu!", "url": "https://example.org/chart"})
        self.assertTrue(self.errors())
        self.info(source={"type": "osu!", "url": "https://example.org/chart", "permission_url": "https://example.org/mapper-permission"})
        self.assertEqual(self.errors(), [])

    def test_cover_needs_licence(self):
        (self.folder / "cover.png").write_bytes(b"fixture")
        self.info(cover="cover.png")
        self.assertTrue(any("cover_license" in e for e in self.errors()))

    def test_bad_types_and_paths(self):
        for changes in ({"audio": "../audio.mp3"}, {"cover": "../../cover.png"}, {"preview": True}, {"bpm": "120"}, {"level": 2.5}, {"title": "\n"}, {"plugins": ["wrong"]}):
            before = validator.read_json(self.folder / "info.json")
            with self.subTest(changes=changes): self.info(**changes); self.assertTrue(self.errors())
            self.info(**before)

    def test_disallowed_files_sizes_and_binaries(self):
        for name, content in (("run.exe", b"MZ\0\0"), ("chart.json.bak", b"{}"), ("notes.txt", b"text"), ("cover.jpg", b"MZ\0\0")):
            p = self.folder / name; p.write_bytes(content)
            with self.subTest(name=name): self.assertTrue(self.errors())
            p.unlink()
        with (self.folder / "audio.mp3").open("wb") as f: f.truncate(12 * validator.MIB + 1)
        self.assertTrue(any("exceeds" in e for e in self.errors()))

    def test_utf8_duplicate_nonfinite_json(self):
        for data in (b"\xff", b'{"title":"x","title":"y"}', b'{"t":NaN}', b'{"t":1e999}'):
            with self.subTest(data=data):
                (self.folder / "info.json").write_bytes(data); self.assertTrue(self.errors())

    def test_symlink_rejected_if_available(self):
        p = self.folder / "linked"
        try: p.symlink_to(self.folder / "chart.json")
        except OSError as exc: self.skipTest("Windows symlink permission unavailable: " + str(exc))
        self.assertTrue(any("symlink" in e for e in self.errors()))

    def test_script_flagged_without_execution(self):
        p = self.folder / "plugins/probe"; p.mkdir(parents=True)
        (p / "entry.gd").write_text('extends RefCounted\n', encoding="utf-8")
        result = validator.inspect_folder(self.folder)
        self.assertEqual(result["errors"], [])
        self.assertTrue(any("needs maintainer review" in w for w in result["warnings"]))

    def test_slug_and_packaging(self):
        for slug in ("UPPER", "../escape", "a" * 49, ".hidden", "_reserved"):
            self.assertIsNone(validator.SLUG.fullmatch(slug))
        from build_release import included_song
        self.assertFalse(included_song(Path("fan-made/_template/chart.json")))
        self.assertTrue(included_song(Path("fan-made/my-chart/info.json")))

    def test_changed_selection(self):
        from unittest.mock import patch
        paths = b"songs/fan-made/new/chart.json\0songs/fan-made/old/audio.mp3\0songs/fan-made/_template/info.json\0songs/fan-made/README.md\0"
        with patch.object(validator.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, paths)):
            self.assertEqual(validator.changed_slugs("base...head"), ["new", "old"])


class EngineTests(unittest.TestCase):
    def test_engine_good_and_bad(self):
        with TemporaryWorkspace(prefix="fan-engine-") as work:
            root = Path(work) / "songs"
            good = make_sample(root)
            bad = make_sample(root, "bad-orphan")
            chart = validator.read_json(bad / "chart.json"); chart["notes"][0]["light"] = 999
            (bad / "chart.json").write_text(json.dumps(chart), encoding="utf-8")
            summary = Path(work) / "summary.md"
            self.assertEqual(validator.main([good.name, "--songs-root", str(root), "--summary", str(summary)]), 0)
            self.assertIn("5/5 PERFECT", summary.read_text(encoding="utf-8"))
            self.assertEqual(validator.main([bad.name, "--songs-root", str(root), "--summary", str(summary)]), 1)
            self.assertIn("ChartLib", summary.read_text(encoding="utf-8"))

    def test_plugins_without_script_execution(self):
        with TemporaryWorkspace(prefix="fan-plugins-") as work:
            root = Path(work) / "songs"
            script = make_sample(root, "script-review")
            declarative = make_sample(root, "data-only")
            for folder, tier in ((script, "script"), (declarative, "declarative")):
                plugin = folder / "plugins/probe"; plugin.mkdir(parents=True)
                manifest = {"id": "probe", "version": "1.0.0", "api": 1, "tier": tier, "title": "Original fixture plugin", "author": "Fixture generator", "description": "Original validation fixture", "provides": {}, "fields": [], "assets": [], "entry": "entry.gd" if tier == "script" else None, "requires": []}
                if tier == "declarative": manifest["definitions"] = {}
                (plugin / "plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
                if tier == "script":
                    # A static initializer would leave a marker if anything loaded this Script.
                    marker = (folder / "EXECUTED.txt").as_posix()
                    code = 'extends RefCounted\nstatic var marker = mark()\nstatic func mark():\n\tvar f = FileAccess.open(' + json.dumps(marker) + ', FileAccess.WRITE)\n\tf.store_string("executed")\n\tf.close()\n\treturn true\n'
                    (plugin / "entry.gd").write_text(code, encoding="utf-8")
                chart = validator.read_json(folder / "chart.json")
                chart["plugins"] = [{"id": "probe", "version": "1.0.0"}]
                (folder / "chart.json").write_text(json.dumps(chart), encoding="utf-8")
            summary = Path(work) / "summary.md"
            self.assertEqual(validator.main([script.name, declarative.name, "--songs-root", str(root), "--summary", str(summary)]), 0)
            self.assertIn("needs maintainer review", summary.read_text(encoding="utf-8"))
            self.assertIn("script-tier plugins disabled", summary.read_text(encoding="utf-8"))
            self.assertFalse((script / "EXECUTED.txt").exists())


if __name__ == "__main__": unittest.main()
