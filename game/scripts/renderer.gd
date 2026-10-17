## Compatibility facade; all behavior is supplied by registered plugins (API 1).
class_name Renderer
extends Node2D

const LayerScript = BuiltinRenderData.LayerScript
const LW = BuiltinRenderData.LW
const LH = BuiltinRenderData.LH
const HY0 = BuiltinRenderData.HY0
const S0 = BuiltinRenderData.S0
const GAMMA0 = BuiltinRenderData.GAMMA0
const ARC0 = BuiltinRenderData.ARC0
const AXIS = BuiltinRenderData.AXIS
const PK = BuiltinRenderData.PK
const PEDAL_XL = BuiltinRenderData.PEDAL_XL
const MISS_GREY = BuiltinRenderData.MISS_GREY
const TEX_NAMES = BuiltinRenderData.TEX_NAMES
const PALETTE = BuiltinRenderData.PALETTE
const KEY_GUIDES = BuiltinRenderData.KEY_GUIDES
const CARRIER_TINT = BuiltinRenderData.CARRIER_TINT
const STAGE_TINT = BuiltinRenderData.STAGE_TINT
const Geo = BuiltinRenderData.Geo

var registry: PluginRegistry
var _runtime: Node2D

func _init(scope: PluginRegistry = null) -> void:
	registry = scope if scope != null else PluginRegistry.standard()
	_runtime = registry.service_script("renderer").new()
	_runtime.configure(registry)
	add_child(_runtime)

var TEX: Dictionary:
	get: return _runtime.TEX
	set(value): _runtime.TEX = value

var hy0: Variant:
	get: return _runtime.hy0
	set(value): _runtime.hy0 = value

var gamma0: Variant:
	get: return _runtime.gamma0
	set(value): _runtime.gamma0 = value

var arc0: Variant:
	get: return _runtime.arc0
	set(value): _runtime.arc0 = value

var judge_y: Variant:
	get: return _runtime.judge_y
	set(value): _runtime.judge_y = value

var line_l: float:
	get: return _runtime.line_l
	set(value): _runtime.line_l = value

var line_r: Variant:
	get: return _runtime.line_r
	set(value): _runtime.line_r = value

var curve: String:
	get: return _runtime.curve
	set(value): _runtime.curve = value

var calib_mode: bool:
	get: return _runtime.calib_mode
	set(value): _runtime.calib_mode = value

var f: Dictionary:
	get: return _runtime.f
	set(value): _runtime.f = value

var S: Dictionary:
	get: return _runtime.S
	set(value): _runtime.S = value

var G: Geo:
	get: return _runtime.G
	set(value): _runtime.G = value

var bp: Dictionary:
	get: return _runtime.bp
	set(value): _runtime.bp = value

var flow_now: float:
	get: return _runtime.flow_now
	set(value): _runtime.flow_now = value

var flow_t: float:
	get: return _runtime.flow_t
	set(value): _runtime.flow_t = value

var last_fx_t: float:
	get: return _runtime.last_fx_t
	set(value): _runtime.last_fx_t = value

var hits: Array:
	get: return _runtime.hits
	set(value): _runtime.hits = value

var plucks: Array:
	get: return _runtime.plucks
	set(value): _runtime.plucks = value

var hold_ends: Array:
	get: return _runtime.hold_ends
	set(value): _runtime.hold_ends = value

var rings: Array:
	get: return _runtime.rings
	set(value): _runtime.rings = value

var judges: Array:
	get: return _runtime.judges
	set(value): _runtime.judges = value

var combo_pop_at: float:
	get: return _runtime.combo_pop_at
	set(value): _runtime.combo_pop_at = value

var combo_break_v: Dictionary:
	get: return _runtime.combo_break_v
	set(value): _runtime.combo_break_v = value

var track_flash_at: float:
	get: return _runtime.track_flash_at
	set(value): _runtime.track_flash_at = value

var last_combo: int:
	get: return _runtime.last_combo
	set(value): _runtime.last_combo = value

var score_shown: float:
	get: return _runtime.score_shown
	set(value): _runtime.score_shown = value

var _rng: RandomNumberGenerator:
	get: return _runtime._rng
	set(value): _runtime._rng = value

var bg: Sprite2D:
	get: return _runtime.bg
	set(value): _runtime.bg = value

var L: Dictionary:
	get: return _runtime.L
	set(value): _runtime.L = value

var grain: ColorRect:
	get: return _runtime.grain
	set(value): _runtime.grain = value

var _dim_tex: GradientTexture2D:
	get: return _runtime._dim_tex
	set(value): _runtime._dim_tex = value

var bg_scene: bool:
	get: return _runtime.bg_scene
	set(value): _runtime.bg_scene = value

var BEAM_STYLE: String:
	get: return _runtime.BEAM_STYLE
	set(value): _runtime.BEAM_STYLE = value

var _breath_on: bool:
	get: return _runtime._breath_on
	set(value): _runtime._breath_on = value

var _mods_now: Array:
	get: return _runtime._mods_now
	set(value): _runtime._mods_now = value

var _carriers: Dictionary:
	get: return _runtime._carriers
	set(value): _runtime._carriers = value

var _carrier_chart: Variant:
	get: return _runtime._carrier_chart
	set(value): _runtime._carrier_chart = value

var _nd_notes: Array:
	get: return _runtime._nd_notes
	set(value): _runtime._nd_notes = value

var _nd_holds: Array:
	get: return _runtime._nd_holds
	set(value): _runtime._nd_holds = value

var _cur_chord: bool:
	get: return _runtime._cur_chord
	set(value): _runtime._cur_chord = value

var note_scale: float:
	get: return _runtime.note_scale
	set(value): _runtime.note_scale = value

var hint_mode: String:
	get: return _runtime.hint_mode
	set(value): _runtime.hint_mode = value

var _cur_note: Dictionary:
	get: return _runtime._cur_note
	set(value): _runtime._cur_note = value

var _cur_lw: float:
	get: return _runtime._cur_lw
	set(value): _runtime._cur_lw = value

var _cur_st: Dictionary:
	get: return _runtime._cur_st
	set(value): _runtime._cur_st = value

var _letter_ok: bool:
	get: return _runtime._letter_ok
	set(value): _runtime._letter_ok = value

var _nd_letters: Array:
	get: return _runtime._nd_letters
	set(value): _runtime._nd_letters = value

var _marker_until: int:
	get: return _runtime._marker_until
	set(value): _runtime._marker_until = value

func _ready() -> void:
	pass

static func _noise(t: float, a: float, b: float, c: float) -> float:
	return PluginRegistry.standard().service_script("renderer")._noise(t, a, b, c)

func _geo() -> Geo:
	return _runtime._geo()

func s_of_p(p: float) -> float:
	return _runtime.s_of_p(p)

func clear_fx() -> void:
	_runtime.clear_fx()

func visual_progress(light_id: int,chart_time: float) -> float:
	return _runtime.visual_progress(light_id,chart_time)

func visual_time(light_id: int,progress: float) -> float:
	return _runtime.visual_time(light_id,progress)

func frame(fd: Dictionary, stage: StageFx) -> void:
	_runtime.frame(fd, stage)

func _breath_at(key: String) -> float:
	return _runtime._breath_at(key)

func _modulate(l: Dictionary, id: int) -> Dictionary:
	return _runtime._modulate(l, id)

func _beat_phase() -> float:
	return _runtime._beat_phase()

func _breathe(l: Dictionary, id: int) -> Dictionary:
	return _runtime._breathe(l, id)

func _beat_pulse() -> Dictionary:
	return _runtime._beat_pulse()

func sprite(c: CanvasItem, tex: Texture2D, x: float, y: float, w: float, h: float, a: float, col := Color.WHITE) -> void:
	_runtime.sprite(c, tex, x, y, w, h, a, col)

func aspect(n: String) -> float:
	return _runtime.aspect(n)

func band(c: CanvasItem, tex: Texture2D, xl0: float, xl1: float, s0: float, s1: float, alpha: float, pad_k: float, fade_top := 0.0, v0 := 0.0, v1 := 1.0, col := Color.WHITE) -> void:
	_runtime.band(c, tex, xl0, xl1, s0, s1, alpha, pad_k, fade_top, v0, v1, col)

func _is_carrier(id: int) -> bool:
	return _runtime._is_carrier(id)

func _is_bg(id: int) -> bool:
	return _runtime._is_bg(id)

func _refresh_roles() -> void:
	_runtime._refresh_roles()

func _paint_tracks(c: CanvasItem) -> void:
	_runtime._paint_tracks(c)

func curve_line(c: CanvasItem, xl: float, s0: float, s1: float, a0: float, a_mid: float, a1: float, width: float, steps := 32) -> void:
	_runtime.curve_line(c, xl, s0, s1, a0, a_mid, a1, width, steps)

func text(c: CanvasItem, s: String, x: float, y: float, size: int, alpha: float, align := "left", spacing := 0, font: Font = null, col := Color.WHITE) -> void:
	_runtime.text(c, s, x, y, size, alpha, align, spacing, font, col)

func text_width(s: String, size: int, spacing := 0) -> float:
	return _runtime.text_width(s, size, spacing)

func _paint_beam(c: CanvasItem) -> void:
	_runtime._paint_beam(c)

func _line_strip(c: CanvasItem, x0: float, x1: float, h: float, a: float) -> void:
	_runtime._line_strip(c, x0, x1, h, a)

func _pluck_dy(x: float) -> float:
	return _runtime._pluck_dy(x)

func _sides(from: String) -> Array:
	return _runtime._sides(from)

func _note_at(st: Dictionary, n: Dictionary, p: float) -> Dictionary:
	return _runtime._note_at(st, n, p)

func _land_st(n: Dictionary, st: Dictionary) -> Dictionary:
	return _runtime._land_st(n, st)

func _draw_note(_c, P: Dictionary, a: float, k := 1.0, col := Color.WHITE, big := false, nw := 1.0) -> void:
	_runtime._draw_note(_c, P, a, k, col, big, nw)

func _path_at(n: Dictionary, d: float) -> Array:
	return _runtime._path_at(n, d)

func _note_at_u(st: Dictionary, u: float, p: float) -> Dictionary:
	return _runtime._note_at_u(st, u, p)

func _ribbon(c: CanvasItem, n: Dictionary, st: Dictionary, tau_h: float, tau_t: float, t: float, fall: float, a: float, fade: float, thin := 1.0) -> void:
	_runtime._ribbon(c, n, st, tau_h, tau_t, t, fall, a, fade, thin)

func _missed(n: Dictionary, st: Dictionary, t: float, fall: float) -> Dictionary:
	return _runtime._missed(n, st, t, fall)

func _paint_note_sprites(c: CanvasItem) -> void:
	_runtime._paint_note_sprites(c)

func _paint_holds(c: CanvasItem) -> void:
	_runtime._paint_holds(c)

func _plan_notes() -> void:
	_runtime._plan_notes()

func _dash(c: CanvasItem, x: float, age: float, delay: float, rise: float, life: float, w0: float, a0: float) -> void:
	_runtime._dash(c, x, age, delay, rise, life, w0, a0)

func _paint_fx(c: CanvasItem) -> void:
	_runtime._paint_fx(c)

func _paint_hud(c: CanvasItem) -> void:
	_runtime._paint_hud(c)

func _draw_combo(c: CanvasItem, st: Dictionary) -> void:
	_runtime._draw_combo(c, st)

func show_marker() -> void:
	_runtime.show_marker()

func _draw_marker(c: CanvasItem, y: float) -> void:
	_runtime._draw_marker(c, y)

func _draw_meter(c: CanvasItem) -> void:
	_runtime._draw_meter(c)

func _paint_hud_add(c: CanvasItem) -> void:
	_runtime._paint_hud_add(c)

func add_ripple(xl: float, level: float) -> void:
	_runtime.add_ripple(xl, level)

func add_judge(t: String, xl: float, dt: float) -> void:
	_runtime.add_judge(t, xl, dt)

func add_hold_end(n: Dictionary) -> void:
	_runtime.add_hold_end(n)

func add_combo_break(v: int) -> void:
	_runtime.add_combo_break(v)

func add_cue_ring(yellow: bool, from: String) -> void:
	_runtime.add_cue_ring(yellow, from)

func add_cue_text(t: String, from: String) -> void:
	_runtime.add_cue_text(t, from)

