## Deterministic gameplay-only evidence. No production script is instrumented.
## Run under Xvfb with Dummy audio. Calls the real core, renderer and draw callbacks.
extends SceneTree

const FPS := 60
const SEED := 20261017
var args := {}
var renderer: Renderer
var core: GameCore
var meta := {}
var draw_usec := 0
var draw_calls := 0
var layer_usec := {}
var measured := false
var evidence_session: SongPluginSession
var rule_usec := {}

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A real Xvfb renderer is required; headless cannot capture pixels.")
		quit(1); return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	KB.set_layout("ansi")
	var song := str(args.get("song", "fixture_dense"))
	var song_root := ProjectSettings.globalize_path("res://../songs")
	var raw = ChartLib.demo() if song == "demo" else SU.load_json(song_root.path_join("../game/tests/fixtures/dense" if song == "fixture_dense" else song).path_join("chart.json"))
	var scope: PluginRegistry = PluginRegistry.standard()
	if song.begins_with("_plugin_demos/"):
		evidence_session = SongPluginSession.new()
		var report := evidence_session.prepare(song_root.path_join(song), raw, song)
		if not report.errors.is_empty() or report.requires_trust:
			push_error(str(report)); quit(1); return
		var opened := evidence_session.open()
		if not opened.errors.is_empty():
			push_error(str(opened)); quit(1); return
		scope = evidence_session.registry
		raw = evidence_session.chart_data
	core = GameCore.new(scope)
	if not core.load_chart(raw):
		push_error("Cannot load evidence chart: " + song)
		quit(1); return
	meta = {"title": "DEMO", "artist": "L’âge tendre", "version": "TUTORIAL", "dir": song, "level": 3}
	for entry in SU.load_json(song_root.path_join("index.json"), []):
		if entry.dir == song:
			meta = {"title": entry.title, "artist": entry.artist, "version": entry.version, "dir": song, "level": entry.level}
	renderer = Renderer.new(scope)
	if args.has("profile"):
		renderer._runtime.free()
		renderer._runtime = preload("res://tests/perf_render_profile.gd").new()
		renderer._runtime.configure(scope)
		renderer.add_child(renderer._runtime)
		var callbacks: Array = core._runtime.pipeline._phases.update
		for index in callbacks.size():
			callbacks[index] = _timed_rule.bind(callbacks[index], str(index))
	root.add_child(renderer)
	renderer._rng.seed = SEED
	renderer.note_scale = 1.5
	renderer.hint_mode = "off"
	renderer.curve = "deemo"
	renderer.line_l = 0.0
	renderer.line_r = SU.LW * 15.0 / KB.span()
	core.stage.mode = "full"
	core.autoplay = true
	core.playing = true
	core.ripple.connect(renderer.add_ripple)
	core.judged.connect(renderer.add_judge)
	core.hold_end.connect(renderer.add_hold_end)
	core.combo_break.connect(renderer.add_combo_break)
	core.cue_judged.connect(_on_cue)
	for name in renderer.L:
		var layer = renderer.L[name]
		layer.painter = _timed_painter.bind(layer.painter, name)
	var target := float(args.get("time", "3.0"))
	var start := maxf(0.0, target - 2.0)
	if args.get("mode", "shot") == "performance": start = 0.0
	if start > 0.0: core.skip_before(start - 0.05)
	# Initialize frame data before the first draw, as in the application's first process.
	_frame(start, 0.0)
	await RenderingServer.frame_post_draw
	if args.get("mode", "shot") == "performance":
		await _performance()
	else:
		var steps := int(round((target - start) * FPS))
		for index in range(1, steps + 1):
			_frame(start + float(index) / FPS, float(index) / FPS)
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.get_size() != Vector2i(1600, 900):
			push_error("Unexpected screenshot dimensions: " + str(image.get_size()))
			quit(1); return
		var output := str(args.get("out", ""))
		if image.save_png(output) != OK:
			push_error("Cannot save screenshot: " + output)
			quit(1); return
		print("CAPTURE song=%s chart_time=%.9f size=1600x900 seed=%d frames=%d path=%s" % [song, target, SEED, steps + 1, output])
	renderer.free()
	core = null
	if evidence_session != null: evidence_session.close()
	quit()

func _timed_rule(context: Dictionary, callback: Callable, key: String) -> void:
	var before := Time.get_ticks_usec()
	callback.call(context)
	if measured: rule_usec[key] = int(rule_usec.get(key, 0)) + Time.get_ticks_usec() - before

func _timed_painter(canvas: CanvasItem, painter: Callable, name: String) -> void:
	var before := Time.get_ticks_usec()
	painter.call(canvas)
	if measured:
		var elapsed := Time.get_ticks_usec() - before
		draw_usec += elapsed
		draw_calls += 1
		layer_usec[name] = int(layer_usec.get(name, 0)) + elapsed

func _on_cue(cue: Dictionary, grade: String) -> void:
	if grade != "MISS": renderer.add_cue_ring(cue.yellow, cue.from)
	renderer.add_cue_text(grade, cue.from)

func _frame(t: float, elapsed: float) -> Dictionary:
	var before := Time.get_ticks_usec()
	core.update(t)
	var update_usec := Time.get_ticks_usec() - before
	var lights := core.light_states(t, 1.0)
	var by_id := {}
	for light in lights: by_id[light.id] = light
	var fd := {"t": t, "fxT": t, "perf": elapsed, "dt": 1.0 / FPS,
		"lights": lights, "light_by_id": by_id, "notes": core.notes, "cues": core.cues,
		"fall": 1.5, "reach": 1.0, "tl": core.tl, "chart": core.chart,
		"phase": core.chart.notes[0].t if not core.chart.notes.is_empty() else 0.0,
		"stats": core.stats, "play": true, "space_down": core.space_down,
		"hit_log": core.hit_log, "chords": core.chords, "meta": meta,
		"progress": clampf(t / core.end_time, 0.0, 1.0), "countdown": 0.0, "ending": {}}
	before = Time.get_ticks_usec()
	renderer.frame(fd, core.stage)
	return {"update_usec": update_usec, "frame_usec": Time.get_ticks_usec() - before}

func _performance() -> void:
	# Warm caches on the same first second, then restart the chart and RNG identically.
	for frame in range(1, FPS + 1):
		_frame(float(frame) / FPS, float(frame) / FPS)
		await RenderingServer.frame_post_draw
	core.reset_run(); core.playing = true
	renderer.clear_fx(); renderer._rng.seed = SEED
	renderer.flow_t = -999.0
	layer_usec.clear()
	rule_usec.clear()
	if args.has("profile"):
		renderer._runtime.timings.clear()
		renderer._runtime.counts.clear()
	var samples := []
	var updates := []
	var frames := []
	var draws := []
	var calls := 0
	var started := Time.get_ticks_usec()
	for index in range(1, 30 * FPS + 1):
		draw_usec = 0; draw_calls = 0; measured = true
		var sample := _frame(float(index) / FPS, float(index) / FPS)
		await RenderingServer.frame_post_draw
		measured = false
		if draw_calls != renderer.L.size():
			push_error("Missing or duplicate draw callbacks on frame %d: %d" % [index, draw_calls])
			quit(1); return
		updates.append(sample.update_usec); frames.append(sample.frame_usec); draws.append(draw_usec)
		samples.append(sample.update_usec + sample.frame_usec + draw_usec)
		calls += draw_calls
		# Never accelerate the required 30 seconds of rendered autoplay.
		var deadline := started + int(float(index) / FPS * 1e6)
		if Time.get_ticks_usec() < deadline:
			await create_timer(float(deadline - Time.get_ticks_usec()) / 1e6).timeout
	# SceneTree timers may fire a fraction of a frame early on Windows.
	# Wait for the real monotonic deadline instead of rounding the receipt.
	while Time.get_ticks_usec() - started < 30000000:
		await process_frame
	var wall_seconds := (Time.get_ticks_usec() - started) / 1e6
	var sorted := samples.duplicate(); sorted.sort()
	var total := 0.0
	for sample in samples: total += sample
	var result := {"schema": 1, "scope": "GameCore.update+Renderer.frame+Renderer.draw_callbacks",
		"duration_seconds": 30.0, "wall_duration_seconds": wall_seconds,
		"frames": samples.size(), "fps": FPS, "draw_callbacks": calls,
		"song": args.get("song", "fixture_dense"), "seed": SEED, "resolution": [1600, 900],
		"godot": Engine.get_version_info().string,
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"mean_usec": total / samples.size(), "p95_usec": sorted[int(ceil(samples.size() * 0.95)) - 1],
		"samples_usec": samples, "update_samples_usec": updates, "frame_samples_usec": frames,
		"draw_samples_usec": draws, "layer_total_usec": layer_usec,
		"measurement_note": "CPU update, frame preparation and all real CanvasItem draw callbacks. GPU submission and idle time excluded."}
	if args.has("profile"):
		result["primitive_total_usec"] = renderer._runtime.timings
		result["primitive_calls"] = renderer._runtime.counts
		result["rule_total_usec"] = rule_usec
	SU.save_json(str(args.get("out", "")), result)
	print("PERFORMANCE frames=%d wall=%.3fs mean=%.3fus p95=%.3fus callbacks=%d" % [samples.size(), wall_seconds, result.mean_usec, result.p95_usec, calls])
