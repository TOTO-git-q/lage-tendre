## godot --headless --path . -s tests/replay_log.gd -- <playlog.json> <song_dir> [cut=1] [guard=0] [track] [reach=2]
## replays a real play log's key presses (the hits' keys at t + hitDt and every stray) through GameCore under a rule
## variant, to measure how many of a human's presses a judgement change would turn into hits
extends SceneTree

func _init() -> void:
	KB.set_layout("ansi")
	var a := OS.get_cmdline_user_args()
	var log = SU.load_json(a[0])
	var raw = SU.load_json(ProjectSettings.globalize_path("res://").path_join("../songs").path_join("../game/tests/fixtures/dense" if a[1] == "fixture_dense" else a[1]).path_join("chart.json"))
	GameCore.cut_windows = a.size() < 3 or a[2] != "0"
	if a.size() >= 4: GameCore.cluster_guard = a[3] != "0"
	if a.size() >= 4 and a[3] != "0" and a[3] != "1": GameCore.cluster_s = float(a[3])
	if a.size() >= 6: GameCore.cluster_reach = float(a[5])
	GameCore.cut_same_track = a.size() < 5 or a[4] != "key"
	if a.size() >= 7: GameCore.cut_by_landing = a[6] != "0"
	var ev := []
	for n in log.notes:
		if n.key != "" and n.hitDt != null and n.state != "skip":
			var t: float = n.t + n.hitDt
			ev.append([t, "down", n.key]); ev.append([t + (n.dur if n.dur > 0.0 else 0.08), "up", n.key])
	for s in log.strays:
		ev.append([s.ts, "down", s.key]); ev.append([s.ts + 0.08, "up", s.key])
	for c in log.cues:
		if c.hitDt != null: ev.append([c.t + c.hitDt, "sdown", ""]); ev.append([c.t + c.hitDt + maxf(0.05, c.dur), "sup", ""])
	ev.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1].ends_with("up") and not y[1].ends_with("up")))
	var core := GameCore.new()
	core.load_chart(raw)
	core.playing = true
	var t := 0.0
	var i := 0
	var end: float = ev[-1][0] + 1.0
	while t < end:
		while i < ev.size() and ev[i][0] <= t:
			var e: Array = ev[i]
			match e[1]:
				"down":
					if core.down.has(e[2]): core.release_key(e[2], e[0] - 0.001)
					core.press_key(e[2], e[0])
				"up": core.release_key(e[2], e[0])
				"sdown": core.press_space(e[0])
				"sup": core.release_space(e[0])
			i += 1
		core.update(t)
		t += 1.0 / 240.0
	var s := core.stats
	print("replay cut=%s%s guard=%s  P=%d G=%d g=%d MISS=%d strays=%d maxCombo=%d acc=%.4f" % [GameCore.cut_windows, "(track)" if GameCore.cut_same_track else "", str(GameCore.cluster_s) if GameCore.cluster_guard else "off", s.PERFECT, s.GREAT, s.GOOD, s.MISS, core.strays.size(), s.maxCombo, s.accuracyLive])
	if OS.get_environment("DBG") != "":
		for b in core.debug_blocked:
			var nn: Dictionary = core.notes[b.id]
			print("BLOCK ts=%.3f %s would take id%d t=%.3f (light %d, final %s %s dt%.0f key=%s)" % [b.ts, b.code, b.id, b.nt, b.nlight, nn.state, nn.grade, nn.hitDt * 1000, nn.key])
	quit()
