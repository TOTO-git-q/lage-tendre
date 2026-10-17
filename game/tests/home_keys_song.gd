## godot --headless --path . -s tests/home_keys_song.gd -- <song_dir>
## a player who presses each note's suggested home-row key (the fingering letter) exactly on time must hit everything:
## with moving tracks this checks that every note's track really sits over that key when the note lands
extends SceneTree

const HOME := ["KeyA", "KeyS", "KeyD", "KeyF", "KeyG", "KeyH", "KeyJ", "KeyK", "KeyL", "Semicolon", "Quote"]

func _init() -> void:
	KB.set_layout("ansi")
	var song: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "fixture_dense"
	var raw = SU.load_json(ProjectSettings.globalize_path("res://").path_join("../songs").path_join("../game/tests/fixtures/dense" if song == "fixture_dense" else song).path_join("chart.json"))
	var core := GameCore.new()
	core.load_chart(raw)
	core.playing = true
	var ev := []
	for n in core.notes:
		if n.k < 0: continue
		ev.append([n.t, "down", HOME[n.k], n.id])
		ev.append([n.t + (n.dur if n.kind == "hold" else 0.05), "up", HOME[n.k], n.id])
	for c in core.cues:
		ev.append([c.t, "space_down", "", -1]); ev.append([c.t + maxf(0.05, c.dur), "space_up", "", -1])
	ev.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1].ends_with("up") and not b[1].ends_with("up")))
	var t := 0.0
	var i := 0
	while t < core.end_time:
		while i < ev.size() and ev[i][0] <= t:
			var e: Array = ev[i]
			match e[1]:
				"down":
					if core.down.has(e[2]): core.release_key(e[2], e[0] - 0.001)
					var r = core.press_key(e[2], e[0])
					if OS.get_environment("HK_DEBUG") != "" and (r == null or r.id != e[3]):
						print("  press %s at %.4f for note %d -> %s" % [e[2], e[0], e[3], "null" if r == null else "note %d (t=%.4f k=%d)" % [r.id, r.t, r.k]])
				"up": core.release_key(e[2], e[0])
				"space_down": core.press_space(e[0])
				"space_up": core.release_space(e[0])
			i += 1
		core.update(t)
		t += 1.0 / 240.0
	var bad := []
	for n in core.notes:
		if n.grade != "PERFECT": bad.append("%.3f k=%d %s" % [n.t, n.k, n.grade])
	print("home-key player on %s: %d notes, not PERFECT: %d  %s" % [song, core.notes.size(), bad.size(), str(bad.slice(0, 8))])
	quit()
