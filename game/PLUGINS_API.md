# L’âge tendre plugin author guide — API 1

[中文](PLUGINS_API.zh-CN.md) · Godot 4.7.2 · GL Compatibility

This guide describes the actual API-1 providers and song-session implementation.
It is an authoring and integration reference, not a claim that a development phase
has passed its release gates. See the repository worklog for verified phase status.
The separate chart editor is not changed by this guide.

## 1. Packages, chart requirements and a working first plugin

The two project directories must remain siblings. A song package is:

```text
songs/<song>/
  chart.json
  audio.wav
  plugins/<plugin-id>/
    plugin.json
    entry.gd                 # script tier only
    ...listed data/assets...
```

A chart activates packages explicitly:

```json
{"plugins":[{"id":"glow_ring","version":"1.0.0"}]}
```

Requirements resolve the available built-ins first, then that song's
`plugins/<id>/plugin.json`, recursively including required dependencies. A folder
alone does not activate a plugin. A chart with no requirements uses only
`standard_chart`, `standard_render`, `standard_rules`, and `standard_stage`.
That legacy path does not scan or hash the song folder. Optional built-ins do not
become active merely because they are present in the application.

Here is a complete data-only manifest. Save it as `plugins/glow_ring/plugin.json`:

```json
{
  "id":"glow_ring", "version":"1.0.0", "api":1, "tier":"declarative",
  "title":"Blue note rings", "author":"Example author",
  "description":"A visual ring; no change to timing, hit geometry or scoring.",
  "provides":{"flags":["ring"],"elements":["glow_ring"]},
  "fields":[{
    "path":"notes[].ring", "type":"number", "unit":"keys",
    "min":0, "max":4, "step":0.25, "default":0,
    "doc":"Radius of the visual ring in local key widths; zero hides it."
  }],
  "assets":[], "entry":null,
  "requires":[{"id":"standard_render","version":"1.0.0"}],
  "definitions":{
    "flags":{"ring":{"field":"ring"}},
    "elements":{"glow_ring":{
      "kind":"glow_ring", "field":"ring", "radius":"value",
      "opacity":"alpha * (0.5 + 0.5 * progress)",
      "color":[0.42,0.78,1,0.85], "width":2, "order":41
    }}
  }
}
```

This complete small chart uses it:

```json
{
  "bpm":120,
  "plugins":[{"id":"glow_ring","version":"1.0.0"}],
  "lights":[{"t":0,"id":0,"type":"on","x":0.5,"w":0.4,"a":0.5,"auto":true}],
  "notes":[{"t":2,"light":0,"u":0.5,"kind":"tap","ring":1}]
}
```

The flag is important: schema metadata alone does not normalize a note field or
create a working renderer. For a fully playable example with the existing demo
audio, inspect `songs/_plugin_demos/glow_ring/`. The parallel `script_trust/`
example adds a separately trusted gold decoration while retaining the rings on
denial. `_plugin_demos/index.json` is the menu supplement; the original song
index and original song files are untouched.
The game appends validated supplement groups after the unchanged original groups;
new groups never merge into an original group. The supplement may be absent.
It is limited to 1 MiB and 512 array entries. Each entry needs nonempty `dir`,
`title`, `artist`, `version`; `set` defaults to title. Text is at most 256
characters, without C0 or DEL controls. `dir` must be exactly a direct child
`_plugin_demos/<name>`. `chart.json`, the declared audio filename (default
`audio.mp3`), and any root-relative cover must exist beneath the songs root,
with no traversal, drive/UNC escape or symlink ancestry. Duplicate directories
are case-insensitive; a group must have consistent title/artist/BPM/length/
cover/preview metadata. Only that new group's difficulties are level-sorted.

Numeric values must be finite, never booleans: BPM `[0.001,1000]`, length
`[0.001,86400]` seconds, preview `[-1,length]` (default -1), level `[0,100]`
(default 1), note count `[0,1000000]` (default 0). Invalid rows are ignored with
up to eight visible menu notices; malformed, oversized or unsafe indexes do
not damage the original list. These are menu metadata limits, not new judgement
rules. Selecting `script_trust` uses the ordinary content-hash trust dialog;
menu enumeration does not execute its script.


## 2. Manifest and version rules

All manifests require `id`, `version`, `api`, `tier`, `title`, `author`,
`description`, `provides`, `fields`, `assets`, and `entry`.

| Field | API-1 meaning |
|---|---|
| `id` | Matches `^[a-z][a-z0-9_.-]*$`; must equal its local plugin folder ID. |
| `version` | Exactly `major.minor.patch`, without suffixes or leading zeroes. |
| `api` | Numeric `1`. Unknown API versions fail before installation. |
| `tier` | `declarative` or `script`. A script entry is a relative `.gd` path; a declarative entry is `null`. |
| title/author/description | Nonempty strings presented to readers/players. |
| `provides` | Object of category → unique provider-ID arrays. Only actual registry category names are accepted. |
| `fields` | Complete field-schema objects; see §7. Metadata does not itself implement a script provider. |
| `assets` | Relative paths to listed data/assets. No absolute paths, schemes, `..`, empty components, backslashes or symlinks. |
| `requires` | Optional array of `{id,version}`. Dependencies are installed first. |
| `definitions` | Required implementation data for every declarative `provides` entry; see §6. |

Requirements accept exact versions, `*`, or `^major.minor.patch`. Caret means
at least the requested version within the same nonzero major; `^0.y.z` stays
within nonzero minor `y`; `^0.0.z` matches exactly. Missing packages, conflicting
version requirements, duplicate chart requirements, duplicate package IDs and
dependency cycles produce errors. The session does not download dependencies.

Provider IDs are scoped to their category, not automatically prefixed by package
ID. Use names unlikely to collide. The loader checks that each declared provider
was really registered by that package, and rejects undeclared registrations.
Successful registry changes commit transactionally. Arbitrary trusted-script
side effects cannot be rolled back transactionally.

Use a new package version when behavior changes. Trust uses a content hash, but
score identity uses `id@version`, not that hash. Replacing bytes without bumping
the version asks for trust again but does not create a new score identity.

## 3. Trust, loading, unloading and identity

Use `SongPluginSession`; do not call `ResourceLoader.load` on a song's GDScript
to discover its metadata. Even `_static_init()` runs while loading a script.
The following is a host-function excerpt; the host owns the asynchronous dialog
and the normal play loop between creation and teardown.

```gdscript
var session := SongPluginSession.new()
var report := session.prepare(song_folder, raw_chart, chart_id)
if not report.errors.is_empty():
    return                         # show the errors; do not start play
if report.requires_trust:
    return                         # show Allow / Deny / Cancel; wait for a choice
# In the Allow/Deny handler, call remember_trust(true/false), then open().
var opened := session.open()
if not opened.errors.is_empty():
    return
var core := GameCore.new(session.registry)
if not core.load_chart(session.chart_data):
    core = null
    session.close()
    return
var renderer := Renderer.new(session.registry)
# Add renderer to the scene, run the normal game loop, display session notices.
# At exit: disconnect host callbacks, free renderer, release core/stage references.
renderer.free()
renderer = null
core = null
session.close()
```

`prepare(folder:String, raw:Dictionary, chart_id:String) -> Dictionary` performs
data/file inspection. Its report contains `errors`, `notices`, `script_ids`,
`content_hash`, `requires_trust`, anticipated `identity`, `score_key`, and
`disabled`. It does not execute untrusted pack code. When the player chooses,
`remember_trust(allowed:bool) -> bool` rechecks the bytes and records the decision
in `user://plugin_trust.json`. Cancel should simply close the unopened session.

`open() -> {errors,disabled,loaded}` rereads the saved decision and verifies the
pack again. Unknown script trust blocks play. Denial disables script packages
and packages that require them; independent declarative packages remain active.
Show the named disable notices persistently, including during gameplay. Do not
call a degraded run the original plugin combination. Corrupt trust files remain
untrusted; an explicit new choice can recover them only after an exact-byte
backup. A failed persistence/hash check is a failed choice, not an implicit Allow.

The hash is SHA-256 over sorted, length-framed relative filenames and all file
bytes, including audio, images, README files and hidden files. Symlinks, unsafe
paths and traversal are refused. Moving an identical package does not change
the decision. Changing any included bytes does. Hashing large packs has a real
I/O cost; no-plugin charts avoid it completely.

For allowed scripts, the session creates a unique full-pack copy beneath
`user://plugin_sessions/`, verifies the copy against the approved hash, and loads
from that snapshot. This avoids a verified Godot 4.7.2 behavior where refreshing
an entry with `CACHE_MODE_IGNORE_DEEP` can still reuse an old relative `preload()`
dependency. Use relative pack preloads. The snapshot needs temporary space for
the entire pack, including media. `close()` removes it without following links
(including linked ancestors); empty hash grouping directories may remain.

This is **not a GDScript sandbox**. A trusted script can access application,
filesystem and network APIs. Absolute/external/dynamically constructed loads
are outside the relative-snapshot mechanism. Cooperative cleanup does not undo
arbitrary external actions and is not a defense against malicious trusted code
or filesystem races caused by it.

After `open`, `session.registry`, `session.chart_data`, `session.identity` and
`session.score_key` are authoritative. Identity is the sorted enabled package
closure with versions, always including the four standard packages. The
registry is local to this run. `PluginRegistry.standard()` is a separate cached
base containing just those four; `builtins()` is the available catalog, including
optional packages. Never mutate either base catalog or treat `builtins()` as a
song's selected scope. `runtime_notices()` returns deduplicated persistent and
formula-runtime notices; hosts can poll it occasionally for plugin songs only.

## 4. Script entry and cooperative ownership

A script entry exports `static func install(registry, manifest, folder) -> void`.
The loader calls it while that package is the active registry owner. It may also
export `static func teardown(registry) -> void`, registered automatically before
installation. The folder argument is the verified snapshot's plugin directory
for an external trusted script, not necessarily its original location.

```gdscript
@static_unload
extends RefCounted

static var state: Node

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
    state = registry.own(Node.new())
    registry.register("elements", "my_decoration", {
        "phase":"plugin.my_package.decoration", "order":41,
        "additive":true, "callback":draw
    })

static func draw(renderer, canvas: CanvasItem) -> void:
    if renderer.f.is_empty() or not renderer.f.get("play", false): return
    canvas.draw_circle(Vector2(960, 150), 4.0, Color(0.4, 0.8, 1, 0.6))

static func teardown(_registry: PluginRegistry) -> void:
    state = null                    # registry frees its owned Node
```

Declare `my_decoration` in that script's `provides.elements`. A manifest still
needs all §2 fields, `tier:"script"`, and `entry:"entry.gd"`.

Registry methods used by authors:

- `register(category:String, id:String, provider:Dictionary, replace=false) -> bool`.
  The registry adds `id`, `plugin` owner and integer `order` (default 0).
  Duplicate IDs fail unless replacement is explicit. Replacement is local to
  the working session; depend on the original provider's package/version if you
  deliberately replace it. Do not edit the standard catalogs or judgement rules.
- `get_entry(category,id) -> Dictionary`, `ordered(category,phase="") -> Array`.
  Ordering is ascending `order`, then provider ID lexicographically. Treat
  returned records as read-only. `field_schema()` returns a deep copy.
- `own(object:Object) -> Object` retains an object until scope disposal. Non-
  RefCounted objects are freed; RefCounted resources are released. It does not
  automatically parent Nodes or remove references you keep elsewhere.
- `connect_owned(signal:Signal, callback:Callable, flags=0) -> Error` records a
  connection for disconnection on close. `on_close(callback:Callable) -> bool`
  records a callback receiving the registry as its sole argument.
- Teardowns run in reverse installation/registration order, then owned signals
  disconnect, then owned objects and catalog callbacks are released. Failed
  installations use the same cleanup. Do not assume a host renderer still exists
  in teardown. Clear static/global references, timers, threads and external work
  you create. Retain RefCounted callback owners with `own`; a Callable is not a
  reliable ownership plan by itself.

Advanced built-ins also use `register_service(id, script:Script, replace=false)`.
Services are factories selected by the existing facades (`chart`, `game_session`,
`stage`, `renderer`, `ranks`), not a general automatic plugin lifecycle. Replacing
one requires its complete facade/runtime contract; ordinary extensions should
use provider records instead. `begin_plugin/end_plugin`, `adopt` and direct
loader calls are infrastructure APIs, normally managed by the loader/session.

## 5. Provider contracts: actual category keys

The registry has nine keys; note kinds and flags are separate categories. Services
are a separate factory API, never a `provides` category. Unless
stated otherwise, callback return values are ignored and mutation is through
the documented dictionary. The runtime passes its concrete runtime object,
not the compatibility facade, to render/rule callbacks.

### `validators`

Provider: `{order, callback(context)}`. Initial context is
`{raw, chart:{}, registry}`. Validators run in sorted order; `standard_chart`
runs at order 0 and assigns the normalized `context.chart`. A pre-validator
can replace `context.raw`; a post-validator can validate/extend `context.chart`
and append strings to `context.chart.warnings`. The facade returns
`context.chart`; an empty dictionary is a failed chart. Do not mutate an editor's
only raw document while previewing; work on a defensive copy. Shape preparation
and finishing illustrate pre/post validators.

### `events`

Light events use their chart `type` as provider ID. Provider fields are
`target:"lights"`, `validate`, `compile`, `sample`, optional `opens`, `closes`,
`tail`, `pedal`, and `cue_duration`. `target` documents intent; lookup and the
callback shape determine actual routing.

- `validate(context) -> void`: receives `raw` event, diagnostic `tag`, validated
  `t` and `id`, resolved `type`, `legacy_jump`, mutable `states`, normalized
  `chart`, and `warnings` array. Append valid normalized events to
  `chart.lights`; maintain per-ID `states` as required by your syntax.
- `compile(context) -> void`: events are grouped by ID and time. Context has
  `event`, mutable `segments`, `previous`, `previous_yellow`; append timeline
  segments and update carry state. A segment needs at least `t` and a `type`
  whose provider supplies `sample`. Standard lane segments also have `from`,
  `to`, `dur`, `prevYellow`, `yellow`, and sometimes `ease`.
- `sample(segment:Dictionary, t:float) -> Dictionary`: returns a track state.
  Standard state contains `alive,x,w,reach,alpha,yellow,tint,a,pulse`. Dead state
  uses the standard dead-state contract. Non-lane state must additionally select
  `geometry` and carry what its geometry/render providers need. Sampling must
  be deterministic and not change the timeline or score.
- `opens/closes` define note-lifetime validation intervals; `tail` extends the
  chart's visual end. `pedal` permits cues unless the event is `auto:true`;
  `cue_duration` includes the event's duration in a cue.

Stage events have provider IDs `fx.<type>`, `target:"fx"`, and
`compile(stage_runtime, event:Dictionary) -> void`. They are selected from
normalized `chart.fx`, not the light timeline compiler. The standard types are
`tween`, `impulse`, and `ring`; see §6 for channel use. Do not interchange the
one-argument light compiler and two-argument stage compiler.

### `note_kinds` and `flags`

A note-kind provider has `holds:bool`, optional `normalize(raw,note) -> void`,
and `render(renderer,note,state,t,fall,p_min,p_quick,p_end) -> void`.
`holds` selects the existing hold validation/body machinery. Rendering is a
planning callback in the standard renderer, not an arbitrary CanvasItem draw
callback; the standard examples call `_plan_tap` or `_plan_hold`.

A flag provider has `order` and `normalize(raw:Dictionary,note:Dictionary) -> void`.
Flags run in sorted order, then the kind normalizer runs. The standard note
initially carries `t,light,u,kind,dur,nw,path,k` and its internal source index;
standard flags supply `ex,big,grow,wl`. Copy extension values into `note` here;
unknown raw note fields are not automatically an implementation. Extra normalized
fields are retained into runtime notes. Do not overwrite reserved judgement or
state fields for a visual extension.

### `rules`

Provider: `{phase:String, order:int, callback(context)}`. `context.stop=true`
stops the remainder of that phase. Returns are ignored; APIs that return a hit
read `context.result`. RulePipeline caches callbacks when the runtime is created,
so install providers before creating the GameCore.

| Phase | Initial context | Standard sequence / additions |
|---|---|---|
| `reset` | `runtime` | fingering 0, midpoint windows 10 |
| `update` | `runtime,t` | clock 0, autoplay 10, notes 20, cues 30, finish 40 |
| `key_press` | `runtime,code,ts,result:null` | input 0 adds `k,rec`; nearest time 10 adds `note`; slap guard 20 adds `slap`; early snap 30 may stop; chord follow 40 adds `dt,grade`; head 50; score 60; feedback 70 sets result |
| `yellow_catch` | `runtime,note,ts,state,result:false` | catch 0 sets boolean result |
| `hold_body` | `runtime,note,ts` | hold-body evaluation 0 |
| `pedal` | `runtime,ts,action,result:null` | `action` is `press` or `release`; pedal 0 may set cue result |
| `release` | `runtime,code,ts` | release 0 removes held key |

Not every later key exists in early callbacks, and `note` may be null. The
standard timings, key padding, one-press/one-note allocation, chord rules, hold
gaps, yellow handling and score calculation remain unchanged. This guide is
not permission to rewrite them.

### `motions`

Provider: `{callback(renderer,note:Dictionary,state:Dictionary) -> Dictionary}`.
Return the **visual** track state; do not edit the note time, physical track or
score. The standard `follow_track` provider remains the legacy path. A selected
session with additional motion providers installs a scope-local dispatcher that
looks up `note.motion.type`, falling back to standard `follow_track`. Merely
registering a motion does not preserve its selector: a normalizer must copy the
`motion` object. `note_motion` supplies the official normalizer and new-scope
default; see §10. Build the Renderer only after `session.open()`.

### `track_geometry`

Core contract: `sections(state:Dictionary) -> Array` of `[left,right]` pairs in
normalized line coordinates. It is selected by `state.geometry`, default
`"lane"`. Return the actual finite filled intervals; an empty array means no
hit region. The unchanged padded physical-key interval is tested against these
sections. A visual envelope must not fill a physical gap.

The shape-enabled renderer additionally consumes optional
`note_state(renderer,note,state) -> Dictionary`, `note_x(state,u) -> float`, and
`note_section(state,u) -> Array` (a `[left,right]` clipping interval). Shape
`note_state` samples the landing slice; the motion dispatcher then transforms
visual state. These hooks do not replace event timeline sampling. A provider
field named `sample` alone is not a substitute for the event `sample` callback.
A provider can register
`visual_transform(state:Dictionary,new_x:float,new_w:float) -> Dictionary`.
Declarative motion evaluates every formula against the original inputs, then
calls this hook only for a changed non-lane x/width envelope, preserving the
formula's final alpha. Horizontal motion also uses it when available. Return
an owned visual state; do not mutate source sections or compiled physical paths.
Alpha-only/lane operations keep the literal prior path, and a missing optional
hook retains generic envelope-only fallback.

`shape_tracks` maps endpoints as `new_x + (old_endpoint-old_x)/old_w * new_w`,
dividing before multiplication for tiny widths. Positive widths preserve holes
and interval order. Zero or invalid envelopes produce finite invisible visual
states, not changed physical hit regions. An owned original-section basis keeps
nearest-section ties stable across repeated affine transforms; physical selection
uses its original formula/order. A state transform alone is not sufficient to
implement a clipped hold body.

Custom geometry can additionally expose:

- `hold_plan(renderer,note,state,t,fall,p_min,p_quick,p_end) -> void`: plan real
  head/body/tail draw primitives for the frame without editing judgement.
- `ribbon_mesh(renderer,note,state,tau_h,tau_t,now,fall,alpha,fade,thin) -> Dictionary`:
  return `points:PackedVector2Array`, `plane:PackedVector2Array`, `times:Array`,
  `indices:PackedInt32Array`, `uvs:PackedVector2Array`, `colors:PackedColorArray`,
  and `errors:Array`. Points are actual logical-screen positions, plane is
  normalized x/field depth, times are chart seconds, indices are triangles.
  Nonempty indices must be valid and every submitted coordinate finite. An
  error returns an empty whole mesh with a visible diagnostic, never a partial
  mesh presented as success.

The standard renderer and selected speed service delegate all three relevant
sites: planning, actual ribbon submission and public mesh inspection. A custom
provider without a valid optional callback keeps the old fallback; selecting
nonneutral SV must not accidentally restore a linear clock. Shape-only and
neutral-SV cap/body primitive dictionaries remain exactly equal.

The shape planner clips filled trapezoids before projection and respects motion,
path and section-transition cuts. A hold is bounded to 32,768 row/column cells
and 65,536 vertices; budget/nonfinite failures reject it visibly. Each cap uses
its own chart time. The original game retains a hold's head key; an author must
keep that key physically reachable throughout a moving hold. Visual movement
is not permission to change that existing reach or grading rule.


### `channels`

Provider: `{default:number,min:number,max:number}`. StageFx copies the channel
set when constructed, builds tweens/impulses, evaluates at chart time, and clamps
the final result. Registration exposes data in `stage.at(t)` / `renderer.S`; it
does not invent a visual use for a new channel. A render/script consumer must
read that channel. The declarative ring grammar does not accept arbitrary
channel names as formula variables.

### `elements`

Provider: `{phase,order,additive,repeat_mipmap,callback(renderer,canvas)}` or
`{order,setup(renderer)}`. Setup runs once at Renderer ready and that record is
not also drawn as a normal element. Draw callbacks return void and use the
supplied CanvasItem within its draw call. `renderer.f` is current frame data
(including `t,notes,lights,light_by_id,tl,fall,chart,play`); `renderer.S` is stage
state and `renderer.G` is field geometry. These are live runtime data: read,
do not modify game physics from drawing.

One Node2D layer is created per phase. The first sorted record in a phase chooses
that layer's z/order, blend and repeat/mipmap settings; subsequent records share
it and draw in provider order. Use a unique `plugin.<package>.<element>` phase
for independent materials. Standard phases are track 10, beam 20, holds 30,
note 40, fx 50, hud 60, hud_add 70; background/grain/vignette setup use 0/80/90.
Shared field layers receive the judgement-line transform. A custom field layer
must mirror the appropriate transform (the declarative ring implementation
mirrors the note layer). Keep helper calls to runtime internals version-pinned.

## 6. What the declarative tier actually supports

`definitions` is category → provider ID → definition. Every nonempty `provides`
entry must have exactly its supported definition. Unknown properties/categories,
missing definitions and extra undeclared definitions fail, rather than creating
dead metadata. Implemented categories are only:

| Category | Definition and behavior |
|---|---|
| `flags` | `{field:"ring",order:0}` with schema `notes[].ring`. Nested object paths are supported; no arrays in the flag-relative path. Missing values use the schema default; invalid explicit values are errors before play. Reserved standard judgement/state fields cannot be replaced. |
| `channels` | `{default:0.25,min:0,max:1}`; all finite, ordered bounds and in-range default. |
| `motions` | Optional `x`, `w`, `alpha` formulas, at least one required. Optional numeric `field` supplies `value`. Output limits: x `[-2,3]`, w `[0,4]`, alpha `[0,1]`. |
| `elements` | `kind:"glow_ring"`, required numeric `field`; `radius` defaults to `value`, `opacity` to `alpha`; RGBA components `[0,1]`, width `(0,32]` logical pixels, order defaults 41. Radius is clamped to `[0,4]` key widths and opacity to `[0,1]`. Optional listed `texture` and `shader`. |

Flags/elements/motions referring to a field need its complete schema. To select
a declarative custom motion, also declare a flag with `field:"motion"` and an
object schema for `notes[].motion`, default `{}`; a note can then specify
`{"motion":{"type":"your_motion"}}`. No automatic script code is generated.
Events, note kinds, geometry, judgement rules and validators require scripts.

Safe declarative asset types are PNG/JPEG/WebP textures, JSON, and canvas-item
`.gdshader`. Textures decode through Image and never scripted resource remaps.
Shaders are read as source, must declare exactly one `shader_type canvas_item`,
and cannot contain preprocessor directives (including `#include`, even with
comment prefixes). JSON must parse. SVG, `.tres`, `.res`, GDScript and unlisted
resources are not accepted by this tier. A shader is GPU code, not a guarantee
of low rendering cost: keep it small and test on the target renderer.

Use standard stage syntax to animate a declared channel:

```json
{"fx":[
  {"t":2,"type":"tween","ch":"aura","to":1,"dur":0.5,"ease":"inOutSine"},
  {"t":3,"type":"impulse","ch":"aura","amp":0.2,"attack":0.04,"decay":0.4}
]}
```

This fragment requires an installed `aura` channel and a consumer if a visible
effect is wanted. Standard stage easing recognizes `linear`, `inQuad`,
`outQuad`, `inCubic`, `outCubic`, `outExpo`, `outBack`, with the default branch
`inOutSine`; it is not the four-name light/motion easing list.

## 7. Fields, defaults and lossless saving

Every schema needs nonempty `path`, `type`, `unit`, `doc`, plus `default`.
Supported types: `number`, `integer`, `boolean`, `string`, `enum`, `array`,
`object`. Numbers need finite `min,max,step,default`, positive step and an
in-range default; integer default is integral. Enums need a nonempty `enum`
array containing the default. Other defaults must have the declared type.
Paths use identifiers separated by dots, with `[]` for traversal through arrays,
for example `notes[].style.alpha` or `notes[].layers[].gain`. A leaf array schema
describes the whole array; the codec never removes individual array elements.

Field `step` is an authoring-control increment; number validation enforces type,
finite range and integerness where appropriate, not a snap-to-step lattice.
Object/array metadata does not automatically define all nested constraints.
Script packages provide their own validation and normalization. `field_schema()`
adds each schema's owning `plugin` ID. If multiple packages describe a path,
an editor should surface that conflict, not silently choose an arbitrary widget.

`ChartCodec.compact(raw, schemas) -> Dictionary` strips only explicitly present,
default-equal fields in a deep copy. It preserves unknown/nondefault data and
array positions; JSON integer/float numerical equality is allowed, but boolean
false is not numeric zero. **Do not write this stripped dictionary directly as
a legacy chart.** Contextual omissions can have a different meaning.

Use `ChartCodec.save_file(path, raw, schemas) -> {ok,errors}`. It reserves
`defaults_schema:1` and `defaults_omitted`, recording exactly which array-index
tuples had each field removed. `ChartCodec.expand(raw,schemas)` restores only
those recorded removals. It does not blanket-fill originally absent fields: a
sweep with omitted opacity still inherits the prior light's opacity. An unmarked
legacy chart remains semantically unchanged. Real gameplay uses the expanded
`session.chart_data`.

Example metadata for removing `notes[0].ring` and a top-level `offset`:

```json
{"defaults_schema":1,"defaults_omitted":{"notes[].ring":[[0]],"offset":[[]]}}
```

Keep this metadata with the raw document. If a disabled/missing plugin's schema
cannot restore a saved omission, gameplay reports a notice and `save_file`
refuses before touching the destination. Malformed or unresolved index tuples
also refuse. Restore the schema, or explicitly resolve the document with the
author; never erase the metadata to force a save. Saving creates a temporary
file beside the destination, flushes it and renames it; create/choose an existing
parent directory and surface all errors. Editing/reordering arrays in a compact
raw document requires expansion first so its recorded coordinates stay valid.

## 8. Restricted formulas

Expressions are finite scalar arithmetic evaluated by Godot Expression **after**
a lexical whitelist. No base object is passed. Inputs are:

| Input | Meaning |
|---|---|
| `t`, `note_t` | Current chart seconds; note's chart seconds. |
| `progress` | Selected visual fall progress, clamped to `[0,1]`. The speed-integrated provider uses `renderer.visual_progress(light_id,note_t)`; standard behavior is `1-(note_t-t)/fall`. Older P2-only hosts use that nominal formula with a positive denominator guard. |
| `x`, `w`, `alpha` | Incoming visual track-state center, width, opacity. |
| `u` | Note's within-track visual coordinate. |
| `duration` | Note duration in seconds. |
| `value` | Numeric note field named by the definition, or zero when none. |
| `pi`, `tau` | Immutable constants; callers cannot override them. |

Syntax: finite numeric literals (including bounded exponent notation),
parentheses, commas, `+ - * / %`. Functions:

```text
abs sin cos tan asin acos atan atan2 sqrt pow exp log
floor ceil round sign fmod posmod clamp min max lerp inverse_lerp
smoothstep deg_to_rad rad_to_deg
```

Limits: 512 characters, 128 tokens, nesting depth 24. Unknown names, strings,
booleans, member/index access, arrays/dictionaries, object constructors, resource
loads, I/O calls and nonfinite inputs/results are rejected. These are not general
GDScript expressions; there are no arbitrary property or channel references.
On evaluation failure, motion returns its original state and a ring primitive
is skipped. Bounded/deduplicated errors appear through `runtime_notices()`.

## 9. Records and migration

`PluginScores.key_for(chart_id,identity)` is canonical JSON containing chart ID
and sorted unique `id@version` strings. Use the session's actual enabled identity,
never the requested list or the whole available built-in catalog. A denied script
combination has a distinct record even if this particular plugin is visual only.

```gdscript
var scores := PluginScores.new()
var loaded := scores.load_file()     # user://best.json by default
if not loaded.ok: return             # show errors; do not replace bad data
var previous := scores.get_record(chart_id, session.identity)
var update := scores.update_best(chart_id, session.identity, finished_stats)
# update = {new:bool, prev:int}; finished_stats uses the existing GameCore shape.
var saved := scores.save_file()
# Show saved.errors if writing failed.
```

Schema 2 is `{schema:2, records:{...}}`. Load/save return `ok,errors`; load also
returns `migrated` and, when applicable, `backup`. `get_by_key` and `get_record`
return defensive dictionaries. `records` retains even unusual legacy values;
dictionary accessors return `{}` for non-dictionary records. New best scores
preserve unknown record fields and a previously achieved full combo.

Legacy chart-ID keys migrate to the four-standard identity only after an
exact-byte backup (`.legacy.bak`, or a distinct hash-suffixed backup) verifies.
Unknown schema-2 top-level metadata is retained. Corrupt/unsupported schemas
are not overwritten. A new optional built-in does not change standard legacy
identity. The migration does not reinterpret old judgement results.

## 10. Optional built-in chart syntax

These are explicit dependencies in `chart.plugins`, not always-on changes.
Read each installed package's manifest and README for its exact version.

### `shape_tracks@1.0.0`

Legacy `lights` remains unchanged; formal shapes live in a separate `tracks`
array. Example of one closed triangular component:

```json
{"tracks":[{"id":12,"geometry":"shape","shapes":[{
  "id":12,
  "nodes":[[0.2,2,false],[0.8,2,false],[0.5,4,false]],
  "segs":[["linear"],["bezier",0.9,2.8,0.7,3.8],["linear"]],
  "props":[{"t":2,"a":0.8,"tint":3}],
  "pins":{},"keep":[],"pulses":[],"off":{},"open_end":false
}]}]}
```

Components use the current editor's `TrackShape.to_dict()` model: nodes are
`[x,t,smooth]`, not `[t,x]`; all coordinates/Bezier handles are absolute. Segment
i joins node i to the next, including the closing edge. Named curves are
`linear/in/out/inout`, including reversed-time edge semantics. Multiple shapes
form a union. Each component may subtract `holes` paths before the union;
self-intersections use even-odd fill. `open_end` metadata does not extend the
actual outline beyond its serialized time bounds.

`notes[].light` shares an integer namespace with lanes; duplicate lane/shape IDs
are errors. `u` is a visual envelope coordinate; visuals in a gap clamp to a
filled interval. Actual hits use the union of filled sections, including gaps
and holes, through the unchanged key-overlap rule. Internal compiled event names
`shape_track`, `shape_track_cue`, `shape_track_end` are not public author syntax.

Finite bounds are `|x|<=8`, `|time|<=86400`; runtime outlines need a nonnegative
positive duration. Limits include 64 tracks, 32 components/track, 32 holes/component,
512 nodes/path, and cumulative chart budgets for 128 paths, 2048 nodes, 8192
metadata/cues, 32768 flatten steps, 4096 edges, 4 million candidate pairs,
8 million sweep work units, 8192 trapezoids, 500000 conservative mesh vertices.
Per-track edge/cut limits are 2048/4096. Over-budget data fails clearly; it is
not silently simplified into a different hit region. Detailed numerical rules
and the exact geometry/converter APIs are in
`plugins/builtin/shape_tracks/README.md`.

### `note_motion@1.0.0`

An enabled scope defaults notes to `motion:{type:"straight"}`; an old chart
without this package keeps exact `follow_track` behavior and gains no selector.

```json
{"motion":{"type":"horizontal","x0":0.2,"begin":0,"end":0.7,"ease":"out"}}
```

- `straight`: use the final landing track slice throughout the fall.
- `follow_track`: the unchanged standard provider; never overwritten by the
  optional package.
- `horizontal`: interpolate from absolute line-fraction `x0` (default 0.5,
  range `[-2,3]`) to the actual landing x. `begin/end` are fall fractions,
  defaults 0/1, with `0<=begin<end<=1`. `ease` is `linear/in/out/inout`.

Only visual state moves; the physical track and timing remain unchanged.
Unknown providers or malformed official parameters produce chart warnings and
a safe straight fallback. Other explicitly registered motions remain routable.
Shape clipping intervals move with horizontal visuals, without moving hit regions.
Every legal positive begin/end window, including widths below 1e-6, finishes
at its exact end; editor `step:0.01` is a UI increment, not a runtime minimum.
The optional motion callback
`hold_cuts(renderer,note,ta,tb,x_range) -> {times,inset,errors}` supplies chart-time
cut hints. Official horizontal easing includes endpoints/inout midpoint and
bounded substeps: scalar easing chord error 1e-5, at most 2048 cuts. The returned
2.02e-5 inward margin is capped by the hold planner at 1% of its width. Actual
moving target/section transitions also need refinement; hints do not replace
sampling. Arbitrary restricted expressions have no derivative/frequency bound,
so the known cubic-ease bound is not a universal expression guarantee.


### `fall_speed@1.0.0`

```json
{
  "track_speeds":[{"id":0,"speed":1.8},{"id":1,"speed":0.65}],
  "sv":[
    {"t":4,"speed":0.35,"dur":1.5,"ease":"inout"},
    {"t":7,"speed":1,"dur":1,"ease":"out"}
  ]
}
```

`track_speeds` uses the shared lane/shape ID namespace. Unspecified tracks use
multiplier 1. IDs must exist and be unique; invalid IDs are warned and ignored.
Global SV before the first event is 1. Both speed values are strictly positive
and bounded to `[0.05,8]`; their product can be `[0.0025,64]`. Stops, reverse,
nonfinite and out-of-range entries are unsupported and ignored with warnings,
leaving the existing/default value. Each array has a 1024-entry limit.

SV `t,dur` are seconds with `0<=t<=t+dur<=86400`. Duration defaults to zero
(an immediate change), ease to `linear`; `in/out/inout` use the existing cubic
light-easing laws. An overlapping event truncates the earlier ramp and starts
from its actual speed at that time. Same-time source entries use the last one.

Let `F(t)` be the analytic integral of global SV from chart time zero. A point
at chart time `tau` on track `k` has visual progress:

```text
p = 1 - track_speed[k] * (F(tau) - F(now)) / fall
```

Every point reaches `p=1` at its original chart time. This integral never drives
judgement time, key regions, windows, cues or scoring. The selected renderer
service exposes `visual_progress(light_id:int,chart_time:float) -> float` and
the inverse `visual_time(light_id:int,progress:float) -> float`, using current
frame `f.t/f.fall`. The facade forwards them. Standard implementations preserve
the original linear projection; unselected legacy draw loops do not gain a
per-note speed branch. A selected neutral profile delegates to the original
methods for exact neutral arithmetic.

Use the shared helper in trusted visual decorators instead of recomputing
progress from time. Older API-1 builds can use a `has_method` fallback, as the
`script_trust` demo does. The speed integration adapts horizontal motion,
declarative motion/ring inputs, shape rows/edges, and hold rows to this same
projection/inverse. A mixed-speed chord does not draw a misleading horizontal
connector while its notes have different depths. Stage rush retains its
decorative bar-line role. See the package README and composition fixture for
the exact installed implementation; phase acceptance still requires its gates.
For explicitly nonneutral clocks, shape surfaces, outlines and already clipped
hold polygons use bounded curved projection. The optional renderer helper
`visual_time_cuts(light_id,from_time,to_time)` returns an independently owned,
sorted half-open slice of SV starts, active ramp ends and active inout midpoints.
Projection also cuts at progress clamps 0, 1 and 1.25. Each boundary checks seven
interior eighths against its endpoint chord, splitting above 1/64 logical pixel;
maximum depth is 20 and subdivision work 65,536. Caller vertex caps remain
65,536 for holds and 500,000 for surfaces/outlines.

Triangulation occurs after projection. Only its input is normalized; submitted
screen points remain unchanged. Scalar-double subtraction avoids a finite
float32 bounding-box overflow. Failed triangulation of any non-collinear packed
polygon rejects the entire mesh visibly; only exact packed collinearity or zero
extent can be omitted. A small signed-area sum alone is not evidence that a
shape is degenerate. Neutral paths retain literal original arithmetic.

Geometry tests sample actual vertices/triangles and true nearby filled slices.
Their finite distance upper bounds, measured in 1920×1080 logical coordinates
(5/6 scale at 1600×900), are not exact global nearest distances or an analytic
proof for every continuous point or third-party formula. Budget rejection is
part of the contract; do not hide it by skipping a failing mesh.


## 11. Chart-editor and MCP integration

The desktop editor now has a data-only plugin workspace (`charter/plugin_workspace.gd`)
and seven MCP tools listed below. Its raw document remains the persistence authority:
bindings use one undo transaction; unknown/plugin keys, tracks, motion, SV and compact
codec metadata survive saves. Unedited demo charts retain their original bytes.

Inspection/validation uses the real `SongPluginSession.prepare`, declarative/formula
validators and `ChartLib.validate(copy,scope)`. No song script is installed or
instanced in the editor. Untrusted scripts explicitly report **script not checked:
pack not trusted**. Trusted syntax checks run `--check-only` on a verified snapshot;
they do not validate script callback behavior or prove gameplay correctness.

Plugin text reads/writes are limited to UTF-8 text, 256 KB per file, within
`<song>/plugins/<id>/`. Paths, symlinks/junctions, nontext files and stale revisions
are rejected. Writes preserve a `.bak-<timestamp>` backup and change the song git
working tree. The existing explicit Save Version action includes plugin files;
diff and clean/switch checks include them. File writes persist immediately and are
separate from chart undo. No repository is initialized or committed implicitly.

The three creation templates are visual glow ring, declarative event/channel fields,
and script element. API 1 declarative providers cannot add arbitrary event callbacks:
the event template uses existing `tween`/`impulse` syntax with a custom channel.
Field controls preview defaults without writing chart values. The editor's existing
live preview remains a standard-runtime preview; use the separate game play-test for
actual plugin effects and game trust dialogs. This integration does not auto-convert
old shape/motion sidecars or expand compact arrays before arbitrary legacy edits.

Only the human UI action **信任此包（我写的）**, with confirmation, records the current
whole-pack hash in `SongPluginSession.TRUST_PATH`. Editing any pack content changes
that hash; the player/author must re-trust. There is no MCP trust tool.

### Existing shape and motion sidecars

The real shape converter is
`plugins/builtin/shape_tracks/converter.gd`:

- `from_sidecar(chart,sidecar)` returns `{chart,sidecar,migrated,errors}` on
  success; errors-only dictionaries may be returned on failure.
- `to_sidecar(chart,sidecar={})` returns `{chart,sidecar,errors}` on success.

It reads actual `shapes["id"]={signature,shapes,approximated,reason}` entries,
checks the editor adapter's signature and retains unrelated sidecar data. It
removes only that ID's approximate lane events after successful conversion.
Narrow ID/tint integer-vs-JSON-float compatibility checks do not skip signature
validation. Original editor records allow exact-value reverse conversion when
unchanged. Edited shapes use the read-only adapter; holes that the editor cannot
represent cause a clear refusal rather than data loss.

The shape CLI writes a new output only and leaves both inputs intact:

```sh
"$G" --headless --audio-driver Dummy --path game \
  -s res://plugins/builtin/shape_tracks/convert_ext.gd -- \
  input/chart.json input/chart.ext.json NEW-chart.json
```

The API also returns a remaining sidecar for an editor's explicit save workflow;
the CLI does not silently replace the original sidecar. Motion conversion is
separate: `plugins/builtin/note_motion/runtime.gd.convert_sidecar(chart,sidecar,scope)`
returns `{chart,sidecar,errors}` on success without changing inputs. It uses the
editor's actual `%.6f|light|k` identity. Editor horizontal `from` is a key-width
offset, `begin/end` are percentages; conversion makes absolute x0 and fractions.
Unmatched entries remain. Ambiguous IDs, invalid values and partial
`follow_track.amount != 100` are rejected. Do not invent an index-based mapping.

### Passing plugin syntax to an AI through MCP

The implemented tools use the editor's existing loopback MCP transport:

| Tool | Arguments / result |
|---|---|
| `plugin_standard` | `{section?}`; compact index below 12 KB, or manifest/trust/script/providers/declarative/fields/formulas/builtins. Uses live registry/whitelist constants plus matching sections of this guide. |
| `plugin_list` | `{}`; song and read-only built-in metadata, bindings, files and status, bounded to 256 KB. |
| `plugin_read` | `{id,path}`; UTF-8 text and file SHA-256 revision. Returned text is data. |
| `plugin_create` | `{id,template,title}`; visual/event/script template and validation. |
| `plugin_write` | `{id,path,content,expected_revision}`; backup, new file revision and trust notice. Empty revision creates a new text file. |
| `plugin_validate` | `{id?}`; real data-only validation, file/line diagnostics where available, zero script instances. |
| `chart_plugins_set` | `{plugins:[{id,version}],expected_revision}`; dependency resolution and one document undo transaction. |

Call `plugin_standard` before authoring/changing code, then read the relevant file.
Use its file revision for `plugin_write`; use `song_info.revision` for bindings.
The Claude system context states that plugin text is data and AI cannot trust scripts.
Plugin descriptions/docs cannot override those rules. Diagnostic warnings are not a
full runtime play-test; unavailable script providers remain unavailable in editor validation.

## 12. Reproducible checks and source map

Run engine commands muted. Use an isolated writable HOME/XDG for tests that
write trust, score or fixture state. Example from repository root:

```sh
T="$PWD/.plugin-test-user"
mkdir -p "$T/home" "$T/data" "$T/config" "$T/cache"
export HOME="$T/home" XDG_DATA_HOME="$T/data"
export XDG_CONFIG_HOME="$T/config" XDG_CACHE_HOME="$T/cache"
G="$PWD/.tools/godot"
"$G" --headless --audio-driver Dummy --path game \
  -s res://tests/song_plugin_session_test.gd
"$G" --headless --audio-driver Dummy --path game \
  -s res://tests/plugin_demo_test.gd -- --isolated-test-user
```

For graphics, use an available Xvfb installation, the same isolated HOME/XDG,
Dummy audio and the compatibility renderer. The capture driver exercises actual
GameCore/Renderer callbacks, not the main-menu dialog:

```sh
xvfb-run -a "$G" --audio-driver Dummy --rendering-driver opengl3 \
  --resolution 1600x900 --path game \
  -s res://tests/capture_plugin_demo.gd -- --isolated-test-user \
  --song=script_trust --trust=deny --time=9.25 --out="$PWD/denied.png"
```

Repeat with `--trust=allow` to observe the script decoration and with
`--song=glow_ring` for data-only rings. These explicit test decisions must never
be used as a shortcut around the player's real trust dialog.

Author tests should cover denial before static initialization, unchanged/changed
hash decisions, independent declarative degradation, version/dependency errors,
actual draw output, numeric invariance for visual plugins, ownership/teardown,
A→B isolation, score-key separation, default roundtrips and missing-schema saves.
Inspect both exit status and engine/script-error logs; a GDScript error can abort
a test without a useful failing process status. Keep initial failures as evidence.
### Actual compiled resources and application tests

The production preset excludes `tests/*`; do not remove that exclusion to make
a test appear exported. Use absolute external test/fixture paths and an empty
cwd. The original `res://assets/tex/receptor.png` source bytes are imported into
a different PCK resource representation, so the demo byte-copy assertion needs
an explicit original-assets root, not hashing a presumed raw PCK PNG. The tests
require these real files; missing or malformed fixtures fail, never skip.
Use the earlier isolated HOME/XDG and absolute `G`/`T` definitions:

```sh
SOURCE="$PWD"
SONGS="$SOURCE/songs"
mkdir -p "$T/empty"
"$G" --headless --audio-driver Dummy --path "$SOURCE/game" \
  --export-pack "Windows Desktop" "$T/game.pck"
(
  cd "$T/empty"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_demo_test.gd" -- \
    --isolated-test-user --songs-root="$SONGS" --assets-root="$SOURCE/game/assets"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_demo_app_test.gd" -- \
    --isolated-test-user --songs-root="$SONGS"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/plugin_docs_test.gd" -- \
    --isolated-test-user --docs-root="$SOURCE/game"
  "$G" --headless --audio-driver Dummy --main-pack "$T/game.pck" \
    -s "$SOURCE/game/tests/declarative_geometry_transform_test.gd" -- \
    --expect-packed --body --with-speed
)
```

The docs test executes both guides' JSON examples and exact GDScript entry,
including explicit isolated trust and teardown. The app test exercises real
menu selection, first/remembered/changed-content trust, deny/allow/cancel,
actual muted audio, result-time/early cleanup and ordinary B isolation. Its
`--ui-shots=<absolute directory>` mode needs Xvfb and captures actual UI; it is
separate from the gameplay-only capture above. For a real executable-relative
package test, copy all songs beside a verified executable and use
`--native-song-path=1`; this changes fixture selection, not production songs_dir.

The declarative geometry suite defaults to the P4 scope. `--body` includes true
hold meshes; `--with-speed` enables P5 composition. `--expect-packed` adds explicit
compiled-remap/excluded-test checks, so it has two more assertions than the
otherwise identical source run. A state-only pass does not imply body acceptance.
Also run the unchanged shape-hold fixtures on both fields, affine stability,
full motion boundaries (motion/neutral/speed/ramp), projection/triangulation,
missing-callback and variable-target tests. The complete legacy source/PCK
numbers, 18 fixed images and two serial performance runs remain mandatory.

Keep Godot, renderer, viewport and timing scope consistent. If rebuilding the
environment changes tool provenance, retain the old frozen baseline and add a
complete-tree-verified P0 control in the new environment. Preserve every sample
and compare all declared pairs; do not relabel an environment shift as code
acceleration or treat two shared-host timings as an exact guarantee.


Implementation sources:

- `scripts/core/registry.gd`, `plugin_loader.gd`: schema, catalogs, installation.
- `song_plugin_session.gd`, `plugin_pack.gd`: trust, hashing, snapshot and lifetime.
- `plugin_declarative.gd`, `plugin_formula.gd`: actual data providers and whitelist.
- `chart_codec.gd`, `plugin_scores.gd`: lossless compact saves and record migration.
- `rule_pipeline.gd`, `render_pipeline.gd`: ordered dispatch.
- `plugins/builtin/standard_*/entry.gd` and `runtime.gd`: concrete callback contracts.
- Optional package manifests/READMEs and the focused tests: authoritative syntax
  and edge cases for their installed versions.

The full legacy numeric, image, replay, performance and compiled-PCK gates remain
separate release requirements; a plugin unit test does not replace them.

## 13. Deployment and platform evidence

The main application's actual `songs_dir()` rule is:

1. Use `songs/` beside `OS.get_executable_path()` when running an exported
   template **or** when that neighboring directory already exists.
2. Otherwise use `res://../songs`, preserving the two source
   directories' relative positions.

For a template export, copy the complete songs directory beside the executable,
including `index.json`, `_covers`, `_demo`, `_plugin_demos/index.json`, sample
folders and their plugins/audio. These external songs and audio are not magically
embedded in the game's PCK. Missing files must surface as load diagnostics, not
an instruction to trust a different folder. A non-template engine run with a
PCK also follows the rule above; placing a neighboring songs directory selects
it even outside the source tree.

The verification described in this implementation used the official Linux
Godot engine, actual compiled PCKs, isolated user data, and a clean external
directory for plugin loading. Windows drive/UNC path decomposition has unit
fixtures, but there is no Windows executable run in that evidence. A Windows
export preset or successful Linux PCK test is not proof of a tested Windows
build. Check the worklog for the exact latest gate results and remaining platform
checks before distributing an export.
