## godot --headless --path . -s tests/extap_test.gd    : yellow (ExTap) notes after CHUNITHM
## a key already held inside the track catches a yellow note (owner 2026-10-16); a press inside its window is CRITICAL;
## a roll across a yellow chain on neighbouring keys takes each note on its own key
extends SceneTree

func chart() -> Dictionary:
	# wide left light A..F; one lone yellow note at 3.0 (D), then a 4-note chain A S D F 60 ms apart from 4.0
	var U := 1.0 / 15.0
	var notes := [{"t": 3.0, "light": 0, "u": 0.5625, "kind": "tap", "ex": true, "k": 2}]
	for j in 4:
		notes.append({"t": 4.0 + 0.06 * j, "light": 0, "u": (2.25 + j - 1.75) / 4.0, "kind": "tap", "ex": true, "k": j})
	return {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "x": 3.75 * U, "w": 4.0 * U, "auto": true}], "notes": notes}

func run(name: String, steps: Array, want: Array) -> bool:
	var core := GameCore.new()
	core.load_chart(chart())
	core.playing = true
	var t := 0.0
	var i := 0
	while t < 5.0:
		while i < steps.size() and steps[i][0] <= t:
			var s: Array = steps[i]
			if s[1] == "down": core.press_key(s[2], s[0])
			else: core.release_key(s[2], s[0])
			i += 1
		core.update(t)
		t += 1.0 / 240.0
	var got := []
	for n in core.notes: got.append("%s/%s" % [n.grade, n.key])
	print("%-46s %s" % [name, str(got)])
	return got == want

func _init() -> void:
	KB.set_layout("ansi")
	var ok := true
	var chain := ["PERFECT/KeyA", "PERFECT/KeyS", "PERFECT/KeyD", "PERFECT/KeyF"]
	ok = run("press 0.12 s late, then roll the chain", [[3.12, "down", "KeyD"], [3.2, "up", "KeyD"],
		[4.0, "down", "KeyA"], [4.06, "down", "KeyS"], [4.12, "down", "KeyD"], [4.18, "down", "KeyF"]], ["PERFECT/KeyD"] + chain) and ok
	ok = run("key held from before catches the lone one", [[2.5, "down", "KeyD"], [3.5, "up", "KeyD"]], ["PERFECT/KeyD", "MISS/", "MISS/", "MISS/", "MISS/"]) and ok
	ok = run("one key held through the chain catches it all", [[3.9, "down", "KeyD"], [4.4, "up", "KeyD"]], ["MISS/", "PERFECT/KeyD", "PERFECT/KeyD", "PERFECT/KeyD", "PERFECT/KeyD"]) and ok
	ok = run("chain rolled 25 ms early", [[4.0 - 0.025, "down", "KeyA"], [4.035, "down", "KeyS"], [4.095, "down", "KeyD"], [4.155, "down", "KeyF"]],
		["MISS/"] + chain) and ok
	print("EXTAP RULES: ", "PASS" if ok else "FAIL")
	quit()
