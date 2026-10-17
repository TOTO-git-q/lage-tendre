extends Control
## Horizontal property lanes over the time around the playhead.
##   mode "camera": camera and judgement-line channels as curves on their word scales
##                  (bands such as 极远 / 远 / 中 / 近 / 极近); keyframes are draggable dots,
##                  double-click adds one, right-click changes ease / speed / deletes.
##   mode "track":  centre, width, opacity and tint of the selected track over time; its
##                  keyframes drag up/down (value) and sideways (time).
## Wheel scrolls time, Ctrl+wheel zooms, Alt disables snapping while dragging.

signal seek(t: float)
signal picked

const Tokens = preload("res://theme.gd")
const Vocab = preload("res://vocabulary.gd")
const Ops = preload("res://edit_ops.gd")
const Adapter = preload("res://track_adapter.gd")
const LABEL_W := 108.0
const LANE_H := 96.0
const TOP := 22.0
const CAMERA_EASES := ["linear", "inQuad", "outQuad", "inOutSine", "outBack"]
const CAMERA_EASE_WORDS := ["匀速", "渐快", "渐慢", "缓入缓出", "回弹"]
const SPEED_WORDS := ["瞬切", "急", "中", "缓", "极缓"]
const TRACK_CHANNELS := {
	"x": {"label": "中心", "unit": "键", "range": [0.0, 15.0], "levels": [{"word": "A", "value": 2.25}, {"word": "F", "value": 5.25}, {"word": "G|H", "value": 7.5}, {"word": "J", "value": 8.25}, {"word": "'", "value": 12.25}]},
	"w": {"label": "宽度", "unit": "键", "range": [0.0, 15.0], "levels": [{"word": "1 键", "value": 1.0}, {"word": "3 键", "value": 3.0}, {"word": "6 键", "value": 6.0}, {"word": "全宽", "value": 15.0}]},
	"a": {"label": "不透明度", "unit": "", "range": [0.0, 1.0], "levels": [{"word": "0", "value": 0.0}, {"word": ".25", "value": 0.25}, {"word": ".5", "value": 0.5}, {"word": ".75", "value": 0.75}, {"word": "1", "value": 1.0}]},
	"tint": {"label": "色调", "unit": "", "range": [-1.0, 9.0], "levels": []},
}

var mode := "camera"
var doc
var timeline
var channels: Array = ["zoom", "vpx", "line_y", "line_glow"]
var span := 12.0
var cursor := 0.0
var drag: Dictionary = {}
var hover: Dictionary = {}
var menu := PopupMenu.new()
var ease_menu := PopupMenu.new()
var speed_menu := PopupMenu.new()
var _menu_index := -1

func _ready() -> void:
	clip_contents = true; focus_mode = Control.FOCUS_CLICK
	add_child(menu); ease_menu.name = "ease"; speed_menu.name = "speed"
	menu.add_child(ease_menu); menu.add_child(speed_menu)
	menu.id_pressed.connect(_menu); ease_menu.id_pressed.connect(func(i): _menu(100 + i)); speed_menu.id_pressed.connect(func(i): _menu(200 + i))
	mouse_exited.connect(func(): hover = {}; queue_redraw())

func lane_channels() -> Array:
	return TRACK_CHANNELS.keys() if mode == "track" else channels

func spec(ch: String) -> Dictionary:
	return TRACK_CHANNELS[ch] if mode == "track" else Vocab.data().get(ch, {})

func update_height() -> void:
	custom_minimum_size.y = TOP + lane_channels().size() * LANE_H + 6

func t0() -> float: return cursor - span * 0.15
func x_of(t: float) -> float: return LABEL_W + (t - t0()) / span * (size.x - LABEL_W - 8)
func time_at(x: float) -> float: return t0() + (x - LABEL_W) / maxf(1.0, size.x - LABEL_W - 8) * span
func lane_top(i: int) -> float: return TOP + i * LANE_H
func y_of(i: int, ch: String, v: float) -> float:
	var s := spec(ch); var lo := float(s.range[0]); var hi := float(s.range[1])
	return lane_top(i) + LANE_H - 10 - clampf((v - lo) / maxf(1e-9, hi - lo), 0, 1) * (LANE_H - 22)
func value_at(i: int, ch: String, y: float) -> float:
	var s := spec(ch); var lo := float(s.range[0]); var hi := float(s.range[1])
	return lo + clampf((lane_top(i) + LANE_H - 10 - y) / (LANE_H - 22), 0, 1) * (hi - lo)

func track_id() -> int:
	return int(doc.selection.tracks[0]) if doc != null and not doc.selection.get("tracks", []).is_empty() else -1

## ------------------------------------------------------------------ keyframes
func keyframes(i: int, ch: String) -> Array:
	var out := []
	if mode == "camera":
		for k in doc.raw.get("fx", []).size():
			var e: Dictionary = doc.raw.fx[k]
			if str(e.get("ch", "")) != ch: continue
			var t := float(e.t) + (float(e.get("dur", 0.0)) if e.get("type", "") == "tween" else 0.0)
			var v := float(e.get("to", e.get("amp", 0.0)))
			out.append({"index": k, "t": t, "start": float(e.t), "v": v, "p": Vector2(x_of(t), y_of(i, ch, v))})
	else:
		var id := track_id()
		if id < 0: return out
		for k in doc.raw.lights.size():
			var e: Dictionary = doc.raw.lights[k]
			if int(e.get("id", -1)) != id or not e.get("type", "") in ["on", "sweep"]: continue
			var t := float(e.t) + float(e.get("dur", 0.0))
			var st: Dictionary = doc.state_at(doc.core.tl.get(id, []), t + 1e-6)
			var v := 0.0
			match ch:
				"x": v = float(st.x) * 15.0
				"w": v = float(st.w) * 15.0
				"a": v = float(st.a) if st.a >= 0 else 1.0
				"tint": v = float(st.tint)
			var y := lane_top(i) + LANE_H / 2.0 if ch == "tint" else y_of(i, ch, v)
			out.append({"index": k, "t": t, "start": float(e.t), "v": v, "p": Vector2(x_of(t), y)})
	return out

func _hit(p: Vector2) -> Dictionary:
	var chs := lane_channels()
	var lane := int((p.y - TOP) / LANE_H)
	if lane < 0 or lane >= chs.size() or p.x < LABEL_W: return {}
	for kf in keyframes(lane, chs[lane]):
		if kf.p.distance_to(p) < 8: return {"lane": lane, "ch": chs[lane], "kf": kf}
	return {"lane": lane, "ch": chs[lane]}

## ------------------------------------------------------------------ input
func _gui_input(e: InputEvent) -> void:
	if doc == null or doc.raw.is_empty(): return
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := 1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if e.ctrl_pressed: span = clampf(span * pow(0.87, d), 2.0, 60.0); queue_redraw()
		else: seek.emit(maxf(0.0, cursor - d * span * 0.06))
		accept_event(); return
	if e is InputEventMouseMotion:
		if drag.is_empty(): hover = _hit(e.position)
		else:
			var t := time_at(e.position.x)
			drag.t = t if e.alt_pressed else timeline.snap_time(t)
			var v := value_at(drag.lane, drag.ch, e.position.y)
			if not e.alt_pressed: v = _snap_value(drag.lane, drag.ch, v, e.position.y)
			drag.v = v; drag.moved = true
		mouse_default_cursor_shape = Control.CURSOR_DRAG if hover.has("kf") else Control.CURSOR_ARROW
		queue_redraw(); return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			grab_focus()
			var h := _hit(e.position)
			if h.is_empty(): return
			if e.double_click and not h.has("kf"): _add(h.lane, h.ch, e.position); accept_event(); return
			if h.has("kf"):
				if mode == "camera":
					doc.selection.fx = [h.kf.index]; doc.selection.notes = []; doc.selection.tracks = []
					picked.emit()
				drag = {"lane": h.lane, "ch": h.ch, "kf": h.kf, "t": h.kf.t, "v": h.kf.v, "moved": false}
			accept_event()
		elif not drag.is_empty():
			var d := drag; drag = {}
			if d.moved: _commit_drag(d)
			queue_redraw()
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		var h := _hit(e.position)
		if h.has("kf"): _context(h, e.position)

func _snap_value(lane: int, ch: String, v: float, y: float) -> float:
	var s := spec(ch)
	if ch == "tint": return roundf(v)
	for l in s.get("levels", []):
		if absf(y_of(lane, ch, float(l.value)) - y) < 7: return float(l.value)
	if mode == "track": return snappedf(v, 0.25 if ch in ["x", "w"] else 0.05)
	return v

func _commit_drag(d: Dictionary) -> void:
	var kf: Dictionary = d.kf
	if mode == "camera":
		var e: Dictionary = doc.raw.fx[kf.index]
		var value := {}
		var dur := float(e.get("dur", 0.0)) if e.get("type", "") == "tween" else 0.0
		value.t = Adapter.num(maxf(0.0, d.t - dur))
		value["to" if e.get("type", "") == "tween" else "amp"] = Adapter.num(d.v)
		timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "镜头关键帧", "ops": [{"target": "fx", "op": "update", "index": kf.index, "value": value}]}))
	else:
		_track_event_edit(kf.index, d.ch, d.v, d.t)

func _track_event_edit(index: int, ch: String, v: float, t_end: float) -> void:
	var id := track_id()
	if timeline.locked_tracks.get(id, false): timeline.say("轨道已锁定"); return
	var e: Dictionary = doc.raw.lights[index].duplicate()
	var value := {}
	match ch:
		"x": value.x = Adapter.num(v / 15.0)
		"w": value.w = Adapter.num(maxf(1.0, v) / 15.0)
		"a": value.a = Adapter.num(clampf(v, 0, 1))
		"tint": value.tint = clampi(roundi(v), -1, 9)
	value.t = Adapter.num(maxf(0.0, t_end - float(e.get("dur", 0.0))))
	if not e.has("x"): value.erase("x")
	var after := []
	for k in doc.raw.lights.size():
		if k == index: var m := e.duplicate(); m.merge(value, true); after.append(m)
		else: after.append(doc.raw.lights[k])
	var ops := [{"target": "lights", "op": "update", "index": index, "value": value}]
	ops.append_array(Adapter.reseat_ops(doc, id, after))
	if timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "轨道" + TRACK_CHANNELS[ch].label, "ops": ops})): timeline.select_track(id)

func _add(lane: int, ch: String, p: Vector2) -> void:
	var t: float = timeline.snap_time(time_at(p.x))
	var v := _snap_value(lane, ch, value_at(lane, ch, p.y), p.y)
	if mode == "camera":
		var beat: float = doc.position(t).beat_seconds
		var event := {"t": Adapter.num(t), "type": "tween", "ch": ch, "to": Adapter.num(v), "dur": Adapter.num(beat * 2.0), "ease": "inOutSine"}
		if ch == "trauma": event = {"t": Adapter.num(t), "type": "impulse", "ch": ch, "amp": Adapter.num(v), "attack": 0.04, "decay": Adapter.num(beat * 2.0)}
		if timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "添加镜头关键帧", "ops": [{"target": "fx", "op": "add", "value": event}]})):
			doc.selection.fx = [doc.raw.fx.size() - 1]; doc.selection.notes = []; doc.selection.tracks = []; picked.emit()
	else:
		var id := track_id()
		if id < 0: return
		var st: Dictionary = doc.state_at(doc.core.tl.get(id, []), t)
		if not st.alive: timeline.say("轨道此时不存在"); return
		var event := {"t": Adapter.num(t), "id": id, "type": "sweep", "dur": Adapter.num(doc.position(t).beat_seconds), "x": Adapter.num(st.x), "w": Adapter.num(st.w), "auto": true}
		match ch:
			"x": event.x = Adapter.num(v / 15.0)
			"w": event.w = Adapter.num(maxf(1.0, v) / 15.0)
			"a": event.a = Adapter.num(clampf(v, 0, 1))
			"tint": event.tint = clampi(roundi(v), -1, 9)
		var after: Array = doc.raw.lights.duplicate(); after.append(event)
		var ops := [{"target": "lights", "op": "add", "value": event}]
		ops.append_array(Adapter.reseat_ops(doc, id, after))
		if timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "添加轨道关键帧", "ops": ops})): timeline.select_track(id)

func _context(h: Dictionary, p: Vector2) -> void:
	_menu_index = h.kf.index
	menu.clear(); ease_menu.clear(); speed_menu.clear()
	if mode == "camera":
		for i in CAMERA_EASE_WORDS.size(): ease_menu.add_item(CAMERA_EASE_WORDS[i], i)
		for i in SPEED_WORDS.size(): speed_menu.add_item(SPEED_WORDS[i], i)
		menu.add_submenu_node_item("缓动", ease_menu); menu.add_submenu_node_item("运动快慢", speed_menu)
		menu.add_separator(); menu.add_item("删除关键帧", 1)
	else:
		for i in 4: ease_menu.add_item(["缓入缓出", "匀速", "缓入", "缓出"][i], i)
		menu.add_submenu_node_item("缓动", ease_menu); menu.add_separator(); menu.add_item("删除关键帧", 1)
	menu.reset_size(); menu.popup(Rect2i(Vector2i(get_screen_position() + p), Vector2i.ZERO))

func _menu(id: int) -> void:
	if _menu_index < 0: return
	if mode == "camera":
		var e: Dictionary = doc.raw.fx[_menu_index]
		if id == 1: timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "删除镜头关键帧", "ops": [{"target": "fx", "op": "delete", "index": _menu_index}]})); doc.selection.fx = []; picked.emit(); return
		if id >= 200:
			var beat: float = doc.position(float(e.t)).beat_seconds
			var d: float = [0.03, beat, beat * 2, beat * 4, beat * 8][id - 200]
			timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "镜头运动", "ops": [{"target": "fx", "op": "update", "index": _menu_index, "value": {"dur": Adapter.num(d)} if e.get("type", "") == "tween" else {"decay": Adapter.num(d)}}]}))
		elif id >= 100:
			timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "镜头缓动", "ops": [{"target": "fx", "op": "update", "index": _menu_index, "value": {"ease": CAMERA_EASES[id - 100]}}]}))
	else:
		var e: Dictionary = doc.raw.lights[_menu_index]
		if id == 1:
			if e.type == "on": timeline.say("起始关键帧不能删除（删除整条轨道请用轨道菜单）"); return
			timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "删除轨道关键帧", "ops": [{"target": "lights", "op": "delete", "index": _menu_index}]}))
		elif id >= 100 and e.type == "sweep":
			timeline.report(doc.edit({"expected_revision": doc.revision(), "label": "轨道缓动", "ops": [{"target": "lights", "op": "update", "index": _menu_index, "value": {"ease": ["inout", "linear", "in", "out"][id - 100]}}]}))
		timeline.select_track(track_id())

## ------------------------------------------------------------------ drawing
func _draw() -> void:
	if doc == null or doc.raw.is_empty(): return
	var tk := Tokens.tokens()
	var sans := Tokens.font("sans"); var semi := Tokens.font("sans", 600); var mono := Tokens.font("mono"); var num := Tokens.font("num")
	var chs := lane_channels()
	var lo := t0(); var hi := lo + span
	if mode == "track" and track_id() < 0:
		draw_string(sans, Vector2(LABEL_W, 44), "选择一条轨道，这里显示它的中心、宽度、不透明度和色调随时间的变化。", HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.muted)
		return
	# bar lines and labels
	for pos in doc.grid(maxf(0, lo), hi, 1):
		var x := x_of(pos.seconds)
		draw_line(Vector2(x, TOP - 4), Vector2(x, size.y), Color(tk.text, 0.08), 1)
		draw_string(num, Vector2(x + 4, 14), str(int(pos.bar)), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.muted)
	for i in chs.size():
		var ch: String = chs[i]; var s := spec(ch)
		var top := lane_top(i)
		if s.is_empty(): continue
		draw_line(Vector2(0, top), Vector2(size.x, top), tk.border, 1)
		draw_string(semi, Vector2(4, top + 22), str(s.get("label", ch)), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8, Tokens.BODY, tk.text)
		draw_string(mono, Vector2(4, top + 40), ch if mode == "camera" else str(s.unit), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8, Tokens.XS, tk.faint)
		# word bands
		var levels: Array = s.get("levels", [])
		var last_label_y := INF
		for k in levels.size():
			var y := y_of(i, ch, float(levels[k].value))
			var y_prev := y_of(i, ch, float(levels[k - 1].value)) if k > 0 else y + 10
			var y_next := y_of(i, ch, float(levels[k + 1].value)) if k + 1 < levels.size() else y - 10
			var band_top := (y + y_next) / 2.0; var band_bottom := (y + y_prev) / 2.0
			if k % 2 == 0: draw_rect(Rect2(LABEL_W, band_top, size.x - LABEL_W, band_bottom - band_top), Color(tk.text, 0.025))
			draw_line(Vector2(LABEL_W, y), Vector2(size.x, y), Color(tk.text, 0.06), 1)
			var word: String = str(levels[k].word)
			var w := sans.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS).x
			if absf(y - last_label_y) >= 15 or k == levels.size() - 1 and absf(y - last_label_y) >= 11:
				draw_string(sans, Vector2(LABEL_W - w - 8, y + 4), word, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, tk.muted); last_label_y = y
		if ch == "tint" and mode == "track": _draw_tint_lane(i, tk); continue
		# the actual value over time
		var pts := PackedVector2Array()
		for q in 181:
			var t := lo + q / 180.0 * span
			pts.append(Vector2(x_of(t), y_of(i, ch, _sample(ch, t))))
		draw_polyline(pts, Color(tk.text, 0.72), 1.6, true)
		for kf in keyframes(i, ch):
			if kf.t < lo - 1 or kf.t > hi + 1 or kf.p.x < LABEL_W: continue
			var p: Vector2 = kf.p
			var is_sel: bool = mode == "camera" and kf.index in doc.selection.get("fx", [])
			var is_drag: bool = not drag.is_empty() and drag.lane == i and drag.kf.index == kf.index
			if is_drag: p = Vector2(x_of(drag.t), y_of(i, ch, drag.v))
			if kf.start < kf.t - 1e-4: draw_line(Vector2(x_of(kf.start), p.y), p, Color(tk.clay, 0.35), 1)
			var hv: bool = hover.get("kf", {}).get("index", -1) == kf.index and hover.lane == i
			draw_circle(p, 5.5 if hv or is_drag else 4.5, tk.clay if is_sel or is_drag else tk.s3, true, -1, true)
			draw_arc(p, 5.5 if hv or is_drag else 4.5, 0, TAU, 20, tk.clay, 1.5, true)
			if is_drag: draw_string(mono, p + Vector2(10, -10), "%s  %s" % [doc.position(drag.t).bar_beat, String.num(drag.v, 3)], HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, tk.clay)
	var cx := x_of(cursor)
	draw_line(Vector2(cx, TOP - 4), Vector2(cx, size.y), tk.clay, 1.5)

func _sample(ch: String, t: float) -> float:
	if mode == "camera": return float(doc.core.stage.at(t).get(ch, 0.0))
	var st: Dictionary = doc.state_at(doc.core.tl.get(track_id(), []), t)
	if not st.alive: return 0.0 if ch != "a" else 0.0
	match ch:
		"x": return st.x * 15.0
		"w": return st.w * 15.0
		"a": return st.a if st.a >= 0 else 1.0
	return float(st.get("tint", -1))

func _draw_tint_lane(i: int, tk: Dictionary) -> void:
	var lo := t0()
	var top := lane_top(i) + 14
	var steps := 120
	for q in steps:
		var t := lo + (q + 0.5) / steps * span
		var st: Dictionary = doc.state_at(doc.core.tl.get(track_id(), []), t)
		if not st.alive: continue
		draw_rect(Rect2(x_of(lo + float(q) / steps * span), top, (size.x - LABEL_W - 8) / steps + 0.5, LANE_H - 28), Color(Tokens.tint(int(st.get("tint", -1))), 0.7))
	for kf in keyframes(i, "tint"):
		var p := Vector2(kf.p.x, top + (LANE_H - 28) / 2.0)
		draw_circle(p, 4.5, tk.s3, true, -1, true); draw_arc(p, 4.5, 0, TAU, 20, tk.clay, 1.5, true)
