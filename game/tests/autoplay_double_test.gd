## godot --headless --path . -s tests/autoplay_double_test.gd [-- <song_dir> ...]
## the slap player: autoplay presses the note's key AND a neighbouring key of the same track for every note -- at the very
## same instant, and again 8 ms later.  Owner, 2026-10-16: pressing two keys for every note must still be an All Perfect
## (1,010,000) -- the extra key is harmless.  Default charts: demo, fixture_dense, _demo (skipped if it
## does not validate).  Extra args: song dirs (replace the default list).
extends SceneTree

func _run(raw, extra_ms: float) -> Dictionary:
	var core := GameCore.new()
	if not core.load_chart(raw): return {}
	core.autoplay = true
	core.autoplay_extra = 1
	core.autoplay_extra_ms = extra_ms
	core.playing = true
	var t := 0.0
	while core.playing and t < core.end_time + 2.0:
		core.update(t)
		t += 1.0 / 60.0
	var s: Dictionary = core.stats
	s["strays"] = core.strays.size()
	return s

func _init() -> void:
	KB.set_layout("ansi")
	var root := ProjectSettings.globalize_path("res://").path_join("../songs").simplify_path()
	var list: Array = Array(OS.get_cmdline_user_args()) if OS.get_cmdline_user_args().size() > 0 else ["demo", "fixture_dense", "_demo"]
	var bad := 0
	for d in list:
		var raw = ChartLib.demo() if d == "demo" else SU.load_json(root.path_join("../game/tests/fixtures/dense" if d == "fixture_dense" else d).path_join("chart.json"))
		if raw == null or not GameCore.new().load_chart(raw):
			print("SKIP %s (does not validate / missing)" % d); continue
		for ms in [0.0, 8.0]:
			var s := _run(raw, ms)
			var ok: bool = not s.is_empty() and s.PERFECT == s.total and s.MISS == 0 and s.score == 1010000
			if not ok: bad += 1
			print("%s %-18s extra +%.0f ms: total=%d P=%d G=%d g=%d M=%d crit=%d score=%d strays=%d" % ["PASS" if ok else "FAIL", d, ms, s.total, s.PERFECT, s.GREAT, s.GOOD, s.MISS, s.CRITICAL, s.score, s.strays])
	print("AUTOPLAY DOUBLE: ", "PASS" if bad == 0 else "FAIL (%d)" % bad)
	quit()
