"""Reproduce original synthetic charts, metadata and seeded imperfect input."""
from pathlib import Path
import argparse
import json
import random

ROOT = Path(__file__).resolve().parents[1]


def fixtures():
    notes = []
    for i in range(400):
        for hand in ([0, 1] if i % 4 == 0 else [i % 2]):
            note = {"t": 3 + i * .25, "light": hand,
                    "u": .5625 if hand == 0 else .4375, "k": 2 if hand == 0 else 8,
                    "kind": "tap", "dur": 0}
            if i % 16 == 0:
                note.update(kind="hold", dur=.375)
            elif i % 11 == 0:
                note["ex"] = True
            if i % 13 == 0:
                note["big"] = True
            notes.append(note)
    chart = {"title": "Synthetic Two Hands", "audio": "../../../../songs/_demo/audio.wav",
             "bpm": 120, "offset": 0, "timing": [{"t": 0, "beat": .5, "meter": 4}], "meta": {},
             "lights": [{"t": 0, "id": hand, "type": "on", "x": x / 15, "w": 4 / 15,
                         "a": .65, "auto": True, "tint": hand + 2}
                        for hand, x in [(0, 3.75), (1, 11.25)]], "notes": notes,
             # An explicit neutral effect keeps automatic staging disabled.
             "fx": [{"t": 0, "type": "tween", "ch": "zoom", "to": 1.0, "dur": .01}]}
    analysis = {"provenance": {"source": "Synthetic test metadata; not measured audio analysis"},
                "bars": [{"bar": i, "energy": .5} for i in range(53)]}
    rng = random.Random(20261017)
    replay = {"provenance": "Seeded synthetic test input, not a player recording", "seed": 20261017,
              "notes": [{"t": n["t"], "dur": n["dur"], "key": "KeyD" if n["k"] == 2 else "KeyL",
                         "hitDt": None if rng.random() < .06 else round(rng.gauss(0, .065), 6),
                         "state": "done"} for n in notes],
              "strays": [{"ts": round(rng.uniform(2, 103), 6),
                          "key": rng.choice(["KeyS", "KeyK", "KeyF", "KeyJ"])} for _ in range(160)],
              "cues": []}
    return {"dense/chart.json": chart, "dense/analysis.json": analysis, "replay_synthetic.json": replay}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate the three owned fixture files")
    args = parser.parse_args()
    base = ROOT / "game/tests/fixtures"
    for name, data in fixtures().items():
        path = base / name
        if args.write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        elif json.loads(path.read_text(encoding="utf-8")) != data:
            raise SystemExit("Fixture differs: " + name)
        print("VERIFIED", name)


if __name__ == "__main__":
    main()
