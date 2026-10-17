## Headless: would a HUMAN pressing the "natural" key for every DEMO note get it?
##   godot --headless --path . -s tests/human_keys_test.gd
## natural key = home-row key whose centre is nearest the note's drawn landing x (renderer _land_st geometry
## at arrival); also tries same-column keys on the other rows.  Then a full human run (natural keys, pedal
## held through every cue, holds held to the end) with timing offsets, in simulated time.
extends SceneTree

const B := 0.5
const T0 := 2.0

func beat(t: float) -> float:
	return (t - T0) / B

func draw_x(core: GameCore, n: Dictionary, t_view: float) -> float:
	# replica of renderer._land_st + _note_at: geometry used to draw note n at time t_view
	var segs: Array = core.tl[n.light]
	var i_n := -1
	var i_c := -1
	for k in segs.size():
		if segs[k].t <= n.t + 1e-9: i_n = k
		if segs[k].t <= t_view + 1e-9: i_c = k
	var st := ChartLib.light_at(segs, t_view)
	for k in range(i_c + 1, i_n + 1):
		if segs[k].type == "jump" or segs[k].type == "on":
			st = ChartLib.light_at(segs, n.t + 1e-4); break
	return st.x + (n.u - 0.5) * st.w

func nearest_home(x: float) -> Dictionary:
	var best = null
	for k in KB.list:
		if k.row != 2: continue
		if best == null or absf(k.cx - x) < absf(best.cx - x): best = k
	return best

func column_keys(x: float) -> Array:
	var out := []
	for k in KB.list:
		if k.row == 2: continue
		if x * 15.0 >= k.x0 and x * 15.0 < k.x0 + k.w: out.append(k)
	return out

func overlap(k: Dictionary, st: Dictionary) -> float:
	return (minf((k.x0 + k.w) / 15.0, st.x + st.w / 2.0) - maxf(k.x0 / 15.0, st.x - st.w / 2.0)) * 15.0

func _init() -> void:
	var total_bad := 0
	for lay in KB.LAYOUT_NAMES:
		KB.set_layout(lay)
		var core := GameCore.new()
		core.load_chart(ChartLib.demo())
		print("==== layout ", lay, "  notes=", core.notes.size(), " cues=", core.cues.size(), " warnings=", core.chart.warnings)
		# ---- 1. static check per note (isolated: is the natural key accepted for this light at n.t?)
		var nbad := 0
		var drift := []
		for n in core.notes:
			var st := ChartLib.light_at(core.tl[n.light], n.t)
			var xl := draw_x(core, n, n.t)
			var nk := nearest_home(xl)
			var ok_home := overlap(nk, st) >= 0.1 - 1e-6
			var hand_ok: bool = (n.light == 0 and nk.cx <= KB.x_of("KeyF") + 1e-6) or (n.light == 1 and nk.cx >= KB.x_of("KeyJ") - 1e-6)
			var col_fail := []
			for k in column_keys(xl):
				if overlap(k, st) < 0.1 - 1e-6: col_fail.append(k.code)
			if not ok_home or not hand_ok or not col_fail.is_empty():
				nbad += 1
				print("  STATIC beat %.2f light %d zone [%.2f,%.2f]u landing %.2fu key %s home_ok=%s hand_ok=%s column_fail=%s" % [
					beat(n.t), n.light, (st.x - st.w / 2) * 15, (st.x + st.w / 2) * 15, xl * 15, nk.code, ok_home, hand_ok, col_fail])
			# drift: where is the note drawn while falling (fall 0.6..3.5 s)?  different nearest key = misleading
			for fall in [1.5, 3.5]:
				for frac in [0.25, 0.5, 0.75]:
					var tv: float = n.t - fall * (1.0 - frac)
					var k2 := nearest_home(draw_x(core, n, tv))
					if k2.code != nk.code:
						drift.append("beat %.2f %s drawn over %s at %.2fs before arrival (fall %.1f)" % [beat(n.t), nk.code, k2.code, n.t - tv, fall])
						break
		print("  static failures: ", nbad)
		print("  drift (note drawn over another key while falling): ", drift.size())
		for d in drift.slice(0, 40): print("    ", d)
		# ---- 2. full human run, natural home-row keys, several timing offsets
		for off in [0.0, -0.03, 0.03, -0.06, 0.06, -0.10]:
			var bad := run_human(lay, off, 2)
			total_bad += bad
		# other rows: same column key on rows 1 and 3
		for row in [1, 3]:
			total_bad += run_human(lay, 0.0, row)
		# tolerance: does the home key one step INWARD (toward the index finger) / OUTWARD still register?
		var tol := []
		var c2 := GameCore.new(); c2.load_chart(ChartLib.demo())
		for n in c2.notes:
			var st := ChartLib.light_at(c2.tl[n.light], n.t)
			var nk := nearest_home(draw_x(c2, n, n.t))
			var inward: float = nk.cx + (1.0 if n.light == 0 else -1.0) / 15.0
			var ik := nearest_home(inward)
			if overlap(ik, st) < 0.1 - 1e-6 and not ik.code in ["KeyG", "KeyH"]:
				tol.append("%.1f:%s(not %s)" % [beat(n.t), nk.code.trim_prefix("Key"), ik.code.trim_prefix("Key")])
		print("  notes whose inward-neighbour key (not G/H) registers NOTHING: ", tol.size())
		print("    ", " ".join(tol))
		print("  -- hand-anchored human (index on F/J, reads note relative to light inner edge):")
		run_human(lay, 0.0, 9)
	print("TOTAL human failures: ", total_bad)
	quit()

func key_for(core: GameCore, n: Dictionary, row: int) -> String:
	var xl := draw_x(core, n, n.t)
	if row == 2: return nearest_home(xl).code
	if row == 9: return finger_key(core, n)
	for k in column_keys(xl):
		if k.row == row: return k.code
	return nearest_home(xl).code

## hand-anchored human: index fingers rest on F / J; a note is read RELATIVE to its light's inner edge
## (inner edge = index finger, next key = middle finger, ...), the way section 1 teaches it
func finger_key(core: GameCore, n: Dictionary) -> String:
	var st := ChartLib.light_at(core.tl[n.light], n.t)
	var xl := draw_x(core, n, n.t)
	var inner: float = st.x + st.w / 2.0 if n.light == 0 else st.x - st.w / 2.0
	var f := int(floor(absf(inner - xl) * 15.0 + 1e-6))
	var keys: Array = ["KeyF", "KeyD", "KeyS", "KeyA", "CapsLock"] if n.light == 0 else ["KeyJ", "KeyK", "KeyL", "Semicolon", "Quote"]
	return keys[mini(f, keys.size() - 1)]

func run_human(lay: String, off: float, row: int) -> int:
	var core := GameCore.new()
	core.load_chart(ChartLib.demo())
	core.playing = true
	var evs := []   # {ts, kind: press/release/spress/srelease, code, note}
	for n in core.notes:
		var code := key_for(core, n, row)
		var ts: float = n.t + off
		evs.append({"ts": ts, "k": "press", "code": code, "note": n})
		var rel_t: float = n.t + n.dur + 0.01 if n.kind == "hold" else ts + 0.07
		evs.append({"ts": rel_t, "k": "release", "code": code})
	for c in core.cues:
		evs.append({"ts": c.t + off, "k": "spress"})
		evs.append({"ts": c.t + (c.dur + 0.01 if c.dur > 0.0 else off + 0.08), "k": "srelease"})
	evs.sort_custom(func(a, b):
		if absf(a.ts - b.ts) > 1e-9: return a.ts < b.ts
		return (a.k == "release" or a.k == "srelease") and not (b.k == "release" or b.k == "srelease"))
	var fails := []
	var missed_cues := 0
	core.cue_judged.connect(func(c, g): if g == "MISS": missed_cues += 1)
	for e in evs:
		core.update(e.ts)
		match e.k:
			"press":
				if core.down.has(e.code):
					fails.append("beat %.2f key %s ignored: still in `down`" % [beat(e.note.t), e.code])
				var got = core.press_key(e.code, e.ts)
				if got == null:
					fails.append("beat %.2f key %s -> no note" % [beat(e.note.t), e.code])
				elif not is_same(got, e.note):
					fails.append("beat %.2f key %s -> took note at beat %.2f (%s)" % [beat(e.note.t), e.code, beat(got.t), got.grade])
			"release": core.release_key(e.code, e.ts)
			"spress": core.press_space(e.ts)
			"srelease": core.release_space(e.ts)
	var t: float = evs[-1].ts
	while core.playing:
		t += 0.05; core.update(t)
	var st := core.stats
	var tag := "row %d off %+.2f" % [row, off]
	print("  run %-16s P=%d G=%d g=%d M=%d / %d  cueMiss=%d  fails=%d" % [tag, st.PERFECT, st.GREAT, st.GOOD, st.MISS, st.total, missed_cues, fails.size()])
	for f in fails.slice(0, 60): print("      ", f)
	return fails.size() + st.MISS
