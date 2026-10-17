# Original-content regression baselines

The checked-in numeric and 18-image baselines use the original dense synthetic fixture, the materialized demo chart and the built-in tutorial. No player recording is included: replay_synthetic.json is seeded test input. Synthetic analysis metadata is not measured audio analysis. The built-in tutorial supplies pedal cues; the dense fixture supplies chords, holds, yellow notes and big notes. Focused rule suites separately assert cut windows, slap guard, snap and release gaps.

Set GODOT to an installed Godot 4.7.2 executable. From the repository root:

```text
python game/tests/capture_baseline.py --out dist/candidate --source-commit public-source
python game/tests/capture_render.py --out dist/candidate --mode all
python game/tests/compare_baseline.py game/tests/baselines dist/candidate --report dist/comparison.json
```

On Windows capture uses an offscreen OpenGL window; on Linux run capture_render.py under xvfb. Audio is Dummy. Numeric comparison is exact; image comparison retains the existing pixel tolerance. Full comparison also requires measured 30-second update/frame/draw performance evidence and enforces the existing 5% regression limit. Performance is machine-dependent; use captures from the same host and renderer. `--numbers-only` explicitly reports partial evidence.

For a before/after change, capture both runs on the same machine with the same original content. `source_commit` is a capture label; this exported public checkout has no inherited private history. source_overrides.json declares no asset replacements. The public preparation worklog records pre-edit synthetic rule outputs and preserved implementation hashes.

`python tools/generate_test_fixtures.py` verifies the seeded fixtures without writing; `--write` regenerates them. The dense chart uses a valid neutral zoom tween to preserve its explicit stage state while satisfying editor validation.
