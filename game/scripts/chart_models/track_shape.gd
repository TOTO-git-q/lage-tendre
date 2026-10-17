extends RefCounted
## Editor-side track outline: one closed path in (x, t) space.
##   x = normalized line position (0..1, spill allowed), t = chart seconds (up = later).
## A segment joins nodes[i] -> nodes[(i + 1) % n]. Its curve is either one of today's named
## eases (exactly the game's SU.ease_by applied over time) or a free cubic bezier ("bezier",
## two absolute control points). The path is serialization-agnostic: track_adapter.gd decides
## whether it can be written as today's light events or must wait for the new track syntax.

const PRESETS := ["linear", "in", "out", "inout"]
const EPS := 1e-7

var id: int = -1
var nodes: Array = []      # [{x: float, t: float, smooth: bool}]
var segs: Array = []       # [{ease: String, h1: Vector2, h2: Vector2}]
var props: Array = []      # [{t, a, tint}] opacity (-1 = unset legacy) and palette tint, sorted by t
var pins: Dictionary = {}  # time key -> extra fields of an original event that starts there (flash / cue)
var pulses: Array = []     # raw pulse events inside this lifetime, kept verbatim
var keep: Dictionary = {}  # time keys of original sweep ends: kept as knots so durations stay exact
var off_extra: Dictionary = {}
var open_end := false      # no off event: alive until the chart ends

static func tkey(t: float) -> String:
	return "%.6f" % t

func clone():
	var s = get_script().new()
	s.id = id; s.nodes = nodes.duplicate(true); s.segs = segs.duplicate(true); s.props = props.duplicate(true)
	s.pins = pins.duplicate(true); s.keep = keep.duplicate(); s.pulses = pulses.duplicate(true); s.off_extra = off_extra.duplicate(true); s.open_end = open_end
	return s

func size() -> int: return nodes.size()
func pos(i: int) -> Vector2: return Vector2(nodes[i].x, nodes[i].t)
func next(i: int) -> int: return (i + 1) % nodes.size()
func prev(i: int) -> int: return (i - 1 + nodes.size()) % nodes.size()

## [lo, hi] in float64 (Vector2 is float32: too coarse for chart seconds).
func t_range() -> Array:
	var lo := INF; var hi := -INF
	for n in nodes: lo = minf(lo, n.t); hi = maxf(hi, n.t)
	return [lo, hi]

## ---------------------------------------------------------------- evaluation
static func ease_value(name: String, f: float) -> float:
	return SU.ease_by(name, f)

## Exact (float64) point on a named-ease segment: [x, t].
func seg_eval(i: int, s: float) -> Array:
	var a: Dictionary = nodes[i]; var b: Dictionary = nodes[next(i)]; var seg: Dictionary = segs[i]
	if seg.ease == "bezier":
		var p := seg_point(i, s)
		return [p.x, p.y]
	var t: float = lerpf(a.t, b.t, s)
	if absf(b.t - a.t) < EPS: return [lerpf(a.x, b.x, s), t]
	if a.t < b.t: return [a.x + (b.x - a.x) * ease_value(seg.ease, s), t]
	return [b.x + (a.x - b.x) * ease_value(seg.ease, 1.0 - s), t]

func seg_point(i: int, s: float) -> Vector2:
	var a := pos(i); var b := pos(next(i)); var seg: Dictionary = segs[i]
	if seg.ease == "bezier":
		var h1: Vector2 = seg.h1; var h2: Vector2 = seg.h2; var r := 1.0 - s
		return a * r * r * r + h1 * 3.0 * r * r * s + h2 * 3.0 * r * s * s + b * s * s * s
	if absf(b.y - a.y) < EPS: return a.lerp(b, s)
	var t := lerpf(a.y, b.y, s)
	if a.y < b.y: return Vector2(a.x + (b.x - a.x) * ease_value(seg.ease, s), t)
	return Vector2(b.x + (a.x - b.x) * ease_value(seg.ease, 1.0 - s), t)

func seg_samples(i: int) -> int:
	var seg: Dictionary = segs[i]
	if seg.ease == "linear": return 1
	return 18

## Closed outline polygon in (x, t); also returns the segment index of each vertex.
func polygon() -> Dictionary:
	var pts := PackedVector2Array(); var owner := PackedInt32Array()
	for i in nodes.size():
		var steps := seg_samples(i)
		for k in steps:
			pts.append(seg_point(i, float(k) / steps)); owner.append(i)
	return {"points": pts, "owner": owner}

## Horizontal cross-section at time t: sorted x intersections of the outline (pairs = inside intervals).
static func crossings(poly: PackedVector2Array, t: float) -> Array:
	var xs := []
	var n := poly.size()
	for i in n:
		var p := poly[i]; var q := poly[(i + 1) % n]
		if (p.y <= t and q.y > t) or (q.y <= t and p.y > t):
			xs.append(p.x + (t - p.y) / (q.y - p.y) * (q.x - p.x))
	xs.sort()
	return xs

func envelope(t: float, poly = null) -> Vector2:
	var pts: PackedVector2Array = poly if poly != null else polygon().points
	var xs := crossings(pts, t)
	if xs.is_empty(): return Vector2(NAN, NAN)
	return Vector2(xs[0], xs[-1])

func prop_at(t: float) -> Dictionary:
	if props.is_empty(): return {"a": -1.0, "tint": -1}
	var cur: Dictionary = props[0]
	for p in props:
		if p.t <= t + EPS: cur = p
		elif absf(t - cur.t) <= EPS: break
		else:
			# opacity ramps between keys; tint switches where its key's segment begins
			var k := clampf((t - cur.t) / maxf(EPS, p.t - cur.t), 0.0, 1.0)
			var a := lerpf(float(cur.a), float(p.a), k) if cur.a >= 0 and p.a >= 0 else float(p.a)
			return {"a": a, "tint": int(p.tint)}
	return {"a": float(cur.a), "tint": int(cur.tint)}

## ---------------------------------------------------------------- editing
func translate(dx: float, dt: float) -> void:
	for n in nodes: n.x += dx; n.t += dt
	for s in segs:
		if s.ease == "bezier": s.h1 += Vector2(dx, dt); s.h2 += Vector2(dx, dt)
	for p in props: p.t += dt
	var moved := {}
	for k in pins: moved[tkey(float(k) + dt)] = pins[k]
	pins = moved
	var kept := {}
	for k in keep: kept[tkey(float(k) + dt)] = true
	keep = kept
	for p in pulses: p.t = float(p.t) + dt

## dx / dt stay float64 (a Vector2 would round chart seconds and positions to float32).
func move_node(i: int, dx: float, dt: float) -> void:
	nodes[i].x += dx; nodes[i].t += dt
	# free handles travel with their node, like any vector editor
	if segs[i].ease == "bezier": segs[i].h1 += Vector2(dx, dt)
	if segs[prev(i)].ease == "bezier": segs[prev(i)].h2 += Vector2(dx, dt)

## Best named ease for the sub-curve [s0, s1] of `name` (exact for linear; nearest otherwise).
static func fit_preset(name: String, s0: float, s1: float) -> String:
	if name == "linear": return "linear"
	var v0 := ease_value(name, s0); var v1 := ease_value(name, s1)
	if absf(v1 - v0) < 1e-9: return "linear"
	var best := "linear"; var err := INF
	for cand in PRESETS:
		var e := 0.0
		for k in 17:
			var f := k / 16.0
			var want := (ease_value(name, lerpf(s0, s1, f)) - v0) / (v1 - v0)
			e += pow(ease_value(cand, f) - want, 2)
		if e < err: err = e; best = cand
	return best

## Split segment i at parameter s; returns the new node index.
func insert(i: int, s: float) -> int:
	s = clampf(s, 0.02, 0.98)
	var a := pos(i); var b := pos(next(i)); var seg: Dictionary = segs[i]
	var p := seg_point(i, s)
	var exact := seg_eval(i, s)
	var first := {"ease": seg.ease, "h1": Vector2.ZERO, "h2": Vector2.ZERO}
	var second := {"ease": seg.ease, "h1": Vector2.ZERO, "h2": Vector2.ZERO}
	if seg.ease == "bezier":
		var p01: Vector2 = a.lerp(seg.h1, s); var p12: Vector2 = seg.h1.lerp(seg.h2, s); var p23: Vector2 = seg.h2.lerp(b, s)
		var p012 := p01.lerp(p12, s); var p123 := p12.lerp(p23, s)
		first.h1 = p01; first.h2 = p012; second.h1 = p123; second.h2 = p23
	elif absf(b.y - a.y) > EPS:
		var lo_first := a.y < b.y
		first.ease = fit_preset(seg.ease, 0.0, s) if lo_first else fit_preset(seg.ease, 1.0 - s, 1.0)
		second.ease = fit_preset(seg.ease, s, 1.0) if lo_first else fit_preset(seg.ease, 0.0, 1.0 - s)
	var at := i + 1
	nodes.insert(at, {"x": exact[0], "t": exact[1], "smooth": seg.ease != "linear"})
	segs[i] = first
	segs.insert(at, second)
	return at

func remove(i: int) -> bool:
	if nodes.size() <= 3: return false
	var j := prev(i)
	var merged := {"ease": segs[j].ease, "h1": segs[j].h1, "h2": segs[i].h2}
	if segs[j].ease != segs[i].ease and (segs[j].ease == "bezier") != (segs[i].ease == "bezier"):
		merged.ease = "linear"
	if merged.ease == "bezier": merged.h2 = segs[i].h2
	nodes.remove_at(i); segs.remove_at(i)
	segs[j if j < i else j - 1] = merged
	return true

func set_ease(i: int, ease_name: String) -> void:
	var a := pos(i); var b := pos(next(i))
	if ease_name == "bezier" and segs[i].ease != "bezier":
		# start from the cubic that matches the current named curve, so converting is seamless
		var c: Array = {"linear": [1.0 / 3.0, 2.0 / 3.0], "in": [0.0, 0.0], "out": [1.0, 1.0], "inout": [0.0, 1.0]}.get(segs[i].ease, [1.0 / 3.0, 2.0 / 3.0])
		var lo := a if a.y <= b.y else b; var hi := b if a.y <= b.y else a
		var near_lo := Vector2(lo.x + (hi.x - lo.x) * c[0], lerpf(lo.y, hi.y, 1.0 / 3.0))
		var near_hi := Vector2(lo.x + (hi.x - lo.x) * c[1], lerpf(lo.y, hi.y, 2.0 / 3.0))
		if absf(b.y - a.y) < EPS: near_lo = a.lerp(b, 1.0 / 3.0); near_hi = a.lerp(b, 2.0 / 3.0)
		segs[i] = {"ease": "bezier", "h1": near_lo if a.y <= b.y else near_hi, "h2": near_hi if a.y <= b.y else near_lo}
		return
	segs[i] = {"ease": ease_name, "h1": Vector2.ZERO, "h2": Vector2.ZERO}

## Index of the node with the same time on the other side of a lane shape (-1 when none).
func partner(i: int) -> int:
	var t: float = nodes[i].t
	var best := -1
	for j in nodes.size():
		if j != i and absf(nodes[j].t - t) < 1e-6 and j != next(i) and j != prev(i): best = j
	if best >= 0: return best
	for j in nodes.size():
		if j != i and absf(nodes[j].t - t) < 1e-6: return j
	return -1

## ---------------------------------------------------------------- presets (dragged box in x/t)
static func preset(kind: String, x0: float, x1: float, t0: float, t1: float):
	var s = load("res://scripts/chart_models/track_shape.gd").new()
	var cx := (x0 + x1) / 2.0; var ct := (t0 + t1) / 2.0; var rx := (x1 - x0) / 2.0; var rt := (t1 - t0) / 2.0
	var pts := []
	var eases := []
	match kind:
		"diamond":
			pts = [Vector2(cx, t0), Vector2(x1, ct), Vector2(cx, t1), Vector2(x0, ct)]
		"star":
			for k in 10:
				var ang := PI / 2.0 + k * PI / 5.0
				var r := 1.0 if k % 2 == 0 else 0.45
				pts.append(Vector2(cx + cos(ang) * rx * r, ct - sin(ang) * rt * r))
		"circle":
			pts = [Vector2(cx, t0), Vector2(x1, ct), Vector2(cx, t1), Vector2(x0, ct)]
			eases = ["bezier", "bezier", "bezier", "bezier"]
		"heart":
			pts = [Vector2(cx, t0), Vector2(x1, lerpf(t0, t1, 0.62)), Vector2(lerpf(cx, x1, 0.5), t1), Vector2(cx, lerpf(t0, t1, 0.8)), Vector2(lerpf(x0, cx, 0.5), t1), Vector2(x0, lerpf(t0, t1, 0.62))]
			eases = ["out", "bezier", "bezier", "bezier", "bezier", "in"]
		_:
			pts = [Vector2(x0, t0), Vector2(x0, t1), Vector2(x1, t1), Vector2(x1, t0)]
	var exact := []   # float64 node coordinates (Vector2 is float32)
	match kind:
		"diamond", "circle": exact = [[cx, t0], [x1, ct], [cx, t1], [x0, ct]]
		"heart": exact = [[cx, t0], [x1, lerpf(t0, t1, 0.62)], [lerpf(cx, x1, 0.5), t1], [cx, lerpf(t0, t1, 0.8)], [lerpf(x0, cx, 0.5), t1], [x0, lerpf(t0, t1, 0.62)]]
		"star":
			for k in 10:
				var ang := PI / 2.0 + k * PI / 5.0
				var r := 1.0 if k % 2 == 0 else 0.45
				exact.append([cx + cos(ang) * rx * r, ct - sin(ang) * rt * r])
		_: exact = [[x0, t0], [x0, t1], [x1, t1], [x1, t0]]
	for i in pts.size():
		s.nodes.append({"x": float(exact[i][0]), "t": float(exact[i][1]), "smooth": kind in ["circle", "heart"]})
		s.segs.append({"ease": eases[i] if i < eases.size() else "linear", "h1": Vector2.ZERO, "h2": Vector2.ZERO})
	var k := 0.5523
	if kind == "circle":
		var c := Vector2(cx, ct)
		for i in 4:
			var a: Vector2 = pts[i]; var b: Vector2 = pts[(i + 1) % 4]
			# quarter arc: the tangent at a is parallel to (b - c), at b parallel to (a - c)
			s.segs[i].h1 = a + (b - c) * k
			s.segs[i].h2 = b + (a - c) * k
	if kind == "heart":
		var lobe := (t1 - t0) * 0.32
		s.segs[1].h1 = Vector2(x1, lerpf(t0, t1, 0.62) + lobe * 0.6); s.segs[1].h2 = Vector2(lerpf(cx, x1, 0.85), t1)
		s.segs[2].h1 = Vector2(lerpf(cx, x1, 0.15), t1); s.segs[2].h2 = Vector2(cx, lerpf(t0, t1, 0.92))
		s.segs[3].h1 = Vector2(cx, lerpf(t0, t1, 0.92)); s.segs[3].h2 = Vector2(lerpf(x0, cx, 0.85), t1)
		s.segs[4].h1 = Vector2(lerpf(x0, cx, 0.15), t1); s.segs[4].h2 = Vector2(x0, lerpf(t0, t1, 0.62) + lobe * 0.6)
	return s

## ---------------------------------------------------------------- persistence (sidecar)
func to_dict() -> Dictionary:
	var ns := []
	for n in nodes: ns.append([n.x, n.t, n.smooth])
	var ss := []
	for g in segs: ss.append([g.ease, g.h1.x, g.h1.y, g.h2.x, g.h2.y] if g.ease == "bezier" else [g.ease])
	return {"id": id, "nodes": ns, "segs": ss, "props": props.duplicate(true), "pins": pins.duplicate(true), "keep": keep.keys(), "pulses": pulses.duplicate(true), "off": off_extra.duplicate(true), "open_end": open_end}

static func from_dict(d: Dictionary):
	var s = load("res://scripts/chart_models/track_shape.gd").new()
	s.id = int(d.get("id", -1))
	for n in d.get("nodes", []): s.nodes.append({"x": float(n[0]), "t": float(n[1]), "smooth": bool(n[2]) if n.size() > 2 else false})
	for g in d.get("segs", []):
		if g[0] == "bezier": s.segs.append({"ease": "bezier", "h1": Vector2(g[1], g[2]), "h2": Vector2(g[3], g[4])})
		else: s.segs.append({"ease": str(g[0]), "h1": Vector2.ZERO, "h2": Vector2.ZERO})
	s.props = d.get("props", []).duplicate(true); s.pins = d.get("pins", {}).duplicate(true)
	for k in d.get("keep", []): s.keep[str(k)] = true
	s.pulses = d.get("pulses", []).duplicate(true); s.off_extra = d.get("off", {}).duplicate(true); s.open_end = d.get("open_end", false)
	return s
