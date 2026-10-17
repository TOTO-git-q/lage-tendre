extends RefCounted
## Adapter between the editor's track shapes (track_shape.gd) and today's light-event syntax.
##
## Interface (the planned core refactor replaces this file with direct shape serialization):
##   from_events(events, id)        -> Array[TrackShape]   one shape per on..off lifetime
##   is_representable(shape)        -> {ok, reason, knots}
##   to_events(shape, inherit, grid)-> {events, exact, reason}
## Today's syntax: per lifetime, left/right edges are functions of time that share keyframe
## times and one named ease per interval (inout/linear/in/out); the start/end edges are flat.
## Anything else is approximated by its cross-section envelope for the game and kept exactly
## in the sidecar chart.shapes.json until the engine supports general shapes.

const Shape = preload("res://scripts/chart_models/track_shape.gd")
const GEOMETRY := ["t", "id", "type", "x", "w", "a", "tint", "dur", "ease"]

static func num(v: float) -> float:
	return float(String.num(v, 9))

static func extras(e: Dictionary) -> Dictionary:
	var out := {}
	for k in e:
		if not k in GEOMETRY: out[k] = e[k]
	return out

## Stable identity of one track's events, used to match sidecar shapes and editing memos.
static func signature(events: Array) -> String:
	var rows := []
	for e in events: rows.append(JSON.stringify(e, "", true))
	rows.sort()
	return "|".join(rows).sha256_text().left(16)

## ---------------------------------------------------------------- events -> shapes
static func from_events(events: Array, id: int, chart_end: float) -> Array:
	var list := []
	for e in events:
		if int(e.get("id", -1)) == id and e.has("t"): list.append(e)
	list.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var shapes := []
	var state := {"x": 0.5, "w": 0.2, "a": -1.0, "tint": -1}
	var knots := []; var pins := {}; var keep := {}; var pulses := []; var current = null
	for e in list:
		var t := float(e.t); var type := str(e.get("type", ""))
		if type == "on":
			state = {"x": float(e.get("x", state.x)), "w": float(e.get("w", state.w)), "a": float(e.get("a", state.a)), "tint": int(e.get("tint", state.tint))}
			knots = [{"t": t, "x": state.x, "w": state.w, "a": state.a, "tint": state.tint, "ease": "linear"}]
			pins = {Shape.tkey(t): extras(e)}; keep = {}; pulses = []; current = true
		elif current == null: continue
		elif type == "pulse": pulses.append(e.duplicate(true))
		elif type == "sweep":
			var dur := maxf(0.0, float(e.get("dur", 0.0)))
			if t > knots[-1].t + 1e-9: knots.append({"t": t, "x": state.x, "w": state.w, "a": state.a, "tint": state.tint, "ease": "linear"})
			pins[Shape.tkey(t)] = extras(e)
			state = {"x": float(e.get("x", state.x)), "w": float(e.get("w", state.w)), "a": float(e.get("a", state.a)), "tint": int(e.get("tint", state.tint))}
			if dur <= 1e-9: knots[-1].merge(state, true)
			else:
				keep[Shape.tkey(t + dur)] = true
				knots.append({"t": t + dur, "x": state.x, "w": state.w, "a": state.a, "tint": state.tint, "ease": str(e.get("ease", "inout"))})
		elif type == "off":
			if t > knots[-1].t + 1e-9: knots.append({"t": t, "x": state.x, "w": state.w, "a": state.a, "tint": state.tint, "ease": "linear"})
			var s = build(id, knots, pins, pulses); s.keep = keep; s.off_extra = extras(e); shapes.append(s); current = null
	if current != null:
		var end := maxf(chart_end, knots[-1].t + 0.5)
		if end > knots[-1].t + 1e-9: knots.append({"t": end, "x": state.x, "w": state.w, "a": state.a, "tint": state.tint, "ease": "linear"})
		var s = build(id, knots, pins, pulses); s.keep = keep; s.open_end = true; shapes.append(s)
	return shapes

static func build(id: int, knots: Array, pins: Dictionary, pulses: Array):
	var s = Shape.new(); s.id = id; s.pins = pins.duplicate(true); s.pulses = pulses.duplicate(true)
	if knots.size() == 1: knots.append(knots[0].duplicate()); knots[1].t += 0.05
	var m := knots.size()
	for k in knots: s.nodes.append({"x": k.x - k.w / 2.0, "t": k.t, "smooth": false})
	for i in range(m - 1, -1, -1): s.nodes.append({"x": knots[i].x + knots[i].w / 2.0, "t": knots[i].t, "smooth": false})
	for i in m - 1: s.segs.append({"ease": knots[i + 1].ease, "h1": Vector2.ZERO, "h2": Vector2.ZERO})
	s.segs.append({"ease": "linear", "h1": Vector2.ZERO, "h2": Vector2.ZERO})          # end edge
	for i in range(m - 1, 0, -1): s.segs.append({"ease": knots[i].ease, "h1": Vector2.ZERO, "h2": Vector2.ZERO})
	s.segs.append({"ease": "linear", "h1": Vector2.ZERO, "h2": Vector2.ZERO})          # start edge
	for k in knots: s.props.append({"t": k.t, "a": k.a, "tint": k.tint})
	return s

## ---------------------------------------------------------------- representability
static func is_representable(s) -> Dictionary:
	var n: int = s.nodes.size()
	if n < 4: return {"ok": false, "reason": "形状少于四个节点"}
	for g in s.segs:
		if g.ease == "bezier": return {"ok": false, "reason": "自定义贝塞尔曲线"}
	var r: Array = s.t_range()
	var lows := []; var highs := []
	for i in n:
		if absf(s.nodes[i].t - r[0]) < 1e-6: lows.append(i)
		if absf(s.nodes[i].t - r[1]) < 1e-6: highs.append(i)
	if lows.size() != 2 or highs.size() != 2: return {"ok": false, "reason": "起止边不是水平直线"}
	var b0: int = lows[0]; var b1: int = lows[1]
	if s.next(b0) != b1 and s.next(b1) != b0: return {"ok": false, "reason": "起始边不相连"}
	var start: int = b1 if s.next(b0) == b1 else b0   # walking forward from `start` leaves the start edge
	var chain_a := [start]; var i := start
	var up := true
	while true:
		var j: int = s.next(i)
		if s.nodes[j].t < s.nodes[i].t - 1e-9: return {"ok": false, "reason": "边线在时间上回折"}
		if absf(s.nodes[j].t - s.nodes[i].t) < 1e-9: break
		chain_a.append(j); i = j
	if absf(s.nodes[chain_a[-1]].t - r[1]) > 1e-6: return {"ok": false, "reason": "边线在时间上回折"}
	var top_a: int = chain_a[-1]; var top_b: int = s.next(top_a)
	if absf(s.nodes[top_b].t - r[1]) > 1e-6: return {"ok": false, "reason": "结束边不是水平直线"}
	var chain_b := [top_b]; i = top_b
	while i != (b0 if start == b1 else b1):
		var j: int = s.next(i)
		if s.nodes[j].t > s.nodes[i].t + 1e-9 or absf(s.nodes[j].t - s.nodes[i].t) < 1e-9: return {"ok": false, "reason": "边线在时间上回折"}
		chain_b.append(j); i = j
	chain_b.reverse()   # bottom -> top
	if chain_a.size() != chain_b.size(): return {"ok": false, "reason": "两侧边节点时间不一致"}
	var mid: float = (r[0] + r[1]) / 2.0
	var left_a: bool = _chain_x(s, chain_a, mid) <= _chain_x(s, chain_b, mid)
	var left: Array = chain_a if left_a else chain_b; var right: Array = chain_b if left_a else chain_a
	var knots := []
	for k in left.size():
		var tl: float = s.nodes[left[k]].t; var tr: float = s.nodes[right[k]].t
		if absf(tl - tr) > 1e-6: return {"ok": false, "reason": "两侧边节点时间不一致"}
		var l: float = s.nodes[left[k]].x; var rr: float = s.nodes[right[k]].x
		if rr - l < SU.KEY_UNIT - 1e-4: return {"ok": false, "reason": "宽度小于一键"}
		var ease := "linear"
		if k > 0:
			var el: String = _seg_between(s, left[k - 1], left[k]).ease
			var er: String = _seg_between(s, right[k - 1], right[k]).ease
			var hold_l: bool = absf(l - s.nodes[left[k - 1]].x) < 1e-9
			var hold_r: bool = absf(rr - s.nodes[right[k - 1]].x) < 1e-9
			if not hold_l and not hold_r and el != er: return {"ok": false, "reason": "两侧边曲线不同（今日语法一段只能一种曲线）"}
			ease = er if hold_l else el
		var p: Dictionary = s.prop_at(tl)
		knots.append({"t": tl, "l": l, "r": rr, "ease": ease, "a": p.a, "tint": p.tint})
	for p in s.props:
		var on_knot := false
		for k in knots:
			if absf(k.t - p.t) < 1e-6: on_knot = true
		if not on_knot: return {"ok": false, "reason": "不透明度关键点不在节点上"}
	return {"ok": true, "reason": "", "knots": knots}

static func _chain_x(s, chain: Array, t: float) -> float:
	for k in chain.size() - 1:
		var a = s.nodes[chain[k]]; var b = s.nodes[chain[k + 1]]
		if t >= a.t and t <= b.t: return lerpf(a.x, b.x, (t - a.t) / maxf(1e-9, b.t - a.t))
	return s.nodes[chain[0]].x

static func _seg_between(s, i: int, j: int) -> Dictionary:
	return s.segs[i] if s.next(i) == j else s.segs[j]

## ---------------------------------------------------------------- shapes -> events
## inherit = {a, tint} carried over from this track's previous lifetime (build_timelines keeps it).
static func to_events(s, inherit: Dictionary, grid_step: float = 0.05) -> Dictionary:
	var rep := is_representable(s)
	var knots: Array = rep.knots if rep.ok else approximate(s, grid_step)
	knots = reduce(knots, s.pins, s.keep)
	var events := []
	var prev := {"a": float(inherit.get("a", -1.0)), "tint": int(inherit.get("tint", -1))}
	var k0: Dictionary = knots[0]
	var on := {"t": num(k0.t), "id": s.id, "type": "on", "x": num((k0.l + k0.r) / 2.0), "w": num(k0.r - k0.l)}
	if k0.a >= 0 and absf(k0.a - prev.a) > 1e-9: on.a = num(k0.a)
	if int(k0.tint) != prev.tint: on.tint = int(k0.tint)
	on.merge(s.pins.get(Shape.tkey(k0.t), {"auto": true}), false)
	events.append(on); prev = {"a": k0.a, "tint": int(k0.tint)}
	for i in knots.size() - 1:
		var a: Dictionary = knots[i]; var b: Dictionary = knots[i + 1]
		var pinned: bool = i > 0 and s.pins.has(Shape.tkey(a.t))
		if not changed(a, b) and not pinned: continue
		var e := {"t": num(a.t), "id": s.id, "type": "sweep", "dur": num(b.t - a.t), "x": num((b.l + b.r) / 2.0), "w": num(b.r - b.l)}
		if b.ease != "inout": e.ease = b.ease
		if b.a >= 0 and absf(b.a - prev.a) > 1e-9: e.a = num(b.a)
		if int(b.tint) != prev.tint: e.tint = int(b.tint)
		e.merge(s.pins.get(Shape.tkey(a.t), {"auto": true}), false)
		events.append(e); prev = {"a": b.a, "tint": int(b.tint)}
	for p in s.pulses: events.append(p.duplicate(true))
	var middle := events.slice(1)
	middle.sort_custom(func(x, y): return float(x.t) < float(y.t) if float(x.t) != float(y.t) else x.type == "pulse" and y.type != "pulse")
	events = [events[0]] + middle
	if not s.open_end:
		var off := {"t": num(knots[-1].t), "id": s.id, "type": "off"}
		off.merge(s.off_extra, false)
		events.append(off)
	return {"events": events, "exact": rep.ok, "reason": rep.reason, "final": prev}

static func changed(a: Dictionary, b: Dictionary) -> bool:
	return absf(a.l - b.l) > 1e-9 or absf(a.r - b.r) > 1e-9 or absf(a.a - b.a) > 1e-9 or int(a.tint) != int(b.tint)

## Drop knots whose removal leaves the drawn track unchanged (collinear linear runs, repeated
## holds). Knots where an original event starts are kept: each event start flashes the track.
static func reduce(knots: Array, pins: Dictionary, keep: Dictionary = {}) -> Array:
	var out := knots.duplicate(true)
	var again := true
	while again:
		again = false
		for k in range(1, out.size() - 1):
			var a: Dictionary = out[k - 1]; var m: Dictionary = out[k]; var b: Dictionary = out[k + 1]
			if pins.has(Shape.tkey(m.t)) or keep.has(Shape.tkey(m.t)) or int(m.tint) != int(b.tint) or int(a.tint) != int(m.tint): continue
			var hold := not changed(a, m) and not changed(m, b)
			var f: float = (m.t - a.t) / maxf(1e-9, b.t - a.t)
			var straight: bool = m.ease == "linear" and b.ease == "linear" and absf(lerpf(a.l, b.l, f) - m.l) < 1e-7 and absf(lerpf(a.r, b.r, f) - m.r) < 1e-7 and absf(lerpf(a.a, b.a, f) - m.a) < 1e-7
			if hold or straight:
				if hold: b.ease = "linear"
				out.remove_at(k); again = true; break
	return out

## Cross-section envelope sampled on the grid: the game draws/judges this until the engine
## supports the exact outline (kept in the sidecar).
static func approximate(s, grid_step: float) -> Array:
	var poly: PackedVector2Array = s.polygon().points
	var r: Array = s.t_range()
	var times := []
	var t: float = r[0]
	while t < r[1] - 1e-6: times.append(t); t += maxf(0.02, grid_step)
	for n in s.nodes:
		if not times.has(n.t): times.append(n.t)
	times.append(r[1])
	times.sort()
	var knots := []
	for i in times.size():
		var tt: float = times[i]
		var probe: float = clampf(tt, r[0] + 1e-4, r[1] - 1e-4)
		var env: Vector2 = s.envelope(probe, poly)
		if is_nan(env.x): env = Vector2(0.45, 0.55)
		var w := maxf(env.y - env.x, SU.KEY_UNIT * 1.05)
		var c := (env.x + env.y) / 2.0
		# keep at least one key centre inside, as the validator requires
		var nearest := clampf(roundf(c * 15.0 - 2.25), 0, 10)
		var kc := (2.25 + nearest) / 15.0
		if kc < c - w / 2.0 or kc > c + w / 2.0: c = kc
		var p: Dictionary = s.prop_at(tt)
		if knots.is_empty() or absf(knots[-1].t - tt) > 1e-6:
			knots.append({"t": tt, "l": c - w / 2.0, "r": c + w / 2.0, "ease": "linear", "a": p.a, "tint": p.tint})
	return knots

## ---------------------------------------------------------------- notes ride their track
## New u for every note on track `id` so it keeps landing on its fingering key.
static func reseat_ops(doc, id: int, lights_after: Array) -> Array:
	var c := ChartLib.validate({"lights": lights_after, "notes": []})
	var tl := ChartLib.build_timelines(c.lights)
	var ops := []
	if not tl.has(id): return ops
	for i in doc.raw.notes.size():
		var n: Dictionary = doc.raw.notes[i]
		if int(n.light) != id: continue
		var before := ChartLib.light_at(doc.core.tl.get(id, []), float(n.t))
		var st := ChartLib.light_at(tl[id], float(n.t))
		if not st.alive or not before.alive: continue
		var k := int(n.get("k", -1))
		var land: float = (2.25 + k) / 15.0 if k >= 0 else before.x + (float(n.u) - 0.5) * before.w
		var u := clampf((land - st.x) / maxf(1e-6, st.w) + 0.5, 0.0, 1.0)
		if absf(u - float(n.u)) > 1e-7: ops.append({"target": "notes", "op": "update", "index": i, "value": {"u": num(u)}})
	return ops
