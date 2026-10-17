extends PanelContainer
## Floating card for a segment between two selected outline nodes (Ctrl+click two nodes or
## Enter). Curve presets, node style, insert / delete / flatten, and segment-wide position,
## width, opacity ramp and tint. All values are wheel / arrow adjustable.

const W = preload("res://ui/widgets.gd")
const Tokens = preload("res://theme.gd")
const Adapter = preload("res://track_adapter.gd")
const Ops = preload("res://edit_ops.gd")

var timeline
var si := 0
var a := 0
var b := 0
var body := VBoxContainer.new()
var title := Label.new()
var note := Label.new()
var keys := []   # [[t, x], [t, x]]: node identities survive inserts / deletes

func _ready() -> void:
	theme_type_variation = "Float"
	custom_minimum_size = Vector2(372, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(body); body.add_theme_constant_override("separation", 10)
	visible = false

func open(tl, shape_index: int, node_a: int, node_b: int, at: Vector2) -> void:
	timeline = tl; si = shape_index; a = node_a; b = node_b
	var s = tl.work.shapes[si]
	keys = [[s.nodes[a].t, s.nodes[a].x], [s.nodes[b].t, s.nodes[b].x]]
	rebuild()
	visible = true
	reset_size()
	_place.call_deferred(at)

func _place(at: Vector2) -> void:
	reset_size()
	var parent_size: Vector2 = get_parent().size
	position = Vector2(clampf(at.x + 18, 8, parent_size.x - size.x - 8), clampf(at.y - size.y / 2.0, 8, parent_size.y - size.y - 44))

func close() -> void:
	visible = false

func rebuild() -> void:
	for c in body.get_children(): body.remove_child(c); c.queue_free()
	if timeline == null or timeline.work.is_empty() or si >= timeline.work.shapes.size(): visible = false; return
	var s = timeline.work.shapes[si]
	a = _resolve(s, 0, a); b = _resolve(s, 1, b)
	if a < 0 or b < 0 or a >= s.size() or b >= s.size(): visible = false; return
	var seg: Dictionary = timeline.segment_nodes(si, a, b)
	var doc = timeline.doc
	var head := HBoxContainer.new(); body.add_child(head)
	title.text = "片段 %s–%s" % [Ops.pretty(doc, seg.t0), Ops.pretty(doc, seg.t1)]
	title.theme_type_variation = "Heading"; title.clip_text = true; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(title)
	var close_b := W.IconButton.new("close", "关闭（Esc）"); close_b.pressed.connect(close); head.add_child(close_b)
	var eases := ["linear", "in", "out", "inout", "bezier"]
	var current := 0
	if not seg.segs.is_empty():
		current = maxi(0, eases.find(s.segs[seg.segs[0]].ease))
	var curve := W.Segmented.new(["直线", "缓入", "缓出", "缓入缓出", "自由"], current, ["匀速（linear）", "渐快（in）", "渐慢（out）", "先快后慢再快（inout）", "自由贝塞尔，需要新轨道语法"])
	curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curve.changed.connect(func(i): timeline.segment_op(si, a, b, "ease", eases[i]); rebuild())
	body.add_child(curve)
	note.theme_type_variation = "Faint"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 340
	note.text = "曲线同时作用于这一段的两条边，现有语法一段只能有一种曲线。轨道会在每个关键帧起点轻闪一下。" if seg.lane else "自由形状：游戏按外轮廓近似显示，精确形状保存在 chart.ext.json。"
	body.add_child(note)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 4); actions.add_theme_constant_override("v_separation", 4); body.add_child(actions)
	for spec in [["plus", "插入节点", "insert", "在这一段中间插入一个节点"], ["minus", "删除节点", "delete", "删除这一段的端点"], ["curve", "平滑", "smooth", "两端节点改为平滑"], ["node", "尖角", "corner", "两端节点改为尖角"], ["sliders", "拉平", "flatten", "去掉这一段中间的起伏"]]:
		var btn := W.IconButton.new(spec[0], spec[3], spec[1])
		var op: String = spec[2]
		btn.pressed.connect(func(): timeline.segment_op(si, a, b, op); _after())
		actions.add_child(btn)
	if seg.lane:
		var c_val := 0.0; var w_val := 0.0
		var p: int = s.partner(a)
		if p >= 0:
			c_val = (s.nodes[a].x + s.nodes[p].x) / 2.0 * 15.0; w_val = absf(s.nodes[a].x - s.nodes[p].x) * 15.0
		var center := W.ScrubField.new("中心", "键", 0.25); center.set_value(c_val)
		center.formatter = func(v): return String.num(v, 2)
		center.changed.connect(func(v, final): if final: timeline.segment_op(si, a, b, "center", v / 15.0))
		body.add_child(center)
		var width := W.ScrubField.new("宽度", "键", 0.25); width.set_value(w_val); width.min_value = 1.0
		width.formatter = func(v): return String.num(v, 2)
		width.changed.connect(func(v, final): if final: timeline.segment_op(si, a, b, "width", v / 15.0))
		body.add_child(width)
	var a0: Dictionary = s.prop_at(seg.t0); var a1: Dictionary = s.prop_at(seg.t1)
	var op0 := W.ScrubField.new("起点不透明度", "", 0.05); op0.handle.custom_minimum_size.x = 100; op0.set_value(maxf(0, a0.a)); op0.min_value = 0; op0.max_value = 1
	op0.formatter = func(v): return String.num(v, 2)
	op0.changed.connect(func(v, final): if final: timeline.segment_op(si, a, b, "a0", v))
	body.add_child(op0)
	var op1 := W.ScrubField.new("终点不透明度", "", 0.05); op1.handle.custom_minimum_size.x = 100; op1.set_value(maxf(0, a1.a)); op1.min_value = 0; op1.max_value = 1
	op1.formatter = func(v): return String.num(v, 2)
	op1.changed.connect(func(v, final): if final: timeline.segment_op(si, a, b, "a1", v))
	body.add_child(op1)
	var tint_row := HBoxContainer.new(); body.add_child(tint_row)
	var tl := Label.new(); tl.text = "色调"; tl.theme_type_variation = "Muted"; tl.custom_minimum_size.x = W.LABEL_W; tint_row.add_child(tl)
	var sw := W.Swatches.new(int(a1.tint)); sw.changed.connect(func(v): timeline.segment_op(si, a, b, "tint", v)); tint_row.add_child(sw)
	var rep := Adapter.is_representable(s)
	var foot := Label.new(); foot.theme_type_variation = "Faint"
	foot.text = "这个形状可以直接写成现有的轨道事件" if rep.ok else "这个形状需要新轨道语法，等引擎支持：" + rep.reason
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; foot.custom_minimum_size.x = 340
	if not rep.ok: foot.add_theme_color_override("font_color", Tokens.CLAY)
	body.add_child(foot)
	reset_size()

func _resolve(s, which: int, fallback: int) -> int:
	if keys.size() < 2: return fallback
	var best := -1; var bd := INF
	for i in s.size():
		if absf(s.nodes[i].t - keys[which][0]) > 1e-5: continue
		var d: float = absf(s.nodes[i].x - keys[which][1])
		if d < bd: bd = d; best = i
	if best >= 0: keys[which][1] = s.nodes[best].x
	return best

func _after() -> void:
	rebuild()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: close(); accept_event()
