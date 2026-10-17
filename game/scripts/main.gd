## L’âge tendre -- app shell: state machine, input routing, menus (title / songs / settings / pause / result /
## sync / line alignment), main loop.  Port of [6] UI from spotlight-rhythm/index.html.
##
## Command line (after `--`):  --mute  --autoplay  --song=<dir|demo>  --from=<t>  --screen=songs|settings
##   --result-demo=<SSS|SS|S|AAA|AA|A|BBB|BB|B|F>  (the results screen with made-up numbers)
##   --shot=<png> --shot-at=<seconds>  (saves the window to a PNG and quits; used for silent self-checks)
##   --replay=<keys.json>  plays a recorded key timeline instead of the keyboard (promo videos with Movie Maker):
##     [{"t": chart time, "code": "KeyA"|"Space"|..., "down": true|false}, ...]; each event goes through the normal
##     core.press_key / release_key / press_space / release_space at its own time; autoplay, real keys and the
##     focus-loss pause are off.  Judgement is unchanged.
extends Node

const DrawCtrl := preload("res://scripts/draw_ctrl.gd")
const LW := SU.LW
const LH := SU.LH

var R: Renderer
var core := GameCore.new()
var audio: AudioEngine
var ui: Control
var screens := {}
var state := "menu":
	set(value):
		state = value
		if _pacing_ready: _apply_frame_pacing()
var settings := {"note_size": 1.0, "hint": "move", "fall": 1.5, "offset_ms": 0, "reach": 1.0, "hit_kind": "wood", "stage": "full", "curve": "deemo",
	"layout": "ansi", "layout_manual": false, "autoplay": false, "fullscreen": true, "debug": false, "keyguard": true, "low_latency": false}
# 2026-10-17: four input polls per 60 Hz refresh, bounded CPU/GPU demand.
const LOW_LATENCY_FPS := 240
var _pacing_ready := false
var _pacing_changed_at := -10000000    # SU.ticks() of the last vsync switch: a focus blip right after it is not a real focus loss
var _normal_vsync := DisplayServer.VSYNC_ENABLED
var _normal_max_fps := 0
var _normal_accumulated_input := true
var calib := {"L": 0.0, "R": 1.0}       # 2026-10-16: left Shift .. right Shift = the screen edges
var best := {}
var _scores := PluginScores.new()
var _song_plugins: SongPluginSession
var _pending_play := {}
var _plugin_status: Label
var _plugin_identity := []
var _uses_song_plugins := false
var _result_backdrop := true
var _run_serial := 0
var _plugin_notice_base := ""
var _plugin_notice_at := 0
var meta := {}
var args := {}
var songs := []                   # [{title, artist, bpm, length, cover, preview, diffs: [...]}]
var _demo_index_notices := []
var sel_i := 0
var sel_d := 0
var end_at := 0
var end_kind := ""
var resume_at := 0
var settings_return := "menu"
var calib_return := "menu"
var sync_return := "menu"
var sel_handle := "L"
var last_ticks := 0
var started_ticks := 0
var _toast: Label
var _toast_until := 0
var _covers := {}
var _menu_items := []
var _menu_sel := 0
var _kb_down := {}
var _cards := []
var _sync_player: AudioStreamPlayer
var _sync_taps := []
var _sync_t0 := 0
var _sync_meter: Control
var _w := {}                      # named widgets
var _key_i := 0
var _rec := {"new": false, "prev": 0}     # this run's record vs best.json (for the results screen)
var _play_log = preload("res://scripts/play_log.gd").new()
var _replay := []                 # --replay: [{t, code, down}] sorted by t
var _replay_i := 0

# ================================================================ boot
func _ready() -> void:
	_normal_vsync = DisplayServer.window_get_vsync_mode()
	_normal_max_fps = Engine.max_fps
	_normal_accumulated_input = Input.use_accumulated_input
	_pacing_ready = true
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var s = SU.load_json("user://settings.json", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k in s:
			if settings.has(k) and typeof(s[k]) == typeof(settings[k]):
				settings[k] = s[k]
	var c = SU.load_json("user://calib.json", {})
	if typeof(c) == TYPE_DICTIONARY and c.has("L") and c.has("R"):
		calib = {"L": float(c.L), "R": float(c.R)}
	_scores.load_file()
	best = _scores.records
	if args.has("autoplay"): settings.autoplay = true
	if args.has("low-latency"): settings.low_latency = true # probe / one-run override; not saved
	if args.get("curve", "") in ["deemo", "accel", "linear"]: settings.curve = args.curve      # one run only (recordings); not saved
	if args.has("replay"):
		var rp = SU.load_json(args["replay"], [])
		if typeof(rp) == TYPE_ARRAY: _replay = rp
		_replay.sort_custom(func(a, b): return float(a.t) < float(b.t))
		settings.autoplay = false
		print("replay: %d key events from %s" % [_replay.size(), args["replay"]])
	KB.set_layout(settings.layout)
	DisplayServer.window_set_ime_active(false)        # no IME candidate box while the player smashes the keyboard
	_keyguard_update()

	audio = AudioEngine.new()
	audio.muted = args.has("mute")
	add_child(audio)
	R = Renderer.new()
	add_child(R)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.size = Vector2(LW, LH)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)
	_build_title(); _build_songs(); _build_settings(); _build_pause(); _build_result(); _build_sync(); _build_calib(); _build_plugin_trust()
	_toast = _label("", 13, 0.9, 6)
	_toast.position = Vector2(0, LH - 70); _toast.size = Vector2(LW, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_toast)

	_plugin_status = _label("", 13, 0.95, 1)
	_plugin_status.position = Vector2(110, LH - 125); _plugin_status.size = Vector2(LW - 220, 64)
	_plugin_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plugin_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plugin_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	ui.add_child(_plugin_status)
	_bind_core()
	if not _scores.errors.is_empty(): toast("成绩文件：" + "; ".join(_scores.errors))

	if args.has("shot"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_render_overrides()
	_apply_window()
	_apply_settings()
	_load_song_list()
	_show("Menu")
	started_ticks = SU.ticks()
	last_ticks = started_ticks
	if args.has("result-demo"):
		_demo_result.call_deferred(str(args["result-demo"]))
	elif args.has("song"):
		_test_start_song.call_deferred()
	elif args.get("screen", "") == "songs":
		_enter_songs.call_deferred()
	elif args.get("screen", "") == "settings":
		_enter_settings.call_deferred()

func _render_overrides() -> void:
	if args.has("beam"): R.BEAM_STYLE = args["beam"]
	if args.has("field"):                       # field geometry A/B checks: --field=L,R,horizon,bow,judge (fractions)
		var fv: PackedStringArray = str(args["field"]).split(",")
		if fv.size() >= 5:
			calib = {"L": float(fv[0]), "R": float(fv[1])}
			R.hy0 = float(fv[2]) * 1080.0; R.gamma0 = float(fv[3]); R.judge_y = float(fv[4]) * 1080.0
			if fv.size() >= 6: R.arc0 = float(fv[5])          # beam texture A/B checks: --beam=lane|core
	if args.has("bg"):                         # background A/B checks: --bg=<png>
		var bimg := Image.load_from_file(args["bg"])
		if bimg:
			R.bg.texture = ImageTexture.create_from_image(bimg); R.bg_scene = true
	if args.has("note-tex"):                   # texture A/B checks: --note-tex=<png>
		var img := Image.load_from_file(args["note-tex"])
		if img: R.TEX.note = ImageTexture.create_from_image(img)

func _bind_core() -> void:
	core.ripple.connect(_relay_ripple)
	core.judged.connect(_relay_judged)
	core.pressed.connect(_relay_pressed)
	core.hold_end.connect(_relay_hold_end)
	core.combo_break.connect(_relay_combo_break)
	core.cue_judged.connect(_on_cue)
	core.finished.connect(_on_finished)
	if args.has("debug"):
		audio.debug = true
		core.judged.connect(_debug_judge)
		core.cue_judged.connect(_debug_cue)

func _relay_ripple(xl: float, level: float) -> void: R.add_ripple(xl, level)
func _relay_judged(grade: String, xl: float, dt: float) -> void: R.add_judge(grade, xl, dt)
func _relay_pressed(code: String, _xl: float) -> void:
	if settings.hit_kind != "off" and code != "Space": audio.hit(settings.hit_kind)
func _relay_hold_end(note: Dictionary) -> void: R.add_hold_end(note)
func _relay_combo_break(value: int) -> void: R.add_combo_break(value)
func _debug_judge(grade: String, xl: float, dt: float) -> void:
	if grade != "PERFECT": print("[judge] %s xl=%.3f dt=%+.1fms at t=%.3f" % [grade, xl, dt * 1000.0, core.clock_now])
func _debug_cue(cue: Dictionary, grade: String) -> void:
	if grade != "PERFECT": print("[cue] %s t=%.3f now=%.3f" % [grade, cue.t, core.clock_now])

func _replace_runtime(scope: PluginRegistry = null) -> void:
	# Release renderer callbacks before disposing the owning song registry.
	if is_instance_valid(R):
		remove_child(R); R.free()
	core = GameCore.new(scope)
	R = Renderer.new(scope)
	add_child(R)
	_render_overrides()
	_bind_core()
	_apply_settings()

func _release_song_plugins(reset_runtime := true) -> void:
	if reset_runtime and _uses_song_plugins: _replace_runtime()
	if _song_plugins != null:
		_song_plugins.close()
		_song_plugins = null
	_uses_song_plugins = false

func _build_plugin_trust() -> void:
	var screen := _screen("PluginTrust")
	var panel := _center_panel(screen, 1320)
	panel.add_child(_h2("歌曲脚本信任　SCRIPT TRUST"))
	var warning := _label("这首歌包含 GDScript。脚本能读取文件、访问网络并执行任意代码。\nScripts are not sandboxed. Only allow a song pack you trust.\n拒绝后仍载入独立的声明式插件，并明确显示被禁用的功能。", 19, 0.95, 1)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(1120, 126)
	panel.add_child(warning)
	var details := _label("", 15, 0.8, 0)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(1120, 150)
	panel.add_child(details); _w.plugin_trust_details = details
	panel.add_child(_button("信任此内容并开始　ALLOW  [Y]", _plugin_trust_answer.bind(true), 16))
	panel.add_child(_button("禁用脚本并开始　DENY  [N]", _plugin_trust_answer.bind(false), 16))
	panel.add_child(_button("取消　CANCEL  [ESC]", _cancel_plugin_play, 16))

func _plugin_trust_answer(allowed: bool) -> void:
	if state != "plugin_trust" or _pending_play.is_empty(): return
	var session: SongPluginSession = _pending_play.session
	if not session.remember_trust(allowed):
		var details: Array = session.report.get("errors", []).duplicate()
		if details.is_empty(): details.append("歌曲包已变化或信任记录无法保存，请重新选择。 / Pack changed or trust could not be saved.")
		_plugin_load_error(details)
		return
	_begin_prepared_song()

func _cancel_plugin_play() -> void:
	if not _pending_play.is_empty():
		_pending_play.session.close()
		_pending_play.clear()
	_plugin_status.text = ""
	_enter_songs()

func _plugin_load_error(errors: Array) -> void:
	if not _pending_play.is_empty():
		_pending_play.session.close()
		_pending_play.clear()
	state = "songs"
	_show("Songs")
	_w.ss_note.text = "插件 / Plugin: " + "; ".join(errors)
	_plugin_status.text = _w.ss_note.text
	print("PLUGIN START BLOCKED: ", "; ".join(errors))

func _plugin_preview(diff: Dictionary) -> Dictionary:
	var raw = ChartLib.demo() if diff.get("demo", false) else SU.load_json(songs_dir().path_join(str(diff.dir)).path_join("chart.json"))
	if typeof(raw) != TYPE_DICTIONARY: return {"errors": ["Cannot read chart.json"], "notices": [], "identity": PluginScores.standard_identity()}
	var probe := SongPluginSession.new()
	var report := probe.prepare(songs_dir().path_join(str(diff.dir)), raw, str(diff.dir)).duplicate(true)
	probe.close()
	return report

func _test_start_song() -> void:
	var dir: String = args.song
	for i in songs.size():
		for j in songs[i].diffs.size():
			if songs[i].diffs[j].dir == dir:
				sel_i = i; sel_d = j
				_play_selected(float(args.get("from", "0")))
				return
	if not _test_working_copy(dir):
		push_error("song not found: " + dir)

# ================================================================ persistence / paths
func _save_settings() -> void:
	SU.save_json("user://settings.json", settings)

func songs_dir() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("songs")
	if OS.has_feature("template") or DirAccess.dir_exists_absolute(beside):
		return beside
	return ProjectSettings.globalize_path("res://").path_join("../songs").simplify_path()

func _apply_window() -> void:
	if args.has("shot") or args.has("windowed"):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_settings() -> void:
	_apply_frame_pacing()
	KB.set_layout(settings.layout)
	core.stage.mode = settings.stage
	core.autoplay = settings.autoplay
	R.curve = settings.curve
	R.accel_k = float(settings.get("accel_k", 1.7))
	R.persp_k = _persp_k(float(settings.get("persp_deg", 35.0)))
	R.note_scale = 1.5 * settings.note_size
	R.hint_mode = "off"                         # 2026-10-16: no letters; faint key guides on the track instead
	R.line_l = calib.L * LW
	R.line_r = calib.L * LW + (calib.R - calib.L) * LW * 15.0 / KB.span()

func _apply_frame_pacing() -> void:
	if not _pacing_ready: return
	# paused counts as play (owner, 2026-10-18): switching vsync on every Esc made fullscreen flicker / lose focus,
	# which re-paused the song right after resuming. The switch now happens once at the start and end of a play.
	var low: bool = settings.low_latency and state in ["playing", "resuming", "paused"]
	var vsync: int = DisplayServer.VSYNC_DISABLED if low else _normal_vsync
	if DisplayServer.window_get_vsync_mode() != vsync:
		DisplayServer.window_set_vsync_mode(vsync)
		_pacing_changed_at = SU.ticks()
	Engine.max_fps = LOW_LATENCY_FPS if low else _normal_max_fps
	Input.use_accumulated_input = false if low else _normal_accumulated_input

# ================================================================ theme / widget helpers
func _box(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(0)
	sb.content_margin_left = 26; sb.content_margin_right = 26; sb.content_margin_top = 10; sb.content_margin_bottom = 10
	return sb

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Fonts.spaced(Fonts.ui(), 3)
	t.default_font_size = 15
	t.set_stylebox("normal", "Button", _box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.35)))
	t.set_stylebox("hover", "Button", _box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.7)))
	t.set_stylebox("pressed", "Button", _box(Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.9)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(1, 1, 1, 0.92))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", Color(1, 1, 1, 0.92))
	t.set_stylebox("panel", "PanelContainer", _panel_box())
	t.set_stylebox("slider", "HSlider", _line_box())
	t.set_icon("grabber", "HSlider", _dot(12))
	t.set_icon("grabber_highlight", "HSlider", _dot(14))
	t.set_stylebox("grabber_area", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("grabber_area_highlight", "HSlider", StyleBoxEmpty.new())
	return t

func _panel_box() -> StyleBoxFlat:
	var sb := _box(Color(0, 0, 0, 0.62), Color(1, 1, 1, 0.18))
	sb.set_content_margin_all(48)
	sb.content_margin_left = 72; sb.content_margin_right = 72
	return sb

func _line_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.45)
	sb.content_margin_top = 0.5; sb.content_margin_bottom = 0.5
	return sb

func _dot(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(r - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _label(t: String, size: int, alpha := 0.92, spacing := 3, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", Fonts.spaced(font if font else Fonts.ui(), spacing))
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, alpha)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(t: String, cb: Callable, size := 15) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	return b

func _screen(name: String, mouse := true) -> Control:
	var s := Control.new()
	s.size = Vector2(LW, LH)
	s.mouse_filter = Control.MOUSE_FILTER_PASS if mouse else Control.MOUSE_FILTER_IGNORE
	s.visible = false
	ui.add_child(s)
	screens[name] = s
	return s

func _center_panel(parent: Control, min_w: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.size = Vector2(LW, LH)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size.x = min_w
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	return v

func _h2(t: String) -> Label:
	var l := _label(t, 34, 1.0, 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _show(name: String) -> void:
	for k in screens:
		screens[k].visible = k == name
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if name == "" and state in ["playing", "resuming", "loading"] else Input.MOUSE_MODE_VISIBLE

func toast(msg: String, sec := 1.8) -> void:
	_toast.text = msg
	_toast_until = SU.ticks() + int(sec * 1e6)

# ================================================================ title
func _build_title() -> void:
	var s := _screen("Menu")
	var logo := _label("L’âge tendre", 104, 1.0, 12, Fonts.title())
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.position = Vector2(0, 330); logo.size = Vector2(LW, 120)
	s.add_child(logo)
	var items := [["歌曲", "SONGS", "songs"], ["设置", "SETTINGS", "settings"], ["退出", "EXIT", "exit"]]
	for i in items.size():
		var it := Control.new()
		it.position = Vector2(LW / 2.0 - 160, 540 + i * 116); it.size = Vector2(320, 90)
		var zh := _label(items[i][0], 34, 1.0, 20)
		zh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; zh.size = Vector2(320, 50)
		var en := _label(items[i][1], 12, 0.7, 7)
		en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; en.position.y = 52; en.size = Vector2(320, 20)
		var l1 := ColorRect.new(); l1.color = Color.WHITE; l1.size = Vector2(34, 1); l1.position = Vector2(28, 25)
		var l2 := ColorRect.new(); l2.color = Color.WHITE; l2.size = Vector2(34, 1); l2.position = Vector2(258, 25)
		for n in [zh, en, l1, l2]:
			it.add_child(n)
		var idx: int = i
		it.mouse_entered.connect(func(): _menu_select(idx))
		it.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _menu_go(items[idx][2]))
		s.add_child(it)
		_menu_items.append([it, l1, l2, items[i][2]])
	_menu_select(0)

func _menu_select(i: int) -> void:
	_menu_sel = i
	for k in _menu_items.size():
		var on: bool = k == i
		_menu_items[k][0].modulate = Color(1, 1, 1, 1.0 if on else 0.34)
		_menu_items[k][1].visible = on
		_menu_items[k][2].visible = on

func _menu_go(where: String) -> void:
	match where:
		"songs": _enter_songs()
		"settings": _enter_settings()
		"exit": get_tree().quit()

# ================================================================ song select (maimai / CHUNITHM style)
func _load_song_list() -> void:
	_demo_index_notices.clear()
	songs = [{"title": "DEMO", "artist": "L’âge tendre", "bpm": 120.0, "length": 64.0, "cover": songs_dir().path_join("_covers/demo.jpg"),
		"preview": -1.0, "diffs": [{"dir": "demo", "version": "TUTORIAL", "level": 3, "notes": 199, "demo": true}]}]
	var idx = SU.load_json(songs_dir().path_join("index.json"), [])
	if typeof(idx) != TYPE_ARRAY:
		idx = []
	var sets := {}
	var order := []
	for e in idx:
		var key := str(e.get("set", e.get("title", "")))
		if not sets.has(key):
			sets[key] = {"title": e.title, "artist": e.artist, "bpm": float(e.bpm), "length": float(e.length),
				"cover": songs_dir().path_join(str(e.cover)) if e.get("cover") else "", "preview": float(e.get("preview", -1.0)), "diffs": []}
			order.append(key)
		sets[key].diffs.append(e)
	for k in order:
		sets[k].diffs.sort_custom(func(a, b): return a.get("level", 0) < b.get("level", 0))
		songs.append(sets[k])
	_append_plugin_demos()
	_append_fan_charts()

func _append_fan_charts() -> void:
	var discovered := FanChartLibrary.discover(songs_dir())
	for notice in discovered.notices: print("Fan-made charts: ", notice)
	for row in discovered.entries:
		songs.append({"title": row.title, "artist": row.artist, "bpm": float(row.bpm), "length": float(row.length),
			"cover": songs_dir().path_join(row.cover) if not str(row.cover).is_empty() else "", "preview": float(row.preview),
			"group": FanChartLibrary.GROUP, "diffs": [row]})

func _demo_index_notice(message: String) -> void:
	if _demo_index_notices.size() < 8:
		_demo_index_notices.append("插件演示 / Plugin demos: " + message)

func _demo_text(value: Variant, empty := false) -> bool:
	if not value is String or value.length() > 256 or (not empty and value.strip_edges().is_empty()): return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return false
	return true

func _demo_file_safe(relative: String) -> bool:
	if not PluginPack.safe_relative(relative): return false
	for part in relative.split("/", true):
		if not _demo_text(part): return false
	# Reuse the tested POSIX/drive/UNC and symlink-ancestry inspection contract.
	return PluginPack.file_path(songs_dir(), relative).errors.is_empty()

func _demo_number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _demo_entry_valid(row: Dictionary) -> bool:
	for field in ["dir", "title", "artist", "version"]:
		if not _demo_text(row.get(field)): return false
	if not _demo_text(row.get("set", row.title)): return false
	var dir: String = row.dir
	var parts := dir.split("/", true)
	if parts.size() != 2 or parts[0] != "_plugin_demos" or parts[1] in ["", ".", ".."] or not _demo_file_safe(dir.path_join("chart.json")): return false
	var audio = row.get("audio", "audio.mp3")
	if not _demo_text(audio) or "/" in audio or not _demo_file_safe(dir.path_join(audio)): return false
	var cover = row.get("cover", "")
	if not _demo_text(cover, true) or (not cover.is_empty() and not _demo_file_safe(cover)): return false
	if not _demo_number(row.get("bpm"), 0.001, 1000.0) or not _demo_number(row.get("length"), 0.001, 86400.0): return false
	if not _demo_number(row.get("preview", -1.0), -1.0, float(row.length)): return false
	if not _demo_number(row.get("level", 1), 0.0, 100.0) or not _demo_number(row.get("notes", 0), 0.0, 1000000.0): return false
	return true

func _append_plugin_demos() -> void:
	var path := songs_dir().path_join("_plugin_demos/index.json")
	if not FileAccess.file_exists(path): return
	if not _demo_file_safe("_plugin_demos/index.json"):
		_demo_index_notice("unsafe index path; ignored"); return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		_demo_index_notice("index unreadable or exceeds 1 MiB; ignored"); return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Array or parser.data.size() > 512:
		_demo_index_notice("expected at most 512 JSON entries; ignored"); return
	var seen := {}; var groups := {}; var order := []
	for song in songs:
		for diff in song.diffs: seen[str(diff.dir).to_lower()] = true
	for i in parser.data.size():
		var row = parser.data[i]
		if not row is Dictionary or not _demo_entry_valid(row):
			_demo_index_notice("invalid entry %d; ignored" % [i + 1]); continue
		var key: String = str(row.get("set", row.title))
		var signature := [row.title, row.artist, float(row.bpm), float(row.length), row.get("cover", ""), float(row.get("preview", -1.0))]
		if seen.has(str(row.dir).to_lower()) or (groups.has(key) and groups[key].signature != signature):
			_demo_index_notice("duplicate directory or conflicting group at entry %d; ignored" % [i + 1]); continue
		seen[str(row.dir).to_lower()] = true
		if not groups.has(key):
			groups[key] = {"title": row.title, "artist": row.artist, "bpm": float(row.bpm), "length": float(row.length),
				"cover": songs_dir().path_join(str(row.cover)) if row.get("cover") else "", "preview": float(row.get("preview", -1.0)), "diffs": [], "signature": signature}
			order.append(key)
		groups[key].diffs.append(row.duplicate(true))
	for key in order:
		groups[key].erase("signature")
		groups[key].diffs.sort_custom(func(a, b): return a.get("level", 0) < b.get("level", 0))
		songs.append(groups[key])

func _cover(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path): return null
	if not _covers.has(path):
		var img := Image.load_from_file(path)
		_covers[path] = ImageTexture.create_from_image(img) if img else null
	return _covers[path]

func _tier(lv: int) -> String:
	if lv >= 14: return "BEYOND"
	if lv >= 11: return "MASTER"
	if lv >= 8: return "EXPERT"
	if lv >= 5: return "ADVANCED"
	return "BASIC"

func _build_songs() -> void:
	var s := _screen("Songs")
	var bgr := TextureRect.new()
	bgr.position = Vector2(-60, -60); bgr.size = Vector2(LW + 120, LH + 120)
	bgr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgr.material = ShaderMaterial.new()
	bgr.material.shader = load("res://assets/shaders/cover_blur.gdshader")
	bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(bgr)
	_w.ss_bg = bgr
	var shade := ColorRect.new()
	shade.size = Vector2(LW, LH); shade.color = Color(0, 0, 0, 0.35); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(shade)
	var head := _label("SONGS", 22, 1.0, 4)
	_w.ss_group = head
	head.position = Vector2(60, 40)
	s.add_child(head)
	var cnt := _label("", 14, 0.6, 6)
	cnt.position = Vector2(LW - 360, 46); cnt.size = Vector2(300, 24); cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.add_child(cnt)
	_w.ss_count = cnt
	var strip := Control.new()
	strip.size = Vector2(LW, LH); strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(strip)
	_w.ss_strip = strip
	var title := _label("", 40, 1.0, 4)
	title.position = Vector2(200, 632); title.size = Vector2(LW - 400, 56); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.add_child(title)
	var artist := _label("", 17, 0.72, 5)
	artist.position = Vector2(0, 690); artist.size = Vector2(LW, 28); artist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(artist)
	var mt := _label("", 13, 0.45, 5, Fonts.hud())
	mt.position = Vector2(0, 722); mt.size = Vector2(LW, 22); mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(mt)
	_w.ss_title = title; _w.ss_artist = artist; _w.ss_meta = mt
	var diffs := HFlowContainer.new()
	diffs.position = Vector2(210, 768); diffs.size = Vector2(LW - 420, 220)
	diffs.alignment = FlowContainer.ALIGNMENT_CENTER
	diffs.add_theme_constant_override("h_separation", 10); diffs.add_theme_constant_override("v_separation", 10)
	s.add_child(diffs)
	_w.ss_diffs = diffs
	var play := _button("开始　PLAY", _play_selected.bind(0.0), 15)
	play.position = Vector2(LW / 2.0 - 120, 900); play.size = Vector2(240, 48)
	s.add_child(play)
	_w.ss_play = play
	var note := _label("", 13, 0.55, 3)
	note.position = Vector2(80, 956); note.size = Vector2(LW - 160, 52); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.add_child(note)
	_w.ss_note = note
	var keys := _label("← →　选曲　　　↑ ↓　难度　　　ENTER　开始　　　ESC　返回", 11, 0.32, 5)
	keys.position = Vector2(0, LH - 44); keys.size = Vector2(LW, 20); keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_child(keys)
	s.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: _song_move(1)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_UP: _song_move(-1))

func _enter_songs() -> void:
	state = "songs"
	R.clear_fx()
	_show("Songs")
	if _cards.size() != songs.size(): _build_cards()
	_song_select(sel_i, true)

func _build_cards() -> void:
	for c in _cards: c.queue_free()
	_cards.clear()
	for k in songs.size():
		var sg: Dictionary = songs[k]
		var card := Panel.new()
		card.size = Vector2(440, 440)
		card.pivot_offset = Vector2(220, 220)
		card.position = Vector2(LW / 2.0 - 220, 360 - 220)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.04, 0.04); sb.border_color = Color(1, 1, 1, 0.25); sb.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", sb)
		var tr := TextureRect.new()
		tr.texture = _cover(sg.cover)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(1, 1); tr.size = Vector2(438, 438)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tr)
		var badge := ColorRect.new()
		badge.color = Color.WHITE; badge.size = Vector2(104, 74); badge.position = Vector2(336, 366)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bt := _label("", 11, 1.0, 4); bt.add_theme_color_override("font_color", Color.BLACK)
		bt.position = Vector2(0, 6); bt.size = Vector2(104, 16); bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var bl := _label("", 46, 1.0, 0, Fonts.hud()); bl.add_theme_color_override("font_color", Color.BLACK)
		bl.position = Vector2(0, 20); bl.size = Vector2(104, 54); bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(bt); badge.add_child(bl)
		card.add_child(badge)
		var nm := _label(sg.title, 19, 0.75, 3)
		nm.position = Vector2(-40, 452); nm.size = Vector2(520, 30); nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.add_child(nm)
		var idx: int = k
		card.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if idx == sel_i: _play_selected(0.0)
			else: _song_select(idx))
		_w.ss_strip.add_child(card)
		_cards.append({"card": card, "img": tr, "badge": badge, "bt": bt, "bl": bl, "nm": nm, "sb": sb})

func _song_select(i: int, instant := false) -> void:
	sel_i = posmod(i, songs.size())
	for k in _cards.size():
		var d := k - sel_i
		var a := absi(d)
		var dx := 0.0 if d == 0 else signf(d) * (392.0 + (a - 1) * 292.0)
		var sc := 1.0 if d == 0 else 0.56
		var c: Dictionary = _cards[k]
		var target := Vector2(LW / 2.0 - 220 + dx, 360 - 220)
		var alpha: float = [1.0, 0.78, 0.45, 0.2][a] if a < 4 else 0.0
		c.card.z_index = 10 - mini(a, 10)
		c.card.mouse_filter = Control.MOUSE_FILTER_STOP if a <= 3 else Control.MOUSE_FILTER_IGNORE
		c.badge.visible = d == 0
		c.nm.visible = d != 0
		c.sb.border_color = Color(1, 1, 1, 0.95 if d == 0 else 0.22)
		c.img.modulate = Color(1, 1, 1) if d == 0 else Color(0.75, 0.75, 0.75)
		if instant:
			c.card.position = target; c.card.scale = Vector2(sc, sc); c.card.modulate.a = alpha
		else:
			var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c.card, "position", target, 0.34)
			tw.tween_property(c.card, "scale", Vector2(sc, sc), 0.34)
			tw.tween_property(c.card, "modulate:a", alpha, 0.34)
	_song_info()
	audio.preview_stop()
	var sg: Dictionary = songs[sel_i]
	var my := sel_i
	get_tree().create_timer(0.45).timeout.connect(func():
		if state == "songs" and sel_i == my and not sg.diffs[0].get("demo", false):
			var df: Dictionary = sg.diffs[0]
			audio.preview_play(songs_dir().path_join(df.dir).path_join(str(df.get("audio", "audio.mp3"))), sg.preview if sg.preview >= 0.0 else 30.0))

func _song_move(d: int) -> void:
	if state == "songs": _song_select(sel_i + d)

func _song_diff(d: int) -> void:
	var n: int = songs[sel_i].diffs.size()
	sel_d = posmod(sel_d + d, n)
	_song_info()

func _song_info() -> void:
	if state == "songs" and is_instance_valid(_plugin_status): _plugin_status.text = ""
	var sg: Dictionary = songs[sel_i]
	sel_d = mini(sel_d, sg.diffs.size() - 1)
	var df: Dictionary = sg.diffs[sel_d]
	_w.ss_bg.texture = _cover(sg.cover)
	_w.ss_group.text = str(sg.get("group", "SONGS"))
	_w.ss_count.text = "%02d / %02d" % [sel_i + 1, songs.size()]
	_w.ss_title.text = sg.title
	_w.ss_artist.text = sg.artist
	_w.ss_meta.text = "BPM %d   ·   %d:%02d   ·   %s NOTES" % [int(round(sg.bpm)), int(sg.length) / 60, int(sg.length) % 60, str(df.get("notes", "-"))]
	for ch in _w.ss_diffs.get_children(): ch.queue_free()
	for k in sg.diffs.size():
		var x: Dictionary = sg.diffs[k]
		var on: bool = k == sel_d
		var chip := Button.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(168, 100)
		var sbn := StyleBoxFlat.new()
		sbn.bg_color = Color.WHITE if on else Color(0, 0, 0, 0)
		sbn.border_color = Color(1, 1, 1, 1.0 if on else 0.28); sbn.set_border_width_all(1)
		for st in ["normal", "hover", "pressed"]:
			chip.add_theme_stylebox_override(st, sbn)
		chip.modulate.a = 1.0 if on else 0.62
		var col := Color.BLACK if on else Color.WHITE
		var preview := _plugin_preview(x)
		var b := _scores.get_record(str(x.dir), preview.get("identity", PluginScores.standard_identity()))
		var lines := [[_tier(int(x.get("level", 1))), 10, 4, 10, Fonts.ui()], [str(x.get("level", "?")), 30, 0, 26, Fonts.hud()],
			[str(x.version), 11, 1, 64, Fonts.ui()], [("%07d" % int(b.score)) + ("　FC" if b.get("fc", false) else "") if b else "", 10, 2, 80, Fonts.hud()]]
		for ln in lines:
			var l := _label(ln[0], ln[1], 1.0, ln[2], ln[4])
			l.add_theme_color_override("font_color", col)
			l.position = Vector2(14, ln[3]); l.size = Vector2(142, ln[1] + 8)
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			chip.add_child(l)
		var kk: int = k
		chip.pressed.connect(func(): sel_d = kk; _song_info())
		_w.ss_diffs.add_child(chip)
	var c: Dictionary = _cards[sel_i] if sel_i < _cards.size() else {}
	if not c.is_empty():
		c.bt.text = _tier(int(df.get("level", 1)))
		c.bl.text = str(df.get("level", "?"))

	var report := _plugin_preview(df)
	var messages: Array = report.get("errors", []).duplicate()
	messages.append_array(report.get("notices", []))
	messages.append_array(_demo_index_notices)
	if report.get("requires_trust", false): messages.append("开局将询问信任脚本 / Script trust required at start")
	_w.ss_note.text = "; ".join(messages)
	_w.ss_play.disabled = not report.get("errors", []).is_empty()

func _play_selected(from_t := 0.0) -> void:
	if state != "songs" and state != "menu": return
	var sg: Dictionary = songs[sel_i]
	var df: Dictionary = sg.diffs[sel_d]
	audio.preview_stop()
	var raw = ChartLib.demo() if df.get("demo", false) else SU.load_json(songs_dir().path_join(str(df.dir)).path_join("chart.json"))
	var stream := _stream_for_current()
	if typeof(raw) != TYPE_DICTIONARY or stream == null:
		_plugin_load_error(["载入失败 / Cannot load chart/audio: " + str(df.dir)]); return
	var session := SongPluginSession.new()
	var report := session.prepare(songs_dir().path_join(str(df.dir)), raw, str(df.dir))
	_pending_play = {"session": session, "raw": raw, "from_t": from_t,
		"meta": {"title": sg.title, "artist": sg.artist, "version": df.version, "dir": df.dir, "level": int(df.get("level", 0))}}
	if not report.errors.is_empty(): _plugin_load_error(report.errors); return
	if report.requires_trust:
		state = "plugin_trust"
		_w.plugin_trust_details.text = "脚本 / Scripts: " + ", ".join(report.script_ids) + "\nSHA-256: " + str(report.content_hash) + "\n此选择仅适用于当前内容。内容改变后会再次询问。"
		_show("PluginTrust")
		return
	_begin_prepared_song()

func _begin_prepared_song() -> void:
	if _pending_play.is_empty(): return
	var pending := _pending_play.duplicate()
	var session: SongPluginSession = pending.session
	var result := session.open()
	if not result.errors.is_empty(): _plugin_load_error(result.errors); return
	_finish_play_log("replace_song")
	_release_song_plugins()
	_uses_song_plugins = not pending.raw.get("plugins", []).is_empty()
	# Old charts use the immutable standard scope, allowing their result backdrop
	# to continue after the empty song session closes without retaining a plugin.
	_replace_runtime(session.registry if _uses_song_plugins else null)
	_song_plugins = session
	_plugin_identity = session.identity.duplicate()
	if not core.load_chart(session.chart_data):
		_pending_play.clear(); _release_song_plugins()
		_plugin_load_error(["谱面校验失败 / Chart validation failed"]); return
	meta = pending.meta
	meta["plugins"] = _plugin_identity.duplicate()
	meta["score_key"] = session.score_key
	_plugin_status.text = "; ".join(result.get("disabled", []))
	if not _plugin_status.text.is_empty():
		_plugin_status.text = "已禁用 / DISABLED: " + _plugin_status.text
		print("PLUGIN DEGRADED: ", _plugin_status.text)
	_plugin_notice_base = _plugin_status.text
	_plugin_notice_at = 0
	_pending_play.clear()
	_start(float(pending.from_t))

func _start(from_t := 0.0) -> void:
	_finish_play_log("restart")
	_run_serial += 1
	_result_backdrop = true
	end_at = 0; end_kind = ""; resume_at = 0
	_apply_settings()
	core.reset_run()
	_play_log.begin(str(meta.get("dir", "demo")), settings, from_t, _plugin_identity)
	if from_t > 0.0: core.skip_before(from_t - 0.05)
	R.clear_fx()
	state = "playing"
	core.playing = true
	_show("")
	audio.play(_stream_for_current(), core.chart.offset, from_t)

func _stream_for_current() -> AudioStream:
	var df: Dictionary = songs[sel_i].diffs[sel_d]
	if df.get("demo", false):
		return audio.load_stream(songs_dir().path_join("_demo/audio.wav"))
	return audio.load_stream(songs_dir().path_join(df.dir).path_join(str(df.get("audio", "audio.mp3"))))

# ================================================================ settings
func _build_settings() -> void:
	var s := _screen("Settings")
	var v := _center_panel(s, 1380)
	v.add_child(_h2("SETTINGS"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 72)
	v.add_child(cols)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 600; left.add_theme_constant_override("separation", 10)
	var right := VBoxContainer.new(); right.custom_minimum_size.x = 600; right.add_theme_constant_override("separation", 14)
	cols.add_child(left); cols.add_child(right)
	left.add_child(_col_head("游玩　PLAY"))
	_w.fall = _slider_row(left, "下落时间　FALL", 0.6, 3.5, 0.05, func(x): settings.fall = x; _sync_settings_ui(); _save_settings())
	_w.curve = _toggle_row(left, "下落方式　APPROACH", func(): settings.curve = {"deemo": "accel", "accel": "linear", "linear": "deemo"}[settings.curve]; _after_change())
	# one row that follows the curve (owner, 2026-10-18): 透视 -> perspective angle, 加速 -> acceleration; hidden for 匀速
	_w.curve_amt = _slider_row(left, "透视角度　ANGLE", 0.0, 1.0, 0.01, func(x):
		if settings.curve == "accel": settings.accel_k = snappedf(lerpf(1.1, 3.5, x), 0.05)
		elif settings.curve == "deemo": settings.persp_deg = roundf(lerpf(15.0, 75.0, x))
		_after_change())
	_w.reach = _slider_row(left, "轨道长度　REACH", 0.25, 1.0, 0.05, func(x): settings.reach = x; _sync_settings_ui(); _save_settings())
	_w.offset = _slider_row(left, "音频偏移　OFFSET", -200, 200, 1, func(x): settings.offset_ms = int(x); _sync_settings_ui(); _save_settings())
	_w.size = _slider_row(left, "按键大小　NOTE SIZE", 0.5, 1.5, 0.05, func(x): settings.note_size = x; _after_change())
	_w.hit = _toggle_row(left, "击键音　HIT SOUND", func():
		settings.hit_kind = {"wood": "deep", "deep": "crisp", "crisp": "off", "off": "wood"}[settings.hit_kind]
		_after_change()
		if settings.hit_kind != "off": audio.hit(settings.hit_kind))
	_w.stage = _toggle_row(left, "演出强度　STAGE FX", func(): settings.stage = {"full": "reduced", "reduced": "off", "off": "full"}[settings.stage]; _after_change())
	_w.auto = _toggle_row(left, "AUTOPLAY", func(): settings.autoplay = not settings.autoplay; _after_change())
	_w.fs = _toggle_row(left, "显示　DISPLAY", func(): settings.fullscreen = not settings.fullscreen; _apply_window(); _after_change())
	_w.kg = _toggle_row(left, "系统键　SYSTEM KEYS", func(): settings.keyguard = not settings.keyguard; _keyguard_update(); _after_change())
	_w.low_latency = _toggle_row(left, "低延迟　LOW LATENCY", func(): settings.low_latency = not settings.low_latency; _after_change())
	right.add_child(_col_head("键盘　KEYBOARD"))
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 0)
	right.add_child(seg)
	_w.seg = {}
	for pair in [["ansi", "ANSI　美式"], ["ansi65", "ANSI 短右Shift"], ["iso", "ISO　欧式"], ["jis", "JIS　日式"]]:
		var nm: String = pair[0]
		var b := _button(pair[1], func(): settings.layout = nm; settings.layout_manual = true; _after_change(), 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.add_child(b)
		_w.seg[nm] = b
	var kv := Control.new()
	kv.set_script(DrawCtrl)
	kv.custom_minimum_size = Vector2(600, 250)
	kv.painter = _paint_kb_view
	right.add_child(kv)
	_w.kbview = kv
	var hint := _label("", 12, 0.55, 2)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(600, 44)
	right.add_child(hint)
	_w.kbhint = hint
	var rb := HBoxContainer.new(); rb.add_theme_constant_override("separation", 18)
	rb.add_child(_button("判定线对齐　ALIGN", _enter_calib))
	rb.add_child(_button("延迟校准　SYNC", _enter_sync))
	right.add_child(rb)
	var back := CenterContainer.new()
	back.add_child(_button("返回　BACK", _exit_settings))
	v.add_child(back)

func _col_head(t: String) -> Control:
	var v := VBoxContainer.new()
	v.add_child(_label(t, 12, 0.5, 6))
	var line := ColorRect.new(); line.color = Color(1, 1, 1, 0.15); line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)
	return v

func _slider_row(parent: Control, label: String, lo: float, hi: float, step: float, cb: Callable) -> Dictionary:
	var h := HBoxContainer.new(); h.custom_minimum_size.y = 46; h.add_theme_constant_override("separation", 20)
	var l := _label(label, 14, 0.8, 3); l.custom_minimum_size.x = 210
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sl := HSlider.new(); sl.min_value = lo; sl.max_value = hi; sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	var val := _label("", 14, 0.9, 2, Fonts.hud()); val.custom_minimum_size.x = 200
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l); h.add_child(sl); h.add_child(val)
	parent.add_child(h)
	sl.value_changed.connect(func(x): if not sl.has_meta("syncing"): cb.call(x))
	return {"slider": sl, "val": val}

func _toggle_row(parent: Control, label: String, cb: Callable) -> Button:
	var h := HBoxContainer.new(); h.custom_minimum_size.y = 46
	var l := _label(label, 14, 0.8, 3); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var b := _button("", cb, 13); b.custom_minimum_size = Vector2(150, 36)
	h.add_child(l); h.add_child(b)
	parent.add_child(h)
	return b

func _set_toggle(b: Button, txt: String, on: bool) -> void:
	b.text = txt
	var sb := _box(Color(1, 1, 1, 0.9) if on else Color(0, 0, 0, 0), Color(1, 1, 1, 0.9 if on else 0.35))
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.BLACK if on else Color.WHITE)

func _set_slider(w: Dictionary, v: float, txt: String) -> void:
	w.slider.set_meta("syncing", true)
	w.slider.value = v
	w.slider.remove_meta("syncing")
	w.val.text = txt

## camera angle -> depth factor of the perspective fall: 35 deg keeps the original look (k = 9, far end at 1/10 size);
## a steeper camera (bigger angle) flattens the perspective, a lower one deepens it
static func _persp_k(deg: float) -> float:
	return 9.0 * tan(deg_to_rad(35.0)) / tan(deg_to_rad(clampf(deg, 10.0, 80.0)))

func _deemo_speed(fall: float) -> float:
	var M := [8.91, 7, 6.39, 5.86, 5.86, 5.86, 6.1, 6.6, 6.8, 7.45, 8, 9, 10, 11.1, 13, 14, 15, 17.4]
	var t_of := func(sp: float) -> float:
		var i := clampf((sp - 1.0) / 0.5, 0.0, M.size() - 1.0)
		var a := int(floor(i))
		var b := mini(a + 1, M.size() - 1)
		return 70.98 / ((M[a] + (M[b] - M[a]) * (i - a)) * sp)
	var lo := 1.0
	var hi := 9.5
	for k in 40:
		var m := (lo + hi) / 2.0
		if t_of.call(m) > fall: lo = m
		else: hi = m
	return (lo + hi) / 2.0

func _after_change() -> void:
	_apply_settings()
	_sync_settings_ui()
	_save_settings()

func _sync_settings_ui() -> void:
	_set_slider(_w.fall, settings.fall, "%.2f s" % settings.fall + ("　≈ Deemo %.1f" % _deemo_speed(settings.fall) if settings.curve == "deemo" else ""))
	_set_slider(_w.reach, settings.reach, "%d %%" % int(round(settings.reach * 100)))
	_set_slider(_w.offset, settings.offset_ms, ("+" if settings.offset_ms > 0 else "") + "%d ms" % settings.offset_ms)
	_set_slider(_w.size, settings.note_size, "%.2f x" % settings.note_size)
	_set_toggle(_w.curve, {"deemo": "透视 DEEMO", "accel": "加速 ACCEL", "linear": "匀速 LINEAR"}[settings.curve], settings.curve == "deemo")
	var amt_row: Control = _w.curve_amt.slider.get_parent()
	amt_row.visible = settings.curve != "linear"
	var amt_label := amt_row.get_child(0) as Label
	if settings.curve == "accel":
		var ak := float(settings.get("accel_k", 1.7))
		amt_label.text = "加速度　ACCEL"
		_set_slider(_w.curve_amt, inverse_lerp(1.1, 3.5, ak), "x%.2f" % ak + ("　默认" if is_equal_approx(ak, 1.7) else ""))
	elif settings.curve == "deemo":
		var deg := float(settings.get("persp_deg", 35.0))
		amt_label.text = "透视角度　ANGLE"
		_set_slider(_w.curve_amt, inverse_lerp(15.0, 75.0, deg), "%d°" % int(deg) + ("　默认" if is_equal_approx(deg, 35.0) else ""))
	_set_toggle(_w.hit, {"wood": "木质 WOOD", "deep": "深沉 DEEP", "crisp": "清脆 CRISP", "off": "OFF"}[settings.hit_kind], settings.hit_kind != "off")
	_set_toggle(_w.stage, settings.stage.to_upper(), settings.stage == "full")
	_set_toggle(_w.auto, "ON" if settings.autoplay else "OFF", settings.autoplay)
	_set_toggle(_w.fs, "全屏 FULL" if settings.fullscreen else "窗口 WINDOW", settings.fullscreen)
	_set_toggle(_w.kg, "屏蔽 BLOCKED" if settings.keyguard else "系统 SYSTEM", settings.keyguard)
	_set_toggle(_w.low_latency, "开 ON" if settings.low_latency else "关 OFF", settings.low_latency)
	for nm in _w.seg:
		_set_toggle(_w.seg[nm], _w.seg[nm].text, nm == settings.layout)
	_w.kbhint.text = {"ansi": "美式全尺寸 / TKL，以及右 Shift 长的笔记本：右 Shift 2.75u。", "ansi65": "美式 75% / 65%，以及右 Shift 短、旁边就是 ↑ 键的笔记本：右 Shift 1.75u。", "iso": "欧式：Enter 两行高，左 Shift 右边多一个 \\ 键。",
		"jis": "日式：Backspace 左边是 ¥，右 Shift 左边是 ろ；かな / 英数键也能当踏板。"}[settings.layout] \
		+ ("" if settings.layout_manual else "　按到 ¥ / ろ 等日式键会自动切到 JIS。")

func _enter_settings() -> void:
	if state != "menu" and state != "paused": return
	settings_return = state
	state = "settings"
	R.clear_fx()
	_sync_settings_ui()
	_show("Settings")

func _exit_settings() -> void:
	if state != "settings": return
	_save_settings()
	state = settings_return
	_show({"menu": "Menu", "paused": "Pause"}[settings_return])

func _paint_kb_view(c: Control) -> void:
	var W := c.size.x
	var u := W / 15.4
	var ox := u * 0.2
	var rh := c.size.y / 5.3
	var gap := maxf(2.0, u * 0.08)
	var now := SU.ticks()
	c.draw_rect(Rect2(ox, 0, u * 5.75, rh * 4), Color(1, 1, 1, 0.035))
	c.draw_rect(Rect2(ox + u * 7.75, 0, u * 7.25, rh * 4), Color(1, 1, 1, 0.035))
	c.draw_dashed_line(Vector2(ox + u * 6.75, 0), Vector2(ox + u * 6.75, rh * 4), Color(0.91, 0.85, 0.65, 0.45), 1.0, 4.0)
	var all := []
	var r := 0
	for row in KB.rows(settings.layout):
		for k in row:
			all.append({"code": k[0], "x0": k[1], "w": k[2], "ri": r})
		r += 1
	if settings.layout == "iso" or settings.layout == "jis":
		all.append({"code": "Enter", "x0": 13.75, "w": 1.25, "ri": 2, "low": true})
	if settings.layout == "jis":
		for k in [["NonConvert", 3.5, 1.25, "英数"], ["Space", 4.75, 4.5, "SPACE"], ["Convert", 9.25, 1.25, "変換"], ["KanaMode", 10.5, 1.25, "かな"]]:
			all.append({"code": k[0], "x0": k[1], "w": k[2], "ri": 4, "lb": k[3]})
	else:
		all.append({"code": "Space", "x0": 3.75, "w": 6.25, "ri": 4, "lb": "SPACE"})
	var font := Fonts.ui()
	for k in all:
		var x: float = ox + k.x0 * u + gap / 2.0
		var w: float = k.w * u - gap
		var y: float = k.ri * rh + gap / 2.0
		var h := rh - gap
		if k.get("low", false): y = 2.0 * rh - gap / 2.0; h = rh
		elif k.code == "Enter" and k.ri == 1 and not settings.layout in ["ansi", "ansi65"]: h = rh
		var lit := 0.0
		if _kb_down.has(k.code):
			var up: int = _kb_down[k.code]
			lit = 1.0 if up == 0 else maxf(0.0, 1.0 - (now - up) / 4e5)
		var cxk: float = k.x0 + k.w / 2.0
		var gh: bool = k.ri < 4 and k.w <= 1.01 and cxk > 5.75 and cxk < 7.75
		var fill := Color(1, 1, 1, 0.18 + 0.72 * lit) if lit > 0.0 else (Color(0, 0, 0, 0.35) if gh else Color(1, 1, 1, 0.04))
		c.draw_rect(Rect2(x, y, w, h), fill)
		c.draw_rect(Rect2(x + 0.5, y + 0.5, w - 1, h - 1), Color(1, 1, 1, 0.5 if k.ri == 4 else 0.28), false, 1.0)
		if k.get("low", false): continue
		var lb: String = k.get("lb", KB.label(k.code))
		var fs := int(rh * (0.26 if lb.length() > 2 else 0.34))
		var tw := font.get_string_size(lb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font, Vector2(x + w / 2.0 - tw / 2.0, y + rh / 2.0 + fs * 0.35), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0, 0, 0) if lit > 0.5 else Color(1, 1, 1, 0.35 if gh else 0.8))
		if k.code == "KeyF" or k.code == "KeyJ":
			c.draw_rect(Rect2(x + w / 2.0 - u * 0.12, y + h - rh * 0.18, u * 0.24, 1), Color(1, 1, 1, 0.8))
	var dead := []
	for code in _kb_down:
		if _kb_down[code] != 0 and now - _kb_down[code] > 450000: dead.append(code)
	for code in dead: _kb_down.erase(code)

# ================================================================ pause / result
func _build_pause() -> void:
	var s := _screen("Pause")
	var v := _center_panel(s, 520)
	v.add_child(_h2("PAUSED"))
	for b in [["继续　RESUME", _resume], ["重开　RESTART", _restart], ["设置　SETTINGS", _enter_settings], ["退出　QUIT", _quit_to_songs]]:
		var btn := _button(b[0], b[1])
		btn.custom_minimum_size = Vector2(360, 46)
		v.add_child(btn)

func _build_result() -> void:
	var s := _screen("Result")
	var v := ResultView.new()
	v.restart_pressed.connect(_restart)
	v.songs_pressed.connect(_quit_to_songs)
	s.add_child(v)
	_w.res = v

## the results screen: rank by score (scripts/ranks.gd), staggered reveal (scripts/result_view.gd); Enter skips it
func _show_result(st: Dictionary = core.stats, rec: Dictionary = _rec, kind: String = end_kind) -> void:
	var rank := Ranks.rank_of(int(st.score))
	_w.res.begin(st, meta, rec, rank, kind)
	_show("Result")

## --result-demo=<RANK>: the results screen with made-up numbers for that rank (self-checks / screenshots)
func _demo_result(rank: String) -> void:
	rank = rank.to_upper()
	core.load_chart(ChartLib.demo())
	meta = {"title": "Original Demo", "artist": "TOTO-git-q", "version": "EX", "dir": "demo", "level": 11}
	var st := Ranks.demo_stats(rank)
	var kind := "ap" if rank == "SSS" else ("fc" if rank == "SS" else "")
	var rec := {"new": rank in ["SSS", "AA", "BBB"], "prev": int(st.score) - 12340 if rank != "BBB" else 0}
	if rank in ["S", "A", "B", "F"]: rec = {"new": false, "prev": int(st.score) + 21800}
	state = "result"
	end_kind = ""
	_show_result(st, rec, kind)

func _on_finished(st: Dictionary) -> void:
	_finish_play_log("result")
	state = "result"
	end_kind = ("ap" if st.GREAT == 0 and st.GOOD == 0 else "fc") if st.MISS == 0 else ""
	end_at = SU.ticks()
	_rec = {"new": false, "prev": 0}
	var id: String = meta.get("dir", "")
	if id != "" and not settings.autoplay:
		_rec = _scores.update_best(id, _plugin_identity, st)
		var saved := _scores.save_file()
		if not saved.get("errors", []).is_empty(): toast("成绩保存失败：" + "; ".join(saved.errors))
	var completed_stats := st.duplicate(true)
	var serial := _run_serial
	get_tree().create_timer(3.2 if end_kind != "" else 0.9).timeout.connect(func():
		if state == "result" and serial == _run_serial:
			audio.stop()
			_show_result(completed_stats, _rec, end_kind)
			_result_backdrop = not _uses_song_plugins
			_release_song_plugins())

func _pause() -> void:
	if state != "playing": return
	state = "paused"
	audio.pause()
	_show("Pause")

func _resume() -> void:
	if state != "paused": return
	state = "resuming"
	resume_at = SU.ticks() + 1500000
	_show("")

func _restart() -> void:
	_finish_play_log("restart")
	audio.stop()
	_release_song_plugins()
	state = "songs"
	_play_selected(0.0)

func _quit_to_songs() -> void:
	_finish_play_log("quit_to_songs")
	audio.stop()
	core.playing = false
	end_at = 0
	_release_song_plugins()
	_plugin_status.text = ""
	_enter_songs()

func _on_cue(cue: Dictionary, grade: String) -> void:
	if grade != "MISS":
		R.add_cue_ring(cue.yellow, cue.from)
		if settings.hit_kind != "off": audio.pedal(cue.yellow)
	R.add_cue_text(grade, cue.from)

# ================================================================ sync (tap to a metronome)
func _build_sync() -> void:
	var s := _screen("Sync")
	var v := _center_panel(s, 760)
	v.add_child(_h2("SYNC"))
	var p := _label("听节拍，在每一声上按空格", 15, 0.85, 3); p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(p)
	var m := Control.new()
	m.set_script(DrawCtrl)
	m.custom_minimum_size = Vector2(600, 80)
	m.painter = _paint_sync
	v.add_child(m)
	_sync_meter = m
	var rd := _label("", 15, 0.9, 3, Fonts.hud()); rd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rd)
	_w.sync_read = rd
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 18)
	hb.add_child(_button("应用　APPLY", _exit_sync.bind(true)))
	hb.add_child(_button("返回　BACK", _exit_sync.bind(false)))
	v.add_child(hb)
	_sync_player = AudioStreamPlayer.new()
	_sync_player.stream = _metronome()
	add_child(_sync_player)

func _metronome() -> AudioStreamWAV:
	var sr := 44100
	var n := sr * 2                     # 4 clicks of 0.5 s, the first accented, looped
	var data := PackedByteArray(); data.resize(n * 2)
	for i in n:
		var t := fmod(float(i) / sr, 0.5)
		var acc := 1.0 if i < sr / 2 else 0.6
		var v := (0.8 * sin(TAU * 1600.0 * t) + 0.3 * sin(TAU * 3200.0 * t)) * exp(-t * 110.0) * acc if t < 0.04 else 0.0
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = sr; w.stereo = false; w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_begin = 0; w.loop_end = n
	return w

func _enter_sync() -> void:
	if state != "settings" and state != "paused" and state != "menu": return
	sync_return = state
	state = "sync"
	_sync_taps.clear()
	_sync_t0 = SU.ticks()
	_sync_player.play()
	_show("Sync")

func _sync_estimate() -> Dictionary:
	if _sync_taps.size() < 8: return {}
	var a := _sync_taps.duplicate(); a.sort()
	var m: float = a[a.size() / 2]
	var dev := []
	for x in a: dev.append(absf(x - m))
	dev.sort()
	return {"ms": m, "jitter": dev[dev.size() / 2], "n": a.size()}

func _sync_tap() -> void:
	if (SU.ticks() - _sync_t0) < 1500000: return       # warm-up beats
	var pos := _sync_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var err := fposmod(pos + 0.25, 0.5) - 0.25
	_sync_taps.append(err * 1000.0)
	if _sync_taps.size() > 24: _sync_taps.pop_front()
	var e := _sync_estimate()
	_w.sync_read.text = ("%+d ms　　±%d ms　　%d 下" % [int(round(e.ms)), int(round(e.jitter)), e.n]) if not e.is_empty() else "再敲 %d 下" % (8 - _sync_taps.size())
	_sync_meter.queue_redraw()

func _paint_sync(c: Control) -> void:
	var W := c.size.x
	var cx := W / 2.0
	var cy := c.size.y * 0.55
	var span := W * 0.46
	var X := func(ms: float) -> float: return cx + clampf(ms / 150.0, -1.0, 1.0) * span
	c.draw_rect(Rect2(cx - span, cy - 1, span * 2, 2), Color(1, 1, 1, 0.1))
	for ms in [-100, -50, 50, 100]: c.draw_rect(Rect2(X.call(ms) - 0.5, cy - 5, 1, 10), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(cx - 1, cy - 14, 2, 28), Color(1, 1, 1, 0.55))
	for i in _sync_taps.size():
		c.draw_rect(Rect2(X.call(_sync_taps[i]) - 1, cy - 9, 2, 18), Color(1, 1, 1, 0.15 + 0.6 * (i + 1) / _sync_taps.size()))
	var e := _sync_estimate()
	if not e.is_empty():
		var x: float = X.call(e.ms)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 16), Vector2(x - 6, cy - 26), Vector2(x + 6, cy - 26)]), Color(0.91, 0.85, 0.65, 0.95))
	c.draw_string(Fonts.hud(), Vector2(cx - span, cy + 26), "EARLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.4))
	c.draw_string(Fonts.hud(), Vector2(cx + span - 34, cy + 26), "LATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.4))

func _exit_sync(apply: bool) -> void:
	if state != "sync": return
	_sync_player.stop()
	var e := _sync_estimate()
	if apply and not e.is_empty():
		settings.offset_ms = clampi(int(round(e.ms)), -200, 200)
		_save_settings()
		toast("OFFSET %+d ms" % settings.offset_ms)
	state = sync_return
	_sync_settings_ui()
	_show({"menu": "Menu", "settings": "Settings", "paused": "Pause"}[sync_return])

# ================================================================ judgement-line alignment
func _build_calib() -> void:
	var s := _screen("Calib")
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := _label("拖动两端手柄，使判定线左右端对齐桌上键盘的左右边缘（` 键左缘 / Backspace 右缘）\n← → 微调 1px（Shift 10px）　Tab 切换端点　按字母键在对应位置打出标记核对",
		14, 0.85, 2)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.position = Vector2(0, 120); p.size = Vector2(LW, 60)
	s.add_child(p)
	var rd := _label("", 14, 0.8, 2, Fonts.hud()); rd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rd.position = Vector2(0, 190); rd.size = Vector2(LW, 24)
	s.add_child(rd)
	_w.cal_read = rd
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 18)
	hb.position = Vector2(LW / 2.0 - 200, 236)
	hb.add_child(_button("重置　RESET", func(): calib = {"L": 0.0, "R": 1.0}; _calib_changed()))
	hb.add_child(_button("完成　DONE", _exit_calib))
	s.add_child(hb)
	for which in ["L", "R"]:
		var h := Control.new()
		h.set_script(DrawCtrl)
		h.size = Vector2(34, 34)
		h.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		var w2: String = which
		h.painter = func(c):
			var sel: bool = sel_handle == w2
			c.draw_circle(Vector2(17, 17), 16.5, Color(1, 1, 1, 0.22 if sel else 0.0))
			c.draw_arc(Vector2(17, 17), 16.5, 0, TAU, 40, Color(1, 1, 1, 1.0 if sel else 0.7), 1.0, true)
			c.draw_circle(Vector2(17, 17), 3, Color.WHITE)
		h.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed: sel_handle = w2; _calib_changed()
			elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_move_handle(w2, h.position.x + ev.position.x))
		s.add_child(h)
		_w["handle_" + which] = h

func _move_handle(which: String, px: float) -> void:
	var minw := 0.3 * LW
	if which == "L": calib.L = clampf(px, 0.0, calib.R * LW - minw) / LW
	else: calib.R = clampf(px, calib.L * LW + minw, LW) / LW
	_calib_changed()

func _calib_changed() -> void:
	R.line_l = calib.L * LW
	R.line_r = calib.L * LW + (calib.R - calib.L) * LW * 15.0 / KB.span()
	_w.handle_L.position = Vector2(calib.L * LW - 17, SU.JUDGE_Y - 17)
	_w.handle_R.position = Vector2(calib.R * LW - 17, SU.JUDGE_Y - 17)
	_w.handle_L.queue_redraw(); _w.handle_R.queue_redraw()
	_w.cal_read.text = "L %.2f%%　　R %.2f%%　　间距 %.1f%%" % [calib.L * 100, calib.R * 100, (calib.R - calib.L) * 100]

func _enter_calib() -> void:
	if state != "settings" and state != "paused": return
	calib_return = state
	state = "calib"
	R.calib_mode = true
	R.clear_fx()
	sel_handle = "L"
	_calib_changed()
	_show("Calib")

func _exit_calib() -> void:
	if state != "calib": return
	SU.save_json("user://calib.json", calib)
	R.calib_mode = false
	state = calib_return
	_show({"settings": "Settings", "paused": "Pause"}[calib_return])

# ================================================================ input
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or args.has("shot") or args.has("replay"):     # self-check / replay runs never take real keyboard input
		return
	var e := event as InputEventKey
	var now := SU.ticks()
	var raw := KB.code_of(e)
	if raw == "Escape" and e.pressed and not e.echo:
		if _esc_udp != null and _keyguard_pid > 0 and not _esc_from("os"):
			get_viewport().set_input_as_handled()
			return
	if e.pressed and not e.echo:
		if ((e.keycode == KEY_ENTER and e.alt_pressed) or e.keycode == KEY_F11) and not state in ["playing", "paused", "resuming"]:
			settings.fullscreen = not settings.fullscreen
			_apply_window(); _save_settings(); _sync_settings_ui()
			get_viewport().set_input_as_handled()
			return
		var h := KB.hint(raw)
		if h != "" and not settings.layout_manual and settings.layout != h:
			settings.layout = h; _apply_settings(); _save_settings(); _sync_settings_ui()
			toast("检测到 %s 键盘，已切换键位" % h.to_upper())
	# while a chart plays (owner, 2026-10-16): Caps Lock and Ctrl do nothing, and a stray Ctrl / Alt / Win held down no
	# longer swallows the real key presses (Fn never reaches the game: the keyboard firmware handles it)
	var in_play := state in ["playing", "paused", "resuming"]
	if in_play and (raw == "CapsLock" or e.keycode == KEY_CTRL or e.keycode == KEY_META or e.keycode == KEY_ALT):
		get_viewport().set_input_as_handled()
		return
	if e.pressed and not in_play and (e.ctrl_pressed or e.alt_pressed or e.meta_pressed):
		return
	var code := "Space" if KB.is_pedal(raw) else raw
	if raw in ["NonConvert", "Convert", "KanaMode"]:
		# Windows often sends no key-up for IME toggle keys: as a pedal they are tap-only
		if e.pressed and not e.echo:
			_key_down(code, raw, false, now, false)
			_key_up(code, raw, now)
		get_viewport().set_input_as_handled()
		return
	if e.pressed:
		_key_down(code, raw, e.echo, now, e.shift_pressed)
	else:
		_key_up(code, raw, now)
	get_viewport().set_input_as_handled()

func _key_down(code: String, raw: String, echo: bool, now: int, shift: bool) -> void:
	if _marker_key(code, echo, now): return
	match state:
		"menu":
			if code == "ArrowUp" or code == "ArrowDown":
				_menu_select(posmod(_menu_sel + (-1 if code == "ArrowUp" else 1), _menu_items.size()))
			elif (code == "Enter" or code == "Space") and not echo:
				_menu_go(_menu_items[_menu_sel][3])
		"songs":
			if code == "Escape": audio.preview_stop(); state = "menu"; _show("Menu")
			elif code == "ArrowLeft" or code == "ArrowRight": _song_move(-1 if code == "ArrowLeft" else 1)
			elif code == "ArrowUp" or code == "ArrowDown": _song_diff(-1 if code == "ArrowUp" else 1)
			elif (code == "Enter" or code == "Space") and not echo: _play_selected(0.0)
		"plugin_trust":
			if echo: return
			if code == "KeyY": _plugin_trust_answer(true)
			elif code == "KeyN": _plugin_trust_answer(false)
			elif code == "Escape": _cancel_plugin_play()
		"settings":
			if code == "Escape": _exit_settings()
			elif not echo:
				_kb_down[raw] = 0
				_w.kbview.queue_redraw()
		"calib":
			if code == "Escape": _exit_calib()
			elif code == "ArrowLeft" or code == "ArrowRight":
				var step := (10.0 if shift else 1.0) * (-1.0 if code == "ArrowLeft" else 1.0)
				_move_handle(sel_handle, (calib.L if sel_handle == "L" else calib.R) * LW + step)
			elif code == "Tab" and not echo:
				sel_handle = "R" if sel_handle == "L" else "L"; _calib_changed()
			elif KB.is_key(code) and not echo:
				R.add_ripple(KB.x_of(code), 1.0)
		"sync":
			if code == "Escape": _exit_sync(false)
			elif code == "Enter": _exit_sync(true)
			elif (code == "Space" or KB.is_key(code)) and not echo: _sync_tap()
		"paused":
			if code == "Escape": _resume()
		"resuming":
			if code == "Escape": resume_at = 0; state = "paused"; _show("Pause")
		"result":
			if code == "KeyR" and not echo: _restart()
			elif (code == "Escape" or code == "Enter") and not echo and screens.Result.visible:
				if _w.res.can_leave(): _quit_to_songs()
				else: _w.res.skip()
		"playing":
			if code == "Escape": _pause(); return
			if echo: return
			var ts: float = audio.time_at(now) - settings.offset_ms / 1000.0
			if code == "Space": core.press_space(ts)
			elif KB.is_key(code): core.press_key(code, ts)

func _key_up(code: String, raw: String, now: int) -> void:
	if code == "Backquote" and state in ["playing", "paused", "resuming"]: return
	if state == "settings":
		if _kb_down.has(raw): _kb_down[raw] = now
		return
	if state != "playing" and state != "paused" and state != "resuming": return
	var ts: float = audio.time_at(now) - settings.offset_ms / 1000.0
	if code == "Space": core.release_space(ts)
	elif KB.is_key(code): core.release_key(code, ts)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and not args.has("shot") and not args.has("replay") 			and SU.ticks() - _pacing_changed_at > 500000:
		core.release_all(audio.now_time() - settings.offset_ms / 1000.0)
		_pause()

# ================================================================ main loop
func _process(_delta: float) -> void:
	_poll_esc_fast()
	var now := SU.ticks()
	if _uses_song_plugins and _song_plugins != null and now >= _plugin_notice_at:
		_plugin_notice_at = now + 1000000
		var notices: Array = _song_plugins.runtime_notices()
		_plugin_status.text = _plugin_notice_base
		if not notices.is_empty():
			_plugin_status.text += ("\n" if not _plugin_status.text.is_empty() else "") + "插件提示 / Plugin: " + "; ".join(notices)
	var dt := clampf((now - last_ticks) / 1e6, 0.0, 0.05)
	last_ticks = now
	var perf := (now - started_ticks) / 1e6
	audio.sync(now)
	if state == "resuming" and resume_at > 0 and now >= resume_at:
		resume_at = 0
		state = "playing"
		audio.resume()
	var play := state in ["playing", "paused", "resuming"] or (state == "result" and _result_backdrop)
	var t := 0.0
	if play:
		t = audio.time_at(now) - settings.offset_ms / 1000.0
		if state == "playing":
			_replay_feed(t)
			core.update(t)
		if SU._movie_fps > 0.0 and state == "playing" and Engine.get_process_frames() % 30 == 0:
			print("MOVIE_SYNC frame=%d t=%.4f" % [Engine.get_process_frames(), t])
	var lights := []
	if play:
		lights = core.light_states(t, settings.reach)
	elif state in ["menu", "settings", "loading"]:
		lights = [{"id": 0, "alive": true, "x": 0.5 + 0.2 * sin(perf * 0.31), "w": 0.24 + 0.08 * sin(perf * 0.17 + 1.0), "reach": 1.0, "alpha": 0.8, "pulse": 0.0}]
	var by_id := {}
	for l in lights: by_id[l.id] = l
	var ending := {}
	if end_at > 0 and state == "result" and end_kind != "":
		ending = {"kind": end_kind, "age": (now - end_at) / 1e6}
	var fd := {"t": t, "fxT": t if play else perf, "perf": perf, "dt": dt, "lights": lights, "light_by_id": by_id,
		"notes": core.notes if play else [], "cues": core.cues if play else [], "fall": settings.fall, "reach": settings.reach,
		"tl": core.tl, "chart": core.chart if play else {}, "phase": core.chart.notes[0].t if play and not core.chart.notes.is_empty() else 0.0,
		"stats": core.stats if play else {}, "play": play, "space_down": core.space_down, "hit_log": core.hit_log, "chords": core.chords,
		"meta": meta, "progress": clampf(t / core.end_time, 0.0, 1.0) if play and core.end_time > 0.0 else 0.0,
		"countdown": maxf(0.0, (resume_at - now) / 1e6) if state == "resuming" and resume_at > 0 else 0.0, "ending": ending}
	R.frame(fd, core.stage)
	if _toast_until > 0:
		_toast.modulate.a = clampf((_toast_until - now) / 2.5e5, 0.0, 1.0)
		if now > _toast_until: _toast_until = 0
	if state == "settings" and not _kb_down.is_empty():
		_w.kbview.queue_redraw()
	if args.has("keys"):                       # scripted keys for self-checks: --keys=Enter,ArrowRight,... (one per 0.7 s from 1 s)
		var ks: PackedStringArray = str(args["keys"]).split(",")
		var due := int((perf - 1.0) / 0.7)
		while _key_i < ks.size() and _key_i <= due:
			var k := ks[_key_i]
			if k != "_":
				_key_down(k, k, false, now, false)
				_key_up(k, k, now)
			_key_i += 1
	if args.has("shot") and perf >= float(args.get("shot-at", "3")):
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			img.save_png(args.shot)
		print("shot saved: ", args.shot, "  state=", state, "  t=", "%.2f" % t, "  combo=", core.stats.get("combo", 0), "  score=", core.stats.get("score", 0))
		_finish_play_log("shot")
		get_tree().quit()

## --replay: feed every recorded key event up to chart time t, each at its own time (the core is brought up to the
## event's time first, so misses / yellow catches / hold ticks happen in the same order as for a live player)
func _replay_feed(t: float) -> void:
	while _replay_i < _replay.size() and float(_replay[_replay_i].t) <= t:
		var ev: Dictionary = _replay[_replay_i]
		_replay_i += 1
		var ts := maxf(float(ev.t), core.clock_now)
		core.update(ts)
		var code := str(ev.code)
		if code == "Space":
			if ev.down: core.press_space(ts)
			else: core.release_space(ts)
		elif KB.is_key(code):
			if ev.down: core.press_key(code, ts)
			else: core.release_key(code, ts)

# ================================================================ playtest evidence
func _test_working_copy(dir: String) -> bool:
	# Charter working copies can be rendered without changing the human's song index.
	if not PluginLoader.safe_relative(dir) or "." in dir.split("/") or "" in dir.split("/"): return false
	var folder := songs_dir().path_join(dir)
	var raw = SU.load_json(folder.path_join("chart.json"))
	if typeof(raw) != TYPE_DICTIONARY: return false
	var audio_file := ""
	for ext in ["mp3", "ogg", "wav"]:
		if FileAccess.file_exists(folder.path_join("audio." + ext)):
			audio_file = "audio." + ext; break
	if audio_file.is_empty(): return false
	var cm: Dictionary = raw.get("meta", {})
	songs.append({"title": str(cm.get("title", dir)), "artist": str(cm.get("artist", "")), "bpm": raw.get("bpm", 120.0),
		"length": 0.0, "cover": "", "preview": -1.0,
		"diffs": [{"dir": dir, "version": str(cm.get("version", "WORKING")), "audio": audio_file, "level": 1}]})
	sel_i = songs.size() - 1; sel_d = 0
	_play_selected(float(args.get("from", "0")))
	return state in ["playing", "plugin_trust"]

func _marker_key(code: String, echo: bool, now: int) -> bool:
	if code != "Backquote" or state not in ["playing", "paused", "resuming"]: return false
	if state == "playing" and not echo:
		_play_log.mark(audio.time_at(now) - settings.offset_ms / 1000.0)
		R.show_marker()
	return true

func _finish_play_log(reason: String) -> void:
	_play_log.finish(core, reason)

func _exit_tree() -> void:
	if _pacing_ready:
		DisplayServer.window_set_vsync_mode(_normal_vsync)
		Engine.max_fps = _normal_max_fps
		Input.use_accumulated_input = _normal_accumulated_input
		_pacing_ready = false
	_finish_play_log("quit")
	if not _pending_play.is_empty(): _pending_play.session.close(); _pending_play.clear()
	# The tree is being destroyed; release scoped callbacks before its registry.
	if _song_plugins != null:
		if is_instance_valid(R): R.free()
		core = null
		_song_plugins.close(); _song_plugins = null
	_keyguard_stop()

# ================================================================ KeyGuard: system shortcuts off while the game is in front
# keyguard/KeyGuard.exe (next to the exe in a build) -- Win / Menu / Alt (so no Alt+Tab, Alt+F4) / Ctrl+Esc / media
# keys are swallowed while this window is in front, the StickyKeys-style hotkeys are off while it runs; only Esc keeps
# its meaning.  It watches our pid and restores everything if we exit or crash.  Never in shot / test runs.
var _keyguard_pid := -1
# Esc fast path (2026-10-18): KeyGuard sends "ESC" the instant the key goes down; the same press then also arrives as
# a normal (possibly ~1 s late) key event. Each source counts its presses; a press acts only when its source is ahead,
# so whichever copy comes first acts and the other is dropped, and a lost packet heals itself.
var _esc_udp: PacketPeerUDP
var _esc_n := {"udp": 0, "os": 0}
var _esc_last := 0

func _esc_from(source: String) -> bool:
	var now := SU.ticks()
	if now - _esc_last > 3000000:             # quiet for 3 s: both sources agree again
		var m: int = maxi(_esc_n.udp, _esc_n.os)
		_esc_n.udp = m; _esc_n.os = m
	_esc_last = now
	_esc_n[source] += 1
	var other := "os" if source == "udp" else "udp"
	return _esc_n[source] > _esc_n[other]

func _poll_esc_fast() -> void:
	if _esc_udp == null: return
	while _esc_udp.get_available_packet_count() > 0:
		if _esc_udp.get_packet().get_string_from_ascii() == "ESC" and _esc_from("udp"):
			_key_down("Escape", "Escape", false, SU.ticks(), false)

func _keyguard_path() -> String:
	var p := OS.get_executable_path().get_base_dir().path_join("KeyGuard.exe")
	if FileAccess.file_exists(p): return p
	p = ProjectSettings.globalize_path("res://keyguard/KeyGuard.exe")
	if FileAccess.file_exists(p): return p
	return _keyguard_build()

## Running from source (owner, 2026-10-18): the repo does not track .exe files, so without this the guard never started
## and Caps Lock / Win / Alt reached Windows. Build it once into user:// with Windows' own C# compiler (.NET Framework 4,
## present on every Windows) and rebuild when KeyGuard.cs is newer.
func _keyguard_build() -> String:
	if OS.get_name() != "Windows" or OS.has_feature("template"): return ""
	var src := ProjectSettings.globalize_path("res://keyguard/KeyGuard.cs")
	var csc := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	if not FileAccess.file_exists(src) or not FileAccess.file_exists(csc): return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://keyguard"))
	var out := ProjectSettings.globalize_path("user://keyguard/KeyGuard.exe")
	if FileAccess.file_exists(out) and FileAccess.get_modified_time(out) >= FileAccess.get_modified_time(src): return out
	var log := []
	# csc reads "/x" inside a path as an option, so hand it backslash paths
	var code := OS.execute(csc, ["-nologo", "-target:winexe", "-optimize+", "-out:" + out.replace("/", "\\"), src.replace("/", "\\")], log, true)
	if code != 0 or not FileAccess.file_exists(out):
		push_warning("KeyGuard build failed: " + "".join(log).left(400))
		return ""
	return out

func _keyguard_update() -> void:
	var want: bool = settings.keyguard and OS.get_name() == "Windows" and not args.has("shot") and not args.has("windowed")
	if want and _keyguard_pid < 0:
		var p := _keyguard_path()
		if p != "":
			var kg_args := [str(OS.get_process_id())]
			if _esc_udp == null:
				_esc_udp = PacketPeerUDP.new()
				if _esc_udp.bind(0, "127.0.0.1") != OK: _esc_udp = null
			if _esc_udp != null: kg_args += ["--esc-port", str(_esc_udp.get_local_port())]
			_keyguard_pid = OS.create_process(p, kg_args)
	elif not want: _keyguard_stop()

func _keyguard_stop() -> void:
	if _keyguard_pid > 0: OS.kill(_keyguard_pid)          # it restores the settings itself on exit
	_keyguard_pid = -1
