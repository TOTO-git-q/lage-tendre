"""Validate fan-chart submissions with stdlib inspection and the real muted Godot runtime."""
from pathlib import Path
import argparse
import json
import math
import os
import re
import stat
import subprocess
import sys
from urllib.parse import urlsplit

from godot_path import default_godot
from workspace_temp import TemporaryWorkspace

ROOT = Path(__file__).resolve().parents[1]
SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,47}\Z")
COMPONENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\Z")
AUDIO_LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "CC-BY-NC-4.0", "CC-BY-NC-SA-4.0", "LicenseRef-Permission"}
CHART_LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "MIT", "0BSD", "Unlicense"}
FIELDS = {"title", "artist", "version", "level", "bpm", "preview", "audio", "cover", "chart_author", "chart_license", "audio_license", "cover_license", "source", "plugins"}
FILES = {"info.json", "chart.json", "CREDITS.md", "audio.mp3", "audio.ogg", "cover.png", "cover.jpg"}
PLUGIN_EXTENSIONS = {".json", ".gd", ".gdshader", ".png", ".jpg", ".webp", ".svg", ".txt", ".md", ".ogg", ".wav"}
MIB = 1024 * 1024


def linked(path):
    s = path.lstat()
    return stat.S_ISLNK(s.st_mode) or bool(getattr(s, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def safe_ancestors(path):
    return all(not linked(p) for p in [path, *path.parents] if p.exists() or p.is_symlink())


def read_json(path):
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj: raise ValueError("duplicate JSON key: " + key)
            obj[key] = value
        return obj
    def invalid(value):
        raise ValueError("non-finite JSON number: " + value)
    def finite_float(value):
        parsed = float(value)
        if not math.isfinite(parsed): raise ValueError("non-finite JSON number")
        return parsed
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique, parse_constant=invalid, parse_float=finite_float)


def text(value):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= 256 and all(ord(c) >= 32 and ord(c) != 127 for c in value)


def number(value, low, high):
    return type(value) in (int, float) and low <= value <= high and math.isfinite(value)


def url(value):
    if not text(value): return False
    try:
        u = urlsplit(value)
        return u.scheme in ("https", "http") and bool(u.hostname) and not u.username and not u.password and not any(c.isspace() for c in value)
    except ValueError:
        return False


def licence(value, field, errors):
    if not isinstance(value, dict):
        errors.append(field + " must be {id, url, evidence}"); return
    if set(value) != {"id", "url", "evidence"}: errors.append(field + " requires exactly id, url, evidence")
    if not isinstance(value.get("id"), str) or value["id"] not in AUDIO_LICENSES: errors.append(field + ".id is not an allowed redistribution licence")
    for key in ("url", "evidence"):
        if not url(value.get(key)): errors.append(field + "." + key + " must be an HTTP(S) URL")


def inspect_folder(folder):
    """Return metadata/errors without importing Godot or executing pack content."""
    errors, warnings = [], []
    result = {"slug": folder.name, "errors": errors, "warnings": warnings}
    if not SLUG.fullmatch(folder.name): errors.append("slug must be 1–48 lowercase a-z0-9, - or _, starting with a letter/digit")
    if not folder.is_dir(): errors.append("missing submission folder"); return result
    if not safe_ancestors(folder): errors.append("symlinks/junctions in the submission ancestry are forbidden"); return result
    count, total = 0, 0
    # Do not follow links, including junctions; validate directory names before descent.
    pending = [(folder, 0)]
    while pending:
        directory, depth = pending.pop()
        for p in sorted(directory.iterdir()):
            count += 1
            rel = p.relative_to(folder)
            name = rel.as_posix()
            if count > 256: errors.append("submission exceeds 256 filesystem entries"); pending.clear(); break
            if linked(p): errors.append("symlink/junction forbidden: " + name); continue
            if not COMPONENT.fullmatch(p.name) or ".bak" in p.name.lower(): errors.append("unsafe filename: " + name); continue
            if p.is_dir():
                if rel.parts[0] != "plugins" or depth >= 5: errors.append("unexpected/deep directory: " + name)
                else: pending.append((p, depth + 1))
                continue
            if not p.is_file(): errors.append("non-regular file: " + name); continue
            is_plugin = len(rel.parts) >= 3 and rel.parts[0] == "plugins"
            if (len(rel.parts) == 1 and name not in FILES) or (len(rel.parts) > 1 and (not is_plugin or p.suffix not in PLUGIN_EXTENSIONS)):
                errors.append("file is not allowed (executables/archives are forbidden): " + name)
            size = p.stat().st_size
            total += size
            limit = 12 * MIB if name in ("audio.mp3", "audio.ogg") else MIB if name.startswith("cover.") else 65536 if name == "info.json" else 8 * MIB if name == "chart.json" else 2 * MIB
            if size > limit: errors.append(f"{name} exceeds {limit} bytes")
            if size == 0: errors.append("empty file: " + name)
            # Catch renamed binaries as well as executable extensions. GDScript is the explicit reviewable exception.
            with p.open("rb") as stream: magic = stream.read(4)
            if magic[:2] == b"MZ" or magic == b"\x7fELF" or magic[:2] == b"#!" or magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
                errors.append("executable content forbidden: " + name)
            if p.suffix == ".json" and size <= limit:
                try: read_json(p)
                except (ValueError, UnicodeError, OSError, RecursionError) as exc: errors.append(f"invalid UTF-8 JSON {name}: {exc}")
            if p.suffix == ".gd": warnings.append(f"script-tier plugin: {name} — needs maintainer review; never executed by this validator")
    if total > 32 * MIB: errors.append("submission exceeds 32 MiB total")
    for name in ("info.json", "chart.json", "CREDITS.md"):
        if not (folder / name).is_file(): errors.append("missing " + name)
    if errors: return result
    try:
        info, chart = read_json(folder / "info.json"), read_json(folder / "chart.json")
        credits = (folder / "CREDITS.md").read_text(encoding="utf-8")
    except (ValueError, UnicodeError, OSError, RecursionError) as exc:
        errors.append(str(exc)); return result
    if not credits.strip(): errors.append("CREDITS.md must contain credits and licence links")
    if not isinstance(info, dict): errors.append("info.json must be an object"); return result
    for key in sorted(set(info) - FIELDS): errors.append("unknown info.json field: " + key)
    for key in ("title", "artist", "version", "chart_author"):
        if not text(info.get(key)): errors.append("missing/invalid " + key)
    if not number(info.get("level"), 0, 100) or info["level"] % 1: errors.append("level must be an integer in 0..100")
    if not number(info.get("bpm"), 20, 400): errors.append("bpm must be in 20..400")
    if not number(info.get("preview"), -1, 86400): errors.append("preview must be a finite second in -1..86400")
    if not isinstance(info.get("chart_license"), str) or info["chart_license"] not in CHART_LICENSES: errors.append("chart_license must be CC-BY-SA-4.0 or an allowed more permissive licence")
    licence(info.get("audio_license"), "audio_license", errors)
    audio = info.get("audio")
    if audio not in ("audio.mp3", "audio.ogg") or not (folder / str(audio)).is_file(): errors.append("audio must name an existing audio.mp3 or audio.ogg")
    for name in ("audio.mp3", "audio.ogg"):
        if (folder / name).exists() and name != audio: errors.append("unreferenced audio: " + name)
    cover = info.get("cover", "")
    if cover:
        if cover not in ("cover.jpg", "cover.png") or not (folder / str(cover)).is_file(): errors.append("cover must name an existing cover.jpg or cover.png")
        licence(info.get("cover_license"), "cover_license", errors)
    elif "cover_license" in info: errors.append("cover_license supplied without a cover")
    for name in ("cover.jpg", "cover.png"):
        if (folder / name).exists() and name != cover: errors.append("unreferenced cover: " + name)
    if "source" in info:
        source = info["source"]
        if not isinstance(source, dict) or set(source) != {"type", "url", "permission_url"}:
            errors.append("source must have type, url, permission_url (original mapper permission)")
        elif not text(source["type"]) or not url(source["url"]) or not url(source["permission_url"]): errors.append("invalid source type/URL or missing conversion permission_url")
    if not isinstance(chart, dict) or not isinstance(chart.get("notes"), list) or not isinstance(chart.get("lights"), list):
        errors.append("chart.json must contain notes and lights arrays"); return result
    if "audio" in chart and chart["audio"] != audio: errors.append("chart.audio must match info.audio (no external paths)")
    if chart.get("bpm") != info.get("bpm"): errors.append("chart.bpm must match info.bpm")
    requirements = chart.get("plugins", [])
    if not isinstance(requirements, list): errors.append("chart.plugins must be an array")
    elif "plugins" in info and info["plugins"] != requirements: errors.append("info.plugins must match chart.plugins")
    result["info"] = info
    return result


def changed_slugs(git_range):
    if git_range.startswith("-") or not git_range.strip(): raise ValueError("invalid git range")
    proc = subprocess.run(["git", "diff", "--name-only", "-z", git_range, "--", "songs/fan-made/"], cwd=ROOT, capture_output=True, check=True)
    paths = [p.split("/") for p in proc.stdout.decode("utf-8").split("\0") if p]
    return sorted({p[2] for p in paths if len(p) >= 4 and not p[2].startswith(("_", "."))})


def engine_check(folder, godot, workspace, env):
    command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "-s", "res://tests/validate_fan_chart.gd", "--", str(folder)]
    proc = subprocess.run(command, capture_output=True, env=env, timeout=180)
    output = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
    (workspace / (folder.name + ".log")).write_text(output, encoding="utf-8")
    lines = [line.removeprefix("FAN_RESULT ") for line in output.splitlines() if line.startswith("FAN_RESULT ")]
    diagnostics = [line for line in output.splitlines() if "SCRIPT ERROR" in line or (line.startswith("ERROR:") and line != "ERROR: Failed to read the root certificate store.")]
    if proc.returncode or len(lines) != 1 or diagnostics:
        return {"errors": ["Godot validation failed: " + "; ".join(diagnostics[:4])], "warnings": []}
    return json.loads(lines[0])


def markdown(results, removed=()):
    lines = ["# Fan-made chart validation", "", "Automated checks do not verify ownership, the truth of permission evidence, or human playability. Maintainer review is required.", ""]
    for slug in removed: lines += [f"- `{slug}`: removed folder; no remaining chart to validate."]
    if not results: lines += ["No submitted chart folders to validate (templates and hidden folders are excluded).", ""]
    for r in results:
        status = "FAIL" if r["errors"] else "PASS"
        lines += [f"## {r['slug']} — {status}", ""]
        for e in r["errors"]: lines.append("- Error: " + str(e).replace("\n", " ").replace("<", "&lt;"))
        for w in r["warnings"]: lines.append("- Warning: " + str(w).replace("\n", " ").replace("<", "&lt;"))
        if "stats" in r:
            s = r["stats"]
            lines += [f"- Autoplay: {s['PERFECT']}/{s['total']} PERFECT; GREAT {s['GREAT']}, GOOD {s['GOOD']}, MISS {s['MISS']}, CRITICAL timing bonuses {s['CRITICAL']}.",
                      f"- Density: {r['notes']} notes, {r['duration']:.2f} s chart span, {r['nps']:.2f} mean notes/s, {r['peak_nps']} peak notes in any 1 s window."]
            for layout, count in r["human_key_failures"].items(): lines.append(f"- Static natural-home-key failures ({layout}): {count} (informational).")
        lines.append("")
    lines.append(f"Result: {sum(bool(r['errors']) for r in results)} failing folder(s) / {len(results)} checked.")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slugs", nargs="*")
    parser.add_argument("--changed", metavar="GIT_RANGE")
    parser.add_argument("--songs-root", type=Path, default=ROOT / "songs", help="temporary songs root for local tests")
    parser.add_argument("--godot", default=default_godot())
    parser.add_argument("--summary", type=Path, help="also save the Markdown summary")
    args = parser.parse_args(argv)
    if args.changed and args.slugs: parser.error("choose slugs or --changed")
    root = args.songs_root.absolute() / "fan-made"
    removed, results = [], []
    try:
        if not safe_ancestors(root): raise ValueError("fan-made root ancestry contains a symlink/junction")
        slugs = changed_slugs(args.changed) if args.changed else args.slugs or sorted(p.name for p in root.iterdir() if not p.name.startswith(("_", ".")) and (p.is_dir() or p.is_symlink()))
        for slug in dict.fromkeys(slugs):
            if not SLUG.fullmatch(slug):
                results.append({"slug": "invalid-slug", "errors": ["invalid slug argument"], "warnings": []}); continue
            folder = root / slug
            if args.changed and not folder.exists() and not folder.is_symlink(): removed.append(slug); continue
            results.append(inspect_folder(folder))
        pending = [r for r in results if not r["errors"]]
        if pending:
            with TemporaryWorkspace(prefix="fan-validator-") as work:
                workspace = Path(work)
                env = os.environ.copy()
                for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                    env[key] = str(workspace / key); Path(env[key]).mkdir()
                imported = subprocess.run([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--import"], env=env, capture_output=True, timeout=120)
                output = (imported.stdout + imported.stderr).decode("utf-8", errors="replace")
                if imported.returncode or "SCRIPT ERROR" in output: raise ValueError("Godot project import failed: " + output[-2000:])
                for r in pending:
                    checked = engine_check(root / r["slug"], args.godot, workspace, env)
                    r["errors"].extend(checked.pop("errors"))
                    r["warnings"].extend(checked.pop("warnings"))
                    r.update(checked)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        results.append({"slug": "validator", "errors": [str(exc)], "warnings": []})
    summary = markdown(results, removed)
    print(summary)
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(summary, encoding="utf-8")
    return int(any(r["errors"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
