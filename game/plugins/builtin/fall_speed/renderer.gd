## Explicit fall_speed renderer service. The standard runtime stays literal.
extends "res://plugins/builtin/standard_render/runtime.gd"
const Profile=preload("res://plugins/builtin/fall_speed/profile.gd")
var _scroll_chart: Dictionary={}
var _scroll_profile: Dictionary=Profile.compile([])
var _scroll_tracks: Dictionary={}
var _scroll_neutral:=true
var _scroll_cuts: Array=[]

func _sync_scroll() -> void:
	var chart: Dictionary=f.get("chart",{})
	if is_same(chart,_scroll_chart): return
	_scroll_chart=chart; _scroll_profile=chart.get("_fall_profile",Profile.compile([]))
	_scroll_tracks=chart.get("_fall_tracks",{}); _scroll_neutral=chart.get("_fall_neutral",true)
	_scroll_cuts=[]
	var events: Array=_scroll_profile.events
	for i in events.size():
		var event: Dictionary=events[i]; var a:=float(event.t)
		var b:=a+float(event.dur)
		if i+1<events.size(): b=minf(b,float(events[i+1].t))
		_scroll_cuts.append(a)
		if b>a: _scroll_cuts.append(b)
		var middle:=a+float(event.dur)*0.5
		if event.ease=="inout" and middle>a and middle<b: _scroll_cuts.append(middle)
	_scroll_cuts.sort()

func uses_integrated_scroll() -> bool:
	_sync_scroll(); return not _scroll_neutral

func _progress_at(light_id: int,chart_time: float,now: float) -> float:
	_sync_scroll()
	if _scroll_neutral: return 1.0-(chart_time-now)/float(f.fall)
	var distance: float=float(_scroll_tracks.get(light_id,1.0))*(Profile.integral(_scroll_profile,chart_time)-Profile.integral(_scroll_profile,now))
	return 1.0-distance/float(f.fall)

func visual_progress(light_id: int,chart_time: float) -> float:
	_sync_scroll()
	if _scroll_neutral: return super.visual_progress(light_id,chart_time)
	return _progress_at(light_id,chart_time,float(f.t))

func visual_time(light_id: int,progress: float) -> float:
	_sync_scroll()
	if _scroll_neutral: return super.visual_time(light_id,progress)
	var area:=Profile.integral(_scroll_profile,float(f.t))+(1.0-progress)*float(f.fall)/float(_scroll_tracks.get(light_id,1.0))
	return Profile.time_at(_scroll_profile,area)

## Optional visual-clock cuts: jumps, active ramp ends and inout midpoints.
func visual_time_cuts(_light_id: int,from_time: float,to_time: float) -> Array:
	_sync_scroll()
	if _scroll_neutral:return []
	return _scroll_cuts.slice(_scroll_cuts.bsearch(from_time),_scroll_cuts.bsearch(to_time))

func _draw_note(_c, P: Dictionary, a: float, k := 1.0, col := Color.WHITE, big := false, nw := 1.0) -> void:
	if not uses_integrated_scroll(): super._draw_note(_c,P,a,k,col,big,nw); return
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
		var pp := clampf(visual_progress(int(_cur_note.get("light",0)),float(_cur_note.get("t",f.t))),0.0,1.0)
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

func _follow_track_state(n: Dictionary, st: Dictionary) -> Dictionary:
	if not uses_integrated_scroll(): return super._follow_track_state(n,st)
	var segs: Array = f.tl.get(n.light, [])
	var i_n := -1
	var i_c := -1
	for k in segs.size():
		if segs[k].t <= n.t + 1e-9: i_n = k
		if segs[k].t <= f.t + 1e-9: i_c = k
	var moving: bool = i_c >= 0 and segs[i_c].type == "sweep" and segs[i_c].t + segs[i_c].dur < n.t
	for k in range(i_c + 1, i_n + 1):
		if segs[k].type in ["on", "sweep"]:
			moving = true
	if moving:
		var L2 := _light_at(segs, n.t + 1e-4)
		if st.alive and f.fall > 0.0:                      # ride the moving light, settle on the landing place
			var pp := clampf(visual_progress(int(n.light),float(n.t)),0.0,1.0)
			var k := clampf((pp - 0.25) / 0.6, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return {"x": lerpf(st.x, L2.x, k), "w": lerpf(st.w, L2.w, k), "alpha": st.alpha, "alive": true}
		return {"x": L2.x, "w": L2.w, "alpha": st.alpha if st.alive else 1.0, "alive": true}
	return st


func _missed(n: Dictionary, st: Dictionary, t: float, fall: float) -> Dictionary:
	if not uses_integrated_scroll(): return super._missed(n,st,t,fall)
	var early: bool = n.state == "miss" and n.hitDt < -SU.WIN_GOOD
	var late: bool = (n.state == "pending" or n.state == "miss") and not early and t > n.t
	if not late and not (early and t > n.t + n.hitDt): return {}
	var P: Dictionary
	if early:
		var t0: float = n.t + n.hitDt
		var te := t0 + 0.06 * (1.0 - exp(-(t - t0) / 0.06))
		P = _note_at(st, n, _progress_at(int(n.light),float(n.t),te))
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

func _paint_lane_edges(c: CanvasItem) -> void:
	if not uses_integrated_scroll(): super._paint_lane_edges(c); return
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
	# Tempo decoration follows global SV plus the existing stage rush clock.
	if f.play and f.chart.bpm > 0.0:
		var beat: float = 60.0 / f.chart.bpm
		var nb := int(ceil((flow_now - f.phase) / beat))
		for guard in 400:
			var n := nb + guard
			var p: float = _progress_at(-1,float(f.phase)+n*beat,flow_now)
			if p < 1.0 - f.reach: break
			if p > 1.0 or n % 4 != 0: continue
			var s := s_of_p(p)
			var x0 := G.x_of(0.0, s)
			var x1 := G.x_of(1.0, s)
			sprite(c, TEX.judge, (x0 + x1) / 2.0, G.y_of(s), (x1 - x0) * 1.02, 16.0 * s, 0.07 * minf(1.0, s * 1.6) * S.exposure * (1.4 if S.rush > 1.2 else 1.0))
	if S.flash > 0.003:
		band(c, lane, 0.0, 1.0, s_top, 1.0, S.flash * 0.9, 0.04)
		sprite(c, TEX.judge, G.cx, G.jy, G.D * 1.1, 70.0, S.flash * 1.2)

func _plan_notes() -> void:
	if not uses_integrated_scroll(): super._plan_notes(); return
	_nd_notes.clear(); _nd_holds.clear(); _nd_letters.clear()
	if f.is_empty() or not f.play: return
	var t: float=f.t; var fall: float=f.fall; var p_min: float=1.0-f.reach
	for group in f.chords:
		var xs:=[]; var lo:=INF; var hi:=-INF; var ymin:=INF; var ymax:=-INF; var depth:=0.0; var fade:=1.0
		for n in group:
			if n.state!="pending": continue
			var p:=visual_progress(int(n.light),float(n.t))
			if p<p_min or p>1.0: continue
			var st:=_land_st(n,f.get("light_by_id_raw",f.light_by_id)[n.light])
			if not st.alive: continue
			var point:=_note_at(st,n,p)
			xs.append([point,n]); lo=minf(lo,point.x); hi=maxf(hi,point.x)
			ymin=minf(ymin,point.y); ymax=maxf(ymax,point.y); depth=point.s; fade=minf(fade,clampf((p-p_min)/0.12,0,1))
		for entry in xs:
			var gap:=INF
			for other in xs:
				if other[1]!=entry[1] and absf(other[0].y-entry[0].y)<2.0: gap=minf(gap,absf(other[0].x-entry[0].x))
			entry[1]["_mw"]=gap*0.92
		# A mixed-speed chord is not horizontal until its notes reach the line.
		if xs.size()>1 and hi-lo>2.0 and ymax-ymin<2.0:
			_nd_holds.append(func(c): sprite(c,TEX.line,(lo+hi)*0.5,ymin,(hi-lo)*1.08,maxf(10.0,26.0*depth),0.25*fade*2.4))
	for n in f.notes:
		if n.state=="skip": continue
		var p:=visual_progress(int(n.light),float(n.t)); var tail:=visual_progress(int(n.light),float(n.t+n.dur))
		if p<p_min-0.05 or (tail>1.2 and not (n.state in ["miss","pending"] and t-n.t<1.0)): continue
		var st:=_land_st(n,f.get("light_by_id_raw",f.light_by_id)[n.light])
		if not st.alive: continue
		_cur_chord=n.get("chord",false); _cur_note=n; _cur_lw=st.w; _cur_st=st; _letter_ok=false
		var planner: Callable=_kind_planners.get(n.kind,Callable())
		if planner.is_valid(): planner.call(self,n,st,t,fall,p_min,p,tail)

func _hold_state(n: Dictionary,tau: float,u: float) -> Dictionary:
	var point:=n.duplicate(); point.t=tau; point.u=u
	return _land_st(point,_light_at(f.tl.get(n.light,[]),float(f.t)))

func _plan_hold(n: Dictionary, st: Dictionary, t: float, fall: float, p_min: float, p_quick: float, p_end: float) -> void:
	if _custom_geometry and st.get("geometry","lane")!="lane":
		var custom: Callable=registry.get_entry("track_geometry",str(st.geometry)).get("hold_plan",Callable())
		if custom.is_valid(): super._plan_hold(n,st,t,fall,p_min,p_quick,p_end); return
	if not uses_integrated_scroll(): super._plan_hold(n,st,t,fall,p_min,p_quick,p_end); return
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
	var tau_h: float = visual_time(int(n.light),pb)
	var tau_t: float = visual_time(int(n.light),pt)
	var ph := _path_at(n, clampf(tau_h - n.t, 0.0, n.dur))
	var pe := _path_at(n, n.dur)
	st=_hold_state(n,tau_h,float(ph[0]))
	_cur_st=st; _cur_lw=st.w
	var head_note:=n.duplicate(); head_note.u=ph[0]; head_note.t=tau_h; _cur_note=head_note
	var Pb := _note_at_u(st, ph[0], pb)
	var xl: float = Pb.xl
	# semi-transparent, and the wider the ribbon the fainter, so a light-wide hold never hides notes
	var hb_a: float = (1.0 if active else 0.75) * a
	var thin_k: float = 0.55 if (holding and not active) else 1.0  # forgiven gap: the string thins, never darkens
	var stc := st.duplicate()
	_nd_holds.append(func(cc): _ribbon(cc, n, stc, tau_h, tau_t, t, fall, hb_a, 0.0, thin_k))
	if p_end>p_min:
		var tail_st:=_hold_state(n,float(n.t+n.dur),float(pe[0])); var tail_note:=n.duplicate(); tail_note.u=pe[0]; tail_note.t=n.t+n.dur
		_cur_st=tail_st; _cur_lw=tail_st.w; _cur_note=tail_note
		_draw_note(c,_note_at_u(tail_st,pe[0],p_end),a*0.55,0.7,Color.WHITE,false,pe[1])
		_cur_st=st; _cur_lw=st.w; _cur_note=head_note
	if not dmh.is_empty(): _draw_note(c, dmh.P, dmh.a, 1.0, dmh.col, n.big, ph[1])
	elif n.state != "fail":
		_letter_ok = not active and pb < 1.0
		_draw_note(c, Pb, a, 1.12 + 0.05 * sin(f.perf * 30.0) if active else 1.0, Color.WHITE, n.big, ph[1])
		_letter_ok = false
	if active and _rng.randf() < f.dt * 6.0: hits.append({"xl": xl, "level": 0.5, "born": last_fx_t})


## Returned primitives are also inspected by headless tests: exact scroll times,
## cross-section clips and mapped vertices share the actual draw implementation.
func ribbon_mesh(n: Dictionary,tau_h: float,tau_t: float,now: float,a: float,thin:=1.0) -> Dictionary:
	if _custom_geometry and n.get("geometry","lane")!="lane":
		var callback: Callable=registry.get_entry("track_geometry",str(n.geometry)).get("ribbon_mesh",Callable())
		if callback.is_valid():
			var state:=_hold_state(n,tau_h,float(n.u))
			return callback.call(self,n,state,tau_h,tau_t,now,float(f.fall),a,0.0,thin)
	var points:=PackedVector2Array(); var plane:=PackedVector2Array(); var uvs:=PackedVector2Array(); var colors:=PackedColorArray(); var indices:=PackedInt32Array(); var times:=[]
	var p0:=_progress_at(int(n.light),tau_h,now); var p1:=_progress_at(int(n.light),tau_t,now)
	var count:=clampi(int(ceil(absf(p0-p1)/0.02)),28,128)
	var previous:=-1; var previous_interval:=[]
	for i in count+1:
		var p:=lerpf(p0,p1,float(i)/count); var tau:=visual_time(int(n.light),p)
		var path:=_path_at(n,clampf(tau-float(n.t),0.0,float(n.dur)))
		var st:=_hold_state(n,tau,float(path[0]))
		if not st.get("alive",false): previous=-1; continue
		var x: float=st.x+(float(path[0])-0.5)*st.w
		var section: Array=[st.x-st.w*0.5,st.x+st.w*0.5]
		if st.get("geometry","lane")!="lane": x=_geometry_note_x(st,float(path[0])); section=_geometry_note_section(st,float(path[0]))
		if section.is_empty(): previous=-1; continue
		var nwk: float=1.3*note_scale if path[1]<=1.0 else float(path[1])*note_scale/1.5
		var width:=minf(nwk*thin/15.0,(float(section[1])-float(section[0]))*0.96)
		x=clampf(x,float(section[0])+width*0.5,float(section[1])-width*0.5)
		var s:=s_of_p(p); var start:=points.size()
		for side in [-0.5,0.5]:
			var xl: float=x+width*side
			plane.append(Vector2(xl,s)); points.append(Vector2(G.x_of(xl,s),G.y_of(s))); uvs.append(Vector2(side+0.5,0.97)); times.append(tau)
			var tail:=clampf(float(count-i)/4.0,0.0,1.0)
			colors.append(Color(SU.HOLD_COL.r,SU.HOLD_COL.g,SU.HOLD_COL.b,clampf(0.42*a*(0.35+0.65*tail),0.0,1.0)))
		if previous>=0 and maxf(float(previous_interval[0]),float(section[0]))<=minf(float(previous_interval[1]),float(section[1])):
			indices.append_array([previous,previous+1,start,previous+1,start+1,start])
		previous=start; previous_interval=section
	return {"points":points,"plane":plane,"times":times,"uvs":uvs,"colors":colors,"indices":indices}

func _ribbon(c: CanvasItem,n: Dictionary,st: Dictionary,tau_h: float,tau_t: float,t: float,fall: float,a: float,fade: float,thin:=1.0) -> void:
	if _custom_geometry and st.get("geometry","lane")!="lane":
		var custom: Callable=registry.get_entry("track_geometry",str(st.geometry)).get("ribbon_mesh",Callable())
		if custom.is_valid(): super._ribbon(c,n,st,tau_h,tau_t,t,fall,a,fade,thin); return
	if not uses_integrated_scroll(): super._ribbon(c,n,st,tau_h,tau_t,t,fall,a,fade,thin); return
	var data:=ribbon_mesh(n,tau_h,tau_t,t,a,thin)
	if data.indices.is_empty(): return
	var tex: Texture2D=TEX.track_flat if TEX.get("track_flat")!=null else TEX.hold
	RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(),data.indices,data.points,data.colors,data.uvs,PackedInt32Array(),PackedFloat32Array(),tex.get_rid())
