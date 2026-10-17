extends RefCounted
## Line icons drawn with vectors on a 16-unit grid (no font or image assets), round feel, in the
## spirit of the Claude app's Phosphor-style glyphs. The stroke follows the drawn size (1.5 px at
## 16, 1.7 at 18, 1.9 at 20) so every icon in a row carries the same visual weight.

static func stroke_for(size: float) -> float:
	return clampf(size * 0.094, 1.5, 2.0)

static func draw(ci: CanvasItem, name: String, center: Vector2, size: float, color: Color, width: float = -1.0) -> void:
	if width <= 0.0: width = stroke_for(size)
	var s := size / 16.0
	var o := center - Vector2(8, 8) * s
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var line := func(pts: Array, closed := false) -> void:
		var arr := PackedVector2Array()
		for p in pts: arr.append(P.call(p.x, p.y))
		if closed: arr.append(arr[0])
		ci.draw_polyline(arr, color, width, true)
	var arc := func(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
		ci.draw_arc(P.call(cx, cy), r * s, a0, a1, 24, color, width, true)
	var dot := func(x: float, y: float, r: float = 1.1) -> void:
		ci.draw_circle(P.call(x, y), r * s, color, true, -1.0, true)
	var fill := func(pts: Array) -> void:
		var arr := PackedVector2Array()
		for p in pts: arr.append(P.call(p.x, p.y))
		ci.draw_colored_polygon(arr, color)
	match name:
		"attach":
			line.call([Vector2(11,3),Vector2(6,10),Vector2(7,12),Vector2(9,11),Vector2(14,4),Vector2(13,1),Vector2(10,1),Vector2(3,10),Vector2(3,13),Vector2(6,15),Vector2(9,14),Vector2(13,9)])
		"code":
			line.call([Vector2(5,4),Vector2(1.5,8),Vector2(5,12)])
			line.call([Vector2(11,4),Vector2(14.5,8),Vector2(11,12)])
			line.call([Vector2(9.5,2),Vector2(6.5,14)])
		"play": fill.call([Vector2(5, 3.5), Vector2(12.5, 8), Vector2(5, 12.5)])
		"pause":
			fill.call([Vector2(4.5, 3.5), Vector2(6.8, 3.5), Vector2(6.8, 12.5), Vector2(4.5, 12.5)])
			fill.call([Vector2(9.2, 3.5), Vector2(11.5, 3.5), Vector2(11.5, 12.5), Vector2(9.2, 12.5)])
		"undo":
			arc.call(8.5, 9, 4.5, -PI * 0.95, PI * 0.5)
			line.call([Vector2(2.2, 5.6), Vector2(4.0, 8.6), Vector2(6.9, 6.8)])
		"redo":
			arc.call(7.5, 9, 4.5, PI * 0.5, PI * 1.95)
			line.call([Vector2(13.8, 5.6), Vector2(12.0, 8.6), Vector2(9.1, 6.8)])
		"loop":
			line.call([Vector2(3, 9), Vector2(3, 6), Vector2(12, 6)]); line.call([Vector2(10, 4), Vector2(12, 6), Vector2(10, 8)])
			line.call([Vector2(13, 7), Vector2(13, 10), Vector2(4, 10)]); line.call([Vector2(6, 8), Vector2(4, 10), Vector2(6, 12)])
		"metronome":
			line.call([Vector2(5.5, 2.5), Vector2(10.5, 2.5), Vector2(13, 13.5), Vector2(3, 13.5)], true)
			line.call([Vector2(8, 11), Vector2(11.5, 4.5)]); dot.call(8, 11)
		"tick":
			line.call([Vector2(3, 10), Vector2(3, 6)]); line.call([Vector2(6, 12), Vector2(6, 4)]); line.call([Vector2(9, 11), Vector2(9, 5)]); line.call([Vector2(12, 9), Vector2(12, 7)])
		"magnet":
			arc.call(8, 8.5, 4.5, PI, TAU); line.call([Vector2(3.5, 8.5), Vector2(3.5, 13)]); line.call([Vector2(12.5, 8.5), Vector2(12.5, 13)])
			line.call([Vector2(2.5, 11), Vector2(5.5, 11)]); line.call([Vector2(10.5, 11), Vector2(13.5, 11)])
		"sun":
			ci.draw_arc(P.call(8, 8), 3 * s, 0, TAU, 24, color, width, true)
			for k in 8:
				var a := k * TAU / 8.0
				line.call([Vector2(8, 8) + Vector2(cos(a), sin(a)) * 5.0, Vector2(8, 8) + Vector2(cos(a), sin(a)) * 6.6])
		"moon": arc.call(8, 8, 5.5, -PI * 0.15, PI * 1.35); arc.call(10.6, 6.2, 4.2, PI * 0.55, PI * 1.25)
		"gear":
			ci.draw_arc(P.call(8, 8), 2.2 * s, 0, TAU, 20, color, width, true)
			var pts := []
			for k in 16:
				var a := k * TAU / 16.0 + TAU / 32.0
				var r := 6.0 if (k % 2 == 0) else 4.6
				pts.append(Vector2(8, 8) + Vector2(cos(a), sin(a)) * r)
			line.call(pts, true)
		"more": dot.call(3.5, 8); dot.call(8, 8); dot.call(12.5, 8)
		"eye":
			arc.call(8, 13.5, 8.2, -PI * 0.82, -PI * 0.18); arc.call(8, 2.5, 8.2, PI * 0.18, PI * 0.82)
			ci.draw_arc(P.call(8, 8), 2 * s, 0, TAU, 16, color, width, true)
		"eye_off":
			arc.call(8, 13.5, 8.2, -PI * 0.82, -PI * 0.18); arc.call(8, 2.5, 8.2, PI * 0.18, PI * 0.82)
			line.call([Vector2(3, 13), Vector2(13, 3)])
		"lock":
			line.call([Vector2(3.5, 7.5), Vector2(12.5, 7.5), Vector2(12.5, 13.5), Vector2(3.5, 13.5)], true)
			arc.call(8, 7.5, 3, PI, TAU); dot.call(8, 10.5, 0.9)
		"unlock":
			line.call([Vector2(3.5, 7.5), Vector2(12.5, 7.5), Vector2(12.5, 13.5), Vector2(3.5, 13.5)], true)
			arc.call(8, 5.5, 3, PI, TAU * 0.93)
		"solo":
			arc.call(8, 9, 5, PI, TAU)
			line.call([Vector2(3, 9), Vector2(3, 12.5), Vector2(5, 12.5), Vector2(5, 9.5), Vector2(3, 9.5)])
			line.call([Vector2(13, 9), Vector2(13, 12.5), Vector2(11, 12.5), Vector2(11, 9.5), Vector2(13, 9.5)])
		"select": fill.call([Vector2(4, 2.5), Vector2(12.5, 9), Vector2(8.4, 9.6), Vector2(10.8, 13.4), Vector2(9.2, 14.2), Vector2(6.8, 10.4), Vector2(4, 13)])
		"note":
			ci.draw_style_box(_cap(color), Rect2(P.call(2.5, 6.5), Vector2(11, 3.2) * s))
		"hold":
			ci.draw_rect(Rect2(P.call(6.4, 2.5), Vector2(3.2, 9) * s), Color(color, 0.45))
			ci.draw_style_box(_cap(color), Rect2(P.call(2.5, 10.5), Vector2(11, 3.2) * s))
		"track":
			fill.call([Vector2(4, 13.5), Vector2(7, 2.5), Vector2(12, 2.5), Vector2(9.5, 13.5)])
		"shape_rect": line.call([Vector2(4, 3), Vector2(12, 3), Vector2(12, 13), Vector2(4, 13)], true)
		"shape_diamond": line.call([Vector2(8, 2.5), Vector2(13, 8), Vector2(8, 13.5), Vector2(3, 8)], true)
		"shape_circle": ci.draw_arc(P.call(8, 8), 5.5 * s, 0, TAU, 28, color, width, true)
		"shape_star":
			var pts := []
			for k in 10:
				var a := -PI / 2.0 + k * PI / 5.0
				pts.append(Vector2(8, 8.4) + Vector2(cos(a), sin(a)) * (6.0 if k % 2 == 0 else 2.6))
			line.call(pts, true)
		"shape_heart":
			arc.call(5.6, 6.2, 2.6, PI * 0.8, TAU); arc.call(10.4, 6.2, 2.6, PI, TAU + PI * 0.2)
			line.call([Vector2(3.1, 7.2), Vector2(8, 13), Vector2(12.9, 7.2)])
		"panel_left":
			line.call([Vector2(2.5, 3), Vector2(13.5, 3), Vector2(13.5, 13), Vector2(2.5, 13)], true); line.call([Vector2(6.5, 3), Vector2(6.5, 13)])
		"panel_right":
			line.call([Vector2(2.5, 3), Vector2(13.5, 3), Vector2(13.5, 13), Vector2(2.5, 13)], true); line.call([Vector2(9.5, 3), Vector2(9.5, 13)])
		"panel_bottom":
			line.call([Vector2(2.5, 3), Vector2(13.5, 3), Vector2(13.5, 13), Vector2(2.5, 13)], true); line.call([Vector2(2.5, 9.5), Vector2(13.5, 9.5)])
		"sparkle":
			for k in 10:
				var a := -PI / 2.0 + k * TAU / 10.0
				var r: float = 6.3 if k % 2 == 0 else 4.6
				ci.draw_line(P.call(8, 8) + Vector2(cos(a), sin(a)) * 1.2 * s, P.call(8, 8) + Vector2(cos(a), sin(a)) * r * s, color, width * 1.15, true)
		"close": line.call([Vector2(4, 4), Vector2(12, 12)]); line.call([Vector2(12, 4), Vector2(4, 12)])
		"chevron_down": line.call([Vector2(4.5, 6.5), Vector2(8, 10), Vector2(11.5, 6.5)])
		"chevron_right": line.call([Vector2(6.5, 4.5), Vector2(10, 8), Vector2(6.5, 11.5)])
		"chevron_left": line.call([Vector2(9.5, 4.5), Vector2(6, 8), Vector2(9.5, 11.5)])
		"plus": line.call([Vector2(8, 3.5), Vector2(8, 12.5)]); line.call([Vector2(3.5, 8), Vector2(12.5, 8)])
		"minus": line.call([Vector2(3.5, 8), Vector2(12.5, 8)])
		"braces":
			line.call([Vector2(6, 2.5), Vector2(4.6, 3.2), Vector2(4.6, 7), Vector2(3, 8), Vector2(4.6, 9), Vector2(4.6, 12.8), Vector2(6, 13.5)])
			line.call([Vector2(10, 2.5), Vector2(11.4, 3.2), Vector2(11.4, 7), Vector2(13, 8), Vector2(11.4, 9), Vector2(11.4, 12.8), Vector2(10, 13.5)])
		"history":
			arc.call(8, 8, 5.5, -PI * 0.9, PI * 1.1); line.call([Vector2(8, 5), Vector2(8, 8.3), Vector2(10.2, 9.6)])
			line.call([Vector2(1.6, 4.6), Vector2(2.7, 7.3), Vector2(5.2, 6.1)])
		"warning":
			line.call([Vector2(8, 2.5), Vector2(14, 13), Vector2(2, 13)], true); line.call([Vector2(8, 6.5), Vector2(8, 9.5)]); dot.call(8, 11.4, 0.85)
		"branch":
			ci.draw_arc(P.call(4.5, 3.8), 1.6 * s, 0, TAU, 14, color, width, true); ci.draw_arc(P.call(4.5, 12.2), 1.6 * s, 0, TAU, 14, color, width, true)
			ci.draw_arc(P.call(11.5, 5.5), 1.6 * s, 0, TAU, 14, color, width, true)
			line.call([Vector2(4.5, 5.4), Vector2(4.5, 10.6)]); line.call([Vector2(11.5, 7.1), Vector2(11.5, 8), Vector2(4.6, 10.3)])
		"wave":
			for k in 7:
				var hgt: float = [2.0, 5.0, 8.5, 4.0, 7.0, 3.0, 1.5][k]
				line.call([Vector2(2.5 + k * 1.85, 8 - hgt / 2.0), Vector2(2.5 + k * 1.85, 8 + hgt / 2.0)])
		"camera":
			line.call([Vector2(2.5, 4.5), Vector2(10.5, 4.5), Vector2(10.5, 11.5), Vector2(2.5, 11.5)], true)
			line.call([Vector2(10.5, 7), Vector2(13.5, 5), Vector2(13.5, 11), Vector2(10.5, 9)])
		"curve":
			var pts := []
			for k in 13:
				var f := k / 12.0
				pts.append(Vector2(2.5 + f * 11.0, 12.5 - SU.ease_in_out(f) * 9.0))
			line.call(pts)
		"sliders":
			line.call([Vector2(2.5, 5), Vector2(13.5, 5)]); line.call([Vector2(2.5, 11), Vector2(13.5, 11)])
			ci.draw_circle(P.call(10, 5), 1.9 * s, color, true, -1, true); ci.draw_circle(P.call(6, 11), 1.9 * s, color, true, -1, true)
		"preview":
			line.call([Vector2(2.5, 3.5), Vector2(13.5, 3.5), Vector2(13.5, 12.5), Vector2(2.5, 12.5)], true)
			fill.call([Vector2(6.7, 5.8), Vector2(10.5, 8), Vector2(6.7, 10.2)])
		"fingering":
			line.call([Vector2(2.5, 4.5), Vector2(13.5, 4.5), Vector2(13.5, 11.5), Vector2(2.5, 11.5)], true)
			for k in 3: dot.call(5 + k * 3, 8, 0.9)
		"window": line.call([Vector2(8, 2.5), Vector2(8, 13.5)]); line.call([Vector2(5, 4), Vector2(11, 4)]); line.call([Vector2(5, 12), Vector2(11, 12)])
		"keyboard":
			line.call([Vector2(2, 4.5), Vector2(14, 4.5), Vector2(14, 11.5), Vector2(2, 11.5)], true)
			for k in 4: dot.call(4.5 + k * 2.4, 7, 0.75)
			line.call([Vector2(5.5, 9.4), Vector2(10.5, 9.4)])
		"search": ci.draw_arc(P.call(7, 7), 4 * s, 0, TAU, 20, color, width, true); line.call([Vector2(10, 10), Vector2(13.5, 13.5)])
		"motion":
			var pts := []
			for k in 9:
				var f := k / 8.0
				pts.append(Vector2(3 + f * 4 + SU.ease_out(f) * 5.0, 2.5 + f * 9.0))
			line.call(pts); ci.draw_style_box(_cap(color), Rect2(P.call(7.5, 11.5), Vector2(6, 2.6) * s))
		"node":
			line.call([Vector2(5, 5), Vector2(11, 5), Vector2(11, 11), Vector2(5, 11)], true)
		"send": line.call([Vector2(8, 13), Vector2(8, 3.5)]); line.call([Vector2(4, 7.5), Vector2(8, 3.5), Vector2(12, 7.5)])
		"stop": fill.call([Vector2(4.5, 4.5), Vector2(11.5, 4.5), Vector2(11.5, 11.5), Vector2(4.5, 11.5)])
		"trash":
			line.call([Vector2(2.5, 4.5), Vector2(13.5, 4.5)]); line.call([Vector2(6, 4.5), Vector2(6.5, 2.5), Vector2(9.5, 2.5), Vector2(10, 4.5)])
			line.call([Vector2(4, 4.5), Vector2(4.8, 13.5), Vector2(11.2, 13.5), Vector2(12, 4.5)])
		"copy":
			line.call([Vector2(5.5, 5.5), Vector2(13, 5.5), Vector2(13, 13.5), Vector2(5.5, 13.5)], true)
			line.call([Vector2(3, 10.5), Vector2(3, 2.5), Vector2(10.5, 2.5)])
		_: dot.call(8, 8, 2)

static func _cap(color: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new(); b.bg_color = color; b.set_corner_radius_all(3); b.anti_aliasing = true
	return b
