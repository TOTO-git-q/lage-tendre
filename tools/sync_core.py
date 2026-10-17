"""Copy authoritative game runtime into charter; --check never writes (Python stdlib only)."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game"
TARGET = ROOT / "charter"
FOLDERS = ("scripts", "plugins", "assets")
FILES = ("icon.png", "icon.png.import", "PLUGINS_API.md", "PLUGINS_API.zh-CN.md", "PLUGINS_SPEC.md")
MANIFEST = TARGET / ".core-sync.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    paths = [p for folder in FOLDERS for p in (root / folder).rglob("*") if p.is_file()]
    paths += [root / name for name in FILES if (root / name).is_file()]
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted(paths)}


def sync(check=False):
    expected = inventory(SOURCE)
    if not expected or any(not (SOURCE / name).is_dir() for name in FOLDERS):
        raise RuntimeError("Missing authoritative game runtime")
    reference = ROOT / "docs/CHART_SYNTAX.md"
    reference_target = TARGET / "chart_syntax_reference.md"
    reference_ok = reference_target.exists() and digest(reference_target) == digest(reference)
    actual = inventory(TARGET)
    document = {"schema": 1, "source": "../game", "files": expected}
    saved = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else None
    changed = sorted(k for k, v in expected.items() if actual.get(k) != v)
    stale = sorted(set(actual) - set(expected))
    if check:
        if changed or stale or saved != document or not reference_ok:
            print(f"Core sync OUT OF DATE: {len(changed)} missing/changed, {len(stale)} stale; run python tools/sync_core.py")
            return 1
        print(f"Core sync OK: {len(expected)} SHA-256 verified files")
        return 0
    if not reference_ok:
        shutil.copy2(reference, reference_target)
    # Ownership is limited to the explicitly listed runtime paths; no editor files are touched.
    for key in stale:
        (TARGET / key).unlink()
    for key in changed:
        dst = TARGET / key
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE / key, dst)
    for folder in FOLDERS:
        for p in sorted((TARGET / folder).rglob("*"), reverse=True):
            if p.is_dir() and not any(p.iterdir()):
                p.rmdir()
    MANIFEST.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Core sync: {len(changed)} copied, {len(stale)} stale deleted, {len(expected)} files")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    return sync(parser.parse_args().check)


if __name__ == "__main__":
    raise SystemExit(main())
