# Agent instructions
Layout: `game/` (game Godot project), `charter/` (chart editor Godot project), `songs/` (shared songs and plugin
demos), `docs/` (chart syntax), `tools/`.
Setup: `bash tools/setup_godot.sh`; tests: `bash tools/run_tests.sh` (or `python tools/run_tests.py` on Windows).
Run `python tools/sync_core.py` before launching or exporting the charter; never edit its ignored copies of game
code inside `charter/` — edit `game/`. Release: `python tools/build_release.py` → `release/*.zip`.
Never change judgement rules or song content unless the task says so. All Godot runs muted, headless/offscreen on
Windows or under xvfb. No network installs or new third-party code. Terminate owned processes by PID only.
Current public preparation task: `PUBLIC_TASK.md`; progress: `PUBLIC_WORKLOG.md`.
