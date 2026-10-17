## Judgement state machine (port of [4] GAME): cues, notes, holds, autoplay, scoring.
class_name BuiltinGameRuntime
extends RefCounted

signal ripple(xl: float, level: float)
signal judged(grade: String, xl: float, dt: float)
signal cue_judged(cue: Dictionary, grade: String)
signal pressed(code: String, xl: float)
signal hold_end(note: Dictionary)
signal combo_break(combo: int)
signal finished(stats: Dictionary)

var chart := {}
var tl := {}
var ids := []
var notes := []
var cues := []
var chords := []
var end_time := 0.0
var stats := {}
var down := {}                # code -> {ts, note}
var space_down := false
var space_cue = null
var rel := []
var hit_log := []
var strays := []               # presses that found no note (play log: where the misses come from)
var autoplay := false
var playing := false
var clock_now := 0.0           # last time seen by update() (for hit log ages)
var stage := StageFx.new()
var cut_windows:
	get: return GameCore.cut_windows
var cluster_guard:
	get: return GameCore.cluster_guard
var cut_same_track:
	get: return GameCore.cut_same_track
var cut_by_landing:
	get: return GameCore.cut_by_landing
var fifo_compensate:
	get: return GameCore.fifo_compensate
var regrade_enabled:
	get: return GameCore.regrade
var snap_enabled:
	get: return GameCore.snap
var cluster_s:
	get: return GameCore.cluster_s
var cluster_reach:
	get: return GameCore.cluster_reach
var _hits := []                        # recent hits / slap keys: {ts, t, cx} (slap guard)
var autoplay_extra := 0               # autoplay slap test: 1 = every note also gets a neighbouring key in its track
var autoplay_extra_ms := 0.0          # ... pressed this many ms after the note's own key (negative: before it)
var debug_blocked := []             # presses the slap guard held back (tests/replay_log.gd prints them with DBG=1)
var xp := []                          # extra presses queued by autoplay

var registry: PluginRegistry
var _chart_provider: Script
var _hold_kinds := {}
var _geometry := {}
var _custom_geometry := false
var pipeline: RulePipeline

func configure(scope: PluginRegistry) -> void:
	registry = scope
	_custom_geometry = scope.records.get("track_geometry", {}).size() > 1
	_chart_provider = scope.service_script("chart")
	for provider in scope.ordered("track_geometry"):
		_geometry[provider.id] = provider.get("sections", Callable())
	for kind in scope.ordered("note_kinds"):
		_hold_kinds[kind.id] = kind.get("holds", false)
	pipeline = RulePipeline.new(scope)
	stage = StageFx.new(scope)

const MIN_OVERLAP = BuiltinGameData.MIN_OVERLAP

func _new_stats(total: int) -> Dictionary:
	return {"CRITICAL": 0, "PERFECT": 0, "GREAT": 0, "GOOD": 0, "MISS": 0, "combo": 0, "maxCombo": 0, "total": total, "judged": 0,
		"accuracy": 0.0, "accuracyLive": 0.0, "score": 0, "fast": 0, "slow": 0}

func _recalc() -> void:
	var s := stats
	var sc: float = s.PERFECT + SU.CREDIT_GREAT * s.GREAT + SU.CREDIT_GOOD * s.GOOD
	s.judged = s.PERFECT + s.GREAT + s.GOOD + s.MISS
	s.accuracy = sc / s.total if s.total else 0.0
	s.accuracyLive = sc / s.judged if s.judged else 0.0
	# CHUNITHM-style: 1,000,000 for all PERFECT, up to +10,000 for CRITICAL timing (max 1,010,000)
	s.score = int(round(1e6 * sc / s.total + 1e4 * s.CRITICAL / s.total)) if s.total else 0

func _log_hit(dt: float, grade: String) -> void:
	hit_log.append({"dt": dt, "grade": grade, "at": clock_now})
	if hit_log.size() > 48: hit_log.pop_front()
	if grade != "MISS" and absf(dt) > SU.WIN_CRITICAL:
		if dt < 0.0: stats.fast += 1
		else: stats.slow += 1

func _count(grade: String, d: int, crit := false) -> void:
	stats[grade] += d
	if crit: stats.CRITICAL += d
	_recalc()

func _combo_for(grade: String) -> void:
	if grade == "MISS":
		if stats.combo >= 10: combo_break.emit(stats.combo)
		stats.combo = 0
	else:
		stats.combo += 1
		stats.maxCombo = maxi(stats.maxCombo, stats.combo)

static func grade_of(d: float) -> String:
	if d <= SU.WIN_PERFECT + 1e-9: return "PERFECT"
	if d <= SU.WIN_GREAT + 1e-9: return "GREAT"
	return "GOOD"

# ---------------------------------------------------------------- loading
func load_chart(raw) -> bool:
	var c := ChartLib.validate(raw, registry)
	if c.is_empty():
		return false
	chart = c
	stage.build(c)
	tl = _build_timelines(c.lights)
	ids = tl.keys()
	ids.sort()
	var end := 0.0
	for e in c.lights:
		end = maxf(end, e.t + e.get("dur", 0.0) + float(registry.get_entry("events", str(e.type)).get("tail", 0.0)))
	for n in c.notes:
		end = maxf(end, n.t + n.dur)
	end_time = end + 1.4
	reset_run()
	return true

func reset_run() -> void:
	notes = []
	var i := 0
	for n in chart.notes:
		notes.append({"id": i, "t": n.t, "light": n.light, "u": n.u, "kind": n.kind, "dur": n.dur, "state": "pending",
			"grade": "", "headGrade": "", "key": "", "lineX": -1.0, "hitDt": 0.0, "hitX": -1.0, "auto": false, "crit": false,
			"big": n.get("big", false), "nw": n.get("nw", 1.0), "path": n.get("path", []), "k": n.get("k", -1),
			"ex": n.get("ex", false), "grow": n.get("grow", []), "wl": n.get("wl", 0.0)})
		for key in n:
			if not notes[-1].has(key): notes[-1][key] = n[key]
		i += 1
	cues = []
	i = 0
	for q in _chart_provider.build_cues(chart.lights, registry):
		cues.append({"id": i, "t": q.t, "from": q.from, "dur": q.dur, "lights": q.lights, "yellow": q.yellow, "state": "pending",
			"grade": "", "headGrade": "", "auto": false, "crit": false})
		i += 1
	var ticks := 0
	var step := SU.hold_tick(float(chart.get("bpm", 120.0)))
	for n in notes:
		n["ticks"] = []; n["tick_i"] = 0; n["gap_t"] = -1.0; n["held_t"] = -INF; n["gap"] = 0.0; n["held_since"] = false; n["last_ts"] = n.t
		if _hold_kinds.get(n.kind, false):
			var j := 1
			while n.t + j * step <= n.t + n.dur - step / 2.0 + 1e-9:      # no tick in the last half step: letting go there is free
				n.ticks.append(n.t + j * step); j += 1
			if n.ticks.is_empty(): n.ticks.append(n.t + n.dur / 2.0)
			ticks += n.ticks.size()
	stats = _new_stats(notes.size() + ticks + cues.size())
	down.clear()
	space_down = false
	space_cue = null
	rel.clear()
	xp.clear()
	hit_log.clear()
	strays.clear()
	_hits.clear()
	chords = []
	var grp := []
	for n in notes:
		if not grp.is_empty() and absf(n.t - grp[0].t) > 0.002:
			if grp.size() > 1: chords.append(grp)
			grp = []
		grp.append(n)
	if grp.size() > 1: chords.append(grp)
	for g in chords:
		for n in g:
			n["chord"] = true; n["sibs"] = g
	pipeline.run("reset", {"runtime": self})

## CHUNITHM's 縦連判定: when one key can reach two notes landing apart, the windows meet at the midpoint -- the
## earlier note's late side and the later note's early side are cut there, whatever has been hit already.  So a
## press in the earlier note's half never goes to the later one (a fat-fingered second key after a hit is a stray),
## and an early press there does not snap onto it either.
func _cut_windows() -> void:
	var span := []
	for n in notes:
		n["w_e"] = SU.WIN_GOOD; n["w_l"] = SU.WIN_GOOD; n["snap_from"] = -INF
		var st := _light_at(tl[n.light], n.t + 1e-4) if tl.has(n.light) else {"alive": false}
		var sections := _sections(st)
		# 2026-10-18 (owner's real play: 40 of 52 MISSes were in-track presses turned stray): on a lane the cut looks at
		# where each note lands (one key wide), not at the whole track -- on a wide shared track a left-hand note and a
		# right-hand note no longer cut each other's windows. Shaped tracks keep their sections.
		if cut_by_landing and sections.size() == 1 and str(st.get("geometry", "lane")) == "lane":
			var lx: float = st.x + (float(n.u) - 0.5) * st.w
			sections = [[lx - 0.5 / 15.0, lx + 0.5 / 15.0]]
		span.append(sections)
	if not cut_windows: return
	var reach := 2.0 * maxf(SU.WIN_GOOD, SU.SNAP_EARLY)
	for i in notes.size():
		var a: Dictionary = notes[i]
		if span[i].is_empty(): continue
		for j in range(i + 1, notes.size()):
			var b: Dictionary = notes[j]
			var gap: float = b.t - a.t
			if gap >= reach: break
			if gap <= SU.CHORD_EPS or span[j].is_empty(): continue
			# yellow (ExTap) chains are rolled across the keys: like CHUNITHM's cells, two of them only cut each other
			# on the same key; anything else cuts wherever one (padded) key reaches both
			if cut_same_track and a.light != b.light: continue
			if a.ex and b.ex and a.k >= 0 and b.k >= 0:
				if a.k != b.k: continue
			elif not _one_key_reaches_sections(span[i], span[j]): continue
			var half := gap / 2.0
			a.w_l = minf(a.w_l, half)
			b.w_e = minf(b.w_e, half)
			b.snap_from = maxf(b.snap_from, a.t + half)

func _one_key_reaches_sections(p: Array, q: Array) -> bool:
	for a in p:
		for b in q:
			if _one_key_reaches(a, b): return true
	return false

func _one_key_reaches(p: Array, q: Array) -> bool:
	for k in KB.list:
		var k0: float = k.x0 / 15.0 - SU.KEY_PAD
		var k1: float = (k.x0 + k.w) / 15.0 + SU.KEY_PAD
		if minf(k1, p[1]) - maxf(k0, p[0]) >= MIN_OVERLAP and minf(k1, q[1]) - maxf(k0, q[0]) >= MIN_OVERLAP:
			return true
	return false

const HOME = BuiltinGameData.HOME

## Fingering hints.  Each note gets the home-row key it is most comfortably played with ("k": the chart's own
## suggestion, else the key under the note's centre) and "hint" = the hand has to (re)place itself for it: a
## chord, the first note after a pause, or a jump of two keys or more from that hand's last note.  Notes that
## simply continue a figure carry no hint -- the pattern reads itself.
func _fingering() -> void:
	var tl := _build_timelines(chart.lights)
	var prev_t := -INF
	var last := {"L": [-INF, -1], "R": [-INF, -1]}
	for n in notes:
		if n.k < 0 and tl.has(n.light):
			var st := _light_at(tl[n.light], n.t + 1e-4)
			if st.alive:
				n.k = clampi(int(round((st.x + (n.u - 0.5) * st.w) * 15.0 - 2.25)), 0, 10)
		n["key_code"] = HOME[n.k] if n.k >= 0 else ""
		var hand := "L" if n.k <= 4 else "R"
		var lh: Array = last[hand]
		n["hint"] = n.k >= 0 and (n.get("chord", false) or n.t - prev_t >= 0.45 or n.t - lh[0] > 1.0)
		prev_t = n.t
		last[hand] = [n.t, n.k]

func skip_before(t0: float) -> void:
	var k := 0
	for n in notes:
		if n.t < t0:
			n.state = "skip"; k += 1 + n.ticks.size()
	for c in cues:
		if c.t < t0:
			c.state = "skip"; k += 1
	stats.total = maxi(0, stats.total - k)

func light_states(t: float, reach: float) -> Array:
	var out := []
	for id in ids:
		var s := _light_at(tl[id], t)
		out.append({"id": id, "alive": s.alive, "x": s.x, "w": s.w, "reach": reach, "alpha": s.alpha, "pulse": s.pulse, "tint": s.get("tint", -1), "a": s.get("a", -1.0)})
		if _custom_geometry and s.has("geometry"):
			for key in s:
				if not out[-1].has(key): out[-1][key] = s[key]
	return out

# ---------------------------------------------------------------- hit resolution (key range must overlap the zone)
## Which note a press takes (owner, 2026-10-18): a press inside a live track always takes a note if one is in its
## window -- nothing in-track is thrown away as a mis-touch. Order: a chord already begun first (its other notes take
## the next presses); otherwise first come, first served (the earliest pending note of the reachable tracks), so one key
## tapped in rhythm clears any number of notes lined up in a track and a chord can be caught as A then S.
## Compensation: when the earliest candidate is already later than GREAT for this press but a later candidate is
## within PERFECT of it, the press goes to that later note (the player is clearly on the next beat); the old note keeps
## its own window for the next press. Ties at one moment: the note fingered on this key, a normal before a yellow,
## then the nearest.
func resolve_hit(xk: float, ts: float, k0: float, k1: float, code := ""):
	var cands := []
	var cache := {}
	for n in notes:
		if n.state != "pending": continue
		var cref: float = n.get("chord_ref", -INF)
		var late: float = maxf(n.w_l, cref + SU.CHORD_FOLLOW - n.t) if cref > -INF else n.w_l
		if ts - n.t < -n.w_e - 1e-9 or ts - n.t > late + 1e-9: continue      # its own window
		if not cache.has(n.light):
			cache[n.light] = _light_at(tl[n.light], maxf(ts, n.t - 0.05))
		var st: Dictionary = cache[n.light]
		if not st.alive: continue
		if not _overlaps(st, k0, k1): continue
		cands.append(n)
	if cands.is_empty(): return null
	var begun := cands.filter(func(n): return n.get("chord_ref", -INF) > -INF)
	if not begun.is_empty(): return _pick_at_moment(begun, xk, code)
	cands.sort_custom(func(a, b): return a.t < b.t)
	var first: Dictionary = cands[0]
	if fifo_compensate and ts - first.t > SU.WIN_GREAT:
		for n in cands:
			if n.t - first.t > SU.CHORD_EPS and absf(ts - n.t) <= SU.WIN_PERFECT:
				return _pick_at_moment(cands.filter(func(m): return absf(m.t - n.t) <= SU.CHORD_EPS), xk, code)
	return _pick_at_moment(cands.filter(func(m): return absf(m.t - first.t) <= SU.CHORD_EPS), xk, code)

func _pick_at_moment(group: Array, xk: float, code: String):
	var best = null
	var rank := [INF, INF, INF]
	for n in group:
		var st: Dictionary = _light_at(tl[n.light], n.t)
		var own: float = 0.0 if code != "" and n.get("key_code", "") == code else 1.0
		var r := [own, 1.0 if n.ex else 0.0, absf(st.x + (n.u - 0.5) * st.w - xk)]
		if r < rank:
			best = n; rank = r
	return best

func press_key(code: String, ts: float):
	var context := {"runtime": self, "code": code, "ts": ts, "result": null}
	pipeline.run("key_press", context)
	return context.result

static func rule_key_input(context: Dictionary) -> void: context.runtime._rule_key_input(context)
static func rule_nearest_time(context: Dictionary) -> void: context.runtime._rule_nearest_time(context)
static func rule_slap_guard(context: Dictionary) -> void: context.runtime._rule_slap_guard(context)
static func rule_early_snap(context: Dictionary) -> void: context.runtime._rule_early_snap(context)
static func rule_chord_follow(context: Dictionary) -> void: context.runtime._rule_chord_follow(context)
static func rule_note_head(context: Dictionary) -> void: context.runtime._rule_note_head(context)
static func rule_scoring(context: Dictionary) -> void: context.runtime._rule_scoring(context)
static func rule_hit_feedback(context: Dictionary) -> void: context.runtime._rule_hit_feedback(context)

func _rule_key_input(context: Dictionary) -> void:
	var code: String = context.code
	if not KB.by_code.has(code) or down.has(code):
		context.stop = true
		return
	var k: Dictionary = KB.by_code[code]
	var rec := {"ts": context.ts, "note": null}
	down[code] = rec
	pressed.emit(code, k.cx)
	context.k = k
	context.rec = rec

func _rule_nearest_time(context: Dictionary) -> void:
	var k: Dictionary = context.k
	var k0: float = k.x0 / 15.0 - SU.KEY_PAD
	var k1: float = (k.x0 + k.w) / 15.0 + SU.KEY_PAD
	context.note = resolve_hit(k.cx, context.ts, k0, k1, context.code)
	if regrade_enabled: _try_regrade(context, k0, k1)

## Grade protection (owner, 2026-10-18). A tap taken more than PERFECT early is provisional: its hit effect shows at
## once, its grade is settled PERFECT after its own time. Until then a later press on its track that is closer to the
## note's time re-judges it with the better timing -- that press is used up there (it does not go on to take the next
## note early, so one extra key of a slap no longer drags every following note down to GOOD), and the earlier press
## counts as the stray. A press is only superseded by a better press for the same note; a single press always counts.
func _try_regrade(context: Dictionary, k0: float, k1: float) -> void:
	var ts: float = context.ts
	var best = null
	var best_d := INF
	for r in notes:
		if not r.get("provisional", false) or not (r.state in ["hit", "holding"]): continue
		if ts > r.t + SU.WIN_PERFECT + 1e-9: continue
		var d := absf(ts - r.t)
		if d >= absf(float(r.hitDt)) - 1e-4: continue
		if not _overlaps(_light_at(tl[r.light], r.t), k0, k1): continue
		if d < best_d:
			best = r; best_d = d
	if best == null: return
	var n = context.note
	# owner 2026-10-18 ("two presses became one"): the press is matched against both the provisional note and the
	# next pending one and goes where it earns the better grade; on a tie it takes the pending note, so a second
	# press is never swallowed while a real note is waiting for it
	if n != null and _grade_rank(absf(ts - n.t)) <= _grade_rank(best_d): return
	var r: Dictionary = best
	var old_grade: String = r.grade
	var old_crit: bool = r.crit
	var old_dt: float = r.hitDt
	if strays.size() < 4000: strays.append({"ts": snappedf(r.get("prov_ts", ts), 1e-4), "key": r.key})
	var dt: float = ts - r.t
	var grade := grade_of(absf(dt))
	r.crit = absf(dt) <= SU.WIN_CRITICAL + 1e-9
	_count(old_grade, -1, old_crit); _count(grade, 1, r.crit)
	if absf(old_dt) > SU.WIN_CRITICAL: stats.fast = maxi(0, stats.fast - 1)
	_log_hit(dt, grade)
	r.grade = grade; r.headGrade = grade; r.key = context.code; r.hitDt = dt; r.hitX = context.k.cx
	r.fb = {"grade": grade, "x": context.k.cx, "dt": dt}
	ripple.emit(context.k.cx, (3.0 if r.big else 2.0) if grade == "PERFECT" else 1.0)
	if grade == "PERFECT" or ts >= r.t:
		_settle(r)
	context.result = r
	context.stop = true

## 0 CRITICAL, 1 PERFECT, 2 GREAT, 3 GOOD (smaller is better)
static func _grade_rank(d: float) -> int:
	if d <= SU.WIN_CRITICAL + 1e-9: return 0
	if d <= SU.WIN_PERFECT + 1e-9: return 1
	if d <= SU.WIN_GREAT + 1e-9: return 2
	return 3

func _settle(n: Dictionary) -> void:
	if not n.get("provisional", false): return
	n.provisional = false
	var fb: Dictionary = n.get("fb", {})
	if not fb.is_empty(): judged.emit(fb.grade, fb.x, fb.dt)

func _rule_slap_guard(context: Dictionary) -> void:
	var k: Dictionary = context.k
	var ts: float = context.ts
	var n = context.note
	# The same-hand cluster may take a chord partner, never another moment.
	var slap := false
	if cluster_guard:
		var grown := []
		var other_moment := false
		_hits = _hits.filter(func(c): return ts - c.ts < cluster_s)
		for c in _hits:
			if absf(k.cx - c.cx) > cluster_reach / 15.0 + SU.EPS: continue
			slap = true
			grown.append({"ts": c.ts, "t": c.t, "cx": k.cx})
			if n != null and absf(n.t - c.t) > SU.CHORD_EPS: other_moment = true
		_hits.append_array(grown)
		if other_moment:
			if debug_blocked.size() < 400: debug_blocked.append({"ts": ts, "code": context.code, "id": n.id, "nt": n.t, "nlight": n.light})
			n = null
	context.slap = slap
	context.note = n

func _rule_early_snap(context: Dictionary) -> void:
	if context.note != null: return
	var k: Dictionary = context.k
	var ts: float = context.ts
	var code: String = context.code
	context.stop = true
	if context.slap:
		if strays.size() < 4000: strays.append({"ts": snappedf(ts, 1e-4), "key": code})
		return
	var sn = _snap_target(ts, k.x0 / 15.0 - SU.KEY_PAD, (k.x0 + k.w) / 15.0 + SU.KEY_PAD) if snap_enabled else null
	if sn != null:
		sn["snap"] = {"code": code, "ts": ts, "x": k.cx}
		ripple.emit(k.cx, 0.5)
		return
	ripple.emit(k.cx, 0.0)
	if strays.size() < 4000: strays.append({"ts": snappedf(ts, 1e-4), "key": code})

func _rule_chord_follow(context: Dictionary) -> void:
	var n: Dictionary = context.note
	var k: Dictionary = context.k
	var ts: float = context.ts
	_hits.append({"ts": ts, "t": n.t, "cx": k.cx})
	var dt: float = ts - n.t
	var cref: float = n.get("chord_ref", -INF)
	var follow: bool = cref > -INF and ts >= cref - 1e-9 and ts - cref <= SU.CHORD_FOLLOW + 1e-9
	if follow: dt = ts - cref
	var grade := "PERFECT" if n.ex or follow else grade_of(absf(dt))
	n.crit = n.ex or absf(dt) <= SU.WIN_CRITICAL + 1e-9
	_chord_begun(n, ts)
	n.grade = grade; n.headGrade = grade; n.key = context.code; n.hitDt = dt; n.hitX = k.cx
	# hold heads too (owner, 2026-10-18): the body is kept by any key in the track, so re-judging the head never
	# touches the hold itself
	n["provisional"] = regrade_enabled and not follow and not n.ex and dt < -SU.WIN_CRITICAL - 1e-9
	if n.provisional: n["prov_ts"] = ts
	context.dt = dt
	context.grade = grade

func _rule_note_head(context: Dictionary) -> void:
	var n: Dictionary = context.note
	if _hold_kinds.get(n.kind, false):
		n.state = "holding"; context.rec.note = n; n.gap = 0.0
	else:
		n.state = "hit"

func _rule_scoring(context: Dictionary) -> void:
	_count(context.grade, 1, context.note.crit); _combo_for(context.grade); _log_hit(0.0 if context.note.ex else context.dt, context.grade)

func _rule_hit_feedback(context: Dictionary) -> void:
	var n: Dictionary = context.note
	var k: Dictionary = context.k
	var grade: String = context.grade
	ripple.emit(k.cx, (3.0 if n.big else 2.0) if grade == "PERFECT" else 1.0)
	if n.get("provisional", false):
		n["fb"] = {"grade": grade, "x": k.cx, "dt": context.dt}
	else:
		judged.emit(grade, k.cx, 0.0 if n.ex else context.dt)
	context.result = n

func _chord_begun(n: Dictionary, ts: float) -> void:
	for s in n.get("sibs", []):
		if not is_same(s, n) and s.state == "pending" and s.get("chord_ref", -INF) == -INF:
			s["chord_ref"] = ts

## Snap ("adsorption"): a press too early for any window is not thrown away -- it latches onto the next normal note
## of its light that lands within SNAP_EARLY, and that note is judged when it reaches the line (no better than GREAT
## unless the press was inside the GREAT window anyway).  One press latches one note; a real press on the note in time
## still wins (the note is pending until it lands).
func _snap_target(ts: float, k0: float, k1: float):
	var best = null
	for n in notes:
		if n.state != "pending" or n.ex or n.has("snap"): continue
		if n.t <= ts or n.t > ts + SU.SNAP_EARLY or ts <= n.snap_from: continue   # not from a previous note's half
		var st := _light_at(tl[n.light], n.t)
		if not st.alive: continue
		if not _overlaps(st, k0, k1): continue
		if best == null or n.t < best.t: best = n
	return best

func _land_snap(n: Dictionary) -> void:
	var sp: Dictionary = n.snap
	var dt: float = sp.ts - n.t
	var grade := grade_of(minf(absf(dt), SU.WIN_GREAT))
	n.crit = absf(dt) <= SU.WIN_CRITICAL + 1e-9
	n.grade = grade; n.headGrade = grade; n.key = sp.code; n.hitDt = dt; n.hitX = sp.x
	if _hold_kinds.get(n.kind, false):
		n.state = "holding"; n.gap = 0.0
		var rec = down.get(sp.code)
		if rec and absf(rec.ts - sp.ts) < 1e-6: rec.note = n
	else:
		n.state = "hit"
	_chord_begun(n, sp.ts)
	_count(grade, 1, n.crit); _combo_for(grade); _log_hit(dt, grade)
	ripple.emit(sp.x, (3.0 if n.big else 2.0) if grade == "PERFECT" else 1.0)
	judged.emit(grade, sp.x, dt)

## Yellow notes are protected (owner, 2026-10-16: pressing every one was too hard): one that reaches the line while a key
## is already held inside its track is caught by that key -- the keyboard version of sliding through Deemo's yellow
## chains.  A press still takes one as well (any timing in its window = PERFECT).
func _catch(n: Dictionary, ts: float, st: Dictionary) -> bool:
	var context := {"runtime": self, "note": n, "ts": ts, "state": st, "result": false}
	pipeline.run("yellow_catch", context)
	return context.result

static func rule_yellow_catch(context: Dictionary) -> void:
	context.result = context.runtime._standard_catch(context.note, context.ts, context.state)

func _standard_catch(n: Dictionary, ts: float, st: Dictionary) -> bool:
	for code in down:
		var k: Dictionary = KB.by_code[code]
		var k0: float = k.x0 / 15.0 - SU.KEY_PAD
		var k1: float = (k.x0 + k.w) / 15.0 + SU.KEY_PAD
		if not _overlaps(st, k0, k1): continue
		n.crit = true; n.grade = "PERFECT"; n.headGrade = "PERFECT"; n.key = code; n.hitDt = 0.0; n.hitX = k.cx
		if _hold_kinds.get(n.kind, false):
			n.state = "holding"; n.gap = 0.0; down[code].note = n
		else:
			n.state = "hit"
		_chord_begun(n, ts)
		_count("PERFECT", 1, true); _combo_for("PERFECT"); _log_hit(0.0, "PERFECT")
		ripple.emit(k.cx, 2.0)
		judged.emit("PERFECT", k.cx, 0.0)
		return true
	return false

func release_key(code: String, ts: float) -> void:
	pipeline.run("release", {"runtime": self, "code": code, "ts": ts})

static func rule_release(context: Dictionary) -> void:
	context.runtime.down.erase(context.code)

## A hold's body after CHUNITHM / UMIGURI: it is held while ANY key is down inside its light (not only the one that
## struck the head; a key already held when the head arrives counts too, even if the head itself was missed).  Each
## tick is graded by how long the light went without a key since the previous tick (SU.HOLD_GAP_*); the hold never
## breaks for good.  `gap_t` (>= 0 while no key is in it) also tells the renderer to dim the ribbon.
func _hold_kept(n: Dictionary, ts: float) -> bool:
	var st := _light_at(tl[n.light], ts)
	if not st.alive: return true
	for code in down:
		var k: Dictionary = KB.by_code[code]
		if _overlaps(st, k.x0 / 15.0 - SU.KEY_PAD, (k.x0 + k.w) / 15.0 + SU.KEY_PAD):
			return true
	return false

func _hold_step(n: Dictionary, ts: float) -> void:
	pipeline.run("hold_body", {"runtime": self, "note": n, "ts": ts})

static func rule_hold_body(context: Dictionary) -> void:
	context.runtime._standard_hold_step(context.note, context.ts)

func _standard_hold_step(n: Dictionary, ts: float) -> void:
	var t1: float = minf(ts, n.t + n.dur)
	if t1 > n.last_ts:
		if _hold_kept(n, t1):
			n.held_t = t1; n.held_since = true; n.gap_t = -1.0
			if n.state in ["miss", "fail"]: n.state = "holding"
		else:
			n.gap += t1 - n.last_ts
			if n.gap_t < 0.0: n.gap_t = n.last_ts
			if n.state == "holding" and n.gap > SU.HOLD_GAP_GOOD and n.tick_i < n.ticks.size(): n.state = "fail"
		n.last_ts = t1
	while n.tick_i < n.ticks.size() and n.ticks[n.tick_i] <= ts + 1e-9:
		n.tick_i += 1
		var g := "MISS"
		if n.held_t > -INF:
			if n.gap <= SU.HOLD_GAP_CRIT + 1e-9: g = "PERFECT"
			elif n.gap <= SU.HOLD_GAP_PERFECT + 1e-9: g = "PERFECT"
			elif n.gap <= SU.HOLD_GAP_GOOD + 1e-9: g = "GOOD"
		_count(g, 1, g == "PERFECT" and n.gap <= SU.HOLD_GAP_CRIT + 1e-9); _combo_for(g)
		if n.held_since:
			n.gap = 0.0; n.held_since = false
	if ts >= n.t + n.dur - 1e-9 and n.state != "pending":
		n.body_done = true
		if n.state == "holding":
			n.state = "done"; hold_end.emit(n)


func release_all(ts: float) -> void:
	for code in down.keys():
		release_key(code, ts)
	if space_down: release_space(ts)

func press_space(ts: float):
	var context := {"runtime": self, "ts": ts, "action": "press", "result": null}
	pipeline.run("pedal", context)
	return context.result

static func rule_pedal(context: Dictionary) -> void:
	if context.action == "press": context.result = context.runtime._standard_press_space(context.ts)
	else: context.runtime._standard_release_space(context.ts)

func _standard_press_space(ts: float):
	if space_down: return null
	space_down = true
	var best = null
	for c in cues:
		if c.state == "pending" and absf(c.t - ts) <= SU.WIN_GOOD + 1e-9 and (best == null or c.t < best.t):
			best = c
	pressed.emit("Space", -1.0)
	if best == null: return null
	var grade := grade_of(absf(ts - best.t))
	_record_cue_hit(best, ts)
	best.grade = grade; best.headGrade = grade
	best.crit = absf(ts - best.t) <= SU.WIN_CRITICAL + 1e-9
	if best.dur > 0.0:
		best.state = "holding"; space_cue = best
	else:
		best.state = "hit"
	_count(grade, 1, best.crit); _combo_for(grade); _log_hit(ts - best.t, grade)
	cue_judged.emit(best, grade)
	return best

func release_space(ts: float) -> void:
	pipeline.run("pedal", {"runtime": self, "ts": ts, "action": "release", "result": null})

func _standard_release_space(ts: float) -> void:
	space_down = false
	var c = space_cue
	if c and c.state == "holding":
		if ts < c.t + c.dur - maxf(SU.HOLD_EARLY, 0.25 * c.dur): _fail_cue(c)
		else: c.state = "done"
	space_cue = null

func _fail_cue(c: Dictionary) -> void:
	c.state = "fail"
	_count(c.headGrade, -1, c.crit); _count("MISS", 1); c.grade = "MISS"; _combo_for("MISS")
	cue_judged.emit(c, "MISS")

func _miss_note(n: Dictionary) -> void:
	n.state = "miss"; n.grade = "MISS"
	_count("MISS", 1); _combo_for("MISS"); _log_hit(SU.WIN_GOOD, "MISS")
	judged.emit("MISS", n.lineX if n.lineX >= 0.0 else 0.5, SU.WIN_GOOD)

func _miss_cue(c: Dictionary) -> void:
	c.state = "miss"; c.grade = "MISS"
	_count("MISS", 1); _combo_for("MISS")
	cue_judged.emit(c, "MISS")

# ---------------------------------------------------------------- autoplay (perfect machine, same press/release paths)
func _auto_key(n: Dictionary) -> String:
	var st := _light_at(tl[n.light], n.t)
	var target: float = st.x + (n.u - 0.5) * st.w
	var lo: float = st.x - st.w / 2.0 - SU.EPS
	var hi: float = st.x + st.w / 2.0 + SU.EPS
	var c := []
	for k in KB.list:
		if not _custom_geometry or not st.has("geometry"):
			if k.cx >= lo and k.cx <= hi: c.append(k)
		elif _overlaps(st, k.x0 / 15.0 - SU.KEY_PAD, (k.x0 + k.w) / 15.0 + SU.KEY_PAD): c.append(k)
	# free keys first (a key still down from the previous note is lifted and struck again: yellow notes need a press)
	c.sort_custom(func(a, b): return [int(down.has(a.code)), absf(a.cx - target)] < [int(down.has(b.code)), absf(b.cx - target)])
	for k in c:
		if is_same(resolve_hit(k.cx, n.t, k.x0 / 15.0 - SU.KEY_PAD, (k.x0 + k.w) / 15.0 + SU.KEY_PAD, k.code), n): return k.code
	return c[0].code if not c.is_empty() else "KeyA"

## The second key of a slap (autoplay_extra): the nearest other key whose padded range overlaps the note's track,
## centre inside the track first, a free key first.
func _extra_key(n: Dictionary, code: String) -> String:
	var st := _light_at(tl[n.light], n.t)
	var lo: float = st.x - st.w / 2.0
	var hi: float = st.x + st.w / 2.0
	var me: Dictionary = KB.by_code[code]
	var c := []
	for k in KB.list:
		if k.code == code or not minf(k.x0 / 15.0 + k.w / 15.0 + SU.KEY_PAD, hi) - maxf(k.x0 / 15.0 - SU.KEY_PAD, lo) >= MIN_OVERLAP: continue
		c.append(k)
	c.sort_custom(func(a, b): return [int(down.has(a.code)), int(a.cx < lo - SU.EPS or a.cx > hi + SU.EPS), absf(a.cx - me.cx) + 0.001 * absi(a.row - me.row)] < [int(down.has(b.code)), int(b.cx < lo - SU.EPS or b.cx > hi + SU.EPS), absf(b.cx - me.cx) + 0.001 * absi(b.row - me.row)])
	return c[0].code if not c.is_empty() else ""

func _autoplay(ts: float) -> void:
	for guard in 800:
		var best = null
		var bt := INF
		var kind := ""
		for r in rel:
			if r.ts <= ts and r.ts < bt - 1e-12: best = r; bt = r.ts; kind = "rel"
		for c in cues:
			if c.t > ts: break
			if c.state == "pending" and not c.auto and c.t <= ts and c.t < bt - 1e-12: best = c; bt = c.t; kind = "cue"
		for n in notes:
			if n.t > ts: break
			# a note an extra key took early (provisional) still gets its own on-time press, which re-judges it
			if (n.state == "pending" or n.get("provisional", false)) and not n.auto and n.t <= ts and n.t < bt - 1e-12: best = n; bt = n.t; kind = "note"
		for r in xp:                   # a slap's extra key comes after every real note of the same instant
			if r.ts <= ts and r.ts < bt - 1e-12: best = r; bt = r.ts; kind = "xp"
		if best == null: break
		if kind == "rel":
			rel.erase(best)
			if best.get("space", false): release_space(best.ts)
			else: release_key(best.code, best.ts)
		elif kind == "xp":
			xp.erase(best)
			if not down.has(best.code):
				press_key(best.code, best.ts)
				rel.append({"code": best.code, "ts": best.ts + best.dur})
		elif kind == "cue":
			best.auto = true
			if space_down: release_space(best.t - 1e-4)
			press_space(best.t)
			rel.append({"space": true, "ts": best.t + (best.dur if best.dur > 0.0 else 0.05)})
		else:
			best.auto = true
			var code := _auto_key(best)
			if down.has(code):
				release_key(code, best.t - 1e-4)
				rel = rel.filter(func(r): return r.get("code", "") != code)
			press_key(code, best.t)
			rel.append({"code": code, "ts": best.t + (best.dur if _hold_kinds.get(best.kind, false) else 0.06)})
			if autoplay_extra > 0:
				var x := _extra_key(best, code)
				if x != "": xp.append({"code": x, "ts": best.t + autoplay_extra_ms / 1000.0, "dur": best.dur if _hold_kinds.get(best.kind, false) else 0.06})

func update(ts: float) -> void:
	pipeline.run("update", {"runtime": self, "t": ts})

func _update_notes(ts: float) -> void:
	var cache := {}
	for n: Dictionary in notes:
		# 2026-10-17: future notes only need their public line position. All
		# catch/snap/miss/body predicates below are false before their head time.
		if n.t > ts:
			var state: String = n.state
			if state == "pending" or state == "holding":
				if not cache.has(n.light): cache[n.light] = _light_at(tl[n.light], ts)
				var future: Dictionary = cache[n.light]
				if future.alive: n.lineX = future.x + (n.u - 0.5) * future.w
			continue
		if n.get("provisional", false) and ts > n.t + SU.WIN_PERFECT:
			_settle(n)
		if n.state == "pending" and n.ex and ts >= n.t and not down.is_empty():
			if not cache.has(n.light): cache[n.light] = _light_at(tl[n.light], ts)
			if cache[n.light].alive: _catch(n, ts, cache[n.light])
		if n.state == "pending":
			if n.has("snap") and ts >= n.t + SU.WIN_CRITICAL:      # a real press right on time still beats the snap
				_land_snap(n)
			elif ts > maxf(n.t + SU.WIN_GOOD, n.get("chord_ref", -INF) + SU.CHORD_FOLLOW) + 1e-9:
				_miss_note(n)
		if _hold_kinds.get(n.kind, false) and ts >= n.t and n.state != "skip" and not n.get("body_done", false):
			_hold_step(n, ts)
		if n.state == "pending" or n.state == "holding":
			if not cache.has(n.light): cache[n.light] = _light_at(tl[n.light], ts)
			var st: Dictionary = cache[n.light]
			if st.alive: n.lineX = st.x + (n.u - 0.5) * st.w

func _update_cues(ts: float) -> void:
	for c in cues:
		if c.state == "pending":
			if ts > c.t + SU.WIN_GOOD + 1e-9: _miss_cue(c)
		elif c.state == "holding":
			if ts >= c.t + c.dur - 1e-9: c.state = "done"

func _finish_update(ts: float) -> void:
	if playing and ts > end_time:
		playing = false
		_recalc()
		finished.emit(stats)

## Log cue timing through the same press path for humans and autoplay.
func _record_cue_hit(cue: Dictionary, ts: float) -> void:
	cue["hitDt"] = ts - cue.t
	cue["key"] = "Space"

## Session-scoped chart providers; compatibility callers still use ChartLib's built-in scope.
func _light_at(segments, t: float) -> Dictionary:
	return _chart_provider.light_at(segments, t, registry)

func _build_timelines(events: Array) -> Dictionary:
	return _chart_provider.build_timelines(events, registry)

func _sections(state: Dictionary) -> Array:
	var callback: Callable = _geometry.get(str(state.get("geometry", "lane")), Callable())
	return callback.call(state) if callback.is_valid() else []

func _overlaps(state: Dictionary, k0: float, k1: float) -> bool:
	for section in _sections(state):
		if minf(k1, section[1]) - maxf(k0, section[0]) >= MIN_OVERLAP: return true
	return false
