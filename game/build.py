"""Compatibility build entry point; see tools/build_release.py."""
from pathlib import Path
import subprocess
import sys

if __name__ == "__main__":
    raise SystemExit(subprocess.call([sys.executable, str(Path(__file__).resolve().parents[1] / "tools/build_release.py"), *sys.argv[1:]]))
