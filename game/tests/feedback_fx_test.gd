## Deterministic real-core feedback coverage and offscreen 60 Hz sequences.
## Extends the repository baseline driver to use its exact frame-data contract.
extends "res://tests/capture_render.gd"

var failures := 0
var output_dir := ""
var observations := []

func _frame(t: float, elapsed: float) -> Dictionary:
	# Scripted jumps still timestamp final signals at the simulated current frame,
	# rather than the preceding render (which may be seconds earlier in a fixture).
	if renderer != null: renderer.last_fx_t = t
	return super._frame(t, elapsed)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FX CHECK: " + message)

func fixture(kind := "tap", chord := false, stack := false, yellow := false, big := false) -> Dictionary:
	var lights := []
	for pair in [[0, "KeyD"], [1, "KeyK"], [2, "KeyF"]]:
		lights.append({"t": 0.0, "id": pair[0], "type": "on", "x": KB.by_code[pair[1]].cx, "w": 2.0 / 15.0, "auto": true})
	var notes := [{"t": 3.0, "light": 0, "u": 0.5, "kind": kind, "dur": 1.5 if kind == "hold" else 0.0, "ex": yellow, "big": big}]
	if chord: notes.append({"t": 3.0, "light": 1, "u": 0.5, "kind": "tap"})
	if stack:
		notes.append({"t": 3.3, "light": 1, "u": 0.5, "kind": "tap"})
		notes.append({"t": 3.65, "light": 2, "u": 0.5, "kind": "tap"})
	return {"bpm": 120.0, "offset": 2.0, "timing": [{"t": 2.0, "beat": 0.5, "meter": 4}], "meta": {}, "lights": lights, "notes": notes}

func setup_case(raw: Dictionary) -> void:
	print("FX setup notes=", raw.notes.size())
	core = GameCore.new()
	check(core.load_chart(raw), "fixture loads")
	print("FX chart loaded")
	core.playing = true
	core.stage.mode = "off"
	renderer = Renderer.new()
	root.add_child(renderer)
	renderer._rng.seed = SEED
	renderer.note_scale = 1.5
	renderer.hint_mode = "off"
	core.ripple.connect(renderer.add_ripple)
	core.judged.connect(renderer.add_judge)
	core.hold_end.connect(renderer.add_hold_end)
	core.combo_break.connect(renderer.add_combo_break)
	meta = {"title": "FEEDBACK FX", "artist": "Deterministic scripted presses", "version": "VISUAL CHECK"}
	_frame(1.0, 1.0)
	print("FX frame initialized")

func press(at: float, code: String, release := true) -> void:
	print("FX press ", at, " ", code)
	_frame(at, at)
	print("FX press complete")
	renderer.last_fx_t = at
	check(core.press_key(code, at) != null, "scripted press hits at %.3f" % at)
	if release: core.release_key(code, at + 0.01)
	_frame(at, at)

func capture_case(label: String, start: float, count := 8) -> void:
	print("FX capture ", label)
	for index in count:
		var t := start + float(index) / FPS
		_frame(t, t)
		await RenderingServer.frame_post_draw
		if not output_dir.is_empty():
			var path := output_dir.path_join("%s_%02d.png" % [label, index])
			check(root.get_texture().get_image().save_png(path) == OK, "save " + path)
		var rt = renderer._runtime
		observations.append({"case": label, "frame": index, "t": t, "heads": renderer._nd_notes.duplicate(true),
			"impacts": rt.impacts.duplicate(true), "timing": rt.timing_stack.duplicate(true), "pulses": rt.combo_pulses.duplicate(true)})

func finish_case() -> void:
	renderer.free()
	core = null

func _run() -> void:
	KB.set_layout("ansi")
	if args.has("capture"):
		check(DisplayServer.get_name() != "headless", "real offscreen rendering required")
		output_dir = str(args.capture).path_join("frames")
		DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	setup_case(fixture())
	press(2.93, "KeyD")
	check(core.notes[0].grade == "GREAT" and core.notes[0].provisional, "early GREAT is provisional")
	check(renderer._runtime.timing_stack.is_empty(), "no provisional timing text")
	await capture_case("early_great", 2.93, 16)
	check(renderer._runtime.timing_stack.size() == 1, "one settled FAST entry")
	finish_case()

	setup_case(fixture("tap", false, false, false, true))
	press(3.0, "KeyD")
	await capture_case("critical_big", 3.0)
	check(renderer._runtime.timing_stack.is_empty(), "CRITICAL has no timing text")
	check(renderer._runtime.combo_pulses[-1].grade == "CRITICAL", "critical pulse")
	finish_case()

	setup_case(fixture())
	press(3.1, "KeyD")
	await capture_case("late_good", 3.1)
	check(core.notes[0].grade == "GOOD", "late GOOD")
	check(renderer._runtime.timing_stack[0].label == "LATE", "late label")
	finish_case()

	setup_case(fixture())
	await capture_case("miss", 3.12)
	check(core.notes[0].state == "miss", "miss stranded")
	check(renderer._runtime.timing_stack.is_empty(), "MISS has no timing text")
	check(renderer._runtime.combo_pulses[-1].grade == "MISS", "grey miss pulse")
	finish_case()

	setup_case(fixture("tap", true))
	press(2.93, "KeyD")
	press(2.93, "KeyK")
	check(renderer._runtime.impacts.size() == 1, "critical chord follower bursts immediately before chart time")
	await capture_case("chord", 2.93, 16)
	check(renderer._runtime.timing_stack.size() == 1, "wide chord is one entry despite deferred partner")
	check(renderer._runtime.timing_stack[0].grade == "GREAT", "worst chord grade wins")
	finish_case()

	# Three identical on-time results on the same key are three chart moments.
	var repeat_raw := fixture()
	repeat_raw.notes.append({"t": 3.033, "light": 0, "u": 0.5, "kind": "tap"})
	repeat_raw.notes.append({"t": 3.066, "light": 0, "u": 0.5, "kind": "tap"})
	setup_case(repeat_raw)
	for at in [3.0, 3.033, 3.066]: press(at, "KeyD")
	check(renderer._runtime.feedback_groups.size() == 3, "same-key stream moments remain distinct")
	finish_case()

	setup_case(fixture("tap", false, true))
	press(2.93, "KeyD")
	press(3.4, "KeyK")
	press(3.61, "KeyF")
	await capture_case("stack", 3.72)
	check(renderer._runtime.timing_stack.size() == 3, "three visible final FAST/LATE entries")
	_frame(4.7, 4.7)
	check(renderer._runtime.timing_stack.is_empty(), "timing entries expire")
	finish_case()

	setup_case(fixture())
	press(2.9, "KeyD")
	press(3.0, "KeyD")
	_frame(3.06, 3.06)
	check(core.notes[0].grade == "PERFECT", "grade protection upgrades to critical")
	check(renderer._runtime.timing_stack.is_empty(), "provisional GOOD is never shown after critical correction")
	check(renderer._runtime.combo_pulses.size() == 1, "one final pulse after regrade")
	finish_case()

	setup_case(fixture("tap", false, false, true))
	press(2.9, "KeyD")
	_frame(3.0, 3.0)
	check(renderer._runtime.timing_stack.is_empty(), "early ExTap has no FAST text")
	check(renderer._runtime.combo_pulses[0].grade == "CRITICAL", "ExTap is critical")
	finish_case()

	for late in [false, true]:
		setup_case(fixture("hold"))
		var at := 3.1 if late else 2.93
		press(at, "KeyD", false)
		await capture_case("hold_late" if late else "hold_early", at)
		check(core.notes[0].state == "holding" and not renderer._nd_holds.is_empty(), "hold body remains")
		finish_case()

	setup_case(fixture())
	for i in 80: renderer.add_ripple(0.3, 3.0)
	check(renderer.hits.size() <= 32 and renderer.plucks.size() <= 32, "bounded hit effects")
	for i in 80:
		renderer.last_fx_t = 2.0 + i * 0.05
		renderer.add_judge("GREAT", 0.3, -0.07)
	check(renderer._runtime.combo_pulses.size() <= 12 and renderer._runtime.timing_stack.size() <= 3 and renderer._runtime.feedback_groups.size() <= 32, "bounded dense-stream HUD feedback")
	renderer.clear_fx()
	check(renderer.hits.is_empty() and renderer._runtime.combo_pulses.is_empty() and renderer._runtime.timing_stack.is_empty(), "seek/restart clears feedback")
	finish_case()
	if not output_dir.is_empty(): SU.save_json(str(args.capture).path_join("observations.json"), observations)
	print("FEEDBACK FX: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
