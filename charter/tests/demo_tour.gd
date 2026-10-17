extends SceneTree
## Deterministic, real-editor UI tour. Never loaded by normal application startup.
const Pointer = preload("res://tests/demo_pointer.gd")
const Ops = preload("res://edit_ops.gd")
class DemoBridge:
	extends "res://claude_bridge.gd"
	func auth(_action="status") -> Dictionary: return {"loggedIn":false}
class FrameAudio:
	extends "res://scripts/audio_engine.gd"
	var start_frame := 0
	func play(stream: AudioStream, offset: float, from_t: float) -> void:
		super.play(stream, offset, from_t)
		start_frame = Engine.get_process_frames()
	func sync(_now: int) -> void:
		if _running: _a = _lead_t0 + (Engine.get_process_frames() - start_frame) / 60.0
	func time_at(_usec: int) -> float: return _a
class DemoApp:
	extends "res://app.gd"
	var fixture_root := ""
	func songs_root() -> String: return fixture_root
	func _process(dt: float) -> void:
		super._process(dt)
		if not doc.raw.is_empty(): time_main.text=str(doc.position(cursor).bar_beat).get_slice("+",0)
class DemoPopover:
	extends "res://ui/segment_popover.gd"
	func rebuild() -> void:
		# Fresh labels avoid the original card reusing children queued for deletion.
		if title.get_parent()!=null: title=Label.new()
		if note.get_parent()!=null: note=Label.new()
		super.rebuild()

var app
var pointer
var window_pointer
var extra_pointers := {}
var mouse := Vector2(800,450)
var rehearsal := false
var allow_commits := false
var out := ""
var markers := []
var origin_chart := {}
var verification := []
var tour_start := 0
var passed := true

func _init() -> void: run.call_deferred()
func wait(seconds: float) -> void:
	var count := maxi(1, int(seconds * 60.0 * (0.15 if rehearsal else 1.0)))
	for i in count: await process_frame
func settle() -> void:
	for i in 5: await process_frame
func require(ok: bool, message: String) -> void:
	verification.append({"ok":ok,"message":message,"frame":Engine.get_process_frames()})
	print("DEMO_PASS " if ok else "DEMO_FAIL ",message)
	var worklog := FileAccess.open(out.get_base_dir().get_base_dir().path_join("VIDEO_WORKLOG.md"),FileAccess.READ_WRITE)
	if worklog:
		worklog.seek_end(); worklog.store_string("\n- "+("Rehearsal" if rehearsal else "Recording")+" "+("verified: " if ok else "failed: ")+message+" (frame "+str(Engine.get_process_frames())+").\n")
		worklog.close()
	if not ok:
		passed = false
		root.get_texture().get_image().save_png(out.path_join("failure.png"))
		save_receipt()
		quit(1)
func save_receipt() -> void:
	var f := FileAccess.open(out.path_join("rehearsal-receipt.json" if rehearsal else "tour-receipt.json"),FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"markers":markers,"checks":verification,"frames":Engine.get_process_frames(),"fps":60,"passed":passed},"  "))
func marker(name: String) -> void:
	markers.append({"name":name,"seconds":Engine.get_process_frames()/60.0})
	print("DEMO_STAGE ",name," frame=",Engine.get_process_frames())
	await settle()
	if rehearsal:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("rehearsal-"+name+".png"))
	save_receipt()
func at(c: Control, local := Vector2(-1,-1)) -> Vector2:
	var p: Vector2 = c.size / 2.0 if local.x < 0 else local
	var view := c.get_viewport()
	if view is Window and view != root:
		return Vector2(view.position) + c.get_global_transform_with_canvas() * p
	return c.get_global_transform_with_canvas() * p
func event_to(e: InputEvent, view: Viewport = root) -> void:
	# push_input uses viewport coordinates and dispatches the real Control input path.
	if view!=root and e is InputEventMouse:
		e.position+=Vector2(view.position); e.global_position=e.position
		root.push_input(e,true)
	else: view.push_input(e,true)
func motion(p: Vector2, down := false, ctrl := false, view: Viewport = root) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p - Vector2(view.position) if view != root else p
	e.global_position = e.position; e.relative = p - mouse
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; e.ctrl_pressed = ctrl
	mouse = p; pointer.position = p
	window_pointer.position = p - Vector2(app.script_window.position)
	pointer.visible = view==root; window_pointer.visible = view==app.script_window
	for item in extra_pointers.values():
		if is_instance_valid(item): item.hide()
	if view!=root and view!=app.script_window:
		var id := view.get_instance_id()
		if not extra_pointers.has(id):
			var layer := CanvasLayer.new(); layer.layer=128; view.add_child(layer)
			var cursor=Pointer.new(); layer.add_child(cursor); extra_pointers[id]=cursor
		extra_pointers[id].position=p-Vector2(view.position); extra_pointers[id].show()
	event_to(e,view)
func move(p: Vector2, down := false, ctrl := false, view: Viewport = root, seconds := 0.42) -> void:
	var start := mouse
	var count := maxi(6,int(seconds*60.0*(0.25 if rehearsal else 1.0)))
	for i in count:
		var t := float(i+1) / count; var eased := t*t*(3.0-2.0*t)
		motion(start.lerp(p,eased),down,ctrl,view)
		await process_frame
func button(pressed: bool, which := MOUSE_BUTTON_LEFT, ctrl := false, double := false, view: Viewport = root) -> void:
	var e := InputEventMouseButton.new(); e.position = mouse - Vector2(view.position) if view != root else mouse
	e.global_position = e.position; e.button_index = which; e.pressed = pressed; e.ctrl_pressed = ctrl; e.double_click = double
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and which == MOUSE_BUTTON_LEFT else 0
	if pressed and which == MOUSE_BUTTON_LEFT:
		pointer.pulse = 1.0; window_pointer.pulse = 1.0
		for item in extra_pointers.values():
			if is_instance_valid(item): item.pulse=1.0
	event_to(e,view)
func click(p: Vector2, ctrl := false, double := false, view: Viewport = root) -> void:
	await move(p,false,ctrl,view)
	await wait(0.22)
	button(true,MOUSE_BUTTON_LEFT,ctrl,double,view); await process_frame
	button(false,MOUSE_BUTTON_LEFT,ctrl,false,view)
	await wait(0.4)
func drag(a: Vector2, b: Vector2, view: Viewport = root) -> void:
	await move(a,false,false,view); await wait(0.25)
	button(true,MOUSE_BUTTON_LEFT,false,false,view); await process_frame
	await move(b,true,false,view,0.6); button(false,MOUSE_BUTTON_LEFT,false,false,view)
	await wait(0.6)
func wheel(p: Vector2, direction: int, count := 1, ctrl := false, view: Viewport = root) -> void:
	await move(p,false,ctrl,view); await wait(0.25)
	for i in count:
		button(true,MOUSE_BUTTON_WHEEL_UP if direction>0 else MOUSE_BUTTON_WHEEL_DOWN,ctrl,false,view)
		button(false,MOUSE_BUTTON_WHEEL_UP if direction>0 else MOUSE_BUTTON_WHEEL_DOWN,ctrl,false,view)
		await wait(0.35)
	await settle()
func key(code: Key, ctrl := false, shift := false, alt := false, view: Viewport = root) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = true
	e.ctrl_pressed = ctrl; e.shift_pressed = shift; e.alt_pressed = alt
	event_to(e,view); await process_frame; e.pressed=false; event_to(e,view); await wait(0.5)
func segment(c: Control, index: int) -> void:
	await click(at(c,c._rects[index].get_center()))
func find_text(node: Node, value: String) -> Control:
	if node is Button and node.text == value and node.is_visible_in_tree(): return node
	if node is Control and "caption" in node and node.caption == value and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := find_text(child,value)
		if found != null: return found
	return null
func tap_text(value: String, node: Node = app) -> void:
	var c := find_text(node,value)
	if c == null: require(false,"UI control exists: "+value); return
	await click(at(c),false,false,c.get_viewport())
func timeline_point(u: float, t: float) -> Vector2:
	return at(app.timeline,Vector2(app.timeline.x_of(u),app.timeline.y_of(t)))
func open_main() -> void:
	# Song opening uses the exact library callback; nested plugin demo folders are not in its flat list.
	app.open_song("_demo"); await settle()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--rehearsal": rehearsal=true
		if arg == "--allow-temp-commits": allow_commits=true
	root.position=Vector2i(-5000,-5000); root.size=Vector2i(1920,1080)
	app=DemoApp.new(); app.persist=false; app.silent=rehearsal
	app.audio=FrameAudio.new(); app.bridge=DemoBridge.new(); app.popover=DemoPopover.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--songs-root="): app.fixture_root=arg.substr(13).replace("\\","/")
	out=app.fixture_root.get_base_dir()
	app.settings={"mcp_port":0}; root.add_child(app)
	await settle(); app.dismiss_hint()
	# Bound the app's own fractional beat label so its changing text cannot expand the toolbar.
	app.time_main.clip_text=true; app.time_main.custom_minimum_size.x=82
	await settle()
	var layer := CanvasLayer.new(); layer.layer=128; root.add_child(layer); pointer=Pointer.new(); layer.add_child(pointer); pointer.position=mouse
	var wl := CanvasLayer.new(); wl.layer=128; app.script_window.add_child(wl); window_pointer=Pointer.new(); wl.add_child(window_pointer); window_pointer.hide()
	require(app.doc.path.begins_with(app.fixture_root),"editor opens disposable songs only")
	require(root.size==Vector2i(1920,1080) and root.content_scale_size==Vector2i(1600,900),"1920x1080 with proportional UI scale")
	require(app.audio.music.stream!=null,"main song audio loaded")
	origin_chart=app.doc.raw.duplicate(true)
	app.seek(48.0); await wait(1.5)
	await click(at(app.play_b)); await wait(6.0)
	await marker("01-playback"); await click(at(app.play_b)); await wait(0.5)
	# Timeline scroll/zoom and track selection via the actual sidebar.
	await wheel(at(app.timeline,Vector2(220,220)),1,2)
	await wheel(at(app.timeline,Vector2(220,220)),1,2,true)
	await key(KEY_B,true)
	# A numeric search reduces the list before selecting the main carrier track.
	await click(at(app.track_search))
	var search := InputEventKey.new(); search.unicode=48; search.pressed=true; event_to(search); await settle()
	var row_index := -1
	for i in app.track_list.rows.size():
		if app.track_list.rows[i].get("id",-1)==0: row_index=i; break
	if row_index < 0:
		# Expand the carrier group using its real list header.
		await click(at(app.track_list,Vector2(80,20)))
		for i in app.track_list.rows.size():
			if app.track_list.rows[i].get("id",-1)==0: row_index=i; break
	require(row_index>=0,"main light track listed")
	await click(at(app.track_list,Vector2(55,app.track_list._row_top(row_index)+17)))
	require(app.timeline.selected_track()==0,"sidebar selects light track 0")
	# Reframe to an uncluttered opening phrase by scrolling the gutter.
	app.track_search.release_focus(); app.seek(4.0); app.timeline.pixels=100.0; await settle()
	var st: Dictionary=app.doc.state_at(app.doc.core.tl[0],5.0)
	var right_edge := float(st.x)+float(st.w)/2.0
	var before_revision: String=app.doc.revision()
	await drag(timeline_point(right_edge,5.1),timeline_point(right_edge+0.065,5.1))
	require(app.doc.revision()!=before_revision,"edge drag changes light-track width")
	await marker("02-track-width"); await wait(1.5)
	await key(KEY_B,true)
	# Insert visible edge-node pairs, then Ctrl-select two right-side nodes.
	st=app.doc.state_at(app.doc.core.tl[0],5.0); right_edge=float(st.x)+float(st.w)/2.0
	await click(timeline_point(right_edge,5.2),false,true)
	await click(timeline_point(right_edge,7.0),false,true)
	var s=app.timeline.work.shapes[0]; var nodes := []
	for i in s.size():
		if s.partner(i)>=0 and s.nodes[i].x>s.nodes[s.partner(i)].x and s.nodes[i].t>7.5 and s.nodes[i].t<9.2: nodes.append(i)
	nodes.sort_custom(func(a,b): return s.nodes[a].t<s.nodes[b].t)
	require(nodes.size()>=2,"two visible taper endpoints available after edge-node insertion")
	var moved_node_time: float=s.nodes[nodes[-1]].t
	app.timeline.sel_nodes=[]
	await click(at(app.timeline,app.timeline.screen(s.pos(nodes[0]))),true)
	await click(at(app.timeline,app.timeline.screen(s.pos(nodes[-1]))),true)
	require(app.popover.visible,"Ctrl-click opens segment popover")
	app.popover._place(Vector2(620,430)); await settle()
	var curve=app.popover.body.get_child(1)
	await segment(curve,1)
	await settle(); app.popover._place(Vector2(620,430)); await settle()
	curve=app.popover.body.get_child(1)
	await move(at(curve,curve._rects[1].get_center()))
	require(app.doc.undo_stack[-1].label=="片段缓入" and curve.index==1,"curve preset applied to tapering segment")
	await marker("03-vector-curve"); await wait(2.0)
	await click(at(app.popover.body.get_child(0).get_child(1)))
	app.timeline.select_track(0,true); await settle()
	s=app.timeline.work.shapes[0]
	var moved_node := -1
	for i in s.size():
		if absf(s.nodes[i].t-moved_node_time)<0.01 and s.partner(i)>=0 and s.nodes[i].x>s.nodes[s.partner(i)].x: moved_node=i
	require(moved_node>=0,"curve endpoint identity survives chart cleanup")
	var np: Vector2=at(app.timeline,app.timeline.screen(s.pos(moved_node)))
	before_revision=app.doc.revision()
	await drag(np,np+Vector2(-26,-18))
	require(app.doc.revision()!=before_revision,"track node moved by dragging")
	# Draw a recognisable star through the existing shape toolbar.
	await segment(app.tool_seg,3); await segment(app.shape_seg,3)
	await drag(timeline_point(0.30,6.1),timeline_point(0.70,9.1))
	require(app.timeline.shape_kind=="star" and app.timeline.work.shapes[0].size()==10,"shape tool draws star")
	await wait(1.8); await marker("03b-star")
	await segment(app.tool_seg,0)
	# Return to the carrier track, then place three taps and a dragged hold.
	app.timeline.set_selection([],[0]); app.timeline.select_track(0); app.seek(4.0); await settle()
	var note_count: int=app.doc.raw.notes.size()
	await segment(app.tool_seg,1)
	for spec in [[0.35,5.5],[0.45,6.1],[0.55,6.7]]:
		await click(timeline_point(spec[0],spec[1]))
	require(app.doc.raw.notes.size()==note_count+3,"three taps placed through timeline UI")
	await segment(app.tool_seg,2)
	await drag(timeline_point(0.65,7.2),timeline_point(0.65,8.4))
	require(app.doc.raw.notes.size()==note_count+4 and app.doc.raw.notes[-1].kind=="hold","hold created by dragging")
	await segment(app.tool_seg,0)
	var last: Dictionary=app.doc.raw.notes[-1]
	await click(timeline_point(Ops.key_x(Ops.note_key(last)),float(last.t)))
	await key(KEY_E,true); await settle()
	require(app.inspector.fields.has("kind"),"note inspector visible")
	await segment(app.inspector.fields.kind,0)
	require(app.doc.raw.notes[-1].kind=="tap","note type changed in inspector")
	await key(KEY_Z,true); require(app.doc.raw.notes[-1].kind=="hold","undo restores hold")
	await key(KEY_Y,true); require(app.doc.raw.notes[-1].kind=="tap","redo restores tap")
	await marker("04-notes"); await wait(1.5)
	# Contextual track opacity responds to mouse wheel and updates the real preview.
	app.timeline.set_selection([],[0]); app.timeline.select_track(0); await settle()
	var old_opacity: String=app.doc.revision()
	await wheel(at(app.inspector.fields.opacity,Vector2(70,13)),-1,5)
	require(app.doc.revision()!=old_opacity,"mouse wheel changes track opacity")
	await marker("05-properties"); await wait(1.5); await key(KEY_E,true)
	# Camera lane: create then drag a zoom keyframe, scrub with timeline gutter.
	await click(at(app.strip_buttons.camera)); await settle()
	var lanes=app.drawer.camera_lanes
	var camera_count: int=app.doc.raw.get("fx",[]).size()
	var cam_p: Vector2=at(lanes,Vector2(lanes.x_of(5.8),lanes.y_of(0,"zoom",1.2)))
	await click(cam_p,false,true)
	require(app.doc.raw.fx.size()==camera_count+1,"camera zoom keyframe added")
	var kfs: Array=lanes.keyframes(0,"zoom"); var added={}
	for kf in kfs:
		if int(kf.index)==camera_count: added=kf
	if not added.is_empty(): await drag(at(lanes,added.p),at(lanes,added.p+Vector2(35,-12)))
	await wheel(at(app.timeline,Vector2(20,220)),1,2)
	await marker("06-camera"); await wait(2.0)
	# Save through real confirmation dialog (only the copied song can be written).
	await click(at(app.save_b)); await wait(1.0)
	for child in app.get_children():
		if child is ConfirmationDialog and child.visible:
			await click(at(child.get_ok_button()),false,false,child)
	await settle()
	require(app.doc.revision()==app.doc.saved_revision,"working chart saved in temporary song folder")
	await click(at(app.strip_buttons.versions)); await wait(1.5)
	if allow_commits:
		await tap_text("启用版本管理")
		await tap_text("保存版本"); await wait(1.0)
		var store=app.doc.version_store()
		require(store.list_versions().get("commits",[]).size()==1,"version saved only in disposable song repository")
		# The first committed version and a visibly changed working copy share the same music axis.
		app.timeline.select_track(0); Ops.set_track_props(app.doc,0,{"a":0.75},"轨道不透明度","")
		app.drawer.refresh(); await settle()
		await tap_text("工作副本"); await tap_text("main"); await tap_text("并排比较")
	else:
		# No Git writes. Use the comparison renderer callback with actual before/after charts.
		app._show_compare(["原始谱面","working"],[origin_chart,app.doc.raw.duplicate(true)])
	app.seek(5.0); await settle()
	require(app.compare_view.visible,"multi-version shared-axis comparison visible")
	await marker("07-versions"); await wait(3.0)
	await tap_text("退出对比"); await click(at(app.strip_buttons.versions))
	# The library callback opens the declarative plugin demo, never the source folder.
	app.doc.open(app.fixture_root.path_join("_plugin_demos/glow_ring/chart.json")); app._show_song_title(); app.on_document_changed(); app.seek(4.0); await settle()
	await key(KEY_E,true,true); await settle()
	var window=app.script_window
	require(window.visible,"script workspace opens")
	var row_button: Control=null
	for child in window.list.get_children():
		if child is HBoxContainer:
			for c in child.get_children():
				if c is Button and c.text.contains("glow_ring"): row_button=c
	if row_button!=null: await click(at(row_button),false,false,window)
	else:
		await move(Vector2(window.position)+Vector2(140,280),false,false,window); window.select_plugin("glow_ring")
	await settle()
	require(window.selected=="glow_ring" and window.code.text.contains('"glow_ring"'),"glow_ring plugin.json displayed")
	await click(at(window.detail_tabs,window.detail_tabs.get_tab_rect(1).get_center()),false,false,window)
	await settle()
	var spin=window.fields.get_child(1).get_child(1)
	var spin_before: float=spin.value
	await click(at(spin),false,false,window)
	await wheel(at(spin),1,3,false,window)
	require(spin.value!=spin_before,"plugin field form responds to wheel")
	await marker("08-plugin-fields"); await wait(2.0)
	var was_bound: bool=window.selected_row().get("bound",false)
	await click(at(window.bind_button),false,false,window)
	require(window.selected_row().get("bound",false)!=was_bound,"plugin binding toggled")
	await wait(0.8); await click(at(window.bind_button),false,false,window)
	require(window.selected_row().get("bound",false)==was_bound,"plugin binding restored")
	await click(at(window.detail_tabs,window.detail_tabs.get_tab_rect(2).get_center()),false,false,window)
	await marker("08b-plugin-standard"); await wait(3.0)
	await tap_text("关闭 ✕",window); await settle()
	await open_main(); app.seek(52.0); await settle()
	await move(at(app.play_b)); await click(at(app.play_b)); await wait(7.5)
	await marker("09-finale"); await click(at(app.play_b)); await move(Vector2(1520,830)); await wait(2.0)
	require(not app.playing and not app.drawer.visible and not window.visible,"clean final editor frame")
	await marker("10-end")
	save_receipt(); print("DEMO_COMPLETE frames=",Engine.get_process_frames())
	app.queue_free(); await process_frame; await process_frame
	quit(0 if passed else 1)
