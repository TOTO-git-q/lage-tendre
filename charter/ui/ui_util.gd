extends RefCounted
## Shared input/measure helpers for the Charter UI.
const Tokens = preload("res://theme.gd")

static func step_mod(e: InputEvent) -> float:
	if e is InputEventWithModifiers:
		if e.shift_pressed: return 10.0
		if e.ctrl_pressed or e.alt_pressed: return 0.1
	return 1.0

static func wheel_dir(e: InputEvent) -> int:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: return 1
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN: return -1
	return 0

static func text_width(text: String, size: int = 14, f: Font = null) -> float:
	var font: Font = f if f != null else Tokens.font("sans")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A label's text never contributes to the layout. A positive width reserves a
## fixed slot; width zero fills the space allocated by its parent.
static func bounded_label(label: Label, width: float = 0.0, numeric := false, text_tooltip := true) -> void:
	label.clip_text = true
	label.max_lines_visible = 1
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_FILL if width > 0 else Control.SIZE_EXPAND_FILL
	if numeric: label.add_theme_font_override("font", Tokens.font("num"))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if text_tooltip and not label.has_meta("bounded_tooltip"):
		label.set_meta("bounded_tooltip", true)
		label.draw.connect(func(): label.tooltip_text = label.text)

static func bounded_option(button: OptionButton, width: float) -> void:
	button.fit_to_longest_item = false
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.x = width
	button.size_flags_horizontal = Control.SIZE_FILL

## Quantise only the clock, never the document/MCP position or the playhead.
## Fractions are whole-note units, like the canonical format, bounded by grid.
static func clock_position(doc, seconds: float, grid: int) -> String:
	var segment: Dictionary = doc.timing()[0]
	for candidate in doc.timing():
		if candidate.t <= seconds: segment = candidate
	var step: float = float(segment.beat) * 4.0 / maxi(1, grid)
	var at: float = float(segment.t) + roundf((seconds - float(segment.t)) / step) * step
	var p: Dictionary = doc.position(at)
	var whole := floori(float(p.beat) + 0.000001)
	var numerator := roundi((float(p.beat) - whole) * grid)
	var divisor := grid * 4
	var word := "%d.%d" % [int(p.bar), whole]
	if numerator == 0: return word
	var a := numerator; var b := divisor
	while b != 0:
		var remainder := a % b; a = b; b = remainder
	return word + "·%d/%d" % [numerator / a, divisor / a]

static func clock_seconds(seconds: float) -> String:
	var centis := maxi(0, roundi(seconds * 100.0))
	return "%d:%02d.%02d" % [centis / 6000, (centis / 100) % 60, centis % 100]
