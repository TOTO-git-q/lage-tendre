extends Control
## 新建歌曲: a modal card over the editor. Pick the audio, name the song, set the tempo (type it,
## or tap along while it plays) and the first beat (click the waveform), name the difficulty.
## Creates songs/<dir>/ with the audio and an empty chart and adds it to the game's song list.

signal created(result: Dictionary)

const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Lib = preload("res://song_library.gd")

var root := ""
var fan_made := false
var heading := Label.new()
var destination := Label.new()
var audio_path := ""
var card := PanelContainer.new()
var audio_label := Label.new()
var title_edit := LineEdit.new()
var artist_edit := LineEdit.new()
var diff_edit := LineEdit.new()
var level
var bpm
var offset
var tap_label := Label.new()
var wave := Control.new()
var error := Label.new()
var create_b := Button.new()
var play_b: W.IconButton
var player := AudioStreamPlayer.new()
var file_dialog := FileDialog.new()
var peaks := PackedFloat32Array()
var view_lo := 0.0
var view_span := 20.0
var taps: Array = []
const PEAK_STEP := 0.02

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	draw.connect(func(): draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45)))
	add_child(player)
	card.theme_type_variation = "Float"; card.custom_minimum_size = Vector2(620, 0)
	add_child(card)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); card.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	heading.text = "新建歌曲"; heading.theme_type_variation = "Title"; head.add_child(heading)
	head.add_child(_spacer())
	var close_b := W.IconButton.new("close", "取消（Esc）"); close_b.pressed.connect(close); head.add_child(close_b)
	# audio
	var arow := _row("音频", v)
	var pick := Button.new(); pick.text = "选择音频文件…"; pick.pressed.connect(func(): file_dialog.popup_file_dialog()); arow.add_child(pick)
	audio_label.theme_type_variation = "Muted"; audio_label.clip_text = true; audio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_label.text = "mp3、ogg 或 wav"; arow.add_child(audio_label)
	# names
	title_edit.placeholder_text = "歌名"; title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _row("歌名", v).add_child(title_edit)
	artist_edit.placeholder_text = "作曲 / 演唱"; artist_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _row("作者", v).add_child(artist_edit)
	var drow := _row("难度", v)
	diff_edit.text = "EX"; diff_edit.placeholder_text = "EX、HARD …"; diff_edit.custom_minimum_size.x = 140; drow.add_child(diff_edit)
	drow.add_child(_gap(16))
	level = W.ScrubField.new("等级", "", 1.0); level.min_value = 0; level.max_value = 15
	level.formatter = func(x): return str(int(x))
	level.set_value(10)
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL; drow.add_child(level)
	# tempo
	var brow := _row("BPM", v)
	bpm = W.ScrubField.new("", "", 0.1); bpm.handle.custom_minimum_size.x = 0; bpm.min_value = 20; bpm.max_value = 400; bpm.formatter = func(x): return "%.1f" % x
	bpm.set_value(120)
	bpm.custom_minimum_size.x = 150; brow.add_child(bpm)
	bpm.changed.connect(func(_x, _f): wave.queue_redraw())
	var tap := Button.new(); tap.text = "跟着音乐敲击定速"; tap.tooltip_text = "播放时跟着拍子点这个按钮，至少 4 下"
	tap.pressed.connect(_tap); brow.add_child(tap)
	tap_label.theme_type_variation = "Faint"; brow.add_child(tap_label)
	var orow := _row("第一拍", v)
	offset = W.ScrubField.new("", "秒", 0.001); offset.handle.custom_minimum_size.x = 0; offset.min_value = 0; offset.max_value = 600; offset.formatter = func(x): return "%.3f" % x
	offset.set_value(0)
	offset.custom_minimum_size.x = 150; orow.add_child(offset)
	offset.changed.connect(func(_x, _f): wave.queue_redraw())
	play_b = W.IconButton.new("play", "试听（从波形左端开始）", "试听"); play_b.pressed.connect(_toggle_play); orow.add_child(play_b)
	var hint := Label.new(); hint.text = "点击波形设定第一拍，滚轮缩放"; hint.theme_type_variation = "Faint"; orow.add_child(hint)
	# waveform with the beat grid
	wave.custom_minimum_size = Vector2(0, 110); wave.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wave.draw.connect(_draw_wave); wave.gui_input.connect(_wave_input); v.add_child(wave)
	error.theme_type_variation = "Muted"; error.add_theme_color_override("font_color", Tokens.DANGER); error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(error)
	var foot := HBoxContainer.new(); v.add_child(foot)
	var note := destination; note.text = "会在 songs 里新建文件夹，并加入游戏歌单（先备份 index.json）"; note.theme_type_variation = "Faint"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; foot.add_child(note)
	var cancel := Button.new(); cancel.text = "取消"; cancel.theme_type_variation = "Ghost"; cancel.pressed.connect(close); foot.add_child(cancel)
	create_b.text = "创建歌曲"; create_b.theme_type_variation = "Primary"; create_b.pressed.connect(_create); foot.add_child(create_b)
	file_dialog.use_native_dialog = true; file_dialog.access = FileDialog.ACCESS_FILESYSTEM; file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; 音频"]); file_dialog.title = "选择歌曲音频"
	file_dialog.file_selected.connect(set_audio)
	add_child(file_dialog)

func _spacer() -> Control:
	var c := Control.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return c

func _gap(w: float) -> Control:
	var c := Control.new(); c.custom_minimum_size.x = w; return c

func _row(label: String, parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 10); parent.add_child(r)
	var l := Label.new(); l.text = label; l.theme_type_variation = "Muted"; l.custom_minimum_size = Vector2(64, 34); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(l)
	return r

func open(community := false) -> void:
	fan_made = community
	heading.text = "新建社区谱面" if community else "新建歌曲"
	destination.text = "创建 songs/fan-made/<slug>/；提交前填写授权信息。音频仅 OGG / MP3。" if community else "会在 songs 里新建文件夹，并加入游戏歌单（先备份 index.json）"
	visible = true; error.text = ""; taps = []; tap_label.text = ""
	_place.call_deferred()

func _place() -> void:
	card.reset_size()
	card.position = ((size - card.size) / 2.0).floor()

func close() -> void:
	player.stop(); visible = false

func set_audio(path: String) -> void:
	audio_path = path
	audio_label.text = path.get_file()
	if title_edit.text.strip_edges().is_empty(): title_edit.text = path.get_file().get_basename()
	player.stream = Lib.load_audio(path)
	peaks = Lib.peaks(path, PEAK_STEP, 90.0)
	view_lo = 0.0; view_span = 20.0
	wave.queue_redraw()

func _toggle_play() -> void:
	if player.playing: player.stop(); play_b.icon_name = "play"; play_b.queue_redraw(); return
	if player.stream == null: error.text = "先选择音频文件"; return
	player.play(view_lo); play_b.icon_name = "pause"; play_b.queue_redraw()

func _tap() -> void:
	var now := Time.get_ticks_usec() / 1e6
	if not taps.is_empty() and now - taps[-1] > 2.0: taps = []
	taps.append(now)
	if taps.size() > 12: taps.pop_front()
	if taps.size() >= 4:
		var gaps := []
		for i in range(1, taps.size()): gaps.append(taps[i] - taps[i - 1])
		gaps.sort()
		var b := snappedf(60.0 / gaps[gaps.size() / 2], 0.1)
		bpm.set_value(b); wave.queue_redraw()
		tap_label.text = "%d 下" % taps.size()
	else:
		tap_label.text = "再敲 %d 下" % (4 - taps.size())

func _process(_dt: float) -> void:
	if visible and player.playing: wave.queue_redraw()

func _x(t: float) -> float: return (t - view_lo) / view_span * wave.size.x
func _t(x: float) -> float: return view_lo + x / maxf(1.0, wave.size.x) * view_span

func _draw_wave() -> void:
	var tk := Tokens.tokens()
	wave.draw_style_box(Tokens.box(tk.canvas, 8, tk.border), Rect2(Vector2.ZERO, wave.size))
	var h := wave.size.y; var mid := h / 2.0
	if peaks.is_empty():
		var f := Tokens.font("sans"); var msg := "选择音频后显示波形"
		var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x
		wave.draw_string(f, Vector2((wave.size.x - w) / 2.0, mid + 5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.faint)
		return
	var i0 := maxi(0, int(view_lo / PEAK_STEP)); var i1 := mini(peaks.size(), int((view_lo + view_span) / PEAK_STEP) + 1)
	for i in range(i0, i1):
		var x := _x(i * PEAK_STEP)
		wave.draw_line(Vector2(x, mid - peaks[i] * h * 0.42), Vector2(x, mid + peaks[i] * h * 0.42), Color(tk.text, 0.28), maxf(1.0, wave.size.x / view_span * PEAK_STEP))
	# beat grid from the first beat: bars stronger, numbered
	var beat := 60.0 / maxf(1.0, float(bpm.value)); var t0 := float(offset.value)
	var k0 := int(floor((view_lo - t0) / beat)); var num := Tokens.font("num", 600)
	for k in range(maxi(0, k0), k0 + int(view_span / beat) + 2):
		var tb := t0 + k * beat
		if tb < view_lo or tb > view_lo + view_span: continue
		var bar := k % 4 == 0
		wave.draw_line(Vector2(_x(tb), 0), Vector2(_x(tb), h), Color(tk.clay, 0.9 if k == 0 else (0.45 if bar else 0.18)), 2.0 if k == 0 else 1.0)
		if bar and beat * wave.size.x / view_span > 6: wave.draw_string(num, Vector2(_x(tb) + 4, 15), str(k / 4 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.clay)
	if player.playing:
		var px := _x(player.get_playback_position())
		wave.draw_line(Vector2(px, 0), Vector2(px, h), tk.text, 1.5)

func _wave_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT: offset.emit_value(snappedf(_t(e.position.x), 0.001), true); wave.queue_redraw()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if e.ctrl_pressed or not e.shift_pressed:
					var at := _t(e.position.x)
					view_span = clampf(view_span * (0.8 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25), 2.0, 90.0)
					view_lo = maxf(0.0, at - e.position.x / maxf(1.0, wave.size.x) * view_span)
				else:
					view_lo = maxf(0.0, view_lo + (-1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * view_span * 0.2)
				wave.queue_redraw()
		wave.accept_event()

func _create() -> void:
	var result := Lib.create_song(root, {"audio": audio_path, "title": title_edit.text, "artist": artist_edit.text, "bpm": float(bpm.value),
		"offset": float(offset.value), "difficulty": diff_edit.text, "level": int(level.value), "fan_made": fan_made})
	if result.has("error"): error.text = str(result.error); return
	close(); created.emit(result)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: close(); accept_event()
