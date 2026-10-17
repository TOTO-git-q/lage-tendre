extends SceneTree
## Real offscreen/headless geometry regression. Values may change; rectangles may
## not. Explicit pane/compare transitions get a new baseline after settling.
const App = preload("res://app.gd")
const U = preload("res://ui/ui_util.gd")
var app
var failed := 0
var compared := 0
var samples: Array = []
var moved: Dictionary = {}
var owned_before: Array = []

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failed += 1
func frames(n := 8) -> void:
	for i in n: await process_frame
func collect(node: Node, result: Dictionary, prefix: String) -> void:
	if node is Control and node.is_visible_in_tree(): result[prefix] = node.get_global_rect()
	for i in node.get_child_count():
		collect(node.get_child(i), result, prefix + "/" + str(i))
func rects() -> Dictionary:
	var result := {}
	collect(app.time_main.get_parent().get_parent(), result, "top")
	for name in ["timeline_card", "timeline", "preview_card", "preview_frame", "inspector_card", "assistant", "tracks_pane", "drawer", "status_label", "save_state"]:
		var node: Control = app.get(name)
		if node.is_visible_in_tree(): result[name] = node.get_global_rect()
	if app.assistant.visible:
		for name in ["header", "selector", "chip_label", "thinking", "composer_shell"]:
			var node: Control = app.assistant.get(name)
			if node.is_visible_in_tree(): result["agent/" + name] = node.get_global_rect()
	if app.drawer.visible:
		for name in ["header", "title", "subtitle", "content"]:
			result["drawer/" + name] = app.drawer.get(name).get_global_rect()
	if app.script_window.visible:
		for name in ["heading", "notice", "code", "tabs", "bind_button", "trust_button"]:
			var node: Control = app.script_window.get(name)
			if node.is_visible_in_tree(): result["scripts/" + name] = node.get_global_rect()
	return result
func assert_rects(baseline: Dictionary, stage: String) -> void:
	var now := rects()
	for key in baseline:
		if not now.has(key):
			if not moved.has(stage+key): check(false, stage+": disappeared "+key); moved[stage+key]=true
		elif now[key] != baseline[key]:
			if not moved.has(stage+key): check(false, stage+": moved "+key+" "+str(baseline[key])+" -> "+str(now[key])); moved[stage+key]=true
		compared += 1
func stress(i: int) -> void:
	app.timeline.set_selection([0] if i % 3 == 0 else [], [0] if i % 3 == 1 else [])
	app.doc.selection.from = 1.0; app.doc.selection.to = 1.0 + i * 0.1234567
	app.assistant.update_context()
	app.status_label.text = ("Selection / revision / port 65535 " + str(i)).repeat(30 if i % 2 else 1)
	app.save_state.text = "已保存" if i % 2 else "有未保存的修改"
	app.song_title.text = "Long song title ".repeat(40 if i % 2 else 1)
	app.song_sub.text = "Version ".repeat(30 if i % 2 else 1)
	app.section_label.text = "A very long runtime section ".repeat(i % 4 + 1)
	app.kiai_badge.text = "KIAI" if i % 2 else ""
	app.strip_buttons.checks.badge = str(i * 10007) if i % 2 else ""
	var rate_pick: OptionButton = app.mode_seg.get_parent().get_child(app.mode_seg.get_index()+1)
	rate_pick.select(i % rate_pick.item_count)
	app.assistant.thinking.text = "Thinking ".repeat(i % 5 + 1)
	if app.drawer.visible: app.drawer.subtitle.text = "Runtime drawer values 999999 / 0.123456789 ".repeat(i % 5 + 1)

func exercise(stage: String, count := 60) -> void:
	await frames()
	var baseline := rects()
	for i in count:
		app.seek(float(i * 7919 % 29000) / 1000.0 + 0.0001234567)
		app.timeline.grid = app.Timeline.GRIDS[i % app.Timeline.GRIDS.size()]
		stress(i)
		await process_frame
		assert_rects(baseline, stage)
	check(not moved.keys().any(func(k): return str(k).begins_with(stage)), stage+": exact rects stable")

func run() -> void:
	owned_before = preload("res://tests/owned_nodes.gd").snapshot()
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true); KB.set_layout("ansi")
	app = App.new(); app.persist = false; app.silent = true; app.bridge.cli_enabled = false
	root.add_child(app); app.dismiss_hint()
	await frames()
	# Original in-memory fixture: no song edits or filesystem source changes.
	app.doc.raw = {"bpm":120,"timing":[{"t":0,"beat":0.5,"meter":4}],"lights":[{"t":0,"id":0,"type":"on","x":0.5,"w":0.8,"a":0},{"t":150,"id":0,"type":"off"}],"notes":[{"t":3,"k":5,"kind":"tap","light":0,"u":0.5}]}
	app.doc.refresh_core(); app.on_document_changed(); app.seek(0)
	var canonical: String = app.doc.position(20.412345678).bar_beat
	check(canonical.contains("+"), "canonical MCP off-grid fraction retained")
	check(U.clock_position(app.doc, 20.412345678, 16).length() < 16 and not U.clock_position(app.doc, 20.412345678, 16).contains("+"), "display clock bounds off-grid fractions")
	check(U.clock_position(app.doc, 2.0, 16) == "1.1" and U.clock_position(app.doc, 2.125, 16) == "1.1·1/16", "beat and subdivision display")
	check(U.clock_position(app.doc, 2.0 / 3.0, 3) == "0.2·1/12", "triplet grid fraction uses whole-note units")
	check(U.clock_seconds(59.9999) == "1:00.00" and U.clock_seconds(20.4) == "0:20.40", "centisecond carry and padding")
	var actual_end: float = app.doc.core.end_time
	app.doc.core.end_time = 599.9999; app._reserve_clock()
	check(app.time_sub.custom_minimum_size.x >= U.text_width("10:00.00", 14, preload("res://theme.gd").font("mono")), "clock reservation includes centisecond minute carry")
	app.doc.core.end_time = actual_end; app._reserve_clock()
	var quick := "--quick" in OS.get_cmdline_user_args()
	for dims in [Vector2i(1600,900), Vector2i(1920,1080)]:
		for zoom in [false, true]:
			root.size = dims; DisplayServer.window_set_size(dims); app.set_ui_zoom(0.0)
			if zoom:
				var key := InputEventKey.new(); key.pressed=true; key.ctrl_pressed=true; key.keycode=KEY_PLUS
				app._unhandled_key_input(key)
			check(is_equal_approx(root.content_scale_factor, 1.1 if zoom else 1.0), "Ctrl+ zoom " + str(dims)+" "+str(zoom))
			app.panes.inspector=true; app.panes.assistant=false; app.panes.drawer=false; app.panes.library=false; app.panes.tracks=false; app.panes.preview=true
			app.apply_panes(true); await frames(12)
			var stage := "%dx%d-zoom%s" % [dims.x,dims.y,zoom]
			var top: Control = app.time_main.get_parent().get_parent()
			print("LAYOUT_SIZE ", stage, " root=",app.size," top=",top.size," timeline=",app.timeline.size)
			check(top.size.x <= app.size.x, stage+": topbar fits window")
			check(app.clock.size.x == app.clock.custom_minimum_size.x, stage+": clock minimum equals allocation")
			await exercise(stage+"/inspector")
			# Continuous real playback, not simulated delta or a frame-count shortcut.
			app.seek(0); app.rate=1.0; app.toggle_play(); await frames()
			var baseline := rects(); var begin := Time.get_ticks_msec(); var start: float = app.cursor; var ticks := 0
			while Time.get_ticks_msec()-begin < (300 if quick else 20500):
				await process_frame; assert_rects(baseline,stage+"/play"); ticks += 1
			app.toggle_play()
			var elapsed := (Time.get_ticks_msec()-begin)/1000.0
			check(app.cursor-start >= (0.1 if quick else 20.0), stage+": playback advanced " + (">=0.1s quick (" if quick else ">=20s (") + str(app.cursor-start)+")")
			check(not moved.keys().any(func(k): return str(k).begins_with(stage+"/play")), stage+": every playback frame stable")
			samples.append({"stage":stage,"elapsed_seconds":elapsed,"frames":ticks,"playhead_delta":app.cursor-start})
			for pane in ["assistant", "library", "drawer", "preview"]:
				app.toggle_pane(pane); await frames(24)
				await exercise(stage+"/"+pane, 30)
				app.toggle_pane(pane); await frames(24)
			# Each drawer tab must retain the requested height, even large JSON/version content.
			app.panes.drawer=true
			for tab in app.Drawer.TABS:
				app.panes.tab=tab; app.apply_panes(true); await frames()
				check(app.drawer.size.y == float(app.panes.drawer_h),stage+": drawer height "+tab)
				await exercise(stage+"/drawer-"+tab, 8)
			app.panes.drawer=false; app.apply_panes(true)
			app.panes.assistant=true; app.panes.inspector=false; app.apply_panes(true); await frames()
			check(app.assistant.size.x == float(app.panes.assistant_w),stage+": remembered Agent width")
			app.assistant.backend="claude"; app.assistant.render_all()
			app.assistant.add_message("assistant","stream ".repeat(300))
			await exercise(stage+"/stream",20)
			app.assistant.append_stream(" longer".repeat(300)); await frames()
			check(app.assistant.size.x == float(app.panes.assistant_w),stage+": streaming keeps dock width")
			app.assistant.backend="external"; app.assistant.render_all()
			app._show_compare(["working","Long reference ".repeat(40)],[app.doc.raw.duplicate(true),app.doc.raw.duplicate(true)])
			await exercise(stage+"/compare",20); app.close_compare()
			app.script_window.show_workspace(); await frames()
			var script_rects := rects()
			for i in 20:
				app.script_window.heading.text="Plugin title ".repeat(i+1)
				app.script_window.notice.text="Notice ".repeat(i+1)
				app.script_window.bind_button.text="Binding ".repeat(i+1)
				await process_frame; assert_rects(script_rects,stage+"/scripts")
			app.script_window.close()
			app.panes.assistant=false; app.panes.inspector=true; app.apply_panes(true); await frames()
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var dir := "res://shots/layout-stability"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
				root.get_texture().get_image().save_png(dir.path_join(stage+".png"))
	check(app.doc.position(20.412345678).bar_beat == canonical,"canonical format unchanged after all UI paths")
	print("LAYOUT_SAMPLES ", JSON.stringify(samples))
	print("LAYOUT comparisons=",compared," failures=",failed)
	app.queue_free(); await frames(10)
	preload("res://tests/owned_nodes.gd").release_since(owned_before)
	await frames(3)
	quit(1 if failed else 0)
