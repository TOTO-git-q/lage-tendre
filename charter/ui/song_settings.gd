extends VBoxContainer
## 歌曲设置: the inspector page when nothing is selected. Song name / artist / difficulty / level
## (chart meta, and on request the game song list), the audio file, the audio offset and the tempo
## map (timing segments: first beat, BPM, meter), with the waveform and its beat lines around the
## playhead so the grid can be checked against the music while it plays.
##
## Every change is one undo step through document.gd (target "song" / meta). Notes, tracks and
## camera events are in chart seconds, so tempo edits only move the grid; re-timing the chart to
## a new grid and shifting the chart with the audio are separate, confirmed actions.

const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Lib = preload("res://song_library.gd")
const Timing = preload("res://song_timing.gd")
const PEAK_STEP := 0.02

static var _peaks_cache: Dictionary = {}   # audio path -> [mtime, peaks]

var app
var doc
var title_edit := LineEdit.new()
var artist_edit := LineEdit.new()
var diff_edit := LineEdit.new()
var level
var audio_label := Label.new()
var offset_field
var seg_box := VBoxContainer.new()
var seg_rows: Array = []
var wave := Control.new()
var retime_b: W.IconButton
var retime_note := Label.new()
var tap_label := Label.new()
var taps: Array = []
var view_span := 8.0
## The grid the chart was written against, per chart file (taken when the page first shows the
## song, replaced after a re-time); the re-time action converts from it to the current grid.
static var baselines: Dictionary = {}
var baseline: Array:
	get: return baselines.get(doc.path, [])
	set(v): baselines[doc.path] = v
var _gesture := 0

func _ready() -> void:
	add_theme_constant_override("separation", 10)

func build() -> void:
	seg_rows = []
	if not baselines.has(doc.path): baseline = doc.timing().duplicate(true)
	var meta: Dictionary = doc.raw.get("meta", {})
	# ---- song
	add_child(_section("歌曲"))
	title_edit.text = str(meta.get("title", doc.song_meta.get("title", ""))); title_edit.placeholder_text = "歌名"
	artist_edit.text = str(meta.get("artist", doc.song_meta.get("artist", ""))); artist_edit.placeholder_text = "作者"
	diff_edit.text = str(meta.get("difficulty", doc.song_meta.get("version", ""))); diff_edit.placeholder_text = "EX"
	for pair in [["歌名", title_edit, "title"], ["作者", artist_edit, "artist"], ["难度", diff_edit, "difficulty"]]:
		var e: LineEdit = pair[1]; var key: String = pair[2]
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.text_submitted.connect(_meta_text.bind(key)); e.focus_exited.connect(func(): _meta_text(e.text, key))
		_row(pair[0]).add_child(e)
	level = W.ScrubField.new("等级", "", 1.0); level.min_value = 0; level.max_value = 15
	level.formatter = func(x): return str(int(x))
	level.set_value(float(meta.get("level", doc.song_meta.get("level", 0))))
	level.changed.connect(func(v, final): if final: _set_meta("level", int(v), "歌曲等级"))
	add_child(level)
	var sync_b := W.IconButton.new("branch", "把歌名、作者、难度和等级写进 songs/index.json（先备份）", "同步到游戏歌单")
	sync_b.pressed.connect(func(): app.song_action("add_to_game", app.current_dir()))
	add_child(sync_b)
	# ---- audio
	add_child(_section("音频"))
	var arow := HBoxContainer.new(); add_child(arow)
	audio_label.text = app.api.audio_path().get_file(); audio_label.theme_type_variation = "Num"; audio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_label.clip_text = true; arow.add_child(audio_label)
	var rep := Button.new(); rep.text = "替换音频…"; rep.pressed.connect(func(): app.replace_audio_dialog()); arow.add_child(rep)
	offset_field = W.ScrubField.new("音频偏移", "秒", 0.001)
	offset_field.formatter = func(x): return "%.3f" % x
	offset_field.tooltip_text = "音频第 0 秒在谱面时钟上的位置"
	offset_field.changed.connect(func(v, final): _set_song({"offset": snappedf(v, 0.0001)}, "音频偏移", "song-offset-%d" % offset_field.gesture, final))
	add_child(offset_field)
	add_child(_note("改偏移只移动音频，谱面里的音符、轨道和镜头不动。"))
	var shift_b := W.IconButton.new("motion", "音频和整张谱面一起在谱面时钟上平移（片头留白变长或变短）", "整体平移谱面…")
	shift_b.pressed.connect(_shift_dialog); add_child(shift_b)
	# ---- tempo map
	add_child(_section("节拍"))
	seg_box.add_theme_constant_override("separation", 6); add_child(seg_box)
	_build_segments()
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 4); actions.add_theme_constant_override("v_separation", 4); add_child(actions)
	var first_b := W.IconButton.new("node", "把第一段的第一拍放到播放头", "设为第一拍"); first_b.pressed.connect(_first_beat_here); actions.add_child(first_b)
	var add_b := W.IconButton.new("plus", "从播放头开始一段新的 BPM", "在播放头变速"); add_b.pressed.connect(_add_change); actions.add_child(add_b)
	var tap := W.IconButton.new("metronome", "播放时跟着拍子点，至少 4 下，设定播放头所在段的 BPM", "敲击定速"); tap.pressed.connect(_tap); actions.add_child(tap)
	tap_label.theme_type_variation = "Faint"; tap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; actions.add_child(tap_label)
	# waveform with the beat grid around the playhead
	wave.custom_minimum_size = Vector2(0, 120); wave.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wave.tooltip_text = "点击跳到这里，滚轮缩放。开着节拍器播放，可以听拍线和音乐是否对齐"
	wave.draw.connect(_draw_wave); wave.gui_input.connect(_wave_input)
	add_child(wave)
	var metro := W.IconButton.new("metronome", "播放时在每一拍响一声", "节拍器"); metro.toggle_mode = true
	metro.button_pressed = app.metro_b.button_pressed
	metro.toggled.connect(func(on): app.metro_b.button_pressed = on; app.metro_b.queue_redraw())
	add_child(metro)
	add_child(_note("音符、轨道和镜头都按谱面时间（秒）存放。改 BPM 或第一拍只会移动网格（小节号和吸附），不会移动它们。"))
	retime_b = W.IconButton.new("curve", "整张谱面原本是按错的网格写的时候用：所有事件保持小节和拍位置，换算到新网格", "让 note 跟着新节拍移动…")
	retime_b.pressed.connect(_retime_dialog); add_child(retime_b)
	retime_note.theme_type_variation = "Faint"; retime_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(retime_note)
	sync()

func _section(text: String) -> Label:
	var l := Label.new(); l.text = text; l.theme_type_variation = "Heading"
	return l

func _note(text: String) -> Label:
	var l := Label.new(); l.text = text; l.theme_type_variation = "Faint"; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _row(label: String) -> HBoxContainer:
	var r := HBoxContainer.new(); add_child(r)
	var l := Label.new(); l.text = label; l.theme_type_variation = "Muted"; l.custom_minimum_size = Vector2(W.LABEL_W, W.ROW_H); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(l)
	return r

func _build_segments() -> void:
	for c in seg_box.get_children(): seg_box.remove_child(c); c.queue_free()
	seg_rows = []
	var segs: Array = doc.timing()
	for i in segs.size():
		var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 2); seg_box.add_child(card)
		var head := HBoxContainer.new(); card.add_child(head)
		var h := Label.new(); h.text = "从 %s 起" % doc.position(float(segs[i].t) + 0.0001).bar_beat.get_slice("+", 0) if i > 0 else "第一段"
		h.theme_type_variation = "Section"; h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(h)
		if i > 0:
			var del := W.IconButton.new("trash", "删除这次变速"); del.pressed.connect(_remove_segment.bind(i)); head.add_child(del)
		var start := W.ScrubField.new("第一拍" if i == 0 else "开始于", "秒", 0.001)
		start.formatter = func(x): return "%.3f" % x
		start.changed.connect(func(v, final): _set_segment(i, "t", v, "song-t-%d-%d" % [i, start.gesture], final))
		card.add_child(start)
		var bpm := W.ScrubField.new("BPM", "", 1.0); bpm.min_value = 20; bpm.max_value = 600
		bpm.formatter = func(x): return ("%.3f" % x).rstrip("0").rstrip(".")
		bpm.changed.connect(func(v, final): _set_segment(i, "bpm", v, "song-bpm-%d-%d" % [i, bpm.gesture], final))
		card.add_child(bpm)
		var meter := W.ScrubField.new("拍号", "拍每小节", 1.0); meter.min_value = 1; meter.max_value = 16
		meter.formatter = func(x): return str(int(x))
		meter.changed.connect(func(v, final): if final: _set_segment(i, "meter", roundf(v), "", true))
		card.add_child(meter)
		seg_rows.append({"t": start, "bpm": bpm, "meter": meter})

## Refresh the values after any document change (rebuild when the number of segments changed).
func sync() -> void:
	if doc == null or doc.raw.is_empty(): return
	var segs: Array = doc.timing()
	if segs.size() != seg_rows.size(): _build_segments()
	for i in segs.size():
		seg_rows[i].t.step = 0.001
		seg_rows[i].t.set_value(float(segs[i].t)); seg_rows[i].bpm.set_value(60.0 / float(segs[i].beat)); seg_rows[i].meter.set_value(float(segs[i].get("meter", 4)))
	offset_field.set_value(float(doc.raw.get("offset", 0.0)))
	var changed := _timing_signature(segs) != _timing_signature(baseline)
	retime_b.disabled = not changed
	retime_note.text = ("谱面是按 %s 写的；现在的网格是 %s。" % [Timing.bpm_text(baseline), Timing.bpm_text(segs)]) if changed else ""
	retime_note.visible = changed
	wave.queue_redraw()

static func _timing_signature(segs: Array) -> String:
	var rows := []
	for s in segs: rows.append("%.4f|%.6f|%d" % [float(s.t), float(s.beat), int(s.get("meter", 4))])
	return ";".join(rows)

## ------------------------------------------------------------------ commits
func _commit(value: Dictionary, label: String, coalesce: String = "", ext = null) -> bool:
	var args := {"expected_revision": doc.revision(), "label": label, "ops": [{"target": "song", "value": value}], "coalesce": coalesce}
	if ext != null: args["ext"] = ext
	var result: Dictionary = doc.edit(args)
	if result.has("error"): app.report(result); sync(); return false
	return true

var _last_live := 0
func _set_song(value: Dictionary, label: String, coalesce: String, final: bool) -> void:
	var now := Time.get_ticks_msec()
	if not final and now - _last_live < 120: return
	_last_live = now
	_commit(value, label, coalesce)

func _timing_copy() -> Array:
	var out := []
	for s in doc.timing(): out.append({"t": float(s.t), "beat": float(s.beat), "meter": int(s.get("meter", 4))})
	return out

func _set_segment(i: int, field: String, v: float, coalesce: String, final: bool) -> void:
	var timing := _timing_copy()
	if i >= timing.size(): return
	match field:
		"t": timing[i].t = snappedf(v, 0.0001)
		"bpm": timing[i].beat = 60.0 / clampf(v, 20.0, 600.0)
		"meter": timing[i].meter = int(v)
	_set_song({"timing": timing}, {"t": "第一拍" if i == 0 else "变速位置", "bpm": "BPM", "meter": "拍号"}[field], coalesce, final)

func _first_beat_here() -> void:
	var timing := _timing_copy()
	var t: float = snappedf(app.cursor, 0.0001)
	if timing.size() > 1 and t >= float(timing[1].t) - 0.01: app.report({"error": "播放头在第二段之后；第一拍要放在第一次变速之前"}); return
	timing[0].t = t
	_commit({"timing": timing}, "设为第一拍")

func _add_change() -> void:
	var timing := _timing_copy()
	var t: float = snappedf(app.cursor, 0.0001)
	var cur: Dictionary = timing[0]
	for s in timing:
		if s.t <= t: cur = s
	for s in timing:
		if absf(s.t - t) < 0.01: app.report({"error": "这里已经有一次变速了，直接改它的 BPM"}); return
	timing.append({"t": t, "beat": cur.beat, "meter": cur.meter})
	_commit({"timing": timing}, "在 %s 变速" % doc.position(t).bar_beat.get_slice("+", 0))

func _remove_segment(i: int) -> void:
	var timing := _timing_copy()
	if i <= 0 or i >= timing.size(): return
	timing.remove_at(i)
	_commit({"timing": timing}, "删除变速")

func _tap() -> void:
	var now := Time.get_ticks_usec() / 1e6
	if not taps.is_empty() and now - taps[-1] > 2.0: taps = []
	taps.append(now)
	if taps.size() > 12: taps.pop_front()
	if taps.size() < 4: tap_label.text = "再点 %d 下" % (4 - taps.size()); return
	var gaps := []
	for k in range(1, taps.size()): gaps.append(taps[k] - taps[k - 1])
	gaps.sort()
	var bpm := snappedf(60.0 / gaps[gaps.size() / 2], 0.1)
	var timing := _timing_copy()
	var at := 0
	for k in timing.size():
		if timing[k].t <= app.cursor: at = k
	timing[at].beat = 60.0 / clampf(bpm, 20.0, 600.0)
	tap_label.text = "%s BPM（%d 下）" % [String.num(bpm, 1), taps.size()]
	_commit({"timing": timing}, "敲击定速", "song-tap-%d" % int(taps[0] * 1000))

## ------------------------------------------------------------------ the two explicit whole-chart actions
func _retime_dialog() -> void:
	var counts := [doc.raw.notes.size(), doc.raw.lights.size(), doc.raw.get("fx", []).size()]
	var shapes: int = doc.ext.get("shapes", {}).size()
	var ask := ConfirmationDialog.new(); ask.title = "让 note 跟着新节拍移动"
	ask.dialog_text = "把 %d 个音符、%d 个轨道事件、%d 个镜头事件从原来的网格（%s）换算到现在的网格（%s），每个事件保持它的小节和拍位置。\n只有整张谱面原本按错的网格写时才需要这样做。可以撤销。" % [counts[0], counts[1], counts[2], Timing.bpm_text(baseline), Timing.bpm_text(doc.timing())]
	if shapes > 0: ask.dialog_text += "\n有 %d 条只保存在编辑器里的精确轨道形状，会改回游戏里的近似外形。" % shapes
	ask.ok_button_text = "移动全部事件"; ask.cancel_button_text = "取消"
	app.add_child(ask); ask.popup_centered(Vector2i(560, 220))
	ask.confirmed.connect(func(): retime_to_grid(); ask.queue_free()); ask.canceled.connect(ask.queue_free)

## Re-time every event from the baseline grid to the current one (one undo step).
func retime_to_grid() -> bool:
	var moved: Dictionary = Timing.retime(doc.raw, baseline, doc.timing())
	var ext: Dictionary = Timing.rekey_motions(doc.ext, doc.raw.notes, moved.notes)
	ext.shapes = {}
	if _commit({"notes": moved.notes, "lights": moved.lights, "fx": moved.get("fx", []), "meta": moved.get("meta", {})}, "让 note 跟着新节拍移动", "", ext):
		baseline = doc.timing().duplicate(true); sync(); app._say("全部事件已按新网格移动，小节和拍位置不变"); return true
	return false

func _shift_dialog() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "整体平移谱面"; dialog.ok_button_text = "平移"; dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 10); dialog.add_child(box)
	var l := Label.new(); l.text = "音频和整张谱面（音符、轨道、镜头、节拍）一起移动，相互对齐不变，只是片头留白变长或变短。"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 440; box.add_child(l)
	var d := W.ScrubField.new("平移", "秒", 0.01); d.formatter = func(x): return "%+.3f" % x
	d.set_value(0.0); box.add_child(d)
	app.add_child(dialog); dialog.popup_centered(Vector2i(500, 200))
	dialog.confirmed.connect(func(): shift_chart(float(d.value)); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free)

func shift_chart(d: float) -> bool:
	if absf(d) < 0.0001: return false
	var moved: Dictionary = Timing.shift(doc.raw, d)
	if moved.has("error"): app.report(moved); return false
	var ext: Dictionary = Timing.rekey_motions(doc.ext, doc.raw.notes, moved.notes)
	ext.shapes = {}
	var ok := _commit({"notes": moved.notes, "lights": moved.lights, "fx": moved.get("fx", []), "meta": moved.get("meta", {}), "timing": moved.timing, "offset": moved.offset}, "整体平移谱面 %+.3f 秒" % d, "", ext)
	if ok:
		baseline = Timing.shift({"timing": baseline, "notes": [], "lights": []}, d).timing if not baseline.is_empty() else baseline
		app.seek(app.cursor + d); sync()
	return ok

## ------------------------------------------------------------------ meta
func _meta_text(text: String, key: String) -> void:
	_set_meta(key, text.strip_edges().to_upper() if key == "difficulty" else text.strip_edges(), {"title": "歌名", "artist": "作者", "difficulty": "难度名"}[key])

func _set_meta(key: String, value, label: String) -> void:
	var meta: Dictionary = doc.raw.get("meta", {}).duplicate(true)
	if meta.get(key, null) == value or (value is String and value.is_empty() and not meta.has(key)): return
	meta[key] = value
	var result: Dictionary = doc.edit({"expected_revision": doc.revision(), "label": label, "ops": [{"target": "meta", "value": meta}]})
	if result.has("error"): app.report(result)

## ------------------------------------------------------------------ waveform with beat lines
func _peaks() -> PackedFloat32Array:
	var path: String = app.api.audio_path()
	if path.is_empty(): return PackedFloat32Array()
	var mt := FileAccess.get_modified_time(path)
	if not _peaks_cache.has(path) or _peaks_cache[path][0] != mt: _peaks_cache[path] = [mt, Lib.peaks(path, PEAK_STEP)]
	return _peaks_cache[path][1]

func _lo() -> float: return app.cursor - view_span * 0.25
func _x(t: float) -> float: return (t - _lo()) / view_span * wave.size.x

func _process(_dt: float) -> void:
	if is_visible_in_tree() and app != null and app.playing: wave.queue_redraw()

func _draw_wave() -> void:
	var tk := Tokens.tokens()
	wave.draw_style_box(Tokens.box(tk.canvas, 8, tk.border), Rect2(Vector2.ZERO, wave.size))
	var h := wave.size.y; var mid := h * 0.55
	var peaks := _peaks()
	var off := float(doc.raw.get("offset", 0.0))
	var lo := _lo(); var hi := lo + view_span
	var i0 := maxi(0, int((lo - off) / PEAK_STEP)); var i1 := mini(peaks.size(), int((hi - off) / PEAK_STEP) + 1)
	var lw := maxf(1.0, wave.size.x / view_span * PEAK_STEP)
	for i in range(i0, i1):
		var x := _x(off + i * PEAK_STEP)
		wave.draw_line(Vector2(x, mid - peaks[i] * h * 0.36), Vector2(x, mid + peaks[i] * h * 0.36), Color(tk.text, 0.3), lw)
	var num := Tokens.font("num", 600)
	for pos in doc.grid(maxf(-2.0, lo), hi, 4):
		var on_bar: bool = absf(pos.beat - 1.0) < 0.01
		var x := _x(pos.seconds)
		wave.draw_line(Vector2(x, 18), Vector2(x, h), Color(tk.clay, 0.55 if on_bar else 0.2), 1.0)
		if on_bar: wave.draw_string(num, Vector2(x + 4, 14), str(int(pos.bar)), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.clay)
	for s in doc.timing():
		if s.t >= lo and s.t <= hi: wave.draw_line(Vector2(_x(s.t), 0), Vector2(_x(s.t), h), tk.clay, 2.0)
	var px := _x(app.cursor)
	wave.draw_line(Vector2(px, 0), Vector2(px, h), tk.text, 1.5)

func _wave_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT: app.seek(maxf(0.0, _lo() + e.position.x / maxf(1.0, wave.size.x) * view_span))
			MOUSE_BUTTON_WHEEL_UP: view_span = maxf(2.0, view_span * 0.8)
			MOUSE_BUTTON_WHEEL_DOWN: view_span = minf(40.0, view_span * 1.25)
		wave.queue_redraw(); wave.accept_event()
