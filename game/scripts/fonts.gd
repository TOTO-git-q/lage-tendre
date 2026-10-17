## System fonts (no font files shipped): UI = Segoe UI Light / YaHei / Yu Gothic, HUD digits = Bahnschrift.
class_name Fonts

static var _ui: SystemFont
static var _hud: SystemFont
static var _var := {}
static var _title: SystemFont

## the title logo: a book serif, a quiet nod to Deemo's typography
static func title() -> SystemFont:
	if _title == null:
		_title = SystemFont.new()
		_title.font_names = PackedStringArray(["Palatino Linotype", "Constantia", "Georgia", "serif"])
		_title.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _title

static func ui() -> SystemFont:
	if _ui == null:
		_ui = SystemFont.new()
		_ui.font_names = PackedStringArray(["Segoe UI Light", "Segoe UI", "Microsoft YaHei UI Light", "Microsoft YaHei UI", "Yu Gothic UI Light", "Yu Gothic UI", "sans-serif"])
		_ui.font_weight = 300
		_ui.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_ui.hinting = TextServer.HINTING_LIGHT
	return _ui

static func hud() -> SystemFont:
	if _hud == null:
		_hud = SystemFont.new()
		_hud.font_names = PackedStringArray(["Bahnschrift Light", "Bahnschrift", "Segoe UI Light", "Segoe UI", "sans-serif"])
		_hud.font_weight = 300
		_hud.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _hud

## a letter-spaced variation (spacing in px, as CSS letter-spacing)
static func spaced(base: Font, spacing: int) -> Font:
	if spacing == 0:
		return base
	var key := str(base.get_instance_id()) + ":" + str(spacing)
	if not _var.has(key):
		var v := FontVariation.new()
		v.base_font = base
		v.spacing_glyph = spacing
		_var[key] = v
	return _var[key]
