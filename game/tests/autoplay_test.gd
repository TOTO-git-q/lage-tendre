## Headless logic check: autoplay every chart in simulated time; all items must be PERFECT.
##   godot --headless --path . -s tests/autoplay_test.gd
extends SceneTree

func _init() -> void:
	KB.set_layout("ansi")
	var dir := ProjectSettings.globalize_path("res://").path_join("../songs").simplify_path()
	var idx = SU.load_json(dir.path_join("index.json"), [])
	var list: Array = [{"dir": "demo"}] + idx
	var bad := 0
	for e in list:
		var core := GameCore.new()
		var raw = ChartLib.demo() if e.dir == "demo" else SU.load_json(dir.path_join(e.dir).path_join("chart.json"))
		if not core.load_chart(raw):
			print("LOAD FAIL ", e.dir); bad += 1; continue
		core.autoplay = true
		core.playing = true
		var misses := []
		var on_judged := func(g, xl, dt): if g == "MISS": misses.append(core.clock_now)
		core.judged.connect(on_judged)
		var t := 0.0
		while core.playing and t < core.end_time + 2.0:
			core.update(t)
			t += 1.0 / 60.0
		var st: Dictionary = core.stats
		var ok: bool = st.PERFECT == st.total and st.MISS == 0
		if not ok: bad += 1
		print("%s %-18s total=%d P=%d G=%d g=%d M=%d score=%d warn=%d %s" % ["OK " if ok else "BAD", e.dir, st.total, st.PERFECT, st.GREAT, st.GOOD, st.MISS, st.score, core.chart.warnings.size(), str(misses.slice(0, 5))])
		# Test-only teardown: the callback captures core; disconnect its reference cycle.
		core.judged.disconnect(on_judged)
	print("bad charts: ", bad)
	quit()
