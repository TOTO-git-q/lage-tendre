## godot --headless --path . -s tests/one_chart.gd -- <song dir>   : validate + autoplay one chart
extends SceneTree
func _init() -> void:
	KB.set_layout("ansi")
	var dir: String = OS.get_cmdline_user_args()[0]
	var root := ProjectSettings.globalize_path("res://").path_join("../songs").simplify_path()
	var raw = SU.load_json(root.path_join("../game/tests/fixtures/dense" if dir == "fixture_dense" else dir).path_join("chart.json"))
	var core := GameCore.new()
	if not core.load_chart(raw):
		print("LOAD FAIL"); quit(); return
	print("validated: notes %d -> %d, lights %d -> %d, warnings %d" % [raw.notes.size(), core.chart.notes.size(), raw.lights.size(), core.chart.lights.size(), core.chart.warnings.size()])
	for w in core.chart.warnings.slice(0, 12): print("  ", w)
	print("cues: ", core.cues.size(), "  stage majors: ", core.stage.summary.get("majors", []))
	core.autoplay = true
	core.playing = true
	var t := 0.0
	while core.playing and t < core.end_time + 2.0:
		core.update(t)
		t += 1.0 / 60.0
	var st: Dictionary = core.stats
	print("autoplay: total=%d P=%d G=%d g=%d M=%d crit=%d score=%d" % [st.total, st.PERFECT, st.GREAT, st.GOOD, st.MISS, st.CRITICAL, st.score])
	quit()
