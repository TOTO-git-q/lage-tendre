## Test-only nested CPU attribution; production has no timers.
extends BuiltinRendererRuntime

var timings := {}
var counts := {}

func record(key: String, since: int) -> void:
	timings[key] = int(timings.get(key, 0)) + Time.get_ticks_usec() - since
	counts[key] = int(counts.get(key, 0)) + 1

func band(c: CanvasItem, tex: Texture2D, xl0: float, xl1: float, s0: float, s1: float, alpha: float, pad_k: float, fade_top := 0.0, v0 := 0.0, v1 := 1.0, col := Color.WHITE) -> void:
	var before := Time.get_ticks_usec()
	super.band(c, tex, xl0, xl1, s0, s1, alpha, pad_k, fade_top, v0, v1, col)
	record("band", before)

func curve_line(c: CanvasItem, xl: float, s0: float, s1: float, a0: float, a_mid: float, a1: float, width: float, steps := 32) -> void:
	var before := Time.get_ticks_usec()
	super.curve_line(c, xl, s0, s1, a0, a_mid, a1, width, steps)
	record("curve_line", before)

func _line_strip(c: CanvasItem, x0: float, x1: float, h: float, a: float) -> void:
	var before := Time.get_ticks_usec()
	super._line_strip(c, x0, x1, h, a)
	record("line_strip", before)

func _plan_notes() -> void:
	var before := Time.get_ticks_usec()
	super._plan_notes()
	record("plan_notes", before)

func _geo() -> Geo:
	var before := Time.get_ticks_usec()
	var result := super._geo()
	record("geo", before)
	return result
