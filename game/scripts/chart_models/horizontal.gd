extends RefCounted
## 水平: the note appears offset sideways and slides to its landing x during part of the fall.
const ID := "horizontal"
const LABEL := "水平"

static func params() -> Array:
	return [
		{"key": "from", "label": "起点偏移", "unit": "键", "default": -3.0, "min": -15.0, "max": 15.0, "step": 0.25},
		{"key": "begin", "label": "开始于", "unit": "%", "default": 0.0, "min": 0.0, "max": 95.0, "step": 5.0},
		{"key": "end", "label": "到位于", "unit": "%", "default": 70.0, "min": 5.0, "max": 100.0, "step": 5.0},
		{"key": "ease", "label": "曲线", "options": ["linear", "in", "out", "inout"], "default": "out"},
	]

static func offset(p: Dictionary, r: float, _ctx: Dictionary) -> float:
	var progress := 1.0 - r / 1.3
	var b := float(p.begin) / 100.0; var e := maxf(b + 0.01, float(p.end) / 100.0)
	var f := clampf((progress - b) / (e - b), 0.0, 1.0)
	return float(p.from) / 15.0 * (1.0 - SU.ease_by(str(p.ease), f))

static func start(p: Dictionary, _ctx: Dictionary) -> float:
	return float(p.from) / 15.0

static func with_start(p: Dictionary, x_offset: float, _ctx: Dictionary) -> Dictionary:
	var out := p.duplicate(); out.from = snappedf(x_offset * 15.0, 0.25)
	return out
