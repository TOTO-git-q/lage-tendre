# L'âge tendre — modular core and song plugins (SPEC, 2026-10-16)

The owner wants the game decoupled into modules, with syntax and visual elements pluggable: a song folder can carry
its own syntax / element plugins (someone's cool idea), they load when that song is played and unload when another
song is played. Implement it in the Godot 4.7.2 project `<repository-relative path>` (scripts in
`scripts/`, ~4.6k lines: `chart_lib.gd` (validate / timelines / light_at), `game_core.gd` (judgement, autoplay),
`renderer.gd` (field drawing), `stage_fx.gd` (camera / fx channels), `main.gd` (menus, play loop, input),
`su.gd` (constants), `kb.gd`, `audio_engine.gd`, `play_log.gd`, `ranks.gd`, `result_view.gd`).
Songs live in `../songs/` (index.json; charts in syntax v3 — read
`../docs/CHART_SYNTAX.md` sections "Chart syntax v2" and "Syntax v3").

## 0. Decisions already made by the owner (do not re-decide)
1. **Two plugin tiers.** Declarative plugins (data + textures + `.gdshader` + restricted formulas evaluated with
   Godot's `Expression` on a fixed input set) are allowed by default. Script plugins (GDScript) can do anything, so a
   song pack's scripts run only after the player trusts that pack once (a dialog on first load; trust stored in
   `user://` keyed by the pack's content hash; untrusted → script parts disabled, declarative parts still load; the
   chart must then say clearly what is missing instead of failing silently).
2. **Plugin ids are bound to the chart.** A chart declares the plugins it needs: `"plugins": [{"id": "...", "version": "..."}]`.
   Scores / best records are keyed by chart + its plugin set (id@version list), so modified rules never mix with
   standard results. A chart without `plugins` uses only built-ins (all existing charts).
3. **Track-centric core.** "The core of this game is the change of the tracks and the notes on them." Judgement: a
   press hits a note if the key's range (padded 1 key each side) overlaps the note's TRACK cross-section at the
   judgement line at that moment; one press = one note; the note's drawn position is cosmetic.
4. **Future syntax approved** (implement it as built-in plugins in this refactor, see §3): tracks as arbitrary closed
   shapes in (time × position) space with custom cubic-bezier curves and independent edges (a star, a heart; the
   cross-section can be several intervals — a press inside any of them counts); per-note motion (default: a note
   falls straight at its landing place; optional motion types are plugins: "horizontal" = slides from another x,
   "follow track" = today's behaviour, kept for old charts); fast/slow lights (per-track fall speed), and scroll
   speed changes (SV).

## 1. Architecture
- **Core** = song clock, lean chart model, plugin registry, judgement pipeline, render pipeline, input. The core knows
  no concrete event type, note kind or drawing.
- **Registries** (one place, documented API version `api: 1`): event types (light/track events and their fields),
  note kinds & flags, judgement rules (ordered stages with a stable contract), note motions, track geometry
  providers (lane form today, shape form new), fx/camera channels (StageFx channels incl. line_y/line_tilt/line_glow),
  render elements (layers with explicit z order: background, tracks, key guides/dividers, holds, notes, judgement
  line, hit effects, HUD), and validators (each plugin validates its own fields; ChartLib.validate becomes the
  aggregate).
- **Built-in plugins**: move every existing feature behind the same API — v3 light events (on/sweep/pulse/off, x/w/a/
  tint/ease), pedal cues, tap/hold/ex/big/grow, hold ticks, CHUNITHM midpoint cut (same-track), chord follow, slap
  guard, yellow catch, snap, track-centric hit, legacy fields loading (jump → sweep etc.), stage fx, renderer layers.
  Folder `plugins/builtin/<id>/` with the same manifest format as song plugins (so the system is dog-fooded).
- **Song plugins**: `songs/<dir>/plugins/<id>/plugin.json` = {id, version, api, tier: declarative|script, title,
  author, description, provides: {events, note_kinds, flags, motions, track_geometry, channels, elements, rules},
  fields: [JSON-schema-like field specs with unit, range, step, enum, default, doc — used by the chart editor's
  inspector and its MCP], assets, entry (script tier only)}. Loaded on song start in dependency order, instantiated
  per play, fully unloaded on exit (no global state left behind — test it by playing song A with a plugin, then song B
  without, and checking B is identical to a clean run).
- **Lean chart**: only fields that differ from defaults are written; plugin defaults come from their schemas.

## 2. Hard requirements: nothing changes for existing charts
Before refactoring, record baselines (store under `tests/baselines/`):
- headless results: `tests/autoplay_test.gd` (every chart in index.json + demo), `tests/one_chart.gd`,
  `tests/home_keys_song.gd`, `tests/fat_finger_test.gd`, `tests/autoplay_double_test.gd`, `tests/hold_rules_test.gd`,
  `tests/extap_test.gd`, `tests/snap_test.gd`, `tests/track_any_key_test.gd`, `tests/track_chord_test.gd`,
  `tests/chord_gap_test.gd`, `tests/human_keys_test.gd` (TOTAL human failures today: 32), `tests/ranks_test.gd`,
  and `<repository-relative path>`
  (the owner's real play replay) — every number must be identical after the refactor;
- render baselines: offscreen screenshots of `fixture_dense`, `_demo` and demo at ~6 chart times each
  (`--path <proj> --position -5000,-5000 -- --mute --autoplay --song=<dir> --from=<T> --shot=<png> --shot-at=3.5`),
  compared pixel-wise (allow only sub-perceptual noise; report the max diff);
- frame time not worse (measure average draw+update time over a 30 s autoplay window before/after).

## 3. New built-in plugins (prove the API; each with a tiny demo chart under `songs/_plugin_demos/<name>/`, a copy
of an existing song's audio is fine, and a headless test)
1. `shape_tracks`: tracks as closed paths (nodes + line / cubic-bezier segments) in (time, x); cross-section at the
   line = union of intervals; judgement via the intervals; rendering on the arched field (tessellate in (x, s) space,
   subdivide edges because the field mapping is non-linear). Must be able to read the chart editor's shape model
   (`charter/track_shape.gd`, `charter/track_adapter.gd`, sidecar `chart.ext.json`) — define the chart serialization
   (`lights` stays for lane tracks; shapes under a new `tracks` key or a `shape` event — choose, document, and write
   a converter from `chart.ext.json`). Demo: a star and a heart carrying notes.
2. `note_motion`: per-note `motion: {type, ...params}`; types `straight` (default), `follow_track` (legacy default
   for charts without plugins — old charts must look identical), `horizontal` (from x0 to the landing x over the
   fall, ease param). Demo with a chord spreading outward.
3. `fall_speed`: per-track fall-speed multiplier and per-chart scroll-speed (SV) events {t, speed, ease, dur}; notes
   still land exactly on time; the judgement is untouched. Demo: a fast and a slow light side by side; an SV slow-down
   section.
4. One declarative-only song plugin example (no script) that adds a visual element (e.g. a shader-driven glow ring
   on big notes) with fields in its schema — proves the declarative tier.
5. One script-tier song plugin example in a demo song pack, to exercise the trust prompt (first load asks; deny →
   declarative only + a clear in-game message; allow → runs; trust remembered by content hash).

## 4. Out of scope now
- The chart editor (`charter/`) integration is a later step: do NOT edit `charter/*` (another agent works there).
  But write `PLUGINS_API.md` (English + Chinese summary) describing exactly how the editor should list a chart's
  plugins, read their field schemas for the inspector, validate, and expose them via MCP.
- Do not change judgement constants or rules; do not change existing charts' files (except adding nothing).

## 5. Working rules
- Godot binary `$env:GODOT`; every run headless or offscreen
  (`--position -5000,-5000`), audio muted; never kill processes by image name (PID only); `.bat/.ps1` ASCII only; no
  network installs; no new third-party code.
- Work in phases, each ending green: P0 baselines → P1 registry + plugin loader + manifest format + built-in plugins
  for existing features (behaviour identical) → P2 song-plugin loading/unloading + trust + score keying →
  P3 shape_tracks → P4 note_motion → P5 fall_speed/SV → P6 declarative + script demo packs → P7 docs.
- Worklog `<repository-relative path>`: after every verified step append what was done,
  how it was verified (numbers), and where you stopped. If it already has entries, continue from the last one.
  End with `PLUGINS DONE` or `PLUGINS PARTIAL` + what remains.
