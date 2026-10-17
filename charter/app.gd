extends Control
## L'âge tendre Charter: window layout and wiring. Arranged like the Agent desktop app: the calm
## default view is only the timeline and the real game preview. Everything else opens on demand
## from labelled toggles and remembers its state: a left sidebar with two tabs (歌曲 = the song
## library with new / import / export, Ctrl+L; 轨道 = the track list, Ctrl+B), one
## right-hand dock with two tabs (属性 = the contextual inspector, Ctrl+E; 助手 = the assistant,
## Ctrl+I), and the bottom drawer (camera / track lanes, music, history, checks, JSON, versions).
## Panels live in res://ui/.

const Document = preload("res://document.gd")
const ThemeFactory = preload("res://theme.gd")
const Tokens = preload("res://theme.gd")
const Timeline = preload("res://timeline.gd")
const Tools = preload("res://tools.gd")
const Server = preload("res://mcp_server.gd")
const Bridge = preload("res://claude_bridge.gd")
const Ops = preload("res://edit_ops.gd")
const U = preload("res://ui/ui_util.gd")
const StablePane = preload("res://ui/stable_pane.gd")
const W = preload("res://ui/widgets.gd")
const Icons = preload("res://ui/icons.gd")
const Inspector = preload("res://ui/inspector.gd")
const TrackList = preload("res://ui/track_list.gd")
const Drawer = preload("res://ui/drawer.gd")
const Assistant = preload("res://ui/assistant_panel.gd")
const Popover = preload("res://ui/segment_popover.gd")
const CompareView = preload("res://compare_view.gd")
const Lib = preload("res://song_library.gd")
const Library = preload("res://ui/library.gd")
const NewSong = preload("res://ui/new_song.gd")
const PluginWindow = preload("res://ui/plugin_window.gd")
const PANES_PATH := "user://charter_panes.json"
const TOOLS := ["select", "tap", "hold", "track"]
const SHAPES := ["rect", "diamond", "circle", "star", "heart"]
const RATES := [0.25, 0.5, 0.75, 1.0]

var doc = Document.new()
var api = Tools.new()
var server = Server.new()
var bridge = Bridge.new()
var script_window
var scripts_b
var timeline = Timeline.new()
var renderer = Renderer.new()
var audio = AudioEngine.new()
var viewport := SubViewport.new()
var compare_view = CompareView.new()
var compare_preview
var inspector = Inspector.new()
var track_list = TrackList.new()
var drawer = Drawer.new()
var assistant = Assistant.new()
var popover = Popover.new()

var light := false
var cursor := 0.0
var playing := false
var test_play := false
var autoplay := true
var loop := false
var rate := 1.0
var silent := false
var shots := ""
var shots_scaled := false          # --shots-scaled: capture with the real proportional UI scale
var persist := true
var song_dirs: Array = []
var settings: Dictionary = {"mcp_port": 47800}
var panes: Dictionary = {"tracks": false, "drawer": false, "tab": "camera", "drawer_h": 270.0, "assistant": false, "assistant_w": 380.0,
	"inspector": false, "inspector_w": 360.0, "library": false, "preview": true, "split": 0.5, "light": false, "scripts": false}
const HINTS_PATH := "user://charter_hints.json"
var last_beat := -999
var last_note := -999.0
var rate_audio_started := false
var turn_revision := ""
var changed_fx: Array = []

# layout nodes
var background := ColorRect.new()
var song_title := Label.new()
var song_sub := Label.new()
var library = Library.new()
var library_b: W.IconButton
var side_tabs
var library_box := VBoxContainer.new()
var tracks_box := VBoxContainer.new()
var library_search := LineEdit.new()
var new_song = NewSong.new()
var more_menu := MenuButton.new()
var file_dialog := FileDialog.new()
var _file_job: Callable
var play_b: W.IconButton
var mode_seg
var clock := HBoxContainer.new()
var time_main := Label.new()
var time_sub := Label.new()
var metro_b: W.IconButton
var tick_b: W.IconButton
var loop_b: W.IconButton
var tracks_b: W.IconButton
var assistant_b: W.IconButton
var inspector_b: W.IconButton
var dock_grip := Control.new()
var preview_frame := AspectRatioContainer.new()
var hint_card: PanelContainer
var preview_b: W.IconButton
var theme_b: W.IconButton
var save_b := Button.new()
var tool_seg
var shape_seg
var grid_field
var section_label := Label.new()
var kiai_badge := Label.new()
var tracks_pane := StablePane.new()
var track_search := LineEdit.new()
var main_split := HBoxContainer.new()
var divider := Control.new()
var timeline_card := StablePane.new()
var compare_bar := HBoxContainer.new()
var compare_title := Label.new()
var right_col := VBoxContainer.new()
var preview_card := PanelContainer.new()
var preview_aspect := AspectRatioContainer.new()
var preview_rect := TextureRect.new()
var preview_field := Node2D.new()
var inspector_card := StablePane.new()
var assistant_holder := Control.new()
var status_label := Label.new()
var save_state := Label.new()
var strip_buttons: Dictionary = {}
var sheet: PanelContainer

func songs_root() -> String:
	return OS.get_executable_path().get_base_dir().path_join("songs") if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://../songs").simplify_path()

## ------------------------------------------------------------------ startup
func _ready() -> void:
	DisplayServer.window_set_title("L’âge tendre Charter")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for arg in OS.get_cmdline_user_args():
		if arg == "--silent": silent = true
		if arg.begins_with("--shots="): shots = arg.substr(8); silent = true; persist = false
		if arg == "--shots-scaled": shots_scaled = true
	AudioServer.set_bus_mute(0, silent)
	if persist: _load_state()
	apply_ui_scale()
	light = bool(panes.get("light", false))
	api.doc = doc; api.author = "user"; api.server = server; api.app = self; api.songs_root = songs_root(); api.attachments = preload("res://attachments.gd").new(); api.attachments.start(); bridge.api = api; bridge.server = server; bridge.doc = doc
	timeline.locked_tracks = doc.locked_tracks
	add_child(audio); add_child(server); add_child(bridge)
	server.start(api, int(settings.get("mcp_port", 47800))); bridge.config = ProjectSettings.globalize_path(server.config_path)
	doc.changed.connect(on_document_changed)
	build_ui(); apply_theme()
	get_window().files_dropped.connect(_agent_files_dropped)
	# Embedded Window preserves the shared theme and the root's proportional scale.
	get_viewport().gui_embed_subwindows=true
	script_window=PluginWindow.new(); script_window.app=self; add_child(script_window); script_window.theme=theme
	_scan_songs()
	var want := str(settings.get("last_song", "_demo")) if persist else "_demo"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--song="): want = arg.substr(7)          # open a given song folder directly
	var index := song_dirs.find(want)
	if index < 0: index = maxi(0, song_dirs.find("_demo"))
	if not song_dirs.is_empty(): load_song(index)
	bridge.message.connect(assistant.on_message)
	bridge.auth_state.connect(assistant.set_auth)
	bridge.auth_output.connect(assistant.show_auth_output)
	bridge.done.connect(_turn_done)
	bridge.auth("status")
	apply_panes(true)
	print("CHARTER_READY songs=", song_dirs.size(), " notes=", doc.raw.get("notes", []).size(), " mcp=", server.port)
	if not shots.is_empty(): capture_shots.call_deferred()

func _load_state() -> void:
	if FileAccess.file_exists("user://charter_settings.json"):
		var saved = JSON.parse_string(FileAccess.get_file_as_string("user://charter_settings.json"))
		if saved is Dictionary: settings.merge(saved, true)
	if FileAccess.file_exists(PANES_PATH):
		var p = JSON.parse_string(FileAccess.get_file_as_string(PANES_PATH))
		if p is Dictionary: panes.merge(p, true)

## UI scale (owner, 2026-10-16): the whole editor scales proportionally with the window -- text, icons, spacing and the
## timeline together, never just a bigger page -- from a 1600 x 900 design size (keep aspect, expand the extra side).
## Ctrl + = / Ctrl + - zoom on top of that, Ctrl + 0 resets; remembered in charter_settings.json.  Screenshot runs
## stay unscaled unless --shots-scaled is given (then they show what the owner sees at 2880 x 1800 and 1920 x 1080).
const DESIGN_SIZE := Vector2i(1600, 900)

func apply_ui_scale() -> void:
	var root := get_tree().root
	get_window().min_size = Vector2i(1280, 720)
	if not shots.is_empty() and not shots_scaled:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED; root.content_scale_factor = 1.0
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = DESIGN_SIZE
	root.content_scale_factor = clampf(float(settings.get("ui_zoom", 1.0)), 0.6, 2.0)

func set_ui_zoom(z: float) -> void:
	if z <= 0.0: settings.erase("ui_zoom")
	else: settings["ui_zoom"] = clampf(snappedf(z, 0.05), 0.6, 2.0)
	apply_ui_scale()
	if persist:
		var f := FileAccess.open("user://charter_settings.json", FileAccess.WRITE)
		if f: f.store_string(JSON.stringify(settings)); f.close()

func save_panes() -> void:
	if not persist: return
	panes.light = light
	var f := FileAccess.open(PANES_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(panes)); f.close()

## ------------------------------------------------------------------ layout
func _label(text: String, variation: String = "") -> Label:
	var l := Label.new(); l.text = text; l.theme_type_variation = variation; return l

func _spacer() -> Control:
	var c := Control.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return c

func _gap(w: float) -> Control:
	var c := Control.new(); c.custom_minimum_size.x = w; return c

func build_ui() -> void:
	background.name = "Background"; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_topbar())
	var body_margin := MarginContainer.new(); body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: body_margin.add_theme_constant_override("margin_" + side, 14)
	body_margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(body_margin)
	var outer := VBoxContainer.new(); outer.add_theme_constant_override("separation", 10); body_margin.add_child(outer)
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 10)
	outer.add_child(body)
	body.add_child(_build_tracks_pane())
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main_split.add_theme_constant_override("separation", 0); body.add_child(main_split)
	main_split.add_child(_build_timeline_card())
	divider.custom_minimum_size.x = 12; divider.mouse_default_cursor_shape = Control.CURSOR_HSIZE; divider.tooltip_text = "拖动调整时间线与预览的宽度"
	divider.gui_input.connect(_divider_input); divider.mouse_entered.connect(divider.queue_redraw); divider.mouse_exited.connect(divider.queue_redraw)
	divider.draw.connect(func():
		var hot := Rect2(Vector2.ZERO, divider.size).has_point(divider.get_local_mouse_position())
		divider.draw_line(Vector2(6, divider.size.y / 2.0 - 16), Vector2(6, divider.size.y / 2.0 + 16), Tokens.c("clay") if hot else Tokens.c("border_strong"), 3, true))
	main_split.add_child(divider)
	right_col.add_theme_constant_override("separation", 10); right_col.custom_minimum_size.x = 380; right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(right_col)
	# the preview owns the whole right column: 16:9, as large as the column allows, centred
	preview_frame.ratio = 16.0 / 9.0; preview_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	preview_frame.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER; preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(preview_frame)
	preview_frame.add_child(_build_preview_card())
	main_split.resized.connect(_apply_split)
	get_window().size_changed.connect(func(): _fit_preview_pixels.call_deferred())
	# right dock (like Agent's side panel): one slot, two tabs -- 属性 (inspector) and 助手 (assistant)
	dock_grip.name = "DockGrip"; dock_grip.custom_minimum_size.x = 6; dock_grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	dock_grip.tooltip_text = "拖动调整宽度"
	dock_grip.gui_input.connect(func(e):
		if e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var key := "assistant_w" if panes.assistant else "inspector_w"
			panes[key] = clampf(float(panes[key]) - e.relative.x, 320.0, 560.0)
			(assistant if panes.assistant else inspector_card).custom_minimum_size.x = panes[key]
		elif e is InputEventMouseButton and not e.pressed: save_panes())
	body.add_child(dock_grip)
	body.add_child(_build_inspector_pane())
	assistant.bridge = bridge; assistant.doc = doc; assistant.app = self
	assistant.custom_minimum_size.x = 380
	assistant.close_requested.connect(func(): toggle_pane("assistant"))
	assistant.turn_undo.connect(undo_claude_turn); assistant.turn_keep.connect(clear_turn_highlights)
	body.add_child(assistant)
	drawer.app = self; drawer.doc = doc; drawer.timeline = timeline; drawer.clip_contents = true; assistant.clip_contents = true
	drawer.closed.connect(func(): toggle_pane("drawer"))
	drawer.resized_to.connect(func(h): panes.drawer_h = h; save_panes())
	outer.add_child(drawer)
	root.add_child(_build_strip())
	add_child(popover)
	sheet = _build_sheet(); add_child(sheet)
	hint_card = _build_hint(); add_child(hint_card)
	new_song.created.connect(_song_created); add_child(new_song)
	file_dialog.use_native_dialog = true; file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_selected.connect(func(path): if _file_job.is_valid(): _file_job.call(path))
	file_dialog.dir_selected.connect(func(path): if _file_job.is_valid(): _file_job.call(path))
	add_child(file_dialog)

## The inspector as a dock tab: a titled pane with its own close button, content scrolls.
func _build_inspector_pane() -> Control:
	inspector_card.theme_type_variation = "Pane"; inspector_card.clip_contents = true; inspector_card.custom_minimum_size.x = 360
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); inspector_card.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var mark := Control.new(); mark.custom_minimum_size = Vector2(24, 34)
	mark.draw.connect(func(): Icons.draw(mark, "sliders", Vector2(11, 17), 18, Tokens.c("muted")))
	head.add_child(mark)
	var title := _label("属性", "Title"); title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; head.add_child(title)
	head.add_child(_spacer())
	var close_b := W.IconButton.new("close", "收起（Ctrl+E）"); close_b.pressed.connect(func(): toggle_pane("inspector")); head.add_child(close_b)
	var isc := ScrollContainer.new(); isc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; isc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(isc)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL; isc.add_child(inspector)
	inspector.doc = doc; inspector.timeline = timeline; inspector.app = self
	return inspector_card

## One-time hint under the 助手 toggle (first launch only; dismissed for good in user://).
func _hint_seen() -> bool:
	if not FileAccess.file_exists(HINTS_PATH): return false
	var h = JSON.parse_string(FileAccess.get_file_as_string(HINTS_PATH))
	return h is Dictionary and bool(h.get("assistant", false))

func dismiss_hint() -> void:
	if hint_card == null or not hint_card.visible: return
	hint_card.visible = false
	if persist:
		var f := FileAccess.open(HINTS_PATH, FileAccess.WRITE)
		if f: f.store_string(JSON.stringify({"assistant": true})); f.close()

func _build_hint() -> PanelContainer:
	var card := PanelContainer.new(); card.theme_type_variation = "Float"; card.name = "AssistantHint"
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); card.add_child(row)
	var mark := Control.new(); mark.custom_minimum_size = Vector2(20, 30)
	mark.draw.connect(func(): Icons.draw(mark, "sparkle", Vector2(10, 15), 16, Tokens.CLAY))
	row.add_child(mark)
	var l := _label("Agent 在这里，Ctrl+I 打开", ""); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row.add_child(l)
	var ok := Button.new(); ok.text = "知道了"; ok.theme_type_variation = "Ghost"; ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(dismiss_hint); row.add_child(ok)
	card.visible = not _hint_seen()
	return card

func _place_hint() -> void:
	if hint_card == null or not hint_card.visible or assistant_b == null: return
	var r := assistant_b.get_global_rect()
	var s := hint_card.get_combined_minimum_size()
	hint_card.size = s
	hint_card.position = Vector2(clampf(r.end.x - s.x, 8.0, size.x - s.x - 8.0), r.end.y + 8.0)

## Top bar: identity and song on the left, listening in the middle, document actions on the right.
## Icons 20 px in 36 px targets; the only filled colour is Save.
func _top_icon(name: String, tip: String) -> W.IconButton:
	var b := W.IconButton.new(name, tip); b.custom_minimum_size = Vector2(36, 36); b.icon_size = 20
	return b

func _build_topbar() -> Control:
	var bar := MarginContainer.new()
	for side in ["left", "right"]: bar.add_theme_constant_override("margin_" + side, 14)
	bar.add_theme_constant_override("margin_top", 10); bar.add_theme_constant_override("margin_bottom", 10)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); bar.add_child(row)
	library_b = _pane_toggle("panel_left", "歌曲", "歌曲库：打开、新建、导入、导出（Ctrl+L）"); library_b.pressed.connect(func(): toggle_pane("library")); row.add_child(library_b)
	tracks_b = _pane_toggle("node", "轨道", "轨道列表（Ctrl+B）"); tracks_b.pressed.connect(func(): toggle_pane("tracks")); row.add_child(tracks_b)
	row.add_child(_gap(10))
	# the open song, like the conversation title in the Agent app: click to show the library
	var song_box := HBoxContainer.new(); song_box.add_theme_constant_override("separation", 10); song_box.custom_minimum_size.x = 120
	song_box.size_flags_horizontal = Control.SIZE_FILL; song_box.custom_minimum_size.x = 160; song_box.mouse_filter = Control.MOUSE_FILTER_STOP
	song_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; song_box.tooltip_text = "当前歌曲。点击打开歌曲库（Ctrl+L）"
	song_box.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: toggle_pane("library"))
	song_title.max_lines_visible = 1; song_title.custom_minimum_size.y = 32
	song_title.theme_type_variation = "Title"; song_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; song_title.clip_text = true
	song_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; song_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	song_title.mouse_filter = Control.MOUSE_FILTER_PASS
	U.bounded_label(song_sub, 64, true)
	song_sub.theme_type_variation = "Muted"; song_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; song_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	song_box.add_child(song_title); song_box.add_child(song_sub)
	row.add_child(song_box)
	row.add_child(_gap(12))
	# transport: everything about listening sits together
	play_b = W.IconButton.new("play", "播放或暂停（Space）"); play_b.custom_minimum_size = Vector2(40, 40); play_b.icon_size = 18; play_b.round = true
	play_b.pressed.connect(toggle_play); row.add_child(play_b)
	clock.name = "TransportClock"; clock.add_theme_constant_override("separation", 10); clock.size_flags_horizontal = Control.SIZE_FILL
	time_main.add_theme_font_override("font", Tokens.font("mono", 600)); time_main.add_theme_font_size_override("font_size", Tokens.MD)
	time_main.tooltip_text = "小节.拍"; time_main.mouse_filter = Control.MOUSE_FILTER_PASS
	time_sub.theme_type_variation = "MonoMuted"; time_sub.tooltip_text = "分:秒"; time_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	for l in [time_main, time_sub]: l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.size_flags_vertical = Control.SIZE_FILL
	clock.add_child(_gap(2)); clock.add_child(time_main); clock.add_child(time_sub); row.add_child(clock)
	mode_seg = W.Segmented.new(["预览", "自动", "试玩"], 0, ["只看画面，不判定", "真实判定，自动演奏", "真实判定，由你来按（Esc 退出）"])
	mode_seg.changed.connect(func(i): test_play = i > 0; autoplay = i < 2; if playing: restart_transport())
	row.add_child(mode_seg)
	var rate_pick := OptionButton.new(); rate_pick.theme_type_variation = "GhostOption"; rate_pick.focus_mode = Control.FOCUS_NONE; rate_pick.tooltip_text = "播放速度"
	for r in RATES: rate_pick.add_item(("%s×" % str(r)).replace("0.", "."))
	U.bounded_option(rate_pick, 64); rate_pick.add_theme_font_override("font", Tokens.font("num"))
	rate_pick.custom_minimum_size.y = 36
	rate_pick.select(3); rate_pick.item_selected.connect(func(i): rate = RATES[i]; audio.music.pitch_scale = rate)
	rate_pick.gui_input.connect(func(e):
		var d := 0
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP: d = 1
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN: d = -1
		if d != 0:
			var i := clampi(rate_pick.selected + d, 0, RATES.size() - 1); rate_pick.select(i); rate_pick.item_selected.emit(i); rate_pick.accept_event())
	row.add_child(rate_pick)
	metro_b = _top_icon("metronome", "节拍器"); metro_b.toggle_mode = true; row.add_child(metro_b)
	tick_b = _top_icon("tick", "音符提示音"); tick_b.toggle_mode = true; row.add_child(tick_b)
	loop_b = _top_icon("loop", "循环播放所选时间段"); loop_b.toggle_mode = true; loop_b.toggled.connect(func(on): loop = on); row.add_child(loop_b)
	row.add_child(_gap(16))
	var undo_b := _top_icon("undo", "撤销（Ctrl+Z）"); undo_b.pressed.connect(func(): report(doc.undo())); row.add_child(undo_b)
	var redo_b := _top_icon("redo", "重做（Ctrl+Y）"); redo_b.pressed.connect(func(): report(doc.redo())); row.add_child(redo_b)
	row.add_child(_gap(6))
	theme_b = _top_icon("sun", "切换浅色或深色"); theme_b.pressed.connect(func(): light = not light; apply_theme(); save_panes()); row.add_child(theme_b)
	# overflow: files (new, import, export, game song list) and settings
	more_menu.text = "⋯"; more_menu.flat = true; more_menu.focus_mode = Control.FOCUS_NONE; more_menu.tooltip_text = "歌曲文件与设置"
	more_menu.custom_minimum_size = Vector2(36, 36); more_menu.add_theme_font_size_override("font_size", Tokens.LG)
	var mp := more_menu.get_popup()
	for item in [["歌曲设置（BPM、偏移、歌名）", 8], [], ["新建歌曲…", 0], ["新建社区谱面…", 9], ["导入谱面 chart.json…", 1], ["导入歌曲文件夹…", 2], ["导入歌曲包 .zip…", 3], [], ["导出歌曲包（.zip）…", 4], ["导出谱面 chart.json…", 5], ["加入游戏歌单…", 6], [], ["设置…", 7]]:
		if item.is_empty(): mp.add_separator()
		else: mp.add_item(item[0], item[1])
	mp.id_pressed.connect(_more_action)
	row.add_child(more_menu)
	row.add_child(_gap(6))
	save_b.text = "保存"; save_b.theme_type_variation = "Primary"; save_b.focus_mode = Control.FOCUS_NONE; save_b.tooltip_text = "保存谱面（Ctrl+S）"
	save_b.clip_text = true; save_b.custom_minimum_size = Vector2(76, 36); save_b.pressed.connect(confirm_save); row.add_child(save_b)
	# pane toggles, labelled, at the far right like the Agent app: the preview, then the dock's two tabs
	var sep := VSeparator.new(); sep.custom_minimum_size = Vector2(17, 24); sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(sep)
	preview_b = _pane_toggle("preview", "画面", "实时预览（Ctrl+P）"); preview_b.pressed.connect(func(): toggle_pane("preview")); row.add_child(preview_b)
	inspector_b = _pane_toggle("sliders", "属性", "所选内容的属性（Ctrl+E）"); inspector_b.pressed.connect(func(): toggle_pane("inspector")); row.add_child(inspector_b)
	assistant_b = _pane_toggle("sparkle", "Agent", "Agent（Ctrl+I）"); assistant_b.pressed.connect(func(): toggle_pane("assistant")); row.add_child(assistant_b)
	scripts_b = _pane_toggle("code", "脚本", "插件与脚本工房（Ctrl+Shift+E）"); scripts_b.pressed.connect(func(): toggle_pane("scripts")); row.add_child(scripts_b)
	resized.connect(_fit_topbar); _fit_topbar.call_deferred()
	return bar

## Viewport changes select a deterministic compact profile. Text/value changes
## never trigger responsive layout. Full captions remain available as tooltips.
func _fit_topbar() -> void:
	var compact := size.x < 1560
	for pair in [[library_b, "歌曲"], [tracks_b, "轨道"], [scripts_b, "脚本"]]:
		pair[0].set_caption("" if compact else pair[1])

## A labelled pane toggle: icon + word, 36 high, clay tint while its pane is open.
func _pane_toggle(icon: String, word: String, tip: String) -> W.IconButton:
	var b := W.IconButton.new(icon, tip, word); b.custom_minimum_size.y = 36
	return b

## Left sidebar, two tabs: 歌曲 (the song library) and 轨道 (the track list).
func _build_tracks_pane() -> Control:
	tracks_pane.theme_type_variation = "Pane"; tracks_pane.custom_minimum_size.x = 320; tracks_pane.clip_contents = true
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); tracks_pane.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	side_tabs = W.Segmented.new(["歌曲", "轨道"], 0, ["歌曲库（Ctrl+L）", "轨道列表（Ctrl+B）"])
	side_tabs.changed.connect(func(i): toggle_pane("library" if i == 0 else "tracks", true))
	head.add_child(side_tabs); head.add_child(_spacer())
	var close_b := W.IconButton.new("close", "收起"); close_b.pressed.connect(func(): toggle_pane("tracks" if panes.tracks else "library")); head.add_child(close_b)
	# songs
	library_box.add_theme_constant_override("separation", 8); library_box.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(library_box)
	var lrow := HBoxContainer.new(); library_box.add_child(lrow)
	library_search.placeholder_text = "搜索歌名、作者"; library_search.clear_button_enabled = true; library_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_search.text_changed.connect(func(t): library.filter = t; library.rebuild())
	lrow.add_child(library_search)
	var new_b := W.IconButton.new("plus", "新建歌曲：选音频、定速、设第一拍", "新建"); new_b.custom_minimum_size.y = 36; new_b.pressed.connect(open_new_song); lrow.add_child(new_b)
	var lsc := ScrollContainer.new(); lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL; lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lsc.add_child(library); library_box.add_child(lsc)
	library.open_dir.connect(open_song)
	library.action.connect(song_action)
	# tracks
	tracks_box.add_theme_constant_override("separation", 8); tracks_box.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(tracks_box)
	var trow := HBoxContainer.new(); tracks_box.add_child(trow)
	track_search.placeholder_text = "搜索轨道编号"; track_search.clear_button_enabled = true; track_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_search.text_changed.connect(func(t): track_list.filter = t; track_list.rebuild())
	trow.add_child(track_search)
	var add_b := W.IconButton.new("plus", "画一条新轨道（轨道工具，按 4）", "新轨道"); add_b.custom_minimum_size.y = 36; add_b.pressed.connect(func(): set_tool("track")); trow.add_child(add_b)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(track_list); tracks_box.add_child(sc)
	track_list.doc = doc; track_list.timeline = timeline
	track_list.pick.connect(func(id): timeline.set_selection([], [id]))
	track_list.jump.connect(func(t): seek(maxf(0.0, t + 0.5)))
	track_list.flags_changed.connect(func(): inspector.refresh(true))
	return tracks_pane

func _build_timeline_card() -> Control:
	timeline_card.theme_type_variation = "Pane"; timeline_card.size_flags_horizontal = Control.SIZE_FILL
	timeline_card.add_theme_stylebox_override("panel", Tokens.box(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 0))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); timeline_card.add_child(v)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 8); v.add_child(head)
	tool_seg = W.Segmented.new(["icon:select", "icon:note", "icon:hold", "icon:track"], 0, ["选择与编辑（1 或 V）", "放点按音符（2 或 N）", "放长按音符，向上拖出长度（3 或 H）", "画轨道，拖出范围（4 或 T）"])
	tool_seg.changed.connect(func(i): set_tool(TOOLS[i]))
	head.add_child(tool_seg)
	shape_seg = W.Segmented.new(["icon:shape_rect", "icon:shape_diamond", "icon:shape_circle", "icon:shape_star", "icon:shape_heart"], 0, ["矩形：今日的轨道", "菱形（需要新轨道语法）", "圆形（需要新轨道语法）", "星形（需要新轨道语法）", "心形（需要新轨道语法）"])
	shape_seg.changed.connect(func(i): timeline.shape_kind = SHAPES[i])
	shape_seg.visible = false; head.add_child(shape_seg)
	head.add_child(_spacer())
	# where the playhead is in the song: section name, and a badge while inside a KIAI span
	U.bounded_label(section_label, 88)
	section_label.theme_type_variation = "Muted"; section_label.tooltip_text = "播放头所在的段落"; section_label.mouse_filter = Control.MOUSE_FILTER_PASS
	section_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; head.add_child(section_label)
	U.bounded_label(kiai_badge, 32)
	kiai_badge.text = ""; kiai_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kiai_badge.add_theme_font_override("font", Tokens.font("sans", 600)); kiai_badge.add_theme_font_size_override("font_size", Tokens.XS)
	head.add_child(kiai_badge)
	head.add_child(_gap(8))
	grid_field = W.EnumField.new("网格", ["1 分", "2 分", "3 分", "4 分", "6 分", "8 分", "12 分", "16 分"], 7)
	grid_field.get_child(0).custom_minimum_size.x = 36; grid_field.box.custom_minimum_size.x = 84; grid_field.box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid_field.box.tooltip_text = "每小节分几格。滚轮或 [ ] 切换，轨道节点随网格出现"
	grid_field.changed.connect(func(i): timeline.grid = Timeline.GRIDS[i]; timeline.queue_redraw())
	head.add_child(grid_field)
	var finger := W.IconButton.new("fingering", "始终显示每个音符的键位字母"); finger.toggle_mode = true
	finger.toggled.connect(func(on): timeline.show_fingering = on; timeline.queue_redraw()); head.add_child(finger)
	var windows := W.IconButton.new("window", "显示判定窗口"); windows.toggle_mode = true
	windows.toggled.connect(func(on): timeline.show_windows = on; timeline.queue_redraw()); head.add_child(windows)
	compare_bar.visible = false; v.add_child(compare_bar)
	U.bounded_label(compare_title)
	compare_title.theme_type_variation = "Heading"; compare_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; compare_bar.add_child(compare_title)
	var close_cmp := W.IconButton.new("close", "回到时间线", "退出对比"); close_cmp.pressed.connect(close_compare); compare_bar.add_child(close_cmp)
	timeline.doc = doc; timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL; timeline.custom_minimum_size = Vector2(420, 300)
	v.add_child(timeline)
	timeline.seek.connect(seek); timeline.selected.connect(on_selection); timeline.nodes_changed.connect(on_selection)
	timeline.status.connect(_say)
	timeline.popover_requested.connect(_open_popover)
	popover.timeline = timeline
	compare_view.visible = false; compare_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(compare_view)
	compare_view.focus_version.connect(focus_compare); compare_view.seek.connect(seek)
	compare_view.take_passage.connect(func(ref, lo, hi): report(doc.version_store().take_range(ref, lo, hi, doc.revision())))
	return timeline_card

func _build_preview_card() -> Control:
	preview_card.theme_type_variation = "Card"
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + side, 6)
	preview_card.add_child(pad)
	preview_aspect.ratio = 16.0 / 9.0; preview_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	pad.add_child(preview_aspect)
	# The game renders at the screen's real pixel size (layout size x UI scale), so the preview stays
	# sharp when the window scales the editor up; the texture is then shown at layout size.
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
	preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE; preview_aspect.add_child(preview_rect)
	viewport.size = Vector2i(640, 360); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; preview_rect.add_child(viewport)
	preview_rect.texture = viewport.get_texture()
	viewport.add_child(preview_field); preview_field.add_child(renderer)
	preview_rect.resized.connect(_fit_preview_pixels)
	preview_field.scale = Vector2.ONE * 0.2
	return preview_card

## Physical pixels per layout pixel (1.0 when the window is not scaled).
func ui_pixel_scale() -> float:
	var layout := get_viewport_rect().size
	return maxf(1.0, float(get_window().size.x) / maxf(1.0, layout.x)) if layout.x > 0 else 1.0

func _fit_preview_pixels() -> void:
	if preview_rect.size.x < 2: return
	var px := (preview_rect.size * ui_pixel_scale()).round()
	viewport.size = Vector2i(maxi(2, int(px.x)), maxi(2, int(px.y)))
	var k := minf(px.x / SU.LW, px.y / SU.LH)
	preview_field.scale = Vector2.ONE * k
	preview_field.position = (px - Vector2(SU.LW, SU.LH) * k) / 2.0

func _build_strip() -> Control:
	var strip := MarginContainer.new()
	for side in ["left", "right"]: strip.add_theme_constant_override("margin_" + side, 14)
	strip.add_theme_constant_override("margin_bottom", 6)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 2); strip.add_child(row)
	var keys := ["camera", "track", "music", "history", "checks", "json", "versions"]
	for i in keys.size():
		var info: Array = Drawer.TABS[keys[i]]
		var b := W.IconButton.new(info[1], "%s（%s）" % [info[0], info[2]], info[0])
		b.custom_minimum_size.y = 34; b.icon_size = 16
		var key: String = keys[i]
		b.pressed.connect(func(): open_drawer(key))
		row.add_child(b); strip_buttons[key] = b
	row.add_child(_gap(16))
	# transient messages (tool hints, refusals) on the left, the save state on the right
	U.bounded_label(status_label, 0, true)
	status_label.theme_type_variation = "Muted"; status_label.clip_text = true; status_label.custom_minimum_size.x = 160
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status_label)
	row.add_child(_gap(12))
	U.bounded_label(save_state, 112, false, false)
	save_state.theme_type_variation = "Muted"; save_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; save_state.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(save_state)
	row.add_child(_gap(4))
	var help := W.IconButton.new("keyboard", "快捷键（?）"); help.pressed.connect(toggle_sheet); row.add_child(help)
	return strip

func _build_sheet() -> PanelContainer:
	var card := PanelContainer.new(); card.theme_type_variation = "Float"; card.visible = false
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); card.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var t := _label("快捷键", "Title"); head.add_child(t)
	head.add_child(_spacer())
	var close_b := W.IconButton.new("close", "关闭（Esc）"); close_b.pressed.connect(func(): card.visible = false); head.add_child(close_b)
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 40); v.add_child(cols)
	var groups := [
		["编辑", [["1–4 或 V N H T", "选择、点按、长按、画轨道"], ["双击", "放音符（选择工具）"], ["拖动", "移动；按住 Alt 拖动是复制"], ["Shift 或 Ctrl 点击", "加选或反选"], ["拖空白处", "框选音符或节点"], ["Delete", "删除所选"], ["Ctrl C、V、D", "复制、粘贴、原位复制"], ["↑ ↓ ← →", "按网格或按键微调"], ["Esc", "取消选择"]]],
		["轨道形状", [["拖节点", "移动这一点（Alt 关闭吸附，Shift 锁定方向）"], ["拖边线", "加宽或收窄"], ["拖主体", "整体移动"], ["双击边线", "插入节点"], ["Ctrl 点两个节点", "选中一个片段"], ["Enter", "打开片段设置"], ["[ ]", "网格密度，节点随之出现"]]],
		["视图与播放", [["滚轮", "沿时间滚动"], ["Ctrl 加滚轮", "以指针为中心缩放"], ["Shift 加滚轮", "移动一格网格"], ["中键拖动", "平移"], ["Space", "从播放头播放或暂停"], ["Home、End", "跳到开头、结尾"], ["Ctrl Z、Y", "撤销、重做"], ["Ctrl S", "保存"], ["Ctrl L、B", "歌曲库、轨道列表"], ["Ctrl J", "底部抽屉"], ["Ctrl E、I", "属性、Claude"], ["Ctrl P", "实时预览"], ["Ctrl + 或 −", "放大或缩小界面，Ctrl 0 复原"], ["Alt 1–7", "打开底部的七个工具"]]],
	]
	for g in groups:
		var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8); cols.add_child(col)
		col.add_child(_label(g[0], "Heading"))
		col.add_child(_gap(0))
		for pair in g[1]:
			var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 12); col.add_child(r)
			var k := W.Kbd.new(pair[0]); r.add_child(k)
			var d := _label(pair[1], "Muted"); d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; r.add_child(d)
	return card

func toggle_sheet() -> void:
	sheet.visible = not sheet.visible
	if sheet.visible:
		sheet.reset_size()
		sheet.position = ((size - sheet.get_combined_minimum_size()) / 2.0).floor()

## ------------------------------------------------------------------ panes
func toggle_pane(which: String, force_open := false) -> void:
	match which:
		"tracks":   # the left sidebar shows one tab at a time, like the right dock
			panes.tracks = true if force_open else not panes.tracks
			if panes.tracks: panes.library = false
		"library":
			panes.library = true if force_open else not panes.library
			if panes.library: panes.tracks = false; library.rescan()
		"assistant":   # the dock shows one tab at a time; opening a tab while the dock is closed opens the dock
			panes.assistant = not panes.assistant
			if panes.assistant: panes.inspector = false; dismiss_hint()
		"inspector":
			panes.inspector = not panes.inspector
			if panes.inspector: panes.assistant = false
		"preview": panes.preview = not panes.preview
		"drawer": panes.drawer = not panes.drawer
		"scripts": panes.scripts = not panes.scripts
	apply_panes(); save_panes()

func open_drawer(tab: String) -> void:
	if panes.drawer and panes.tab == tab: panes.drawer = false
	else: panes.drawer = true; panes.tab = tab
	apply_panes(); save_panes()

func apply_panes(instant := false) -> void:
	if script_window!=null:
		if panes.get("scripts",false) and not script_window.visible: script_window.show_workspace()
		elif not panes.get("scripts",false) and script_window.visible: script_window.close()
		scripts_b.active=panes.get("scripts",false)
	var side_open: bool = panes.tracks or panes.library
	_slide(tracks_pane, "custom_minimum_size:x", 320.0, side_open, instant or (tracks_pane.visible and side_open))
	tracks_b.active = panes.tracks; library_b.active = panes.library
	library_box.visible = panes.library; tracks_box.visible = not panes.library
	side_tabs.set_index(0 if panes.library else 1)
	# switching tabs inside an open dock is instant; only opening / closing the dock slides
	var dock_was_open: bool = assistant.visible or inspector_card.visible
	var dock_open: bool = panes.assistant or panes.inspector
	var swap: bool = dock_was_open and dock_open
	_slide(assistant, "custom_minimum_size:x", float(panes.assistant_w), panes.assistant, instant or swap)
	_slide(inspector_card, "custom_minimum_size:x", float(panes.inspector_w), panes.inspector, instant or swap)
	dock_grip.visible = dock_open
	assistant_b.active = panes.assistant; inspector_b.active = panes.inspector
	if panes.assistant:
		assistant.update_context()
		if not instant: bridge.auth("status")
	if panes.inspector:
		inspector.refresh(true)
		if status_label.text.begins_with("已选"): _say("")
	preview_card.visible = panes.preview; preview_b.active = panes.preview
	right_col.visible = panes.preview; divider.visible = panes.preview
	timeline_card.size_flags_horizontal = Control.SIZE_FILL if panes.preview else Control.SIZE_EXPAND_FILL
	if panes.drawer: drawer.open(panes.tab)
	_slide(drawer, "custom_minimum_size:y", float(panes.drawer_h), panes.drawer, instant)
	for k in strip_buttons: strip_buttons[k].active = panes.drawer and panes.tab == k
	_apply_split.call_deferred()
	track_list.rebuild()

## Keep the timeline | preview split at the remembered ratio (default half / half).
func _apply_split() -> void:
	if main_split.size.x < 10: return
	if not panes.preview: timeline_card.custom_minimum_size.x = 440.0; return
	var w := clampf(main_split.size.x * float(panes.split), 440.0, main_split.size.x - 380.0 - 12.0)
	timeline_card.custom_minimum_size.x = w

func _divider_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		panes.split = clampf((timeline_card.size.x + e.relative.x) / maxf(1.0, main_split.size.x), 0.25, 0.8)
		_apply_split()
	elif e is InputEventMouseButton and not e.pressed: save_panes()

var _slides: Dictionary = {}
func _slide(node: Control, property: String, target: float, show: bool, instant: bool) -> void:
	if _slides.has(node) and is_instance_valid(_slides[node]): _slides[node].kill()
	_slides.erase(node)
	if instant or not is_inside_tree() or shots != "" or node.visible == show:
		node.visible = show; node.set_indexed(property, target); return
	if show:
		node.visible = true; node.set_indexed(property, 0.0)
		var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, property, target, 0.22); _slides[node] = tw
	else:
		var tw := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, property, 0.0, 0.18); tw.tween_callback(func(): node.visible = false; node.set_indexed(property, target))
		_slides[node] = tw

func apply_theme() -> void:
	theme = ThemeFactory.make(light)
	if script_window!=null: script_window.apply_editor_theme()
	var t := Tokens.tokens(light)
	background.color = t.bg
	kiai_badge.add_theme_color_override("font_color", t.clay)
	kiai_badge.add_theme_stylebox_override("normal", Tokens.box(t.clay_tint, 6, Color.TRANSPARENT, 8, 3))
	timeline.light = light; timeline.refresh(true)
	theme_b.icon_name = "moon" if not light else "sun"
	propagate_call("queue_redraw")
	track_list.rebuild()

## ------------------------------------------------------------------ song and document
func load_song(i: int) -> void:
	if assistant.copy_thread != null: report({"error":"附件正在复制，请稍后切换歌曲"}); return
	if script_window!=null and script_window.has_dirty(): report({"error":"脚本工房有未保存文件，请先保存后切换歌曲"}); return
	if bridge.running: report({"error": "助手正在修改谱面，先停止助手再切换歌曲"}); return
	if doc.revision() != doc.saved_revision and not doc.raw.is_empty():
		report({"error": "这首歌有未保存的修改，先保存或撤销再切换歌曲"}); return
	if not doc.path.is_empty(): assistant.save_conversation()
	playing = false; audio.stop(); cursor = 0; bridge.session_id = ""
	timeline.select_track(-1)
	report(doc.open(songs_root().path_join(song_dirs[i]).path_join("chart.json")))
	audio.music.stream = audio.load_stream(api.audio_path())
	assistant.load_conversation()
	seek(doc.seconds("1.1") if is_finite(doc.seconds("1.1")) else 0.0)
	_show_song_title()
	library.current = song_dirs[i]; library.queue_redraw()
	if persist:
		settings["last_song"] = song_dirs[i]
		var f := FileAccess.open("user://charter_settings.json", FileAccess.WRITE)
		if f: f.store_string(JSON.stringify(settings)); f.close()

## ------------------------------------------------------------------ song files (library, new, import, export)
func _scan_songs() -> void:
	song_dirs = []
	var root := songs_root()
	for dir in DirAccess.get_directories_at(root):
		if FileAccess.file_exists(root.path_join(dir).path_join("chart.json")): song_dirs.append(dir)
	if DirAccess.dir_exists_absolute(root.path_join("_plugin_demos")):
		for dir in DirAccess.get_directories_at(root.path_join("_plugin_demos")):
			var nested := "_plugin_demos/" + dir
			if FileAccess.file_exists(root.path_join(nested).path_join("chart.json")): song_dirs.append(nested)
	for e in FanChartLibrary.discover(root).entries: song_dirs.append(str(e.dir))
	library.root = root; library.rescan()

func open_song(dir: String) -> void:
	if not dir in song_dirs: _scan_songs()
	var i := song_dirs.find(dir)
	if i >= 0 and doc.path.get_base_dir().simplify_path() != songs_root().path_join(dir).simplify_path(): load_song(i)

func current_dir() -> String:
	var base: String = str(doc.path).get_base_dir().replace("\\", "/").simplify_path()
	var prefix := songs_root().replace("\\", "/").simplify_path().trim_suffix("/") + "/"
	return base.trim_prefix(prefix) if base.begins_with(prefix) else base.get_file()

func _show_song_title() -> void:
	var info: Dictionary = api.call_tool("song_info", {})
	song_title.text = str(info.get("title", current_dir()))
	var version := str(doc.song_meta.get("version", doc.raw.get("meta", {}).get("difficulty", "")))
	song_sub.text = version if doc.song_meta.has("version") else (current_dir() + (" " + version if not version.is_empty() else ""))
	song_title.tooltip_text = song_title.text + "\n" + doc.path
	song_sub.tooltip_text = song_sub.text

## 歌曲设置 is the 属性 page with nothing selected.
func open_song_settings() -> void:
	timeline.set_selection([], [])
	if not panes.inspector: toggle_pane("inspector")
	inspector.refresh(true)

func replace_audio_dialog() -> void:
	_pick_file("替换音频", FileDialog.FILE_MODE_OPEN_FILE, ["*.mp3, *.ogg, *.wav ; 音频"], "", func(path):
		var ask := ConfirmationDialog.new(); ask.title = "替换音频"
		ask.dialog_text = "用 %s 替换这首歌的音频？原来的音频会改名保留为备份。谱面不变；如果新音频开头长短不同，再调整音频偏移。" % path.get_file()
		ask.ok_button_text = "替换"; ask.cancel_button_text = "取消"
		add_child(ask); ask.popup_centered(Vector2i(520, 170))
		ask.canceled.connect(ask.queue_free)
		ask.confirmed.connect(func():
			ask.queue_free()
			var result := Lib.replace_audio(doc.path.get_base_dir(), path)
			if result.has("error"): report(result); return
			playing = false; audio.stop(); audio.music.stream = audio.load_stream(api.audio_path())
			inspector.refresh(true)
			_say("音频已替换为 %s，原音频已备份" % str(result.path).get_file())))

func open_new_song() -> void:
	new_song.root = songs_root(); new_song.open(false)

func open_new_fan_song() -> void:
	new_song.root = songs_root(); new_song.open(true)

func _song_created(result: Dictionary) -> void:
	_scan_songs(); open_song(str(result.dir))
	_say(("已新建社区谱面 %s；提交前填写 info.json 和 CREDITS.md 的授权信息" if result.get("fan_made", false) else "已新建 %s，并加入游戏歌单（index.json 已备份）") % str(result.dir))

func _more_action(id: int) -> void:
	match id:
		0: open_new_song()
		1: _pick_file("导入谱面 chart.json", FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; 谱面"], "", func(path): _imported(Lib.import_chart(songs_root(), path, current_dir())))
		2: _pick_file("导入歌曲文件夹（含 chart.json 和音频）", FileDialog.FILE_MODE_OPEN_DIR, [], "", func(path): _imported(Lib.import_folder(songs_root(), path)))
		3: _pick_file("导入歌曲包", FileDialog.FILE_MODE_OPEN_FILE, ["*.zip ; 歌曲包"], "", func(path): _imported(Lib.import_zip(songs_root(), path)))
		4: song_action("export_package", current_dir())
		5: song_action("export_chart", current_dir())
		6: song_action("add_to_game", current_dir())
		7: settings_dialog()
		8: open_song_settings()
		9: open_new_fan_song()

func _pick_file(title: String, mode: int, filters: Array, filename: String, job: Callable) -> void:
	file_dialog.title = title; file_dialog.file_mode = mode; file_dialog.filters = PackedStringArray(filters)
	file_dialog.current_file = filename; _file_job = job
	file_dialog.popup_file_dialog()

func _imported(result: Dictionary) -> void:
	if result.has("error"): report(result); return
	_scan_songs(); open_song(str(result.dir))
	_say("已导入到 songs/%s" % str(result.dir))

## Export and game-list actions for a song folder (from the library's context menu or the ⋯ menu).
func song_action(what: String, dir: String) -> void:
	var root := songs_root()
	var raw: Dictionary = doc.raw if dir == current_dir() else {}
	var entry := {}
	for e in Lib.read_index(root):
		if e is Dictionary and str(e.get("dir", "")) == dir:
			entry = e
	var name := Lib.slug(str(entry.get("title", dir))) + ("-" + str(entry.version).to_lower() if entry.has("version") else "")
	match what:
		"open": open_song(dir)
		"settings": open_song(dir); open_song_settings()
		"reveal": OS.shell_show_in_file_manager(root.path_join(dir).path_join("chart.json"))
		"export_package":
			_pick_file("导出歌曲包", FileDialog.FILE_MODE_SAVE_FILE, ["*.zip ; 歌曲包"], name + ".zip", func(path):
				_export_with_confirm(func(ow): return Lib.export_package(root, dir, _with_ext(path, "zip"), raw, ow), "歌曲包"))
		"export_chart":
			_pick_file("导出谱面", FileDialog.FILE_MODE_SAVE_FILE, ["*.json ; 谱面"], name + ".chart.json", func(path):
				_export_with_confirm(func(ow): return Lib.export_chart(root.path_join(dir), _with_ext(path, "json"), raw, ow), "谱面"))
		"add_to_game": _add_to_game_dialog(dir)

func _with_ext(path: String, ext: String) -> String:
	return path if path.get_extension().to_lower() == ext else path + "." + ext

func _export_with_confirm(job: Callable, what: String) -> void:
	var result: Dictionary = job.call(false)
	if str(result.get("error", "")) == "exists":
		var ask := ConfirmationDialog.new(); ask.title = "文件已存在"
		ask.dialog_text = "%s 已经存在。要用这次导出的%s替换它吗？" % [str(result.path).get_file(), what]
		ask.ok_button_text = "替换"; ask.cancel_button_text = "取消"
		add_child(ask); ask.popup_centered(Vector2i(460, 150))
		ask.confirmed.connect(func(): _export_done(job.call(true), what); ask.queue_free()); ask.canceled.connect(ask.queue_free)
		return
	_export_done(result, what)

func _export_done(result: Dictionary, what: String) -> void:
	if result.has("error"): report(result); return
	var dirty: bool = doc.revision() != doc.saved_revision
	_say("已导出%s到 %s%s" % [what, str(result.path), "（包含尚未保存的修改）" if dirty else ""])

## 加入游戏歌单: which song set and difficulty this folder is in the game's song select.
func _add_to_game_dialog(dir: String) -> void:
	var root := songs_root()
	var group := {}
	for g in Lib.scan(root):
		for d in g.diffs + g.copies:
			if d.dir == dir:
				group = g
	var entry := {}
	for e in Lib.read_index(root):
		if e is Dictionary and str(e.get("dir", "")) == dir:
			entry = e
	var meta: Dictionary = doc.raw.get("meta", {}) if dir == current_dir() else Lib.chart_meta(root.path_join(dir))
	var dialog := ConfirmationDialog.new(); dialog.title = "加入游戏歌单"; dialog.ok_button_text = "加入"; dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 10); dialog.add_child(box)
	var same_song: bool = not group.is_empty() and not group.get("diffs", []).is_empty() and not group.get("other", false)
	var intro := _label(("作为《%s》的一个难度加入游戏的选歌界面。" % group.title) if same_song else "作为一首新歌加入游戏的选歌界面。", "Muted")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(intro)
	var vrow := HBoxContainer.new(); box.add_child(vrow)
	vrow.add_child(_label("难度名", "Muted"))
	var version := LineEdit.new(); version.custom_minimum_size.x = 160
	version.text = str(entry.get("version", meta.get("difficulty", "")))
	if version.text.is_empty(): version.text = "EX"
	vrow.add_child(version)
	var level := W.ScrubField.new("等级", "", 1.0); level.min_value = 0; level.max_value = 15; level.formatter = func(x): return str(int(x))
	level.set_value(float(entry.get("level", 10)))
	box.add_child(level)
	var err := _label("", "Muted"); err.add_theme_color_override("font_color", Tokens.DANGER); err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(err)
	add_child(dialog); dialog.popup_centered(Vector2i(480, 230))
	dialog.get_ok_button().pressed.connect(func():
		var fields := {"version": version.text.strip_edges().to_upper(), "level": int(level.value)}
		if same_song:
			fields.set = str(group.key); fields.title = str(group.title); fields.artist = str(group.artist)
		var result: Dictionary = Lib.add_to_index(root, dir, fields)
		if result.has("error"): report(result); return
		library.rescan(); doc.song_meta = result.entry.duplicate(true); _show_song_title()
		_say("已加入游戏歌单：%s %s（index.json 已备份）" % [str(result.entry.title), str(result.entry.version)]))
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())

func wire_core() -> void:
	if not doc.core.ripple.is_connected(renderer.add_ripple): doc.core.ripple.connect(renderer.add_ripple)
	if not doc.core.judged.is_connected(renderer.add_judge): doc.core.judged.connect(renderer.add_judge)
	if not doc.core.hold_end.is_connected(renderer.add_hold_end): doc.core.hold_end.connect(renderer.add_hold_end)
	if not doc.core.combo_break.is_connected(renderer.add_combo_break): doc.core.combo_break.connect(renderer.add_combo_break)

func on_document_changed() -> void:
	_reserve_clock()
	wire_core()
	timeline.refresh(true)
	track_list.rebuild()
	inspector.refresh()
	if drawer.visible: drawer.refresh()
	if popover.visible: popover.rebuild()
	report({})

func on_selection() -> void:
	inspector.refresh()
	if not panes.inspector: _say(_selection_hint())
	assistant.update_context()
	track_list.queue_redraw()
	if drawer.visible and drawer.tab in ["json", "track"]: drawer.refresh()
	if popover.visible and (timeline.sel_nodes.size() != 2): popover.close()

## With the 属性 tab closed, the status strip names the selection and how to edit it.
func _selection_hint() -> String:
	var n: int = doc.selection.get("notes", []).size()
	if not timeline.sel_nodes.is_empty(): return "已选 %d 个节点。Ctrl+E 打开属性" % timeline.sel_nodes.size()
	if n > 0: return "已选 %d 个音符。Ctrl+E 打开属性" % n
	if not doc.selection.get("tracks", []).is_empty(): return "已选轨道 %d。Ctrl+E 打开属性" % int(doc.selection.tracks[0])
	if not doc.selection.get("fx", []).is_empty(): return "已选一个镜头事件。Ctrl+E 打开属性"
	return ""

func refresh_side() -> void:
	track_list.queue_redraw(); timeline.queue_redraw()

func report(result: Dictionary) -> void:
	var dirty: bool = doc.revision() != doc.saved_revision
	save_state.text = "有未保存的修改" if dirty else "已保存"
	save_state.add_theme_color_override("font_color", Tokens.c("clay") if dirty else Tokens.c("muted"))
	var details := ["修订 " + doc.revision().left(8), "内置 MCP 端口 %d" % server.port]
	if not doc.ext_empty(): details.append("引擎暂不支持的形状和运动保存在 chart.ext.json")
	save_state.tooltip_text = "\n".join(details)
	if result.has("error"):
		status_label.text = Ops.explain(result); status_label.add_theme_color_override("font_color", Tokens.c("danger"))
	elif status_label.has_theme_color_override("font_color"):
		status_label.remove_theme_color_override("font_color"); status_label.text = ""
	save_b.disabled = not dirty
	var issues: int = drawer.count_issues()
	strip_buttons.checks.badge = str(issues) if issues > 0 else ""; strip_buttons.checks.queue_redraw()

## A transient message in the status strip (tool hints, confirmations).
func _say(text: String) -> void:
	status_label.remove_theme_color_override("font_color"); status_label.text = text

func set_tool(name: String) -> void:
	timeline.tool = name; tool_seg.set_index(TOOLS.find(name))
	shape_seg.visible = name == "track"
	timeline.ghost = {}; timeline.queue_redraw()
	_say({"select": "点选、拖动或框选；双击空白处放音符", "tap": "在网格上单击放音符；变红表示这里没有轨道承载", "hold": "按下后向上拖出长按的长度", "track": "拖出一个范围画轨道，形状在左侧选择"}[name])

func _open_popover(si: int, a: int, b: int) -> void:
	var s = timeline.work.shapes[si]
	var p: Vector2 = timeline.screen(s.pos(a)).lerp(timeline.screen(s.pos(b)), 0.5)
	p.y = clampf(p.y, 40.0, timeline.size.y - 40.0)
	popover.open(timeline, si, a, b, timeline.get_global_rect().position - get_global_rect().position + p)

## ------------------------------------------------------------------ transport
func seek(t: float) -> void:
	cursor = clampf(t, 0.0, maxf(0.0, doc.core.end_time)); timeline.cursor = cursor
	compare_view.cursor = cursor; compare_view.queue_redraw()
	if playing: restart_transport()
	timeline.queue_redraw()
	if drawer.visible: drawer.tick()

func restart_transport() -> void:
	playing = true; doc.core.reset_run(); doc.decorate_notes(); doc.core.skip_before(cursor); doc.core.autoplay = autoplay; doc.core.playing = test_play
	if compare_view.visible and compare_preview != null:
		compare_preview.reset_run(); compare_preview.skip_before(cursor); compare_preview.autoplay = autoplay; compare_preview.playing = test_play
	rate_audio_started = rate == 1 or cursor >= float(doc.raw.get("offset", 0))
	if rate_audio_started: audio.play(audio.music.stream, float(doc.raw.get("offset", 0)), cursor)
	else: audio.stop()
	audio.music.pitch_scale = rate
	play_b.icon_name = "pause"; play_b.queue_redraw()

func toggle_play() -> void:
	if playing: playing = false; audio.stop(); play_b.icon_name = "play"; play_b.queue_redraw()
	else: restart_transport()

func _process(dt: float) -> void:
	if hint_card != null and hint_card.visible: _place_hint()
	if doc.raw.is_empty(): return
	api.tick_jobs()
	assistant.tick()
	if playing:
		audio.sync(SU.ticks())
		cursor = audio.time_at(SU.ticks()) if rate == 1 else (audio.music.get_playback_position() + doc.raw.get("offset", 0) if audio.music.playing else cursor + dt * rate)
		if rate != 1 and not rate_audio_started and cursor >= float(doc.raw.get("offset", 0)):
			audio.play(audio.music.stream, float(doc.raw.get("offset", 0)), cursor); rate_audio_started = true
		if loop and doc.selection.to > doc.selection.from and cursor >= doc.selection.to: cursor = doc.selection.from; restart_transport()
		if test_play: doc.core.update(cursor)
		if test_play and compare_view.visible and compare_preview != null: compare_preview.update(cursor)
		var beat := int(floor((cursor - doc.timing()[0].t) / doc.position(cursor).beat_seconds))
		if metro_b.button_pressed and beat != last_beat and audio.sfx.has("wood"): audio.sfx.wood.play()
		last_beat = beat
		if tick_b.button_pressed:
			for n in doc.core.notes:
				if n.t > last_note and n.t <= cursor and n.t >= cursor - 0.1: audio.sfx.crisp.play(); break
		last_note = cursor
		if cursor >= doc.core.end_time: playing = false; audio.stop(); play_b.icon_name = "play"
		timeline.cursor = cursor; timeline.queue_redraw()
		compare_view.cursor = cursor
		if compare_view.visible: compare_view.queue_redraw()
		if drawer.visible: drawer.tick()
	time_main.text = U.clock_position(doc, cursor, timeline.grid)
	time_sub.text = U.clock_seconds(cursor)
	if Engine.get_process_frames() % 15 == 0: _update_section()
	var display_core = compare_preview if compare_view.visible and compare_preview != null else doc.core
	if not preview_card.visible: return
	var lights: Array = display_core.light_states(cursor, 1.0); var by_id := {}
	for l in lights: by_id[l.id] = l
	var frame := {"t": cursor, "fxT": cursor, "perf": cursor, "dt": dt, "lights": lights, "light_by_id": by_id, "notes": doc.core.notes, "cues": doc.core.cues, "fall": 1.3, "reach": 1.0, "tl": doc.core.tl, "chart": doc.core.chart, "phase": doc.timing()[0].t, "stats": doc.core.stats, "play": true, "space_down": doc.core.space_down, "hit_log": doc.core.hit_log, "chords": doc.core.chords, "meta": {}, "progress": cursor / doc.core.end_time, "countdown": 0, "ending": {}}
	if display_core != doc.core:
		for key in ["notes", "cues", "tl", "chart", "chords", "stats", "hit_log", "space_down"]: frame[key] = display_core.get(key)
	renderer.frame(frame, display_core.stage)

## Reserve the complete song range and every supported grid once per document
## update. Per-frame values cannot affect the row's minimum OR allocated width.
func _reserve_clock() -> void:
	if doc.raw.is_empty(): return
	var end: float = maxf(0.0, doc.core.end_time)
	var bar_digits := 1; var beat_digits := 1
	var negative := false
	for at in [0.0, end + float(doc.position(end).beat_seconds) * 2.0]:
		var p: Dictionary = doc.position(at)
		bar_digits = maxi(bar_digits, str(absi(int(p.bar))).length())
		negative = negative or int(p.bar) < 0
	for segment in doc.timing():
		bar_digits = maxi(bar_digits, str(absi(int(segment.bar))).length())
		beat_digits = maxi(beat_digits, str(int(segment.get("meter", 4))).length())
	var sample := ("-" if negative else "") + "8".repeat(bar_digits) + "." + "8".repeat(beat_digits) + "·88/88"
	U.bounded_label(time_main, ceilf(U.text_width(sample, Tokens.MD, Tokens.font("mono", 600))))
	time_main.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	var time_sample := "8".repeat(str(int(ceilf(end)) / 60).length()) + ":88.88"
	U.bounded_label(time_sub, ceilf(U.text_width(time_sample, Tokens.BODY, Tokens.font("mono"))))
	time_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	# Three gaps (including the leading 2px slot), all accounted for explicitly.
	clock.custom_minimum_size.x = 2 + time_main.custom_minimum_size.x + time_sub.custom_minimum_size.x + 20

func _update_section() -> void:
	var bar: int = int(doc.position(cursor).bar)
	var name := ""
	for s in doc.music.get("sections", []):
		if int(s.get("bar", 0)) <= bar: name = str(s.get("name", ""))
	var kiai := false
	for k in doc.raw.get("meta", {}).get("kiai", []):
		if cursor >= float(k.get("t0", 0)) and cursor < float(k.get("t1", 0)): kiai = true
	section_label.text = name; kiai_badge.text = "KIAI" if kiai else ""; kiai_badge.self_modulate.a = 1.0 if kiai else 0.0

## ------------------------------------------------------------------ keys
func _unhandled_key_input(e: InputEvent) -> void:
	if not e is InputEventKey: return
	if test_play and playing and not autoplay:
		if e.pressed and e.keycode == KEY_ESCAPE: toggle_play(); get_viewport().set_input_as_handled(); return
		if e.echo: return
		var code := KB.code_of(e)
		if KB.is_pedal(code): code = "Space"
		if code == "Space":
			if e.pressed: doc.core.press_space(cursor)
			else: doc.core.release_space(cursor)
		elif e.pressed: doc.core.press_key(code, cursor)
		else: doc.core.release_key(code, cursor)
		get_viewport().set_input_as_handled(); return
	if not e.pressed or e.echo: return
	var ctrl: bool = e.ctrl_pressed or e.meta_pressed
	if ctrl and e.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT, KEY_0, KEY_KP_0]:
		var z: float = float(settings.get("ui_zoom", 1.0))
		if e.keycode in [KEY_0, KEY_KP_0]: set_ui_zoom(0.0)
		elif e.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]: set_ui_zoom(z - 0.1)
		else: set_ui_zoom(z + 0.1)
		get_viewport().set_input_as_handled(); return
	var handled := true
	if ctrl and e.keycode == KEY_Z: report(doc.redo() if e.shift_pressed else doc.undo())
	elif ctrl and e.keycode == KEY_Y: report(doc.redo())
	elif ctrl and e.keycode == KEY_S: confirm_save()
	elif ctrl and e.keycode == KEY_B: toggle_pane("tracks")
	elif ctrl and e.keycode == KEY_L: toggle_pane("library")
	elif ctrl and e.keycode == KEY_J: toggle_pane("drawer")
	elif ctrl and e.keycode == KEY_I: toggle_pane("assistant")
	elif ctrl and e.keycode == KEY_E: toggle_pane("scripts" if e.shift_pressed else "inspector")
	elif ctrl and e.keycode == KEY_P: toggle_pane("preview")
	elif e.alt_pressed and e.keycode >= KEY_1 and e.keycode <= KEY_7: open_drawer(["camera", "track", "music", "history", "checks", "json", "versions"][e.keycode - KEY_1])
	elif ctrl or e.alt_pressed: handled = false
	elif e.keycode == KEY_SPACE: toggle_play()
	elif e.keycode == KEY_HOME: seek(0.0)
	elif e.keycode == KEY_END: seek(doc.core.end_time)
	elif e.keycode in [KEY_1, KEY_V]: set_tool("select")
	elif e.keycode in [KEY_2, KEY_N]: set_tool("tap")
	elif e.keycode in [KEY_3, KEY_H]: set_tool("hold")
	elif e.keycode in [KEY_4, KEY_T]: set_tool("track")
	elif e.keycode == KEY_SLASH and e.shift_pressed or e.unicode == 63: toggle_sheet()
	elif e.keycode == KEY_ESCAPE and new_song.visible: new_song.close()
	elif e.keycode == KEY_ESCAPE and sheet.visible: sheet.visible = false
	elif e.keycode == KEY_ESCAPE and popover.visible: popover.close()
	elif e.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		timeline.cycle_grid(-1 if e.keycode == KEY_BRACKETLEFT else 1); grid_field.set_index(Timeline.GRIDS.find(timeline.grid))
	else: handled = false
	if handled: get_viewport().set_input_as_handled()

## ------------------------------------------------------------------ assistant turn
func _turn_done(result: Dictionary) -> void:
	assistant.on_done(result)
	timeline.changed_notes = result.get("diff", {}).get("notes", [])
	turn_revision = result.get("revision", doc.revision()); timeline.changed_tracks = []; changed_fx = result.get("diff", {}).get("fx", [])
	for event_index in result.get("diff", {}).get("lights", []):
		if event_index < doc.raw.lights.size(): timeline.changed_tracks.append(int(doc.raw.lights[event_index].id))
	on_document_changed()

func clear_turn_highlights() -> void:
	assistant.turn_actions.visible = false; timeline.changed_notes = []; timeline.changed_tracks = []; changed_fx = []; turn_revision = ""; timeline.queue_redraw()

func undo_claude_turn() -> void:
	if doc.revision() != turn_revision or doc.undo_stack.is_empty() or doc.undo_stack[-1].author not in ["Agent","Claude"]:
		report({"error": "本轮之后谱面已改变；请在历史中先撤销后续编辑"}); return
	report(doc.undo()); clear_turn_highlights()

## ------------------------------------------------------------------ dialogs
func confirm_save() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "保存谱面"
	dialog.dialog_text = "保存前会先留一份带时间戳的备份。\nchart.json 只写游戏需要的字段；引擎暂不支持的形状和运动写入旁边的 chart.ext.json。"
	dialog.ok_button_text = "保存"; dialog.cancel_button_text = "取消"
	add_child(dialog); dialog.popup_centered(Vector2i(500, 180))
	dialog.confirmed.connect(func(): _saved(doc.save()); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free)

func _saved(result: Dictionary) -> void:
	report(result)
	if result.has("error"): return
	if result.get("unchanged", false): _say("没有需要保存的修改"); return
	var text := "已保存 %s/chart.json，旧版本备份为 %s" % [current_dir(), str(result.get("backup", "")).get_file()]
	if not str(result.get("sidecar", "")).is_empty(): text += "；引擎暂不支持的部分写入 chart.ext.json"
	_say(text)

func settings_dialog() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "设置"; dialog.ok_button_text = "保存设置"; dialog.cancel_button_text = "关闭"
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 8); dialog.add_child(box)
	box.add_child(_label("内置 MCP 地址", "Heading"))
	var url := LineEdit.new(); url.text = "http://127.0.0.1:%d/mcp" % server.port; url.editable = false; box.add_child(url)
	var port := W.ScrubField.new("固定端口", "", 1.0); port.min_value = 1024; port.max_value = 65535; port.set_value(float(server.port))
	port.formatter = func(v): return str(int(v))
	box.add_child(port)
	var note := _label("保存后立即生效。占用或排除端口会拒绝；Agent 页提供连接配置及访问令牌设置。\n配置文件：" + bridge.config, "Faint"); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	add_child(dialog); dialog.popup_centered(Vector2i(640, 260))
	dialog.confirmed.connect(func():
		var result = server.set_port(int(port.value))
		if result.has("error"): report(result); return
		settings.mcp_port = int(port.value)
		var f := FileAccess.open("user://charter_settings.json", FileAccess.WRITE)
		if f: f.store_string(JSON.stringify(settings)); f.close()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)

## ------------------------------------------------------------------ compare
func open_compare(refs: Array) -> void:
	var charts := []
	for ref in refs:
		var result: Dictionary = doc.version_store().read(ref)
		if result.has("error"): report(result); return
		charts.append(result.chart)
	_show_compare(refs, charts)

func _show_compare(refs: Array, charts: Array) -> void:
	compare_view.configure(doc, refs, charts); compare_view.cursor = cursor
	compare_view.visible = true; timeline.visible = false; compare_bar.visible = true
	compare_title.text = "对比 " + "、".join(refs.map(func(r): return "工作副本" if r == "working" else str(r)))

func close_compare() -> void:
	compare_view.visible = false; timeline.visible = true; compare_bar.visible = false; compare_preview = null

func focus_compare(ref: String) -> void:
	var snapshot: Dictionary = doc.version_store().read(ref) if ref != "working" else {"chart": doc.raw}
	if snapshot.has("error"): return
	compare_preview = GameCore.new(); compare_preview.load_chart(snapshot.chart)
	compare_preview.skip_before(cursor); compare_preview.autoplay = autoplay; compare_preview.playing = test_play

## ------------------------------------------------------------------ screenshots (offscreen)
func capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	# Capture within the selected original chart, including shorter demo songs.
	seek(minf(doc.seconds("44.1"), maxf(3.0, doc.core.end_time * 0.65)))
	doc.selection.from = cursor; doc.selection.to = minf(doc.core.end_time, cursor + 8.0)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var preview_image := viewport.get_texture().get_image()
	preview_image.save_png(shots.path_join("preview.png"))
	var bright := 0
	for y in 32:
		for x in 32:
			var c := preview_image.get_pixel(x * (preview_image.get_width() - 1) / 31, y * (preview_image.get_height() - 1) / 31)
			if maxf(c.r, maxf(c.g, c.b)) > 0.3: bright += 1
	print("PREVIEW_BRIGHT_SAMPLES=", bright)
	if bright == 0: push_error("Live preview rendered empty"); get_tree().quit(1); return
	var refs := []; var charts := []
	for variant in ["_demo", "_plugin_demos/motion", "_plugin_demos/shapes"]:
		var source := songs_root().path_join(variant).path_join("chart.json")
		if FileAccess.file_exists(source): refs.append(variant); charts.append(JSON.parse_string(FileAccess.get_file_as_string(source)))
	var sizes := [Vector2i(2880, 1800), Vector2i(1920, 1080)] if shots_scaled else [Vector2i(1600, 900), Vector2i(1920, 1080)]
	for dims in sizes:
		get_window().size = dims
		var tag := "-%dx%d" % [dims.x, dims.y]
		await get_tree().create_timer(0.3).timeout
		if shots_scaled: print("SCALED_SHOT window=", get_window().size, " layout=", size)
		# 1. calm default view, both themes, a few notes selected
		_shot_selection_notes()
		for theme_light in [false, true]:
			light = theme_light; apply_theme()
			await capture_frame(("light" if light else "dark") + tag)
		light = false; apply_theme()
		if shots_scaled and dims.x == 2880:
			# the right dock on each tab (three notes still selected)
			hint_card.visible = false
			panes.inspector = true; apply_panes(true)
			await capture_frame("dock-inspector" + tag)
			panes.inspector = false; panes.assistant = true; apply_panes(true)
			await capture_frame("dock-assistant" + tag)
			panes.assistant = false; apply_panes(true)
			# 歌曲设置: the 属性 page with nothing selected, then scrolled to the tempo map
			panes.assistant = false; open_song_settings(); apply_panes(true)
			await capture_frame("song-settings" + tag)
			if inspector.song_page != null:
				(inspector.get_parent() as ScrollContainer).ensure_control_visible(inspector.song_page.wave)
				await capture_frame("song-settings-timing" + tag)
			panes.inspector = false; apply_panes(true); _shot_selection_notes()
			panes.library = true; library.rescan(); apply_panes(true)
			await capture_frame("library" + tag)
			panes.library = false; apply_panes(true)
			open_new_song(); new_song.set_audio(api.audio_path()); new_song.title_edit.text = "新歌"; new_song.bpm.set_value(202.0); new_song.offset.set_value(2.991)
			await capture_frame("new-song" + tag)
			new_song.close(); new_song.audio_path = ""; new_song.title_edit.text = ""
		# 2. every pane open: tracks, camera lanes, assistant
		hint_card.visible = false
		panes.tracks = true; panes.assistant = true; panes.drawer = true; panes.tab = "camera"; apply_panes(true)
		await capture_frame("panes" + tag)
		panes.tracks = false; panes.assistant = false; panes.drawer = false; apply_panes(true)
		hint_card.visible = not _hint_seen()
		# 3. compare view with three writings on one music axis
		if charts.size() == 3 and not shots_scaled:
			_show_compare(refs, charts); panes.preview = false; apply_panes(true)
			await capture_frame("compare-3" + tag)
			close_compare(); panes.preview = true; apply_panes(true)
	# interaction states at 1920x1080 (with the 属性 tab open, so the inspector shows with them)
	hint_card.visible = false
	if shots_scaled:
		get_window().size = Vector2i(2880, 1800); await get_tree().create_timer(0.3).timeout
		await _shot_scaled_inspector()
	else:
		await _shot_interactions()
	print("CHARTER_SHOTS ", shots)
	get_tree().quit()

func _shot_selection_notes() -> void:
	var notes := []
	for i in doc.raw.notes.size():
		var t := float(doc.raw.notes[i].t)
		if t >= cursor and t < cursor + 1.0 and notes.size() < 3: notes.append(i)
	timeline.set_selection(notes, [])

func _shot_interactions() -> void:
	panes.inspector = true; apply_panes(true)
	# a refused placement: the tap tool over a key that no live track covers
	set_tool("tap")
	timeline.set_selection([], [])
	var refuse := Vector2(-1, -1)
	for k in [0, 10, 1, 9, 5]:
		for dy in [60.0, 120.0, 200.0, 280.0]:
			var p := Vector2(timeline.x_of(Ops.key_x(k)), timeline.judge_y() - dy)
			var t: float = timeline.snap_time(timeline.time_of(p.y))
			if not Ops.placement(doc, t, k, 0.0).ok: refuse = p; break
		if refuse.x >= 0: break
	if refuse.x >= 0:
		var motion := InputEventMouseMotion.new(); motion.position = refuse
		timeline.mouse = refuse; timeline._gui_input(motion)
		await capture_frame("refusal-1920x1080")
	set_tool("select"); timeline.ghost = {}
	# a context menu on a note
	var nv: Dictionary = {}
	for v in timeline.notes_view:
		if v.t > cursor + 0.3 and v.t < timeline.t_hi() - 0.3: nv = v; break
	if not nv.is_empty():
		timeline._context_menu(Vector2(timeline.x_of(nv.x), timeline.y_of(nv.t)))
		await capture_frame("context-1920x1080")
		timeline.menu.hide()
	# a selected track with its outline nodes and the segment popover
	var carrier := -1
	for id in timeline.tracks_view:
		var tv: Dictionary = timeline.tracks_view[id]
		for poly in tv.polys:
			if poly.lo < cursor + 1.0 and poly.hi > cursor + 1.5 and tv.count > 0: carrier = id
	if carrier >= 0:
		timeline.set_selection([], [carrier])
		var s = timeline.work.shapes[timeline._shape_at(carrier, cursor + 1.0)]
		var pair := []
		for i in s.size():
			var p := timeline.screen(s.pos(i))
			if p.y > 80 and p.y < timeline.size.y - 80: pair.append(i)
			if pair.size() == 2: break
		if pair.size() == 2:
			timeline.sel_nodes = [{"s": timeline.work.shapes.find(s), "n": pair[0]}, {"s": timeline.work.shapes.find(s), "n": pair[1]}]
			on_selection()
			_open_popover(timeline.sel_nodes[0].s, pair[0], pair[1])
		await capture_frame("nodes-1920x1080")
		popover.close()
	# drawer tools, one at a time
	if carrier >= 0: timeline.set_selection([], [carrier])
	for tab in ["track", "music", "history", "checks", "versions"]:
		open_drawer(tab)
		await capture_frame("drawer-" + tab + "-1920x1080")
	panes.drawer = false; apply_panes(true)
	timeline.set_selection([], [])
	panes.inspector = false; apply_panes(true)
	# the shortcut sheet
	toggle_sheet()
	await capture_frame("shortcuts-1920x1080")
	sheet.visible = false

## At the owner's screen size: a selected track with its outline nodes and the segment popover.
func _shot_scaled_inspector() -> void:
	var carrier := -1
	for id in timeline.tracks_view:
		var tv: Dictionary = timeline.tracks_view[id]
		for poly in tv.polys:
			if poly.lo < cursor + 1.0 and poly.hi > cursor + 1.5 and tv.count > 0: carrier = id
	if carrier < 0: return
	timeline.set_selection([], [carrier])
	panes.inspector = true; apply_panes(true)
	await capture_frame("track-2880x1800")
	panes.inspector = false; apply_panes(true)
	timeline.set_selection([], [])

func capture_frame(name: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image()
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _exit_tree() -> void:
	if not doc.path.is_empty(): assistant.save_conversation()

func _agent_files_dropped(paths: PackedStringArray) -> void:
	if not panes.assistant: toggle_pane("assistant")
	assistant.add_files(paths)

func confirm_agent_open(dir: String) -> void:
	if has_node("AgentOpenConfirm"): return
	var dialog = ConfirmationDialog.new(); dialog.name = "AgentOpenConfirm"; dialog.title = "Agent song switch"
	dialog.dialog_text = "放弃当前谱面的未保存修改并打开「" + dir + "」？确认后 Agent 需再用 discard:true 请求打开。"
	var revision = doc.revision()
	dialog.confirmed.connect(func(): api.open_confirmed = dir; api.open_confirmed_revision = revision; dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered()

func agent_open_song(dir: String) -> Dictionary:
	playing = false; audio.stop(); cursor = 0
	var grouped = not doc.group_before.is_empty()
	if grouped: doc.end_group()
	var result = doc.open(songs_root().path_join(dir).path_join("chart.json"))
	if grouped: doc.begin_group("Agent turn", "Agent")
	if result.has("error"): return result
	# Import stays in the same conversation, including attachment IDs and CLI session.
	audio.music.stream = audio.load_stream(api.audio_path()); _scan_songs(); library.current = dir; timeline.select_track(-1)
	_show_song_title(); seek(0); assistant.update_context(); assistant.save_conversation()
	return result

func agent_preview(at: float) -> Dictionary:
	if DisplayServer.get_name() == "headless": return {"error":"preview requires offscreen graphics rendering; headless has no pixels"}
	if doc.raw.is_empty(): return {"error":"open a song first"}
	if playing: return {"error":"pause playback before requesting a preview"}
	if not is_finite(at) or at < 0 or at > doc.core.end_time: return {"error":"preview time outside chart"}
	var previous = cursor; var old_size = viewport.size; var old_scale = preview_field.scale; var old_position = preview_field.position
	viewport.size = Vector2i(1280,720); preview_field.scale = Vector2.ONE * (1280.0/SU.LW); preview_field.position = Vector2.ZERO
	seek(at)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	seek(previous); viewport.size = old_size; preview_field.scale = old_scale; preview_field.position = old_position
	if image == null or image.is_empty(): return {"error":"preview pixels unavailable"}
	return {"_mcp_content":[{"type":"image","mimeType":"image/png","data":Marshalls.raw_to_base64(image.save_png_to_buffer())}]}
