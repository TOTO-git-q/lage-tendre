extends Control
## Grouped track list (承载轨 / 演出轨 / 背景 / 踏板). Rows: colour chip (ring = transparent),
## id, a lifetime bar drawn over the whole song, note count; on hover the count gives way to
## show / solo / lock icons. Click selects, double-click jumps to the track's first moment.

signal pick(id: int)
signal jump(t: float)
signal flags_changed

const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")
const Ops = preload("res://edit_ops.gd")
const GROUPS := [["carrier", "承载轨"], ["performer", "演出轨"], ["background", "背景"], ["cue", "踏板"]]
const ROW := 34.0
const HEAD := 34.0

var doc
var timeline
var filter := ""
var collapsed: Dictionary = {}
var rows: Array = []
var hover_row := -1
var hover_icon := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hover_row = -1; hover_icon = ""; queue_redraw())

func rebuild() -> void:
	rows = []
	if doc == null or doc.raw.is_empty() or timeline == null: custom_minimum_size.y = 0; queue_redraw(); return
	var by_role := {}
	for id in timeline.tracks_view:
		var tv: Dictionary = timeline.tracks_view[id]
		if not filter.is_empty() and not filter in str(id): continue
		if not by_role.has(tv.role): by_role[tv.role] = []
		var spans := Ops.lifetimes(doc, id)
		var first: float = spans[0][0] if not spans.is_empty() else 0.0
		by_role[tv.role].append({"id": id, "first": first, "spans": spans, "tv": tv})
	for g in GROUPS:
		var list: Array = by_role.get(g[0], [])
		if list.is_empty(): continue
		list.sort_custom(func(a, b): return a.first < b.first if a.first != b.first else a.id < b.id)
		if not collapsed.has(g[0]): collapsed[g[0]] = list.size() > 24
		rows.append({"head": true, "role": g[0], "label": g[1], "count": list.size()})
		if collapsed[g[0]]: continue
		for item in list: rows.append(item)
	var h := 4.0
	for r in rows: h += HEAD if r.get("head", false) else ROW
	custom_minimum_size.y = h
	queue_redraw()

func _row_at(y: float) -> int:
	var top := 4.0
	for i in rows.size():
		var h := HEAD if rows[i].get("head", false) else ROW
		if y >= top and y < top + h: return i
		top += h
	return -1

func _icon_rects() -> Dictionary:
	var x := size.x - 10
	return {"lock": Rect2(x - 28, 0, 28, ROW), "solo": Rect2(x - 58, 0, 28, ROW), "eye": Rect2(x - 88, 0, 28, ROW)}

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover_row = _row_at(e.position.y); hover_icon = ""
		if hover_row >= 0 and not rows[hover_row].get("head", false):
			var top := _row_top(hover_row)
			for k in _icon_rects():
				var r: Rect2 = _icon_rects()[k]; r.position.y = top
				if r.has_point(e.position): hover_icon = k
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_row >= 0 else Control.CURSOR_ARROW
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _row_at(e.position.y)
		if i < 0: return
		var r: Dictionary = rows[i]
		if r.get("head", false):
			collapsed[r.role] = not collapsed.get(r.role, false); rebuild(); accept_event(); return
		if not hover_icon.is_empty():
			match hover_icon:
				"eye": timeline.hidden_tracks[r.id] = not timeline.hidden_tracks.get(r.id, false)
				"solo": timeline.solo = -1 if timeline.solo == r.id else r.id
				"lock": timeline.locked_tracks[r.id] = not timeline.locked_tracks.get(r.id, false)
			timeline.refresh(true); flags_changed.emit(); queue_redraw(); accept_event(); return
		if e.double_click: jump.emit(r.first)
		else: pick.emit(r.id)
		accept_event()

func _row_top(index: int) -> float:
	var top := 4.0
	for i in index: top += HEAD if rows[i].get("head", false) else ROW
	return top

func _draw() -> void:
	if doc == null or doc.raw.is_empty(): return
	var t := Tokens.tokens()
	var semi := Tokens.font("sans", 600); var num := Tokens.font("num")
	var end := maxf(1.0, doc.core.end_time)
	var selected := int(doc.selection.tracks[0]) if not doc.selection.get("tracks", []).is_empty() else -1
	var y := 4.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r.get("head", false):
			Icons.draw(self, "chevron_right" if collapsed.get(r.role, false) else "chevron_down", Vector2(13, y + HEAD / 2.0), 14, t.muted)
			draw_string(semi, Vector2(26, y + 22), r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, t.muted)
			draw_string(num, Vector2(26 + semi.get_string_size(r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x + 8, y + 22), str(r.count), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, t.faint)
			y += HEAD; continue
		var rect := Rect2(4, y + 1, size.x - 8, ROW - 2)
		var id: int = r.id; var tv: Dictionary = r.tv
		if id == selected: draw_style_box(Tokens.box(t.clay_tint, 7), rect)
		elif i == hover_row: draw_style_box(Tokens.box(t.hover, 7), rect)
		var hidden: bool = timeline.hidden_tracks.get(id, false)
		var dim := 0.4 if hidden or (timeline.solo >= 0 and timeline.solo != id) else 1.0
		var tint := -1
		if not tv.shapes.is_empty() and not tv.shapes[0].props.is_empty(): tint = int(tv.shapes[0].props[0].tint)
		var chip := Tokens.tint(tint)
		var cy := y + ROW / 2.0
		if tv.transparent: draw_arc(Vector2(20, cy), 5.5, 0, TAU, 20, Color(chip, dim), 1.8, true)
		else: draw_circle(Vector2(20, cy), 6, Color(chip, dim), true, -1, true)
		draw_string(Tokens.font("num", 500), Vector2(34, cy + 5), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, Color(t.text if id != selected else t.clay, dim))
		# lifetime over the whole song, as a shape
		var bx0 := 76.0; var bx1 := size.x - 104.0
		if bx1 > bx0 + 20:
			draw_line(Vector2(bx0, cy), Vector2(bx1, cy), Color(t.border_strong, 0.6 * dim), 2, true)
			for span in r.spans:
				var s0: float = bx0 + span[0] / end * (bx1 - bx0)
				var s1: float = bx0 + (minf(span[1], end) if is_finite(span[1]) else end) / end * (bx1 - bx0)
				draw_line(Vector2(s0, cy), Vector2(maxf(s1, s0 + 2.5), cy), Color(chip, 0.95 * dim), 4, true)
			var cur: float = bx0 + timeline.cursor / end * (bx1 - bx0)
			draw_line(Vector2(cur, cy - 5), Vector2(cur, cy + 5), Color(t.clay, 0.55), 1)
		var icons := _icon_rects()
		var show_icons := i == hover_row
		for k in icons:
			var ir: Rect2 = icons[k]; ir.position.y = y
			var on: bool = (k == "eye" and hidden) or (k == "solo" and timeline.solo == id) or (k == "lock" and timeline.locked_tracks.get(id, false))
			if not show_icons and not on: continue
			var name: String = {"eye": "eye_off" if hidden else "eye", "solo": "solo", "lock": "lock" if timeline.locked_tracks.get(id, false) else "unlock"}[k]
			var col: Color = t.clay if on else (t.text if hover_icon == k and i == hover_row else t.faint)
			Icons.draw(self, name, ir.get_center(), 16, col)
		if not show_icons:
			var count := str(tv.count) if tv.count > 0 else ""
			var w := num.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY).x
			draw_string(num, Vector2(size.x - 14 - w - (92 if (hidden or timeline.solo == id or timeline.locked_tracks.get(id, false)) else 0), cy + 5), count, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, t.faint)
		y += ROW

func _get_tooltip(at: Vector2) -> String:
	var i := _row_at(at.y)
	if i < 0 or rows[i].get("head", false): return ""
	var r: Dictionary = rows[i]
	if not hover_icon.is_empty(): return {"eye": "在时间线上隐藏或显示", "solo": "只显示这条轨道", "lock": "锁定后不能编辑"}[hover_icon]
	return "轨道 %d：%d 个音符，首次出现在 %s\n双击跳到那里" % [r.id, r.tv.count, doc.position(r.first).bar_beat]
