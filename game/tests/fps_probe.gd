## Real-app frame pacing probe: main scene, autoplay, window at the given size, measures frame intervals (incl. GPU + vsync).
## -- --song=fixture_dense --autoplay --windowed --mute --w=2880 --h=1800 --secs=20 --out=x.json
extends SceneTree

class ProbeApp:
	extends "res://scripts/main.gd"
	# The probe deliberately runs outside the desktop; keep real autoplay running.
	func _notification(what: int) -> void:
		if what != NOTIFICATION_APPLICATION_FOCUS_OUT: super._notification(what)

var args := {}
var app: ProbeApp
var t_prev := 0
var gaps := []
var procs := []
var started := 0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--").split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else "1"
	app = ProbeApp.new()
	root.add_child(app)
	_go.call_deferred()

func _go() -> void:
	await create_timer(1.0).timeout
	DisplayServer.window_set_size(Vector2i(int(args.get("w", "2880")), int(args.get("h", "1800"))))
	await create_timer(4.0).timeout   # loading + warm up
	if app.state != "playing" or not app.core.autoplay:
		push_error("Probe must measure actual playing autoplay, got: " + app.state)
		quit(1); return
	started = Time.get_ticks_usec(); t_prev = started
	process_frame.connect(_tick)

func _tick() -> void:
	if app.state != "playing":
		push_error("Probe left play during measurement: " + app.state)
		quit(1); return
	var now := Time.get_ticks_usec()
	gaps.append(now - t_prev); t_prev = now
	procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1e6)
	if now - started > float(args.get("secs", "20")) * 1e6:
		process_frame.disconnect(_tick)
		var s := gaps.duplicate(); s.sort()
		var tot := 0.0
		for g in gaps: tot += g
		var p2 := procs.duplicate(); p2.sort()
		var res := {"size": DisplayServer.window_get_size(), "frames": gaps.size(), "mean_gap_ms": tot / gaps.size() / 1000.0,
			"p50_ms": s[s.size() / 2] / 1000.0, "p95_ms": s[int(s.size() * 0.95)] / 1000.0, "max_ms": s[-1] / 1000.0,
			"over_20ms": s.filter(func(x): return x > 20000).size(), "proc_p50_ms": p2[p2.size() / 2] / 1000.0,
			"proc_p95_ms": p2[int(p2.size() * 0.95)] / 1000.0, "vsync": DisplayServer.window_get_vsync_mode(),
			"adapter": RenderingServer.get_video_adapter_name(), "song": args.get("song", ""),
			"low_latency": args.has("low-latency"), "max_fps": Engine.max_fps,
			"over_25ms": s.filter(func(x): return x > 25000).size(), "samples_usec": gaps,
			"godot": Engine.get_version_info().string, "state": app.state}
		if args.has("out"): SU.save_json(args.out, res)
		print("FPSPROBE ", JSON.stringify(res))
		app._quit_to_songs()
		await process_frame
		# ResultView creates two unparented effects until its first begin().
		for effect in [app._w.res._fx, app._w.res._grain]:
			if effect.get_parent() == null: effect.free()
		app.free()
		await process_frame
		quit()
