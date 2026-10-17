extends VBoxContainer
## Contextual inspector: shows only what the current selection needs (notes, a track, outline
## nodes, a camera event, or a quiet song summary). Every change applies immediately as one
## undo step per gesture; wheel / arrows / scrub-drag adjust, typing commits on Enter or blur.

const U = preload("res://ui/ui_util.gd")
const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Ops = preload("res://edit_ops.gd")
const Adapter = preload("res://track_adapter.gd")
const Motion = preload("res://note_motion.gd")
const Vocab = preload("res://vocabulary.gd")
const SongSettings = preload("res://ui/song_settings.gd")
const ROLE_NAMES := {"carrier": "承载轨", "performer": "演出轨", "background": "背景", "cue": "踏板"}
const CAMERA_EASES := ["linear", "inQuad", "outQuad", "inOutSine", "outBack"]
const CAMERA_EASE_WORDS := ["匀速", "渐快", "渐慢", "缓入缓出", "回弹"]
const SPEED_WORDS := ["瞬切", "急", "中", "缓", "极缓"]

var doc
var timeline
var app
var sig := ""
var fields: Dictionary = {}
var head := VBoxContainer.new()
var flow := HFlowContainer.new()
var foot := VBoxContainer.new()
var song_page

func _ready() -> void:
	add_theme_constant_override("separation", 14)
	add_child(head); head.add_theme_constant_override("separation", 4)
	flow.add_theme_constant_override("h_separation", 32); flow.add_theme_constant_override("v_separation", 6)
	add_child(flow)
	add_child(foot); foot.add_theme_constant_override("separation", 8)

func _clear() -> void:
	for box in [head, flow, foot]:
		for c in box.get_children(): box.remove_child(c); c.queue_free()
	fields = {}; song_page = null

func _signature() -> String:
	if doc == null or doc.raw.is_empty(): return "empty"
	if not timeline.sel_nodes.is_empty() and not timeline.work.is_empty(): return "nodes:%d:%s" % [timeline.work.id, JSON.stringify(timeline.sel_nodes)]
	if not doc.selection.get("notes", []).is_empty(): return "notes:" + JSON.stringify(doc.selection.notes)
	if not doc.selection.get("fx", []).is_empty() and doc.selection.get("tracks", []).is_empty(): return "fx:" + JSON.stringify(doc.selection.fx)
	if not doc.selection.get("tracks", []).is_empty(): return "track:%d" % int(doc.selection.tracks[0])
	return "none"

func refresh(force := false) -> void:
	var s := _signature()
	if s != sig or force:
		sig = s; _clear()
		match s.get_slice(":", 0):
			"nodes": _build_nodes()
			"notes": _build_notes()
			"fx": _build_fx()
			"track": _build_track()
			_: _build_empty()
	_update()

## ------------------------------------------------------------------ building blocks
## Heading of the inspector: what is selected (16 semibold), then one plain sentence about it.
func _title(text: String, sub: String = "", chip: Color = Color.TRANSPARENT, outline := false) -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); head.add_child(row)
	if chip.a > 0:
		var dot := Control.new(); dot.custom_minimum_size = Vector2(16, 24)
		dot.draw.connect(func():
			if outline: dot.draw_arc(Vector2(8, 12), 6, 0, TAU, 20, chip, 2.0, true)
			else: dot.draw_circle(Vector2(8, 12), 7, chip, true, -1, true))
		row.add_child(dot)
	var l := Label.new(); l.text = text; l.theme_type_variation = "Heading"; U.bounded_label(l, 112); l.add_theme_font_override("font", Tokens.font("num", 600)); row.add_child(l)
	if not sub.is_empty():
		var m := Label.new(); m.text = sub; m.theme_type_variation = "Muted"; m.clip_text = true; m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(m)

## A row of small facts: value on top (tabular figures), what it is underneath.
func _facts(pairs: Array, parent: Control = null) -> Dictionary:
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 24); row.add_theme_constant_override("v_separation", 8)
	(parent if parent != null else foot).add_child(row)
	var values := {}
	for pair in pairs:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		var a := Label.new(); a.text = str(pair[1]); a.theme_type_variation = "Num"; U.bounded_label(a, 136, true)
		var b := Label.new(); b.text = pair[0]; b.theme_type_variation = "Faint"
		v.add_child(a); v.add_child(b); row.add_child(v)
		values[pair[0]] = a
	return values

## The dock is 320-560 wide: cells fill one column when narrow and flow into two when wide.
func _cell(control: Control, width := 280.0) -> Control:
	control.custom_minimum_size.x = width
	flow.add_child(control)
	return control

func _note_line(text: String) -> Label:
	var l := Label.new(); l.text = text; l.theme_type_variation = "Faint"; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(l); return l

func _commit(args: Dictionary) -> bool:
	args["expected_revision"] = doc.revision()
	var result: Dictionary = doc.edit(args)
	if result.has("error"):
		timeline.say(Ops.explain(result)); refresh(true); return false
	return true

func time_text(t: float) -> String:
	return "%s  (%.3f s)" % [Ops.pretty(doc, t), t]

func parse_time(text: String) -> float:
	var s := text.strip_edges().split(" ")[0]
	if s.ends_with("s"): s = s.trim_suffix("s")
	if s.count(".") == 1 and not s.contains("+") and s.is_valid_float() and s.length() > 0:
		# "44.1" is read as bar.beat when it is a valid position; "55.268" as seconds
		var parts := s.split(".")
		if parts[1].length() == 1 and int(parts[1]) >= 1 and int(parts[1]) <= 9:
			var as_bar: float = doc.seconds(s)
			if is_finite(as_bar): return as_bar
		return s.to_float()
	var v: float = doc.seconds(s)
	return v if is_finite(v) else (s.to_float() if s.is_valid_float() else NAN)

## ------------------------------------------------------------------ nothing selected
func _build_empty() -> void:
	if doc == null or doc.raw.is_empty(): return
	var info: Dictionary = app.api.call_tool("song_info", {})
	var t := Label.new(); t.text = str(info.get("title", "")); t.theme_type_variation = "Display"; t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; head.add_child(t)
	if not str(info.get("artist", "")).is_empty():
		var a := Label.new(); a.text = str(info.get("artist", "")); a.theme_type_variation = "Muted"; U.bounded_label(a); head.add_child(a)
	var facts := HFlowContainer.new(); facts.add_theme_constant_override("h_separation", 28); facts.add_theme_constant_override("v_separation", 8)
	facts.custom_minimum_size.x = 280; flow.add_child(facts)
	var bpm := 60.0 / float(doc.timing()[0].beat)
	for pair in [["BPM", "%.0f" % bpm], ["时长", "%d:%02d" % [int(doc.core.end_time) / 60, int(doc.core.end_time) % 60]], ["音符", str(doc.raw.notes.size())], ["轨道", str(doc.core.tl.size())], ["小节", str(int(info.get("bar_count", 0)))]]:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		var a := Label.new(); a.text = pair[1]; a.add_theme_font_override("font", Tokens.font("serif")); a.add_theme_font_size_override("font_size", Tokens.LG)
		var b := Label.new(); b.text = pair[0]; b.theme_type_variation = "Faint"
		v.add_child(a); v.add_child(b); facts.add_child(v)
	# 歌曲设置: name, audio, offset and the tempo map of the open song
	song_page = SongSettings.new(); song_page.app = app; song_page.doc = doc
	foot.add_child(song_page); song_page.build()

## ------------------------------------------------------------------ notes
func _sel_notes() -> Array:
	var out := []
	for i in doc.selection.notes:
		if int(i) < doc.raw.notes.size(): out.append(int(i))
	return out

func _build_notes() -> void:
	var ids := _sel_notes()
	if ids.is_empty(): _build_empty(); return
	var first: Dictionary = doc.raw.notes[ids[0]]
	if ids.size() == 1: _title("音符 %d" % ids[0], "落在 %s 键，轨道 %d 承载" % [Ops.key_name(Ops.note_key(first)), int(first.light)])
	else: _title("%d 个音符" % ids.size(), "改动同时作用于全部所选")
	var time := W.ScrubField.new("时间", "", 0.125)
	time.formatter = func(v): return time_text(v)
	time.parser = parse_time
	time.changed.connect(func(v, final): _move_notes(v - float(doc.raw.notes[_sel_notes()[0]].t), 0, "insp-time-%d" % time.gesture, final))
	fields.time = _cell(time)
	var key := W.EnumField.new("落键", Array(Ops.KEYS.split("", false)))
	key.changed.connect(func(i): _move_notes(0.0, i - Ops.note_key(doc.raw.notes[_sel_notes()[0]]), "", true))
	fields.key = _cell(key)
	var kind_row := HBoxContainer.new()
	var kl := Label.new(); kl.text = "类型"; kl.theme_type_variation = "Muted"; kl.custom_minimum_size.x = W.LABEL_W; kind_row.add_child(kl)
	var kind := W.Segmented.new(["点按", "长按"], 0); kind_row.add_child(kind)
	kind.changed.connect(_set_kind)
	fields.kind = kind; _cell(kind_row)
	var dur := W.ScrubField.new("时长", "拍", 0.25)
	dur.formatter = func(v): return String.num(v, 3)
	dur.min_value = 0.0625
	dur.changed.connect(func(v, final): _set_dur(v, "insp-dur-%d" % dur.gesture, final))
	fields.dur = _cell(dur)
	var marks := HBoxContainer.new()
	var ml := Label.new(); ml.text = "标记"; ml.theme_type_variation = "Muted"; ml.custom_minimum_size.x = W.LABEL_W; marks.add_child(ml)
	var big := W.IconButton.new("note", "大音符：占满轨道宽度", "大音符"); big.toggle_mode = true; marks.add_child(big)
	var ex := W.IconButton.new("note", "EX 音符：黄键，需要按住保护", "EX"); ex.toggle_mode = true; marks.add_child(ex)
	big.toggled.connect(func(on): _set_flag("big", on)); ex.toggled.connect(func(on): _set_flag("ex", on))
	fields.big = big; fields.ex = ex; _cell(marks)
	# motion (stored in chart.ext.json until the engine supports it)
	var names := ["直落"]
	for t in Motion.types(): names.append(t.LABEL)
	var motion := W.EnumField.new("运动", names)
	motion.changed.connect(func(i): timeline.set_motion(i); refresh(true))
	fields.motion = _cell(motion)
	var m := _motion_of(ids[0])
	if not m.is_empty():
		var mt = Motion.find(str(m.type))
		if mt != null:
			for p in mt.params():
				var key_name: String = p.key
				if p.has("options"):
					var ef := W.EnumField.new(p.label, p.options)
					ef.changed.connect(func(i): _set_motion_param(key_name, p.options[i]))
					fields["m_" + key_name] = _cell(ef)
				else:
					var sf := W.ScrubField.new(p.label, p.get("unit", ""), float(p.step))
					sf.min_value = float(p.min); sf.max_value = float(p.max)
					sf.formatter = func(v): return String.num(v, 2)
					sf.changed.connect(func(v, final): if final: _set_motion_param(key_name, v))
					fields["m_" + key_name] = _cell(sf)
			if ids.size() > 1 and mt.ID == "horizontal":
				var spread := W.IconButton.new("motion", "每个音符从所选音符的中心出发，向两侧展开", "从中心展开")
				spread.pressed.connect(_spread_from_centre)
				_cell(spread, 160)
		_note_line("运动保存在 chart.ext.json。引擎支持之前，只在时间线上显示轨迹；拖动起点圆点可以调整。")
	fields.readout = _facts([["判定窗", "–"], ["tick", "–"], ["演奏手", "–"], ["承载轨道", "–"]])

func _motion_of(i: int) -> Dictionary:
	return doc.ext.motions.get(Ops.motion_key(doc.raw.notes[i]), {})

func _update_notes() -> void:
	var ids := _sel_notes()
	if ids.is_empty(): return
	var first: Dictionary = doc.raw.notes[ids[0]]
	var same := func(field: String, default_value) -> bool:
		for i in ids:
			if doc.raw.notes[i].get(field, default_value) != first.get(field, default_value): return false
		return true
	fields.time.step = timeline.step_seconds(float(first.t))
	fields.time.set_value(float(first.t), ids.size() > 1 and not same.call("t", 0.0))
	fields.key.set_index(maxi(0, Ops.note_key(first)), ids.size() > 1 and not same.call("k", -1))
	fields.kind.set_index(1 if first.get("kind", "tap") == "hold" else 0)
	var beat: float = doc.position(float(first.t)).beat_seconds
	fields.dur.visible = first.get("kind", "tap") == "hold"
	fields.dur.step = timeline.step_seconds(float(first.t)) / beat
	fields.dur.set_value(float(first.get("dur", 0.0)) / beat, ids.size() > 1 and not same.call("dur", 0.0))
	fields.big.set_pressed_no_signal(first.get("big", false)); fields.big.queue_redraw()
	fields.ex.set_pressed_no_signal(first.get("ex", false)); fields.ex.queue_redraw()
	var m := _motion_of(ids[0])
	var types := Motion.types()
	var mi := 0
	for k in types.size():
		if not m.is_empty() and types[k].ID == m.type: mi = k + 1
	fields.motion.set_index(mi)
	if not m.is_empty():
		var p: Dictionary = Motion.defaults(str(m.type)); p.merge(m.get("params", {}), true)
		for key in p:
			if fields.has("m_" + key):
				var f = fields["m_" + key]
				if f is W.EnumField: f.set_index(maxi(0, f.options.find(p[key])))
				else: f.set_value(float(p[key]))
	var core_note := {}
	for n in doc.core.notes:
		if n.get("raw_id", -1) == ids[0]: core_note = n
	if not core_note.is_empty():
		var r: Dictionary = fields.readout
		r["判定窗"].text = "−%.0f / +%.0f ms" % [core_note.w_e * 1000, core_note.w_l * 1000]
		r["tick"].text = str(core_note.ticks.size())
		r["演奏手"].text = "左手" if int(core_note.k) <= 4 else "右手"
		r["承载轨道"].text = str(int(core_note.light))

var _last_live := 0
## Live scrubs commit at most every 140 ms (a full rule check costs ~0.1 s on a big chart);
## the release always commits, all of it merged into one undo step.
func _throttled(final: bool) -> bool:
	var now := Time.get_ticks_msec()
	if not final and now - _last_live < 140: return true
	_last_live = now
	return false

func _move_notes(dt: float, dk: int, coalesce: String, final: bool) -> void:
	if _throttled(final): return
	var res := Ops.move_notes(doc, _sel_notes(), dt, dk, false, timeline.locked_tracks)
	if not res.ok: timeline.say(res.reason); _update(); return
	_commit({"label": "音符时间" if dk == 0 else "音符落键", "ops": res.ops, "ext": res.ext, "coalesce": coalesce})

func _set_kind(i: int) -> void:
	var ops := []
	for id in _sel_notes():
		var n: Dictionary = doc.raw.notes[id]
		var beat: float = doc.position(float(n.t)).beat_seconds
		ops.append({"target": "notes", "op": "update", "index": id, "value": {"kind": "hold", "dur": Adapter.num(maxf(float(n.get("dur", 0)), beat))} if i == 1 else {"kind": "tap", "dur": 0}})
	_commit({"label": "转为长按" if i == 1 else "转为点按", "ops": ops})

func _set_dur(beats: float, coalesce: String, final: bool) -> void:
	if _throttled(final): return
	var ops := []
	for id in _sel_notes():
		var n: Dictionary = doc.raw.notes[id]
		ops.append({"target": "notes", "op": "update", "index": id, "value": {"kind": "hold", "dur": Adapter.num(beats * doc.position(float(n.t)).beat_seconds)}})
	_commit({"label": "长按长度", "ops": ops, "coalesce": coalesce})

func _set_flag(field: String, on: bool) -> void:
	var ops := []
	for id in _sel_notes(): ops.append({"target": "notes", "op": "update", "index": id, "value": {field: on}})
	_commit({"label": "大音符" if field == "big" else "EX", "ops": ops})

func _set_motion_param(key: String, value) -> void:
	var ext: Dictionary = doc.ext.duplicate(true)
	for id in _sel_notes():
		var k := Ops.motion_key(doc.raw.notes[id])
		if ext.motions.has(k): ext.motions[k].params[key] = value
	_commit({"label": "音符运动参数", "ops": [], "ext": ext, "coalesce": "motion-" + key})

func _spread_from_centre() -> void:
	var ids := _sel_notes(); var xs := []
	for nv in timeline.notes_view:
		if nv.i in ids: xs.append(nv.x)
	if xs.is_empty(): return
	var centre: float = (xs.min() + xs.max()) / 2.0
	var ext: Dictionary = doc.ext.duplicate(true)
	for nv in timeline.notes_view:
		if not nv.i in ids: continue
		var k := Ops.motion_key(doc.raw.notes[nv.i])
		if ext.motions.has(k): ext.motions[k].params["from"] = snappedf((centre - nv.x) * 15.0, 0.25)
	_commit({"label": "运动：从中心展开", "ops": [], "ext": ext})

## ------------------------------------------------------------------ track
func _build_track() -> void:
	var id := int(doc.selection.tracks[0])
	if not timeline.tracks_view.has(id): _build_empty(); return
	var tv: Dictionary = timeline.tracks_view[id]
	var shapes: Array = tv.shapes
	var first_tint := -1
	if not shapes.is_empty() and not shapes[0].props.is_empty(): first_tint = int(shapes[0].props[0].tint)
	_title("轨道 %d" % id, ROLE_NAMES.get(tv.role, "") + ("，透明" if tv.transparent else ""), Tokens.tint(first_tint), tv.transparent)
	var opacity_row := VBoxContainer.new()
	var ol := HBoxContainer.new(); opacity_row.add_child(ol)
	var oll := Label.new(); oll.text = "不透明度"; oll.theme_type_variation = "Muted"; oll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ol.add_child(oll)
	var ov := Label.new(); ov.theme_type_variation = "Num"; U.bounded_label(ov, 88, true); ol.add_child(ov); fields.opacity_value = ov
	var opacity := W.Scale01.new(1.0); opacity_row.add_child(opacity)
	opacity.changed.connect(func(v, final):
		ov.text = String.num(v, 2)
		if final: _commit_track({"a": v}, "轨道不透明度", "track-a-%d" % opacity.gesture))
	fields.opacity = opacity; _cell(opacity_row)
	var tint_row := VBoxContainer.new()
	var tl := Label.new(); tl.text = "色调"; tl.theme_type_variation = "Muted"; tint_row.add_child(tl)
	var sw := W.Swatches.new(first_tint); tint_row.add_child(sw)
	sw.changed.connect(func(v): _commit_track({"tint": v}, "轨道色调", "track-tint"))
	fields.tint = sw; _cell(tint_row)
	var actions := HFlowContainer.new()
	var hide_b := W.IconButton.new("eye_off" if timeline.hidden_tracks.get(id, false) else "eye", "在时间线上隐藏或显示", "隐藏" if not timeline.hidden_tracks.get(id, false) else "显示")
	hide_b.pressed.connect(func(): timeline.hidden_tracks[id] = not timeline.hidden_tracks.get(id, false); timeline.refresh(true); app.refresh_side(); refresh(true))
	var solo := W.IconButton.new("solo", "只显示这条轨道", "独奏"); solo.active = timeline.solo == id
	solo.pressed.connect(func(): timeline.solo = -1 if timeline.solo == id else id; timeline.refresh(true); app.refresh_side(); refresh(true))
	var lock := W.IconButton.new("lock" if timeline.locked_tracks.get(id, false) else "unlock", "锁定后不能编辑这条轨道", "锁定"); lock.active = timeline.locked_tracks.get(id, false)
	lock.pressed.connect(func(): timeline.locked_tracks[id] = not timeline.locked_tracks.get(id, false); app.refresh_side(); refresh(true))
	var delete := W.IconButton.new("trash", "删除这条轨道（轨道上不能有音符）", "删除"); delete.pressed.connect(func(): if timeline.report(Ops.delete_track(doc, id)): timeline.set_selection([], []))
	for b in [hide_b, solo, lock, delete]: actions.add_child(b)
	_cell(actions, 280)
	var lifetimes: Array = Ops.lifetimes(doc, id)
	var shown := ""
	if not lifetimes.is_empty():
		var r0: Array = lifetimes[0]
		var end0: float = r0[1] if is_finite(r0[1]) else doc.core.end_time
		shown = "%s–%s" % [Ops.pretty(doc, r0[0]), Ops.pretty(doc, end0)]
		if lifetimes.size() > 1: shown += "  另 %d 段" % (lifetimes.size() - 1)
	_facts([["出现", shown], ["音符", str(tv.count)], ["关键帧", str(Ops.track_events(doc, id).size())]])
	if not tv.exact:
		var warn := _note_line("游戏暂时按外轮廓近似显示这个形状；精确形状保存在 chart.ext.json，等引擎支持新轨道语法。")
		warn.add_theme_color_override("font_color", Tokens.CLAY)
	_note_line("拖节点改形状，拖边线调宽窄，拖主体整体移动；Ctrl 点两个节点可设置这一段。")

func _commit_track(values: Dictionary, label: String, coalesce: String) -> void:
	var id := int(doc.selection.tracks[0])
	if timeline.locked_tracks.get(id, false): timeline.say("轨道已锁定"); return
	var result := Ops.set_track_props(doc, id, values, label, coalesce)
	if result.has("error"): timeline.say(Ops.explain(result))
	timeline.select_track(id, true)

func _update_track() -> void:
	var id := int(doc.selection.tracks[0])
	if not timeline.tracks_view.has(id): return
	var shapes: Array = timeline.tracks_view[id].shapes
	var a_vals := {}; var tints := {}
	for s in shapes:
		for p in s.props: a_vals[snappedf(maxf(0.0, float(p.a)) if p.a >= 0 else 1.0, 0.001)] = true; tints[int(p.tint)] = true
	var a_mixed := a_vals.size() > 1
	var a_val: float = a_vals.keys()[0] if not a_vals.is_empty() else 1.0
	fields.opacity.set_value(a_val, a_mixed)
	fields.opacity_value.text = "随时间变化" if a_mixed else String.num(a_val, 2)
	fields.tint.set_value(tints.keys()[0] if not tints.is_empty() else -1, tints.size() > 1)

## ------------------------------------------------------------------ outline nodes
func _build_nodes() -> void:
	var nodes: Array = timeline.sel_nodes
	_title("%d 个节点" % nodes.size() if nodes.size() > 1 else "节点", "轨道 %d" % timeline.work.id, Tokens.CLAY)
	var pos := W.ScrubField.new("位置", "键", 0.25)
	pos.formatter = func(v): return String.num(v, 2)
	pos.changed.connect(func(v, final):
		var s = timeline.work.shapes[timeline.sel_nodes[0].s]
		var dx: float = v / 15.0 - s.nodes[timeline.sel_nodes[0].n].x
		if final: timeline.nudge_nodes(dx, 0.0))
	fields.pos = _cell(pos)
	var time := W.ScrubField.new("时间", "", 0.125)
	time.formatter = func(v): return time_text(v)
	time.parser = parse_time
	time.changed.connect(func(v, final):
		var s = timeline.work.shapes[timeline.sel_nodes[0].s]
		var dt: float = v - s.nodes[timeline.sel_nodes[0].n].t
		if final and absf(dt) > 1e-9: timeline.nudge_nodes(0.0, dt))
	fields.time = _cell(time)
	var style_row := HBoxContainer.new()
	var sl := Label.new(); sl.text = "节点"; sl.theme_type_variation = "Muted"; sl.custom_minimum_size.x = W.LABEL_W; style_row.add_child(sl)
	var style := W.Segmented.new(["尖角", "平滑"], 0); style_row.add_child(style)
	style.changed.connect(func(i):
		var sn = timeline.sel_nodes
		timeline.segment_op(sn[0].s, sn[0].n, sn[-1].n, "smooth" if i == 1 else "corner"))
	fields.style = style; _cell(style_row)
	var actions := HBoxContainer.new()
	if nodes.size() == 2:
		var seg := W.IconButton.new("curve", "设置这两个节点之间的一段（Enter）", "设置这一段")
		seg.pressed.connect(func(): timeline.popover_requested.emit(nodes[0].s, nodes[0].n, nodes[1].n)); actions.add_child(seg)
	var del := W.IconButton.new("trash", "删除所选节点（Delete）", "删除节点"); del.pressed.connect(timeline.delete_nodes); actions.add_child(del)
	_cell(actions, 280)
	_note_line("拖动时按住 Alt 关闭吸附，按住 Shift 锁定方向。↑↓ 按网格移动时间，←→ 每次移动 ¼ 键。")

func _update_nodes() -> void:
	if timeline.work.is_empty() or timeline.sel_nodes.is_empty(): return
	var sn: Dictionary = timeline.sel_nodes[0]
	if sn.s >= timeline.work.shapes.size(): return
	var s = timeline.work.shapes[sn.s]
	if sn.n >= s.size(): return
	fields.pos.set_value(s.nodes[sn.n].x * 15.0, timeline.sel_nodes.size() > 1)
	fields.time.step = timeline.step_seconds(s.nodes[sn.n].t)
	fields.time.set_value(s.nodes[sn.n].t, timeline.sel_nodes.size() > 1)
	fields.style.set_index(1 if s.nodes[sn.n].smooth else 0)

## ------------------------------------------------------------------ camera event
func _build_fx() -> void:
	var i := int(doc.selection.fx[0])
	if i >= doc.raw.get("fx", []).size(): _build_empty(); return
	var e: Dictionary = doc.raw.fx[i]
	var ch := str(e.get("ch", ""))
	var v: Dictionary = Vocab.data().get(ch, {})
	_title("镜头：" + str(v.get("label", ch)), str(v.get("meaning", "")))
	var time := W.ScrubField.new("时间", "", 0.125)
	time.formatter = func(x): return time_text(x)
	time.parser = parse_time
	time.changed.connect(func(x, final): if final: _set_fx({"t": Adapter.num(x)}, "镜头时间"))
	fields.time = _cell(time)
	if not v.is_empty():
		var words := []
		for l in v.levels: words.append(l.word)
		var level := W.EnumField.new("目标", words)
		level.changed.connect(func(k): _set_fx({"to" if e.get("type", "") == "tween" else "amp": v.levels[k].value}, "镜头目标"))
		fields.level = _cell(level)
		var value := W.ScrubField.new("数值", str(v.unit), (float(v.range[1]) - float(v.range[0])) / 40.0)
		value.min_value = float(v.range[0]); value.max_value = float(v.range[1])
		value.formatter = func(x): return String.num(x, 3)
		value.changed.connect(func(x, final): if final: _set_fx({"to" if e.get("type", "") == "tween" else "amp": Adapter.num(x)}, "镜头数值"))
		fields.value = _cell(value)
	var speed := W.EnumField.new("运动", SPEED_WORDS)
	speed.changed.connect(func(k):
		var beat: float = doc.position(float(e.t)).beat_seconds
		var d: float = [0.03, beat, beat * 2, beat * 4, beat * 8][k]
		_set_fx({"dur": Adapter.num(d)} if e.get("type", "") == "tween" else {"decay": Adapter.num(d)}, "镜头运动"))
	fields.speed = _cell(speed)
	if e.get("type", "") == "tween":
		var ease_f := W.EnumField.new("缓动", CAMERA_EASE_WORDS)
		ease_f.changed.connect(func(k): _set_fx({"ease": CAMERA_EASES[k]}, "镜头缓动"))
		fields.ease = _cell(ease_f)
	var del := W.IconButton.new("trash", "删除这个镜头事件", "删除")
	del.pressed.connect(func():
		if _commit({"label": "删除镜头事件", "ops": [{"target": "fx", "op": "delete", "index": i}]}): doc.selection.fx = []; refresh(true))
	_cell(del, 140)

func _set_fx(values: Dictionary, label: String) -> void:
	var i := int(doc.selection.fx[0])
	_commit({"label": label, "ops": [{"target": "fx", "op": "update", "index": i, "value": values}], "coalesce": "fx-%d-%s" % [i, label]})

func _update_fx() -> void:
	var i := int(doc.selection.fx[0])
	if i >= doc.raw.get("fx", []).size(): return
	var e: Dictionary = doc.raw.fx[i]
	fields.time.step = timeline.step_seconds(float(e.t)); fields.time.set_value(float(e.t))
	var v: Dictionary = Vocab.data().get(str(e.get("ch", "")), {})
	var num := float(e.get("to", e.get("amp", 0.0)))
	if fields.has("level"):
		var best := 0
		for k in v.levels.size():
			if absf(v.levels[k].value - num) < absf(v.levels[best].value - num): best = k
		fields.level.set_index(best); fields.value.set_value(num)
	var beat: float = doc.position(float(e.t)).beat_seconds
	var d := float(e.get("dur", e.get("decay", beat * 2)))
	var speeds := [0.03, beat, beat * 2, beat * 4, beat * 8]; var sp := 0
	for k in speeds.size():
		if absf(speeds[k] - d) < absf(speeds[sp] - d): sp = k
	fields.speed.set_index(sp)
	if fields.has("ease"): fields.ease.set_index(maxi(0, CAMERA_EASES.find(str(e.get("ease", "inOutSine")))))

func _update() -> void:
	if doc == null or doc.raw.is_empty(): return
	match sig.get_slice(":", 0):
		"notes": _update_notes()
		"track": _update_track()
		"nodes": _update_nodes()
		"fx": _update_fx()
		_:
			if song_page != null and is_instance_valid(song_page): song_page.sync()
