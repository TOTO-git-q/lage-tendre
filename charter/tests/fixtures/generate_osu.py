"""Original synthetic mania fixtures. Python is for tests only; runtime uses GDScript."""
from pathlib import Path
import io
import math
import struct
import wave
import zipfile
import zlib


def generate(root=None):
    root = Path(root or Path(__file__).parent / "generated")
    root.mkdir(parents=True, exist_ok=True)
    samples = b"".join(struct.pack("<h", int(1800 * math.sin(i * math.tau * 440 / 8000))) for i in range(8000 * 8))
    with wave.open(str(root / "tone.wav"), "wb") as f:
        f.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
        f.writeframes(samples)
    # Original solid blue 16x16 PNG, no imaging dependency.
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",16,16,8,2,0,0,0))
    png += chunk(b"IDAT", zlib.compress((b"\0"+bytes([50,100,200])*16)*16)) + chunk(b"IEND", b"")
    (root / "bg.png").write_bytes(png)
    for keys in (4, 7):
        objects = []
        for i in range(24):
            col = i % keys
            t = 1000 + i * 250
            x = int((col + .5) * 512 / keys)
            objects.append(f"{x},192,{t},{128 if i % 7 == 0 else 1},0," + (f"{t+200}:0:0:0:0:" if i % 7 == 0 else "0:0:0:0:"))
        # A two-key chord and a sub-80ms hold (becomes a tap).
        objects += ["1,192,7000,1,0,0:0:0:0:", "511,192,7000,128,0,7050:0:0:0:0:"]
        text = f'''osu file format v14

[General]
AudioFilename: tone.wav
PreviewTime: 1000
Mode: 3
[Metadata]
Title: Original Agent IO Fixture
TitleUnicode: Original Agent IO Fixture
Artist: Charter Tests
ArtistUnicode: Charter Tests
Creator: Original Generator
Version: {keys}K
Source: synthetic original fixture
Tags: original test
[Difficulty]
CircleSize: {keys}
OverallDifficulty: 5
[Events]
0,0,"bg.png",0,0
[TimingPoints]
0,500,4,2,0,100,1,0
2000,-50,4,2,0,100,0,0
4000,400,3,2,0,100,1,0
[HitObjects]
''' + "\n".join(objects) + "\n"
        (root / f"original-{keys}k.osu").write_text(text, encoding="utf-8")
    with zipfile.ZipFile(root / "original.osz", "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("original-4k.osu", "original-7k.osu", "tone.wav", "bg.png"):
            z.write(root / name, name)
    with zipfile.ZipFile(root / "traversal.osz", "w") as z:
        z.writestr("../escape.osu", "bad")
    with zipfile.ZipFile(root / "bomb.osz", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("bomb.txt", bytes(3 * 1024 * 1024))
    (root / "text.txt").write_text("Original UTF-8 attachment.\n" * 4000, encoding="utf-8")
    return root


if __name__ == "__main__":
    print(generate())
