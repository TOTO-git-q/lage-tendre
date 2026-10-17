extends RefCounted
## Charter design tokens and Godot Theme, after the Claude Design System storybook:
## four calm surface levels, one clay accent, soft 1 px borders, 8/10/12/20 px radii,
## serif display + clean sans UI; tabular figures for numbers, mono only for time codes and
## typed numeric fields.
##
## Type scale (px at the 1600 x 900 design size; the whole UI scales with the window):
##   XS 12  axis ticks, badges         BODY 14  all UI text, labels, buttons, hints
##   MD 16  headings, the clock        LG 20    pane titles (serif), summary figures
##   XL 28  song title (serif display)
## Icon sizes: 20 in the top bar, 18 in tool rows, 16 inline; hit targets 32-36.

static var light := false
const XS := 12
const BODY := 14
const MD := 16
const LG := 20
const XL := 28
static var _fonts := {}

const CLAY := Color("d97757")
const CLAY_HOVER := Color("cc5a36")
const DANGER := Color("d0614f")
const OK := Color("6f9f86")
const GOLD := Color("e0b45e")

static func tokens(is_light: bool = light) -> Dictionary:
	if is_light:
		return {"bg": Color("f5f5f3"), "s1": Color("fcfcfb"), "s2": Color("ffffff"), "s3": Color("ffffff"), "field": Color("fbfbfa"),
			"border": Color(0, 0, 0, 0.085), "border_strong": Color(0, 0, 0, 0.16), "text": Color("1f1e1d"), "muted": Color("6b6863"),
			"faint": Color("a4a19b"), "hover": Color(0, 0, 0, 0.045), "press": Color(0, 0, 0, 0.08), "clay": CLAY, "clay_soft": Color("fbf3ef"),
			"clay_tint": Color(0.851, 0.467, 0.341, 0.14), "shadow": Color(0, 0, 0, 0.07), "grid": Color(0, 0, 0, 0.05), "grid_beat": Color(0, 0, 0, 0.09),
			"grid_bar": Color(0, 0, 0, 0.17), "note": Color("3a3936"), "note_ex": Color("b5852a"), "danger": DANGER, "ok": OK, "canvas": Color("fdfdfc")}
	return {"bg": Color("0b0b0a"), "s1": Color("151515"), "s2": Color("1a1a19"), "s3": Color("20201e"), "field": Color("121211"),
		"border": Color(1, 1, 1, 0.075), "border_strong": Color(1, 1, 1, 0.14), "text": Color("ecebe7"), "muted": Color("a4a19b"),
		"faint": Color("6b6863"), "hover": Color(1, 1, 1, 0.05), "press": Color(1, 1, 1, 0.09), "clay": CLAY, "clay_soft": Color(0.851, 0.467, 0.341, 0.16),
		"clay_tint": Color(0.851, 0.467, 0.341, 0.16), "shadow": Color(0, 0, 0, 0.45), "grid": Color(1, 1, 1, 0.035), "grid_beat": Color(1, 1, 1, 0.07),
		"grid_bar": Color(1, 1, 1, 0.15), "note": Color("e9e6df"), "note_ex": GOLD, "danger": DANGER, "ok": OK, "canvas": Color("111110")}

static func c(name: String) -> Color:
	return tokens()[name]

## Restrained track tints: the game palette pulled toward the surface so bands stay calm.
static func tint(index: int, is_light: bool = light) -> Color:
	if index < 0 or index > 9: return Color("b9b6ae") if not is_light else Color("8d8a83")
	var base: Color = Renderer.PALETTE[index]
	var hsv := Color.from_hsv(base.h, minf(1.0, base.s * 2.4), 0.86 if not is_light else 0.62)
	return hsv

static func font(kind: String = "sans", weight: int = 400) -> Font:
	var key := kind + str(weight)
	if _fonts.has(key): return _fonts[key]
	if kind == "num":
		# the UI sans with tabular figures, for numbers that line up (counts, ids, ruler values)
		var v := FontVariation.new(); v.base_font = font("sans", weight)
		v.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
		_fonts[key] = v
		return v
	var f := SystemFont.new()
	match kind:
		"serif": f.font_names = PackedStringArray(["Newsreader", "Georgia", "Source Han Serif SC", "SimSun"])
		"mono": f.font_names = PackedStringArray(["JetBrains Mono", "Cascadia Mono", "Consolas", "Microsoft YaHei UI"])
		_: f.font_names = PackedStringArray(["Inter", "Segoe UI Variable Text", "Segoe UI", "Microsoft YaHei UI"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_fonts[key] = f
	return f

static func box(bg: Color, radius: int = 8, border: Color = Color.TRANSPARENT, pad_h: int = 10, pad_v: int = 6, bw: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg; b.set_corner_radius_all(radius); b.corner_detail = 8
	if border.a > 0: b.border_color = border; b.set_border_width_all(bw)
	b.content_margin_left = pad_h; b.content_margin_right = pad_h; b.content_margin_top = pad_v; b.content_margin_bottom = pad_v
	b.anti_aliasing = true
	return b

static func card(is_light: bool = light, radius: int = 12) -> StyleBoxFlat:
	var t := tokens(is_light)
	var b := box(t.s1, radius, t.border, 0, 0)
	return b

static func popup_box(is_light: bool = light) -> StyleBoxFlat:
	var t := tokens(is_light)
	var b := box(t.s3, 10, t.border_strong, 6, 6)
	b.shadow_color = t.shadow; b.shadow_size = 14; b.shadow_offset = Vector2(0, 4)
	return b

static func _blank_icon(size: int = 1) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8); img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

## Small anti-aliased raster glyphs for built-in controls (checks, chevrons), drawn with SDFs.
static func glyph(kind: String, color: Color, accent: Color, size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var ss := 4
	for y in size:
		for x in size:
			var cov := 0.0; var acc := 0.0
			for sy in ss:
				for sx in ss:
					var p := Vector2(x + (sx + 0.5) / ss, y + (sy + 0.5) / ss) / size * 16.0
					var r := _glyph_hit(kind, p)
					cov += r.x; acc += r.y
			cov /= ss * ss; acc /= ss * ss
			var col := color.lerp(accent, acc / maxf(cov, 0.0001)) if cov > 0 else color
			img.set_pixel(x, y, Color(col, cov * col.a))
	return ImageTexture.create_from_image(img)

static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a; var t := clampf((p - a).dot(ab) / ab.length_squared(), 0, 1)
	return p.distance_to(a + ab * t)

static func _rrect_d(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	var q := (p - c).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0) - r

## returns (coverage, accent coverage) at p in a 16-unit box
static func _glyph_hit(kind: String, p: Vector2) -> Vector2:
	match kind:
		"chevron":
			var d := minf(_seg_d(p, Vector2(4.5, 6.5), Vector2(8, 10)), _seg_d(p, Vector2(8, 10), Vector2(11.5, 6.5)))
			return Vector2(1.0 if d < 0.9 else 0.0, 0)
		"chevron_r":
			var d := minf(_seg_d(p, Vector2(6.5, 4.5), Vector2(10, 8)), _seg_d(p, Vector2(10, 8), Vector2(6.5, 11.5)))
			return Vector2(1.0 if d < 0.9 else 0.0, 0)
		"check_on":
			var box_in := _rrect_d(p, Vector2(8, 8), Vector2(6, 6), 2.5) < 0
			var tick := minf(_seg_d(p, Vector2(5, 8.2), Vector2(7.2, 10.4)), _seg_d(p, Vector2(7.2, 10.4), Vector2(11.2, 5.8))) < 0.95
			return Vector2(1.0 if box_in else 0.0, 1.0 if box_in and not tick else 0.0)
		"check_off":
			var d := absf(_rrect_d(p, Vector2(8, 8), Vector2(5.5, 5.5), 2.2))
			return Vector2(1.0 if d < 0.6 else 0.0, 0)
		"radio_on":
			var d := p.distance_to(Vector2(8, 8))
			return Vector2(1.0 if d < 6 else 0.0, 1.0 if d < 6 and d > 2.6 else 0.0)
		"radio_off":
			return Vector2(1.0 if absf(p.distance_to(Vector2(8, 8)) - 5.5) < 0.6 else 0.0, 0)
		"grabber":
			return Vector2(1.0 if p.distance_to(Vector2(8, 8)) < 6 else 0.0, 0)
	return Vector2.ZERO

static func make(is_light: bool) -> Theme:
	light = is_light
	var t := tokens(is_light)
	var th := Theme.new()
	th.default_font = font("sans"); th.default_font_size = BODY
	var text: Color = t.text
	# ---- labels: hierarchy by size, weight and colour (words never below BODY)
	th.set_color("font_color", "Label", text)
	for v in [["Muted", t.muted, BODY, "sans", 400], ["Faint", t.faint, BODY, "sans", 400], ["Section", t.muted, BODY, "sans", 600],
			["Title", text, LG, "serif", 400], ["Display", text, XL, "serif", 400], ["Heading", text, MD, "sans", 600],
			["Num", text, BODY, "num", 400], ["NumMuted", t.muted, BODY, "num", 400],
			["Mono", text, BODY, "mono", 400], ["MonoMuted", t.muted, BODY, "mono", 400]]:
		th.set_type_variation(v[0], "Label")
		th.set_color("font_color", v[0], v[1]); th.set_font_size("font_size", v[0], v[2]); th.set_font("font", v[0], font(v[3], v[4]))
	th.set_color("default_color", "RichTextLabel", text)
	th.set_font_size("normal_font_size", "RichTextLabel", BODY)
	th.set_font("mono_font", "RichTextLabel", font("mono")); th.set_font("bold_font", "RichTextLabel", font("sans", 600))
	# ---- buttons: quiet secondary by default, ghost and primary variations
	var btn := box(t.s2, 8, t.border, 12, 7)
	th.set_stylebox("normal", "Button", btn)
	var bh := box(t.s3, 8, t.border_strong, 12, 7); th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", box(t.press, 8, t.border_strong, 12, 7))
	th.set_stylebox("hover_pressed", "Button", box(t.press, 8, t.border_strong, 12, 7))
	th.set_stylebox("disabled", "Button", box(Color(t.s2, 0.5), 8, t.border, 12, 7))
	th.set_stylebox("focus", "Button", box(Color.TRANSPARENT, 8, Color(CLAY, 0.75), 12, 7, 2))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: th.set_color(k, "Button", text)
	th.set_color("font_disabled_color", "Button", t.faint)
	th.set_constant("h_separation", "Button", 6)
	th.set_type_variation("Ghost", "Button")
	th.set_stylebox("focus", "Ghost", box(Color.TRANSPARENT, 8, Color(CLAY, 0.75), 10, 7, 2))
	th.set_stylebox("normal", "Ghost", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 10, 7))
	th.set_stylebox("hover", "Ghost", box(t.hover, 8, Color.TRANSPARENT, 10, 7))
	th.set_stylebox("pressed", "Ghost", box(t.press, 8, Color.TRANSPARENT, 10, 7))
	th.set_stylebox("hover_pressed", "Ghost", box(t.press, 8, Color.TRANSPARENT, 10, 7))
	th.set_color("font_color", "Ghost", t.muted); th.set_color("font_hover_color", "Ghost", text); th.set_color("font_pressed_color", "Ghost", text)
	th.set_type_variation("Primary", "Button")
	th.set_stylebox("normal", "Primary", box(CLAY, 8, Color.TRANSPARENT, 16, 7))
	th.set_stylebox("hover", "Primary", box(CLAY_HOVER, 8, Color.TRANSPARENT, 16, 7))
	th.set_stylebox("pressed", "Primary", box(CLAY_HOVER.darkened(0.1), 8, Color.TRANSPARENT, 16, 7))
	th.set_stylebox("disabled", "Primary", box(Color(CLAY, 0.35), 8, Color.TRANSPARENT, 16, 7))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: th.set_color(k, "Primary", Color.WHITE)
	th.set_color("font_disabled_color", "Primary", Color(1, 1, 1, 0.7))
	th.set_font("font", "Primary", font("sans", 600))
	# ---- option buttons
	for k in ["normal", "hover", "pressed", "disabled", "focus"]: th.set_stylebox(k, "OptionButton", th.get_stylebox(k, "Button"))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: th.set_color(k, "OptionButton", text)
	th.set_icon("arrow", "OptionButton", glyph("chevron", t.muted, t.muted, 18))
	th.set_constant("arrow_margin", "OptionButton", 10)
	th.set_type_variation("GhostOption", "OptionButton")
	th.set_stylebox("normal", "GhostOption", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 10, 7))
	th.set_stylebox("hover", "GhostOption", box(t.hover, 8, Color.TRANSPARENT, 10, 7))
	th.set_stylebox("pressed", "GhostOption", box(t.press, 8, Color.TRANSPARENT, 10, 7))
	for k in ["normal", "hover", "pressed"]: th.set_stylebox(k, "MenuButton", th.get_stylebox(k, "Ghost"))
	th.set_color("font_color", "MenuButton", t.muted); th.set_color("font_hover_color", "MenuButton", text)
	# ---- text inputs (Composer radius 20 lives on its panel)
	var field := box(t.field, 8, t.border, 10, 7)
	th.set_stylebox("normal", "LineEdit", field)
	th.set_stylebox("focus", "LineEdit", box(t.field, 8, Color(CLAY, 0.75), 10, 7))
	th.set_stylebox("read_only", "LineEdit", box(Color.TRANSPARENT, 8, t.border, 10, 7))
	th.set_font("font", "LineEdit", font("num"))
	th.set_color("font_color", "LineEdit", text); th.set_color("font_placeholder_color", "LineEdit", t.faint)
	th.set_color("caret_color", "LineEdit", CLAY); th.set_color("selection_color", "LineEdit", Color(CLAY, 0.3))
	th.set_type_variation("FlatEdit", "LineEdit")
	th.set_stylebox("normal", "FlatEdit", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 6, 4))
	th.set_stylebox("focus", "FlatEdit", box(t.field, 6, Color(CLAY, 0.75), 6, 4))
	th.set_font("font", "FlatEdit", font("mono")); th.set_font_size("font_size", "FlatEdit", BODY)
	th.set_stylebox("normal", "TextEdit", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 4, 4))
	th.set_stylebox("focus", "TextEdit", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 4, 4))
	th.set_stylebox("read_only", "TextEdit", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 4, 4))
	th.set_color("font_color", "TextEdit", text); th.set_color("font_placeholder_color", "TextEdit", t.faint)
	th.set_color("font_readonly_color", "TextEdit", t.muted); th.set_color("caret_color", "TextEdit", CLAY)
	th.set_color("selection_color", "TextEdit", Color(CLAY, 0.3)); th.set_color("background_color", "TextEdit", Color.TRANSPARENT)
	th.set_type_variation("Code", "TextEdit")
	th.set_font("font", "Code", font("mono")); th.set_font_size("font_size", "Code", 13)
	# ---- panels
	th.set_stylebox("panel", "PanelContainer", box(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 0))
	th.set_type_variation("Card", "PanelContainer"); th.set_stylebox("panel", "Card", card(is_light))
	th.set_type_variation("Pane", "PanelContainer"); th.set_stylebox("panel", "Pane", box(t.s1, 12, t.border, 14, 12))
	th.set_type_variation("Bar", "PanelContainer"); th.set_stylebox("panel", "Bar", box(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 0))
	th.set_type_variation("Bubble", "PanelContainer"); th.set_stylebox("panel", "Bubble", box(t.s3, 14, t.border, 12, 8))
	th.set_type_variation("ToolCard", "PanelContainer"); th.set_stylebox("panel", "ToolCard", box(Color.TRANSPARENT, 10, t.border, 10, 6))
	var composer := box(t.s2 if not is_light else Color.WHITE, 20, t.border_strong, 14, 10)
	composer.shadow_color = Color(0, 0, 0, 0.035 if is_light else 0.3); composer.shadow_size = 10; composer.shadow_offset = Vector2(0, 3)
	th.set_type_variation("Composer", "PanelContainer"); th.set_stylebox("panel", "Composer", composer)
	var float_card := popup_box(is_light); float_card.content_margin_left = 14; float_card.content_margin_right = 14; float_card.content_margin_top = 12; float_card.content_margin_bottom = 12
	th.set_type_variation("Float", "PanelContainer"); th.set_stylebox("panel", "Float", float_card)
	th.set_stylebox("panel", "PopupPanel", popup_box(is_light))
	# ---- popups / menus
	th.set_stylebox("panel", "PopupMenu", popup_box(is_light))
	th.set_stylebox("hover", "PopupMenu", box(t.hover if not is_light else Color(0, 0, 0, 0.05), 6, Color.TRANSPARENT, 8, 4))
	th.set_stylebox("separator", "PopupMenu", box(t.border, 0, Color.TRANSPARENT, 0, 0))
	th.set_color("font_color", "PopupMenu", text); th.set_color("font_hover_color", "PopupMenu", text)
	th.set_color("font_disabled_color", "PopupMenu", t.faint); th.set_color("font_separator_color", "PopupMenu", t.faint)
	th.set_color("font_accelerator_color", "PopupMenu", t.faint)
	th.set_constant("v_separation", "PopupMenu", 12); th.set_constant("h_separation", "PopupMenu", 10); th.set_constant("item_start_padding", "PopupMenu", 10); th.set_constant("item_end_padding", "PopupMenu", 12)
	th.set_font_size("font_size", "PopupMenu", BODY); th.set_font_size("font_separator_size", "PopupMenu", BODY)
	th.set_icon("checked", "PopupMenu", glyph("check_on", CLAY, Color.WHITE, 18)); th.set_icon("unchecked", "PopupMenu", glyph("check_off", t.muted, t.muted, 18))
	th.set_icon("radio_checked", "PopupMenu", glyph("radio_on", CLAY, Color.WHITE, 18)); th.set_icon("radio_unchecked", "PopupMenu", glyph("radio_off", t.muted, t.muted, 18))
	th.set_icon("submenu", "PopupMenu", glyph("chevron_r", t.muted, t.muted, 18))
	th.set_stylebox("panel", "TooltipPanel", box(t.s3, 8, t.border_strong, 10, 6))
	th.set_color("font_color", "TooltipLabel", text); th.set_font_size("font_size", "TooltipLabel", BODY)
	# ---- checkboxes (rare: dialogs)
	for type in ["CheckBox", "CheckButton"]:
		for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]: th.set_stylebox(k, type, box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 4, 4))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: th.set_color(k, type, text)
	th.set_icon("checked", "CheckBox", glyph("check_on", CLAY, Color.WHITE, 18)); th.set_icon("unchecked", "CheckBox", glyph("check_off", t.muted, t.muted, 18))
	# ---- lists, scroll, splits
	th.set_stylebox("panel", "ItemList", box(Color.TRANSPARENT, 8, Color.TRANSPARENT, 2, 2))
	th.set_stylebox("hovered", "ItemList", box(t.hover, 6, Color.TRANSPARENT, 8, 4))
	th.set_stylebox("selected", "ItemList", box(t.clay_tint, 6, Color.TRANSPARENT, 8, 4))
	th.set_stylebox("selected_focus", "ItemList", box(t.clay_tint, 6, Color.TRANSPARENT, 8, 4))
	th.set_stylebox("focus", "ItemList", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 0))
	th.set_stylebox("cursor", "ItemList", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 0))
	th.set_stylebox("cursor_unfocused", "ItemList", box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 0, 0))
	th.set_color("font_color", "ItemList", text); th.set_color("font_hovered_color", "ItemList", text); th.set_color("font_selected_color", "ItemList", text)
	th.set_constant("v_separation", "ItemList", 8); th.set_constant("line_separation", "ItemList", 2)
	th.set_font_size("font_size", "ItemList", BODY)
	for type in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", type, box(Color.TRANSPARENT, 99, Color.TRANSPARENT, 3, 3))
		th.set_stylebox("grabber", type, box(Color(0.59, 0.59, 0.59, 0.25), 99, Color.TRANSPARENT, 3, 3))
		th.set_stylebox("grabber_highlight", type, box(Color(0.59, 0.59, 0.59, 0.4), 99, Color.TRANSPARENT, 3, 3))
		th.set_stylebox("grabber_pressed", type, box(Color(0.59, 0.59, 0.59, 0.5), 99, Color.TRANSPARENT, 3, 3))
	for type in ["HSplitContainer", "VSplitContainer", "SplitContainer"]:
		th.set_icon("grabber", type, _blank_icon()); th.set_icon("h_grabber", type, _blank_icon()); th.set_icon("v_grabber", type, _blank_icon())
		th.set_constant("separation", type, 8); th.set_constant("minimum_grab_thickness", type, 8); th.set_constant("autohide", type, 1)
	th.set_constant("separation", "VBoxContainer", 8); th.set_constant("separation", "HBoxContainer", 8)
	th.set_constant("separation", "HSeparator", 1); th.set_constant("separation", "VSeparator", 1)
	th.set_stylebox("separator", "HSeparator", box(t.border, 0, Color.TRANSPARENT, 0, 0))
	th.set_stylebox("separator", "VSeparator", box(t.border, 0, Color.TRANSPARENT, 0, 0))
	# ---- dialogs
	th.set_stylebox("panel", "AcceptDialog", box(t.s3, 12, t.border_strong, 18, 16))
	th.set_stylebox("embedded_border", "Window", popup_box(is_light))
	th.set_color("title_color", "Window", text); th.set_font_size("title_font_size", "Window", BODY)
	th.set_constant("buttons_separation", "AcceptDialog", 8)
	return th
