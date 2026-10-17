## godot --headless --path . -s tests/track_chord_test.gd : chords inside one track still need one press per note --
## a 2-note / 3-note chord on a track A..L: one key judges one note, the rest MISS; 2 / 3 keys judge them all
extends SceneTree

func run(size: int, keys: Array) -> Array:
	var U := 1.0 / 15.0
	var notes := []
	for j in size:
		notes.append({"t": 3.0, "light": 0, "u": (2.25 + 2 * j - 1.75) / 9.0, "kind": "tap", "k": 2 * j})
	var chart := {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "x": (1.75 + 4.5) * U, "w": 9.0 * U, "auto": true}], "notes": notes}
	var core := GameCore.new()
	core.load_chart(chart)
	core.playing = true
	var t := 0.0
	var pressed := false
	while t < 4.0:
		if not pressed and t >= 3.0:
			for k in keys: core.press_key(k, t)
			pressed = true
		core.update(t)
		t += 1.0 / 240.0
	var hit := 0
	for n in core.notes: hit += int(n.grade == "PERFECT")
	return [hit, core.stats.MISS]

func _init() -> void:
	KB.set_layout("ansi")
	var ok := true
	for c in [[2, ["KeyA"], [1, 1]], [2, ["KeyA", "KeyS"], [2, 0]], [3, ["KeyA"], [1, 2]], [3, ["KeyA", "KeyS"], [2, 1]], [3, ["KeyA", "KeyS", "KeyD"], [3, 0]]]:
		var got := run(c[0], c[1])
		print("%d-note chord, keys %s -> PERFECT %d, MISS %d" % [c[0], str(c[1]), got[0], got[1]])
		ok = ok and got == c[2]
	print("TRACK CHORDS: ", "PASS" if ok else "FAIL")
	quit()
