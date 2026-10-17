"""Build both independent Windows projects and self-contained ZIPs; no publishing."""
from pathlib import Path
import argparse
import hashlib
import os
import shutil
import subprocess
import zipfile

from sync_core import sync
from godot_path import default_godot

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = default_godot()


def included_song(path):
    parts = path.parts
    if len(parts) >= 2 and parts[0] == "fan-made" and parts[1].startswith(("_", ".")):
        return False
    return not any(p.startswith(".") or p in ("_osz", "fixtures", "test_fixtures", "__pycache__") or ".bak" in p.lower() for p in parts)


def copy_songs(target):
    source = ROOT / "songs"
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        if path.is_file() and included_song(rel):
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)


def engine(godot, project, *args):
    env = os.environ.copy()
    env["APPDATA"] = str(ROOT / "dist/build-user")
    env["LOCALAPPDATA"] = str(ROOT / "dist/build-local")
    Path(env["APPDATA"]).mkdir(parents=True, exist_ok=True)
    Path(env["LOCALAPPDATA"]).mkdir(parents=True, exist_ok=True)
    result = subprocess.run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), *args],
                            capture_output=True, env=env)
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    log = ROOT / "dist/build-logs" / (project.name + ("-import.log" if "--import" in args else "-export.log"))
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(output, encoding="utf-8")
    checked = output.replace("ERROR: Failed to read the root certificate store.", "")
    if result.returncode or "SCRIPT ERROR" in checked or "ERROR:" in checked:
        raise RuntimeError(f"Godot failed: {log}\n{output[-4000:]}")


def clean_stage(path):
    # Only these two named generated package directories are owned by this builder.
    if path.parent.resolve() != (ROOT / "dist").resolve() or path.name not in ("LAgeTendre", "LAgeTendreCharter"):
        raise RuntimeError(f"Refusing unexpected build path: {path}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    a = parser.parse_args()
    sync()
    if os.name == "nt":
        # Keep editor settings in the workspace while reusing the already installed templates.
        installed = Path(os.environ["APPDATA"]) / "Godot/export_templates/4.7.2.stable"
        cached = ROOT / "dist/build-user/Godot/export_templates/4.7.2.stable"
        cached.mkdir(parents=True, exist_ok=True)
        for name in ("windows_debug_x86_64.exe", "windows_release_x86_64.exe", "version.txt"):
            src = installed / name
            if src.exists(): shutil.copy2(src, cached / name)
    for name in ("game", "charter"):
        engine(a.godot, ROOT / name, "--import")
    game = ROOT / "dist/LAgeTendre"
    charter = ROOT / "dist/LAgeTendreCharter"
    clean_stage(game)
    clean_stage(charter)
    engine(a.godot, ROOT / "game", "--export-release", "Windows Desktop", str(game / "LAgeTendre.exe"))
    engine(a.godot, ROOT / "charter", "--export-release", "Charter", str(charter / "LAgeTendreCharter.exe"))
    for path in (game / "LAgeTendre.exe", charter / "LAgeTendreCharter.exe"):
        if not path.is_file() or path.stat().st_size < 1_000_000:
            raise RuntimeError(f"Missing export: {path}")
    csc = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
    subprocess.run([str(csc), "-nologo", "-target:winexe", "-optimize+", "-out:" + str(game / "KeyGuard.exe"),
                    str(ROOT / "game/keyguard/KeyGuard.cs")], check=True)
    shutil.copy2(game / "LAgeTendre.exe", charter / "LAgeTendre.exe")
    shutil.copy2(game / "KeyGuard.exe", charter / "KeyGuard.exe")
    shutil.copy2(ROOT / "charter/README.md", charter / "README.md")
    for stage in (game, charter):
        copy_songs(stage / "songs")
        shutil.copy2(ROOT / "LICENSE", stage / "LICENSE")
    notices = ROOT / "dist/GODOT_THIRD_PARTY_NOTICES.txt"
    engine(a.godot, ROOT / "game", "-s", "res://tests/export_licenses.gd", "--", str(notices))
    if not notices.is_file() or notices.stat().st_size < 1000:
        raise RuntimeError("Engine license extraction failed")
    for stage in (game, charter):
        shutil.copy2(notices, stage / notices.name)
    release = ROOT / "release"
    release.mkdir(exist_ok=True)
    for stage in (game, charter):
        output = release / (stage.name + "-win64.zip")
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for path in sorted(stage.rglob("*")):
                if path.is_file(): z.write(path, path.relative_to(stage.parent).as_posix())
        with zipfile.ZipFile(output) as z:
            if z.testzip() is not None: raise RuntimeError("Corrupt ZIP: " + str(output))
        print(f"{output}: {output.stat().st_size:,} bytes SHA-256 {hashlib.sha256(output.read_bytes()).hexdigest()}", flush=True)


if __name__ == "__main__":
    main()
