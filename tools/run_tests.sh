#!/usr/bin/env bash
# Run both independent projects; all Godot invocations are muted.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--canonical" ]; then
  # Preserve the 17-invocation numeric capture protocol and its GODOT recording shim.
  G=${GODOT:-./.tools/godot}
  P=game
  OUT=$P/tests/out; mkdir -p "$OUT"; : > "$OUT/results.txt"
  run() { local name="$1"; shift; echo "== $name" | tee -a "$OUT/results.txt"
    "$G" --headless --audio-driver Dummy --path "$P" -s "res://tests/$name.gd" -- "$@" 2>&1 \
      | grep -E "autoplay:|home-key|fat-finger|RULES|TRACK|CHORD GAP|PASS|FAIL|TOTAL|bad charts|^OK |^BAD |^replay|SCRIPT ERROR" | tee -a "$OUT/results.txt"; }
  run autoplay_test
  for s in fixture_dense _demo; do run one_chart "$s"; run home_keys_song "$s"; run fat_finger_test "$s"; done
  for t in autoplay_double_test hold_rules_test extap_test snap_test track_any_key_test track_chord_test chord_gap_test ranks_test human_keys_test; do run "$t"; done
  run replay_log "$PWD/$P/tests/fixtures/replay_synthetic.json" fixture_dense
  echo "results: $OUT/results.txt"
  exit 0
fi
exec "${PYTHON:-python}" tools/run_tests.py "$@"
