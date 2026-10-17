## Exercises the real application's input path. Run tools/verify_menu_keys.py.
extends SceneTree

const App := preload("res://scripts/main.gd")
var app
var checks := 0
var failures := 0
var shots := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func key(code: int, shift := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code
	event.pressed = true; event.shift_pressed = shift; event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate(); event.pressed = false; event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func hover(control: Control) -> void:
	var event := InputEventMouseMotion.new()
	event.position = control.get_global_rect().get_center() * Vector2(1600.0 / 1920.0, 900.0 / 1080.0)
	event.relative = Vector2(1, 0)
	Input.parse_input_event(event); Input.flush_buffered_events()
	await process_frame

func capture(label: String, screen: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var nav = app._nav[screen]
	check(nav.available(nav.selected) and nav._placed, label + " has selected visible row")
	check(nav._rect.is_equal_approx(nav._target), label + " highlight settled")
	check(root.get_texture().get_image().save_png(shots.path_join(label + ".png")) == OK, "screenshot " + label)

func select_control(screen: String, control: Control) -> void:
	var nav = app._nav[screen]
	for i in nav.rows.size():
		if nav.rows[i].control == control or nav.rows[i].control.is_ancestor_of(control):
			nav.select(i); return
	check(false, "registered control " + screen)

func _init() -> void: run.call_deferred()

func write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content); file.close()

func trust_fixture(nonce: String) -> void:
	var folder := ProjectSettings.globalize_path("user://menu_trust_fixture")
	var plugin := folder.path_join("plugins/menu_test")
	var manifest := {"id": "menu_test", "version": "1.0.0", "api": 1, "tier": "script", "title": "Menu key test", "author": "Local test",
		"description": "Local trust action fixture", "provides": {"elements": ["menu_test_overlay"]}, "fields": [], "assets": [], "entry": "entry.gd"}
	write(plugin.path_join("plugin.json"), JSON.stringify(manifest))
	write(plugin.path_join("entry.gd"), "extends RefCounted\nstatic func install(registry, _manifest, _folder):\n\tvar file = FileAccess.open(\"user://menu_script_ran\", FileAccess.WRITE)\n\tfile.store_string(\"executed\")\n\tregistry.register(\"elements\", \"menu_test_overlay\", {\"phase\": \"ui_overlay\", \"callback\": paint})\nstatic func paint(_renderer, _canvas):\n\tpass\n")
	write(folder.path_join("nonce.txt"), nonce + str(Time.get_ticks_usec()))
	if FileAccess.file_exists("user://menu_script_ran"): DirAccess.remove_absolute("user://menu_script_ran")
	var raw := {"bpm": 120, "lights": [{"t": 0, "id": 0, "type": "on", "x": 0.5, "w": 0.5, "auto": true}],
		"notes": [{"t": 2, "light": 0, "kind": "tap", "u": 0.5}], "plugins": [{"id": "menu_test", "version": "1.0.0"}]}
	var session := SongPluginSession.new()
	var report := session.prepare(folder, raw, "menu_trust_fixture")
	check(report.errors.is_empty() and report.requires_trust, "local trust fixture needs decision")
	app._pending_play = {"session": session, "raw": raw, "from_t": 0.0,
		"meta": {"title": "Local trust fixture", "artist": "Local test", "version": "TEST", "dir": "demo", "level": 1}}
	app.state = "plugin_trust"
	app._show("PluginTrust")

func run() -> void:
	if not "--isolated-test-user" in OS.get_cmdline_user_args() or AudioServer.get_driver_name() != "Dummy":
		printerr("FAIL isolated user and Dummy audio required"); quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-shots="): shots = argument.trim_prefix("--ui-shots=")
	SU.save_json("user://settings.json", {"fullscreen": false, "keyguard": false})
	SU.save_json("user://calib.json", {"L": 0.0, "R": 1.0})
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	app = App.new(); root.add_child(app)
	app.set_process(false)
	await process_frame
	await capture("main", "Menu")
	var menu_nav = app._nav.Menu
	menu_nav.set_process(false)
	var previous_rect: Rect2 = menu_nav._rect
	await key(KEY_UP)
	check(app._nav.Menu.selected == 2, "main wraps upward")
	# Drive elapsed UI time explicitly so frame scheduling cannot mask the easing.
	menu_nav._process(0.0)
	check(menu_nav._rect.is_equal_approx(previous_rect) and not menu_nav._rect.is_equal_approx(menu_nav._target), "highlight eases instead of jumping")
	menu_nav._process(0.06)
	check(not menu_nav._rect.is_equal_approx(previous_rect) and not menu_nav._rect.is_equal_approx(menu_nav._target), "highlight moves through an intermediate position")
	menu_nav._process(0.06)
	check(menu_nav._rect.is_equal_approx(menu_nav._target), "highlight reaches row in 120ms")
	menu_nav.set_process(true)
	await key(KEY_DOWN)
	check(app._nav.Menu.selected == 0, "main wraps downward")
	await key(KEY_ENTER)
	check(app.state == "songs", "main Enter opens songs")
	# Use the existing multi-difficulty song without modifying song content.
	for i in app.songs.size():
		if app.songs[i].diffs.size() > 1:
			app.sel_d = 0; app._song_select(i, true); break
	var song: int = app.sel_i
	await key(KEY_RIGHT)
	check(app.sel_i == posmod(song + 1, app.songs.size()), "right changes song")
	await key(KEY_LEFT)
	check(app.sel_i == song, "left changes song back")
	var count: int = app.songs[app.sel_i].diffs.size()
	await key(KEY_UP)
	check(app.sel_d == count - 1 and app._nav.Songs.selected == app.sel_d, "difficulty wraps up and highlights")
	await key(KEY_DOWN)
	check(app.sel_d == 0 and app._nav.Songs.selected == 0, "difficulty wraps down")
	await capture("songs", "Songs")
	await hover(app._w.ss_play)
	check(app._nav.Songs.rows[app._nav.Songs.selected].control == app._w.ss_play, "hover highlights song Play action")
	await key(KEY_DOWN)
	check(app._nav.Songs.selected == app.sel_d, "difficulty keys restore chip selection after Play hover")
	check(app._w.ss_play.mouse_entered.get_connections().size() == 1, "song rebuild replaces hover connection")
	await hover(app._w.ss_diffs.get_child(0))
	check(app.sel_d == 0, "hover selects song difficulty")
	await key(KEY_ESCAPE)
	await key(KEY_DOWN)
	await key(KEY_SPACE)
	check(app.state == "settings" and app._nav.Settings.selected == 0, "Space opens settings at first row")
	var fall: float = app.settings.fall
	await key(KEY_RIGHT)
	check(is_equal_approx(app.settings.fall, fall + 0.05), "slider uses its step")
	await key(KEY_LEFT, true)
	check(is_equal_approx(app.settings.fall, fall - 0.20), "Shift slider uses five steps")
	check(is_equal_approx(float(SU.load_json("user://settings.json").fall), app.settings.fall), "slider persisted")
	await capture("settings_left", "Settings")
	select_control("Settings", app._w.curve_amt.slider)
	await key(KEY_RIGHT)
	check(is_equal_approx(app.settings.persp_deg, 36.0), "angle slider advances one representable degree")
	await key(KEY_LEFT, true)
	check(is_equal_approx(app.settings.persp_deg, 31.0), "angle Shift advances five degrees")
	select_control("Settings", app._w.curve)
	await key(KEY_RIGHT)
	check(app.settings.curve == "accel", "right cycles toggle")
	select_control("Settings", app._w.curve_amt.slider)
	await key(KEY_RIGHT)
	check(is_equal_approx(app.settings.accel_k, 1.75), "acceleration slider advances one representable step")
	await key(KEY_LEFT, true)
	check(is_equal_approx(app.settings.accel_k, 1.50), "acceleration Shift advances five steps")
	select_control("Settings", app._w.curve)
	await key(KEY_ENTER, false, true)
	check(app.settings.curve == "accel", "activation echo does not cycle toggle")
	await key(KEY_LEFT)
	check(app.settings.curve == "linear", "left cycles toggle")
	await key(KEY_DOWN)
	check(app._nav.Settings.rows[app._nav.Settings.selected].control == app._w.reach.slider.get_parent(), "navigation skips hidden curve row")
	check(app._w.reach.slider.get_parent().get_child(0).self_modulate.a > app._w.fall.slider.get_parent().get_child(0).self_modulate.a, "selected settings text brightens")
	# Every visible row in both columns is reachable by down; wrapping returns to zero.
	app._nav.Settings.select(0)
	var visited := []
	for i in app._nav.Settings.rows.size():
		if app._nav.Settings.selected in visited: break
		visited.append(app._nav.Settings.selected)
		await key(KEY_DOWN)
	var visible_count := 0
	for i in app._nav.Settings.rows.size():
		if app._nav.Settings.available(i): visible_count += 1
	check(visited.size() == visible_count and app._nav.Settings.selected == 0, "all visible settings rows reachable with wrap")
	select_control("Settings", app._w.seg.jis)
	await key(KEY_ENTER)
	check(app.settings.layout == "jis" and app.settings.layout_manual, "right column layout action")
	await capture("settings_right", "Settings")
	# Actual mouse event followed by keyboard changes the hovered row.
	await hover(app._w.offset.slider)
	var offset: int = app.settings.offset_ms
	await key(KEY_RIGHT)
	check(app._nav.Settings.rows[app._nav.Settings.selected].control == app._w.offset.slider.get_parent() and app.settings.offset_ms == offset + 1, "mouse hover and keyboard mix")
	app._enter_calib()
	await key(KEY_RIGHT)
	check(is_equal_approx(app.calib.L * 1920.0, 1.0), "calibration left endpoint step")
	await key(KEY_DOWN)
	await key(KEY_LEFT, true)
	check(app.sel_handle == "R" and is_equal_approx(app.calib.R * 1920.0, 1915.0), "calibration selects right endpoint and Shift step")
	await capture("calibration", "Calib")
	await key(KEY_DOWN)
	await key(KEY_SPACE)
	check(app.calib == {"L": 0.0, "R": 1.0}, "calibration reset action")
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	check(app.state == "settings", "calibration Done returns")
	app._enter_calib(); await key(KEY_ESCAPE)
	check(app.state == "settings", "calibration Esc returns")
	app._enter_sync()
	app._sync_t0 = SU.ticks() - 2000000
	await key(KEY_SPACE)
	check(app._sync_taps.size() == 1 and app.state == "sync", "sync default Space taps")
	await key(KEY_UP)
	check(app._nav.Sync.selected == 2, "sync up wraps to Back")
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	app._sync_taps = [23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0, 23.0]
	await capture("sync", "Sync")
	await key(KEY_ENTER)
	check(app.state == "settings" and app.settings.offset_ms == 23, "sync Apply uses estimate")
	app._enter_sync(); await key(KEY_ESCAPE)
	check(app.state == "settings", "sync Esc returns without apply")
	app._enter_sync(); await key(KEY_UP); await key(KEY_SPACE)
	check(app.state == "settings", "sync Space activates Back")
	await key(KEY_ESCAPE)
	check(app.state == "menu", "settings Esc returns")
	# Start a real built-in demo, then verify arrows never move any menu in play.
	app.sel_i = 0; app.sel_d = 0
	app._enter_songs(); await key(KEY_ENTER)
	check(app.state == "playing", "songs Enter activates demo")
	var selections := {}
	for name in app._nav: selections[name] = app._nav[name].selected
	for arrow in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]: await key(arrow)
	for name in selections: check(app._nav[name].selected == selections[name], "playing leaves " + name + " selection alone")
	await key(KEY_ESCAPE)
	check(app.state == "paused" and app._nav.Pause.selected == 0, "pause defaults to Resume")
	await capture("pause", "Pause")
	await key(KEY_UP)
	check(app._nav.Pause.selected == 3, "pause wraps up")
	await key(KEY_DOWN); await key(KEY_DOWN); await key(KEY_DOWN)
	await key(KEY_ENTER)
	check(app.state == "settings", "pause Settings action")
	await key(KEY_ESCAPE)
	check(app.state == "paused" and app._nav.Pause.selected == 2, "pause selection restored after settings")
	await key(KEY_UP); await key(KEY_UP); await key(KEY_SPACE)
	check(app.state == "resuming", "pause Space resumes")
	await key(KEY_ESCAPE)
	check(app.state == "paused", "resume Esc returns to pause")
	await key(KEY_DOWN); await key(KEY_ENTER)
	check(app.state == "playing", "pause Restart activates")
	await key(KEY_ESCAPE); await key(KEY_UP); await key(KEY_SPACE)
	check(app.state == "songs", "pause Quit activates")
	app._demo_result("AA")
	await key(KEY_ENTER)
	check(app.state == "result" and app._w.res._skipped, "result first activation skips reveal")
	await key(KEY_ENTER)
	check(app.state == "result", "result mashed activation guard")
	await capture("results", "Result")
	await create_timer(0.4).timeout
	await key(KEY_UP)
	check(app._nav.Result.selected == 1, "result wraps to restart")
	await key(KEY_DOWN)
	check(app._nav.Result.selected == 0, "result wraps to Songs")
	await key(KEY_SPACE)
	check(app.state == "songs", "result Space activates Songs")
	app._demo_result("AA"); app._w.res.skip()
	await create_timer(0.4).timeout
	await key(KEY_DOWN); await key(KEY_ENTER)
	check(app.state == "playing", "result Enter activates Restart")
	app._quit_to_songs()
	# Build a pending session using only an existing local fixture; cancelling must release it.
	var session := SongPluginSession.new()
	app._pending_play = {"session": session}
	app.state = "plugin_trust"
	app._w.plugin_trust_details.text = "Local navigation fixture — no scripts executed"
	app._show("PluginTrust")
	check(app._nav.PluginTrust.selected == 1, "trust defaults to Deny")
	await key(KEY_UP)
	check(app._nav.PluginTrust.selected == 0, "trust selects Allow")
	await key(KEY_UP)
	check(app._nav.PluginTrust.selected == 2, "trust wraps up to Cancel")
	await capture("plugin_trust", "PluginTrust")
	await key(KEY_ENTER)
	check(app.state == "songs" and app._pending_play.is_empty(), "trust Enter cancels pending preparation")
	app.state = "plugin_trust"; app._show("PluginTrust")
	await key(KEY_ESCAPE)
	check(app.state == "songs", "trust Esc cancels")
	trust_fixture("deny")
	await key(KEY_SPACE)
	check(app.state == "playing" and not FileAccess.file_exists("user://menu_script_ran") and app._plugin_status.text.contains("menu_test"), "trust Space activates Deny without executing script")
	app._quit_to_songs()
	trust_fixture("allow")
	await key(KEY_UP); await key(KEY_ENTER)
	check(app.state == "playing" and FileAccess.file_exists("user://menu_script_ran"), "trust Enter activates Allow and local fixture executes")
	app._quit_to_songs()
	# Free unattached result effects as well as the application tree.
	for effect in [app._w.res._fx, app._w.res._grain]:
		if effect.get_parent() == null: effect.free()
	app.free(); app = null
	await process_frame
	print("MENU KEYS: ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
