#!/usr/bin/env bash
# Import both projects. Download is opt-in for Linux CI only; local setup stays offline.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools
if [ "${1:-}" = "--download" ]; then
  [ "$(uname -s)" = Linux ] || { echo '--download is Linux CI only' >&2; exit 1; }
  VERSION=4.7.2
  curl --fail --location --retry 3 --output .tools/godot.zip \
    "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip"
  unzip -oq .tools/godot.zip -d .tools
  mv ".tools/Godot_v${VERSION}-stable_linux.x86_64" .tools/godot
  chmod +x .tools/godot
  export GODOT="$PWD/.tools/godot"
fi
if [ -n "${GODOT:-}" ]; then
  G="$GODOT"
elif [ -x .tools/godot ]; then
  G=./.tools/godot
else
  G=$(command -v godot || command -v godot4 || true)
  [ -n "$G" ] || { echo "Install Godot 4.7.2 locally and set GODOT." >&2; exit 1; }
fi
"$G" --version | grep -q '^4\.7\.2\.' || { echo 'Godot 4.7.2 is required' >&2; exit 1; }
"${PYTHON:-python}" tools/sync_core.py
for P in game charter; do
  "$G" --headless --audio-driver Dummy --path "$P" --import
done
"$G" --version
