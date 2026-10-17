"""Temporary work directories with inherited Windows sandbox permissions."""
from pathlib import Path
import shutil
import uuid


class TemporaryWorkspace:
    def __init__(self, prefix="lage-", dir=None):
        parent = Path(dir) if dir else Path(__file__).resolve().parents[1] / "dist"
        parent.mkdir(parents=True, exist_ok=True)
        self.path = parent.resolve() / (prefix + uuid.uuid4().hex)
        self.path.mkdir()
        self.name = str(self.path)

    def __enter__(self):
        return self.name

    def cleanup(self):
        if self.path.exists():
            shutil.rmtree(self.path)

    def __exit__(self, *exc):
        self.cleanup()
