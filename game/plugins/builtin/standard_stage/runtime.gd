## Chart staging engine (port of [4b] STAGE v2; design: research/STAGING_RESEARCH.md).
## Channels = clamp(base tween + impulses); the clamps are engine red lines, not chart data.
class_name BuiltinStageRuntime
extends RefCounted

const CH = BuiltinStageData.CH
const MODE = BuiltinStageData.MODE
var tw := {}
var imp := []
var rings := []
var mode := "full"
var summary := {}

var registry: PluginRegistry
var channels := {}

func configure(scope: PluginRegistry) -> void:
	registry = scope
	channels = {}
	for entry in scope.ordered("channels"):
		channels[entry.id] = [entry.default, entry.min, entry.max]

static func ease_fn(name: String, k: float) -> float:
	match name:
		"linear": return k
		"inQuad": return k * k
		"outQuad": return 1.0 - (1.0 - k) * (1.0 - k)
		"inCubic": return k * k * k
		"outCubic": return 1.0 - pow(1.0 - k, 3.0)
		"outExpo": return 1.0 if k >= 1.0 else 1.0 - pow(2.0, -10.0 * k)
		"outBack":
			var c1 := 1.2
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		_: return -(cos(PI * k) - 1.0) / 2.0          # inOutSine

# ---------------------------------------------------------------- analysis
func _analyse(chart: Dictionary) -> Dictionary:
	var tm: Array = chart.timing if not chart.timing.is_empty() else [{"t": chart.notes[0].t if not chart.notes.is_empty() else 0.0, "beat": 60.0 / chart.bpm, "meter": 4}]
	var end := 0.0
	for n in chart.notes:
		end = maxf(end, n.t + n.dur)
	end += 4.0
	var bars := []
	for i in tm.size():
		var s: Dictionary = tm[i]
		var bl: float = s.beat * s.meter
		var until: float = tm[i + 1].t - 1e-6 if i + 1 < tm.size() else end
		var t: float = s.t
		while t < until:
			bars.append({"t": t, "beat": s.beat, "len": bl})
			t += bl
	if not bars.is_empty():
		var b0: Dictionary = bars[0]
		var t: float = b0.t - b0.len
		while t > -b0.len:
			bars.push_front({"t": t, "beat": b0.beat, "len": b0.len})
			t -= b0.len
	var onsets := []
	for n in chart.notes:
		if not onsets.is_empty() and absf(n.t - onsets[-1].t) < 0.003:
			onsets[-1].w += 0.25
		else:
			onsets.append({"t": n.t, "w": 1.0})
	var nb := bars.size()
	var E := []
	var cnt := []
	E.resize(nb); E.fill(0.0); cnt.resize(nb); cnt.fill(0)
	var bi := 0
	for o in onsets:
		while bi + 1 < nb and bars[bi + 1].t <= o.t + 1e-6:
			bi += 1
		E[bi] += o.w / bars[bi].len
		cnt[bi] += 1
	var first := -1
	var last := -1
	for i in nb:
		if cnt[i] > 0:
			if first < 0: first = i
			last = i
	var sorted := []
	if first >= 0:
		for i in range(first, last + 1):
			if E[i] > 0.0: sorted.append(E[i])
	sorted.sort()
	var pct := func(q: float) -> float: return 0.0 if sorted.is_empty() else sorted[mini(sorted.size() - 1, int(floor(q * sorted.size())))]
	return {"bars": bars, "onsets": onsets, "E": E, "first": first, "last": last, "P40": pct.call(0.4), "P60": pct.call(0.6), "P75": pct.call(0.75), "meta": chart.meta}

func _bar_at(A: Dictionary, t: float) -> int:
	var lo := 0
	var hi: int = A.bars.size() - 1
	while lo < hi:
		var m := (lo + hi + 1) >> 1
		if A.bars[m].t <= t + 1e-6: lo = m
		else: hi = m - 1
	return lo

func _onset_at_or_after(A: Dictionary, t: float, within: float):
	for o in A.onsets:
		if o.t >= t - 0.02:
			return o if o.t - t <= within else null
	return null

func _onset_before(A: Dictionary, t: float):
	var r = null
	for o in A.onsets:
		if o.t < t - 0.02: r = o
		else: break
	return r

# ---------------------------------------------------------------- planning (research rules, simplified)
func _plan(chart: Dictionary) -> Array:
	var A := _analyse(chart)
	var ev := []
	if A.first < 0:
		return ev
	var tween := func(t: float, ch: String, to: float, dur: float, ease: String): ev.append({"t": t, "type": "tween", "ch": ch, "to": to, "dur": dur, "ease": ease})
	var impulse := func(t: float, ch: String, amp: float, attack: float, decay: float): ev.append({"t": t, "type": "impulse", "ch": ch, "amp": amp, "attack": attack, "decay": decay})
	var bars: Array = A.bars
	var phrase_bars := []
	var b := int(A.first)
	while b <= A.last + 1:
		phrase_bars.append(b)
		b += 4
	var phrase_e := func(b0: int) -> float:
		var s := 0.0
		var n := 0
		for i in range(b0, mini(b0 + 4, bars.size())):
			s += A.E[i]; n += 1
		return s / n if n else 0.0
	var kiai := []
	for k in A.meta.get("kiai", []):
		kiai.append([float(k.t0), float(k.t1)])
	var brks := []
	for k in A.meta.get("breaks", []):
		brks.append([float(k.t0), float(k.t1)])
	var in_k := func(t: float) -> bool:
		for k in kiai:
			if t >= k[0] - 0.05 and t < k[1]: return true
		return false
	var EXPO := {"break": 0.40, "verse": 0.70, "mid": 0.85, "chorus": 1.0}
	var labels := []
	for pb in phrase_bars:
		var t: float = bars[pb].t if pb < bars.size() else 0.0
		var e: float = phrase_e.call(pb)
		var lab := ""
		var in_brk := false
		for k in brks:
			if t >= k[0] - 0.05 and t < k[1]: in_brk = true
		if in_brk or e == 0.0: lab = "break"
		elif in_k.call(t + 0.1): lab = "chorus"
		elif not kiai.is_empty(): lab = "mid" if e >= A.P60 else "verse"
		else: lab = "chorus" if e >= A.P75 else ("mid" if e >= A.P40 else "verse")
		labels.append(lab)
	var prev_lab := ""
	for i in phrase_bars.size():
		var pb: int = phrase_bars[i]
		if pb >= bars.size(): continue
		var lab: String = labels[i]
		if lab != prev_lab: tween.call(bars[pb].t, "exposure", EXPO[lab], bars[pb].beat * 2.0, "inOutSine")
		if lab == "break" and prev_lab != "break": tween.call(bars[pb].t, "pitch", 22.0, bars[pb].len * 2.0, "inOutSine")
		if lab != "break" and prev_lab == "break": tween.call(bars[pb].t, "pitch", 0.0, bars[pb].beat * 2.0, "inOutSine")
		prev_lab = lab
	# Major candidates
	var cands := []
	for k in kiai:
		cands.append({"t": k[0], "why": "kiai", "score": 3.0})
	for i in range(1, phrase_bars.size()):
		var pb: int = phrase_bars[i]
		if pb >= bars.size(): continue
		var rise: float = EXPO[labels[i]] - EXPO[labels[i - 1]]
		if labels[i] == "chorus" and rise > 0.1: cands.append({"t": bars[pb].t, "why": "rise", "score": 2.0 + rise})
		if labels[i - 1] == "break" and labels[i] != "break": cands.append({"t": bars[pb].t, "why": "reentry", "score": 2.0})
	cands.sort_custom(func(x, y): return x.score > y.score)
	var majors := []
	for c in cands:
		if majors.size() >= 6: break
		var beat: float = bars[_bar_at(A, c.t)].beat
		var near := false
		for m in majors:
			if absf(m.t - c.t) < 16.0 * beat: near = true
		if not near: majors.append(c)
	majors.sort_custom(func(x, y): return x.t < y.t)
	for m in majors:
		var bi := _bar_at(A, m.t)
		var bar: Dictionary = bars[bi]
		var beat: float = bar.beat
		var hit = _onset_at_or_after(A, m.t - beat * 0.25, beat)
		var T: float = hit.t if hit else m.t
		var bf := maxi(A.first, bi - 4)
		var build_from: float = bars[bf].t if bf < bars.size() else T - bar.len * 4.0
		var pre := ""
		for j in phrase_bars.size():
			if phrase_bars[j] <= bi and phrase_bars[j] + 4 > bi:
				pre = labels[j - 1] if j > 0 else ""
		if pre != "break" and T - build_from > beat * 2.0:
			tween.call(build_from, "exposure", 0.70, T - build_from - beat, "inQuad")
			tween.call(build_from, "rush", 1.8, T - build_from, "inQuad")
			tween.call(build_from, "bow", 0.92, T - build_from, "inQuad")
		var before = _onset_before(A, T)
		var gap: float = T - before.t if before else 0.0
		if before and gap >= maxf(beat, 0.45) and gap <= bar.len * 2.0:
			var cs := maxf(before.t + 0.08, T - beat * 1.5)
			tween.call(cs, "exposure", 0.30, 0.08, "outQuad")
			tween.call(cs, "rush", 0.5, 0.08, "outQuad")
		impulse.call(T - 0.017, "flash", 0.12, 0.04, 0.45)
		impulse.call(T - 0.017, "zoom", 0.025, 0.04, 0.6)
		impulse.call(T - 0.017, "trauma", 0.18, 0.02, 0.4)
		impulse.call(T - 0.017, "kick", 0.5, 0.03, 0.7)
		tween.call(T, "bow", 1.1, 0.12, "outCubic"); tween.call(T + 0.12, "bow", 1.0, 0.6, "outBack")
		tween.call(T, "exposure", 1.05, 0.06, "outExpo"); tween.call(T + 0.06, "exposure", 1.0, 0.8, "outCubic")
		tween.call(T, "rush", 2.5, 0.04, "outExpo"); tween.call(T + 0.04, "rush", 1.0, 0.6, "outCubic")
		ev.append({"t": T, "type": "ring"})
		m["T"] = T
	# Minor phrase accents
	for i in range(1, phrase_bars.size()):
		var pb: int = phrase_bars[i]
		if pb >= bars.size() or labels[i] == "break": continue
		var t: float = bars[pb].t
		var bl: float = bars[pb].len
		var skip := false
		for m in majors:
			if absf(m.get("T", m.t) - t) < bl * 1.01: skip = true
		if skip: continue
		var hit = _onset_at_or_after(A, t - bars[pb].beat * 0.25, bars[pb].beat * 0.5)
		var T: float = hit.t if hit else t
		impulse.call(T - 0.017, "zoom", 0.01 if labels[i] == "chorus" else 0.007, 0.06, 0.35)
		impulse.call(T - 0.017, "kick", 0.18, 0.04, 0.4)
	# light coupling
	var tl := ChartLib.build_timelines(chart.lights)
	var last_couple := -INF
	var carriers := {}
	for nn in chart.notes:
		carriers[nn.light] = true
	var evs: Array = chart.lights.duplicate()
	evs.sort_custom(func(a, b): return a.t < b.t)
	for e in evs:
		if e.type != "sweep": continue
		# the camera follows the hand lights; of the many dynamic tracks (200+) only big slow moves, one per 2 beats
		if not carriers.has(e.id): continue          # only the lights that carry notes move the camera
		if true:
			var fr0 := ChartLib.light_at(tl[e.id], e.t - 0.01)
			if not fr0.alive or absf(e.x - fr0.x) < 0.25 or e.get("dur", 0.0) < 0.3: continue
			if e.t - last_couple < 2.0 * bars[_bar_at(A, e.t)].beat: continue
			last_couple = e.t
		var from := ChartLib.light_at(tl[e.id], e.t - 0.01)
		if not from.alive: continue
		var dx: float = e.x - from.x
		var beat: float = bars[_bar_at(A, e.t)].beat
		if e.type == "sweep":
			tween.call(e.t, "roll", clampf(8.0 * dx, -2.0, 2.0), e.dur, "inOutSine")
			tween.call(e.t, "vpx", clampf(dx * 1920.0 * 0.25, -29.0, 29.0), e.dur, "inOutSine")
			tween.call(e.t + e.dur, "roll", 0.0, beat, "inOutSine"); tween.call(e.t + e.dur, "vpx", 0.0, beat, "inOutSine")
		else:
			tween.call(e.t, "vpx", clampf(dx * 1920.0 * 0.2, -29.0, 29.0), 0.15, "outCubic")
			tween.call(e.t + 0.15, "vpx", 0.0, 0.5, "inOutSine")
	for c in ChartLib.build_cues(chart.lights, registry):
		if not c.yellow: continue
		var merged := false
		for m in majors:
			if absf(m.get("T", m.t) - c.t) < 0.3: merged = true
		if merged: continue
		impulse.call(c.t - 0.017, "flash", 0.07, 0.04, 0.35)
		impulse.call(c.t - 0.017, "zoom", 0.012, 0.04, 0.45)
		impulse.call(c.t - 0.017, "trauma", 0.08, 0.02, 0.3)
	# intro / outro
	var first_t: float = A.onsets[0].t
	var last_t := 0.0
	for n in chart.notes:
		last_t = maxf(last_t, n.t + n.dur)
	ev.append({"t": -1.0, "type": "tween", "ch": "exposure", "to": 0.25, "dur": 0.01, "ease": "linear"})
	tween.call(maxf(0.0, first_t - 2.5), "exposure", EXPO.get(labels[0], 0.7), 2.0, "inOutSine")
	tween.call(last_t + 0.3, "exposure", 0.35, 2.0, "inOutSine")
	var mj := []
	for m in majors:
		mj.append("%s@%.2f" % [m.why, m.get("T", m.t)])
	summary = {"majors": mj}
	return ev

func _lint(ev: Array, chart: Dictionary) -> Array:
	ev.sort_custom(func(a, b): return a.t < b.t)
	var out := []
	var flashes := []
	var cue_times := []
	for c in ChartLib.build_cues(chart.lights, registry):
		cue_times.append(c.t)
	for e in ev:
		if e.type == "impulse" and e.ch == "flash":
			var near := 0
			for t in flashes:
				if e.t - t < 1.0: near += 1
			if near >= 2 or (not flashes.is_empty() and e.t - flashes[-1] < 0.25): continue
			flashes.append(e.t)
		if e.type == "tween" and e.ch == "exposure" and e.to <= 0.3 and e.t > 0.0:
			var blocked := false
			for t in cue_times:
				if e.t > t - SU.APPROACH and e.t < t: blocked = true
			if blocked: continue
		out.append(e)
	return out

# ---------------------------------------------------------------- compile & evaluate
func build(chart: Dictionary) -> void:
	var events := _lint(chart.fx.duplicate() if not chart.fx.is_empty() else _plan(chart), chart)
	tw = {}
	imp = []
	rings = []
	for c in channels: tw[c] = []
	for e in events:
		var callback: Callable = registry.get_entry("events", "fx." + str(e.type)).get("compile", Callable())
		if callback.is_valid(): callback.call(self, e)
	for c in channels:
		var a: Array = tw[c]
		a.sort_custom(func(x, y): return x.t < y.t)
		for i in a.size():                               # only the last tween started counts: O(n), not O(n^2)
			if i == 0:
				a[i].from = channels[c][0]
			else:
				var p: Dictionary = a[i - 1]
				var k := clampf((a[i].t - p.t) / p.dur, 0.0, 1.0)
				a[i].from = p.from + (p.to - p.from) * ease_fn(p.ease, k)
	imp.sort_custom(func(x, y): return x.t < y.t)

func _compile_event(e: Dictionary) -> void:
	if e.type == "ring":
		rings.append(e.t); return
	if not channels.has(e.get("ch", "")): return
	if e.type == "tween":
		tw[e.ch].append({"t": e.t, "dur": maxf(1e-3, e.get("dur", 0.0)), "ease": e.get("ease", "inOutSine"), "to": e.to, "from": null})
	elif e.type == "impulse":
		var att: float = e.get("attack", 0.04)
		var dec: float = e.get("decay", 0.4)
		imp.append({"t": e.t, "ch": e.ch, "amp": e.amp, "attack": maxf(0.005, att), "tau": maxf(0.02, dec / 3.0), "end": e.t + att + dec * 1.6})

func _base(c: String, t: float, upto := -1) -> float:
	var a: Array = tw[c]
	var n := a.size() if upto < 0 else upto
	var v: float = channels[c][0]
	for i in n:
		var s: Dictionary = a[i]
		if t < s.t: break
		var k := clampf((t - s.t) / s.dur, 0.0, 1.0)
		var f: float = v if s.from == null else s.from
		v = f + (s.to - f) * ease_fn(s.ease, k)
	return v

func at(t: float) -> Dictionary:
	var st := {}
	for c in channels:
		st[c] = _base(c, t) if tw.has(c) and not tw[c].is_empty() else channels[c][0]
	for p in imp:
		if t < p.t: break
		if t > p.end: continue
		var dt: float = t - p.t
		var att := ease_fn("outExpo", clampf(dt / p.attack, 0.0, 1.0))
		var dec := 1.0 if dt <= p.attack else exp(-(dt - p.attack) / p.tau)
		st[p.ch] += p.amp * att * dec
	var m: Dictionary = MODE.get(mode, MODE.full)
	st.zoom = 1.0 + (st.zoom - 1.0) * m.zoom
	st.roll *= m.roll; st.trauma *= m.trauma; st.flash *= m.flash; st.vpx *= m.vpx; st.pitch *= m.pitch
	if mode == "off":
		st.bow = 1.0; st.rush = 1.0; st.kick = 0.0
	for c in channels:
		st[c] = clampf(st[c], channels[c][1], channels[c][2])
	return st

static func rest() -> Dictionary:
	var st := {}
	for c in CH: st[c] = CH[c][0]
	return st
