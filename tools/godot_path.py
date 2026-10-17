"""Locate an already installed engine; never download software."""
from pathlib import Path
import os
import shutil

ROOT = Path(__file__).resolve().parents[1]


def default_godot():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    for name in ("godot.exe", "godot"):
        local = ROOT / ".tools" / name
        if local.is_file():
            return str(local)
    return shutil.which("godot") or shutil.which("godot4") or "godot"
