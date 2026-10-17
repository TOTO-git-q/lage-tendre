## The results screen (after DJMAX RESPECT's layout, in the game's own quiet black-and-white style).
## Left: title / artist / difficulty, the score counting up, the judgement breakdown (counts + thin proportional bars),
## MAX COMBO / ACCURACY / FAST-SLOW.  Right: the rank emblem (a Codex bitmap, assets/tex/rank_<NAME>.png) stamped in with a
## soft bloom, the FC / AP badge, NEW RECORD, the way to the next rank.  Everything is revealed in a staggered timeline
## and Enter skips it to the end (a second Enter leaves the screen).
class_name ResultView
extends Control

signal restart_pressed
signal songs_pressed

const LW := 1920.0
const LH := 1080.0
const X0 := 140.0                       # left column
const CX := 1410.0                      # right column centre
const EMBLEM_Y := 420.0
const T_STAMP := 2.1                    # the rank lands here
const T_END := 3.5
const GOLD := Color(1.0, 0.86, 0.55)
const ICE := Color(0.78, 0.89, 1.0)

var done := false
var _t0 := 0
var _skipped := false
var _skip_at := 0
var _rev := []                          # fade / slide entries
var _bars := []                         # proportional bars with their counting labels
var _score := 0
var _score_zero: Label
var _score_tail: Label
var _stamp: TextureRect
var _fx: Control
var _glow: Texture2D
var _rank := "F"
var _tint := Color.WHITE
var _gl := 0.5
var _special := ""
var _fade := 0.0
var _grain: ColorRect
var _tex_cache := {}

func _ready() -> void:
	size = Vector2(LW, LH)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_glow = _tex("glow")
	_fx = Control.new()
	_fx.size = Vector2(LW, LH)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = m
	_fx.draw.connect(_draw_fx)
	_grain = ColorRect.new()
	_grain.size = Vector2(LW, LH)
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grain.material = ShaderMaterial.new()
	_grain.material.shader = load("res://assets/shaders/grain.gdshader")

func _tex(n: String) -> Texture2D:
	if not _tex_cache.has(n):
		var p := "res://assets/tex/%s.png" % n
		_tex_cache[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[n]

# ---------------------------------------------------------------- build
## st = GameCore.stats; meta = {title, artist, version, level}; rec = {new: bool, prev: int}; kind = "ap" | "fc" | ""
func begin(st: Dictionary, meta: Dictionary, rec: Dictionary, rank: String, kind: String) -> void:
	for ch in get_children():
		if ch != _fx and ch != _grain: ch.queue_free()
	_rev.clear(); _bars.clear()
	if _fx.get_parent() == null: add_child(_fx)
	_rank = rank
	_tint = Ranks.tint_of(rank)
	_gl = Ranks.glow_of(rank)
	_special = kind
	_score = int(st.score)
	done = false; _skipped = false
	_t0 = SU.ticks()
	var total: int = maxi(1, int(st.total))
	var pc: int = int(st.PERFECT) - int(st.CRITICAL)

	# --- left column: song
	var title := _lbl(str(meta.get("title", "")), 52, 1.0, 1, Fonts.title(), Vector2(X0, 112), 790)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	_reveal(title, 0.15, 0.55, Vector2(-26, 0))
	_reveal(_lbl(str(meta.get("artist", "")), 22, 0.7, 2, Fonts.ui(), Vector2(X0 + 2, 190), 780), 0.25, 0.5, Vector2(-22, 0))
	var diff := "%s    Lv %s" % [str(meta.get("version", "")).to_upper(), str(meta.get("level", ""))] if meta.has("level") else str(meta.get("version", "")).to_upper()
	_reveal(_lbl(diff, 15, 0.75, 6, Fonts.ui(), Vector2(X0 + 2, 236), 780), 0.35, 0.5, Vector2(-18, 0))
	_reveal(_rule(Vector2(X0, 292), 760, 0.22), 0.4, 0.6, Vector2.ZERO)

	# --- score
	_reveal(_lbl("SCORE", 14, 0.55, 8, Fonts.ui(), Vector2(X0 + 2, 322), 300), 0.5, 0.5, Vector2.ZERO)
	_score_zero = _lbl("", 8, 0.0, 0, Fonts.ui(), Vector2(0, 0), 1)
	_score_tail = _lbl("", 108, 1.0, 3, Fonts.title(), Vector2(X0, 340), 720)
	_reveal(_score_tail, 0.55, 0.5, Vector2(-20, 0))

	# --- judgement breakdown
	var rows := [["CRITICAL", int(st.CRITICAL), 1.0], ["PERFECT", pc, 0.82], ["GREAT", int(st.GREAT), 0.6], ["GOOD", int(st.GOOD), 0.42], ["MISS", int(st.MISS), 0.0]]
	for i in rows.size():
		var r: Array = rows[i]
		var y := 506.0 + i * 56.0
		var t0 := 0.95 + i * 0.14
		var miss: bool = r[0] == "MISS"
		var la := 0.5 if miss else 0.78
		var name_l := _lbl(r[0], 18, la, 5, Fonts.ui(), Vector2(X0, y), 220)
		var cnt_l := _lbl("0", 30, 0.55 if miss else 1.0, 1, Fonts.hud(), Vector2(X0 + 140, y - 7), 190)
		cnt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var track := _rule(Vector2(X0 + 370, y + 14), 390, 0.13, 3)
		var fill := ColorRect.new()
		fill.color = Color(1, 1, 1, 1) if not miss else Color(0.62, 0.62, 0.62)
		fill.modulate.a = 0.35 + 0.65 * float(r[2]) if not miss else 0.8
		fill.size = Vector2(0, 3); fill.position = Vector2(X0 + 370, y + 14)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
		_reveal(name_l, t0, 0.45, Vector2(-20, 0)); _reveal(cnt_l, t0, 0.45, Vector2(-20, 0)); _reveal(track, t0, 0.45, Vector2.ZERO)
		var wf := 390.0 * float(r[1]) / float(total)
		if r[1] > 0: wf = maxf(wf, 3.0)
		_bars.append({"fill": fill, "lbl": cnt_l, "n": int(r[1]), "w": wf, "t0": t0 + 0.1, "dur": 0.9})

	# --- bottom: MAX COMBO / ACCURACY / FAST SLOW
	_reveal(_rule(Vector2(X0, 836), 760, 0.22), 1.6, 0.6, Vector2.ZERO)
	var stats3 := [["MAX COMBO", str(int(st.maxCombo)), "/ %d" % int(st.total)], ["ACCURACY", "%.2f%%" % (float(st.accuracy) * 100.0), ""],
		["FAST  /  SLOW", "%d  /  %d" % [int(st.fast), int(st.slow)], ""]]
	for i in 3:
		var x := X0 + i * 270.0
		var t0 := 1.7 + i * 0.12
		_reveal(_lbl(stats3[i][0], 13, 0.55, 6, Fonts.ui(), Vector2(x + 2, 858), 260), t0, 0.5, Vector2(0, 10))
		var v := _lbl(stats3[i][1], 38, 1.0, 1, Fonts.hud(), Vector2(x, 880), 260)
		_reveal(v, t0, 0.5, Vector2(0, 10))
		if stats3[i][2] != "":
			var w: float = Fonts.hud().get_string_size(stats3[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
			_reveal(_lbl(stats3[i][2], 16, 0.45, 1, Fonts.hud(), Vector2(x + w + 12, 903), 150), t0, 0.5, Vector2(0, 10))

	# --- right column: rank emblem
	_reveal(_lbl("RANK", 14, 0.5, 14, Fonts.ui(), Vector2(CX - 150, 190), 300, true), T_STAMP - 0.3, 0.5, Vector2.ZERO)
	_stamp = TextureRect.new()
	var tex := _tex("rank_" + rank)
	_stamp.texture = tex
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.stretch_mode = TextureRect.STRETCH_SCALE
	_stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if tex:
		var k := minf(330.0 / 360.0, 760.0 / tex.get_width())
		_stamp.size = Vector2(tex.get_width(), tex.get_height()) * k
		_stamp.position = Vector2(CX, EMBLEM_Y) - _stamp.size * 0.5
		_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.modulate.a = 0.0
	add_child(_stamp)

	# --- badge / record / next rank
	var by := 690.0
	if kind != "":
		var bt := _tex(kind)
		if bt:
			var bh := 40.0 if kind == "fc" else 58.0
			var bw := bh * bt.get_width() / bt.get_height()
			var badge := TextureRect.new()
			badge.texture = bt; badge.stretch_mode = TextureRect.STRETCH_SCALE; badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			badge.size = Vector2(bw, bh); badge.position = Vector2(CX - bw / 2.0, by - bh / 2.0)
			badge.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 1.0)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(badge)
			_reveal(badge, T_STAMP + 0.5, 0.6, Vector2(0, 12))
	var ry := 770.0
	if rec.get("new", false):
		var nr := _lbl("NEW RECORD", 30, 1.0, 10, Fonts.title(), Vector2(CX - 300, ry), 600, true)
		nr.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 1.0)
		_reveal(nr, T_STAMP + 0.7, 0.6, Vector2(0, 12))
		var prev: int = int(rec.get("prev", 0))
		if prev > 0:
			_reveal(_lbl("+ %s" % _grouped(_score - prev), 18, 0.7, 2, Fonts.hud(), Vector2(CX - 300, ry + 46), 600, true), T_STAMP + 0.8, 0.6, Vector2(0, 12))
	elif int(rec.get("prev", 0)) > 0:
		_reveal(_lbl("BEST  %s" % _grouped(int(rec.prev)), 16, 0.5, 5, Fonts.hud(), Vector2(CX - 300, ry + 6), 600, true), T_STAMP + 0.7, 0.6, Vector2(0, 12))
	var nx := Ranks.next_of(rank)
	if not nx.is_empty():
		var cur := Ranks.min_of(rank)
		var need: int = int(nx.min) - _score
		var yy := 878.0
		var head := _lbl("NEXT  %s" % nx.name, 14, 0.6, 7, Fonts.ui(), Vector2(CX - 230, yy + 4), 300)
		var rem := _lbl(_grouped(need), 18, 0.85, 1, Fonts.hud(), Vector2(CX - 230 + 160, yy), 300)
		rem.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var tr := _rule(Vector2(CX - 230, yy + 34), 460, 0.14, 3)
		var frac := clampf(float(_score - cur) / float(maxi(1, int(nx.min) - cur)), 0.0, 1.0)
		var fl := ColorRect.new()
		fl.color = Color(ICE.r, ICE.g, ICE.b, 0.9)
		fl.size = Vector2(460.0 * frac, 3); fl.position = Vector2(CX - 230, yy + 34)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fl)
		for n in [head, rem, tr, fl]: _reveal(n, T_STAMP + 0.9, 0.6, Vector2(0, 10))
	else:
		_reveal(_lbl("HIGHEST RANK", 14, 0.55, 8, Fonts.ui(), Vector2(CX - 300, 884), 600, true), T_STAMP + 0.9, 0.6, Vector2(0, 10))

	# --- vertical divider + hints
	var vl := ColorRect.new()
	vl.color = Color(1, 1, 1, 0.14); vl.position = Vector2(1000, 120); vl.size = Vector2(1, 780)
	vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vl)
	_reveal(vl, 0.4, 0.8, Vector2.ZERO)
	var h1 := _hint("R  重开  RESTART", Vector2(CX - 330, 1000), func(): restart_pressed.emit())
	var h2 := _hint("Enter  选歌  SONGS", Vector2(CX + 30, 1000), func(): songs_pressed.emit())
	_reveal(h1, 3.0, 0.5, Vector2.ZERO); _reveal(h2, 3.0, 0.5, Vector2.ZERO)
	if _grain.get_parent() == null: add_child(_grain)
	move_child(_grain, get_child_count() - 1)
	_apply(0.0)
	visible = true

func _grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out

func _lbl(t: String, fs: int, alpha: float, spacing: int, font: Font, pos: Vector2, w: float, center := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", Fonts.spaced(font, spacing))
	l.add_theme_font_size_override("font_size", fs)
	l.modulate = Color(1, 1, 1, alpha)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.size = Vector2(w, fs * 1.5)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l

func _rule(pos: Vector2, w: float, alpha: float, h := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, alpha)
	r.position = pos; r.size = Vector2(w, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _hint(t: String, pos: Vector2, cb: Callable) -> Label:
	var l := _lbl(t, 15, 0.5, 5, Fonts.ui(), pos, 300, true)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: cb.call())
	return l

func _reveal(n: CanvasItem, t0: float, dur: float, slide: Vector2) -> void:
	_rev.append({"n": n, "t0": t0, "dur": dur, "slide": slide, "a": n.modulate.a, "base": n.position if n is Control else Vector2.ZERO})

# ---------------------------------------------------------------- run
func skip() -> void:
	if not _skipped: _skip_at = SU.ticks()
	_skipped = true

## Enter / Esc leave the screen only once it is fully shown (a mashed double tap does not fly past it)
func can_leave() -> bool:
	return done and (not _skipped or SU.ticks() - _skip_at > 350000)

func _now() -> float:
	return 99.0 if _skipped else (SU.ticks() - _t0) / 1e6

func _process(_dt: float) -> void:
	if _stamp == null or not is_visible_in_tree(): return
	var t := _now()
	_apply(t)
	done = t >= T_END
	_grain.material.set_shader_parameter("seed", float(int(SU.ticks() / 70000)))
	_fx.queue_redraw()
	queue_redraw()

func _apply(t: float) -> void:
	_fade = SU.ease_out(clampf(t / 0.5, 0.0, 1.0))
	for e in _rev:
		var k: float = SU.ease_out(clampf((t - e.t0) / e.dur, 0.0, 1.0))
		var n: CanvasItem = e.n
		n.modulate.a = e.a * k
		if n is Control: n.position = e.base + e.slide * (1.0 - k)
	for b in _bars:
		var k := SU.ease_out(clampf((t - b.t0) / b.dur, 0.0, 1.0))
		b.fill.size.x = b.w * k
		b.lbl.text = _grouped(int(round(b.n * k)))
	# the score counts up (0.7 .. 2.1 s)
	var sk := SU.ease_out(clampf((t - 0.7) / 1.4, 0.0, 1.0))
	_score_zero.text = ""
	_score_tail.text = _grouped(int(round(_score * sk)))
	# the rank stamp
	var ts := t - T_STAMP
	if ts < 0.0:
		_stamp.modulate.a = 0.0
	else:
		var k := clampf(ts / 0.34, 0.0, 1.0)
		var s := 1.0 + (0.55 if _gl > 0.4 else 0.25) * pow(1.0 - k, 3.0)
		_stamp.scale = Vector2(s, s)
		var a := clampf(ts / 0.09, 0.0, 1.0)
		var br := 1.0 + 0.5 * _gl * clampf(1.0 - ts / 0.5, 0.0, 1.0)        # a brief over-bright flare as it lands
		_stamp.modulate = Color(minf(_tint.r * br, 1.6), minf(_tint.g * br, 1.6), minf(_tint.b * br, 1.6), a)

func _draw() -> void:
	draw_rect(Rect2(0, 0, LW, LH), Color(0, 0, 0, _fade))

func _draw_fx() -> void:
	var t := _now()
	var ts := t - T_STAMP
	var c := Vector2(CX, EMBLEM_Y)
	# a faint standing haze behind the right column
	_fx.draw_texture_rect(_glow, Rect2(c.x - 560, c.y - 330, 1120, 660), false, Color(0.7, 0.8, 1.0, 0.07 * _fade))
	if ts < 0.0: return
	var k := clampf(ts / 0.34, 0.0, 1.0)
	var breathe := 0.06 * sin(ts * 1.6)
	var peak := _gl * (0.95 * exp(-ts * 2.4) + 0.38 + breathe)
	var sz := Vector2(1180, 620) * (1.0 + 0.3 * (1.0 - k)) * (0.85 + 0.15 * _gl)
	_fx.draw_texture_rect(_glow, Rect2(c - sz * 0.5, sz), false, Color(_tint.r, _tint.g, _tint.b, clampf(peak * 0.9, 0.0, 1.0)))
	# a horizontal light sweep through the glyph, once
	var sw := clampf(ts / 0.7, 0.0, 1.0)
	if sw < 1.0 and _gl > 0.3:
		var ww := 1500.0 * SU.ease_out(sw)
		_fx.draw_texture_rect(_glow, Rect2(c.x - ww / 2.0, c.y - 18, ww, 36), false, Color(_tint.r, _tint.g, _tint.b, 0.5 * _gl * sin(PI * sw)))
	# flash and a ring of light
	if ts < 0.2:
		_fx.draw_rect(Rect2(0, 0, LW, LH), Color(1, 1, 1, 0.12 * _gl * (1.0 - ts / 0.2)))
	if ts < 1.1:
		var rk := ts / 1.1
		var r := 190.0 + 300.0 * SU.ease_out(rk)
		_fx.draw_arc(c, r, 0.0, TAU, 160, Color(_tint.r, _tint.g, _tint.b, 0.22 * _gl * pow(1.0 - rk, 2.5)), 1.5, true)
	if _special != "" and ts > 0.5:                      # FC / AP: a warm sweep under the badge
		var bk := clampf((ts - 0.5) / 0.9, 0.0, 1.0)
		var ww := 700.0 * SU.ease_out(bk)
		_fx.draw_texture_rect(_glow, Rect2(c.x - ww / 2.0, 690 - 14, ww, 28), false, Color(GOLD.r, GOLD.g, GOLD.b, 0.35 * sin(PI * bk)))
