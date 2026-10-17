## Chart format, validation, light timelines and cues (port of [2] CHART).
class_name BuiltinChartRuntime

## chart syntax v2 (lean): lights are on | sweep | pulse | off.  Legacy "jump" loads as a 0.09 s ease-out sweep.
const TYPES = BuiltinChartData.TYPES
const FROMS = BuiltinChartData.FROMS
const DEAD = BuiltinChartData.DEAD

static func centers(x: float, w: float) -> int:
	return KB.centers_in(x - w / 2.0, x + w / 2.0)

# ---------------------------------------------------------------- timelines (pure function of time)
static func build_timelines(events: Array, scope: PluginRegistry = null) -> Dictionary:
	var registry := scope if scope != null else PluginRegistry.builtins()
	var by := {}
	for e in events:
		if not by.has(e.id):
			by[e.id] = []
		by[e.id].append(e)
	var tl := {}
	for id in by:
		var arr: Array = by[id].duplicate()
		arr.sort_custom(func(a, b): return a.t < b.t)
		var prev := {"x": 0.5, "w": 0.2, "reach": 1.0}
		var prev_y := 0.0
		var segs := []
		var context := {"segments": segs, "previous": prev, "previous_yellow": prev_y}
		for e in arr:
			var callback: Callable = registry.get_entry("events", str(e.type)).get("compile", Callable())
			if not callback.is_valid(): continue
			context.event = e
			callback.call(context)
		tl[id] = segs
	return tl

static func compile_light(context: Dictionary) -> void:
	var e: Dictionary = context.event
	var segs: Array = context.segments
	var prev: Dictionary = context.previous
	var prev_y: float = context.previous_yellow
	if e.type == "off":
		segs.append({"t": e.t, "type": "off", "from": prev, "to": prev, "dur": 0.0, "prevYellow": prev_y, "yellow": prev_y})
		return
	if e.type == "pulse":
		var yp := 1.0 if e.get("from", "LR") == "LR" else 0.0
		segs.append({"t": e.t, "type": "pulse", "from": prev, "to": prev, "dur": 0.0, "prevYellow": prev_y, "yellow": yp})
		context.previous_yellow = yp
		return
	var to := {"x": e.x, "w": e.w, "reach": 1.0, "tint": int(e.get("tint", prev.get("tint", -1))), "a": float(e.get("a", prev.get("a", -1.0)))}
	var yel := 1.0 if e.get("from", "LR") == "LR" else 0.0
	segs.append({"t": e.t, "type": e.type, "from": prev, "to": to, "dur": e.get("dur", 0.0), "prevYellow": prev_y, "yellow": yel, "ease": e.get("ease", "inout")})
	context.previous = to
	context.previous_yellow = yel

static func light_at(segs, t: float, scope: PluginRegistry = null) -> Dictionary:
	if segs == null or segs.is_empty():
		return DEAD
	# 2026-10-17: timelines are sorted at build time. Preserve the last <=
	# sample (including tied timestamps and the original epsilon) when seeking.
	var lo := 0
	var hi: int = segs.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if segs[mid].t <= t + 1e-9: lo = mid + 1
		else: hi = mid
	var i := lo - 1
	if i < 0:
		return DEAD
	var registry := scope if scope != null else PluginRegistry.builtins()
	var callback: Callable = registry.get_entry("events", str(segs[i].type)).get("sample", Callable())
	return callback.call(segs[i], t) if callback.is_valid() else DEAD

static func sample_light(s: Dictionary, t: float) -> Dictionary:
	var dt: float = t - s.t
	var g: Dictionary = s.to
	var alpha := 1.0
	match s.type:
		"on":
			var k := clampf(dt / 0.2, 0.0, 1.0)
			alpha = k * k * (3.0 - 2.0 * k)
		"sweep":
			var k := SU.ease_by(s.get("ease", "inout"), dt / s.dur)
			g = {"x": lerpf(s.from.x, s.to.x, k), "w": lerpf(s.from.w, s.to.w, k), "reach": lerpf(s.from.reach, s.to.reach, k)}
		"off":
			g = s.from
			alpha = 1.0 - dt / 0.2
			if alpha <= 0.0:
				return DEAD
	var yellow: float = s.prevYellow if s.type == "off" else lerpf(s.prevYellow, s.yellow, clampf(dt / 0.25, 0.0, 1.0))
	var op: float = s.to.get("a", -1.0)
	if s.type == "sweep" and op >= 0.0 and s.from.get("a", -1.0) >= 0.0:
		op = lerpf(s.from.a, op, SU.ease_by(s.get("ease", "inout"), dt / s.dur))
	return {"alive": true, "x": g.x, "w": g.w, "reach": g.reach, "alpha": alpha, "yellow": yellow, "tint": s.to.get("tint", -1), "a": op,
		"pulse": 0.0 if s.type == "off" else maxf(0.0, 1.0 - dt / 0.25)}

## note staging: "grow" = [scale when it appears, scale at the line] (e.g. [0.3, 1] small -> big); "wl" = width as a
## fraction of its light (the note scales with the light).  Both are visual only.
static func _grow_of(v) -> Array:
	if typeof(v) != TYPE_ARRAY or v.size() != 2: return []
	return [clampf(SU.num(v[0], 1.0), 0.1, 3.0), clampf(SU.num(v[1], 1.0), 0.1, 3.0)]

static func build_cues(events: Array, scope: PluginRegistry = null) -> Array:
	var registry := scope if scope != null else PluginRegistry.builtins()
	var map := {}
	for e in events:
		if not registry.get_entry("events", str(e.type)).get("pedal", false) or e.get("auto", false):
			continue
		var k := int(round(e.t * 10000.0))
		if not map.has(k):
			map[k] = {"t": e.t, "from": "", "dur": 0.0, "lights": []}
		var c: Dictionary = map[k]
		c.lights.append(e.id)
		if registry.get_entry("events", str(e.type)).get("cue_duration", false):
			c.dur = maxf(c.dur, e.dur)
		if e.get("from", "LR") == "LR":
			c.from = "LR"
		elif c.from == "":
			c.from = e.get("from", "L")
	var out := map.values()
	out.sort_custom(func(a, b): return a.t < b.t)
	for c in out:
		c["yellow"] = c.from == "LR"
	return out

# ---------------------------------------------------------------- validation (SPEC §5)
static func validate(raw, scope: PluginRegistry = null) -> Dictionary:
	var registry := scope if scope != null else PluginRegistry.builtins()
	var warns := []
	if typeof(raw) == TYPE_STRING:
		raw = JSON.parse_string(raw)
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out := {"bpm": SU.num(raw.get("bpm"), 120.0), "offset": SU.num(raw.get("offset"), 0.0), "timing": [], "fx": [],
		"meta": raw.get("meta", {}) if typeof(raw.get("meta")) == TYPE_DICTIONARY else {}, "lights": [], "notes": [], "warnings": warns}
	# legacy: a separate meta.twitch list becomes meta.mod entries (one place for every visual modulation)
	if out.meta.has("twitch"):
		var mods: Array = out.meta.get("mod", []).duplicate()
		for tw in out.meta.twitch:
			mods.append({"t0": float(tw[0]), "t1": float(tw[0]) + 0.5, "kind": "twitch", "dir": float(tw[1])})
		out.meta = out.meta.duplicate(); out.meta.erase("twitch"); out.meta["mod"] = mods
	for s in raw.get("timing", []):
		if typeof(s) == TYPE_DICTIONARY and SU.num(s.get("beat"), 0.0) > 0.0:
			out.timing.append({"t": float(s.t), "beat": float(s.beat), "meter": int(SU.num(s.get("meter"), 4.0))})
	for e in raw.get("fx", []):
		if typeof(e) == TYPE_DICTIONARY and e.has("t") and e.has("type"):
			out.fx.append(e)

	var evs := []
	var li := 0
	for e in raw.get("lights", []):
		if typeof(e) == TYPE_DICTIONARY:
			evs.append({"e": e, "i": li})
		li += 1
	evs.sort_custom(func(a, b): return a.e.get("t", 0.0) < b.e.get("t", 0.0) if a.e.get("t", 0.0) != b.e.get("t", 0.0) else a.i < b.i)
	var S := {}
	for it in evs:
		var e: Dictionary = it.e
		var tag := "lights[%d] (t=%s, id=%s, %s)" % [it.i, str(e.get("t")), str(e.get("id")), str(e.get("type"))]
		var t := SU.num(e.get("t"), -1.0)
		if t < 0.0:
			warns.append(tag + ": bad t"); continue
		var id := int(SU.num(e.get("id"), -1.0))
		if id < 0:
			warns.append(tag + ": bad id"); continue
		var ty: String = str(e.get("type", ""))
		var legacy_jump := ty == "jump"
		if legacy_jump: ty = "sweep"
		var provider := registry.get_entry("events", ty)
		var callback: Callable = provider.get("validate", Callable())
		if not callback.is_valid():
			warns.append(tag + ": unknown type"); continue
		callback.call({"raw": e, "tag": tag, "t": t, "id": id, "type": ty, "legacy_jump": legacy_jump,
			"states": S, "chart": out, "warnings": warns})

	var tl := build_timelines(out.lights, registry)
	var iv := {}
	for e in out.lights:
		if not iv.has(e.id):
			iv[e.id] = []
		if registry.get_entry("events", str(e.type)).get("opens", false):
			iv[e.id].append({"a": e.t, "b": INF})
		elif registry.get_entry("events", str(e.type)).get("closes", false) and not iv[e.id].is_empty():
			iv[e.id][-1].b = e.t
	var alive_over := func(id: int, t0: float, t1: float) -> bool:
		for r in iv.get(id, []):
			if t0 >= r.a - SU.EPS and t1 <= r.b + SU.EPS:
				return true
		return false

	var cand := []
	var ni := 0
	for n in raw.get("notes", []):
		var i := ni
		ni += 1
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var tag := "notes[%d] (t=%s)" % [i, str(n.get("t"))]
		var t := SU.num(n.get("t"), -1.0)
		if t < 0.0:
			warns.append(tag + ": bad t"); continue
		var lid := int(SU.num(n.get("light"), -1.0))
		if not tl.has(lid):
			warns.append(tag + ": unknown light"); continue
		var u := SU.num(n.get("u"), -1.0)
		if u < 0.0 or u > 1.0:
			warns.append(tag + ": u must be in [0,1]"); continue
		var kind: String = str(n.get("kind", ""))
		if registry.get_entry("note_kinds", kind).is_empty():
			warns.append(tag + ": kind must be tap|hold"); continue
		var dur := 0.0
		if registry.get_entry("note_kinds", kind).get("holds", false):
			dur = SU.num(n.get("dur"), 0.0)
			if dur <= 0.0:
				warns.append(tag + ": hold needs dur > 0"); continue
		if not alive_over.call(lid, t, t + dur):
			warns.append(tag + ": light is not alive over the note"); continue
		var nw := clampf(SU.num(n.get("nw"), 1.0), 0.5, 10.0)
		var path := []
		if registry.get_entry("note_kinds", kind).get("holds", false) and typeof(n.get("path")) == TYPE_ARRAY:
			for q in n.path:
				if typeof(q) == TYPE_ARRAY and q.size() >= 3:
					path.append([clampf(SU.num(q[0], 0.0), 0.0, dur), clampf(SU.num(q[1], u), 0.0, 1.0), clampf(SU.num(q[2], nw), 0.5, 10.0)])
			path.sort_custom(func(x, y): return x[0] < y[0])
		var kk := int(SU.num(n.get("k"), -1.0))
		cand.append({"t": t, "light": lid, "u": u, "kind": kind, "dur": dur, "_i": i, "nw": nw, "path": path, "k": kk if kk >= 0 and kk <= 10 else -1})
		for flag in registry.ordered("flags"):
			var normalize: Callable = flag.get("normalize", Callable())
			if normalize.is_valid(): normalize.call(n, cand[-1])
		var normalize_kind: Callable = registry.get_entry("note_kinds", kind).get("normalize", Callable())
		if normalize_kind.is_valid(): normalize_kind.call(n, cand[-1])
	# chord rules
	var groups := {}
	for n in cand:
		var k := str(n.light) + "|" + str(int(round(n.t * 1000.0)))
		if not groups.has(k):
			groups[k] = []
		groups[k].append(n)
	for grp in groups.values():
		grp.sort_custom(func(a, b): return a.u < b.u if a.u != b.u else a._i < b._i)
		var acc := []
		for n in grp:
			var st := light_at(tl[n.light], n.t, registry)
			var lx: float = st.x + (n.u - 0.5) * st.w
			if acc.size() >= 3:
				warns.append("notes[%d]: chord larger than 3" % n._i); continue
			var close := false
			for a in acc:
				if absf(a.lx - lx) < SU.KEY_UNIT - 1e-4:
					close = true
			if close:
				warns.append("notes[%d]: chord notes closer than one key" % n._i); continue
			if centers(st.x, st.w) < acc.size() + 1:
				warns.append("notes[%d]: fewer key centres than chord notes" % n._i); continue
			acc.append({"n": n, "lx": lx})
		for a in acc:
			out.notes.append({"t": a.n.t, "light": a.n.light, "u": a.n.u, "kind": a.n.kind, "dur": a.n.dur, "big": a.n.big, "nw": a.n.nw, "path": a.n.path,
				"k": a.n.k, "ex": a.n.ex, "grow": a.n.grow, "wl": a.n.wl})
			for key in a.n:
				if key != "_i" and not out.notes[-1].has(key): out.notes[-1][key] = a.n[key]
	out.notes.sort_custom(func(a, b):
		if a.t != b.t: return a.t < b.t
		if a.light != b.light: return a.light < b.light
		return a.u < b.u)
	if not warns.is_empty():
		push_warning("[chart] %d warnings, first: %s" % [warns.size(), warns[0]])
	return out

## Standard light event validator, installed through the event registry.
static func validate_light(context: Dictionary) -> void:
	var e: Dictionary = context.raw
	var tag: String = context.tag
	var t: float = context.t
	var id: int = context.id
	var ty: String = context.type
	var legacy_jump: bool = context.legacy_jump
	var S: Dictionary = context.states
	var out: Dictionary = context.chart
	var warns: Array = context.warnings
	if not S.has(id):
		S[id] = {"alive": false, "geom": null, "sweepEnd": -INF}
	var s: Dictionary = S[id]
	if t < s.sweepEnd - SU.EPS:
		warns.append(tag + ": starts inside the previous sweep"); return
	if ty == "off":
		if not s.alive:
			warns.append(tag + ": light is not alive"); return
		s.alive = false
		s.sweepEnd = -INF
		out.lights.append({"t": t, "id": id, "type": "off", "auto": e.get("auto", false) == true})
		return
	if ty == "on":
		if s.alive:
			warns.append(tag + ": light is already alive"); return
	elif not s.alive:
		warns.append(tag + ": light is not alive"); return
	var from: String = e.get("from", "LR") if e.get("from", "LR") in FROMS else "LR"   # matters on pedal cues only
	if ty == "pulse":
		out.lights.append({"t": t, "id": id, "type": "pulse", "from": from, "auto": e.get("auto", false) == true})
		return
	var x := SU.num(e.get("x"), NAN)
	var w := SU.num(e.get("w"), NAN)
	if is_nan(x) or is_nan(w):
		warns.append(tag + ": x/w must be numbers"); return
	if w < SU.KEY_UNIT - 1e-4:
		warns.append(tag + ": w < one key width"); return
	if x - w / 2.0 < -SU.LIGHT_OVER - 1e-6 or x + w / 2.0 > 1.0 + SU.LIGHT_OVER + 1e-6:   # may spill past the edges a little
		warns.append(tag + ": interval leaves the line"); return
	var dur := 0.0
	var ease_name := "out" if legacy_jump else str(e.get("ease", "inout"))
	if not ease_name in SU.EASES: ease_name = "inout"
	if ty == "sweep":
		dur = 0.09 if legacy_jump else SU.num(e.get("dur"), 0.0)
		if dur <= 0.0:
			warns.append(tag + ": sweep needs dur > 0"); return
	var bad := false
	if ty == "sweep":
		var a: Dictionary = s.geom
		var n := int(ceil(dur / 0.05 - 1e-9))
		for k in n + 1:
			var tt := minf(k * 0.05, dur)
			var f := SU.ease_by(ease_name, tt / dur)
			if centers(lerpf(a.x, x, f), lerpf(a.w, w, f)) < 1:
				bad = true; break
	elif centers(x, w) < 1:
		bad = true
	if bad:
		warns.append(tag + ": no key centre inside the light"); return
	var ev := {"t": t, "id": id, "type": ty, "from": from, "x": x, "w": w, "reach": 1.0, "auto": e.get("auto", false) == true}
	if dur > 0.0:
		ev["dur"] = dur
		if ease_name != "inout": ev["ease"] = ease_name
	if e.has("tint"): ev["tint"] = clampi(int(SU.num(e.get("tint"), -1.0)), -1, 9)
	if e.has("a"): ev["a"] = clampf(SU.num(e.get("a"), 1.0), 0.0, 1.0)      # track opacity (v3)
	out.lights.append(ev)
	s.alive = true
	s.geom = {"x": x, "w": w}
	s.sweepEnd = t + dur if dur > 0.0 else -INF


# ---------------------------------------------------------------- demo chart (synth track: 120 BPM, 128 beats, 2 s lead-in)
# Written on the physical home row with the hands split at the G|H gap: left light in [0.75, 5.75] units
# (.. A S D F), right in [7.75, 12.75] (J K L ; '); G and H stay empty.
static func demo() -> Dictionary:
	var B := 0.5
	var T0 := 2.0
	var U := 1.0 / 15.0
	var lights := []
	var notes := []
	var zone := {}
	var KI := {"A": 0, "S": 1, "D": 2, "F": 3, "J": 6, "K": 7, "L": 8, ";": 9, "'": 10}
	var tt := func(b: float) -> float: return T0 + b * B
	var ev := func(b: float, id: int, type: String, from: String, edge := 0.0, wk := 0.0, dur_b := 0.0):
		var e := {"t": tt.call(b), "id": id, "type": type, "from": from}
		if type != "pulse":
			e.x = (edge + wk / 2.0) * U; e.w = wk * U
			zone[id] = [edge, wk]
		if dur_b > 0.0:
			e.dur = dur_b * B
			if dur_b < 0.25: e.ease = "out"                   # a quick reach (what used to be a "jump")
		lights.append(e)
	var off := func(b: float, id: int): lights.append({"t": tt.call(b), "id": id, "type": "off"})
	var n := func(b: float, key: String, dur_b := 0.0):
		var id := 0 if KI[key] <= 3 else 1
		var z: Array = zone[id]
		var o := {"t": tt.call(b), "light": id, "u": (2.25 + KI[key] - z[0]) / z[1], "kind": "hold" if dur_b > 0.0 else "tap"}
		if dur_b > 0.0:
			o.dur = dur_b * B
		notes.append(o)
	var seq := func(b0: float, step: float, keys: String):
		var ks := keys.split(" ")
		for i in ks.size():
			if ks[i] != ".":
				n.call(b0 + i * step, ks[i])
	var HL := 1.75
	var HR := 7.75
	# 1 (0-16) one hand at a time
	ev.call(0, 0, "on", "L", HL, 4); seq.call(2, 1, "D F D F D"); n.call(6.5, "F"); n.call(7, "D")
	ev.call(8, 1, "on", "R", HR, 4); seq.call(10, 1, "J K J K J"); n.call(14.5, "K"); n.call(15, "J")
	# 2 (16-32) alternation; gold cue moves both lights outward
	ev.call(16, 0, "pulse", "LR"); ev.call(16, 1, "pulse", "LR")
	seq.call(17, 0.5, "F J D K F J D K F J D K F")
	ev.call(24, 0, "sweep", "LR", 0.75, 5, 0.18); ev.call(24, 1, "sweep", "LR", HR, 5, 0.18)        # widen outward, inner edges stay at F / J
	seq.call(25, 0.5, "D K S L D K S L D K S L D")
	# 3 (32-48) chords, holds, a triple
	ev.call(32, 0, "sweep", "LR", HL, 4, 0.18); ev.call(32, 1, "sweep", "LR", HR, 4, 0.18)
	for b in [33, 35]:
		n.call(b, "D"); n.call(b, "F")
	for b in [34, 36]:
		n.call(b, "J"); n.call(b, "K")
	n.call(37, "F", 2); seq.call(37, 0.5, "J K J K")
	n.call(40, "J", 2); seq.call(40, 0.5, "D S D F")
	n.call(43, "D"); n.call(43, "F"); n.call(43, "J"); n.call(43, "K")
	seq.call(44, 0.5, "S D F . J K L")
	n.call(47, "S"); n.call(47, "D"); n.call(47, "F")
	# 4 (48-64) sweeps
	ev.call(48, 0, "sweep", "L", 0.75, 5, 4)
	seq.call(49, 0.5, "J K L K J K L")
	seq.call(53, 0.5, "S A S A S")
	ev.call(56, 0, "sweep", "LR", HL, 4, 4); ev.call(56, 1, "sweep", "LR", HR, 5, 4)
	seq.call(61, 0.5, "F K D L F")
	# 5 (64-80) one-key lights, then two keys per hand
	ev.call(64, 0, "sweep", "LR", 4.75, 1, 0.18); ev.call(64, 1, "sweep", "LR", 7.75, 1, 0.18)
	seq.call(65, 0.5, "F J F J F . F J F J J . F")
	ev.call(72, 0, "sweep", "LR", 3.75, 2, 0.18); ev.call(72, 1, "sweep", "LR", 7.75, 2, 0.18)
	seq.call(73, 0.5, "D F J K")
	n.call(75, "D"); n.call(75, "F"); n.call(76, "J"); n.call(76, "K")
	seq.call(77, 0.5, "F D K J F")
	# 6 (80-96) wide lights, holds under one hand, finger rolls
	ev.call(80, 0, "sweep", "LR", 0.75, 5, 0.18); ev.call(80, 1, "sweep", "LR", HR, 5, 0.18)
	n.call(81, "D", 3); seq.call(81, 0.5, "J K L K J")
	n.call(85, "K", 3); seq.call(85, 0.5, "F D S D F")
	seq.call(89, 0.5, "F D S A J K L ;")
	n.call(93, "D"); n.call(93, "F"); n.call(93, "J"); n.call(93, "K")
	seq.call(94, 0.5, "S D F")
	# 7 (96-128) climax and lights out
	ev.call(96, 0, "sweep", "LR", HL, 4, 0.18); ev.call(96, 1, "sweep", "LR", HR, 4, 0.18)
	n.call(97, "D"); n.call(97, "F"); n.call(97, "J"); n.call(97, "K")
	seq.call(97.5, 0.5, "J F K D J F K D J F K")
	n.call(103, "S"); n.call(103, "D"); n.call(103, "F")
	ev.call(104, 0, "pulse", "L")
	seq.call(105, 0.25, "D F D F"); seq.call(106, 0.25, "J K J K")
	n.call(107, "S"); n.call(107, "D"); n.call(107, "F"); n.call(108, "J"); n.call(108, "K"); n.call(108, "L")
	seq.call(109, 0.5, "F J D K")
	n.call(111, "D"); n.call(111, "F"); n.call(111, "J"); n.call(111, "K")
	ev.call(112, 0, "sweep", "LR", 0.75, 5, 0.18); ev.call(112, 1, "sweep", "LR", HR, 5, 0.18)
	seq.call(113, 0.5, "A S D F J K L ; F D S A")
	for k in ["S", "D", "F", "J", "K", "L"]:
		n.call(119, k)
	n.call(120, "D", 4); n.call(120, "K", 4)
	off.call(126, 0); off.call(126, 1)
	return {"bpm": 120, "offset": 0.0, "lights": lights, "notes": notes,
		"timing": [{"t": 2.0, "beat": 0.5, "meter": 4}]}
