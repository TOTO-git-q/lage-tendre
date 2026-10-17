extends RefCounted
## Small, direct-manipulation controls shared by the inspector, popovers and lanes.
## Every adjustable value: wheel (Shift = coarse, Ctrl/Alt = fine), Up/Down when focused,
## drag where natural (scrub labels, sliders), click to type. Enumerations cycle with the wheel.

const Tokens = preload("res://theme.gd")
const Icons = preload("res://ui/icons.gd")

const U = preload("res://ui/ui_util.gd")
const LABEL_W := 76.0      # label column of inspector rows at the design size
const ROW_H := 32.0        # inspector row / field height

## ------------------------------------------------------------------ icon button
class IconButton extends Button:
	var icon_name := ""
	var caption := ""
	var active := false:
		set(v): active = v; queue_redraw()
	## A count shown as a small clay pill: after the caption, or on the corner of an icon-only button.
	var badge := "":
		set(v): badge = v; _fit(); queue_redraw()
	var icon_size := 18.0:
		set(v): icon_size = v; _fit(); queue_redraw()
	var danger := false
	var round := false
	var fixed_width := 0.0
	## Icon-only: a 34 px square around an 18 px glyph. With a caption: icon, then the words.
	func _init(name: String = "", tip: String = "", text_after: String = "") -> void:
		icon_name = name; caption = text_after; tooltip_text = tip
		flat = true; focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(34, 34)
		_fit()
		mouse_entered.connect(queue_redraw); mouse_exited.connect(queue_redraw)
		toggled.connect(func(_v): queue_redraw())
	func _icon_x() -> float: return maxf(10.0, icon_size * 0.5 + 8.0)
	func _badge_w() -> float: return 36.0 if not badge.is_empty() else 0.0
	func _fit() -> void:
		if fixed_width > 0:
			custom_minimum_size.x = fixed_width; return
		if not caption.is_empty():
			custom_minimum_size.x = _icon_x() + icon_size * 0.5 + 8 + U.text_width(caption, Tokens.BODY) + 12 + (42.0 if icon_name == "warning" else 0.0)
	func set_caption(text: String) -> void:
		caption = text
		if caption.is_empty(): custom_minimum_size.x = custom_minimum_size.y
		_fit(); queue_redraw()
	func _draw() -> void:
		var t := Tokens.tokens()
		var on := active or button_pressed
		var hovered := is_hovered() and not disabled
		var radius := int(size.y / 2.0) if round else 8
		if round: draw_style_box(Tokens.box(t.s2, radius, t.border_strong), Rect2(Vector2.ZERO, size))
		if on: draw_style_box(Tokens.box(t.clay_tint, radius), Rect2(Vector2.ZERO, size))
		elif hovered: draw_style_box(Tokens.box(t.hover, radius), Rect2(Vector2.ZERO, size))
		var col: Color = t.clay if on else (t.text if hovered else t.muted)
		if danger: col = t.danger
		if disabled: col = t.faint
		var ic := Vector2(_icon_x(), size.y / 2.0) if not caption.is_empty() else size / 2.0
		Icons.draw(self, icon_name, ic, icon_size, col)
		if not caption.is_empty():
			var f := Tokens.font("sans")
			var tx := _icon_x() + icon_size * 0.5 + 8
			draw_string(f, Vector2(tx, size.y / 2.0 + Tokens.BODY * 0.36), caption, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, size.x - tx - 12 - (_badge_w() + 6 if not badge.is_empty() else 0)), Tokens.BODY, col if on else (t.text if hovered else t.muted))
		if not badge.is_empty():
			var f2 := Tokens.font("num", 600)
			var w := _badge_w()
			var shown := badge if badge.length() <= 3 else "99+"
			var r := Rect2(size.x - w - 8, (size.y - 20) / 2.0, w, 20) if not caption.is_empty() else Rect2(size.x - w + 4, -2, w, 18)
			draw_style_box(Tokens.box(t.clay_tint if not caption.is_empty() else t.clay, 10), r)
			draw_string(f2, Vector2(r.position.x + (w - U.text_width(shown, Tokens.XS, f2)) / 2.0, r.get_center().y + 4.5), shown, HORIZONTAL_ALIGNMENT_LEFT, w, Tokens.XS, t.clay if not caption.is_empty() else Color.WHITE)

## ------------------------------------------------------------------ keycap
class Kbd extends Control:
	var keys := ""
	func _init(text: String = "") -> void:
		keys = text; mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(U.text_width(keys, Tokens.BODY) + 16, 26)
	func _draw() -> void:
		var t := Tokens.tokens()
		var y0 := (size.y - 24.0) / 2.0
		draw_style_box(Tokens.box(t.s2, 6, t.border_strong), Rect2(0, y0, size.x, 24))
		draw_string(Tokens.font("sans", 500), Vector2(8, y0 + 17), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, t.text)

## ------------------------------------------------------------------ scrub number field
class ScrubLabel extends Control:
	var text := ""
	var owner_field
	var dragging := false
	var start_x := 0.0
	var start_value := 0.0
	func _init(label_text: String, field) -> void:
		text = label_text; owner_field = field
		custom_minimum_size = Vector2(LABEL_W, ROW_H)
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		tooltip_text = "左右拖动调整数值；滚轮或 ↑↓ 逐步调整，按住 Shift 粗调、Ctrl 细调"
	func _draw() -> void:
		var t := Tokens.tokens()
		draw_string(Tokens.font("sans"), Vector2(0, size.y / 2.0 + 5), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 4, Tokens.BODY, t.clay if dragging else t.muted)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				dragging = true; start_x = e.global_position.x; start_value = owner_field.value; owner_field.gesture += 1
			elif dragging:
				dragging = false; owner_field.emit_value(owner_field.value, true)
			queue_redraw(); accept_event()
		elif e is InputEventMouseMotion and dragging:
			var px: float = e.global_position.x - start_x
			var mod := U.step_mod(e)
			owner_field.emit_value(start_value + roundf(px / 5.0) * owner_field.step * mod, false)
			accept_event()
		else:
			owner_field.handle_wheel(e)

class ScrubField extends HBoxContainer:
	signal changed(value: float, final: bool)
	var value := 0.0
	var step := 1.0
	var min_value := -INF
	var max_value := INF
	var unit := ""
	var mixed := false
	var gesture := 0
	var key := ""
	var formatter: Callable
	var parser: Callable
	var handle: ScrubLabel
	var edit := LineEdit.new()
	var unit_label := Label.new()
	var _last_wheel := 0
	func _init(label_text: String, unit_text: String = "", step_value: float = 1.0) -> void:
		step = step_value; unit = unit_text
		add_theme_constant_override("separation", 4)
		handle = ScrubLabel.new(label_text, self); add_child(handle)
		edit.theme_type_variation = "FlatEdit"; edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.expand_to_text_length = false; edit.custom_minimum_size = Vector2(60, ROW_H); edit.select_all_on_focus = true; edit.context_menu_enabled = false
		add_child(edit)
		unit_label.theme_type_variation = "Faint"; unit_label.text = unit; unit_label.custom_minimum_size.x = 20 if unit.is_empty() else 0
		add_child(unit_label)
		edit.text_submitted.connect(func(_t): commit_text(); edit.release_focus())
		edit.focus_exited.connect(commit_text)
		edit.gui_input.connect(_edit_input)
	func display(v: float) -> String:
		return formatter.call(v) if formatter.is_valid() else String.num(v, 3)
	func set_value(v: float, is_mixed: bool = false) -> void:
		value = v; mixed = is_mixed
		if not edit.has_focus(): edit.text = "—" if mixed else display(v)
	func emit_value(v: float, final: bool) -> void:
		v = clampf(v, min_value, max_value)
		value = v; mixed = false
		if not edit.has_focus(): edit.text = display(v)
		changed.emit(v, final)
	func commit_text() -> void:
		var text := edit.text.strip_edges()
		if text == "—" or text == display(value): return
		var parsed: float = parser.call(text) if parser.is_valid() else (text.to_float() if text.is_valid_float() else NAN)
		if is_nan(parsed): edit.text = display(value); return
		gesture += 1; emit_value(parsed, true)
	func nudge(direction: int, mod: float) -> void:
		var now := Time.get_ticks_msec()
		if now - _last_wheel > 650: gesture += 1
		_last_wheel = now
		emit_value(value + direction * step * mod, true)
	func handle_wheel(e: InputEvent) -> void:
		var d := U.wheel_dir(e)
		if d != 0: nudge(d, U.step_mod(e)); accept_event()
	func _edit_input(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode in [KEY_UP, KEY_DOWN]:
			nudge(1 if e.keycode == KEY_UP else -1, U.step_mod(e)); edit.text = display(value); edit.accept_event()
		elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			edit.text = display(value); edit.release_focus(); edit.accept_event()
		else:
			var d := U.wheel_dir(e)
			if d != 0: nudge(d, U.step_mod(e)); edit.text = display(value); edit.accept_event()

## ------------------------------------------------------------------ enumeration (wheel cycles)
class EnumField extends HBoxContainer:
	signal changed(index: int)
	var options: Array = []
	var index := 0
	var mixed := false
	var box := Control.new()
	var popup := PopupMenu.new()
	func _init(label_text: String, items: Array, current: int = 0) -> void:
		options = items; index = current
		add_theme_constant_override("separation", 4)
		var l := Label.new(); l.text = label_text; l.theme_type_variation = "Muted"; l.custom_minimum_size = Vector2(LABEL_W, ROW_H)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		box.custom_minimum_size = Vector2(88, ROW_H); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.focus_mode = Control.FOCUS_CLICK; box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.tooltip_text = "单击展开列表；滚轮或 ↑↓ 直接切换"
		add_child(box)
		box.draw.connect(_draw_box); box.gui_input.connect(_box_input)
		box.mouse_entered.connect(box.queue_redraw); box.mouse_exited.connect(box.queue_redraw)
		box.focus_entered.connect(box.queue_redraw); box.focus_exited.connect(box.queue_redraw)
		add_child(popup); popup.id_pressed.connect(func(id): pick(id))
	func set_index(i: int, is_mixed: bool = false) -> void:
		index = i; mixed = is_mixed; box.queue_redraw()
	func pick(i: int) -> void:
		index = posmod(i, options.size()); mixed = false; box.queue_redraw(); changed.emit(index)
	func _draw_box() -> void:
		var t := Tokens.tokens()
		var hovered := Rect2(Vector2.ZERO, box.size).has_point(box.get_local_mouse_position())
		if hovered or box.has_focus(): box.draw_style_box(Tokens.box(t.hover, 6, Color(Tokens.CLAY, 0.75) if box.has_focus() else Color.TRANSPARENT), Rect2(Vector2.ZERO, box.size))
		var label: String = "—" if mixed or options.is_empty() else str(options[index])
		box.draw_string(Tokens.font("num"), Vector2(6, box.size.y / 2.0 + 5), label, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 32, Tokens.BODY, t.text)
		Icons.draw(box, "chevron_down", Vector2(box.size.x - 14, box.size.y / 2.0), 14, t.muted)
	func _box_input(e: InputEvent) -> void:
		var d := U.wheel_dir(e)
		if d != 0: pick(index - d); box.accept_event(); return
		if e is InputEventKey and e.pressed and e.keycode in [KEY_UP, KEY_DOWN]:
			pick(index + (-1 if e.keycode == KEY_UP else 1)); box.accept_event(); return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			popup.clear()
			for i in options.size():
				popup.add_radio_check_item(str(options[i]), i); popup.set_item_checked(i, i == index and not mixed)
			popup.popup(Rect2i(Vector2i(box.get_screen_position() + Vector2(0, box.size.y + 2)), Vector2i(int(box.size.x), 0)))
			box.accept_event()

## ------------------------------------------------------------------ segmented control
class Segmented extends Control:
	signal changed(index: int)
	var options: Array = []      # strings, or "icon:<name>" entries
	var tips: Array = []
	var index := 0
	var compact := false
	var _rects: Array = []
	func _init(items: Array, current: int = 0, tip_list: Array = []) -> void:
		options = items; index = current; tips = tip_list
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(_total_width(), 34)
		mouse_exited.connect(queue_redraw)
	func _item_w(o) -> float:
		var s := str(o)
		return 38.0 if s.begins_with("icon:") else U.text_width(s, Tokens.BODY) + 24.0
	func _total_width() -> float:
		var w := 4.0
		for o in options: w += _item_w(o)
		return w
	func set_index(i: int) -> void: index = i; queue_redraw()
	func _draw() -> void:
		var t := Tokens.tokens()
		draw_style_box(Tokens.box(t.s2 if not Tokens.light else Color(0, 0, 0, 0.045), 99, t.border), Rect2(Vector2.ZERO, size))
		_rects = []
		var x := 2.0
		var mouse := get_local_mouse_position()
		for i in options.size():
			var w := _item_w(options[i]) * (size.x - 4.0) / maxf(1.0, _total_width() - 4.0)
			var r := Rect2(x, 2, w, size.y - 4)
			_rects.append(r)
			if i == index:
				var sel := Tokens.box(t.s3 if not Tokens.light else Color.WHITE, 99, t.border_strong)
				sel.shadow_color = Color(0, 0, 0, 0.12 if Tokens.light else 0.4); sel.shadow_size = 3; sel.shadow_offset = Vector2(0, 1)
				draw_style_box(sel, r)
			elif r.has_point(mouse) and Rect2(Vector2.ZERO, size).has_point(mouse):
				draw_style_box(Tokens.box(t.hover, 99), r)
			var col: Color = t.text if i == index else t.muted
			var s := str(options[i])
			if s.begins_with("icon:"): Icons.draw(self, s.substr(5), r.get_center(), 18, col)
			else:
				var f := Tokens.font("sans", 600 if i == index else 400)
				var tw := U.text_width(s, Tokens.BODY, f)
				draw_string(f, Vector2(r.position.x + (r.size.x - tw) / 2.0, r.position.y + r.size.y / 2.0 + 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.BODY, col)
			x += w
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion: queue_redraw()
		var d := U.wheel_dir(e)
		if d != 0:
			index = posmod(index - d, options.size()); queue_redraw(); changed.emit(index); accept_event(); return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in _rects.size():
				if _rects[i].has_point(e.position):
					index = i; queue_redraw(); changed.emit(i); accept_event(); return
	func _get_tooltip(at: Vector2) -> String:
		for i in _rects.size():
			if _rects[i].has_point(at) and i < tips.size(): return tips[i]
		return tooltip_text

## ------------------------------------------------------------------ tint swatches
class Swatches extends Control:
	signal changed(tint: int)
	const NAMES := ["无色", "月蓝", "玫瑰", "薄荷", "浅金", "薰衣草", "冰青", "杏橙", "浅紫", "嫩绿", "暖白"]
	var value := -1
	var mixed := false
	func _init(current: int = -1) -> void:
		value = current; custom_minimum_size = Vector2(11 * 26, 30)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_exited.connect(queue_redraw)
	func set_value(v: int, is_mixed: bool = false) -> void: value = v; mixed = is_mixed; queue_redraw()
	func _slot(i: int) -> Vector2: return Vector2(13 + i * 26, size.y / 2.0)
	func _hit(p: Vector2) -> int:
		for i in 11:
			if p.distance_to(_slot(i)) < 13: return i - 1
		return -99
	func _draw() -> void:
		var t := Tokens.tokens()
		var hover := _hit(get_local_mouse_position()) if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()) else -99
		for i in 11:
			var tint_i := i - 1; var c := _slot(i)
			if tint_i == value and not mixed: draw_arc(c, 12, 0, TAU, 32, t.clay, 2.0, true)
			elif tint_i == hover: draw_arc(c, 12, 0, TAU, 32, t.border_strong, 1.5, true)
			if tint_i < 0:
				draw_arc(c, 8, 0, TAU, 24, t.muted, 1.5, true); draw_line(c + Vector2(-5.5, 5.5), c + Vector2(5.5, -5.5), t.muted, 1.5, true)
			else:
				draw_circle(c, 8.5, Tokens.tint(tint_i), true, -1, true)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion: queue_redraw()
		var d := U.wheel_dir(e)
		if d != 0:
			value = clampi(value - d, -1, 9) if not mixed else 0; mixed = false; queue_redraw(); changed.emit(value); accept_event(); return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var h := _hit(e.position)
			if h > -99: value = h; mixed = false; queue_redraw(); changed.emit(h); accept_event()
	func _get_tooltip(at: Vector2) -> String:
		var h := _hit(at)
		return "%s（色调 %d）" % [NAMES[h + 1], h] if h > -99 else ""

## ------------------------------------------------------------------ 0..1 scale slider
class Scale01 extends Control:
	signal changed(value: float, final: bool)
	var value := 1.0
	var mixed := false
	var dragging := false
	var gesture := 0
	var _last_wheel := 0
	func _init(current: float = 1.0) -> void:
		value = current; custom_minimum_size = Vector2(180, 46); focus_mode = Control.FOCUS_CLICK
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "拖动或滚动调整（每格 0.05）；Shift 吸附到 ¼，Ctrl 细调"
	func set_value(v: float, is_mixed: bool = false) -> void:
		if not dragging: value = v; mixed = is_mixed; queue_redraw()
	func _x(v: float) -> float: return 8.0 + v * (size.x - 16.0)
	func _draw() -> void:
		var t := Tokens.tokens()
		var y := 13.0
		draw_line(Vector2(_x(0), y), Vector2(_x(1), y), t.border_strong, 4, true)
		if not mixed: draw_line(Vector2(_x(0), y), Vector2(_x(value), y), Color(t.text, 0.55), 4, true)
		var f := Tokens.font("num")
		for k in 5:
			var v := k * 0.25
			draw_line(Vector2(_x(v), y + 6), Vector2(_x(v), y + 9), t.faint, 1)
			var label: String = ["0", ".25", ".5", ".75", "1"][k]
			var w := U.text_width(label, Tokens.XS, f)
			draw_string(f, Vector2(clampf(_x(v) - w / 2.0, 0, size.x - w), y + 25), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.XS, t.muted)
		if not mixed:
			draw_circle(Vector2(_x(value), y), 8, t.s3 if not Tokens.light else Color.WHITE, true, -1, true)
			draw_arc(Vector2(_x(value), y), 8, 0, TAU, 24, t.clay if dragging or has_focus() else t.border_strong, 2.0 if dragging or has_focus() else 1.5, true)
	func _set_from(px: float, e: InputEvent, final: bool) -> void:
		var v := clampf((px - 8.0) / maxf(1.0, size.x - 16.0), 0, 1)
		if e is InputEventWithModifiers and e.shift_pressed: v = snappedf(v, 0.25)
		else: v = snappedf(v, 0.01)
		value = v; mixed = false; queue_redraw(); changed.emit(v, final)
	func _gui_input(e: InputEvent) -> void:
		var d := U.wheel_dir(e)
		if d == 0 and e is InputEventKey and e.pressed and e.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			d = 1 if e.keycode in [KEY_UP, KEY_RIGHT] else -1
		if d != 0:
			var now := Time.get_ticks_msec()
			if now - _last_wheel > 650: gesture += 1
			_last_wheel = now
			var stepv := 0.25 if e is InputEventWithModifiers and e.shift_pressed else (0.01 if e is InputEventWithModifiers and (e.ctrl_pressed or e.alt_pressed) else 0.05)
			value = clampf(snappedf(value + d * stepv, 0.01), 0, 1); mixed = false; queue_redraw(); changed.emit(value, true); accept_event(); return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				dragging = true; gesture += 1
				# a click on a tick label snaps to it
				if e.position.y > 22:
					for k in 5:
						if absf(e.position.x - _x(k * 0.25)) < 12: value = k * 0.25; mixed = false; queue_redraw(); changed.emit(value, true); dragging = false; accept_event(); return
				_set_from(e.position.x, e, false)
			elif dragging:
				dragging = false; changed.emit(value, true); queue_redraw()
			accept_event()
		elif e is InputEventMouseMotion and dragging:
			_set_from(e.position.x, e, false); accept_event()

## ------------------------------------------------------------------ collapsible section
class Section extends VBoxContainer:
	signal toggled_open(open: bool)
	var title := ""
	var open := true
	var header := Control.new()
	var body := VBoxContainer.new()
	var extra := ""
	func _init(title_text: String, is_open: bool = true) -> void:
		title = title_text; open = is_open
		add_theme_constant_override("separation", 4)
		header.custom_minimum_size = Vector2(0, 30); header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_child(header); header.draw.connect(_draw_header); header.gui_input.connect(_header_input)
		body.add_theme_constant_override("separation", 2); add_child(body); body.visible = open
	func _draw_header() -> void:
		var t := Tokens.tokens()
		Icons.draw(header, "chevron_down" if open else "chevron_right", Vector2(8, 15), 14, t.muted)
		header.draw_string(Tokens.font("sans", 600), Vector2(22, 20), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, header.size.x - 130), Tokens.BODY, t.muted)
		if not extra.is_empty():
			var w := 112.0
			header.draw_string(Tokens.font("num"), Vector2(header.size.x - w - 2, 20), extra, HORIZONTAL_ALIGNMENT_LEFT, w, Tokens.BODY, t.faint)
	func _header_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open = not open; body.visible = open; header.queue_redraw(); toggled_open.emit(open)
