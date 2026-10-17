## godot --headless --path . -s tests/track_any_key_test.gd : track-centric judgement -- in a light spanning A..L, pressing
## A for every note hits notes drawn at A S D F G (one press = one note, in time order)
extends SceneTree

func _init() -> void:
	KB.set_layout("ansi")
	var U := 1.0 / 15.0
	var notes := []
	for j in 5:
		notes.append({"t": 3.0 + 0.25 * j, "light": 0, "u": (2.25 + j - 1.75) / 9.0, "kind": "tap", "k": j})
	var chart := {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {},
		"lights": [{"t": 1.0, "id": 0, "type": "on", "x": (1.75 + 4.5) * U, "w": 9.0 * U, "auto": true}], "notes": notes}
	var core := GameCore.new()
	core.load_chart(chart)
	core.playing = true
	var got := []
	var t := 0.0
	var j := 0
	while t < 5.0:
		if j < 5 and t >= 3.0 + 0.25 * j:
			core.press_key("KeyA", t); core.release_key("KeyA", t + 0.05); j += 1
		core.update(t)
		t += 1.0 / 240.0
	for n in core.notes: got.append("%s:%s" % ["ASDFG"[n.k], n.grade])
	print("A x5 on a track A..L -> ", got)
	print("TRACK ANY KEY: ", "PASS" if got == ["A:PERFECT", "S:PERFECT", "D:PERFECT", "F:PERFECT", "G:PERFECT"] else "FAIL")
	quit()
