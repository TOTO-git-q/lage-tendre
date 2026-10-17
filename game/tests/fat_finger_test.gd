## godot --headless --path . -s tests/fat_finger_test.gd -- <song_dir>
## the home-key player (every note on its fingering key, on time) who also brushes a neighbouring key 5-30 ms after
## each tap: the stray press must not eat a later note (CHUNITHM's midpoint window cut) -- prints how many notes
## were taken by a stray key or lost their PERFECT
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
	var busy := {}                  # key -> note times on it (a stray never uses a key needed nearby)
	for n in core.notes:
		if n.k < 0: continue
		ev.append([n.t, "down", HOME[n.k], n.id])
		ev.append([n.t + (n.dur if n.kind == "hold" else 0.05), "up", HOME[n.k], n.id])
		busy[n.k] = busy.get(n.k, []) + [n.t]
	var strays := 0
	for n in core.notes:
		if n.k < 0 or n.kind == "hold": continue
		var nb: int = n.k + (1 if (n.id % 2 == 0 and n.k < 10) or n.k == 0 else -1)
		var at: float = n.t + 0.005 + float((n.id * 7) % 26) / 1000.0
		var clash := false
		for t2 in busy.get(nb, []):
			if absf(t2 - at) < 0.12: clash = true
		if clash: continue
		ev.append([at, "down", HOME[nb], -1]); ev.append([at + 0.04, "up", HOME[nb], -1])
		strays += 1
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
					core.press_key(e[2], e[0])
				"up": core.release_key(e[2], e[0])
				"space_down": core.press_space(e[0])
				"space_up": core.release_space(e[0])
			i += 1
		core.update(t)
		t += 1.0 / 240.0
	var stolen := 0
	var bad := 0
	for n in core.notes:
		if n.k >= 0 and n.key != "" and n.key != HOME[n.k] and not n.ex: stolen += 1
		if n.grade != "PERFECT": bad += 1
	var s := core.stats
	print("fat-finger on %s: %d strays, notes taken by a stray key: %d, not PERFECT: %d, MISS %d, score %d" % [song, strays, stolen, bad, s.MISS, s.score])
	quit()
