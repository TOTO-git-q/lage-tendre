## P6 actual menu, trust and completed-song regression; isolated user directory only.
## --isolated-test-user --songs-root=/absolute/songs [--ui-shots=/absolute/dir]
## --native-song-path=1 requires a generated native package with songs beside its executable.
extends SceneTree

class TestApp:
	extends "res://scripts/main.gd"
	var fixture_root := ""
	func songs_dir() -> String: return super.songs_dir() if fixture_root.is_empty() else fixture_root

const MARKER := "user://plugin_demos/trust_spark_loaded.txt"
const DEMOS := ["shapes", "motion", "speed", "glow_ring", "script_trust"]
var checks := 0
var failures := 0
var options := {}
var source_root := ""
var folder := ""
var app: TestApp
var restored_readme := ""
var original_readme := ""
var evidence := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func write(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: check(false, "test file writable: " + path); return
	f.store_string(value); f.close()

func copy_tree(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return false
	var d := DirAccess.open(source)
	if d == null: return false
	d.include_hidden = true; d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		if name not in [".", ".."] and not name.ends_with(".import"):
			if d.is_link(name): return false
			if d.current_is_dir():
				if not copy_tree(source.path_join(name), destination.path_join(name)): return false
			elif DirAccess.copy_absolute(source.path_join(name), destination.path_join(name)) != OK: return false
		name = d.get_next()
	d.list_dir_end(); return true

func menu_dirs(value: Array) -> Array:
	var result := []
	for song in value:
		for diff in song.diffs: result.append(str(diff.dir))
	return result

func index_probe() -> void:
	var probe := TestApp.new(); probe.fixture_root = folder
	var index_path := folder.path_join("_plugin_demos/index.json")
	var valid := FileAccess.get_file_as_string(index_path)
	write(index_path, "[]"); probe._load_song_list()
	var original := probe.songs.duplicate(true)
	var old_dirs := menu_dirs(original)
	write(index_path, valid); probe._load_song_list()
	check(probe.songs.slice(0, original.size()) == original, "supplement leaves every original menu entry and order exact")
	check(probe.songs.size() == original.size() + 5 and probe._demo_index_notices.is_empty(), "all five real demo folders append without notices")
	var all_dirs := menu_dirs(probe.songs)
	for id in DEMOS: check(all_dirs.count("_plugin_demos/" + id) == 1, "one visible menu entry for " + id)
	var entries: Array = JSON.parse_string(valid)
	var one: Dictionary = entries[3]
	var cases := [null, {}, true, "bad", {"dir":"../../escape"}]
	for field in ["dir", "title", "artist", "version", "bpm", "length", "audio", "cover", "preview", "notes", "level"]:
		var row := one.duplicate(true); row[field] = []
		cases.append(row)
	for path in ["../glow_ring", "_plugin_demos/", "_plugin_demos/..", "_plugin_demos/glow_ring/child", "/tmp/outside", "_plugin_demos/missing"]:
		var row := one.duplicate(true); row.dir = path; cases.append(row)
	for field in ["title", "artist", "version", "set"]:
		var row := one.duplicate(true); row[field] = "bad\ncontrol"; cases.append(row)
	var too_long := one.duplicate(true); too_long.title = "x".repeat(257); cases.append(too_long)
	for pair in [["bpm", -1], ["length", 86401], ["preview", 999], ["notes", -1], ["level", 1000], ["audio", "../audio.wav"], ["cover", "../../outside.png"]]:
		var row := one.duplicate(true); row[pair[0]] = pair[1]; cases.append(row)
	for row in cases:
		write(index_path, JSON.stringify([row])); probe._load_song_list()
		check(probe.songs == original and not probe._demo_index_notices.is_empty(), "malformed optional row is rejected without changing original songs: " + JSON.stringify(row).left(60))
	for bad in ["{}", "[", "[null]", " ".repeat(1048577), JSON.stringify(range(513))]:
		write(index_path, bad); probe._load_song_list()
		check(probe.songs == original and not probe._demo_index_notices.is_empty(), "malformed, oversized or over-count index fails closed")
	write(index_path, JSON.stringify([one, one])); probe._load_song_list()
	check(menu_dirs(probe.songs).count(one.dir) == 1 and not probe._demo_index_notices.is_empty(), "duplicate directory is rejected")
	var conflict: Dictionary = entries[4].duplicate(true); conflict.set = one.set
	write(index_path, JSON.stringify([one, conflict])); probe._load_song_list()
	check(probe.songs.size() == original.size() + 1 and not probe._demo_index_notices.is_empty(), "conflicting group metadata cannot silently merge")
	var repeated := []
	for i in 24: repeated.append(false)
	write(index_path, JSON.stringify(repeated)); probe._load_song_list()
	check(probe._demo_index_notices.size() == 8, "invalid-row notices are bounded")
	for value in [INF, -INF, NAN]: check(not probe._demo_number(value, 0, 10), "nonfinite metadata is rejected")
	check(not probe._demo_number(true, 0, 10), "boolean is not numeric metadata")
	# Actual file links are test-owned and never followed by the loader.
	var link := folder.path_join("_plugin_demos/linked")
	var d := DirAccess.open(folder.path_join("_plugin_demos"))
	check(d != null and d.create_link(folder.path_join("_plugin_demos/glow_ring"), link) == OK, "create isolated symlink fixture")
	var linked := one.duplicate(true); linked.dir = "_plugin_demos/linked"
	write(index_path, JSON.stringify([linked])); probe._load_song_list()
	check(probe.songs == original and not probe._demo_index_notices.is_empty(), "symlinked demo directory is refused")
	write(index_path, valid); probe._load_song_list()
	check(menu_dirs(probe.songs).slice(0, old_dirs.size()) == old_dirs, "valid reload restores all legacy directories exactly")
	probe.free(); probe = null

func select(id: String) -> bool:
	app.state = "songs"
	for i in app.songs.size():
		for j in app.songs[i].diffs.size():
			if app.songs[i].diffs[j].dir == id:
				app.sel_i = i; app.sel_d = j; app._song_info(); return true
	check(false, "actual menu contains selected " + id); return false

func capture(name: String) -> void:
	if not options.has("ui-shots"): return
	check(DisplayServer.get_name() != "headless", "UI screenshot requires actual rendering")
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(options["ui-shots"])
	app._process(0.0)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(str(options["ui-shots"]).path_join(name + ".png")) == OK, "capture actual " + name)

func complete_current(label: String, points: int) -> Dictionary:
	var weak_renderer: WeakRef = weakref(app.R)
	var weak_session: WeakRef = weakref(app._song_plugins)
	var had_plugins: bool = app._uses_song_plugins
	for i in int(ceil(app.core.end_time * 240.0)) + 2: app.core.update(float(i) / 240.0)
	var stats := app.core.stats.duplicate(true)
	check(app.state == "result" and not app.core.playing, label + " reaches actual result state")
	check(stats.total == points and stats.PERFECT == points and stats.MISS == 0 and stats.score == 1010000, label + " full-score autoplay")
	await create_timer(3.4).timeout
	check(app.screens.Result.visible and app._song_plugins == null and weak_session.get_ref() == null, label + " completed result releases session")
	check((weak_renderer.get_ref() == null if had_plugins else weak_renderer.get_ref() == app.R) and app.R.registry.manifests.size() == 4, label + " plugin renderer is disposed; ordinary result retains its intentional standard backdrop")
	check(not FileAccess.file_exists(MARKER), label + " script marker absent after complete teardown")
	return stats

func start_checks(script_enabled: bool) -> void:
	check(app.state == "playing" and app.audio.music.stream is AudioStreamWAV and app.audio._running, "actual menu start loads and starts the WAV")
	check(AudioServer.get_driver_name() == "Dummy" and AudioServer.is_bus_mute(0), "actual app audio remains silent")
	check(app.core.notes.size() == 72 and app.core.chart.warnings.is_empty(), "actual example has 72 valid authored notes")
	check(not app.R.registry.get_entry("elements", "glow_ring").is_empty(), "actual renderer receives declarative ring provider")
	check(not app.R.registry.get_entry("elements", "trust_spark").is_empty() if script_enabled else app.R.registry.get_entry("elements", "trust_spark").is_empty(), "actual script renderer installation follows trust")
	app._process(0.0)
	check(app.R.f.play and app.R.f.chart == app.core.chart, "actual app forwards selected chart to renderer")

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "1"
	_run.call_deferred()

func _run() -> void:
	if not options.has("isolated-test-user") or AudioServer.get_driver_name() != "Dummy":
		push_error("Use an isolated HOME/XDG with --isolated-test-user and --audio-driver Dummy"); quit(2); return
	source_root = str(options.get("songs-root", ProjectSettings.globalize_path("res://../songs")))
	check(source_root.is_absolute_path() and DirAccess.dir_exists_absolute(source_root), "external source songs exist")
	folder = ProjectSettings.globalize_path("user://p6_menu_songs_" + str(Time.get_ticks_usec()))
	check(copy_tree(source_root.path_join("_plugin_demos"), folder.path_join("_plugin_demos")), "copy demo fixtures without symlinks into isolated test directory")
	for dir in ["_demo", "_covers"]: check(copy_tree(source_root.path_join(dir), folder.path_join(dir)), "copy original test media " + dir)
	check(DirAccess.copy_absolute(source_root.path_join("index.json"), folder.path_join("index.json")) == OK, "copy unchanged original index")
	if failures: await cleanup(); finish(); return
	index_probe()
	# Index probe's intentional symlink is excluded from real gameplay pack paths.
	for path in [SongPluginSession.TRUST_PATH, MARKER]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	root.size = Vector2i(1600, 900); root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS; root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	AudioServer.set_bus_mute(0, true)
	app = TestApp.new()
	if options.get("native-song-path", "0") == "1":
		check(app.songs_dir() == source_root and source_root == OS.get_executable_path().get_base_dir().path_join("songs"), "real native executable-relative songs discovery")
		folder = source_root
	else: app.fixture_root = folder
	app.args["mute"] = "1"; app.args["windowed"] = "1"; app.settings.fullscreen = false; app.settings.keyguard = false
	root.add_child(app); app.set_process(false); app.audio.set_muted(true); app.settings.autoplay = true; app.settings.hit_kind = "off"
	check(app._demo_index_notices.is_empty(), "real application opens valid menu without optional-index errors")
	check(select("_plugin_demos/glow_ring"), "select declarative demo in actual menu")
	app._enter_songs(); select("_plugin_demos/glow_ring")
	check(not app._w.ss_play.disabled and app._w.ss_note.text.is_empty(), "declarative demo is playable without trust warning")
	await capture("demo_menu")
	app._play_selected(); start_checks(false)
	check(not app.screens.PluginTrust.visible and app._plugin_status.text.is_empty() and not FileAccess.file_exists(MARKER), "declarative main start never prompts or executes scripts")
	var declared := await complete_current("declarative", 84)
	app._quit_to_songs(); select("_plugin_demos/script_trust")
	check(app._w.ss_note.text.contains("Script trust"), "script demo advertises trust at selection")
	app._play_selected()
	check(app.state == "plugin_trust" and app.screens.PluginTrust.visible, "real first-use trust dialog opens")
	check(app._w.plugin_trust_details.text.contains("trust_spark") and app._w.plugin_trust_details.text.contains("SHA-256"), "dialog identifies actual script and package hash")
	check(not FileAccess.file_exists(MARKER), "no static initialization before consent")
	await capture("demo_trust")
	app._plugin_trust_answer(false); start_checks(false)
	check(app._plugin_status.text.contains("trust_spark") and not FileAccess.file_exists(MARKER), "denial shows named warning and never executes")
	await capture("demo_denied")
	var denied_key := str(app.meta.score_key)
	var denied := await complete_current("denied", 84)
	check(denied == declared, "denial preserves every gameplay statistic")
	app._quit_to_songs(); select("_plugin_demos/script_trust"); app._play_selected()
	check(app.state == "playing" and not FileAccess.file_exists(MARKER), "unchanged denied content remembers decision")
	app._quit_to_songs()
	restored_readme = folder.path_join("_plugin_demos/script_trust/README.md")
	original_readme = FileAccess.get_file_as_string(restored_readme)
	write(restored_readme, original_readme + "\nChanged only by isolated P6 UI test.\n")
	select("_plugin_demos/script_trust"); app._play_selected()
	check(app.state == "plugin_trust" and not FileAccess.file_exists(MARKER), "changed non-code content prompts again without executing")
	app._cancel_plugin_play()
	check(app.state == "songs" and app._pending_play.is_empty() and app._song_plugins == null, "cancel destroys pending preparation")
	app._plugin_trust_answer(true)
	check(app.state == "songs" and not FileAccess.file_exists(MARKER), "stale answer after cancel cannot start or execute")
	select("_plugin_demos/script_trust"); app._play_selected(); app._plugin_trust_answer(true); start_checks(true)
	check(FileAccess.file_exists(MARKER) and app._plugin_status.text.is_empty(), "allow executes actual static initializer and clears degraded notice")
	check(str(app.meta.score_key) != denied_key, "allowed and denied main-app score identities differ")
	var owned: WeakRef
	for item in app._song_plugins.registry._owned:
		if item.object is Node and item.object.name == "TrustSparkDemoState": owned = weakref(item.object)
	check(owned != null and owned.get_ref() != null, "script owns a real cooperative runtime node")
	await capture("demo_allowed")
	var allowed := await complete_current("allowed", 84)
	check(allowed == denied and owned.get_ref() == null, "allowed preserves results and releases owned runtime node")
	app._quit_to_songs(); select("_plugin_demos/script_trust"); app._play_selected()
	check(app.state == "playing" and FileAccess.file_exists(MARKER), "unchanged allowed content starts without another prompt")
	var old_renderer: WeakRef = weakref(app.R); app._quit_to_songs()
	check(old_renderer.get_ref() == null and not FileAccess.file_exists(MARKER), "early exit also frees renderer and owned script state")
	select("demo"); app._play_selected()
	check(app.core.registry.manifests.size() == 4 and app.R.registry.manifests.size() == 4 and app._plugin_status.text.is_empty(), "ordinary B uses only four clean standard packages")
	var clean := GameCore.new(); check(clean.load_chart(ChartLib.demo()), "clean reference B loads")
	clean.autoplay = true; clean.playing = true
	for i in int(ceil(clean.end_time * 240.0)) + 2: clean.update(float(i) / 240.0)
	var after := await complete_current("ordinary B", 242)
	check(after == clean.stats, "ordinary B equals every clean-start reference statistic")
	check(PluginRegistry.standard().manifests.size() == 4, "shared standard registry remains isolated")
	clean = null
	evidence = {"declarative": declared, "denied": denied, "allowed": allowed, "ordinary_b": after, "native_path": options.get("native-song-path", "0") == "1"}
	await cleanup(); finish()

func cleanup() -> void:
	if not restored_readme.is_empty(): write(restored_readme, original_readme)
	# Let the application's existing 450 ms song-preview timers finish naturally.
	await create_timer(0.6).timeout
	if is_instance_valid(app): app.queue_free(); app = null
	await process_frame; await process_frame

func finish() -> void:
	print("PLUGIN DEMO APP RESULT ", JSON.stringify(evidence))
	print("PLUGIN DEMO APP: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
