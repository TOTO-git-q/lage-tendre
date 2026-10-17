## Run the frozen original and current core on the same events, compare public state.
extends SceneTree
var checks := 0
var failures := 0
const FIELDS := ["state", "lineX", "grade", "headGrade", "tick_i", "gap", "gap_t", "held_t", "held_since", "last_ts", "body_done", "auto", "hitDt", "hitX"]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 8: printerr("FAIL ", label)

func _init() -> void: run.call_deferred()

func run() -> void:
	KB.set_layout("ansi")
	var baseline := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-runtime="): baseline = argument.trim_prefix("--baseline-runtime=")
	if not baseline.is_absolute_path() or not FileAccess.file_exists(baseline):
		push_error("An absolute frozen original core source is required"); quit(1); return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(baseline).replace("class_name BuiltinGameRuntime\n", "")
	if script.reload() != OK: quit(1); return
	for song in ["fixture_dense", "_demo", "demo"]:
		for auto in [false, true]:
			var scope := PluginRegistry.standard()
			var before = script.new(); before.configure(scope)
			var after := BuiltinGameRuntime.new(); after.configure(scope)
			var raw: Dictionary = ChartLib.demo() if song == "demo" else SU.load_json(ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json" if song == "fixture_dense" else "res://../songs/" + song + "/chart.json"))
			check(before.load_chart(raw) and after.load_chart(raw) and not after.notes.is_empty(), "both actual runtimes load notes")
			before.autoplay = auto; after.autoplay = auto
			before.playing = true; after.playing = true
			var old_events := []; var new_events := []
			before.judged.connect(func(grade, x, dt): old_events.append([grade, x, dt]))
			after.judged.connect(func(grade, x, dt): new_events.append([grade, x, dt]))
			for ts in [-0.1, 0.0, 0.3, 1.0, 3.75, 8.0, 11.4, 20.0, 20.04, 22.75, 30.0, 40.0, 60.0, 80.0, 92.0, 120.0, 180.0]:
				before.update(ts); after.update(ts)
				check(before.stats == after.stats and before.hit_log == after.hit_log, "exact score and timing log")
				check(old_events == new_events, "exact ordered judgement feedback")
				for i in after.notes.size():
					for key in FIELDS: check(before.notes[i].get(key) == after.notes[i].get(key), "exact public note field " + key)
				for i in after.cues.size(): check(before.cues[i] == after.cues[i], "exact public cue")
	print("PERF UPDATE EQUIVALENCE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
