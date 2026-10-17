extends SceneTree
## Charter GUI behaviour: direct manipulation on the timeline, track shapes as vector outlines,
## contextual inspector with live edits + undo, lanes, panes, lean save + sidecar, assistant.
const App = preload("res://app.gd")
const Document = preload("res://document.gd")
const Ops = preload("res://edit_ops.gd")
const Adapter = preload("res://track_adapter.gd")
const Shape = preload("res://track_shape.gd")
var failed := 0
var app
var owned_before: Array = []

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failed += 1

func _init() -> void: run.call_deferred()

func frames(n := 3) -> void:
	for i in n: await process_frame

func mouse_button(pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, double := false, mods := {}) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = button; e.pressed = pressed; e.position = pos; e.double_click = double
	e.ctrl_pressed = mods.get("ctrl", false); e.shift_pressed = mods.get("shift", false); e.alt_pressed = mods.get("alt", false)
	if button == MOUSE_BUTTON_LEFT and pressed: e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e

func mouse_move(pos: Vector2, mods := {}) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new(); e.position = pos; e.button_mask = MOUSE_BUTTON_MASK_LEFT if mods.get("down", false) else 0
	e.shift_pressed = mods.get("shift", false); e.alt_pressed = mods.get("alt", false); e.ctrl_pressed = mods.get("ctrl", false)
	return e

func drag(tl, a: Vector2, b: Vector2, mods := {}) -> void:
	tl._gui_input(mouse_move(a)); tl._gui_input(mouse_button(a, true, MOUSE_BUTTON_LEFT, false, mods))
	for k in range(1, 6):
		var m := mods.duplicate(); m["down"] = true
		tl._gui_input(mouse_move(a.lerp(b, k / 5.0), m))
	tl._gui_input(mouse_button(b, false, MOUSE_BUTTON_LEFT, false, mods))

func write_chart(path: String, raw: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(raw)); f.close()

func run() -> void:
	owned_before = preload("res://tests/owned_nodes.gd").snapshot()
	KB.set_layout("ansi")
	root.size = Vector2i(1920, 1080)
	app = App.new(); app.persist = false; app.bridge.cli_enabled = false
	root.add_child(app); app.audio.set_muted(true)
	await frames(2)
	root.size = Vector2i(1920, 1080); DisplayServer.window_set_size(Vector2i(1920, 1080))
	await frames(4)
	print("window ", root.size)
	var dir := "res://evidence/temp_ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(dir)): DirAccess.remove_absolute(ProjectSettings.globalize_path(dir).path_join(f))
	var path := ProjectSettings.globalize_path(dir.path_join("chart.json"))
	var raw := {"bpm": 120, "custom_source_field": {"preserve": true}, "timing": [{"t": 0, "beat": 0.5, "meter": 4}],
		"lights": [{"t": 0, "id": 0, "type": "on", "x": 0.5, "w": 0.4, "a": 0, "auto": true}, {"t": 20, "id": 0, "type": "off", "auto": true}], "notes": []}
	write_chart(path, raw)
	var doc = app.doc; var tl = app.timeline
	doc.open(path); app.on_document_changed(); app.seek(3.0)
	await frames(3)
	check(tl.size.x > 300 and tl.size.y > 300, "timeline laid out: " + str(tl.size))
	check(not app.drawer.visible and not app.tracks_pane.visible and not app.assistant.visible and app.preview_card.visible, "default view = timeline + preview + inspector only")
	var cells: Array = tl.shift_cells()
	check(cells.map(func(c): return c.label) == ["Shift", "Z X", "C V", "B N", "M ,", ". /", "Shift"] and cells[0].x1 == 2.25 and cells[1].x1 == 4.25 and cells[-1].x0 == 12.25 and cells[-1].x1 == 15.0, "key ruler shows the ANSI Shift row in cells: " + str(cells.map(func(c): return [c.label, c.x0, c.x1])))
	KB.set_layout("jis"); var jis: Array = tl.shift_cells(); KB.set_layout("ansi")
	check(jis[-1].label == "ろ Shift" and jis[-1].x0 == 12.25, "JIS keyboards get their own right-hand cell")
	var tip: String = tl._get_tooltip(Vector2(tl.x_of(7.6 / 15.0), tl.size.y - 8))
	check(tip.contains("中排 H") and tip.contains("下排 N") and tip.contains("上排 U"), "ruler tooltip names the key under the pointer in every row: " + tip)

	# --- placing: double-click, ghost, refusal with reason
	tl.set_selection([], [])
	tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(3.0)), true, MOUSE_BUTTON_LEFT, true))
	tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(3.0)), false))
	check(doc.raw.notes.size() == 1 and int(doc.raw.notes[0].k) == 5, "double-click places a note on the grid")
	app.set_tool("tap")
	tl._gui_input(mouse_move(Vector2(tl.x_of(Ops.key_x(0)), tl.y_of(4.0))))
	check(not tl.ghost.is_empty() and not tl.ghost.ok and "没有轨道" in tl.ghost.reason, "ghost turns red over an uncovered key: " + str(tl.ghost.get("reason", "")))
	app.seek(0.6)
	tl._gui_input(mouse_move(Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(0.5))))
	check(not tl.ghost.is_empty() and not tl.ghost.ok and "1.3" in tl.ghost.reason, "ghost explains the 1.3 s approach rule: " + str(tl.ghost.get("reason", "")))
	var before: int = doc.raw.notes.size()
	tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(0.5)), true)); tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(0.5)), false))
	check(doc.raw.notes.size() == before and not tl.bubble.is_empty(), "refused click places nothing and shows a reason bubble")
	app.seek(3.0)
	tl._gui_input(mouse_move(Vector2(tl.x_of(Ops.key_x(6)), tl.y_of(4.0))))
	tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(6)), tl.y_of(4.0)), true)); tl._gui_input(mouse_button(Vector2(tl.x_of(Ops.key_x(6)), tl.y_of(4.0)), false))
	check(doc.raw.notes.size() == before + 1 and absf(float(doc.raw.notes[-1].t) - 4.0) < 1e-6, "tap tool places at the ghost")
	app.set_tool("select")

	# --- drag-move a note: time + key, one undo step
	var idx := 0
	var undo_size: int = doc.undo_stack.size()
	var from := Vector2(tl.x_of(Ops.key_x(5)), tl.y_of(3.0))
	tl.set_selection([], [])
	drag(tl, from, Vector2(tl.x_of(Ops.key_x(4)), tl.y_of(3.5)))
	check(int(doc.raw.notes[idx].k) == 4 and absf(float(doc.raw.notes[idx].t) - 3.5) < 1e-6, "drag moves a note in time and key: t=%s k=%s" % [doc.raw.notes[idx].t, doc.raw.notes[idx].k])
	check(doc.undo_stack.size() == undo_size + 1, "drag is one undo step")
	doc.undo(); check(absf(float(doc.raw.notes[idx].t) - 3.0) < 1e-6, "undo restores the dragged note")
	doc.redo()
	# Alt-drag duplicates
	var count: int = doc.raw.notes.size()
	drag(tl, Vector2(tl.x_of(Ops.key_x(4)), tl.y_of(3.5)), Vector2(tl.x_of(Ops.key_x(4)), tl.y_of(5.0)), {"alt": true})
	check(doc.raw.notes.size() == count + 1, "Alt-drag duplicates a note")

	# --- inspector live edit + undo; convert to hold, then drag the hold tail
	tl.set_selection([idx], [0])
	app.inspector.refresh(true)
	check(app.inspector.fields.has("time") and app.inspector.fields.has("kind"), "contextual inspector shows note fields")
	app.inspector.fields.kind.changed.emit(1)
	check(doc.raw.notes[idx].kind == "hold", "inspector segmented converts tap to hold immediately")
	doc.undo(); check(doc.raw.notes[idx].kind == "tap", "inspector edit is one undo step")
	doc.redo()
	var t_before := float(doc.raw.notes[idx].t)
	app.inspector.fields.time.nudge(1, 1.0)
	check(float(doc.raw.notes[idx].t) > t_before, "inspector time steps with wheel / arrow")
	doc.undo(); check(absf(float(doc.raw.notes[idx].t) - t_before) < 1e-9, "inspector step undo")
	tl.refresh(true)
	var nv: Dictionary = tl._view_of(idx)
	var tail := Vector2(tl.x_of(nv.x), tl.y_of(nv.t + nv.dur))
	drag(tl, tail, tail - Vector2(0, tl.pixels * 0.5))
	check(float(doc.raw.notes[idx].dur) > 0.9, "dragging a hold tail lengthens it: dur=%s" % doc.raw.notes[idx].get("dur", 0))

	# --- marquee selection
	tl.set_selection([], [])
	drag(tl, Vector2(tl.x_of(Ops.key_x(2)), tl.y_of(5.4)), Vector2(tl.x_of(Ops.key_x(8)), tl.y_of(2.5)))
	check(doc.selection.notes.size() >= 2, "marquee selects notes: " + str(doc.selection.notes))

	# --- context menu action: delete via menu, then undo
	count = doc.raw.notes.size()
	var nv2: Dictionary = tl._view_of(doc.raw.notes.size() - 1)
	tl._context_menu(Vector2(tl.x_of(nv2.x), tl.y_of(nv2.t)))
	check(tl.menu.item_count > 4, "right-click on a note opens its menu")
	tl.menu.hide()
	tl._menu_action(16)
	check(doc.raw.notes.size() < count, "context menu deletes")
	doc.undo(); check(doc.raw.notes.size() == count, "context menu delete undo")

	# --- wheel zoom keeps the time under the pointer
	var probe := Vector2(tl.x_of(0.5), tl.y_of(app.cursor + 1.0))
	var t_at: float = tl.time_of(probe.y)
	var wheel := mouse_button(probe, true, MOUSE_BUTTON_WHEEL_UP); wheel.ctrl_pressed = true
	var pixels_before: float = tl.pixels
	tl._gui_input(wheel)
	check(tl.pixels > pixels_before and absf(tl.time_of(probe.y) - t_at) < 1e-3, "Ctrl+wheel zooms around the pointer")
	var c0: float = app.cursor
	tl._gui_input(mouse_button(probe, true, MOUSE_BUTTON_WHEEL_UP))
	check(app.cursor > c0, "wheel scrolls time")

	# --- tracks: drag-create a rectangle track, edge drag, node drag, density, segment ops
	app.set_tool("track")
	app.seek(8.0)
	var a := Vector2(tl.x_of(Ops.key_x(1) - 1.0 / 30.0), tl.y_of(8.5))
	var b := Vector2(tl.x_of(Ops.key_x(3) + 1.0 / 30.0), tl.y_of(10.5))
	var ids_before: int = doc.core.tl.size()
	drag(tl, a, b)
	check(doc.core.tl.size() == ids_before + 1, "track tool drag creates a track")
	var new_id: int = Ops.next_track_id(doc) - 1
	var evs := Ops.track_events(doc, new_id)
	check(evs.size() == 2 and evs[0].type == "on" and evs[1].type == "off", "a dragged rectangle is one on + one off event (lean)")
	check(absf(float(evs[0].t) - 8.5) < 1e-6 and absf(float(evs[1].t) - 10.5) < 1e-6, "created track snaps to the grid")
	app.set_tool("select")
	tl.set_selection([], [new_id])
	check(not tl.work.is_empty() and tl.work.id == new_id, "selecting a track opens its outline for editing")
	var w0: float = doc.state_at(doc.core.tl[new_id], 9.3).w
	var s0 = tl.work.shapes[0]
	var env: Vector2 = s0.envelope(9.3)
	var edge := Vector2(tl.x_of(env.y), tl.y_of(9.3))
	tl._gui_input(mouse_move(edge))
	check(tl.hover.get("kind", "") == "edge", "pointer on the right edge finds the edge: " + str(tl.hover))
	drag(tl, edge, edge + Vector2(tl.x_of(2.0 / 15.0) - tl.x_of(0), 0))
	var w1: float = doc.state_at(doc.core.tl[new_id], 9.3).w
	check(absf(w1 - w0 - 2.0 / 15.0) < 0.02, "edge drag widens the track by two keys: %.3f -> %.3f" % [w0, w1])
	check(Ops.track_events(doc, new_id).size() == 2, "widening the whole edge keeps two events")
	# node drag: move the top-right node only -> one sweep appears
	tl.select_track(new_id)
	var s1 = tl.work.shapes[0]
	var top_right := -1
	for i in s1.size():
		if absf(s1.nodes[i].t - 10.5) < 1e-6 and (top_right < 0 or s1.nodes[i].x > s1.nodes[top_right].x): top_right = i
	# insert a node half way up the right edge first (double-click), then drag the top-right node
	var right_mid := Vector2(tl.x_of(s1.envelope(9.5).y), tl.y_of(9.5))
	tl._gui_input(mouse_move(right_mid)); tl._gui_input(mouse_button(right_mid, true, MOUSE_BUTTON_LEFT, true)); tl._gui_input(mouse_button(right_mid, false))
	check(tl.work.shapes[0].size() == 6, "double-click on an edge inserts a node pair (lane track): %d nodes" % tl.work.shapes[0].size())
	s1 = tl.work.shapes[0]
	top_right = -1
	for i in s1.size():
		if absf(s1.nodes[i].t - 10.5) < 1e-6 and (top_right < 0 or s1.nodes[i].x > s1.nodes[top_right].x): top_right = i
	var node_p: Vector2 = tl.screen(s1.pos(top_right))
	tl.sel_nodes = []
	drag(tl, node_p, node_p + Vector2(tl.x_of(1.0 / 15.0) - tl.x_of(0), 0))
	var after_events := Ops.track_events(doc, new_id)
	var st_end: Dictionary = doc.state_at(doc.core.tl[new_id], 10.49)
	check(after_events.size() == 3 and after_events[1].type == "sweep", "node drag writes one sweep: " + JSON.stringify(after_events))
	check(absf((st_end.x + st_end.w / 2.0) - (env.y + 2.0 / 15.0 + 1.0 / 15.0)) < 0.03, "the dragged corner moved right by one key")
	# density switch changes the grid-crossing nodes
	tl.pixels = 300.0; tl.grid = 4; app.seek(9.0)
	var v4: int = tl.virtual_nodes().size()
	tl.cycle_grid(1); tl.cycle_grid(1)
	var v8: int = tl.virtual_nodes().size()
	check(tl.grid == 8 and v8 > v4, "grid density 4 -> 8 shows more edge nodes (%d -> %d)" % [v4, v8])
	tl.grid = 16; tl.pixels = 110.0
	# segment: two nodes on the right edge -> curve preset, undo, straight
	tl.select_track(new_id)
	var s2 = tl.work.shapes[0]
	var right_nodes := []
	for i in s2.size():
		if s2.partner(i) >= 0 and s2.nodes[i].x > s2.nodes[s2.partner(i)].x and s2.nodes[i].t > 9.0: right_nodes.append(i)
	right_nodes.sort_custom(func(x, y): return s2.nodes[x].t < s2.nodes[y].t)
	tl.sel_nodes = [{"s": 0, "n": right_nodes[0]}, {"s": 0, "n": right_nodes[-1]}]
	var opened := [false]
	tl.popover_requested.connect(func(_s, _a, _b): opened[0] = true)
	tl._key(_key_event(KEY_ENTER))
	check(opened[0] and app.popover.visible, "Enter on two nodes opens the segment popover")
	var seg_t0: float = s2.nodes[right_nodes[0]].t
	tl.segment_op(0, right_nodes[0], right_nodes[-1], "ease", "in")
	var sweep := {}
	for e in Ops.track_events(doc, new_id):
		if e.type == "sweep": sweep = e
	check(sweep.get("ease", "") == "in", "segment curve preset writes the sweep ease (both edges): " + JSON.stringify(sweep))
	doc.undo(); tl.refresh(true)
	var sweep2 := {}
	for e in Ops.track_events(doc, new_id):
		if e.type == "sweep": sweep2 = e
	check(sweep2.get("ease", "inout") != "in", "segment op undo")
	app.popover.close()

	# --- lean save: redundant nodes are not written; the game draws the same track
	var ref_events := Ops.track_events(doc, new_id).duplicate(true)
	var ref_tl := ChartLib.build_timelines(ChartLib.validate({"lights": ref_events, "notes": []}).lights)
	tl.select_track(new_id)
	var s3 = tl.work.shapes[0]
	var left_seg := 0
	var ins: int = s3.insert(left_seg, 0.5); tl._pair_insert(s3, ins)
	tl._commit_work("test: redundant nodes")
	var lean_events := Ops.track_events(doc, new_id)
	var same := true
	var ltl := ChartLib.build_timelines(ChartLib.validate({"lights": lean_events, "notes": []}).lights)
	var tt := 8.4
	while tt < 10.7:
		var p: Dictionary = ChartLib.light_at(ref_tl[new_id], tt); var q: Dictionary = ChartLib.light_at(ltl[new_id], tt)
		if p.alive != q.alive or (p.alive and (absf(p.x - q.x) > 1e-6 or absf(p.w - q.w) > 1e-6 or absf(p.alpha - q.alpha) > 1e-6)): same = false
		tt += 0.01
	check(lean_events.size() <= ref_events.size(), "collinear user nodes are not saved (%d events, was %d)" % [lean_events.size(), ref_events.size()])
	check(same, "the game renders the same track after lean rewrite (light_at samples equal)")
	check(tl.work.shapes[0].size() >= ref_events.size() * 2, "the editor keeps the user's nodes in the session")

	# --- a non-representable shape: approximated in chart.json, exact in chart.ext.json
	app.set_tool("track"); tl.shape_kind = "star"; app.seek(12.0)
	drag(tl, Vector2(tl.x_of(0.3), tl.y_of(12.5)), Vector2(tl.x_of(0.7), tl.y_of(14.5)))
	var star_id: int = Ops.next_track_id(doc) - 1
	check(doc.ext.shapes.has(str(star_id)), "a star track keeps its exact outline in the sidecar data")
	check(not Ops.track_events(doc, star_id).is_empty(), "the star is approximated by today's events so the chart stays playable")
	app.set_tool("select"); tl.shape_kind = "rect"

	# --- note motion: plugin, drawn path, stored in the sidecar
	tl.set_selection([idx], [int(doc.raw.notes[idx].light)])
	tl.set_motion(1)
	var mkey := Ops.motion_key(doc.raw.notes[idx])
	check(doc.ext.motions.has(mkey) and doc.ext.motions[mkey].type == "horizontal", "add motion 水平 to a note")
	app.seek(float(doc.raw.notes[idx].t) - 0.3); tl.refresh(true)
	var mv: Dictionary = tl._view_of(idx)
	var handle := Vector2(tl.x_of(tl.motion_start_x(mv, doc.ext.motions[mkey])), tl.y_of(mv.t + 1.3))
	tl._gui_input(mouse_move(handle))
	check(tl.hover.get("kind", "") == "motion", "the motion start handle is under the pointer")
	drag(tl, handle, handle + Vector2(tl.x_of(1.0 / 15.0) - tl.x_of(0), 0))
	check(absf(float(doc.ext.motions[mkey].params.from) - (-2.0)) < 0.01, "dragging the start point changes the motion offset: " + str(doc.ext.motions[mkey].params.from))

	# --- older behaviours kept
	tl.set_selection([], [0]); tl.locked_tracks[0] = true
	count = doc.raw.notes.size()
	tl._place(6.0, 5, 0.0)
	check(doc.raw.notes.size() == count, "a locked track refuses placement")
	tl.locked_tracks[0] = false
	app.light = true; app.apply_theme()
	check(app.theme.get_color("default_color", "RichTextLabel").r < 0.5, "light theme readable text colour")
	app.light = false; app.apply_theme()
	app.confirm_save()
	var dialog = app.get_child(app.get_child_count() - 1)
	check(dialog is ConfirmationDialog, "save asks for confirmation")
	dialog.confirmed.emit()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.custom_source_field.preserve, "save preserves unrelated fields")
	var text := FileAccess.get_file_as_string(path)
	check(not "motions" in text and not "shapes" in text, "chart.json holds no editor-only data")
	check(FileAccess.file_exists(path.get_base_dir().path_join("chart.ext.json")), "shapes and motions saved to chart.ext.json")
	var reopened = Document.new(); reopened.open(path)
	check(reopened.ext.motions.has(mkey) and reopened.ext.shapes.has(str(star_id)), "sidecar data reloads with the chart")
	check(not app.drawer.visible, "JSON stays behind its drawer (closed by default)")
	app.open_drawer("json"); check(app.drawer.visible and app.drawer.tab == "json" and not app.drawer.json_view.editable, "JSON drawer opens read-only")
	app.open_drawer("json"); await create_timer(0.3).timeout
	check(not app.drawer.visible, "same strip button closes the drawer (slides away)")
	app.open_drawer("camera")
	var lanes = app.drawer.camera_lanes
	await frames(3)
	var lane_p := Vector2(lanes.x_of(app.cursor + 1.0), lanes.y_of(0, "zoom", 1.03))
	lanes._gui_input(mouse_button(lane_p, true, MOUSE_BUTTON_LEFT, true))
	check(doc.raw.get("fx", []).size() == 1 and absf(float(doc.raw.fx[0].to) - 1.03) < 1e-6, "double-click in the camera lane adds a keyframe on the word level 近")
	var kf_p: Vector2 = lanes.keyframes(0, "zoom")[0].p
	lanes._gui_input(mouse_move(kf_p)); lanes._gui_input(mouse_button(kf_p, true))
	lanes._gui_input(mouse_move(Vector2(kf_p.x + 40, lanes.y_of(0, "zoom", 1.06)), {"down": true}))
	lanes._gui_input(mouse_button(Vector2(kf_p.x + 40, lanes.y_of(0, "zoom", 1.06)), false))
	check(absf(float(doc.raw.fx[0].to) - 1.06) < 1e-6 and float(doc.raw.fx[0].t) > 0, "dragging a camera keyframe changes its value (snaps to 极近) and time")
	app.open_drawer("camera")
	check(app.bridge.friendly_error("OAuth session expired") == "Claude CLI 未登录：在终端运行 claude 并 /login", "Chinese authentication error")
	app.assistant.messages = [{"role": "user", "text": "Persistent test conversation"}]; app.bridge.session_id = "test-session"; app.assistant.save_conversation()
	app.assistant.messages = []; app.bridge.session_id = ""; app.assistant.load_conversation()
	check(app.assistant.messages.size() == 1 and app.bridge.session_id == "test-session", "per-song conversation and session restore")
	app.assistant.new_conversation(); check(app.bridge.session_id.is_empty(), "new conversation clears the session")
	check(app.assistant.backend_slot.get_parent() == app.assistant.header, "assistant header has a backend slot for Claude | Codex")
	check(app.assistant._without_old_intro([{"role": "assistant", "text": "用音乐的语言，雕刻光与节奏。

选中一段谱面，再告诉 Claude 你想怎样改变。
"}, {"role": "user", "text": "hi"}]).size() == 1, "the old decorative intro is dropped from saved conversations")
	check(app.assistant.title.text == "Agent" and app.assistant.get("model") == null, "panel titled Agent, CLI default model")
	app.assistant.set_backends({"claude":false,"codex":false}); app.assistant.render_all()
	check(app.assistant.backend == "external" and is_instance_valid(app.assistant.external_page), "no CLI shows usable external Agent connection page")
	app.assistant.set_backends({"claude":true,"codex":false}); doc.selection.notes = []; doc.selection.tracks = []; doc.selection.fx = []; doc.selection.from = 0.0; doc.selection.to = 0.0; app.assistant.update_context()
	app.assistant._select_backend(0)
	var qf: Array = app.assistant.quick_flows
	var needs_sel: Array = qf[-1].flow.get_children().filter(func(b): return b.disabled)
	check(needs_sel.size() == app.assistant.QUICK.filter(func(q): return q[1]).size(), "selection-dependent requests wait for selection")
	app.assistant.set_backends({"claude":false,"codex":false})
	app.toggle_pane("assistant"); await frames(2)
	check(app.panes.assistant and app.assistant.visible, "assistant pane opens on demand")
	app.toggle_pane("assistant"); await create_timer(0.3).timeout
	check(not app.panes.assistant and not app.assistant.visible, "assistant pane collapses")
	app.persist = true; app.toggle_pane("tracks"); app.persist = false
	var saved_panes = JSON.parse_string(FileAccess.get_file_as_string(App.PANES_PATH))
	check(saved_panes is Dictionary and saved_panes.tracks == true, "open panes are remembered in user://")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(App.PANES_PATH))
	app.toggle_pane("tracks")

	await lean_round_trip()
	app.playing = false; app.audio.stop()
	app.queue_free(); await frames(8)
	preload("res://tests/owned_nodes.gd").release_since(owned_before)
	await frames(3)
	print("CHARTER_UI failures=", failed)
	quit(1 if failed else 0)

func _key_event(code: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = code; e.pressed = true
	return e

## load -> save lean -> load gives the same validator output and the same autoplay result.
func lean_round_trip() -> void:
	var src := ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json").simplify_path()
	var dir := ProjectSettings.globalize_path("res://evidence/temp_lean")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	var copy := dir.path_join("chart.json")
	DirAccess.copy_absolute(src, copy)
	var original = JSON.parse_string(FileAccess.get_file_as_string(src))
	var d = Document.new(); d.open(copy)
	d.edit({"expected_revision": d.revision(), "label": "touch", "ops": [{"target": "meta", "value": d.raw.meta}]})
	d.saved_revision = ""
	var res: Dictionary = d.save()
	check(not res.has("error"), "lean save of a original demo copy: " + str(res.get("error", "")))
	var lean = JSON.parse_string(FileAccess.get_file_as_string(copy))
	var a := ChartLib.validate(original); var b := ChartLib.validate(lean)
	check(JSON.stringify(Document.sorted_value(a)) == JSON.stringify(Document.sorted_value(b)), "lean chart validates identically")
	var fields := func(chart) -> int:
		var n := 0
		for key in ["lights", "notes", "fx"]:
			for e in chart.get(key, []): n += e.size()
		return n
	check(fields.call(lean) <= fields.call(original), "lean chart keeps no default-valued fields (%d vs %d fields)" % [fields.call(lean), fields.call(original)])
	var scores := []
	for chart in [original, lean]:
		var core := GameCore.new(); core.load_chart(chart); core.autoplay = true; core.playing = true
		var t := 0.0
		while core.playing and t < core.end_time + 2.0:
			core.update(t); t += 1.0 / 60.0
		scores.append([core.stats.score, core.stats.PERFECT, core.stats.MISS])
	check(scores[0] == scores[1], "lean chart plays identically on autoplay: " + str(scores))
