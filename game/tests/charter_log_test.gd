## Lifecycle/marker regression check, with no window or sound.
extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.settings.autoplay = true
	app._play_selected(0.0)
	assert(app._play_log.active)
	var before: int = app.core.stats.judged
	var now := Time.get_ticks_usec()
	app._key_down("Backquote", "Backquote", false, now, false)
	app._key_up("Backquote", "Backquote", now)
	app._key_down("Backquote", "Backquote", true, now, false)
	assert(app._play_log.markers.size() == 1)
	assert(app.core.stats.judged == before)
	assert(not app.core.down.has("Backquote"))
	assert(app.R._marker_until > now and app.R._marker_until <= Time.get_ticks_usec() + 500000)
	app._restart()
	assert(app._play_log.active and app._play_log.markers.is_empty())
	app._on_finished(app.core.stats)
	assert(not app._play_log.active)
	app._restart()
	app._quit_to_songs()
	assert(not app._play_log.active)
	app.audio.preview_stop()
	var core := GameCore.new()
	core.load_chart(ChartLib.demo())
	core.press_space(core.cues[0].t + 0.01)
	assert(absf(core.cues[0].hitDt - 0.01) < 1e-8)
	assert(core.cues[0].key == "Space")
	print("CHARTER_LOG_OK: marker consumed, repeat ignored, scoring unchanged, restart/result/quit persisted, cue timing recorded")
	app.queue_free()
	await process_frame
	quit()
