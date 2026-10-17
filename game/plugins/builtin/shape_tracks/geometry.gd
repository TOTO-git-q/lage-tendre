## Closed paths in (normalized x, chart seconds). Judgement uses float64 curves,
## never the flattened visual mesh. Each component is filled even-odd; holes are
## subtracted from their own component; all components are finally unioned.
extends RefCounted
const EPS := 1e-10
const CURVE_TOL := 0.00002
# Broad authoring limits keep float64 coefficients and render subdivisions bounded.
const MAX_X := 8.0
const MAX_TIME := 86400.0
const MAX_TRACKS := 64
const MAX_PATH_NODES := 512
const MAX_COMPONENTS := 32
const MAX_HOLES := 32
const MAX_VISUAL_EDGES := 2048
const MAX_CUTS := 4096
const MAX_TRAPEZOIDS := 8192
const MAX_MESH_VERTICES := 500000
const LIMITS := {"nodes":2048,"paths":128,"metadata":8192,"flatten_steps":32768,"edges":4096,"pairs":4000000,"sweep":8000000,"trapezoids":8192,"mesh_vertices":500000}

static func new_budget() -> Dictionary: return {"errors":[]}
static func _take(budget: Dictionary,key: String,count:=1) -> bool:
	if not budget.errors.is_empty(): return false
	budget[key]=int(budget.get(key,0))+count
	if budget[key] > LIMITS[key]: budget.errors.append("shape budget exceeded: "+key+" > "+str(LIMITS[key])); return false
	return true
static func bounded(v,limit: float) -> bool: return finite_number(v) and absf(float(v)) <= limit
static func valid_id(v) -> bool: return bounded(v,2147483647.0) and float(v) >= 0 and float(v)==floorf(float(v))

static func finite_number(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v))

static func validate_path(path, tag := "shape", budget: Dictionary = {}) -> Array:
	if budget.is_empty(): budget=new_budget()
	if not path is Dictionary: return [tag+": expected object"]
	if not _take(budget,"paths"): return budget.errors.duplicate()
	for field in ["pins","off"]:
		if not path.get(field,{}) is Dictionary: return [tag+": "+field+" must be an object"]
	for field in ["keep","pulses","props","holes"]:
		if not path.get(field,[]) is Array: return [tag+": "+field+" must be an array"]
	if not path.get("open_end",false) is bool: return [tag+": open_end must be boolean"]
	if path.has("id") and path.id != -1 and not valid_id(path.id): return [tag+": invalid shape id"]
	if path.get("holes",[]).size()>MAX_HOLES: return [tag+": holes exceed "+str(MAX_HOLES)]
	var metadata: int=path.get("pins",{}).size()+path.get("keep",[]).size()+path.get("pulses",[]).size()+path.get("props",[]).size()
	if not _take(budget,"metadata",metadata): return budget.errors.duplicate()
	for time in path.get("pins",{}):
		if not str(time).is_valid_float() or not bounded(float(time),MAX_TIME) or not path.pins[time] is Dictionary:
			return [tag+": pins require bounded time keys and object values"]
		if path.pins[time].get("from","LR") not in ["L","R","LR"] or not path.pins[time].get("auto",false) is bool:
			return [tag+": invalid pin cue metadata"]
	for pulse in path.get("pulses",[]):
		if not pulse is Dictionary or not bounded(pulse.get("t"),MAX_TIME) or not bounded(pulse.get("dur",0.0),MAX_TIME): return [tag+": malformed pulse"]
		if pulse.get("from","LR") not in ["L","R","LR"] or not pulse.get("auto",false) is bool: return [tag+": invalid pulse cue metadata"]
	var nodes=path.get("nodes",[]); var segs=path.get("segs",[])
	if not nodes is Array or nodes.size()<3 or nodes.size()>MAX_PATH_NODES: return [tag+": need 3.."+str(MAX_PATH_NODES)+" nodes"]
	if not segs is Array or segs.size()!=nodes.size(): return [tag+": one segment per node is required"]
	if not _take(budget,"nodes",nodes.size()): return budget.errors.duplicate()
	for n in nodes:
		if not n is Array or n.size()<2 or n.size()>3 or not bounded(n[0],MAX_X) or not bounded(n[1],MAX_TIME): return [tag+": nodes require |x|<=8, |t|<=86400"]
		if n.size()==3 and not n[2] is bool: return [tag+": smooth must be boolean"]
	for seg in segs:
		if not seg is Array or seg.is_empty() or seg[0] not in ["linear","in","out","inout","bezier"]: return [tag+": unknown segment curve"]
		if seg[0]=="bezier":
			if seg.size()!=5: return [tag+": bezier is [bezier,h1x,h1t,h2x,h2t]"]
			if not bounded(seg[1],MAX_X) or not bounded(seg[3],MAX_X) or not bounded(seg[2],MAX_TIME) or not bounded(seg[4],MAX_TIME): return [tag+": handle exceeds coordinate bounds"]
		elif seg.size()!=1: return [tag+": named segment takes no handles"]
	for prop in path.get("props",[]):
		if not prop is Dictionary or not bounded(prop.get("t"),MAX_TIME) or not bounded(prop.get("a"),1.0) or not bounded(prop.get("tint"),9.0): return [tag+": invalid property key"]
		if float(prop.tint)!=floorf(float(prop.tint)) or prop.tint < -1: return [tag+": palette is out of range"]
	for hole in path.get("holes",[]):
		if hole is Dictionary and (not hole.get("holes",[]) is Array or not hole.get("holes",[]).is_empty()): return [tag+": nested holes are not supported"]
		var errors:=validate_path(hole,tag+".hole",budget)
		if not errors.is_empty(): return errors
	return []

static func _poly(a: float, b: float, c: float, d: float, u: float) -> float:
	return ((a * u + b) * u + c) * u + d

static func _coeff(p0: float, p1: float, p2: float, p3: float) -> Array:
	return [-p0 + 3.0*p1 - 3.0*p2 + p3, 3.0*p0 - 6.0*p1 + 3.0*p2, -3.0*p0 + 3.0*p1, p0]

static func _value(c: Array, u: float) -> float:
	return _poly(c[0], c[1], c[2], c[3], u)

static func _turns(c: Array) -> Array:
	var a: float = 3.0*c[0]; var b: float = 2.0*c[1]; var d: float = c[2]
	var roots := []
	if not is_finite(a) or not is_finite(b) or not is_finite(d): return []
	if absf(a) < EPS:
		if absf(b) >= EPS: roots.append(-d / b)
	else:
		var det := b*b - 4.0*a*d
		if not is_finite(det): return []
		if det >= 0.0:
			var q := -0.5 * (b + (1.0 if b >= 0.0 else -1.0) * sqrt(det))
			if absf(q) > EPS:
				roots.append(q/a); roots.append(d/q)
			else: roots.append(-b/(2.0*a))
	var out := [0.0]
	roots.sort()
	for u in roots:
		if u > EPS and u < 1.0 - EPS and absf(u - out[-1]) > EPS: out.append(u)
	out.append(1.0)
	return out

## Named eases match TrackShape.seg_eval, including time-reversed edges.
static func edge(path: Dictionary, i: int) -> Dictionary:
	var a: Array = path.nodes[i]; var b: Array = path.nodes[(i+1) % path.nodes.size()]
	var seg: Array = path.segs[i]
	var cx: Array; var ct: Array
	if seg[0] == "bezier":
		cx = _coeff(a[0], seg[1], seg[3], b[0]); ct = _coeff(a[1], seg[2], seg[4], b[1])
	else:
		var x0 := float(a[0]); var x1 := float(b[0]); var t0 := float(a[1]); var t1 := float(b[1])
		# Reversing a named ease means evaluating the same low-time to high-time law.
		if t0 > t1:
			var tmp := x0; x0 = x1; x1 = tmp; tmp = t0; t0 = t1; t1 = tmp
		var ease: String = seg[0] if absf(t1-t0) > EPS else "linear"
		var handles: Array = {"linear": [1.0/3.0, 2.0/3.0], "in": [0.0, 0.0], "out": [1.0, 1.0], "inout": [0.0, 1.0]}[ease]
		cx = _coeff(x0, lerpf(x0,x1,handles[0]), lerpf(x0,x1,handles[1]), x1)
		ct = [0.0, 0.0, t1-t0, t0]
	return {"x": cx, "t": ct, "turns": _turns(ct)}

static func prepare_path(path: Dictionary) -> Dictionary:
	var edges := []; var lo := INF; var hi := -INF
	for i in path.nodes.size():
		var additions := []
		var a: Array=path.nodes[i]; var b: Array=path.nodes[(i+1)%path.nodes.size()]
		if path.segs[i][0] == "inout" and absf(float(b[1])-float(a[1])) > EPS:
			var low: Array=a if a[1] < b[1] else b; var high: Array=b if a[1] < b[1] else a
			var mid := [(float(low[0])+float(high[0]))*0.5,(float(low[1])+float(high[1]))*0.5]
			additions.append(edge({"nodes":[low,mid],"segs":[["in"],["linear"]]},0))
			additions.append(edge({"nodes":[mid,high],"segs":[["out"],["linear"]]},0))
		else: additions.append(edge(path,i))
		for e in additions:
			if e.turns.is_empty(): return {"errors":["non-finite derived curve"]}
			for coefficient in e.x+e.t:
				if not is_finite(coefficient): return {"errors":["non-finite derived coefficient"]}
			edges.append(e)
			for u in e.turns:
				var t := _value(e.t, u)
				if not is_finite(t): return {"errors":["non-finite derived time"]}
				lo=minf(lo,t); hi=maxf(hi,t)
	var holes := []
	for h in path.get("holes", []):
		var hole:=prepare_path(h)
		if not hole.get("errors",[]).is_empty(): return hole
		holes.append(hole)
	return {"edges": edges, "lo": lo, "hi": hi, "holes": holes, "source": path}

static func prepare(track: Dictionary,budget: Dictionary = {}) -> Dictionary:
	if budget.is_empty(): budget=new_budget()
	var failed: Dictionary={"components":[],"lo":INF,"hi":-INF,"id":track.get("id",-1),"errors":[]}
	if not valid_id(track.get("id")) or not track.get("shapes") is Array or track.shapes.is_empty() or track.shapes.size()>MAX_COMPONENTS:
		failed.errors=["track requires valid id and 1..32 components"]; return failed
	for shape in track.shapes:
		var errors:=validate_path(shape,"shape",budget)
		if not errors.is_empty(): failed.errors=errors; return failed
	var components:=[]; var lo:=INF; var hi:=-INF; var xlo:=INF; var xhi:=-INF; var crossings:=0
	for shape in track.shapes:
		var p:=prepare_path(shape)
		if not p.get("errors",[]).is_empty(): failed.errors=p.errors; return failed
		components.append(p); lo=minf(lo,p.lo); hi=maxf(hi,p.hi)
		for path in [p]+p.holes:
			for e in path.edges: crossings+=e.turns.size()-1
			for n in path.source.nodes: xlo=minf(xlo,n[0]); xhi=maxf(xhi,n[0])
			for seg in path.source.segs:
				if seg[0]=="bezier": xlo=minf(xlo,minf(seg[1],seg[3])); xhi=maxf(xhi,maxf(seg[1],seg[3]))
	return {"components":components,"lo":lo,"hi":hi,"id":track.id,"x_span":xhi-xlo,"crossings":crossings,"errors":[]}

static func path_sections(path: Dictionary, t: float) -> Array:
	if not is_finite(t) or t < path.lo or t >= path.hi: return []
	var xs := []
	for e in path.edges:
		for j in e.turns.size()-1:
			var a: float = e.turns[j]; var b: float = e.turns[j+1]
			var ta := _value(e.t,a); var tb := _value(e.t,b)
			var low := minf(ta,tb); var high := maxf(ta,tb)
			# A horizontal edge contributes no crossing. Half-open endpoints ensure
			# a shared vertex is counted once; a tangent contributes 0 or 2.
			if high-low <= EPS or t < low or t >= high: continue
			var u := a if t == ta else b if t == tb else (a+b)*0.5
			if t != ta and t != tb:
				for iteration in 52:
					u = (a+b)*0.5
					if (_value(e.t,u) < t) == (tb > ta): a=u
					else: b=u
			var x := _value(e.x,u)
			if is_finite(x): xs.append(x)
	xs.sort()
	var intervals := []
	for i in range(0,xs.size()-1,2):
		if xs[i+1]-xs[i] > EPS: intervals.append([xs[i],xs[i+1]])
	return intervals

static func union(intervals: Array) -> Array:
	var rows := intervals.duplicate(true)
	rows.sort_custom(func(a,b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out := []
	for r in rows:
		if r.size()!=2 or not is_finite(r[0]) or not is_finite(r[1]) or r[1]-r[0] <= EPS: continue
		if out.is_empty() or r[0] > out[-1][1]+EPS: out.append(r)
		else: out[-1][1] = maxf(out[-1][1],r[1])
	return out

static func subtract(outer: Array, holes: Array) -> Array:
	var out := []
	for r in outer:
		var x: float = r[0]
		for h in holes:
			if h[1] <= x or h[0] >= r[1]: continue
			if h[0] > x+EPS: out.append([x,minf(h[0],r[1])])
			x = maxf(x,h[1])
			if x >= r[1]: break
		if x < r[1]-EPS: out.append([x,r[1]])
	return out

static func sections(prepared: Dictionary, t: float) -> Array:
	var all := []
	for p in prepared.get("components", []):
		var base := path_sections(p,t); var holes := []
		for h in p.holes: holes.append_array(path_sections(h,t))
		all.append_array(subtract(base,union(holes)))
	return union(all)

static func property_at(path: Dictionary, t: float) -> Dictionary:
	var props: Array = path.get("props", [])
	if props.is_empty(): return {"a": -1.0,"tint": -1}
	var cur: Dictionary = props[0]
	for p in props:
		if p.t <= t+1e-7: cur=p
		elif absf(t-cur.t) <= 1e-7: break
		else:
			var k := clampf((t-cur.t)/maxf(1e-7,p.t-cur.t),0.0,1.0)
			return {"a": lerpf(cur.a,p.a,k) if cur.a >= 0 and p.a >= 0 else float(p.a),"tint": int(p.tint)}
	return {"a": float(cur.a),"tint": int(cur.tint)}

static func style(prepared: Dictionary,t: float) -> Dictionary:
	for p in prepared.components:
		if t >= p.lo-EPS and t <= p.hi+EPS: return property_at(p.source,t)
	return {"a":-1.0,"tint":-1}

static func sample(prepared: Dictionary, t: float) -> Dictionary:
	var iv := sections(prepared,t)
	var st := {"alive": not iv.is_empty(),"x": 0.5,"w": 0.0,"reach": 1.0,"alpha": 1.0,"yellow": 0.0,"pulse": 0.0,"a": -1.0,"tint": -1,"geometry": "shape","sections": iv,"shape": prepared}
	if iv.is_empty(): st.alpha=0.0; return st
	st.x = (iv[0][0]+iv[-1][1])*0.5; st.w = iv[-1][1]-iv[0][0]
	for p in prepared.components:
		if not path_sections(p,t).is_empty():
			st.merge(property_at(p.source,t),true); break
	return st

## Visual landing stays within an actual filled interval; u retains envelope
## coordinates for compatibility with the charter's re-seated notes.
static func note_section(st: Dictionary, u: float) -> Array:
	# Positive visual affine maps preserve the original nearest-section choice.
	# Re-comparing translated float distances can flip an exact midpoint tie.
	var basis: Dictionary=st.get("_visual_section_basis",st)
	var x: float=basis.x+(u-0.5)*basis.w; var best:=[]; var distance:=INF
	var source: Array=basis.get("sections",[]); var spans: Array=st.get("sections",[])
	for i in mini(source.size(),spans.size()):
		var r: Array=source[i]; var d:=absf(x-clampf(x,r[0],r[1]))
		if d<distance: distance=d; best=spans[i]
	return best

static func note_x(st: Dictionary, u: float) -> float:
	var r := note_section(st,u)
	var x: float = st.x+(u-0.5)*st.w
	return clampf(x,r[0],r[1]) if not r.is_empty() else x

## Visual envelope transforms never alter the compiled shape or hit sections.
## Positive widths preserve interval order; a collapsed envelope is invisible.
static func visual_transform(state: Dictionary,new_x: float,new_w: float) -> Dictionary:
	var out:=state.duplicate(); out["sections"]=[]
	var old_x:=float(state.get("x",0.5)); var old_w:=float(state.get("w",0.0))
	out.x=new_x if is_finite(new_x) else old_x if is_finite(old_x) else 0.5
	out.w=new_w if is_finite(new_w) and new_w>=0.0 else 0.0
	if not state.get("alive",false) or not is_finite(old_x) or not is_finite(old_w) or old_w<=0.0 or not is_finite(new_x) or not is_finite(new_w) or new_w<=0.0:
		out.alive=false; return out
	# One minimal, owned source basis is shared by later visual copies, never a
	# state reference or transform chain. Physics states never receive this key.
	if not state.has("_visual_section_basis"):
		out["_visual_section_basis"]={"x":old_x,"w":old_w,"sections":state.get("sections",[]).duplicate(true)}
	for span in state.get("sections",[]):
		# Normalize before scaling so even tiny positive source envelopes cannot
		# overflow an intermediate scale factor.
		out.sections.append([new_x+((float(span[0])-old_x)/old_w)*new_w,new_x+((float(span[1])-old_x)/old_w)*new_w])
	out.alive=not out.sections.is_empty()
	return out

## Adaptive visual flattening only; judgement always uses the original cubics.
static func _flatten_edge(e: Dictionary,a: float,b: float,out: Array,budget: Dictionary,depth:=0) -> void:
	if not _take(budget,"flatten_steps"): return
	var pa:=[_value(e.x,a),_value(e.t,a)]; var pb:=[_value(e.x,b),_value(e.t,b)]
	var error:=0.0
	for f in [0.25,0.5,0.75]:
		var u:=lerpf(a,b,f)
		error=maxf(error,maxf(absf(_value(e.x,u)-lerpf(pa[0],pb[0],f)),absf(_value(e.t,u)-lerpf(pa[1],pb[1],f))))
	if not is_finite(error): budget.errors.append("non-finite flattened edge"); return
	if error>CURVE_TOL:
		if depth>=14: budget.errors.append("curve flattening tolerance exceeds subdivision budget"); return
		_flatten_edge(e,a,(a+b)*0.5,out,budget,depth+1); _flatten_edge(e,(a+b)*0.5,b,out,budget,depth+1)
	elif absf(pb[1]-pa[1])>EPS:
		if not _take(budget,"edges"): return
		out.append([pa[0],pa[1],pb[0],pb[1]])

static func visual_edges(path: Dictionary,budget: Dictionary = {}) -> Array:
	if budget.is_empty(): budget=new_budget()
	var out:=[]
	for e in path.edges:
		for j in e.turns.size()-1:
			_flatten_edge(e,e.turns[j],e.turns[j+1],out,budget)
			if not budget.errors.is_empty(): return []
	return out

static func edge_x(e: Array,t: float) -> float:
	return e[0]+(e[2]-e[0])*(t-e[1])/(e[3]-e[1])

static func _scan_edges(edges: Array,t: float) -> Array:
	var xs := []
	for e in edges:
		if minf(e[1],e[3]) <= t and maxf(e[1],e[3]) > t: xs.append({"x": edge_x(e,t),"edge": e})
	xs.sort_custom(func(a,b): return a.x < b.x)
	var rows := []
	for i in range(0,xs.size()-1,2):
		if xs[i+1].x-xs[i].x > EPS: rows.append([xs[i],xs[i+1]])
	return rows

## A plane sweep produces disjoint trapezoids for the complete UNION, including
## holes and self-intersections. Every vertex and edge-crossing time is a cut.
static func trapezoids(prepared: Dictionary,budget: Dictionary = {}) -> Array:
	if budget.is_empty(): budget=new_budget()
	if not prepared.get("errors",[]).is_empty(): return []
	var all := []; var components := []; var times := []
	for p in prepared.components:
		var outer := visual_edges(p,budget); var holes := []
		all.append_array(outer)
		for h in p.holes:
			var edges := visual_edges(h,budget); holes.append(edges); all.append_array(edges)
		components.append({"outer":outer,"holes":holes})
	if not budget.errors.is_empty(): prepared.errors=budget.errors.duplicate(); return []
	if all.size()>MAX_VISUAL_EDGES: prepared.errors=["track flattened edges exceed 2048 before pair sweep"]; return []
	if not _take(budget,"pairs",all.size()*(all.size()-1)/2): prepared.errors=budget.errors.duplicate(); return []
	prepared["visual_edge_count"]=all.size()
	for e in all: times.append(e[1]); times.append(e[3])
	for i in all.size():
		var a: Array = all[i]
		for j in range(i+1,all.size()):
			var b: Array = all[j]
			var lo := maxf(minf(a[1],a[3]),minf(b[1],b[3])); var hi := minf(maxf(a[1],a[3]),maxf(b[1],b[3]))
			if hi-lo <= EPS: continue
			var d0 := edge_x(a,lo)-edge_x(b,lo); var d1 := edge_x(a,hi)-edge_x(b,hi)
			if d0*d1 < 0.0:
				times.append(lerpf(lo,hi,d0/(d0-d1)))
				if times.size()>MAX_CUTS*2: prepared.errors=["intersection cut budget exceeded"]; return []
	times.sort()
	var cuts := []
	for t in times:
		if cuts.is_empty() or t-cuts[-1] > EPS: cuts.append(t)
	if cuts.size()>MAX_CUTS: prepared.errors=["unique cut budget exceeded"]; return []
	if not _take(budget,"sweep",maxi(0,cuts.size()-1)*all.size()): prepared.errors=budget.errors.duplicate(); return []
	var out := []
	for i in cuts.size()-1:
		var lo: float=cuts[i]; var hi: float=cuts[i+1]; var mid := (lo+hi)*0.5
		var events := []
		for p in components:
			var outer := _scan_edges(p.outer,mid); var holes := []
			for edges in p.holes: holes.append_array(_scan_edges(edges,mid))
			for r in outer:
				var pieces := [r]
				for h in holes:
					var next := []
					for piece in pieces:
						if not _take(budget,"sweep"): prepared.errors=budget.errors.duplicate(); return []
						if h[1].x <= piece[0].x or h[0].x >= piece[1].x: next.append(piece); continue
						if h[0].x > piece[0].x: next.append([piece[0],h[0]])
						if h[1].x < piece[1].x: next.append([h[1],piece[1]])
					pieces=next
				for piece in pieces:
					events.append({"point":piece[0],"delta":1}); events.append({"point":piece[1],"delta":-1})
		events.sort_custom(func(a,b): return a.point.x < b.point.x if a.point.x != b.point.x else a.delta > b.delta)
		var depth := 0; var left := {}
		for event in events:
			if depth == 0: left=event.point
			depth += event.delta
			if depth == 0 and event.point.x-left.x > EPS:
				if not _take(budget,"trapezoids"): prepared.errors=budget.errors.duplicate(); return []
				out.append({"t0":lo,"t1":hi,"left":left.edge,"right":event.point.edge})
	var mesh_bound:=int(ceil(400.0*(ceil(prepared.x_span*48.0)+2*prepared.crossings)))
	for trap in out:
		var width:=maxf(edge_x(trap.right,trap.t0)-edge_x(trap.left,trap.t0),edge_x(trap.right,trap.t1)-edge_x(trap.left,trap.t1))
		mesh_bound+=2*(maxi(1,int(ceil(width*48.0)))+1)
	if not _take(budget,"mesh_vertices",mesh_bound): prepared.errors=budget.errors.duplicate(); return []
	prepared["mesh_vertex_bound"]=mesh_bound
	return out
