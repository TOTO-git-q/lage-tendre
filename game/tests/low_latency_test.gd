## Real app transitions and persistence, with an explicit isolated test user.
extends SceneTree

const App = preload("res://scripts/main.gd")
var failures := 0
var checks := 0
var app
var normal_vsync: int
var normal_fps: int
var normal_input: bool

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func pacing(low: bool, label: String) -> void:
	check(Engine.max_fps == (240 if low else normal_fps), label + " FPS cap")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_vsync_mode() == (DisplayServer.VSYNC_DISABLED if low else normal_vsync), label + " vsync")
	check(Input.use_accumulated_input == (false if low else normal_input), label + " input")

func _init() -> void: run.call_deferred()

func free_app() -> void:
	for effect in [app._w.res._fx, app._w.res._grain]:
		if effect.get_parent() == null: effect.free()
	app.free(); app = null

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-shots="):
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var output := argument.trim_prefix("--ui-shots=").path_join(name + ".png")
			check(root.get_texture().get_image().save_png(output) == OK, "settings screenshot " + name)

func run() -> void:
	if not "--isolated-test-user" in OS.get_cmdline_user_args() or AudioServer.get_driver_name() != "Dummy":
		push_error("Use isolated APPDATA and Dummy audio"); quit(2); return
	var path := "user://settings.json"
	var existed := FileAccess.file_exists(path)
	var original := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	SU.save_json(path, {})
	# Deliberately nondefault values prove restoration uses the captured settings.
	normal_vsync = DisplayServer.window_get_vsync_mode()
	normal_fps = 73; Engine.max_fps = normal_fps
	normal_input = Input.use_accumulated_input
	app = App.new(); root.add_child(app)
	app.set_process(false)
	check(not app.settings.low_latency, "default off with absent setting")
	app.state = "playing"; pacing(false, "default play")
	app.state = "menu"; app._enter_settings()
	await capture("low_latency_off")
	app._w.low_latency.pressed.emit()
	await capture("low_latency_on")
	check(app.settings.low_latency and SU.load_json(path).low_latency, "UI toggle persists true")
	check(app._w.low_latency.text == "开 ON", "bilingual on state")
	pacing(false, "enabled settings")
	app._exit_settings()
	app._play_selected()
	check(app.state == "playing", "real start enters play")
	pacing(true, "play")
	app._pause(); pacing(true, "pause keeps play pacing (no vsync switch on Esc)")
	app._enter_settings(); pacing(false, "settings from pause")
	app._exit_settings(); pacing(true, "back to pause")
	app._resume(); pacing(true, "resume countdown")
	app.resume_at = SU.ticks() - 1
	app._process(0.0)
	check(app.state == "playing", "countdown finishes")
	pacing(true, "resumed play")
	app._pacing_changed_at = SU.ticks()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.state == "playing", "focus blip right after a vsync switch does not pause")
	app._pacing_changed_at = SU.ticks() - 1000000
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.state == "paused", "focus loss pauses")
	pacing(true, "focus pause")
	app._restart(); pacing(true, "restart")
	app._on_finished(app.core.stats); pacing(false, "result immediately")
	app._quit_to_songs(); pacing(false, "song menu")
	for state in ["menu", "songs", "loading", "plugin_trust", "settings", "calib", "sync", "result"]:
		app.state = state; pacing(false, state)
	app.state = "paused"; pacing(true, "paused")
	app.state = "playing"; pacing(true, "before shutdown")
	free_app()
	pacing(false, "shutdown restores")
	app = App.new(); root.add_child(app); app.set_process(false)
	check(app.settings.low_latency, "new app reloads persisted true")
	app._enter_settings(); app._w.low_latency.pressed.emit()
	check(not SU.load_json(path).low_latency and app._w.low_latency.text == "关 OFF", "UI persists off")
	for state in ["playing", "resuming", "paused", "result", "menu"]:
		app.state = state; pacing(false, "disabled " + state)
	free_app()
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(original); file.close()
	else: DirAccess.remove_absolute(path)
	Engine.max_fps = 0
	print("LOW LATENCY: ", checks, " checks, ", failures, " failures; agile=", ProjectSettings.get_setting("input_devices/buffering/agile_event_flushing"), " low_processor=", OS.low_processor_usage_mode)
	quit(1 if failures else 0)
