## godot --headless --path . -s tests/snap_test.gd    : early-press snap ("adsorption") on a tiny synthetic chart
## a press too early for any window latches the next normal note of its light (judged when it lands, <= GREAT);
## a press that is too early even for the snap is a stray; a real press in time still wins
extends SceneTree

func chart() -> Dictionary:
	var U := 1.0 / 15.0
	return {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "from": "L", "x": 3.75 * U, "w": 4.0 * U, "reach": 1.0}],
		"notes": [{"t": 3.0, "light": 0, "u": 0.5625, "kind": "tap"}]}

func run(name: String, steps: Array, want: String) -> bool:
	GameCore.snap = true      # the mechanism is off in the game (2026-10-18) but still kept and tested
	var core := GameCore.new()
	core.load_chart(chart())
	core.playing = true
	var t := 0.0
	var i := 0
	while t < 4.0:
		while i < steps.size() and steps[i][0] <= t:
			var s: Array = steps[i]
			if s[1] == "down": core.press_key(s[2], s[0])
			else: core.release_key(s[2], s[0])
			i += 1
		core.update(t)
		t += 1.0 / 120.0
	var got: String = core.notes[0].grade
	print("%-46s %s  (want %s)" % [name, got, want])
	return got == want

func _init() -> void:
	KB.set_layout("ansi")
	var ok := true
	ok = run("tap 0.25 s early, released -> snaps (GREAT)", [[2.75, "down", "KeyD"], [2.82, "up", "KeyD"]], "GREAT") and ok
	ok = run("tap 0.4 s early -> stray, note missed", [[2.6, "down", "KeyD"], [2.67, "up", "KeyD"]], "MISS") and ok
	ok = run("early tap, then a real press in time wins", [[2.75, "down", "KeyD"], [2.8, "up", "KeyD"], [3.01, "down", "KeyS"]], "PERFECT") and ok
	ok = run("early tap on a key outside the light", [[2.75, "down", "KeyL"], [2.8, "up", "KeyL"]], "MISS") and ok
	print("SNAP RULES: ", "PASS" if ok else "FAIL")
	quit()
