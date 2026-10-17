## godot --headless --path . -s tests/hold_rules_test.gd    : hold rules on a tiny synthetic chart (CHUNITHM / UMIGURI)
## head = a press like a tap; body = a tick every eighth note, held by ANY key in the hold's light; each tick is graded by
## how long the light went without a key since the previous tick (<= 50 ms CRITICAL, <= 100 PERFECT, <= 150 GOOD, else
## MISS); the hold never breaks for good, and the last half step is free
extends SceneTree

func chart() -> Dictionary:
	# left light A..F (x 1.75..5.75 units), one 2 s hold at t = 3 (120 BPM: 7 ticks, 3.25 .. 4.75)
	var U := 1.0 / 15.0
	return {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "x": 3.75 * U, "w": 4.0 * U, "auto": true}],
		"notes": [{"t": 3.0, "light": 0, "u": 0.5625, "kind": "hold", "dur": 2.0}]}

## want = [state, CRITICAL, PERFECT (incl. CRITICAL), GOOD, MISS] over head + 7 ticks
func run(name: String, steps: Array, want: Array) -> bool:
	var core := GameCore.new()
	core.load_chart(chart())
	core.playing = true
	var t := 0.0
	var i := 0
	while t < 6.0:
		while i < steps.size() and steps[i][0] <= t:
			var s: Array = steps[i]
			if s[1] == "down": core.press_key(s[2], s[0])
			else: core.release_key(s[2], s[0])
			i += 1
		core.update(t)
		t += 1.0 / 120.0
	var st := core.stats
	var got := [core.notes[0].state, st.CRITICAL, st.PERFECT, st.GOOD, st.MISS]
	print("%-48s %s  (want %s)" % [name, str(got), str(want)])
	return got == want

func _init() -> void:
	KB.set_layout("ansi")
	var ok := true
	ok = run("held to the end on the head key", [[3.0, "down", "KeyD"], [5.0, "up", "KeyD"]], ["done", 8, 8, 0, 0]) and ok
	ok = run("switch D -> F mid-hold (overlap)", [[3.0, "down", "KeyD"], [3.8, "down", "KeyF"], [3.9, "up", "KeyD"], [5.0, "up", "KeyF"]], ["done", 8, 8, 0, 0]) and ok
	ok = run("40 ms gap: tick still CRITICAL", [[3.0, "down", "KeyD"], [3.6, "up", "KeyD"], [3.64, "down", "KeyA"], [5.0, "up", "KeyA"]], ["done", 8, 8, 0, 0]) and ok
	ok = run("80 ms gap: one tick PERFECT", [[3.0, "down", "KeyD"], [3.6, "up", "KeyD"], [3.68, "down", "KeyA"], [5.0, "up", "KeyA"]], ["done", 7, 8, 0, 0]) and ok
	ok = run("130 ms gap: one tick GOOD", [[3.0, "down", "KeyD"], [3.6, "up", "KeyD"], [3.73, "down", "KeyA"], [5.0, "up", "KeyA"]], ["done", 7, 7, 1, 0]) and ok
	ok = run("0.6 s gap: GOOD, 2 MISS, then back", [[3.0, "down", "KeyD"], [3.6, "up", "KeyD"], [4.2, "down", "KeyD"], [5.0, "up", "KeyD"]], ["done", 5, 5, 1, 2]) and ok
	ok = run("released for good at 3.6", [[3.0, "down", "KeyD"], [3.6, "up", "KeyD"]], ["fail", 3, 3, 1, 4]) and ok
	ok = run("release in the free last half step", [[3.0, "down", "KeyD"], [4.8, "up", "KeyD"]], ["done", 8, 8, 0, 0]) and ok
	ok = run("a key outside the light does not keep it", [[3.0, "down", "KeyD"], [3.5, "down", "KeyL"], [3.55, "up", "KeyD"]], ["fail", 3, 3, 0, 5]) and ok
	ok = run("key held from before: head MISS, body counts", [[2.5, "down", "KeyD"], [5.0, "up", "KeyD"]], ["done", 7, 7, 0, 1]) and ok
	print("HOLD RULES: ", "PASS" if ok else "FAIL")
	quit()
