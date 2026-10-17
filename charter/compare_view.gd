extends Control
## One vertical musical axis shared by every full chart lane.
signal focus_version(ref: String)
signal take_passage(ref: String, lo: float, hi: float)
signal seek(t: float)
var lanes=[]
var diffs=[]
var cursor=0.0
var pixels=65.0
var overlay=false
var doc
var drag_from=-1.0
var selected_lane=0
const COLORS={"added":Color("7bb59a"),"removed":Color("d9897c"),"moved":Color("ddb76c"),"changed":Color("b09bc9")}
const Tokens=preload("res://theme.gd")

func _ready() -> void:
	clip_contents=true
	tooltip_text="滚轮沿共用时间轴滚动，Ctrl 加滚轮缩放。单击一列在预览里播放它；拖选一段后右击，把这段换成该写法"

func time_y(t: float) -> float: return size.y*0.84-(t-cursor)*pixels
func y_time(y: float) -> float: return cursor+(size.y*0.84-y)/pixels

func configure(source, refs: Array, charts: Array) -> void:
	doc=source; lanes=[]; diffs=[]
	for i in charts.size():
		var model=preload("res://document.gd").new(); model.raw=charts[i]; model.refresh_core()
		lanes.append({"ref":refs[i],"doc":model})
		diffs.append(source.version_store().semantic(charts[0],charts[i]))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var direction=1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1
		if event.ctrl_pressed: pixels=clampf(pixels*pow(1.15,direction),20,250)
		else: cursor=maxf(0,cursor+direction*0.5); seek.emit(cursor)
	if event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			selected_lane=clampi(int((event.position.x-82)/maxf(1,size.x-82)*lanes.size()),0,lanes.size()-1)
			drag_from=y_time(event.position.y); focus_version.emit(lanes[selected_lane].ref)
		else:
			if drag_from>=0:
				doc.selection.from=maxf(0,minf(drag_from,y_time(event.position.y))); doc.selection.to=maxf(drag_from,y_time(event.position.y))
				drag_from=-1
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and not lanes.is_empty() and doc.selection.to>doc.selection.from:
		take_passage.emit(lanes[selected_lane].ref,doc.selection.from,doc.selection.to)
	queue_redraw()

func _draw() -> void:
	if lanes.is_empty(): return
	var tk: Dictionary = Tokens.tokens()
	var font: Font = Tokens.font("num"); var semi: Font = Tokens.font("sans", 600); var mono: Font = Tokens.font("mono")
	var width: float = (size.x - 82) / (1 if overlay else lanes.size())
	draw_style_box(Tokens.box(tk.canvas, 12, tk.border), Rect2(Vector2.ZERO, size))
	for point in doc.grid(maxf(0, cursor - 0.5), y_time(36), 4):
		var y: float = time_y(point.seconds)
		var bar: bool = absf(point.beat - 1.0) < 0.01
		draw_line(Vector2(82, y), Vector2(size.x - 4, y), tk.grid_bar if bar else tk.grid, 1)
		if bar:
			draw_string(Tokens.font("num", 600), Vector2(12, y + 6), str(int(point.bar)), HORIZONTAL_ALIGNMENT_LEFT, 40, Tokens.MD, tk.text)
			draw_string(mono, Vector2(12, y + 22), "%.2f s" % point.seconds, HORIZONTAL_ALIGNMENT_LEFT, 66, Tokens.XS, tk.muted)
	if doc.selection.to > doc.selection.from:
		draw_rect(Rect2(74, time_y(doc.selection.to), 2, (doc.selection.to - doc.selection.from) * pixels), Color(tk.clay, 0.8))
	for lane_index in lanes.size():
		var lane: Dictionary = lanes[lane_index]; var model = lane.doc; var left: float = 82 + (0 if overlay else lane_index * width)
		var focused: bool = lane_index == selected_lane
		var title: String = ("工作副本" if lane.ref == "working" else str(lane.ref)) + ("（基准）" if lane_index == 0 else "")
		draw_string(semi, Vector2(left + 12, 24), title, HORIZONTAL_ALIGNMENT_LEFT, width - 20, Tokens.BODY, tk.clay if focused else tk.text)
		var count: int = diffs[lane_index].changes.size()
		if lane_index > 0: draw_string(font, Vector2(left + 12, 44), ("%d 处与基准不同" % count) if count > 0 else "与基准相同", HORIZONTAL_ALIGNMENT_LEFT, width - 20, Tokens.BODY, tk.muted)
		if lane_index > 0 and not overlay: draw_line(Vector2(left, 8), Vector2(left, size.y - 8), tk.border_strong, 1)
		var track_colors := {}
		for change in diffs[lane_index].changes:
			if change.target == "lights":
				var event = change.after if change.after != null else change.before
				track_colors[int(event.id)] = COLORS[change.kind]
		var step: float = 6.0 / pixels
		for id in model.core.tl:
			var t: float = cursor - 0.5
			while t < y_time(44):
				var st = ChartLib.light_at(model.core.tl[id], t)
				if st.alive:
					var band := Rect2(left + st.x * width - st.w * width / 2, time_y(t + step), st.w * width, step * pixels + 0.5)
					var col: Color = Tokens.tint(int(st.get("tint", -1)))
					var a: float = 0.06 if st.get("a", 1) > 0 or st.get("a", 1) < 0 else 0.02
					if track_colors.has(id):
						col = track_colors[id]; a = 0.09
					draw_rect(band, Color(col, a * (0.6 if overlay else 1.0)))
				t += step
		var highlights := {}
		for change in diffs[lane_index].changes:
			if change.target == "notes" and change.get("after") != null: highlights[int(change.after_index)] = COLORS[change.kind]
			if change.target == "fx":
				var event = change.after if change.after != null else change.before
				draw_line(Vector2(left + width - 22, time_y(event.t)), Vector2(left + width - 6, time_y(event.t)), COLORS[change.kind], 2)
			if change.target == "notes" and change.kind == "removed":
				var event = change.before; var base = lanes[0].doc
				var st = ChartLib.light_at(base.core.tl.get(int(event.light), []), event.t)
				var x: float = left + (st.x + (event.u - 0.5) * st.w) * width
				draw_rect(Rect2(x - 7, time_y(event.t) - 3.5, 14, 7), COLORS.removed, false, 1)
		for n in model.core.notes:
			var y: float = time_y(n.t)
			if y < 44 or y > size.y: continue
			var st = ChartLib.light_at(model.core.tl.get(n.light, []), n.t)
			var x: float = left + (st.x + (n.u - 0.5) * st.w) * width
			var ink: Color = highlights.get(int(n.get("raw_id", n.id)), tk.note_ex if n.ex else tk.note)
			if overlay and lane_index > 0: ink = Color(ink, 0.6)
			if n.kind == "hold": draw_rect(Rect2(x - 2.5, time_y(n.t + n.dur), 5, y - time_y(n.t + n.dur)), Color(ink, 0.35))
			draw_style_box(Tokens.box(ink, 3), Rect2(x - 7, y - 3, 14, 6))
		for bar in diffs[lane_index].per_bar_heat:
			var t: float = doc.seconds(str(bar) + ".1"); var y: float = time_y(t)
			if y > 44 and y < size.y: draw_rect(Rect2(left + 3, y - 10, 4, 10), Color(tk.clay, clampf(float(diffs[lane_index].per_bar_heat[bar]) / 15.0, 0.15, 1.0)))
	var py: float = time_y(cursor)
	draw_line(Vector2(6, py), Vector2(size.x - 6, py), tk.clay, 2)

func _get_tooltip(at: Vector2) -> String:
	if lanes.is_empty(): return tooltip_text
	var lane=clampi(int((at.x-82)/maxf(1,size.x-82)*lanes.size()),0,lanes.size()-1)
	var t=y_time(at.y)
	for change in diffs[lane].changes+diffs[lane].get("carrier_reassignments",[]):
		var event=change.after if change.after!=null else change.before
		if absf(event.t-t)<0.1: return change.target+" · "+change.kind+"\n"+JSON.stringify(change,"  ")
	return tooltip_text
