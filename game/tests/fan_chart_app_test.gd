## Actual song-menu and playback integration against an isolated generated songs root.
extends SceneTree

class TestApp:
	extends "res://scripts/main.gd"
	var fixture_root := ""
	func songs_dir() -> String: return fixture_root if not fixture_root.is_empty() else super.songs_dir()

var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _init() -> void: run.call_deferred()

func run() -> void:
	var fixture: String = OS.get_cmdline_user_args()[0]
	var shot: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	var source := TestApp.new()
	check(source.songs_dir() == ProjectSettings.globalize_path("res://../songs").simplify_path(), "source resolves ../songs")
	source.fixture_root = fixture
	# Discovery works independently of a missing or invalid ordinary index.
	source._load_song_list()
	var fan_titles := []
	for song in source.songs:
		if song.get("group", "") == FanChartLibrary.GROUP: fan_titles.append(song.title)
	check(fan_titles == ["Alpha original", "Zulu original"], "own fan group sorted by title; hidden/template/malformed entries skipped")
	source.free()
	var app := TestApp.new(); app.fixture_root = fixture
	app.settings.fullscreen = false
	root.add_child(app)
	app.audio.set_muted(true)
	app.settings.autoplay = true
	app.set_process(false)
	app._enter_songs()
	var selected := -1
	for i in app.songs.size():
		if app.songs[i].get("group", "") == FanChartLibrary.GROUP: selected = i; break
	check(selected >= 0, "fan submission appears in actual game app")
	if selected >= 0:
		app._song_select(selected, true)
		check(app._w.ss_group.text == FanChartLibrary.GROUP and app._w.ss_title.text == "Alpha original", "actual song menu shows community label and title")
		for i in 5: await process_frame
		if not shot.is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(shot) == OK, "offscreen song-list screenshot saved")
		app._play_selected(0.0)
		check(app.state == "playing", "fan chart starts through actual play-selected path")
		var t := 0.0
		while app.core.playing and t < app.core.end_time + 2:
			app.core.update(t); t += 1.0 / 120.0
		check(app.core.stats.PERFECT == 5 and app.core.stats.MISS == 0, "actual app autoplay is all PERFECT")
		check(app.meta.dir == "fan-made/alpha" and app.meta.score_key == PluginScores.key_for("fan-made/alpha", PluginScores.standard_identity()), "scores retain directory-based song key")
	app.audio.stop()
	# Allow the real app's preview/result timers to release their callbacks first.
	await create_timer(3.5).timeout
	app.queue_free(); app = null
	await process_frame; await process_frame
	print("FAN APP: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)
