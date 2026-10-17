## Compatibility data exported by the built-in plugin.
class_name BuiltinRenderData
extends RefCounted

const LayerScript := preload("res://scripts/layer.gd")
const LW := SU.LW
const LH := SU.LH
const HY0 := 0.09 * 1080.0          # 2026-10-16: bigger field (was 0.12) -- "the playing area is too small"
const S0 := 0.1
const GAMMA0 := 0.30                # less narrowing toward the top (was 0.38)
const ARC0 := 0.8                   # arch of the field (Geo.yb)
const AXIS := 6.75 / 15.0          # track axis over the G|H gap: the "( )" is centred on the player's hands
const PK := 1.0 / 0.1 - 1.0
const PEDAL_XL := [-0.045, 1.045]
const MISS_GREY := Color(0.62, 0.62, 0.62)
const TEX_NAMES := ["bg", "note", "hold", "lane", "judge", "pedal", "receptor", "j_perfect", "j_great", "j_good", "j_miss", "fc", "ap", "line", "dash", "glow", "shell", "note_ex", "string", "beam_core", "beam_fiber_a", "beam_fiber_b", "beam_fiber_c", "haze", "lane_clean", "track_flat", "bg_scene"]
const PALETTE := [Color(0.75, 0.86, 1.0), Color(1.0, 0.75, 0.81), Color(0.75, 1.0, 0.87), Color(1.0, 0.90, 0.75),
	Color(0.85, 0.75, 1.0), Color(0.75, 0.95, 1.0), Color(1.0, 0.83, 0.75), Color(0.92, 0.80, 1.0),
	Color(0.75, 0.97, 0.83), Color(1.0, 0.97, 0.92)]
const KEY_GUIDES := [[5.25, 0.16], [8.25, 0.16], [1.125, 0.10], [13.625, 0.10]]
const CARRIER_TINT := [Color(0.86, 0.93, 1.0), Color(1.0, 0.91, 0.93), Color(0.88, 1.0, 0.95), Color(1.0, 0.96, 0.86),
	Color(0.93, 0.89, 1.0), Color(0.86, 0.98, 1.0)]
const STAGE_TINT := [Color(0.86, 0.92, 1.0), Color(1.0, 0.90, 0.92), Color(0.84, 0.97, 1.0), Color(1.0, 0.95, 0.84)]

class Geo:
	var l: float
	var r: float
	var D: float
	var cx: float
	var jy: float:
		set(value): jy = value; _depths.clear(); revision += 1
	var key_w: float
	var hy: float:
		set(value): hy = value; _depths.clear(); revision += 1
	var gam: float:
		set(value): gam = value; _depths.clear(); revision += 1
	var z: float:
		set(value): z = value; _depths.clear(); revision += 1
	var shx: float
	var shy: float:
		set(value): shy = value; _depths.clear(); revision += 1
	var shear: float:
		set(value): shear = value; _depths.clear(); revision += 1
	var vpx: float:
		set(value): vpx = value; _depths.clear(); revision += 1
	var arc := 0.0:
		set(value): arc = value; _depths.clear(); revision += 1
	var revision := 0
	var ys := PackedFloat64Array()
	var _depths := {}             # one geometry instance; all layers share exact double samples
	func depth(s: float) -> PackedFloat64Array:
		if _depths.has(s): return _depths[s]
		var ww := w(s)
		var yy := yb(s)
		var sample := PackedFloat64Array([ww, yy, pow(maxf(s, 0.0), gam), 1.0 + z * ww,
			vpx * ww, (jy - yy) * shear * ww, jy + (yy - jy) * (1.0 + z * ww) + shy * ww])
		if _depths.size() >= 4096: _depths.clear()
		_depths[s] = sample
		return sample
	func w(s: float) -> float:
		return 0.0 if s >= 1.0 else pow(1.0 - maxf(0.0, s), 1.5)
	## depth -> screen height.  arc > 0 stretches the near half (bottom) over more of the screen and folds the far half
	## toward the horizon -- the field becomes an arch: wide and tall near the line, curving away at the top
	func yb(s: float) -> float:
		if arc <= 0.0: return hy + (jy - hy) * s
		var h := jy - hy
		if s >= 1.0: return jy + h * (s - 1.0) / (1.0 - BuiltinRenderData.S0) * (1.0 + arc)
		var v := clampf((1.0 - s) / (1.0 - BuiltinRenderData.S0), 0.0, 1.0)
		return jy - h * v * (1.0 + arc * (1.0 - v))
	func y_of(s: float) -> float:
		var sample := depth(s)
		return sample[6]
	func x_of(xl: float, s: float) -> float:
		var sample := depth(s)
		return cx + (xl - BuiltinRenderData.AXIS) * D * sample[2] * sample[3] + sample[4] + sample[5]
	func build_inverse() -> void:
		_depths.clear()
		ys.resize(161)
		for i in 161:
			ys[i] = y_of(1.25 * i / 160.0)
	func s_of_y(y: float) -> float:
		if y <= ys[0]: return 0.0
		var lo := 0
		var hi := 160
		while hi - lo > 1:
			var m := (lo + hi) >> 1
			if ys[m] <= y: lo = m
			else: hi = m
		var fr := (y - ys[lo]) / maxf(1e-6, ys[hi] - ys[lo])
		return 1.25 * (lo + fr) / 160.0

