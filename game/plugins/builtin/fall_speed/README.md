# Positive fall speed and scroll velocity (preparatory P5)

Enable `fall_speed@1.0.0` in `chart.plugins`.

```json
{
  "track_speeds": [{"id": 0, "speed": 1.8}, {"id": 1, "speed": 0.65}],
  "sv": [
    {"t": 4, "speed": 0.35, "dur": 1.5, "ease": "inout"},
    {"t": 7, "speed": 1, "dur": 1, "ease": "out"}
  ]
}
```

`track_speeds` uses the shared `lights` / shape `tracks` ID namespace. Missing
tracks have multiplier 1. IDs must exist; duplicate/unknown IDs are diagnosed and
ignored. Global velocity before the first SV event is 1. `speed` is strictly
positive, in `[0.05,8]` for both per-track and SV values. Stops, negative/reverse
scroll, nonfinite values and out-of-range values are unsupported: validation
warns and ignores the offending entry, leaving the safe existing/default value.
The product of global and per-track speeds may range from 0.0025 to 64.

SV `t` and `dur` are seconds, with `0 <= t <= t+dur <= 86400`; `dur=0` changes
immediately. Ease is `linear` (default), `in`, `out`, `inout`, using the original
SU cubic easing laws. A new overlapping event truncates the preceding ramp and
starts from its actual speed at the new time. Same-time events are resolved in
source order, last one wins. Each array is limited to 1024 entries before sort.
These policies and ranges match plugin field schemas and diagnostics.

## Exact timing

Let F be the analytic integral of global SV from chart time zero. A point at
chart time tau on track k uses:

`p = 1 - track_speed[k] * (F(tau) - F(now)) / fall`

Thus every tap, hold head/body/tail point, and shape section has `p=1` exactly
at its own chart time, across ramps and jumps. All four easing antiderivatives
are explicit polynomials; the positive monotone integral is inverted with a
bounded 56-step bisection only inside a ramp. Flat tails are inverted directly.
No numerical time-stepping or accumulated frame drift is used. Judgement time,
keys, track sections, windows, cues, and scoring never use the visual integral.

## Composition and service scope

This plugin installs a renderer service subclass only in its selected song
scope. The immutable four-standard registry still owns the original renderer.
Old draw loops and arithmetic are untouched. An explicitly enabled neutral
chart (no SV, all multipliers 1) delegates to original methods, and its progress
uses the literal original arithmetic for exact neutral parity.

The standard renderer exposes two optional-visual helper APIs:

- `visual_progress(light_id: int, chart_time: float) -> float`
- `visual_time(light_id: int, progress: float) -> float`

Standard implementations are the original linear time projection; this service
overrides them with integral/inverse. Existing legacy lane loops do not call
these new methods, so unselected scopes gain no per-note branch or lookup.
Horizontal motion and declarative motion/ring inputs use the shared progress;
shape mesh rows and edges use progress/inverse; hold ribbons use the same
inverse at each row. Each hold row samples its own landing shape section and
clips its width inside that shifted visual section. Disconnected sections are
not bridged by a ribbon triangle. Mixed-speed chord notes do not receive a
misleading horizontal connector while they are at different depths.

`Renderer` facade forwards the helper methods. Trusted script decorators should
call them rather than recalculate progress from time; scripts supporting older
API-1 builds may check `has_method("visual_progress")` and use the former linear
formula as fallback. Declarative formulas continue to receive the same bounded
`progress` variable, now correctly tied to the selected visual clock.

The original stage rush still modulates decorative bar-line clock only; global
SV composes with it. Stage effects and all game clock/judgement rules are intact.

## Evidence and demo

The demo has 16 taps and 2 holds, with original `_demo` audio copied byte-for-byte.
`combined.chart.json` is an additional composition fixture with a two-section
shape, horizontal motion, eased SV and a hold. It is not a separate song entry.
`tests/fall_speed_test.gd` tests analytic integrals, boundaries, overlapping and
same-time events, inverse/derivative identities, invalid inputs, exact neutral
progress/primitives, actual declarative rings, shape vertices, hold clips and
on-time arrival, autoplay and default-field roundtrips.

`capture_demo.gd` uses real default deemo/1.5s rendering without loading audio.
`--variant=neutral_standard` and `--variant=neutral_speed` are the same neutral
chart through the old and opt-in services for pixel comparison. `--variant=combined`
loads the composition fixture. Use only an approved serialized Xvfb slot.
Full P0 gates and phase acceptance belong to the parent integrator.

## Shape-hold callback composition

With the P3 corrective hold provider installed, non-neutral `fall_speed` delegates
shape hold planning and ribbon submission to the geometry's optional `hold_plan`
and `ribbon_mesh` callbacks. The callback uses the same integrated
`visual_progress` / `visual_time` clock. Its clipped trapezoid mesh is shared with
plain shape holds, so narrow holes cannot be bridged between sampled rows.
The public `ribbon_mesh` inspection helper returns that exact provider mesh too.
Neutral SV reaches the same corrected standard shape provider and returns
bit-identical shape cap/body primitives to the non-SV shape renderer.

Providers without those optional callbacks retain the original integrated SV
hold implementation; a missing callback must not fall back to a linear clock.
The new dispatch test exercises that absence case. Default lane geometry is
unchanged; charts without `fall_speed` never instantiate this service.

### Nonneutral shape projection (recovery revision)

The optional renderer method
`visual_time_cuts(light_id: int, from_time: float, to_time: float) -> Array`
returns chart-time cuts for SV jumps, active ramp ends and active `inout`
midpoints. A later event truncates the preceding ramp; same-time source order
still resolves through the original compiled profile. The returned array is
independent of the cached cuts. Neutral clocks return an empty array.

For explicitly nonneutral clocks, shape surfaces, outlines and clipped hold
polygons split at these cuts and at projection clamp boundaries. Their screen
boundaries are adaptively subdivided using seven interior eighth-point samples;
the sampled endpoint-chord criterion is at most 1/64 logical pixel. Mapped
polygons are triangulated after projection. Hold rows also retain P4's mandatory
motion/path cuts, source-stable affine section choice, and local affine-state
refinement. Original speed limits and motion parameter ranges are unchanged.

Triangulation uses a separate axis-normalized local polygon to avoid float32
area cancellation for legal very thin windows. Submitted positions are not
modified by that normalization. Exactly zero packed width/height has no raster
area. A failed triangulation is omitted only when all actual packed vertices
are strictly collinear, using double scalar cross products with no area
tolerance. Non-collinear failure explicitly rejects the whole mesh, including
self-intersections whose signed area cancels to zero. Bounding-box differences
are also computed as doubles so finite packed extremes cannot overflow that
normalization. There is no convex-hull fallback or broadened clipping tolerance.

Each projection plan is limited to 65,536 subdivision steps and depth 20, with
the existing caller vertex limit (hold 65,536; surface/outline 500,000). Nonfinite
float64 values and packed float32 overflow return explicit errors, with no
partial mesh submitted. Legal narrow-window, star and heart examples must still
produce nonempty meshes. Budget diagnostics remain visible through existing
render warnings.

These are finite sampled approximation criteria, not an analytic guarantee for
all continuous curves or arbitrary high-frequency declarative formulas. The
focused tests measure an upper bound on distance to sampled true nearby filled
slices, with each slice at its actual projected y. They do not claim an exact
global shortest distance. The acceptance tolerance is .25 logical pixel;
coordinates are 1920x1080 logical units, so multiply distances by 5/6 for a
1600x900 output. The refinement criterion is screen-space: at a depth s with
nonzero horizontal pixel span, its equivalent horizontal field-unit tolerance
is `(1/64) / abs(G.x_of(1,s)-G.x_of(0,s))`. No depth-independent field-x bound
is claimed because the field scale varies with depth and stage transform.
Same-y horizontal values are retained separately, including large closed-row
float32 readings. Neutral clocks retain the original mesh
path exactly and remain an explicit numerical control.

New recovery tests are `scroll_projection_recovery_test.gd` (requires an explicit
absolute `--songs-root`), `scroll_motion_recovery_test.gd` (neutral/speed/ramp),
and `fall_speed_dispatch_recovery_test.gd`. They exercise production mesh data,
actual ribbon submission, real surface/outline draw callbacks, all standard
SV eases, narrow horizontal windows, actual default-deemo/fall1.5 star/heart
meshes, exact head/tail arrival and unchanged GameCore hold scoring. Missing
required demo fixtures fail explicitly. All recovery logs are newly generated;
lost temporary artifacts from the earlier workspace are not recreated as old
results. Stage acceptance remains with the parent integrator.
