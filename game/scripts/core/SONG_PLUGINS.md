# Song plugins: P2 integration contract

`SongPluginSession.prepare(folder, raw, chart_id)` performs data/file inspection
only. Its report contains `errors`, `notices`, `script_ids`, `content_hash`,
`requires_trust`, `identity`, `score_key`, and `disabled`. It never loads an
untrusted Script, including a script with `_static_init` or a static initializer.
Missing/incompatible/cyclic requirements are errors. Only required local
manifests and their dependency closure are resolved. A chart without requirements
uses the four standard packages and never scans/hashes its song folder.

`remember_trust(bool)` checks that the prepared pack hash is still current, then
records that exact decision in `user://plugin_trust.json`. An explicit choice can
recover an unreadable trust file only after backing up its original bytes.
`open()` rereads the decision and checks the bytes again. Unknown script trust
blocks; denial disables scripts and their dependents, leaves independent
declarative packages active, and produces persistent named notices.

The content SHA-256 uses sorted, length-framed relative names and every file's
bytes, including media and hidden files. Symlinks and unsafe manifest paths are
rejected. Approved script sessions copy the pack to a unique session-local path
and verify the copy against that same hash. Godot 4.7.2 can reuse a stale
GDScript `preload()` dependency even with `CACHE_MODE_IGNORE_DEEP`; fresh verified
paths prevent this. Relative pack preloads preserve their directory layout.
Absolute/dynamically constructed external loads are outside this cooperative
mechanism: trusted scripts are unrestricted, not sandboxed. Snapshots are outside
the original pack and deleted on close without following links, including links
in ancestor directories. Full-pack hashing reads media too; an approved script
session temporarily needs disk space for a complete second copy of the pack.
Close removes that session copy; only empty hash grouping directories may remain.

After a successful open, use `session.registry`, `session.chart_data`,
`session.identity` and `session.score_key`. Actual enabled ids/versions, including
their required closure, define identity. The baseline identity is always the four
`standard_*` packages. Future optional built-ins require explicit activation.
`PluginRegistry.standard()` is an independent cached standard catalog, so optional
catalog replacements cannot erase originals. Legacy facade defaults use it.

Release the song's GameCore, Renderer and StageFx before `close()`. Scripts may
call `registry.own(object)`, `registry.connect_owned(signal, callback, flags)` and
`registry.on_close(callback)` during installation. Teardown callbacks receive the
scope and run in reverse order. A script's optional static `teardown(registry)` is
automatically included. Owned non-RefCounted objects are freed, owned connections
are disconnected and owned resources/catalog callbacks are released. Authors
remain responsible for static/global references and arbitrary external side
effects. Use `@static_unload` and cooperative teardown. Failed installations also
run this cleanup. Neither standard nor available built-in catalogs are disposed.

`runtime_notices()` exposes persistent disable/default notices and bounded,
deduplicated formula errors. Poll only for active plugin songs; failed formula
outputs are discarded rather than applied to physics or drawing.

## Supported declarative definitions

The manifest has a `definitions` object keyed first by category, then by each
id in `provides`. Missing, extra or unsupported definitions are errors.

- `flags`: `{ "field": "ring", "order": 0 }`, with a complete corresponding
  `notes[].ring` field schema. Nested object fields are supported. This normalizes
  extension data only; reserved judgement/state fields cannot be overwritten.
  Invalid explicit chart values are reported before play rather than silently
  replaced. Missing fields use the declared default.
- `channels`: `{ "default": 0.25, "min": 0, "max": 1 }`. Actual StageFx channels
  use these finite limits for tweens/impulses.
- `motions`: `{ "x": "x + 0.2 * (1 - progress)", "w": "w", "alpha": "alpha" }`.
  Each output is optional but at least one is required. An optional numeric
  `field` supplies `value` from a corresponding field schema. Visual x/w/alpha
  are clamped to [-2,3]/[0,4]/[0,1]. This never changes hit geometry. To select a
  motion, preserve `notes[].motion` using an explicit object-schema flag whose
  field is `motion`, then write `motion: {type: "your_motion"}`. A scope-local
  dispatcher is installed only if custom motions exist; legacy hot paths stay
  unchanged.
- `elements`: `{ "kind": "glow_ring", "field": "ring", "radius": "value",
  "opacity": "alpha", "color": [1,1,1,1], "width": 2, "order": 41 }`. A numeric
  `notes[].ring` schema is required. Radius is in key widths, clamped to [0,4];
  opacity is [0,1], width is (0,32] logical pixels. Rings use actual note geometry
  and the judgement-line layer transform. Optional `texture` and `shader` name
  assets explicitly listed in the manifest. Each element has its own layer.

PNG/JPEG/WebP textures load through Image, never scripted resource remaps.
Canvas-item `.gdshader` source is read directly; preprocessor directives/includes
and other shader types are rejected. JSON assets must parse. SVG, `.tres`, `.res`,
script assets and unlisted resources are not supported by this declarative tier.
Events, note kinds, geometry, judgement rules and validators require scripts in
P2; unsupported declarative categories fail clearly.

Formula inputs are finite scalar `t`, `note_t`, `progress`, `x`, `w`, `alpha`,
`u`, `duration`, `value`, plus immutable `pi`/`tau`. Allowed syntax is numeric
literals, parentheses, commas and + - * / %. Allowed functions are `abs`, `sin`,
`cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `sqrt`, `pow`, `exp`, `log`, `floor`,
`ceil`, `round`, `sign`, `fmod`, `posmod`, `clamp`, `min`, `max`, `lerp`,
`inverse_lerp`, `smoothstep`, `deg_to_rad`, `rad_to_deg`. Lexical validation happens
before Expression parsing; strings, objects, member/index access, unknown names,
resource/I/O calls, excessive input and nonfinite inputs/results are rejected.

## Compact charts and records

`ChartCodec.compact(raw, schemas)` returns a defensive copy with only explicitly
default-equal fields removed. Unknown/nondefault values and array positions are
preserved. `save_file(path, raw, schemas)` writes atomically and reserves
`defaults_schema: 1` plus `defaults_omitted`, a map from field paths to the exact
array-index tuples of removed fields. `expand` restores only those omissions.
Originally absent contextual fields are never blanket-filled: a sweep's absent
opacity, tint or ease retains its old semantics. `session.chart_data` expands
this marked form before real gameplay. Disabled plugin schemas stay unavailable
and produce a notice. Saving a previously compacted chart with any unavailable
schema or unresolved omission refuses before touching the destination, preserving
its original bytes and omitted-value metadata. Unmarked legacy charts are unchanged.

`PluginScores.key_for(chart_id, identity)` uses unambiguous canonical JSON with
sorted unique id@version values. `standard_identity()` returns the four baseline
versions. Instance API: `load_file(path="user://best.json")`,
`get_record(chart_id, identity)`, `get_by_key(key)`,
`update_best(chart_id, identity, stats)` returning `{new,prev}`, and `save_file()`.
Load/save results have `ok` and `errors`; load also has `migrated` and, when
applicable, `backup`. Public `records` retains every value. Schema 2 is
`{schema:2, records:{...}}`; unknown schema-2 metadata is preserved. Legacy keys
migrate to standard identities only after an exact-byte backup is verified.
Unknown record fields survive updates, and previous FC is retained. Corrupt or
unsupported score files are never overwritten.

## Verified tests and known initial failures

`tests/song_plugin_session_test.gd` runs all generated fixtures under isolated
`user://`. Its first attempts exposed actual issues:
missing router ownership, an unsafe schema comparison, and stale GDScript
preload caching (`value=one` while the refreshed entry marker was `two`).
These were fixed, not suppressed. The final verified runs have 236 checks,
zero failures and zero engine/script errors. P1's upgraded actual declarative
fixture remains 134 checks, zero failures. Main/UI/render/performance regression
and phase acceptance remain the integration owner's separate gates.
