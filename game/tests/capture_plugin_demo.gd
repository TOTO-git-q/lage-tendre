## Actual P6 draw evidence. Xvfb + Dummy audio, with a dedicated HOME/XDG.
## --song=glow_ring|script_trust --trust=allow|deny --time=9.25 --out=absolute.png
extends "capture_render.gd"

var session: SongPluginSession
var plugin_draws := {}

func _run() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() != "Dummy" or not args.has("isolated-test-user"):
		push_error("Use Xvfb, Dummy audio and --isolated-test-user with isolated HOME/XDG.")
		quit(2); return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	KB.set_layout("ansi")
	var song := str(args.get("song", "glow_ring"))
	if song not in ["glow_ring", "script_trust"]:
		push_error("Unknown P6 sample"); quit(2); return
	var songs_root := str(args.get("songs-root", ProjectSettings.globalize_path("res://../songs")))
	if not songs_root.is_absolute_path() or not DirAccess.dir_exists_absolute(songs_root):
		push_error("An existing absolute external songs root is required"); quit(1); return
	var folder := songs_root.path_join("_plugin_demos").path_join(song)
	var raw: Dictionary = SU.load_json(folder.path_join("chart.json"))
	session = SongPluginSession.new()
	var report := session.prepare(folder, raw, "_plugin_demos/" + song)
	if not report.errors.is_empty():
		push_error(str(report.errors)); quit(1); return
	if not report.script_ids.is_empty():
		if str(args.get("trust", "")) not in ["allow", "deny"]:
			push_error("Explicit capture-test --trust=allow|deny required"); quit(2); return
		if not session.remember_trust(args.trust == "allow"):
			push_error(str(session.report.errors)); quit(1); return
	var opened := session.open()
	if not opened.errors.is_empty():
		push_error(str(opened.errors)); quit(1); return
	core = GameCore.new(session.registry)
	if not core.load_chart(session.chart_data):
		push_error("Cannot load sample chart"); quit(1); return
	meta = {"title": raw.meta.title, "artist": raw.meta.artist, "version": raw.meta.version, "dir": "_plugin_demos/" + song, "level": 2}
	renderer = Renderer.new(session.registry); root.add_child(renderer)
	renderer._rng.seed = SEED; renderer.note_scale = 1.5; renderer.hint_mode = "off"
	renderer.curve = "deemo"; renderer.line_l = 0.0; renderer.line_r = SU.LW * 15.0 / KB.span()
	core.stage.mode = "full"; core.autoplay = true; core.playing = true
	core.ripple.connect(renderer.add_ripple); core.judged.connect(renderer.add_judge)
	core.hold_end.connect(renderer.add_hold_end); core.combo_break.connect(renderer.add_combo_break); core.cue_judged.connect(_on_cue)
	for name in renderer.L:
		if str(name).begins_with("plugin."):
			var layer = renderer.L[name]
			layer.painter = _count_plugin_draw.bind(layer.painter, name)
	var target := float(args.get("time", "9.25"))
	var start := maxf(0.0, target - 2.0)
	if start > 0.0: core.skip_before(start - 0.05)
	_frame(start, 0.0); await RenderingServer.frame_post_draw
	var steps := int(round((target - start) * FPS))
	for index in range(1, steps + 1):
		_frame(start + float(index) / FPS, float(index) / FPS)
		await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var output := str(args.get("out", ""))
	if screenshot.get_size() != Vector2i(1600, 900) or screenshot.save_png(output) != OK:
		push_error("Cannot save 1600x900 sample screenshot"); quit(1); return
	var ring_provider: PluginDeclarative = session.registry.get_entry("elements", "glow_ring").callback.get_object()
	var evidence := {"song": song, "trust": args.get("trust", "declarative"), "identity": session.identity.duplicate(), "disabled": opened.disabled,
		"content_hash": report.content_hash, "time": target, "resolution": [1600, 900], "plugin_draws": plugin_draws,
		"ring_primitives": ring_provider.ring_primitives(renderer._runtime, "glow_ring").size(), "notices": session.runtime_notices()}
	ring_provider = null
	renderer.free(); renderer = null; core = null; session.close()
	evidence.marker_removed_after_close = not FileAccess.file_exists("user://plugin_demos/trust_spark_loaded.txt")
	SU.save_json(output.get_basename() + ".json", evidence)
	print("PLUGIN CAPTURE ", JSON.stringify(evidence))
	quit()

func _count_plugin_draw(canvas: CanvasItem, painter: Callable, name: String) -> void:
	painter.call(canvas)
	plugin_draws[name] = int(plugin_draws.get(name, 0)) + 1
