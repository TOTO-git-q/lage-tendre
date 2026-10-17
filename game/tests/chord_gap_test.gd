## godot --headless --path . -s tests/chord_gap_test.gd : a chord is played as quick successive taps -- two hands a
## little apart still get both notes, graded from the first key, and a note right after the chord is not lost
extends SceneTree

func run(name: String, presses: Array, want: Array) -> bool:
	var U := 1.0 / 15.0
	# left light A..F and right light J..; ; a 2-note chord at 3.0 (D, K), then a D note at 3.15
	var chart := {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "x": 3.75 * U, "w": 4.0 * U, "auto": true},
			{"t": 1.0, "id": 1, "type": "on", "x": 9.75 * U, "w": 4.0 * U, "auto": true}],
		"notes": [{"t": 3.0, "light": 0, "u": 0.5625, "kind": "tap", "k": 2}, {"t": 3.0, "light": 1, "u": 0.5625, "kind": "tap", "k": 7},
			{"t": 3.15, "light": 0, "u": 0.5625, "kind": "tap", "k": 2}]}
	var core := GameCore.new()
	core.load_chart(chart)
	core.playing = true
	var t := 0.0
	var i := 0
	while t < 4.0:
		while i < presses.size() and presses[i][0] <= t:
			core.press_key(presses[i][1], presses[i][0]); core.release_key(presses[i][1], presses[i][0] + 0.03); i += 1
		core.update(t)
		t += 1.0 / 240.0
	var got := []
	for n in core.notes: got.append(n.grade)
	print("%-44s %s" % [name, str(got)])
	return got == want

func _init() -> void:
	KB.set_layout("ansi")
	var ok := true
	ok = run("hands together", [[3.0, "KeyD"], [3.0, "KeyK"], [3.15, "KeyD"]], ["PERFECT", "PERFECT", "PERFECT"]) and ok
	ok = run("right hand 90 ms after the left", [[3.0, "KeyD"], [3.09, "KeyK"], [3.15, "KeyD"]], ["PERFECT", "PERFECT", "PERFECT"]) and ok
	ok = run("left 40 ms late, right 130 ms late", [[3.04, "KeyD"], [3.13, "KeyK"], [3.16, "KeyD"]], ["PERFECT", "PERFECT", "PERFECT"]) and ok
	ok = run("only one hand: the other misses", [[3.0, "KeyD"], [3.15, "KeyD"]], ["PERFECT", "MISS", "PERFECT"]) and ok
	print("CHORD GAP: ", "PASS" if ok else "FAIL")
	quit()
