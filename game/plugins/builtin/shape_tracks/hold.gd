## Shape holds use the same compiled filled trapezoids as the track surface.
## Clip each strip against a single trapezoid before mapping: no triangle can
## join disconnected sections, even when a hole fits between sampling rows.
extends RefCounted
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Mapper=preload("res://plugins/builtin/shape_tracks/projection.gd")
const MAX_P_STEP:=0.01
const MAX_X_STEP:=1.0/48.0
const MAX_CELLS:=32768
const MAX_VERTICES:=65536
const ROW_X_ERROR:=0.00001
const MAX_REFINE_DEPTH:=32

static func _empty(message: String="") -> Dictionary:
	return {"points":PackedVector2Array(),"plane":PackedVector2Array(),"times":[],"indices":PackedInt32Array(),"uvs":PackedVector2Array(),"colors":PackedColorArray(),"errors":[] if message.is_empty() else [message]}

static func _progress(renderer,id: int,tau: float,now: float,fall: float) -> float:
	return renderer.visual_progress(id,tau) if renderer.has_method("visual_progress") else 1.0-(tau-now)/fall

static func _time(renderer,id: int,p: float,now: float,fall: float) -> float:
	return renderer.visual_time(id,p) if renderer.has_method("visual_time") else now+(1.0-p)*fall

static func state_at(renderer,n: Dictionary,tau: float,u: float) -> Dictionary:
	var point:=n.duplicate(); point.t=tau; point.u=u
	return renderer._land_st(point,renderer._light_at(renderer.f.tl.get(n.light,[]),tau))

static func _row(renderer,n: Dictionary,tau: float) -> Dictionary:
	var path: Array=renderer._path_at(n,clampf(tau-float(n.t),0.0,float(n.dur)))
	var base: Dictionary=renderer._light_at(renderer.f.tl.get(n.light,[]),tau)
	var st:=state_at(renderer,n,tau,float(path[0]))
	if not st.get("alive",false) or float(base.get("w",0.0))<=0.0 or float(st.get("w",0.0))<=0.0: return {}
	var section: Array=renderer._geometry_note_section(st,float(path[0]))
	if section.is_empty(): return {}
	var nwk: float=1.3*renderer.note_scale if path[1]<=1.0 else float(path[1])*renderer.note_scale/1.5
	var sx:=float(st.w)/float(base.w)
	return {"x":renderer._geometry_note_x(st,float(path[0])),"section":section,"nwk":nwk,"sx":sx,"tx":float(st.x)-float(base.x)*sx,"section_index":base.sections.find(Geometry.note_section(base,float(path[0])))}

## Refine actual per-time visual state, not a constant-target ease assumption.
## Path knots are mandatory. Nearest-section switches are bisected separately,
## so the two one-sided rows never interpolate a visual jump across a gap.
static func _row_values(row: Dictionary,trap: Dictionary,tau: float) -> Array:
	return [Geometry.edge_x(trap.left,tau)*float(row.sx)+float(row.tx),Geometry.edge_x(trap.right,tau)*float(row.sx)+float(row.tx),float(row.x),float(row.section[0]),float(row.section[1]),float(row.nwk)/15.0]

static func _refine(renderer,n: Dictionary,trap: Dictionary,a: float,b: float,out: Array,budget: Dictionary,depth:=0) -> bool:
	budget.steps+=1
	if budget.steps>MAX_CELLS or out.size()>MAX_CELLS:
		budget.error="Shape hold refinement budget exceeded; no partial mesh drawn";return false
	var times:=[lerpf(a,b,.000001),lerpf(a,b,.25),lerpf(a,b,.5),lerpf(a,b,.75),lerpf(a,b,.999999)]
	var rows:=[]
	for tau in times: rows.append(_row(renderer,n,tau))
	for row in rows:
		if row.is_empty(): out.append(b);return true
	for i in range(1,rows.size()):
		if int(rows[i-1].section_index)==int(rows[i].section_index):continue
		var lo:float=times[i-1];var hi:float=times[i];var initial:=int(rows[i-1].section_index)
		for j in 48:
			var middle:=(lo+hi)*.5
			if middle<=lo or middle>=hi:break
			var sample:=_row(renderer,n,middle)
			if not sample.is_empty() and int(sample.section_index)==initial:lo=middle
			else:hi=middle
		var split:=(lo+hi)*.5
		if split>a and split<b and depth<MAX_REFINE_DEPTH:
			return _refine(renderer,n,trap,a,split,out,budget,depth+1) and _refine(renderer,n,trap,split,b,out,budget,depth+1)
	var first:=_row_values(rows[0],trap,a);var last:=_row_values(rows[-1],trap,b);var error:=0.0
	for i in range(1,4):
		var values:=_row_values(rows[i],trap,times[i]);var k:=float(i)/4.0
		for j in values.size():error=maxf(error,absf(float(values[j])-lerpf(first[j],last[j],k)))
	if error>ROW_X_ERROR:
		var middle:=(a+b)*.5
		if depth>=MAX_REFINE_DEPTH or middle<=a or middle>=b:
			budget.error="Shape hold refinement precision/depth budget exceeded; no partial mesh drawn";return false
		return _refine(renderer,n,trap,a,middle,out,budget,depth+1) and _refine(renderer,n,trap,middle,b,out,budget,depth+1)
	out.append(b);return true

## Half-plane clipping in float64 (Vector2 is float32 in this engine build).
## The clipping boundary is the affine x(t) through [x0,t0,x1,t1].
static func _clip(poly: Array,edge: Array,left: bool) -> Array:
	var result:=[]
	if poly.is_empty(): return result
	var previous: Array=poly[-1]
	var da: float=(float(previous[0])-Geometry.edge_x(edge,float(previous[1])))*(1.0 if left else -1.0)
	for current in poly:
		var db: float=(float(current[0])-Geometry.edge_x(edge,float(current[1])))*(1.0 if left else -1.0)
		if (da>=0.0)!=(db>=0.0):
			var k:=da/(da-db)
			result.append([lerpf(previous[0],current[0],k),lerpf(previous[1],current[1],k)])
		if db>=0.0: result.append(current)
		previous=current; da=db
	return result

static func mesh(renderer,n: Dictionary,_st: Dictionary,tau_h: float,tau_t: float,now: float,fall: float,a: float,_fade: float,thin:=1.0) -> Dictionary:
	for value in [tau_h,tau_t,now,fall,a,thin]:
		if not Geometry.finite_number(value): return _empty("Shape hold requires finite frame values")
	if fall<=0.0 or tau_t<=tau_h or thin<=0.0: return _empty()
	var prepared: Dictionary={}
	for segment in renderer.f.tl.get(n.light,[]):
		if segment.get("type","")=="shape_track": prepared=segment.shape; break
	if prepared.is_empty() or not prepared.get("errors",[]).is_empty(): return _empty("Shape hold has no valid compiled geometry")
	if prepared.trapezoids.is_empty(): return _empty()
	var integrated:bool=renderer.has_method("uses_integrated_scroll") and renderer.uses_integrated_scroll()
	var projection_work:Dictionary=Mapper.budget(renderer,int(n.light),tau_h,tau_t,MAX_VERTICES) if integrated else {}
	var motion_cuts:Array=projection_work.cuts.duplicate() if integrated else []; var inset:=0.0
	for point in n.get("path",[]):
		var tau:=float(n.t)+float(point[0])
		if tau>tau_h and tau<tau_t:motion_cuts.append(tau)
	var cuts_callback: Callable=renderer.registry.get_entry("motions",str(n.get("motion",{}).get("type",""))).get("hold_cuts",Callable())
	if cuts_callback.is_valid():
		var xlo:=INF; var xhi:=-INF
		for trap in prepared.trapezoids:
			for edge in [trap.left,trap.right]:
				xlo=minf(xlo,minf(edge[0],edge[2])); xhi=maxf(xhi,maxf(edge[0],edge[2]))
		var cut_report: Dictionary=cuts_callback.call(renderer,n,tau_h,tau_t,[xlo,xhi])
		if not cut_report.get("errors",[]).is_empty(): return _empty("; ".join(cut_report.errors))
		motion_cuts.append_array(cut_report.get("times",[])); inset=float(cut_report.get("inset",0.0))
	motion_cuts.sort()
	var refine:bool=integrated or cuts_callback.is_valid() or not n.get("path",[]).is_empty()
	var refinement_budget:={"steps":0,"error":""}
	var out:=_empty(); var cells:=0
	var head_p:=_progress(renderer,int(n.light),tau_h,now,fall)
	var tail_p:=_progress(renderer,int(n.light),tau_t,now,fall)
	for trap in prepared.trapezoids:
		var t0:=maxf(tau_h,float(trap.t0)); var t1:=minf(tau_t,float(trap.t1))
		if t1-t0<=Geometry.EPS: continue
		var p0:=_progress(renderer,int(n.light),t0,now,fall); var p1:=_progress(renderer,int(n.light),t1,now,fall)
		if not is_finite(p0) or not is_finite(p1): return _empty("Shape hold has non-finite projected progress")
		if absf(p0-p1)>float(MAX_CELLS-cells)*MAX_P_STEP: return _empty("Shape hold cell budget exceeded; no partial mesh drawn")
		var rows:=maxi(1,int(ceil(absf(p0-p1)/MAX_P_STEP)))
		if rows>MAX_CELLS-cells: return _empty("Shape hold cell budget exceeded; no partial mesh drawn")
		var cuts: Array=[t0,t1]
		for row in range(1,rows): cuts.append(_time(renderer,int(n.light),lerpf(p0,p1,float(row)/rows),now,fall))
		for ci in range(motion_cuts.bsearch(t0),motion_cuts.bsearch(t1)):
			var tau:=float(motion_cuts[ci])
			if tau>t0: cuts.append(tau)
		cuts.sort()
		if refine:
			var refined:=[t0]
			for i in cuts.size()-1:
				if float(cuts[i+1])<=float(cuts[i]):continue
				if not _refine(renderer,n,trap,float(cuts[i]),float(cuts[i+1]),refined,refinement_budget):return _empty(refinement_budget.error)
			cuts=refined
		if cuts.size()-1>MAX_CELLS-cells: return _empty("Shape hold cell budget exceeded; no partial mesh drawn")
		for row in cuts.size()-1:
			cells+=1
			var ta:=float(cuts[row]); var tb:=float(cuts[row+1])
			if tb<=ta: continue # Duplicate representable cut, with zero projected area.
			# One-sided samples keep topology changes at trap boundaries separate.
			var ra:=_row(renderer,n,lerpf(ta,tb,0.000001)); var rb:=_row(renderer,n,lerpf(ta,tb,0.999999))
			if ra.is_empty() or rb.is_empty(): continue
			var wa:=minf(float(ra.nwk)*thin/15.0,(float(ra.section[1])-float(ra.section[0]))*0.96)
			var wb:=minf(float(rb.nwk)*thin/15.0,(float(rb.section[1])-float(rb.section[0]))*0.96)
			var xa:=clampf(float(ra.x),float(ra.section[0])+wa*0.5,float(ra.section[1])-wa*0.5)
			var xb:=clampf(float(rb.x),float(rb.section[0])+wb*0.5,float(rb.section[1])-wb*0.5)
			var la:=Geometry.edge_x(trap.left,ta)*float(ra.sx)+float(ra.tx); var lb:=Geometry.edge_x(trap.left,tb)*float(rb.sx)+float(rb.tx)
			var rta:=Geometry.edge_x(trap.right,ta)*float(ra.sx)+float(ra.tx); var rtb:=Geometry.edge_x(trap.right,tb)*float(rb.sx)+float(rb.tx)
			# Never erase a legal thin section to satisfy an absolute inset.
			var ia:=minf(inset,maxf(0.0,rta-la)*0.01); var ib:=minf(inset,maxf(0.0,rtb-lb)*0.01)
			var left: Array=[la+ia,ta,lb+ib,tb]
			var right: Array=[rta-ia,ta,rtb-ib,tb]
			var poly:=_clip([[xa-wa*0.5,ta],[xa+wa*0.5,ta],[xb+wb*0.5,tb],[xb-wb*0.5,tb]],left,true)
			poly=_clip(poly,right,false)
			if poly.size()<3: continue
			var lo:=INF; var hi:=-INF
			for v in poly: lo=minf(lo,float(v[0])); hi=maxf(hi,float(v[0]))
			var cols:=maxi(1,int(ceil((hi-lo)/MAX_X_STEP)))
			if cols>MAX_CELLS-cells: return _empty("Shape hold cell budget exceeded; no partial mesh drawn")
			cells+=cols
			for col in cols:
				var c0:=lerpf(lo,hi,float(col)/cols); var c1:=lerpf(lo,hi,float(col+1)/cols)
				var part:=_clip(poly,[c0,ta,c0,tb],true); part=_clip(part,[c1,ta,c1,tb],false)
				if part.size()<3: continue
				var projected:Dictionary={}
				if integrated:
					projected=Mapper.polygon(renderer,int(n.light),part,projection_work)
					if not str(projection_work.error).is_empty():return _empty(projection_work.error)
					part=projected.vertices
					if projected.indices.is_empty():continue
				if out.points.size()+part.size()>MAX_VERTICES: return _empty("Shape hold vertex budget exceeded; no partial mesh drawn")
				var start: int=out.points.size()
				for v in part:
					var tau: float=v[1]; var p:=_progress(renderer,int(n.light),tau,now,fall); var s: float=renderer.s_of_p(p)
					var point:=Vector2(renderer.G.x_of(v[0],s),renderer.G.y_of(s))
					if not point.is_finite(): return _empty("Shape hold produced a non-finite mapped vertex")
					out.points.append(point); out.plane.append(Vector2(v[0],s)); out.times.append(tau)
					var k:=clampf((tau-ta)/(tb-ta),0.0,1.0); var width:=lerpf(wa,wb,k)
					out.uvs.append(Vector2(clampf((float(v[0])-lerpf(xa,xb,k))/maxf(width,1e-12)+0.5,0.0,1.0),0.97))
					var tail:=clampf((p-tail_p)/maxf(head_p-tail_p,1e-12)*7.0,0.0,1.0)
					out.colors.append(Color(SU.HOLD_COL.r,SU.HOLD_COL.g,SU.HOLD_COL.b,clampf(0.42*a*(0.35+0.65*tail),0.0,1.0)))
				if integrated:
					for index in projected.indices:out.indices.append(start+index)
				else:
					for j in range(1,part.size()-1): out.indices.append_array([start,start+j,start+j+1])
	if integrated:out["projection_sample_error"]=projection_work.sample_error
	return out

## Same hold staging as the standard provider, with a distinct geometry state
## at each cap and a shared, clipped body. Timing and judgement are untouched.
static func plan(renderer,n: Dictionary,st: Dictionary,t: float,fall: float,p_min: float,p_quick: float,p_end: float) -> void:
	var holding: bool=n.state=="holding"
	var active: bool=holding and n.get("gap_t",-1.0)<0.0
	var finished: bool=n.state=="done" or n.state=="fail"
	if (finished and p_end>=1.0) or n.state=="done": return
	var dmh: Dictionary=renderer._missed(n,st,t,fall)
	var pb:=minf(1.0 if (holding or finished or not dmh.is_empty()) else p_quick,1.1)
	var pt:=maxf(p_end,p_min)
	if pb<=pt: return
	var dead: bool=n.state=="miss" or n.state=="fail"
	var a: float=clampf((pb-p_min)/0.12,0.0,1.0)*st.alpha*(0.28 if dead else 1.0)
	if not dmh.is_empty(): a=dmh.a*(0.5 if dead else 1.0)
	var tau_h:=_time(renderer,int(n.light),pb,t,fall); var tau_t:=_time(renderer,int(n.light),pt,t,fall)
	var ph: Array=renderer._path_at(n,clampf(tau_h-float(n.t),0.0,float(n.dur))); var pe: Array=renderer._path_at(n,float(n.dur))
	st=state_at(renderer,n,tau_h,float(ph[0]))
	if not st.get("alive",false): return
	var head:=n.duplicate(); head.t=tau_h; head.u=ph[0]
	renderer._cur_st=st; renderer._cur_lw=st.w; renderer._cur_note=head
	var pb_note: Dictionary=renderer._note_at_u(st,float(ph[0]),pb)
	var hb_a: float=(1.0 if active else 0.75)*a
	var thin:=0.55 if holding and not active else 1.0
	var state:=st.duplicate()
	renderer._nd_holds.append(func(canvas): renderer._ribbon(canvas,n,state,tau_h,tau_t,t,fall,hb_a,0.0,thin))
	if p_end>p_min:
		var tail_st:=state_at(renderer,n,float(n.t+n.dur),float(pe[0])); var tail:=n.duplicate(); tail.t=n.t+n.dur; tail.u=pe[0]
		if tail_st.get("alive",false):
			renderer._cur_st=tail_st; renderer._cur_lw=tail_st.w; renderer._cur_note=tail
			renderer._draw_note(null,renderer._note_at_u(tail_st,float(pe[0]),p_end),a*0.55,0.7,Color.WHITE,false,float(pe[1]))
		renderer._cur_st=st; renderer._cur_lw=st.w; renderer._cur_note=head
	if not dmh.is_empty(): renderer._draw_note(null,dmh.P,dmh.a,1.0,dmh.col,n.big,float(ph[1]))
	elif n.state!="fail":
		renderer._letter_ok=not active and pb<1.0
		renderer._draw_note(null,pb_note,a,1.12+0.05*sin(renderer.f.perf*30.0) if active else 1.0,Color.WHITE,n.big,float(ph[1]))
		renderer._letter_ok=false
	if active and renderer._rng.randf()<renderer.f.dt*6.0: renderer.hits.append({"xl":pb_note.xl,"level":0.5,"born":renderer.last_fx_t})
