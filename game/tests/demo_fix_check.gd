## Headless: verify the proposed DEMO light fix (widen instead of shift, so each light's inner edge stays at F|G / H|J)
## keeps every note on the same physical key and makes the hand-anchored reading register.
##   godot --headless --path . -s tests/demo_fix_check.gd
extends SceneTree

const U := 1.0 / 15.0

func _init() -> void:
	KB.set_layout("ansi")
	var raw := ChartLib.demo()
	var old_tl := ChartLib.build_timelines(ChartLib.validate(raw).lights)
	var abs_x := []
	for n in raw.notes:
		var st := ChartLib.light_at(old_tl[n.light], n.t)
		abs_x.append(st.x + (n.u - 0.5) * st.w)
	# proposed edits: [beat, id] -> [left edge units, width units]
	var edits := {"24|0": [0.75, 5.0], "24|1": [7.75, 5.0], "48|0": [0.75, 5.0], "56|1": [7.75, 5.0]}
	for e in raw.lights:
		var key := "%d|%d" % [int(round((e.t - 2.0) / 0.5)), e.id]
		if edits.has(key) and e.type != "pulse":
			e.x = (edits[key][0] + edits[key][1] / 2.0) * U; e.w = edits[key][1] * U
	var v := ChartLib.validate(raw)
	print("warnings: ", v.warnings)
	var tl := ChartLib.build_timelines(v.lights)
	var moved := 0
	for i in raw.notes.size():
		var n: Dictionary = raw.notes[i]
		var st := ChartLib.light_at(tl[n.light], n.t)
		n.u = (abs_x[i] - (st.x - st.w / 2.0)) / st.w
		if n.u < -1e-6 or n.u > 1.0 + 1e-6: moved += 1
	print("notes outside their new light: ", moved)
	var core := GameCore.new()
	core.load_chart(raw)
	print("notes after validate: ", core.notes.size(), " (orig 199)")
	# hand-anchored human
	core.playing = true
	var fails := []
	var evs := []
	for n in core.notes:
		var st := ChartLib.light_at(core.tl[n.light], n.t)
		var xl: float = st.x + (n.u - 0.5) * st.w
		var inner: float = st.x + st.w / 2.0 if n.light == 0 else st.x - st.w / 2.0
		var f := int(floor(absf(inner - xl) * 15.0 + 1e-6))
		var keys: Array = ["KeyF", "KeyD", "KeyS", "KeyA", "CapsLock"] if n.light == 0 else ["KeyJ", "KeyK", "KeyL", "Semicolon", "Quote"]
		var code: String = keys[mini(f, 4)]
		evs.append({"ts": n.t, "k": "p", "code": code, "note": n})
		evs.append({"ts": n.t + (n.dur + 0.01 if n.kind == "hold" else 0.07), "k": "r", "code": code})
	for c in core.cues:
		evs.append({"ts": c.t, "k": "sp"}); evs.append({"ts": c.t + maxf(c.dur + 0.01, 0.08), "k": "sr"})
	evs.sort_custom(func(a, b): return a.ts < b.ts if absf(a.ts - b.ts) > 1e-9 else (a.k == "r" or a.k == "sr"))
	for e in evs:
		core.update(e.ts)
		match e.k:
			"p":
				var got = core.press_key(e.code, e.ts)
				if not is_same(got, e.note): fails.append("beat %.2f %s" % [(e.note.t - 2.0) / 0.5, e.code])
			"r": core.release_key(e.code, e.ts)
			"sp": core.press_space(e.ts)
			"sr": core.release_space(e.ts)
	print("hand-anchored human fails with fix: ", fails)
	quit()
