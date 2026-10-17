# Optional note motion (P4)

Enable `note_motion@1.0.0` in `chart.plugins`. Notes in that selected scope default to
`motion: {"type":"straight"}`. A chart without the plugin still uses the unchanged
standard `follow_track` path and gains no motion metadata.

- `straight`: sample the note's final track slice; keep that x/width through the fall.
- `follow_track`: the original `standard_render` provider, unchanged. P2's private
  song-session router delegates to it; this plugin never overrides its registration.
- `horizontal`: start at absolute normalized `x0` (default 0.5), then ease to the
  final landing x. `begin`/`end` are fall fractions (default 0/1), with
  `0 <= begin < end <= 1`; `ease` is `linear`, `in`, `out`, or `inout`.

Only visual state is returned. Note times, track sections, key reach, judgement
windows, scoring, and autoplay rules are untouched. Horizontal copies and shifts
its visual clipping sections, never the actual track used by GameCore. Unknown
providers or malformed official parameters produce a warning and safe straight
fallback. Other explicitly registered motion providers remain routable.

## Composition

Renderer `_land_st` first asks non-lane geometry for its base note state, then calls
P2's motion router. For shapes, the base is the landing cross-section; horizontal
shifts its section union and the envelope together so clipping stays aligned.
The initial shared renderer integration removes the early return after the
geometry callback. The reviewed follow-ons below add shape-hold tessellation and
a provider-owned declarative visual-envelope transform. The old lane arithmetic and standard motion registration stay
literal. Direct renderer users that load registries manually must install the P2
motion router, or use `SongPluginSession.prepare/open` as the tests/demo do.

## Actual charter sidecar conversion

`runtime.gd.convert_sidecar(chart, sidecar, scope)` returns new `chart`, `sidecar`,
`errors` objects without modifying inputs. The identity is the editor's actual
`%.6f|light|k` key. Editor horizontal `{from,begin,end,ease}` means key-width offset,
percentage progress, percentage progress, curve; it maps to x0 and fractions.
Unmatched sidecar entries and shapes remain. Ambiguous duplicate identities,
invalid numbers, or partial editor follow_track `amount != 100` are rejected,
not silently approximated. Full follow_track uses the original runtime behavior.
The editor's visual timeline is illustrative; gameplay uses the selected fall
window rather than its fixed preview depth scale. No charter files are changed.

## Evidence

`tests/note_motion_test.gd` covers explicit P2 sessions, 31 exact legacy and explicit
follow_track samples, straight landing, all four eases, shape holes + clipping,
malformed JSON, compact defaults, real editor offset conversion, original-track
hit vs remote visual x, one press/one note, and 3/3 full-score autoplay.
`capture_demo.gd` captures the real 1600x900 renderer with default deemo/1.5 s;
no audio is opened. Run only in an approved serialized Xvfb slot.


## Positive windows and shape holds (P4 follow-on)

Every finite `0 <= begin < end <= 1` remains valid, including differences below
`1e-6`. At `progress <= begin` the note is exactly at `x0`; at
`progress >= end` it is exactly at its target. Interior normalization divides
by the verified positive difference directly. No judgement time or hit section
is changed. Manifest begin/end metadata both use [0,1]; their joint
constraint is begin < end, and step=.01 is only an editor suggestion.

The horizontal motion provider additionally supplies the optional callback
`hold_cuts(renderer, note, ta, tb, x_range) -> Dictionary`. `ta/tb` are chart
seconds; `x_range` is a finite ordered two-number target envelope in normalized
field x. The result contains `times` (chart-second tessellation cuts), `inset`
(a normalized-x inward clipping allowance), and `errors`. It uses the shared
`visual_time` clock when available, otherwise the original linear clock, so
P4 works independently and P5 can compose without replacing this implementation.

Cuts include `begin`, `end`, and the exact `inout` midpoint, plus bounded uniform
substeps inside the motion window. For the four standard eases, the scalar ease
component uses a conservative `|amplitude| * 12 * dq^2 / 8 <= 1e-5` budget, with
`dq <= .01`. The maximum 2048 generated cut points covers the full supported
shape coordinate range and `x0` range. Budget overflow returns explicit errors
and the real draw path warns once and rejects the entire mesh, never a partial
mesh. These cuts are searched by binary range per shape trapezoid.

An inward allowance of `2.02e-5` normalized x is capped at 1% of each endpoint's
section width. It cannot erase a legal thin section. At 1600px field width the
unscaled allowance is about 0.032px per edge. This scalar easing budget is not a
claim of mathematical zero error for arbitrary continuous geometry, projection,
or third-party expressions. Packed float32 rows may coincide for a valid motion
window shorter than a raster row; endpoint positions still remain exact.
The focused regression measures finite geometric error on actual submitted
1920x1080 logical-coordinate triangles (scaled by 5/6 at 1600x900) for both
linear/deemo fields and all four supported eases,
and provides separate optional neutral/positive/ramped SV modes for the later
P5 composition gate; their availability is not a P4 SV acceptance claim.
Arbitrary high-frequency declarative formulas have no universal derivative
bound and are not silently rejected or covered by the standard-ease guarantee.

Shape hold clipping now applies the same per-row affine transform as visual
geometry: `sx = visual.w/base.w`, `tx = visual.x - base.x*sx`, followed by
`x' = sx*x + tx`. Zero or non-positive source/visual width gives empty geometry.
The transform affects drawing only; physical judgement keeps original sections.

Path knots are also mandatory hold rows. Where the nearest filled section changes,
the shape hold builder bisects that branch transition, retaining separate one-sided
rows. It then checks the actual affine bounds, note target, section endpoints and
width at quarter/mid/three-quarter times, subdividing until the sampled chord error
is at most 1e-5 normalized x. This handles a time-varying target rather than treating
it as a constant in the ease-only bound. Refinement has a separate 32768-work-step
budget and depth 32; exhaustion diagnoses and rejects the whole mesh.
These finite samples are not an analytic guarantee for arbitrary high-frequency
third-party expressions. The focused variable-target regression includes a 2ms
slanted section and a 4ms legal path reversal across disconnected sections, every
standard ease, and linear/deemo projection. Exact branch rows retain the unmodified
raw horizontal overlap report as well as a sampled containment check: an upper
bound on distance to the true filled region, using true projected slices at the
same time and +/-1e-7 seconds. This is not an exact global nearest-distance
computation or a guarantee for every point of every continuous surface. It accounts
for packed float32 y rows
without widening the 0.25 logical-pixel acceptance tolerance.
