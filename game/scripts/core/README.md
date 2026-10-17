# API 1 core (P1)

The core owns catalogs and ordered dispatch. Concrete chart syntax, judgement,
staging, rank thresholds and drawing live in `plugins/builtin/`. The five legacy
classes retain their public fields, signals, constants and methods so the game
and the separate chart editor use their original interfaces.

## Built-in packages

- `standard_chart`: original and legacy chart syntax, event validators/compiler/
  samplers, note kinds and flag normalizers, lane cross-sections, pedal cues.
- `standard_stage`: the original stage planner, event compilation and 13 bounded
  camera/effect channels.
- `standard_rules`: the original judgement state machine, every ordered press/
  update/reset/catch/hold/pedal/release rule, scoring and rank thresholds.
- `standard_render`: the original geometry and resources, note planning, legacy
  motion, 14 render elements in seven draw phases plus background/grain/vignette.

Each package has the same `plugin.json` shape and `install(registry, manifest,
folder)` entry used by external script plugins. There is no built-in-only
registration shortcut. Dependencies use exact `major.minor.patch`, `^` compatible
ranges or `*`; dependency sorting is stable and rejects missing, duplicate,
cyclic and incompatible packages. Registry loading is transactional.

## Session and callback contracts

`PluginRegistry.builtins()` is the process's immutable-by-convention base. Use
`fork_scope()` before adding or replacing providers. Never register song state in
the base. Services are factories: every GameCore/Renderer/StageFx owns a fresh
runtime. Catalog entries are provider metadata and callables, not game state.
Call `dispose()` only after the session releases its runtimes and callbacks.
Trusted script code is not sandboxed; registry rollback cannot undo arbitrary
script side effects. P2 adds the actual song lifecycle/trust UI. P1's loader
already refuses to load script resources without the explicit trusted flag;
declarative entries in P1 are catalog descriptors, not executable formulas yet.

| Catalog | Provider contract |
| --- | --- |
| `events` | Light `validate(context)`, `compile(context)`, `sample(segment,t)`; lifecycle `opens/closes`, `tail`, and pedal `pedal/cue_duration`. Stage events use names `fx.<kind>` and `compile(stage,event)`. |
| `note_kinds` | `holds` plus `render(renderer,note,state,t,fall,p_min,p_quick,p_end)`; optional `normalize(raw,note)` preserves extension fields. |
| `flags` | Ordered `normalize(raw,note)` updates the normalized note. |
| `rules` | `phase`, `order`, `callback(context)`; set `context.stop` to stop that phase. |
| `motions` | `callback(renderer,note,state)` returns the visual track state; never resolves hits. |
| `track_geometry` | `sections(state)` returns `[left,right]` intervals. |
| `channels` | `default`, `min`, `max`; stage evaluation clamps the result. |
| `elements` | Explicit `order`, draw `phase`, blend/repeat settings and `callback(renderer,canvas)`, or one-time `setup(renderer)`. |
| `validators` | Ordered `callback(context)` receives `raw`, normalized `chart`, and session `registry`. |

Light validation contexts contain `raw`, `tag`, `t`, `id`, `type`,
`legacy_jump`, `states`, `chart` and `warnings`. Compilation contexts contain
`event`, `segments`, `previous` and `previous_yellow`. Callbacks may update those
shared containers. All physical judgement uses the geometry provider; visual
motion is a separate catalog. The standard providers reproduce the old values.

Key-press phases share `runtime`, `code`, `ts`, `result`, then `k`, `rec`, `note`,
`slap`, `dt` and `grade`. Their fixed built-in sequence is input → nearest-time
resolution → slap guard → early snap → chord follow → head state → score →
feedback. Update is clock → autoplay → notes → cues → finish. Same-track midpoint
windows and fingering run on reset. `SU` constants are not changed.

`ChartLib.validate(raw, scope)` aggregates validators. Existing one-argument use
still resolves the built-in scope. `build_timelines`, `build_cues` and `light_at`
also accept an optional final scope, leaving legacy calls and return structures
compatible. Session runtimes use their own scope, never a mutable global active
song. `field_schema()` returns a defensive copy with each field's owning plugin.

## Verification

`tests/plugin_registry_test.gd` checks manifests, paths, versions, dependency
order/failures, ownership, field schemas, ordered dispatch, real custom events,
note kinds/flags, geometry-driven hits, channels, disabled scripts, trusted
script installation, atomic failure and scope isolation. The P0 comparison is
separate and mandatory: all 18 numeric checks, 18 images and 30-second real
update/draw timings. Baselines are never regenerated for a refactor.
