extends RefCounted
## Song timing helpers for the 歌曲设置 page. Notes, track events and camera events are stored in
## chart seconds, so editing the tempo map only moves the grid. These functions build the explicit
## follow-up edits: re-time everything from an old grid to a new one (musical positions kept), or
## shift the whole chart together with the audio.

const Ops = preload("res://edit_ops.gd")

## Sorted tempo segments with the beat count where each one starts.
static func segments(timing: Array) -> Array:
	var out := []
	for s in timing: out.append({"t": float(s.t), "beat": float(s.beat), "meter": int(s.get("meter", 4))})
	out.sort_custom(func(a, b): return a.t < b.t)
	var beats := 0.0
	for i in out.size():
		if i > 0: beats += (out[i].t - out[i - 1].t) / out[i - 1].beat
		out[i]["beats"] = beats
	return out

## Continuous beat count at chart time t (before the first segment: extrapolated backwards).
static func beats_at(segs: Array, t: float) -> float:
	var s: Dictionary = segs[0]
	for x in segs:
		if x.t <= t: s = x
	return s.beats + (t - s.t) / s.beat

static func time_at(segs: Array, b: float) -> float:
	var s: Dictionary = segs[0]
	for x in segs:
		if x.beats <= b: s = x
	return s.t + (b - s.beats) * s.beat

static func map_time(old_segs: Array, new_segs: Array, t: float) -> float:
	return time_at(new_segs, beats_at(old_segs, t))

static func _num(v: float) -> float:
	return snappedf(v, 0.0001)

## A copy of raw whose notes, track events and camera events keep their musical position (beat)
## when the tempo map changes from old_timing to new_timing. Durations are re-timed by their ends.
static func retime(raw: Dictionary, old_timing: Array, new_timing: Array) -> Dictionary:
	var a := segments(old_timing); var b := segments(new_timing)
	var out := raw.duplicate(true)
	var m := func(t: float) -> float: return map_time(a, b, t)
	for target in ["notes", "lights", "fx"]:
		for e in out.get(target, []):
			if not e is Dictionary or not e.has("t"): continue
			# round the mapped start and end, then take the difference, so events that touched
			# before (a sweep ending where the next begins) still touch exactly
			var t0 := float(e.t)
			var nt: float = _num(maxf(0.0, m.call(t0)))
			for k in ["dur", "attack", "decay"]:
				if e.has(k) and (e[k] is float or e[k] is int) and float(e[k]) > 0.0:
					e[k] = _num(maxf(0.001, _num(m.call(t0 + float(e[k]))) - nt))
			e["t"] = nt
	for k in ["kiai", "breaks"]:
		var list = out.get("meta", {}).get(k, [])
		if list is Array:
			for span in list:
				if span is Dictionary:
					for f in ["t0", "t1", "t"]:
						if span.has(f): span[f] = _num(maxf(0.0, m.call(float(span[f]))))
	return out

## Everything on the chart clock moves by d seconds together with the audio (offset += d).
static func shift(raw: Dictionary, d: float) -> Dictionary:
	var out := raw.duplicate(true)
	for target in ["notes", "lights", "fx"]:
		for e in out.get(target, []):
			if e is Dictionary and e.has("t"):
				if float(e.t) + d < 0.0: return {"error": "平移后有事件会落到 0 秒之前，请把平移量调小"}
				e["t"] = _num(float(e.t) + d)
	for s in out.get("timing", []): s["t"] = _num(float(s.t) + d)
	out["offset"] = _num(float(out.get("offset", 0.0)) + d)
	if out.get("meta", {}).get("breath", {}) is Dictionary and out.get("meta", {}).get("breath", {}).has("t0"):
		out.meta.breath.t0 = _num(float(out.meta.breath.t0) + d)
	for k in ["kiai", "breaks"]:
		var list = out.get("meta", {}).get(k, [])
		if list is Array:
			for span in list:
				if span is Dictionary:
					for f in ["t0", "t1", "t"]:
						if span.has(f): span[f] = _num(maxf(0.0, float(span[f]) + d))
	return out

## Note motions in chart.ext.json are keyed by note time; carry them over to the moved notes.
static func rekey_motions(ext: Dictionary, before: Array, after: Array) -> Dictionary:
	var out := ext.duplicate(true)
	if out.get("motions", {}).is_empty(): return out
	var moved := {}
	for i in mini(before.size(), after.size()):
		var k := Ops.motion_key(before[i])
		if out.motions.has(k): moved[Ops.motion_key(after[i])] = out.motions[k]
	out.motions = moved
	return out

static func bpm_text(timing: Array) -> String:
	var s := segments(timing)
	return "%s BPM，第一拍 %.3f 秒" % [String.num(60.0 / s[0].beat, 2), s[0].t] if not s.is_empty() else ""
