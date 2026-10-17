## Gameplay renderer (port of [5] RENDERER v5): perspective "( )" track, judgement line only.
## Every visual is a Codex imagegen texture (white + luminance alpha) composited additively;
## the code only lays out, times and moves them.
class_name BuiltinRendererRuntime
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

# Feedback palette and lifetimes live here; no judgement window or score changes.
const GRADE_COLOURS := {"CRITICAL": Color("ffe85a"), "PERFECT": Color("ffb43c"),
	"GREAT": Color("ff8cb4"), "GOOD": Color("78d28c"), "MISS": Color("8c8c8c")}
const GRADE_RANK := {"CRITICAL": 0, "PERFECT": 1, "GREAT": 2, "GOOD": 3, "MISS": 4}
const PULSE_LIFE := 0.4
const TIMING_LIFE := 0.9
const TIMING_PUSH := 0.12
const SNAP_LIFE := 0.075
const IMPACT_LIFE := 0.34
const FX_CAP := 32

var TEX := {}
var hy0 := HY0                     # horizon / perspective bow / judgement line height (field size; --field= overrides)
var gamma0 := GAMMA0
var arc0 := ARC0
var judge_y := SU.JUDGE_Y
var line_l := 0.0                 # line ends (logical px): the keyboard's left Shift .. right Shift = the screen edges
var line_r := LW
var curve := "deemo"
# 2026-10-18 owner: the fall curves are adjustable. accel_k = exponent of the accelerating fall (1.0 would be linear);
# persp_k = depth factor of the perspective fall (far end shown at 1 / (1 + k) of full size; 9 = the original look).
var accel_k := 1.7:
	set(v):
		if not is_equal_approx(v, accel_k): accel_k = v; _drop_curve_caches()
var persp_k := PK:
	set(v):
		if not is_equal_approx(v, persp_k): persp_k = v; _drop_curve_caches()

func _drop_curve_caches() -> void:
	_band_rows.clear(); _curve_points.clear(); _curve_grids.clear()
var calib_mode := false

var f := {}                        # current frame data
var S := {}                        # current stage channels
var G: Geo
var bp := {"b": 0.0, "bar": 0.0}
var flow_now := 0.0
var flow_t := -999.0
var last_fx_t := 0.0
var hits := []
var plucks := []
var hold_ends := []
var rings := []
var judges := []
var combo_pulses := []
var timing_stack := []
var feedback_groups := []
var impacts := []                 # frame-local note-head bursts; never stored on chart notes
var combo_colour := Color.WHITE
var combo_colour_at := -9.0
var _feedback_seen := {}          # recently identified final notes, not chart state
var combo_pop_at := -9.0
var combo_break_v := {}
var track_flash_at := -9.0
var last_combo := 0
var score_shown := 0.0
var _rng := RandomNumberGenerator.new()

var bg: Sprite2D
var L := {}
var grain: ColorRect
var _dim_tex: GradientTexture2D
var bg_scene := false              # the background is an illustrated scene (not the smoke texture)

var registry: PluginRegistry
var _chart_provider: Script
var pipeline: RenderPipeline
var _kind_planners := {}
var _motion: Callable
var _custom_geometry := false
var _band_indices_cache := {}      # instance-local, at most one entry per n in 2..160
var _band_rows := {}               # depth sampling shared by strips within this frame
var _band_geo: Geo
var _band_revision := -1
var _curve_points := {}
var _curve_grids := {}
var _curve_colors := {}
var _strip_uvs := {}              # fixed UV grids, shared by all textures
var _pluck_frame := PackedFloat64Array()

func configure(scope: PluginRegistry) -> void:
	registry = scope
	_custom_geometry = scope.records.get("track_geometry", {}).size() > 1
	_chart_provider = scope.service_script("chart")
	pipeline = RenderPipeline.new(scope)
	for entry in scope.ordered("note_kinds"):
		var callback: Callable = entry.get("render", Callable())
		if callback.is_valid(): _kind_planners[entry.id] = callback
	_motion = scope.get_entry("motions", "follow_track").get("callback", Callable())

# ---------------------------------------------------------------- geometry (stage camera folded in, depth-weighted)
const Geo = BuiltinRenderData.Geo

static func _noise(t: float, a: float, b: float, c: float) -> float:
	return (sin(t * a) + sin(t * b + 1.7) * 0.6 + sin(t * c + 4.1) * 0.35) / 1.95

func _geo() -> Geo:
	var g := Geo.new()
	g.l = line_l; g.r = line_r; g.D = line_r - line_l; g.cx = line_l + AXIS * g.D; g.jy = judge_y; g.key_w = g.D / 15.0
	var st: Dictionary = S if not S.is_empty() else StageFx.rest()
	g.jy += st.get("line_y", 0.0) * LH
	g.hy = hy0 + st.pitch
	g.gam = gamma0 * st.bow
	g.arc = arc0
	g.z = st.zoom - 1.0
	var tr: float = st.trauma * st.trauma
	var nt: float = f.get("t", 0.0)
	g.shx = tr * 0.006 * LH * _noise(nt, 113, 151, 197)
	g.shy = tr * 0.006 * LH * _noise(nt, 127, 163, 211)
	g.shear = tan(deg_to_rad(st.roll + tr * 0.4 * _noise(nt, 139, 181, 223)))
	g.vpx = st.vpx + g.shx
	if G != null and g.l == G.l and g.r == G.r and g.D == G.D and g.cx == G.cx and g.jy == G.jy and g.key_w == G.key_w and g.hy == G.hy and g.gam == G.gam and g.arc == G.arc and g.z == G.z and g.shx == G.shx and g.shy == G.shy and g.shear == G.shear and g.vpx == G.vpx:
		return G
	g.build_inverse()
	return g

## Opt-in visual providers share one chart-time projection. Legacy draw loops
## keep their original literal arithmetic; fall_speed overrides this interface.
func visual_progress(_light_id: int,chart_time: float) -> float:
	return 1.0-(chart_time-float(f.t))/float(f.fall)

func visual_time(_light_id: int,progress: float) -> float:
	return float(f.t)+(1.0-progress)*float(f.fall)

func s_of_p(p: float) -> float:
	p = clampf(p, 0.0, 1.25)
	var s: float
	if curve == "linear": s = S0 + (1.0 - S0) * p
	elif curve == "accel": s = S0 + (1.0 - S0) * pow(p, accel_k)
	else: s = 1.0 / (1.0 + persp_k * (1.0 - p)) if p <= 1.0 else 1.0 + persp_k * (p - 1.0)
	return minf(1.25, s)

# ---------------------------------------------------------------- setup
func _ready() -> void:
	for n in TEX_NAMES:
		var pth := "res://assets/tex/%s.png" % n
		TEX[n] = load(pth) if ResourceLoader.exists(pth) else null
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for element in pipeline.elements:
		var setup: Callable = element.get("setup", Callable())
		if setup.is_valid():
			setup.call(self)
			continue
		var phase := str(element.get("phase", ""))
		if phase.is_empty() or L.has(phase): continue
		var layer := Node2D.new()
		layer.set_script(LayerScript)
		layer.painter = _paint_registered.bind(phase)
		layer.z_index = int(element.order)
		if element.get("additive", false): layer.material = add_mat
		if element.get("repeat_mipmap", false):
			layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(layer)
		L[phase] = layer
	_dim_tex = GradientTexture2D.new()
	_dim_tex.fill = GradientTexture2D.FILL_RADIAL
	_dim_tex.fill_from = Vector2(0.5, 0.5)
	_dim_tex.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 1)); gr.set_color(1, Color(0, 0, 0, 0.4))
	_dim_tex.gradient = gr

func _paint_registered(canvas: CanvasItem, phase: String) -> void:
	pipeline.draw(phase, self, canvas)

func _setup_background() -> void:
	bg = Sprite2D.new()
	bg.texture = TEX.bg
	if TEX.get("bg_scene") != null:                  # 2026-10-16: the illustrated hall (Codex, chosen by the user: "A")
		bg.texture = TEX.bg_scene; bg_scene = true
	bg.centered = true
	bg.position = Vector2(LW / 2.0, LH / 2.0)
	bg.z_index = 0
	add_child(bg)

func _setup_grain() -> void:
	grain = ColorRect.new()
	grain.size = Vector2(LW, LH)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.material = ShaderMaterial.new()
	grain.material.shader = load("res://assets/shaders/grain.gdshader")
	grain.z_index = 80
	add_child(grain)

func _setup_vignette() -> void:
	var vig := ColorRect.new()
	vig.size = Vector2(LW, LH)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.material = ShaderMaterial.new()
	vig.material.shader = load("res://assets/shaders/vignette.gdshader")
	vig.z_index = 90
	add_child(vig)

func clear_fx() -> void:
	hits.clear(); hold_ends.clear(); rings.clear(); judges.clear(); plucks.clear()
	combo_pulses.clear(); timing_stack.clear(); feedback_groups.clear(); impacts.clear()
	combo_colour = Color.WHITE; combo_colour_at = -9.0
	_feedback_seen.clear()
	combo_break_v = {}; last_combo = 0; score_shown = 0.0; track_flash_at = -9.0

# ---------------------------------------------------------------- per-frame entry
func frame(fd: Dictionary, stage: StageFx) -> void:
	f = fd
	last_fx_t = f.fxT
	combo_pulses = combo_pulses.filter(func(p): return last_fx_t - p.born < PULSE_LIFE)
	timing_stack = timing_stack.filter(func(e): return last_fx_t - e.born < TIMING_LIFE and e.grade not in ["CRITICAL", "MISS"])
	feedback_groups = feedback_groups.filter(func(e): return last_fx_t - e.born < TIMING_LIFE)
	S = stage.at(f.t) if f.play else StageFx.rest()
	_breath_on = f.play and stage.mode != "off"
	if f.play: _refresh_roles()
	_mods_now.clear()
	if _breath_on:
		for m in f.chart.get("meta", {}).get("mod", []):
			if f.t >= float(m.t0) and f.t < float(m.t1): _mods_now.append(m)
	if _breath_on:                                   # the hand lights breathe (visual only; judgement keeps the chart geometry)
		var lights := []
		var by_id := {}
		for l in f.lights:
			var b := _breathe(l, l.id)
			lights.append(b); by_id[l.id] = b
		f = f.duplicate()
		f.light_by_id_raw = f.light_by_id                  # notes keep the chart geometry: where you strike never moves
		f.lights = lights; f.light_by_id = by_id
	if flow_t < -100.0 or absf(f.t - flow_t) > 0.5: flow_now = f.t
	else: flow_now += (f.t - flow_t) * S.rush
	flow_t = f.t
	G = _geo()
	# Reuse rows across frames only while all projection inputs match exactly.
	if _band_geo != G:
		_band_rows.clear()
		_curve_points.clear()
		_curve_grids.clear()
		_band_geo = G
		_band_revision = G.revision
	_pluck_frame.clear()
	for pk in plucks:
		var age: float = f.fxT - pk.born
		if age < 0.0 or age > 0.4: continue
		_pluck_frame.append_array([G.x_of(pk.xl, 1.0), pk.amp, exp(-age / 0.07), cos(age * TAU * 6.5)])
	# Field-relative layers share the same conservative judgement-line transform.
	# Identity at defaults; keyboard judgement uses normalized line coordinates.
	var line_tilt := float(S.get("line_tilt", 0.0))
	if f.get("chart", {}).get("meta", {}).get("line_follow_roll", false):
		line_tilt = clampf(line_tilt + float(S.get("roll", 0.0)), -2.0, 2.0)
	var line_angle := deg_to_rad(line_tilt)
	var pivot := Vector2(G.cx, G.jy)
	for layer_name in ["track", "beam", "holds", "note", "fx"]:
		L[layer_name].rotation = line_angle
		L[layer_name].position = pivot - pivot.rotated(line_angle) if line_angle != 0.0 else Vector2.ZERO
	bp = _beat_pulse()
	# background: exposure + slow breathing + bar pulse; mild parallax with the camera
	var op := clampf(S.exposure * (0.94 + 0.06 * sin(f.perf * 0.628)) * (0.9 + 0.1 * bp.bar), 0.0, 1.0) * 0.9
	if f.play and not f.chart.get("meta", {}).get("breath", {}).is_empty():
		if bg_scene:                                             # an illustrated scene: always there, brighter when loud
			op *= 0.55 + 0.45 * pow(_breath_at("energy"), 1.2)
		else:
			op *= 0.15 + 0.85 * pow(_breath_at("energy"), 1.5)   # the smoke in the background rises with the song
	bg.modulate = Color(1, 1, 1, op)
	var k: Variant = 1.0 + (S.zoom - 1.0) * 0.35
	bg.scale = Vector2(LW + 120.0, LH + 80.0) / bg.texture.get_size() * k
	bg.position = Vector2(LW / 2.0 + S.vpx * 0.2, LH / 2.0)
	(grain.material as ShaderMaterial).set_shader_parameter("seed", floor(f.perf / 0.07))
	_plan_notes()
	if hits.size() > FX_CAP: hits = hits.slice(-FX_CAP)
	for l in L.values():
		l.queue_redraw()

## Breathing of the two hand lights, by the song's mood: the chart carries a sampled curve (meta.breath, made by
## tools/stage_lights.py from the music analysis) -- slow deep breaths in the calm parts, a quickening build, wide swells
## and outward kicks only on the song's real heavy hits.  Visual only: notes and the judgement keep the chart geometry.
var BEAM_STYLE := "lane"
var _breath_on := false
func _breath_at(key: String) -> float:
	var br: Dictionary = f.chart.get("meta", {}).get("breath", {})
	var arr: Array = br.get(key, [])
	if arr.is_empty(): return 0.0
	var x: float = (f.t - float(br.t0)) / float(br.dt)
	if x <= 0.0: return float(arr[0])
	var i := int(floor(x))
	if i >= arr.size() - 1: return float(arr[-1])
	return lerpf(float(arr[i]), float(arr[i + 1]), x - i)

## Visual-only motion from chart meta.mod = [{t0, t1, kind, dir}] (notes and judgement keep the chart geometry):
##   beat   -- tracks and decoration swell 8 % on each beat (brighter with it);  breath -- a slow +-15 % over 4 bars;
##   sway   -- decoration sways together (2 beats each way);  twitch -- a track jolts aside (dir) and springs back,
##             the light moves while the note stays.  The background layer breathes slowly on its own.
var _mods_now := []
func _modulate(l: Dictionary, id: int) -> Dictionary:
	if not l.get("alive", false): return l
	if _is_bg(id):
		var bb := l.duplicate()
		var per: float = 8.0 * 60.0 / maxf(1.0, f.chart.bpm)
		bb.w = minf(1.0, l.w * (1.0 + 0.06 * sin(TAU * f.t / per)))
		return bb
	if _mods_now.is_empty(): return l
	var track := _is_carrier(id)
	var beat: float = 60.0 / maxf(1.0, f.chart.bpm)
	var b := l.duplicate()
	var k := 1.0
	for m in _mods_now:
		match str(m.kind):
			"beat":
				var env: float = exp(-_beat_phase() / 0.16)
				k *= 1.0 + 0.08 * env
				b.pulse = maxf(float(b.pulse), 0.4 * env)
			"breath":
				k *= 1.0 + 0.15 * sin(TAU * (f.t - float(m.t0)) / (16.0 * beat))
			"sway":
				if not track: b.x += 0.8 / 15.0 * sin(PI * (f.t - float(m.t0)) / (2.0 * beat))
			"twitch":
				if track:
					var dt: float = f.t - float(m.t0)
					var env2: float = dt / 0.035 if dt < 0.035 else exp(-(dt - 0.035) / 0.09)
					b.x += float(m.get("dir", 1.0)) * 0.6 / 15.0 * env2
	b.w = minf(1.0 + 2.0 * SU.LIGHT_OVER, l.w * k)
	return b

func _beat_phase() -> float:
	if f.chart.bpm <= 0.0: return 1.0
	var beat: float = 60.0 / f.chart.bpm
	var rel: float = f.t - f.phase
	return fposmod(rel, beat) if rel >= 0.0 else 1.0

func _breathe(l: Dictionary, id: int) -> Dictionary:
	return _modulate(l, id) if _breath_on else l

func _beat_pulse() -> Dictionary:
	if not f.play or f.chart.is_empty() or f.chart.bpm <= 0.0: return {"b": 0.0, "bar": 0.0}
	var beat: float = 60.0 / f.chart.bpm
	var rel: float = f.t - f.phase
	if rel < 0.0: return {"b": 0.0, "bar": 0.0}
	var k := rel / beat
	var ph: Variant = (k - floor(k)) * beat
	var b := exp(-ph / 0.11)
	return {"b": b, "bar": b if int(floor(k)) % 4 == 0 else 0.0}

# ---------------------------------------------------------------- primitives
func sprite(c: CanvasItem, tex: Texture2D, x: float, y: float, w: float, h: float, a: float, col := Color.WHITE) -> void:
	if tex == null or a <= 0.003 or w <= 0.0 or h <= 0.0: return
	c.draw_texture_rect(tex, Rect2(x - w / 2.0, y - h / 2.0, w, h), false, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))

func aspect(n: String) -> float:
	var t: Texture2D = TEX[n]
	return t.get_width() / float(t.get_height())

## Integer topology only. Keep packed-array mutations outside this cache isolated.
func _band_indices(n: int) -> PackedInt32Array:
	n = clampi(n, 2, 160)
	if _band_indices_cache.has(n): return _band_indices_cache[n].duplicate()
	var indices := PackedInt32Array()
	for i in n:
		var j := i * 2
		indices.append_array([j, j + 1, j + 2, j + 1, j + 3, j + 2])
	_band_indices_cache[n] = indices
	return indices.duplicate()

## texture stretched over the curved strip xl0..xl1 between depths s0..s1 (v linear in screen y)
func band(c: CanvasItem, tex: Texture2D, xl0: float, xl1: float, s0: float, s1: float, alpha: float, pad_k: float, fade_top := 0.0, v0 := 0.0, v1 := 1.0, col := Color.WHITE) -> void:
	if tex == null or alpha <= 0.003 or s1 <= s0: return
	if _band_geo != G or _band_revision != G.revision:
		_band_rows.clear(); _curve_points.clear(); _curve_grids.clear()
		_band_geo = G; _band_revision = G.revision
	var y0 := G.y_of(s0)
	var y1 := G.y_of(s1)
	var n := clampi(int((y1 - y0) / 5.0), 2, 160)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := _band_indices(n)
	pts.resize((n + 1) * 2)
	cols.resize((n + 1) * 2)
	if fade_top <= 0.0: cols.fill(Color(col.r, col.g, col.b, clampf(alpha, 0.0, 1.0)))
	var uv_key := [n, v0, v1]
	if _strip_uvs.has(uv_key):
		uvs = _strip_uvs[uv_key]
	else:
		uvs.resize((n + 1) * 2)
		for i in n + 1:
			var v := v0 + (v1 - v0) * float(i) / n
			uvs[i * 2] = Vector2(0, v); uvs[i * 2 + 1] = Vector2(1, v)
		if _strip_uvs.size() >= 64: _strip_uvs.clear()
		_strip_uvs[uv_key] = uvs
	var row_key := Vector2(s0, s1)
	# Vector keys are only a bucket: compare doubles before reusing sampled rows.
	var rows: Dictionary = _band_rows.get(row_key, {})
	if rows.is_empty() or rows.s0 != s0 or rows.s1 != s1:
		var heights := PackedFloat64Array()
		var projection := PackedFloat64Array()
		heights.resize(n + 1); projection.resize((n + 1) * 4)
		for i in n + 1:
			var y := y0 + (y1 - y0) * i / n
			var s := G.s_of_y(y)
			var sample := G.depth(s)
			heights[i] = y
			for k in 4: projection[i * 4 + k] = sample[k + 2]
		rows = {"s0": s0, "s1": s1, "heights": heights, "projection": projection}
		if _band_rows.size() >= 64: _band_rows.clear()
		_band_rows[row_key] = rows
	var heights: PackedFloat64Array = rows.heights
	var projection: PackedFloat64Array = rows.projection
	# Cache complete subexpressions, preserving x_of's original multiplication order.
	var left := (xl0 - AXIS) * G.D
	var right := (xl1 - AXIS) * G.D
	var cx := G.cx
	for i in n + 1:
		var y := heights[i]
		var j := i * 4
		var xa := cx + left * projection[j] * projection[j + 1] + projection[j + 2] + projection[j + 3]
		var xb := cx + right * projection[j] * projection[j + 1] + projection[j + 2] + projection[j + 3]
		var pad := (xb - xa) * pad_k
		if fade_top > 0.0:
			var kk := clampf((y - y0) / fade_top, 0.0, 1.0)
			var a := alpha * (kk * kk * (3.0 - 2.0 * kk))
			var cc := Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))
			cols[i * 2] = cc; cols[i * 2 + 1] = cc
		pts[i * 2] = Vector2(xa - pad, y); pts[i * 2 + 1] = Vector2(xb + pad, y)
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())

## The tracks (the lights that carry notes), VOEZ-like: flat translucent bands -- even across, softly feathered sides,
## fading upward -- in a NORMAL-blend layer, so overlapping tracks layer like panes of glass instead of adding up into a
## hot spot.  A faint cool / warm tint tells the two hands apart where they overlap.  Brightness follows the song.
## light roles come from the chart itself: a light that carries notes is a TRACK (white glass, edges, judgement
## stroke); ids 191-199 are the BACKGROUND layer; every other light is DECORATION
var _carriers := {}
var _carrier_chart = null
func _is_carrier(id: int) -> bool:
	return _carriers.has(id) and not _is_bg(id)

func _is_bg(id: int) -> bool:
	return id >= 191 and id < 200

func _refresh_roles() -> void:
	if is_same(f.get("chart"), _carrier_chart): return
	_carrier_chart = f.get("chart")
	_carriers.clear()
	for n in f.chart.get("notes", []):
		_carriers[int(n.light)] = true

func _paint_tracks(c: CanvasItem) -> void:
	pipeline.draw("track", self, c)

func _paint_key_guides(c: CanvasItem) -> void:
	if f.is_empty() or TEX.get("track_flat") == null: return
	var s_top := s_of_p(1.0 - f.reach)
	# key guides: faint threads of light where F and J (the home keys) and the two Shifts (the edges) lie on the track
	for g in KEY_GUIDES:
		curve_line(c, g[0] / 15.0, s_top, 1.0, 0.0, 0.35 * g[1], g[1], 1.3, 48)

func _paint_dividers(c: CanvasItem) -> void:
	if f.is_empty() or TEX.get("track_flat") == null: return
	var s_top := s_of_p(1.0 - f.reach)
	# dividers (owner, 2026-10-17): the Shift row in cells -- left Shift | Z X | C V | B N | M , | . / | right Shift --
	# faint lines on the cell edges of the player's own keyboard layout
	for xd in divider_units():
		curve_line(c, xd / 15.0, s_top, 1.0, 0.0, 0.02, 0.06, 1.0, 48)

func _paint_track_surfaces(c: CanvasItem) -> void:
	if f.is_empty() or TEX.get("track_flat") == null: return
	var s_top := s_of_p(1.0 - f.reach)
	var energy: float = _breath_at("energy") if f.play and not f.chart.get("meta", {}).get("breath", {}).is_empty() else 0.5
	var mood: float = 0.45 + 1.0 * pow(energy, 1.6)
	# staging and dancer tracks first (under the note-carrying ones): the same flat glass, fainter, softly tinted, and
	# far more present when the song is loud -- quiet parts show the two hand tracks, the peaks show six or eight
	var stage_k: float = 0.25 + 1.1 * pow(energy, 1.5)
	# syntax v3: every light is a track; its look is only its opacity `a` (and tint) -- faint ones first, so a
	# transparent note track can sit on top of a visible performer without hiding it
	var v3 := []
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		if st.alive and st.alpha > 0.002 and st.get("a", -1.0) > 0.002: v3.append(st)
	v3.sort_custom(func(p, q): return p.a < q.a)
	for st in v3:
		var col: Color = PALETTE[st.tint] if st.get("tint", -1) >= 0 else Color.WHITE
		band(c, TEX.track_flat, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, 0.17 * st.a * st.alpha * mood * (1.0 + 0.7 * st.pulse), 0.0, 0.0, 0.0, 1.0, col)
	# layer 0, the background (191-199): one very wide, faint, edgeless light behind everything -- depth, not a track
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		if not st.alive or st.alpha <= 0.002 or not _is_bg(st.id) or st.get("a", -1.0) >= 0.0: continue
		var bgc: Color = PALETTE[st.tint] if st.get("tint", -1) >= 0 else Color.WHITE
		band(c, TEX.track_flat, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, 0.035 * st.alpha * (0.5 + 0.8 * energy) * (1.0 + 0.4 * st.pulse), 0.0, 0.0, 0.0, 1.0, bgc)
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		if not st.alive or st.alpha <= 0.002 or _is_carrier(st.id) or _is_bg(st.id) or st.get("a", -1.0) >= 0.0: continue
		var a: float = 0.05 * st.alpha * stage_k * (1.0 + 0.7 * st.pulse)
		var stint: Color = PALETTE[st.tint] if st.get("tint", -1) >= 0 else STAGE_TINT[st.id % STAGE_TINT.size()]
		band(c, TEX.track_flat, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, a, 0.0, 0.0, 0.0, 1.0, stint)
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		if not st.alive or st.alpha <= 0.002 or not _is_carrier(st.id) or st.get("a", -1.0) >= 0.0: continue
		var a: float = 0.17 * st.alpha * mood * (1.0 + 0.7 * st.pulse)
		band(c, TEX.track_flat, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, a, 0.0, 0.0, 0.0, 1.0)   # tracks are white

## chart colour indices (light event "tint" 0..9): VOEZ colours its tracks and washes them section by section; ours are
## the same idea at a whisper -- pale, never saturated
const PALETTE = BuiltinRenderData.PALETTE

## [key centre in units (left Shift = 0 .. right Shift = 15), strength at the line]
const KEY_GUIDES = BuiltinRenderData.KEY_GUIDES

## the dynamic tracks each keep a faint colour of their own (VOEZ colours its tracks; here only a whisper of it)
const CARRIER_TINT = BuiltinRenderData.CARRIER_TINT

## soft tints for the staging / dancer tracks: pale moonlight, pale rose, pale ice, pale gold -- colour only at a whisper
const STAGE_TINT = BuiltinRenderData.STAGE_TINT

func curve_line(c: CanvasItem, xl: float, s0: float, s1: float, a0: float, a_mid: float, a1: float, width: float, steps := 32) -> void:
	if _band_geo != G or _band_revision != G.revision:
		_band_rows.clear(); _curve_points.clear(); _curve_grids.clear()
		_band_geo = G; _band_revision = G.revision
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var point_key := [xl, s0, s1, steps, G.cx, G.D, G.revision]
	if _curve_points.has(point_key): pts = _curve_points[point_key]
	else:
		var grid_key := [s0, s1, steps]
		var grid: PackedFloat64Array
		if _curve_grids.has(grid_key): grid = _curve_grids[grid_key]
		else:
			grid.resize((steps + 1) * 5)
			for i in steps + 1:
				var s := s0 + (s1 - s0) * i / steps
				var sample := G.depth(s)
				for k in 5: grid[i * 5 + k] = sample[k + 2]
			if _curve_grids.size() >= 64: _curve_grids.clear()
			_curve_grids[grid_key] = grid
		var left := (xl - AXIS) * G.D
		var cx := G.cx
		for i in steps + 1:
			var j := i * 5
			pts.append(Vector2(cx + left * grid[j] * grid[j + 1] + grid[j + 2] + grid[j + 3], grid[j + 4]))
		if _curve_points.size() >= 128: _curve_points.clear()
		_curve_points[point_key] = pts
	var color_key := [a0, a_mid, a1, steps]
	if _curve_colors.has(color_key): cols = _curve_colors[color_key]
	else:
		for i in steps + 1:
			var q := float(i) / steps
			var a := lerpf(a0, a_mid, q * 2.0) if q < 0.5 else lerpf(a_mid, a1, q * 2.0 - 1.0)
			cols.append(Color(1, 1, 1, a))
		if _curve_colors.size() >= 128: _curve_colors.clear()
		_curve_colors[color_key] = cols
	c.draw_polyline_colors(pts, cols, width, true)

func text(c: CanvasItem, s: String, x: float, y: float, size: int, alpha: float, align := "left", spacing := 0, font: Font = null, col := Color.WHITE) -> void:
	var fnt: Font = Fonts.spaced(font if font else Fonts.hud(), spacing)
	var w := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x0 := x
	if align == "center": x0 = x - w / 2.0
	elif align == "right": x0 = x - w
	var asc := fnt.get_ascent(size)
	var desc := fnt.get_descent(size)
	c.draw_string(fnt, Vector2(x0, y + (asc - desc) / 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, clampf(alpha, 0.0, 1.0)))

func text_width(s: String, size: int, spacing := 0) -> float:
	return Fonts.spaced(Fonts.hud(), spacing).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

# ---------------------------------------------------------------- beam layer: field, lit lanes, previews, tempo lines, judgement line, receptors
func _paint_beam(c: CanvasItem) -> void:
	pipeline.draw("beam", self, c)

func _paint_lane_edges(c: CanvasItem) -> void:
	if f.is_empty(): return
	var s_top := s_of_p(1.0 - f.reach)
	var lane: Texture2D = TEX.lane
	# the track is faint and literary at rest; the song's energy (chart meta.breath.energy) and the staging carry the bursts
	var energy: float = _breath_at("energy") if f.play and not f.chart.get("meta", {}).get("breath", {}).is_empty() else 0.5
	var mood: float = 0.45 + 1.0 * pow(energy, 1.6)           # 0.45 at rest .. 1.45 at the loudest
	band(c, TEX.haze if TEX.get("haze") != null else lane, 0.0, 1.0, s_top, 1.0, 0.05 * S.exposure * mood, 0.02)
	for xl in [0.0, 1.0]:
		curve_line(c, xl, s_top, 1.0, 0.0, 0.13, 0.26, 1.2, 64)
	var glow: float = (0.9 + 0.1 * minf(1.0, S.exposure)) * (1.0 + 0.5 * S.kick)
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		if not st.alive or st.alpha <= 0.002: continue
		var lit: float = glow * st.alpha * (1.0 + 0.8 * st.pulse + 0.08 * bp.b)
		if st.get("a", -1.0) >= 0.0:                                     # v3 track: two edges, as strong as a^2
			var a2: float = st.a * st.a
			if a2 > 0.004 and st.w * 15.0 > 1.5 + 1e-3:
				var ek3: float = clampf(mood * (1.0 + 0.7 * st.pulse), 0.3, 1.6)
				for xl in [st.x - st.w / 2.0, st.x + st.w / 2.0]:
					if xl > 0.002 and xl < 0.998:
						curve_line(c, xl, s_top, 1.0, 0.0, 0.22 * st.alpha * ek3 * a2, 0.6 * st.alpha * ek3 * a2, 1.6)
			continue
		if _is_bg(st.id): continue                                       # the background layer: no glow, no edges
		if not _is_carrier(st.id):                                       # decoration: a soft haze
			band(c, TEX.haze if TEX.get("haze") != null else lane, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, 0.10 * lit * (0.25 + 1.3 * energy * energy), 0.08)
			continue
		# carrying lights are filled in the track layer (_paint_tracks); here only their edges are drawn
		if st.w * 15.0 <= 1.5 + 1e-3: continue                           # tracks draw their two edges
		var ek: float = clampf(mood * (1.0 + 0.7 * st.pulse), 0.3, 1.6)   # the edge brightens / dims with its surface
		for xl in [st.x - st.w / 2.0, st.x + st.w / 2.0]:
			if xl <= 0.002 or xl >= 0.998: continue                       # a full-line light shows no border
			curve_line(c, xl, s_top, 1.0, 0.0, 0.22 * st.alpha * ek, 0.6 * st.alpha * ek, 1.6)
	# ghost lanes + dashed brackets before light changes
	if f.play:
		for q in f.cues:
			var k := clampf((f.t - (q.t - SU.APPROACH)) / SU.APPROACH, 0.0, 1.0)
			var t_end: float = q.t + maxf(0.0, q.dur)
			if k <= 0.0 or f.t > t_end + 0.2: continue
			var out: Variant = 1.0 - (f.t - t_end) / 0.2 if f.t > t_end else 1.0
			for id in q.lights:
				var st := _light_at(f.tl[id], t_end + 0.21)
				if not st.alive: continue
				if _is_carrier(id):                            # (a decoration cue -- e.g. the seam flash -- is announced by the bracket only)
					band(c, lane, st.x - st.w / 2.0, st.x + st.w / 2.0, s_top, 1.0, 0.24 * k * k * out, 0.12)
				var x0 := G.x_of(st.x - st.w / 2.0, 1.0)
				var x1 := G.x_of(st.x + st.w / 2.0, 1.0)
				var col := Color(1, 1, 1, (0.25 + 0.55 * k) * out)
				c.draw_dashed_line(Vector2(x0, G.jy + 20), Vector2(x1, G.jy + 20), col, 2.0, 9.0)
				c.draw_line(Vector2(x0, G.jy + 8), Vector2(x0, G.jy + 26), col, 2.0)
				c.draw_line(Vector2(x1, G.jy + 8), Vector2(x1, G.jy + 26), col, 2.0)
	var tf: float = f.fxT - track_flash_at
	if tf >= 0.0 and tf < 0.32:
		band(c, lane, 0.0, 1.0, s_top, 1.0, 0.035 * pow(1.0 - tf / 0.32, 2.0), 0.04)
	# tempo lines (bar lines only) at the stage's rush speed; notes never change speed
	if f.play and f.chart.bpm > 0.0:
		var beat: float = 60.0 / f.chart.bpm
		var nb := int(ceil((flow_now - f.phase) / beat))
		for guard in 400:
			var n := nb + guard
			var p: float = 1.0 - (f.phase + n * beat - flow_now) / f.fall
			if p < 1.0 - f.reach: break
			if p > 1.0 or n % 4 != 0: continue
			var s := s_of_p(p)
			var x0 := G.x_of(0.0, s)
			var x1 := G.x_of(1.0, s)
			sprite(c, TEX.judge, (x0 + x1) / 2.0, G.y_of(s), (x1 - x0) * 1.02, 16.0 * s, 0.07 * minf(1.0, s * 1.6) * S.exposure * (1.4 if S.rush > 1.2 else 1.0))
	if S.flash > 0.003:
		band(c, lane, 0.0, 1.0, s_top, 1.0, S.flash * 0.9, 0.04)
		sprite(c, TEX.judge, G.cx, G.jy, G.D * 1.1, 70.0, S.flash * 1.2)

func _paint_judge_line(c: CanvasItem) -> void:
	if f.is_empty(): return
	# judgement line: one tapered line, a brighter stroke over each lit zone
	var x0 := G.x_of(-0.03, 1.0)
	var x1 := G.x_of(1.03, 1.0)
	var lw := x1 - x0
	_line_strip(c, x0, x1, maxf(26.0, lw / aspect("line")), 0.62 + 0.06 * bp.b)
	for st in f.lights:
		if _custom_geometry and st.get("geometry", "lane") != "lane": continue
		var v3a: float = st.get("a", -1.0)
		if not st.alive or st.alpha <= 0.01 or (v3a < 0.0 and not _is_carrier(st.id)) or (v3a >= 0.0 and v3a < 0.05): continue
		var a: float = st.alpha * (1.0 + 0.6 * st.pulse) * (v3a if v3a >= 0.0 else 1.0)
		var za := G.x_of(st.x - st.w / 2.0, 1.0)
		var zb := G.x_of(st.x + st.w / 2.0, 1.0)
		var w := (zb - za) * 1.0
		_line_strip(c, (za + zb) / 2.0 - w / 2.0, (za + zb) / 2.0 + w / 2.0, maxf(30.0, w / aspect("line") * 1.6), 0.45 * a)
	# pluck: the struck spot of the line flares briefly
	for pk in plucks:
		var age: float = f.fxT - pk.born
		if age >= 0.0 and age < 0.18:
			var px := G.x_of(pk.xl, 1.0)
			sprite(c, TEX.line, px, G.jy + _pluck_dy(px), G.key_w * 2.4, 34.0, 0.55 * pk.amp * (1.0 - age / 0.18))
	# A warm, local bloom follows the strike; it never lights the entire line.
	for h in hits:
		var age: float = f.fxT - h.born
		if h.level < 1.0 or age < 0.0 or age >= 0.2: continue
		var x := G.x_of(h.xl, 1.0)
		var q := age / 0.2
		var a := pow(1.0 - q, 1.5)
		sprite(c, TEX.glow, x, G.jy, G.key_w * 2.8, 46.0, 0.42 * a, GRADE_COLOURS.CRITICAL)
		sprite(c, TEX.line, x, G.jy + _pluck_dy(x), G.key_w * 2.6, 24.0 + 14.0 * SU.ease_out(q), 0.85 * a, GRADE_COLOURS.CRITICAL)

func _paint_pedal_receptors(c: CanvasItem) -> void:
	if f.is_empty(): return
	# pedal receptors at both line ends; brighten when a pedal cue is close
	var near := 0.0
	var near_y := false
	if f.play:
		for q in f.cues:
			if q.state != "pending": continue
			var d: float = q.t - f.t
			if d < -0.15 or d > 0.6: continue
			var k := 1.0 - clampf(absf(d) / 0.6, 0.0, 1.0)
			if k > near: near = k; near_y = q.yellow
		for q in f.cues:
			if q.state != "pending": continue
			var d: float = q.t - f.t
			if d < 0.0 or d > 0.6: continue
			var k := 1.0 - d / 0.6
			for xl in _sides(q.from):
				var sz := 74.0 * (1.0 + 1.6 * (1.0 - k))
				sprite(c, TEX.receptor, clampf(G.x_of(xl, 1.0), 48.0, LW - 48.0), G.jy, sz, sz, 0.2 + 0.7 * k, SU.YEL if q.yellow else Color.WHITE)
	for xl in pedal_xl():
		var sz := 74.0 + 10.0 * near
		sprite(c, TEX.receptor, clampf(G.x_of(xl, 1.0), 48.0, LW - 48.0), G.jy, sz, sz, 0.32 + 0.55 * near + (0.25 if f.space_down else 0.0), SU.YEL if (near_y and near > 0.05) else Color.WHITE)
	if calib_mode:
		c.draw_rect(Rect2(G.l - 1, G.jy - 14, 2, 28), Color(1, 1, 1, 0.8))
		c.draw_rect(Rect2(G.r - 1, G.jy - 14, 2, 28), Color(1, 1, 1, 0.8))

## the line as a horizontal strip of the tapered line texture, each column displaced by the plucks:
## a struck spot dips ~3 px and springs back (damped), so the line feels hit
func _line_strip(c: CanvasItem, x0: float, x1: float, h: float, a: float) -> void:
	if a <= 0.003: return
	var n := 96
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := _band_indices(n)
	var cc := Color(1, 1, 1, clampf(a * float(S.get("line_glow", 1.0)), 0.0, 1.0))
	for i in n + 1:
		var u := float(i) / n
		var x := lerpf(x0, x1, u)
		var y := G.jy + _pluck_dy(x)
		pts.append(Vector2(x, y - h / 2.0)); pts.append(Vector2(x, y + h / 2.0))
		uvs.append(Vector2(u, 0)); uvs.append(Vector2(u, 1))
		cols.append(cc); cols.append(cc)
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), TEX.line.get_rid())

func _pluck_dy(x: float) -> float:
	var dy := 0.0
	var sig := G.key_w * 0.9
	for i in range(0, _pluck_frame.size(), 4):
		var d := (x - _pluck_frame[i]) / sig
		dy += 3.2 * _pluck_frame[i + 1] * exp(-d * d) * _pluck_frame[i + 2] * _pluck_frame[i + 3]
	return dy

## cell edges of the Shift row (key units): the start of Z, then every two keys, and the end of "/"
static func divider_units() -> Array:
	var out := []
	for code in ["KeyZ", "KeyC", "KeyB", "KeyM", "Period"]:
		if KB.by_code.has(code): out.append(KB.by_code[code].x0)
	if KB.by_code.has("Slash"): out.append(KB.by_code.Slash.x0 + KB.by_code.Slash.w)
	return out

## pedal lanes (owner, 2026-10-17: the pedal orbs fell outside the screen once the line reached the screen edges):
## each lane lands PEDAL_INSET px inside the visible screen edge, whatever the calibration or keyboard span
const PEDAL_INSET := 70.0
func pedal_xl() -> Array:
	if G == null or G.D <= 0.0: return PEDAL_XL
	return [(PEDAL_INSET - G.l) / G.D, (LW - PEDAL_INSET - G.l) / G.D]

func _sides(from: String) -> Array:
	var pl := pedal_xl()
	if from == "LR": return pl
	return [pl[1]] if from == "R" else [pl[0]]

# ---------------------------------------------------------------- notes
func _note_at(st: Dictionary, n: Dictionary, p: float) -> Dictionary:
	var s := s_of_p(p)
	var xl: float = st.x + (n.u - 0.5) * st.w
	if _custom_geometry and st.has("geometry"): xl = _geometry_note_x(st, n.u)
	return {"x": G.x_of(xl, s), "y": G.y_of(s), "s": s, "xl": xl, "kw": G.x_of(xl + 0.5 / 15.0, s) - G.x_of(xl - 0.5 / 15.0, s)}

## where a note will actually be judged: if its light jumps / turns on before the note, draw it there
func _land_st(n: Dictionary, st: Dictionary) -> Dictionary:
	if _custom_geometry and (n.has("geometry") or st.has("geometry")):
		var geometry: String = str(n.get("geometry", st.get("geometry", "lane")))
		var callback: Callable = registry.get_entry("track_geometry", geometry).get("note_state", Callable())
		if callback.is_valid(): st = callback.call(self, n, st)
	return _motion.call(self, n, st)

func _geometry_note_x(st: Dictionary, u: float) -> float:
	if st.get("geometry", "lane") != "lane":
		var callback: Callable = registry.get_entry("track_geometry", str(st.geometry)).get("note_x", Callable())
		if callback.is_valid(): return callback.call(st, u)
	return st.x + (u - 0.5) * st.w

func _geometry_note_section(st: Dictionary, u: float) -> Array:
	if st.get("geometry", "lane") != "lane":
		var callback: Callable = registry.get_entry("track_geometry", str(st.geometry)).get("note_section", Callable())
		if callback.is_valid(): return callback.call(st, u)
	return [st.x - st.w / 2.0, st.x + st.w / 2.0]

func _follow_track_state(n: Dictionary, st: Dictionary) -> Dictionary:
	var segs: Array = f.tl.get(n.light, [])
	# 2026-10-17: seek sorted timelines instead of scanning their entire future
	# for every visible note. Keep the exact legacy last-tie/epsilon convention.
	var i_n := _timeline_index(segs, n.t)
	var i_c := _timeline_index(segs, f.t)
	var moving: bool = i_c >= 0 and segs[i_c].type == "sweep" and segs[i_c].t + segs[i_c].dur < n.t
	for k in range(i_c + 1, i_n + 1):
		if segs[k].type in ["on", "sweep"]:
			moving = true
	if moving:
		var L2 := _light_at(segs, n.t + 1e-4)
		if st.alive and f.fall > 0.0:                      # ride the moving light, settle on the landing place
			var pp := clampf(1.0 - (n.t - f.t) / f.fall, 0.0, 1.0)
			var k := clampf((pp - 0.25) / 0.6, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return {"x": lerpf(st.x, L2.x, k), "w": lerpf(st.w, L2.w, k), "alpha": st.alpha, "alive": true}
		return {"x": L2.x, "w": L2.w, "alpha": st.alpha if st.alive else 1.0, "alive": true}
	return st

func _timeline_index(segments: Array, t: float) -> int:
	var lo := 0
	var hi := segments.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if segments[mid].t <= t + 1e-9: lo = mid + 1
		else: hi = mid
	return lo - 1

# note draw lists, built once per frame by _plan_notes(): holds/connectors go to an additive layer,
# note capsules (dark backing + capsule + near-line glow) to a normal-blend layer above it
var _nd_notes := []        # [x, y, w, h, a, s]
var _nd_holds := []        # [Callable]
var _cur_chord := false    # set while planning a note that belongs to a multi-press
var note_scale := 1.5      # standard (one-key) note size; set from the NOTE SIZE setting (1.5 x the original look = 1.0)
var hint_mode := "move"    # fingering letters: "off" | "move" (where the hand has to move) | "all"
var _cur_note := {}        # the note being planned (for its chord spacing and fingering letter)
var _cur_lw := 1.0         # width of that note's light (line fraction): a standard note never outgrows its light
var _cur_st := {}          # that note's light state (x, w): the drawn note is clamped inside it
var _letter_ok := false    # true only while drawing a note on its way down (not a hit flash / miss / tail)
var _nd_letters := []      # [x, y, text, size, alpha]
var _note_source: Array = []
var _note_ends := PackedFloat64Array()

func _first_visible_note(t: float, fall: float) -> int:
	if not is_same(_note_source, f.notes):
		_note_source = f.notes
		_note_ends.clear()
		var end := -INF
		for note: Dictionary in _note_source:
			end = maxf(end, note.t + note.dur)
			_note_ends.append(end)
	var cutoff := t - maxf(1.0, 0.2 * fall) - 1e-9
	var lo := 0
	var hi := _note_ends.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _note_ends[mid] < cutoff: lo = mid + 1
		else: hi = mid
	return lo

func _draw_note(_c, P: Dictionary, a: float, k := 1.0, col := Color.WHITE, big := false, nw := 1.0) -> void:
	# one width rule for every note: nw keys (nw <= 1 = the standard width), all scaled by the NOTE SIZE setting
	# (before, nw > 1 ignored the setting, so a "1.5-key" note was drawn narrower than a standard one)
	var std_k: float = 1.3 * note_scale                       # standard width in keys (1.95 at the default size)
	var nwk: float = std_k if nw <= 1.0 else nw * note_scale / 1.5
	if big and nw <= 1.0: nwk *= 1.75
	var w: float = P.kw * k * nwk
	# thickness follows weight a little: wider notes read heavier (1.0 .. 1.3), big ones heaviest
	var thick: float = clampf(1.0 + 0.3 * (nwk / std_k - 1.0), 0.9, 1.3)
	var h := maxf(10.0, P.kw * k * std_k / aspect("note") * (1.55 if big else 1.2 * thick))
	w = minf(w, _cur_note.get("_mw", INF))                    # chord neighbours never merge, however big the notes are
	w = minf(w, P.kw * _cur_lw * 15.0 * 0.96)                 # ... and a note never spills out of its light
	var gr: Array = _cur_note.get("grow", [])
	var gk := 1.0
	if gr.size() == 2:                                          # staging: the note grows (or shrinks) as it falls
		var pp := clampf(1.0 - (float(_cur_note.get("t", f.t)) - f.t) / maxf(0.05, f.fall), 0.0, 1.0)
		gk = lerpf(float(gr[0]), float(gr[1]), pp * pp * (3.0 - 2.0 * pp))
		w *= gk; h *= gk
	if not _cur_st.is_empty():                                  # a note is drawn only inside its light
		var lo_px: float = G.x_of(_cur_st.x - _cur_st.w / 2.0, P.s)
		var hi_px: float = G.x_of(_cur_st.x + _cur_st.w / 2.0, P.s)
		if _custom_geometry and _cur_st.has("geometry"):
			var section := _geometry_note_section(_cur_st, float(_cur_note.get("u", 0.5)))
			if section.is_empty(): return
			lo_px = G.x_of(section[0], P.s); hi_px = G.x_of(section[1], P.s)
		if float(_cur_note.get("wl", 0.0)) > 0.0:               # staging: width as a share of the light
			w = (hi_px - lo_px) * float(_cur_note.wl) * gk
		w = minf(w, (hi_px - lo_px) * 0.98)
		P = P.duplicate()
		P.x = clampf(P.x, lo_px + w / 2.0, hi_px - w / 2.0)
	if _letter_ok and hint_mode != "off" and _cur_note.get("key_code", "") != "" and (hint_mode == "all" or _cur_note.get("hint", false)):
		# the letter fades in on the last stretch of the approach, just above the note
		var la := a * clampf((P.s - 0.2) / 0.15, 0.0, 1.0)
		if la > 0.01:
			var sz := int(round(clampf(15.0 + 26.0 * P.s, 15.0, 40.0)))
			_nd_letters.append([P.x, P.y - h * 0.5 - sz * 0.75, KB.label(_cur_note.key_code), sz, la * 0.9])
	# gentle shimmer: each note breathes ±6 % on its own phase (seeded by its lane position)
	var shim := 0.94 + 0.06 * sin(f.perf * 3.1 + P.xl * 41.0)
	if col == Color.WHITE and _cur_note.get("ex", false): col = SU.YEL   # protected = solid yellow (user); a held key catches it
	if col == Color.WHITE and _cur_note.get("kind", "") == "hold": col = SU.HOLD_COL   # holds / slides: ice blue
	_nd_notes.append([P.x, P.y, w, h, a * shim, P.s, col, big, _cur_note.get("ex", false)])

## a hold's shape at d seconds after its head: [u, nw] (eased between path points; flat without a path)
func _path_at(n: Dictionary, d: float) -> Array:
	var path: Array = n.get("path", [])
	if path.is_empty():
		return [n.u, n.get("nw", 1.0)]
	if d <= path[0][0]:
		return [path[0][1], path[0][2]]
	for i in range(1, path.size()):
		if d <= path[i][0]:
			var q0: Array = path[i - 1]
			var q1: Array = path[i]
			var k := clampf((d - q0[0]) / maxf(1e-4, q1[0] - q0[0]), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return [lerpf(q0[1], q1[1], k), lerpf(q0[2], q1[2], k)]
	return [path[-1][1], path[-1][2]]

func _note_at_u(st: Dictionary, u: float, p: float) -> Dictionary:
	var s := s_of_p(p)
	var xl: float = st.x + (u - 0.5) * st.w
	if _custom_geometry and st.has("geometry"): xl = _geometry_note_x(st, u)
	return {"x": G.x_of(xl, s), "y": G.y_of(s), "s": s, "xl": xl, "kw": G.x_of(xl + 0.5 / 15.0, s) - G.x_of(xl - 0.5 / 15.0, s)}

## the hold body: a semi-transparent ribbon from head to tail that follows the hold's path
func _ribbon(c: CanvasItem, n: Dictionary, st: Dictionary, tau_h: float, tau_t: float, t: float, fall: float, a: float, fade: float, thin := 1.0) -> void:
	if _custom_geometry and st.has("geometry"):
		var mesh: Callable = registry.get_entry("track_geometry", str(st.geometry)).get("ribbon_mesh", Callable())
		if mesh.is_valid():
			var data: Dictionary = mesh.call(self, n, st, tau_h, tau_t, t, fall, a, fade, thin)
			if not data.get("errors", []).is_empty():
				if not n.get("_ribbon_warning", false): n["_ribbon_warning"] = true; push_warning("; ".join(data.errors))
				return
			if data.indices.is_empty(): return
			var texture: Texture2D = TEX.track_flat if TEX.get("track_flat") != null else TEX.hold
			RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), data.indices, data.points, data.colors, data.uvs, PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
			return
	var N := 28
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var el := PackedVector2Array()
	var er := PackedVector2Array()
	var y_h := 0.0
	for i in N + 1:
		var tau := lerpf(tau_h, tau_t, float(i) / N)
		var s := s_of_p(1.0 - (tau - t) / fall)
		var pu := _path_at(n, clampf(tau - n.t, 0.0, n.dur))
		var xl: float = st.x + (pu[0] - 0.5) * st.w
		if _custom_geometry and st.has("geometry"): xl = _geometry_note_x(st, pu[0])
		# the body is as wide as its note (same width rule as _draw_note), never wider than its light
		var nwk: float = 1.3 * note_scale if pu[1] <= 1.0 else pu[1] * note_scale / 1.5
		var hw: float = minf(nwk / 2.0, st.w * 15.0 * 0.48) * thin / 15.0
		var y := G.y_of(s)
		if i == 0: y_h = y
		var xa := G.x_of(xl - hw, s)
		var xb := G.x_of(xl + hw, s)
		pts.append(Vector2(xa, y)); pts.append(Vector2(xb, y))
		el.append(Vector2(xa, y)); er.append(Vector2(xb, y))
		uvs.append(Vector2(0, 0.97)); uvs.append(Vector2(1, 0.97))      # the band's solid row: even along the hold
		var aa := a
		if fade > 0.0:
			var kk := clampf((y_h - y) / fade, 0.0, 1.0)
			aa *= 1.0 - kk * kk * 0.0          # (head side stays solid)
		var tail_k := clampf((float(N - i)) / 4.0, 0.0, 1.0)     # soft tail end
		var cc := Color(SU.HOLD_COL.r, SU.HOLD_COL.g, SU.HOLD_COL.b, clampf(0.42 * aa * (0.35 + 0.65 * tail_k), 0.0, 1.0))
		cols.append(cc); cols.append(cc)
		if i < N:
			var j := i * 2
			idx.append_array([j, j + 1, j + 2, j + 1, j + 3, j + 2])
	# a soft flat band (the track texture turned sideways: even across, feathered edges) instead of the thin string
	var tex: Texture2D = TEX.track_flat if TEX.get("track_flat") != null else TEX.hold
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())

## A note past the line that was not hit (still pending inside the late window, or missed) brakes hard
## just below the line instead of flying off, then fades out slowly.  An early (anti-mash) miss brakes
## where it was.  Returns {} for notes that are not in that situation.
func _missed(n: Dictionary, st: Dictionary, t: float, fall: float) -> Dictionary:
	var early: bool = n.state == "miss" and n.hitDt < -SU.WIN_GOOD
	var late: bool = (n.state == "pending" or n.state == "miss") and not early and t > n.t
	if not late and not (early and t > n.t + n.hitDt): return {}
	var P: Dictionary
	if early:
		var t0: float = n.t + n.hitDt
		var te := t0 + 0.06 * (1.0 - exp(-(t - t0) / 0.06))
		P = _note_at(st, n, 1.0 - (n.t - te) / fall)
	else:
		P = _note_at(st, n, 1.0)
		P.y += 30.0 * (1.0 - exp(-(t - n.t) / 0.045))
	var a: float = st.alpha
	var col := Color.WHITE
	if n.state == "miss":
		var t_miss: float = n.t + (n.hitDt if early else SU.WIN_GOOD)
		var k := clampf((t - t_miss) / 0.75, 0.0, 1.0)
		a *= 0.85 * pow(1.0 - k, 1.3)
		col = MISS_GREY
	return {"P": P, "a": a, "col": col}

func _paint_note_sprites(c: CanvasItem) -> void:
	for d in _nd_notes:
		sprite(c, TEX.note, d[0], d[1], d[2], d[3], d[4], d[6])
		var lit: bool = d[6] != MISS_GREY
		if d[7] and lit:
			sprite(c, TEX.note, d[0], d[1], d[2] * 1.25, d[3] * 2.4, d[4] * 0.22, d[6])
		if d[5] > 0.55 and lit:
			sprite(c, TEX.note, d[0], d[1], d[2] * 1.06, d[3] * 1.5, d[4] * 0.35 * (d[5] - 0.55) / 0.45)
	for L in _nd_letters:
		text(c, L[2], L[0], L[1], L[3], L[4], "center", 0, Fonts.ui())

func _paint_holds(c: CanvasItem) -> void:
	for cb in _nd_holds:
		cb.call(c)
	# note glow (additive, under the capsules): a soft wide halo so notes read as light sources
	for d in _nd_notes:
		if d[6] == MISS_GREY: continue
		sprite(c, TEX.glow, d[0], d[1], d[2] * 1.3, d[3] * 2.3, d[4] * 0.3, d[6])        # soft elliptical halo (Codex glow texture)
		sprite(c, TEX.note, d[0], d[1], d[2] * 1.03, d[3] * 1.25, d[4] * 0.15, d[6])

func _plan_notes() -> void:
	_nd_notes.clear()
	_nd_holds.clear()
	_nd_letters.clear()
	impacts.clear()
	var c = null
	if f.is_empty() or not f.play: return
	var t: float = f.t
	var fall: float = f.fall
	var p_min: float = 1.0 - f.reach
	for grp in f.chords:
		var p: float = 1.0 - (grp[0].t - t) / fall
		if p > 1.0: continue
		if p < p_min: break
		var lo := INF
		var hi := -INF
		var s := 0.0
		var y := 0.0
		var live := 0
		var xs := []
		for n in grp:
			if n.state != "pending": continue
			var st := _land_st(n, f.get("light_by_id_raw", f.light_by_id)[n.light])
			if not st.alive: continue
			var P := _note_at(st, n, p)
			lo = minf(lo, P.x); hi = maxf(hi, P.x); s = P.s; y = P.y; live += 1
			xs.append([P.x, n])
		for e in xs:                      # widest a chord note may be: 92 % of the gap to its nearest neighbour
			var gap := INF
			for e2 in xs:
				if e2[1] != e[1]: gap = minf(gap, absf(e2[0] - e[0]))
			e[1]["_mw"] = gap * 0.92
		if live > 1 and hi - lo > 2.0:
			var ca := 0.25 * clampf((p - p_min) / 0.12, 0.0, 1.0)
			_nd_holds.append(func(cc): sprite(cc, TEX.line, (lo + hi) / 2.0, y, (hi - lo) * 1.08, maxf(10.0, 26.0 * s), ca * 2.4))   # simultaneous line
	for index in range(_first_visible_note(t, fall), f.notes.size()):
		var n: Dictionary = f.notes[index]
		if n.state == "skip": continue
		var p_quick: float = 1.0 - (n.t - t) / fall
		if p_quick < p_min - 0.05: break
		var p_end: float = 1.0 - (n.t + n.dur - t) / fall
		var recent_head: bool = n.state in ["hit", "holding"] and t - _head_hit_time(n) < SNAP_LIFE + IMPACT_LIFE
		if p_quick < p_min - 0.05 or (p_end > 1.2 and not recent_head and not (n.state in ["miss", "pending"] and t - n.t < 1.0)): continue
		var st := _land_st(n, f.get("light_by_id_raw", f.light_by_id)[n.light])
		if not st.alive: continue
		_cur_chord = n.get("chord", false)
		_cur_note = n
		_cur_lw = st.w
		_cur_st = st
		_letter_ok = false
		var planner: Callable = _kind_planners.get(n.kind, Callable())
		if planner.is_valid(): planner.call(self, n, st, t, fall, p_min, p_quick, p_end)

func _plan_tap(n: Dictionary, st: Dictionary, t: float, fall: float, p_min: float, p_quick: float, p_end: float) -> void:
	var c = null
	if n.state == "hit":
		_plan_hit_head(n, st, t, fall, n.nw)
		return
	var dm := _missed(n, st, t, fall)
	if not dm.is_empty():
		if dm.a > 0.004: _draw_note(c, dm.P, dm.a, 1.0, dm.col, n.big, n.nw)
		return
	var p := p_quick
	if p < p_min or p > 1.1: return
	var a: float = clampf((p - p_min) / 0.12, 0.0, 1.0) * st.alpha
	_letter_ok = p < 1.0
	_draw_note(c, _note_at(st, n, p), a, 1.0, Color.WHITE, n.big, n.nw)
	_letter_ok = false

## Visual-only head trajectory. The live note's judgement/state is never modified.
## Late pending notes already brake just below the line in _missed; sample that
## same trajectory at the press so there is no teleport back to the line.
func _hit_head_position(n: Dictionary, st: Dictionary, fall: float) -> Dictionary:
	var dt := _head_hit_time(n) - float(n.t)
	var p := _note_at(st, n, 1.0)
	if dt > 0.0:
		p.y += 30.0 * (1.0 - exp(-dt / 0.045))
	elif dt < -SU.WIN_PERFECT and n.get("headGrade", n.grade) in ["GREAT", "GOOD"]:
		p = _note_at(st, n, 1.0 + dt / fall)
	return p

func _head_hit_time(n: Dictionary) -> float:
	var absolute: float = n.t + n.hitDt
	var reference: float = n.get("chord_ref", -INF)
	if reference == -INF or n.ex: return absolute
	# Follow judgements measure dt from the chord's first press, not chart time.
	# Confirm with the already emitted immediate ripple; an expired follow window
	# uses ordinary chart-relative dt and must not be shifted backwards instead.
	var followed: float = reference + n.hitDt
	for index in range(hits.size() - 1, -1, -1):
		var h: Dictionary = hits[index]
		if h.level >= 1.0 and absf(h.xl - n.hitX) < 1e-6 and absf(h.born - followed) < 0.035:
			return followed
	return absolute

func _plan_hit_head(n: Dictionary, st: Dictionary, t: float, fall: float, nw: float) -> bool:
	var age: float = t - _head_hit_time(n)
	var snap: bool = n.hitDt < -SU.WIN_PERFECT and n.get("headGrade", n.grade) in ["GREAT", "GOOD"]
	var delay := SNAP_LIFE if snap else 0.0
	if age < 0.0 or age > delay + IMPACT_LIFE: return false
	var p := _hit_head_position(n, st, fall)
	if snap and age < SNAP_LIFE:
		var land := _note_at(st, n, 1.0)
		var q := SU.ease_out(age / SNAP_LIFE)
		for key in ["x", "y", "s", "xl", "kw"]: p[key] = lerpf(p[key], land[key], q)
		_draw_note(null, p, st.alpha, 1.0, Color.WHITE, n.big, nw)
		return true
	if snap: p = _note_at(st, n, 1.0)
	var burst_age := age - delay
	var grade := _feedback_grade(n.get("headGrade", n.grade), 0.0 if n.ex else n.hitDt)
	var col: Color = GRADE_COLOURS[grade]
	if impacts.size() < FX_CAP:
		impacts.append({"x": p.x, "y": p.y, "age": burst_age, "big": n.big, "col": col, "kw": p.kw})
	if burst_age < 0.12:
		var first := _nd_notes.size()
		_draw_note(null, p, (1.0 - burst_age / 0.12) * st.alpha, 1.0, col, n.big, nw)
		if _nd_notes.size() > first:
			var d: Array = _nd_notes[-1]
			var squash := 1.0 - clampf(burst_age / (2.0 / 60.0), 0.0, 1.0)
			d[2] = minf(d[2] * (1.0 + 0.22 * squash), minf(_cur_note.get("_mw", INF), p.kw * _cur_lw * 15.0 * 0.96))
			d[3] *= 1.0 - 0.48 * squash
	return burst_age < 0.12

func _plan_hold(n: Dictionary, st: Dictionary, t: float, fall: float, p_min: float, p_quick: float, p_end: float) -> void:
	if _custom_geometry and st.has("geometry"):
		var planner: Callable = registry.get_entry("track_geometry", str(st.geometry)).get("hold_plan", Callable())
		if planner.is_valid(): planner.call(self, n, st, t, fall, p_min, p_quick, p_end); return
	var c = null
	var holding: bool = n.state == "holding"
	var active: bool = holding and n.get("gap_t", -1.0) < 0.0     # in a forgiven gap: a bit dimmer, never dark
	var finished: bool = n.state == "done" or n.state == "fail"
	if (finished and p_end >= 1.0) or n.state == "done": return
	var dmh := _missed(n, st, t, fall)
	var pb := minf(1.0 if (holding or finished or not dmh.is_empty()) else p_quick, 1.1)
	var pt := maxf(p_end, p_min)
	if pb <= pt: return
	var dead: bool = n.state == "miss" or n.state == "fail"
	var a: float = clampf((pb - p_min) / 0.12, 0.0, 1.0) * st.alpha * (0.28 if dead else 1.0)
	if not dmh.is_empty(): a = dmh.a * (0.5 if dead else 1.0)
	# head / tail times on screen, and the hold's shape there
	var tau_h: float = t + (1.0 - pb) * fall
	var tau_t: float = t + (1.0 - pt) * fall
	var ph := _path_at(n, clampf(tau_h - n.t, 0.0, n.dur))
	var pe := _path_at(n, n.dur)
	var Pb := _note_at_u(st, ph[0], pb)
	var xl: float = Pb.xl
	# semi-transparent, and the wider the ribbon the fainter, so a light-wide hold never hides notes
	var hb_a: float = (1.0 if active else 0.75) * a
	var thin_k: float = 0.55 if (holding and not active) else 1.0  # forgiven gap: the string thins, never darkens
	var stc := st.duplicate()
	_nd_holds.append(func(cc): _ribbon(cc, n, stc, tau_h, tau_t, t, fall, hb_a, 0.0, thin_k))
	if p_end > p_min: _draw_note(c, _note_at_u(st, pe[0], p_end), a * 0.55, 0.7, Color.WHITE, false, pe[1])
	if not dmh.is_empty(): _draw_note(c, dmh.P, dmh.a, 1.0, dmh.col, n.big, ph[1])
	elif holding and _plan_hit_head(n, st, t, fall, ph[1]):
		pass                           # only the head moves; the ribbon above is unchanged
	elif n.state != "fail":
		_letter_ok = not active and pb < 1.0
		_draw_note(c, Pb, a, 1.12 + 0.05 * sin(f.perf * 30.0) if active else 1.0, Color.WHITE, n.big, ph[1])
		_letter_ok = false
	if active and _rng.randf() < f.dt * 6.0: hits.append({"xl": xl, "level": 0.5, "born": last_fx_t})

# ---------------------------------------------------------------- fx: rising dashes, pedal orbs, pedal hit rings
func _dash(c: CanvasItem, x: float, age: float, delay: float, rise: float, life: float, w0: float, a0: float) -> void:
	var e := age - delay
	if e < 0.0 or e > life: return
	var q := e / life
	var y := G.jy - 5.0 - rise * SU.ease_out(q)
	var w := w0 * (1.0 - 0.35 * q)
	var a := a0 * pow(1.0 - q, 1.4) * minf(1.0, e / 0.04)
	if a > 0.004: sprite(c, TEX.dash, x, y, w, maxf(6.0, w / aspect("dash")), a)

func _paint_fx(c: CanvasItem) -> void:
	if f.is_empty(): return
	var now: float = f.fxT
	for h in hits:
		var age: float = now - h.born
		var x := G.x_of(h.xl, 1.0)
		var kw := G.key_w
		if age < 0.0: continue
		if h.level <= 0.0: _dash(c, x, age, 0.0, 22.0, 0.3, kw * 0.9, 0.16); continue
		if h.level < 1.0: _dash(c, x, age, 0.0, 40.0, 0.45, kw * 0.8, 0.2); continue
		# Successful note heads supply positioned impacts below. In particular an
		# early GREAT/GOOD must finish its pull before the dense burst starts.
	for impact in impacts:
		var age: float = impact.age
		var q := clampf(age / IMPACT_LIFE, 0.0, 1.0)
		var a := pow(1.0 - q, 1.7)
		var weight := 1.45 if impact.big else 1.0
		var w: float = impact.kw * weight
		var col: Color = impact.col
		sprite(c, TEX.glow, impact.x, impact.y + 5.0, w * 2.5, 60.0 * weight, 0.42 * a, col)
		sprite(c, TEX.line, impact.x, impact.y + 2.0, w * (2.0 + 0.8 * SU.ease_out(q)), 26.0 * weight, 0.85 * a, col)
		# A compact downward shock gives weight without a tall spray obscuring notes.
		if age < 0.16:
			var shock := age / 0.16
			sprite(c, TEX.dash, impact.x, impact.y + 8.0 + 35.0 * SU.ease_out(shock), w * (1.5 - 0.4 * shock), 16.0 * weight, 0.6 * pow(1.0 - shock, 1.4), col)
	for e in hold_ends:
		var age: float = now - e.born
		for j in 3:
			_dash(c, G.x_of(e.xl, 1.0), age, j * 0.05, 46.0 + 22.0 * j, 0.5, G.key_w * (1.25 - 0.18 * j), 0.45 * (1.0 - 0.22 * j))
	hits = hits.filter(func(h): return now - h.born <= 0.65 and now - h.born > -0.05)
	plucks = plucks.filter(func(pk): return now - pk.born <= 0.45 and now - pk.born > -0.05)
	hold_ends = hold_ends.filter(func(e): return now - e.born <= 0.65 and now - e.born > -0.05)
	if f.play:
		var t: float = f.t
		# 2026-10-18 owner: pedal orbs fall with the player's speed setting like the notes (was a fixed SU.APPROACH 1.6 s)
		var ap: float = float(f.fall) if float(f.fall) > 0.05 else SU.APPROACH
		for q in f.cues:
			var e: float = t - (q.t - ap)
			if e < 0.0 or e > ap + q.dur + 0.4: continue
			if (q.dur <= 0.0 and q.state == "hit") or q.state == "skip": continue
			var a := 1.0
			if q.state == "miss": a = clampf(1.0 - (t - q.t - SU.WIN_GOOD) / 0.25, 0.0, 1.0) * 0.5
			if q.state == "fail": a = 0.35
			if a <= 0.01: continue
			var p := minf(e / ap, 1.0)
			var s := s_of_p(p)
			var col := SU.YEL if q.yellow else Color.WHITE
			for xl in _sides(q.from):
				if q.dur > 0.0:
					var pt := maxf(0.0, (e - q.dur) / ap)
					if pt < 1.0: band(c, TEX.hold, xl - 0.014, xl + 0.014, s_of_p(pt), s, 0.85 * a, 0.3)
					if pt >= 1.0: continue
				var sz := (150.0 if q.state == "holding" else 124.0) * (0.35 + 0.65 * s)
				sprite(c, TEX.pedal, G.x_of(xl, s), G.y_of(s), sz, sz, a, col)
	for r in rings:
		var age: float = now - r.born
		if age < 0.0 or age > 0.4: continue
		var k := age / 0.4
		var col := SU.YEL if r.yellow else Color.WHITE
		for xl in _sides(r.from):
			var x := G.x_of(xl, 1.0)
			var sz := 80.0 + 150.0 * SU.ease_out(k)
			sprite(c, TEX.receptor, x, G.jy, sz * 0.8, sz * 0.8, (1.0 - k) * 0.5, col)
			if age < 0.18: sprite(c, TEX.pedal, x, G.jy, 140, 140, 0.5 * (1.0 - age / 0.18), col)
	rings = rings.filter(func(r): return now - r.born <= 0.45)

# ---------------------------------------------------------------- HUD
func _paint_hud(c: CanvasItem) -> void:
	if f.is_empty() or not f.play: return
	c.draw_rect(Rect2(0, 0, LW, 2), Color(1, 1, 1, 0.08))
	c.draw_rect(Rect2(0, 0, LW * f.progress, 2), Color(1, 1, 1, 0.55))
	var m: Dictionary = f.meta
	text(c, str(m.get("title", "")), 48, 46, 26, 0.92, "left", 1, Fonts.ui())
	var sub := str(m.get("artist", "")) + ("   ·   " + str(m.version) if str(m.get("version", "")) != "" else "")
	text(c, sub, 48, 78, 16, 0.68, "left", 2, Fonts.ui())
	var st: Dictionary = f.stats
	if not st.is_empty():
		score_shown += (st.score - score_shown) * minf(1.0, f.dt * 14.0)
		if absf(st.score - score_shown) < 1.0: score_shown = st.score
		var sc := str(int(round(score_shown))).pad_zeros(7)
		var lead := 0
		while lead < sc.length() - 1 and sc[lead] == "0": lead += 1
		var x := LW - 48.0
		var tail := sc.substr(lead)
		text(c, tail, x, 50, 44, 0.95, "right", 2)
		if lead > 0: text(c, sc.substr(0, lead), x - text_width(tail, 44, 2), 50, 44, 0.22, "right", 2)
		text(c, "%.2f %%" % (st.accuracyLive * 100.0), x, 88, 17, 0.6, "right", 2)
		if f.ending.is_empty() and f.countdown <= 0.0: _draw_combo(c, st)
	_draw_meter(c)
	if f.countdown > 0.0 or not f.ending.is_empty():
		var a: float = 0.45 if f.countdown > 0.0 else 0.5 * clampf(f.ending.age / 0.4, 0.0, 1.0)
		c.draw_texture_rect(_dim_tex, Rect2(G.cx - 900, 0.42 * LH - 900, 1800, 1800), false, Color(1, 1, 1, a))
		c.draw_rect(Rect2(0, 0, LW, LH), Color(0, 0, 0, a * 0.4))
	if f.countdown > 0.0:
		var n := int(ceil(f.countdown / 0.5))
		var ph := fmod(f.countdown / 0.5, 1.0)
		var k := 1.0 + 0.25 * ph
		c.draw_set_transform(Vector2(G.cx, 0.42 * LH), 0.0, Vector2(k, k))
		text(c, str(n), 0, 0, 150, 0.4 + 0.6 * (1.0 - ph), "center")
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_combo(c: CanvasItem, st: Dictionary) -> void:
	var now: float = f.fxT
	var y := 0.058 * LH
	if st.combo > last_combo: combo_pop_at = now
	last_combo = st.combo
	if st.combo >= 2:
		var age := now - combo_pop_at
		var pop := 1.0 + 0.14 * pow(1.0 - age / 0.12, 2.0) if age >= 0.0 and age < 0.12 else 1.0
		c.draw_set_transform(Vector2(G.cx, y), 0.0, Vector2(pop, pop))
		var tint := 0.16 * maxf(0.0, 1.0 - (now - combo_colour_at) / PULSE_LIFE)
		text(c, str(st.combo), 0, 0, 58, 0.85, "center", 3, null, Color.WHITE.lerp(combo_colour, tint))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		text(c, "COMBO", G.cx, y + 40, 12, 0.45, "center", 8)
	for e in timing_stack:
		var age: float = now - e.born
		if age < 0.0 or age >= TIMING_LIFE or e.grade in ["CRITICAL", "MISS"]: continue
		var fade := pow(1.0 - age / TIMING_LIFE, 0.8) * minf(1.0, age / 0.06)
		text(c, e.label, G.cx, y + 68.0 + _timing_y(e, now), 16, 0.85 * fade, "center", 4, Fonts.ui(), GRADE_COLOURS[e.grade])
	if not combo_break_v.is_empty():
		var age: float = now - combo_break_v.born
		if age >= 0.0 and age < 0.5:
			c.draw_set_transform(Vector2(G.cx, y + 22.0 * SU.ease_out(age / 0.5)), 0.06 * age / 0.5, Vector2.ONE)
			text(c, str(combo_break_v.value), 0, 0, 58, 0.7 * (1.0 - age / 0.5), "center", 3, null, Color(0.59, 0.59, 0.59))
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif age >= 0.5:
			combo_break_v = {}

var _marker_until := 0

func show_marker() -> void:
	_marker_until = SU.ticks() + 500000

func _draw_marker(c: CanvasItem, y: float) -> void:
	if SU.ticks() < _marker_until:
		c.draw_line(Vector2(G.cx, y - 12), Vector2(G.cx, y - 20), SU.YEL, 2.0)

func _draw_meter(c: CanvasItem) -> void:
	var y := G.jy + 84.0                 # below where missed notes come to rest
	_draw_marker(c, y)
	var hw := 230.0
	var xo := func(dt: float) -> float: return G.cx + clampf(dt / SU.WIN_GOOD, -1.0, 1.0) * hw
	c.draw_rect(Rect2(G.cx - hw, y - 6, hw * 2, 12), Color(1, 1, 1, 0.07))
	c.draw_rect(Rect2(xo.call(-SU.WIN_GREAT), y - 6, xo.call(SU.WIN_GREAT) - xo.call(-SU.WIN_GREAT), 12), Color(1, 1, 1, 0.09))
	c.draw_rect(Rect2(xo.call(-SU.WIN_PERFECT), y - 6, xo.call(SU.WIN_PERFECT) - xo.call(-SU.WIN_PERFECT), 12), Color(1, 1, 1, 0.13))
	c.draw_rect(Rect2(xo.call(-SU.WIN_CRITICAL), y - 6, xo.call(SU.WIN_CRITICAL) - xo.call(-SU.WIN_CRITICAL), 12), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(G.cx - 1, y - 12, 2, 24), Color(1, 1, 1, 0.8))
	text(c, "EARLY", G.cx - hw - 12, y, 11, 0.4, "right", 4)
	text(c, "LATE", G.cx + hw + 12, y, 11, 0.4, "left", 4)
	var sum := 0.0
	var n_avg := 0
	var log: Array = f.hit_log
	for i in range(log.size() - 1, -1, -1):
		var h: Dictionary = log[i]
		if h.grade == "MISS": continue
		if n_avg < 12: sum += h.dt; n_avg += 1
		var age: float = f.t - h.at
		if age < 0.0 or age > 3.0: continue
		c.draw_rect(Rect2(xo.call(h.dt) - 1.5, y - 10, 3, 20), Color(1, 1, 1, 0.85 * (1.0 - age / 3.0)))
	if n_avg:
		var x: float = xo.call(sum / n_avg)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 12), Vector2(x - 5, y - 19), Vector2(x + 5, y - 19)]), Color(1, 1, 1, 0.8))

func _paint_hud_add(c: CanvasItem) -> void:
	if f.is_empty() or not f.play: return
	var now: float = f.fxT
	if f.ending.is_empty() and f.countdown <= 0.0:
		for pulse in combo_pulses:
			var age: float = now - pulse.born
			if age < 0.0 or age >= PULSE_LIFE: continue
			var q := age / PULSE_LIFE
			var size := lerpf(80.0, 190.0, SU.ease_out(q))
			sprite(c, TEX.receptor, G.cx, 0.058 * LH, size, size * 0.52, 0.3 * pow(1.0 - q, 1.5), GRADE_COLOURS[pulse.grade])
		for j in judges:
			var age: float = now - j.born
			if age < 0.0 or age > 0.42: continue
			var tex: Texture2D = TEX["j_" + j.text.to_lower()]
			var pop := 1.25 - 0.25 * (age / 0.07) if age < 0.07 else 1.0
			var a := 1.0 if age < 0.28 else 1.0 - (age - 0.28) / 0.14
			var h := (22.0 if j.text == "PERFECT" else 26.0) * pop
			var y := G.jy - 90.0                                     # fixed above the line, clear of the line's glow
			var col := Color(0.59, 0.59, 0.59) if j.text == "MISS" else Color.WHITE
			sprite(c, tex, j.x, y, h * tex.get_width() / tex.get_height(), h, a * (0.8 if j.text == "MISS" else 0.95), col)
	judges = judges.filter(func(j): return now - j.born <= 0.45)
	if judges.size() > 8: judges = judges.slice(judges.size() - 8)
	if not f.ending.is_empty():
		var age: float = f.ending.age
		var tex: Texture2D = TEX[f.ending.kind]
		if age < 0.25: c.draw_rect(Rect2(0, 0, LW, LH), Color(1, 1, 1, 0.18 * (1.0 - age / 0.25)))
		var k := clampf(age / 0.45, 0.0, 1.0)
		var a := SU.ease_out(k) if age < 2.6 else maxf(0.0, 1.0 - (age - 2.6) / 0.5)
		var w := 980.0 * (0.9 + 0.1 * SU.ease_out(k))
		sprite(c, tex, G.cx, 0.40 * LH, w, w / aspect(f.ending.kind), a)
		var sw := clampf((age - 0.15) / 0.8, 0.0, 1.0)
		if sw > 0.0 and sw < 1.0: sprite(c, TEX.judge, G.cx - 600.0 + 1200.0 * SU.ease_out(sw), 0.40 * LH, 260, 70, sin(PI * sw))

# ---------------------------------------------------------------- events from the game
func add_ripple(xl: float, level: float) -> void:
	hits.append({"xl": xl, "level": level, "born": last_fx_t})
	if hits.size() > FX_CAP: hits.pop_front()
	if level >= 1.0:
		plucks.append({"xl": xl, "amp": 1.6 if level >= 3.0 else (1.0 if level >= 2.0 else 0.8), "born": last_fx_t})
		if plucks.size() > FX_CAP: plucks.pop_front()

func _feedback_grade(grade: String, dt: float) -> String:
	return "CRITICAL" if grade == "PERFECT" and absf(dt) <= SU.WIN_CRITICAL + 1e-9 else grade

func _timing_y(e: Dictionary, now: float) -> float:
	return lerpf(e.y_from, e.y_to, SU.ease_out(clampf((now - e.moved) / TIMING_PUSH, 0.0, 1.0)))

## The signal intentionally stays API-1 compatible. The frame already owns live
## note references, so identify the settled note locally instead of changing the
## core signal or its grade protection. Search only the nearby sorted note slice.
func _feedback_moment(grade: String, xl: float, dt: float) -> String:
	if f.is_empty() or not f.has("notes"): return ""
	var notes: Array = f.notes
	var lo := 0
	var hi := notes.size()
	var time: float = f.t
	if _feedback_seen.size() > 128:
		for id in _feedback_seen.keys():
			if _feedback_seen[id] < time - 0.6: _feedback_seen.erase(id)
	while lo < hi:
		var mid := (lo + hi) >> 1
		if notes[mid].t < time - 0.5: lo = mid + 1
		else: hi = mid
	for index in range(lo, notes.size()):
		var n: Dictionary = notes[index]
		if n.t > time + 0.2: break
		if _feedback_seen.has(n.id) or n.get("provisional", false) or n.grade != grade or n.state in ["pending", "skip"]: continue
		var nx: float = n.get("hitX", -1.0)
		if grade == "MISS": nx = n.get("lineX", -1.0)
		var ndt: float = 0.0 if n.ex else n.hitDt
		if grade != "MISS" and absf(ndt - dt) > 1e-6: continue
		if absf(nx - xl) > 1e-6: continue
		var moment: float = n.t
		for sibling in n.get("sibs", []): moment = minf(moment, sibling.t)
		_feedback_seen[n.id] = n.t
		return "note:%.6f" % moment
	return ""

func _add_combo_feedback(grade: String, xl: float, dt: float) -> void:
	var colour_grade := _feedback_grade(grade, dt)
	combo_colour = GRADE_COLOURS[colour_grade]; combo_colour_at = last_fx_t
	combo_pulses.append({"grade": colour_grade, "born": last_fx_t})
	if combo_pulses.size() > 12: combo_pulses.pop_front()
	var moment := _feedback_moment(grade, xl, dt)
	var group := {}
	for e in feedback_groups:
		# Distinct chart moments never coalesce just because a stream is fast.
		# Legacy/plugin callers without note context retain the old proximity rule.
		if (not moment.is_empty() and e.moment == moment) or (moment.is_empty() and e.moment.is_empty() and absf(last_fx_t - e.born) < 0.04 and absf(e.xl - xl) < 0.135):
			group = e; break
	if group.is_empty():
		group = {"moment": moment, "grade": colour_grade, "dt": dt, "xl": xl, "born": last_fx_t,
			"y_from": 0.0, "y_to": 0.0, "moved": last_fx_t, "label": ""}
		feedback_groups.append(group)
		if feedback_groups.size() > FX_CAP: feedback_groups.pop_front()
	elif GRADE_RANK[colour_grade] > GRADE_RANK[group.grade] or (colour_grade == group.grade and absf(dt) > absf(group.dt)):
		group.grade = colour_grade; group.dt = dt
	group.label = "FAST" if group.dt < 0.0 else "LATE"
	if group.grade in ["CRITICAL", "MISS"]:
		timing_stack.erase(group)
		return
	if not timing_stack.has(group):
		for index in timing_stack.size():
			var e: Dictionary = timing_stack[index]
			e.y_from = _timing_y(e, last_fx_t); e.y_to = (index + 1) * 24.0; e.moved = last_fx_t
		timing_stack.push_front(group)
		if timing_stack.size() > 3: timing_stack.pop_back()

func add_judge(t: String, xl: float, dt: float) -> void:
	_add_combo_feedback(t, xl, dt)
	var x := (G.x_of(clampf(xl, 0.0, 1.0), 1.0) if G else LW / 2.0)
	var RANK := {"PERFECT": 0, "GREAT": 1, "GOOD": 2, "MISS": 3}
	for j in judges:                                  # a chord lands as one judgement (worst grade wins)
		if absf(last_fx_t - j.born) < 0.04 and absf(j.x - x) < 260.0:
			j.x = (j.x * j.n + x) / (j.n + 1); j.n += 1
			if RANK[t] > RANK[j.text]: j.text = t; j.dt = dt
			return
	judges = judges.filter(func(q): return absf(q.x - x) >= 260.0)
	judges.append({"text": t, "dt": dt, "x": x, "n": 1, "born": last_fx_t})

func add_hold_end(n: Dictionary) -> void:
	var xl: float = n.hitX if n.hitX >= 0.0 else (n.lineX if n.lineX >= 0.0 else 0.5)
	hold_ends.append({"xl": xl, "born": last_fx_t})
	plucks.append({"xl": xl, "amp": 0.9, "born": last_fx_t})
	if hold_ends.size() > FX_CAP: hold_ends.pop_front()
	if plucks.size() > FX_CAP: plucks.pop_front()

func add_combo_break(v: int) -> void:
	combo_break_v = {"value": v, "born": last_fx_t}

func add_cue_ring(yellow: bool, from: String) -> void:
	rings.append({"yellow": yellow, "from": from, "born": last_fx_t})
	if rings.size() > FX_CAP: rings.pop_front()
	track_flash_at = last_fx_t

func add_cue_text(t: String, from: String) -> void:
	if G == null: return
	var pl := pedal_xl()
	var x := G.x_of(pl[1], 1.0) if from == "R" else (G.cx if from == "LR" else G.x_of(pl[0], 1.0))
	judges.append({"text": t, "dt": 0.0, "x": x, "n": 1, "born": last_fx_t})

## Session-scoped chart providers; compatibility callers still use ChartLib's built-in scope.
func _light_at(segments, t: float) -> Dictionary:
	return _chart_provider.light_at(segments, t, registry)

func _build_timelines(events: Array) -> Dictionary:
	return _chart_provider.build_timelines(events, registry)
