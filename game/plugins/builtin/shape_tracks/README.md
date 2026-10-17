# Shape tracks (API 1, preparatory P3)

Enable explicitly with `"plugins":[{"id":"shape_tracks","version":"1.0.0"}]`.
The four standard packages remain the default. The P2 session manager owns
activation; the shape validator also refuses undeclared `tracks`.

## Format and compatibility

`lights` retains the unmodified legacy lane syntax. `tracks` is a separate array:

```json
{"id":12,"geometry":"shape","shapes":[{
  "id":12,
  "nodes":[[0.2,2.0,false],[0.8,2.0,false],[0.5,4.0,false]],
  "segs":[["linear"],["bezier",0.9,2.8,0.7,3.8],["linear"]],
  "props":[{"t":2.0,"a":0.8,"tint":3}],
  "pins":{},"keep":[],"pulses":[],"off":{},"open_end":false
}]}
```

The component is exactly the current `charter/track_shape.gd` `to_dict()` model.
Nodes are `[x,t,smooth]`, with absolute x (line fraction) and t (chart seconds).
Segment i joins node i to the next node, wrapping the final segment. Free cubic
handles are absolute `[bezier,h1x,h1t,h2x,h2t]`; both sides are independent.
Named curves `linear/in/out/inout` follow the editor's low-time-to-high-time
semantics exactly, including reversed edges. `inout` is TWO cubic pieces,
matching `SU.ease_by`, not a cubic smoothstep approximation.

Multiple components in `shapes` form a union, whether disjoint, touching or
overlapping. A component can additionally contain `holes`, each a nodes/segs
path subtracted from that component before union. Self-intersecting paths use
even-odd fill. The existing editor has no hole field; reverse conversion of
new holes fails clearly rather than losing them. Geometry is bounded by the
serialized outline even when the editor's `open_end` marker is retained.

`notes[].light` references the same integer namespace for lanes and shapes.
A lane and shape cannot use the same ID. `u` retains the editor's normalized
horizontal-envelope coordinate, and is visual only. A visual position in a gap
is clamped into the nearest filled interval. Hits use the union of actual
sections and the unchanged padded-key rule; one press still claims one note.

The separate `tracks` key avoids pretending an outline is a timed on/sweep
operation, preserves the complete editor model, and leaves all old event
validation/order untouched. A pre-validator creates registered internal
`shape_track`, `shape_track_cue`, `shape_track_end` timeline events. These are
compiler payloads, not another public chart syntax. Original non-auto pedal
cues are retained via converter metadata or shape pins/pulses.

## Geometry and rendering

Judgement evaluates float64 cubic polynomials. Each edge is split at exact time
derivative roots; a monotonic interval is solved by 52 bisections. Scanline
endpoints use lower-inclusive/upper-exclusive time, horizontal edges contribute
no crossing, shared vertices count once, tangencies contribute zero or paired
crossings, and zero-width intervals are omitted. No envelope fills a gap.

Visual flattening is separate (2e-5 maximum coordinate sample error, capped
recursive subdivision). A plane sweep at vertices and edge crossings creates
disjoint trapezoids for the union, including concavities and holes. Visible
trapezoids are subdivided at at most 1/100 of fall progress and 1/48 line width,
triangulated in `(x,s)`, and then mapped through the actual renderer field.
This preserves holes and bends mapped edges instead of drawing one flat polygon.

The plugin adds track/beam render elements. Legacy lane draws are bypassed only
for non-lane geometry. Note sampling uses the note's future shape slice, so
notes and outlines can appear before that shape reaches the judgement line.
Legacy notes retain their exact existing arithmetic and follow-track motion.

## Actual chart.ext.json converter

`converter.gd` reads the real `shapes["id"] = {signature,shapes,approximated,reason}`
sidecar structure. It checks `track_adapter.gd.signature`, moves the exact shape
objects into `tracks`, removes only that ID's approximate lane events, and
retains unrelated sidecar fields/motions. It does not change charter code.

Godot JSON loads all numbers as float, but the current editor can hash integer
id/tint fields before saving. A narrowly bounded compatibility retry rehydrates
only these integral ID/palette fields, with and without pulse fields; it never
ignores signatures or changes numeric values. Stale geometry is rejected.
The `charter` metadata stores original events/sidecar record for an exact-value
unchanged reverse conversion. Edited shapes use the current read-only adapter
for a new approximate legacy export and refreshed signature.

CLI (new output only, never overwrites inputs):

```sh
$G --headless --audio-driver Dummy --path game \
  -s res://plugins/builtin/shape_tracks/convert_ext.gd -- \
  source/chart.json source/chart.ext.json NEW-chart.json
```

The original sidecar is left intact; its note motions still need the motion
plugin's separate conversion. `from_sidecar` also returns a remaining sidecar
for an integrating editor to save under its own explicit workflow.

## Verification and demo

```sh
$G --headless --audio-driver Dummy --path game \
  -s res://tests/shape_tracks_test.gd
```

The focused test uses actual charter classes, checked-in serialized sidecar
fixtures, real GameCore physical-key presses, a denied center-gap key, two-note
chords, full-score autoplay, mapped mesh centroids, curves and malformed input.
`--write-fixtures` is a development-only fixture-regeneration switch, not needed
for ordinary tests. The demo WAV is an identical-byte copy of `_demo/audio.wav`.

`capture_demo.gd` requires a real muted Xvfb renderer. Its `--curve=linear
--fall=4.5` illustrations show the entire outline clearly; these are explicitly
illustrations, not default-gameplay acceptance. Use `--curve=deemo --fall=1.5`
for real default fall behavior. Both still use the game's nonlinear arched field.

P3 is not accepted until the parent integrates it after P2 and reruns all
numeric, 18-image and performance baselines. The isolated focused evidence is
not a replacement for that phase gate.

## Revision 2: numerical and cumulative work limits

Invalid or over-budget geometry is rejected with chart/converter diagnostics,
never silently truncated. All x coordinates and Bézier handles must satisfy
`|x| <= 8`; all times/handles/property times/cues satisfy `|t| <= 86400` seconds.
Runtime shapes still need a nonnegative, positive-duration actual outline.
These wide limits prevent float64 coefficient/discriminant overflow before any
curve math. Derived coefficients/derivatives/turn times are checked as well.
`TrackShape`'s `id=-1` factory sentinel remains accepted as shape metadata;
formal track IDs are nonnegative 32-bit integers.

There are at most 64 tracks, 32 components per track, 32 holes per component,
and 512 nodes per path. Across one chart's shape compilation: at most 128 paths,
2048 nodes, 8192 metadata keys/cues, 32768 flatten-recursion steps, 4096 flattened
edges, 4,000,000 candidate edge pairs, 8,000,000 scan/subtraction work units,
8192 trapezoids, and 500,000 conservative mesh-vertex units. A single track is
limited to 2048 flattened edges and 4096 unique sweep cuts. Edge, pair and cut
budgets are checked before the corresponding expensive sweep phase. Failing to
reach flatten tolerance within 14 subdivisions is also an error.

The real demo uses 16 nodes, 942 flattened edges (star 10, heart 932), 741
trapezoids (6/735), 433,891 candidate pairs, 434,362 scan units and 73,216
conservative vertex units. Budgets leave several-fold margin, while bounding
aggregate work rather than allowing each track to consume a fresh full budget.
The vertex bound covers the supported reach range `[0,1]` independently of fall
time. A final per-mesh finite-frame/allocation guard returns an empty mesh with
an explicit diagnostic rather than a partial mesh if unsupported frame data is
supplied. These limits do not change any accepted shape's geometry or math.

Both converter directions validate array/object containers and original charter
records before typed reads. Reverse conversion refuses stale cached records;
it does not pass malformed data into the read-only editor adapters.

## Hold ribbons and caps

Shape holds sample geometry at each body row and separately at the visible head
and tail. A hold `path` still uses the existing `[seconds, u, nw]` interpretation;
`u` selects the nearest filled section, not the empty gap in its envelope.
Each ribbon strip is intersected with **one compiled union trapezoid** before
triangulation and field mapping. Every topology boundary is a mandatory cut,
including holes narrower than the regular progress sampling interval. This
prevents positive-area triangles from bridging holes or disconnected components.
Visual polygons have closed boundary edges; judgement retains its original
lower-inclusive/upper-exclusive scanline convention. Cubic visual boundaries use
the same bounded flattened geometry as the shape surface, not a second solver.

The two optional `track_geometry` callbacks are:

- `hold_plan(renderer, note, visual_state, now, fall, p_min, p_head, p_tail) -> void`:
  build the actual capsule/ribbon draw lists. The standard hold provider calls it
  only for explicit custom geometry; missing callbacks retain the legacy path.
- `ribbon_mesh(renderer, note, visual_state, head_time, tail_time, now, fall,
  opacity, fade, thin = 1.0) -> Dictionary`: return `points` (mapped screen
  vertices), `indices`, `colors`, `uvs`, `plane` (`x,s` before mapping), `times`
  (chart times for each vertex), and `errors`. The standard draw method submits
  these same arrays, and the headless test records the actual provider result.

Geometry is sampled first; opt-in motion is then applied to the row's visual
state. The row's translated sections move with horizontal motion; the physical
track and judgement stay fixed. The optional `visual_progress`/`visual_time`
interface supplies the same clock to caps, body, motion and SV. Neutral SV uses
exactly the standard shape primitives. Non-neutral SV must delegate its shape
holds to these callbacks as well.

Each hold mesh allows at most 32,768 row/column cells and 65,536 vertices. Progress
step is at most 0.01 and horizontal subdivisions at most 1/48 line width. A budget
violation or non-finite derived vertex rejects the **entire** mesh, returns a
specific error and emits one visible engine warning per note; no partial mesh or
silent truncation is drawn. These are rendering budgets, not judgement changes.
The focused test covers the rejection through the real draw call.
