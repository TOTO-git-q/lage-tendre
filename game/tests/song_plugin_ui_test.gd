## Real application trust/start/exit integration. Run with an isolated HOME and Dummy audio.
extends SceneTree

class TestApp:
	extends "res://scripts/main.gd"
	var fixture_root := ""
	func songs_dir() -> String: return fixture_root

var checks := 0
var failures := 0
var app: TestApp
var folder := ""

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL ", label)

func write(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value); file.close()

func write_json(path: String, value) -> void: write(path, JSON.stringify(value))

func chart() -> Dictionary:
	return {"bpm": 120, "lights": [{"t": 0, "id": 0, "type": "on", "x": 0.5, "w": 0.5, "auto": true}],
		"notes": [{"t": 2, "light": 0, "kind": "tap", "u": 0.5}, {"t": 3, "light": 0, "kind": "tap", "u": 0.5}]}

func setup_fixture() -> void:
	folder = ProjectSettings.globalize_path("user://p2_ui_songs")
	var source_audio := ProjectSettings.globalize_path("res://../songs/_demo/audio.wav")
	# Actual compiled-pack probes run from an empty directory; the fixture audio
	# remains an external original song asset rather than entering the game PCK.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-audio="):
			source_audio = argument.trim_prefix("--fixture-audio=")
	var audio_bytes := FileAccess.get_file_as_bytes(source_audio)
	check(not audio_bytes.is_empty(), "fixture audio is available")
	var entries := []
	for id in ["a", "b", "missing", "version", "_demo"]:
		var dir := folder.path_join(id)
		DirAccess.make_dir_recursive_absolute(dir)
		var audio := FileAccess.open(dir.path_join("audio.wav"), FileAccess.WRITE)
		audio.store_buffer(audio_bytes); audio.close()
		var raw := chart()
		if id == "a": raw.plugins = [{"id": "ui_script", "version": "1.0.0"}]
		if id == "missing": raw.plugins = [{"id": "absent_ui_plugin", "version": "1.0.0"}]
		if id == "version": raw.plugins = [{"id": "standard_chart", "version": "99.0.0"}]
		write_json(dir.path_join("chart.json"), raw)
		if id != "_demo": entries.append({"dir": id, "set": id, "title": id, "artist": "Local fixture", "version": "TEST", "level": 1, "bpm": 120, "length": 8, "audio": "audio.wav"})
	write_json(folder.path_join("index.json"), entries)
	var manifest := {"id": "ui_script", "version": "1.0.0", "api": 1, "tier": "script", "title": "UI test script", "author": "Local tests", "description": "Trust flow integration fixture",
		"provides": {"elements": ["ui_overlay"]}, "fields": [], "assets": [], "entry": "entry.gd"}
	write_json(folder.path_join("a/plugins/ui_script/plugin.json"), manifest)
	write(folder.path_join("a/plugins/ui_script/entry.gd"), "extends RefCounted\nstatic func install(registry, _manifest, _folder):\n\tvar file = FileAccess.open(\"user://p2_ui_script_executed\", FileAccess.WRITE)\n\tfile.store_string(\"allowed\")\n\tregistry.register(\"elements\", \"ui_overlay\", {\"phase\": \"ui_overlay\", \"order\": 45, \"callback\": paint})\nstatic func paint(_renderer, canvas):\n\tcanvas.draw_circle(Vector2(400, 400), 100, Color(1, 0, 1, 0.9))\n")
	# A unique content nonce avoids changing unrelated trust records on repeated runs.
	write(folder.path_join("a/test_nonce.txt"), str(Time.get_ticks_usec()))
	if FileAccess.file_exists("user://p2_ui_script_executed"): DirAccess.remove_absolute("user://p2_ui_script_executed")

func select_song(id: String) -> void:
	app.state = "songs"
	for i in app.songs.size():
		if app.songs[i].diffs[0].dir == id:
			app.sel_i = i; app.sel_d = 0; return
	check(false, "fixture song exists: " + id)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not app.args.has("ui-shots"): return
	var output := str(app.args["ui-shots"])
	DirAccess.make_dir_recursive_absolute(output)
	app._process(0.0)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	check(result == OK, "save real UI screenshot: " + label)

func _init() -> void: _run.call_deferred()

func _run() -> void:
	setup_fixture()
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	app = TestApp.new(); app.fixture_root = folder
	root.add_child(app)
	app.set_process(false); app.audio.muted = true; app.settings.autoplay = true
	select_song("a"); app._play_selected()
	check(app.state == "plugin_trust" and app.screens.PluginTrust.visible, "first script play opens real trust screen")
	check(app._w.plugin_trust_details.text.contains("ui_script") and app._w.plugin_trust_details.text.contains("SHA-256"), "dialog identifies script and content hash")
	check(not FileAccess.file_exists("user://p2_ui_script_executed"), "prompt did not execute script")
	await capture("trust_prompt")
	app._plugin_trust_answer(false)
	check(app.state == "playing", "deny continues to gameplay")
	check(app._plugin_status.text.contains("ui_script") and not app._plugin_status.text.is_empty(), "deny has persistent named in-game notice")
	check(not FileAccess.file_exists("user://p2_ui_script_executed"), "denial never executes script")
	await capture("denied_notice")
	var denied_key := str(app.meta.score_key)
	app._quit_to_songs()
	check(app._song_plugins == null and not app.core.registry.manifests.has("ui_script"), "quit releases song registry")
	select_song("a"); app._play_selected()
	check(app.state == "playing", "unchanged denied hash is remembered")
	app._quit_to_songs()
	write(folder.path_join("a/test_nonce.txt"), "changed-" + str(Time.get_ticks_usec()))
	select_song("a"); app._play_selected()
	check(app.state == "plugin_trust", "changed pack requires a new explicit decision")
	app._plugin_trust_answer(true)
	check(app.state == "playing" and FileAccess.file_exists("user://p2_ui_script_executed"), "allow executes script at song start")
	check(app.R.registry.get_entry("elements", "ui_overlay").get("plugin", "") == "ui_script", "actual renderer owns script visual provider")
	check(str(app.meta.score_key) != denied_key, "full and denied scores are separate")
	await capture("allowed_plugin")
	var weak_renderer: WeakRef = weakref(app.R)
	app._quit_to_songs()
	check(weak_renderer.get_ref() == null and app._song_plugins == null, "exit destroys plugin renderer and session")
	select_song("b"); app._play_selected()
	check(app.state == "playing" and not app.R.registry.manifests.has("ui_script"), "next unmodified song has no previous plugin")
	app.core.update(0.0)
	for i in range(1, 401): app.core.update(float(i) / 60.0)
	var after_a := app.core.stats.duplicate(true)
	var clean := GameCore.new(); clean.load_chart(chart()); clean.autoplay = true; clean.playing = true
	clean.update(0.0)
	for i in range(1, 401): clean.update(float(i) / 60.0)
	check(after_a == clean.stats, "B after plugin A has exact clean-start numerical result")
	clean = null
	# Result animation is part of the run. The session closes when the result panel opens.
	await create_timer(3.4).timeout
	check(app.screens.Result.visible and app._song_plugins == null, "result panel releases completed song session")
	app._quit_to_songs()
	select_song("missing"); app._song_info()
	check(app._w.ss_play.disabled and app._w.ss_note.text.contains("absent_ui_plugin"), "missing plugin is visible at song selection")
	app._play_selected()
	check(app.state == "songs" and app._w.ss_note.text.contains("absent_ui_plugin"), "missing plugin also blocks direct start")
	select_song("version"); app._song_info()
	check(app._w.ss_play.disabled and not app._w.ss_note.text.is_empty(), "wrong version is visible at selection")
	app._play_selected()
	check(app.state == "songs", "wrong version blocks start")
	select_song("a"); app._play_selected()
	check(app.state == "playing", "approved unchanged hash starts without another prompt")
	var completed_renderer: WeakRef = weakref(app.R)
	app.core.update(0.0)
	for i in range(1, 401): app.core.update(float(i) / 60.0)
	await create_timer(3.4).timeout
	check(app.screens.Result.visible and app._song_plugins == null and completed_renderer.get_ref() == null, "completed plugin song releases its actual renderer and session")
	check(not app._result_backdrop and not app.R.registry.manifests.has("ui_script"), "completed plugin result uses clean standard backdrop without callbacks")
	app._quit_to_songs()
	write(folder.path_join("a/test_nonce.txt"), "cancel-" + str(Time.get_ticks_usec()))
	select_song("a"); app._play_selected(); app._cancel_plugin_play()
	check(app.state == "songs" and app._pending_play.is_empty(), "cancel releases pending preparation without starting")
	app.queue_free(); app = null
	await process_frame
	await process_frame
	print("SONG PLUGIN UI: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
