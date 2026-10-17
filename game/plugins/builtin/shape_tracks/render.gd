## Shape meshes are triangulated in (x,s), then mapped to the arched field.
## Trapezoids partition the exact flattened union, so holes never get filled and
## overlapping components never receive multiple alpha blends.
extends RefCounted
const Geometry = preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Mapper = preload("res://plugins/builtin/shape_tracks/projection.gd")
const MAX_X_STEP := 1.0/48.0
const MAX_P_STEP := 1.0/100.0

static func _empty(message: String) -> Dictionary:
	return {"points":PackedVector2Array(),"plane":PackedVector2Array(),"indices":PackedInt32Array(),"times":[],"errors":[message]}

static func mesh(renderer, prepared: Dictionary) -> Dictionary:
	if not prepared.get("errors",[]).is_empty(): return _empty("Rejected shape geometry")
	if not Geometry.finite_number(renderer.f.get("t")) or not Geometry.finite_number(renderer.f.get("fall")) or not Geometry.finite_number(renderer.f.get("reach")) or renderer.f.fall<=0 or renderer.f.reach<0 or renderer.f.reach>1:
		return _empty("Shape frame requires finite time, positive fall and reach in [0,1]")
	if renderer.has_method("uses_integrated_scroll") and renderer.uses_integrated_scroll(): return _projected_mesh(renderer,prepared)
	var points := PackedVector2Array(); var plane := PackedVector2Array(); var indices := PackedInt32Array(); var times := []
	var now := float(renderer.f.t); var fall := maxf(0.001,float(renderer.f.fall))
	var integrated: bool=renderer.has_method("uses_integrated_scroll") and renderer.uses_integrated_scroll()
	var end: float=renderer.visual_time(int(prepared.id),1.0-float(renderer.f.reach)) if integrated else now+fall*float(renderer.f.reach)
	for trap in prepared.get("trapezoids", []):
		var t0 := maxf(trap.t0,now); var t1 := minf(trap.t1,end)
		if t1-t0 <= Geometry.EPS: continue
		var p0: float=renderer.visual_progress(int(prepared.id),t0) if integrated else 1.0-(t0-now)/fall
		var p1: float=renderer.visual_progress(int(prepared.id),t1) if integrated else 1.0-(t1-now)/fall
		var rows := maxi(1,int(ceil((p0-p1)/MAX_P_STEP))) if integrated else maxi(1,int(ceil((t1-t0)/(fall*MAX_P_STEP))))
		for row in rows:
			var a := lerpf(t0,t1,float(row)/rows); var b := lerpf(t0,t1,float(row+1)/rows)
			if integrated:
				a=renderer.visual_time(int(prepared.id),lerpf(p0,p1,float(row)/rows)); b=renderer.visual_time(int(prepared.id),lerpf(p0,p1,float(row+1)/rows))
			var la := Geometry.edge_x(trap.left,a); var ra := Geometry.edge_x(trap.right,a)
			var lb := Geometry.edge_x(trap.left,b); var rb := Geometry.edge_x(trap.right,b)
			var cols := maxi(1,int(ceil(maxf(ra-la,rb-lb)/MAX_X_STEP)))
			var sa: float=renderer.s_of_p(1.0-(a-now)/fall); var sb: float=renderer.s_of_p(1.0-(b-now)/fall)
			if integrated:
				sa=renderer.s_of_p(renderer.visual_progress(int(prepared.id),a)); sb=renderer.s_of_p(renderer.visual_progress(int(prepared.id),b))
			if points.size()+2*(cols+1)>Geometry.MAX_MESH_VERTICES: return _empty("Shape mesh vertex budget exceeded; no partial mesh drawn")
			var start := points.size()
			for j in cols+1:
				var f := float(j)/cols
				for pair in [[lerpf(la,ra,f),sa,a],[lerpf(lb,rb,f),sb,b]]:
					plane.append(Vector2(pair[0],pair[1])); times.append(pair[2])
					points.append(Vector2(renderer.G.x_of(pair[0],pair[1]),renderer.G.y_of(pair[1])))
				if j < cols:
					var k := start+j*2; indices.append_array([k,k+1,k+2,k+1,k+3,k+2])
	return {"points":points,"plane":plane,"indices":indices,"times":times,"errors":[]}

## Only the explicitly nonneutral SV path uses mapped-polygon triangulation.
static func _projected_mesh(renderer,prepared:Dictionary)->Dictionary:
	var out:={"points":PackedVector2Array(),"plane":PackedVector2Array(),"indices":PackedInt32Array(),"times":[],"errors":[]}
	var id:=int(prepared.id);var now:=float(renderer.f.t);var end:float=renderer.visual_time(id,1.0-float(renderer.f.reach))
	var work:=Mapper.budget(renderer,id,now,end,Geometry.MAX_MESH_VERTICES)
	for trap in prepared.get("trapezoids",[]):
		var a:=maxf(float(trap.t0),now);var b:=minf(float(trap.t1),end)
		if b-a<=Geometry.EPS:continue
		var p0:float=renderer.visual_progress(id,a);var p1:float=renderer.visual_progress(id,b)
		var rows:=maxi(1,int(ceil((p0-p1)/MAX_P_STEP)));var cuts:=[a,b]
		for i in range(1,rows):cuts.append(renderer.visual_time(id,lerpf(p0,p1,float(i)/rows)))
		for i in range(work.cuts.bsearch(a),work.cuts.bsearch(b)):
			if float(work.cuts[i])>a:cuts.append(work.cuts[i])
		cuts.sort()
		for i in cuts.size()-1:
			var ta:=float(cuts[i]);var tb:=float(cuts[i+1])
			if tb<=ta:continue
			var la:=Geometry.edge_x(trap.left,ta);var ra:=Geometry.edge_x(trap.right,ta)
			var lb:=Geometry.edge_x(trap.left,tb);var rb:=Geometry.edge_x(trap.right,tb)
			var cols:=maxi(1,int(ceil(maxf(ra-la,rb-lb)/MAX_X_STEP)))
			for j in cols:
				var q0:=float(j)/cols;var q1:=float(j+1)/cols
				var poly:=[[lerpf(la,ra,q0),ta],[lerpf(la,ra,q1),ta],[lerpf(lb,rb,q1),tb],[lerpf(lb,rb,q0),tb]]
				var data:=Mapper.polygon(renderer,id,poly,work)
				if not str(work.error).is_empty():return _empty(work.error)
				if data.indices.is_empty():continue
				var start:int=out.points.size();out.points.append_array(data.points)
				for vertex in data.vertices:out.plane.append(Vector2(vertex[0],vertex[2]));out.times.append(vertex[1])
				for index in data.indices:out.indices.append(start+index)
	out["projection_sample_error"]=work.sample_error
	return out

## Plan every outline before submitting any of this track's segments.
static func projected_lines(renderer,prepared:Dictionary)->Dictionary:
	var out:={"lines":[],"errors":[],"projection_sample_error":0.0}
	var id:=int(prepared.id);var now:=float(renderer.f.t);var end:float=renderer.visual_time(id,1.0-float(renderer.f.reach))
	var work:=Mapper.budget(renderer,id,now,end,Geometry.MAX_MESH_VERTICES)
	for trap in prepared.get("trapezoids",[]):
		var a:=maxf(now,float(trap.t0));var b:=minf(end,float(trap.t1))
		if b-a<=Geometry.EPS:continue
		var style:=Geometry.style(prepared,(a+b)*0.5);var opacity:float=style.a if style.a>=0.0 else 1.0
		if opacity<=0.002:continue
		for edge in [trap.left,trap.right]:
			var vertices:=Mapper.edge(renderer,id,[Geometry.edge_x(edge,a),a],[Geometry.edge_x(edge,b),b],work)
			if not str(work.error).is_empty():return {"lines":[],"errors":[work.error],"projection_sample_error":work.sample_error}
			var points:=PackedVector2Array();var colors:=PackedColorArray()
			for v in vertices:
				points.append(Vector2(v[3],v[4]))
				colors.append(Color(0.75,0.85,1.0,0.45*opacity*clampf((float(v[2])-renderer.s_of_p(1.0-renderer.f.reach))*8.0,0.0,1.0)))
			if points.size()>1:out.lines.append({"points":points,"colors":colors})
	out.projection_sample_error=work.sample_error
	return out

static func _prepared(renderer) -> Array:
	var result := []
	if renderer.f.is_empty() or not renderer.f.get("play",false): return result
	for segments in renderer.f.tl.values():
		for seg in segments:
			if seg.get("type","") == "shape_track": result.append(seg.shape)
	return result

static func surfaces(renderer,canvas: CanvasItem) -> void:
	for prepared in _prepared(renderer):
		var data := mesh(renderer,prepared)
		if not data.errors.is_empty() and not prepared.get("render_warning",false):
			prepared["render_warning"]=true; push_warning("; ".join(data.errors))
		if data.indices.is_empty(): continue
		var colors := PackedColorArray(); var sampled := {}
		for i in data.points.size():
			var time: float=data.times[i]
			if not sampled.has(time): sampled[time]=Geometry.style(prepared,time)
			var st: Dictionary=sampled[time]
			var tint := int(st.get("tint",-1)); var col: Color=renderer.PALETTE[tint] if tint >= 0 and tint < renderer.PALETTE.size() else Color.WHITE
			var opacity: float=st.get("a",-1.0); opacity=opacity if opacity >= 0 else 1.0
			var depth: float=clampf((data.plane[i].y-renderer.s_of_p(1.0-renderer.f.reach))*8.0,0.0,1.0)
			colors.append(Color(col.r,col.g,col.b,0.16*opacity*depth))
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),data.indices,data.points,colors)

static func edges(renderer,canvas: CanvasItem) -> void:
	if renderer.f.is_empty(): return
	var now := float(renderer.f.t); var fall := maxf(0.001,float(renderer.f.fall))
	var integrated: bool=renderer.has_method("uses_integrated_scroll") and renderer.uses_integrated_scroll()
	for prepared in _prepared(renderer):
		if integrated:
			var report:=projected_lines(renderer,prepared)
			if not report.errors.is_empty() and not prepared.get("edge_warning",false):
				prepared["edge_warning"]=true;push_warning("; ".join(report.errors))
			for line in report.lines:canvas.draw_polyline_colors(line.points,line.colors,1.6,true)
			continue
		var end: float=renderer.visual_time(int(prepared.id),1.0-float(renderer.f.reach)) if integrated else now+fall*float(renderer.f.reach)
		for trap in prepared.get("trapezoids",[]):
			var a := maxf(now,trap.t0); var b := minf(end,trap.t1)
			if b-a <= Geometry.EPS: continue
			var style := Geometry.style(prepared,(a+b)*0.5)
			var opacity: float=style.a if style.a >= 0.0 else 1.0
			if opacity <= 0.002: continue
			var p0: float=renderer.visual_progress(int(prepared.id),a) if integrated else 1.0-(a-now)/fall
			var p1: float=renderer.visual_progress(int(prepared.id),b) if integrated else 1.0-(b-now)/fall
			var count := maxi(1,int(ceil((p0-p1)/MAX_P_STEP))) if integrated else maxi(1,int(ceil((b-a)/(fall*MAX_P_STEP))))
			for edge in [trap.left,trap.right]:
				var points := PackedVector2Array(); var colors := PackedColorArray()
				for i in count+1:
					var t := lerpf(a,b,float(i)/count); var s: float=renderer.s_of_p(1.0-(t-now)/fall)
					if integrated:
						t=renderer.visual_time(int(prepared.id),lerpf(p0,p1,float(i)/count)); s=renderer.s_of_p(renderer.visual_progress(int(prepared.id),t))
					var x := Geometry.edge_x(edge,t)
					points.append(Vector2(renderer.G.x_of(x,s),renderer.G.y_of(s)))
					colors.append(Color(0.75,0.85,1.0,0.45*opacity*clampf((s-renderer.s_of_p(1.0-renderer.f.reach))*8.0,0.0,1.0)))
				canvas.draw_polyline_colors(points,colors,1.6,true)
	# Judgement strokes explicitly retain every disconnected section.
	for st in renderer.f.lights:
		if st.get("geometry","") != "shape" or not st.alive: continue
		var opacity: float=st.get("a",-1.0); opacity=opacity if opacity >= 0 else 1.0
		for r in st.sections:
			var a: float=renderer.G.x_of(r[0],1.0); var b: float=renderer.G.x_of(r[1],1.0)
			renderer._line_strip(canvas,a,b,maxf(30.0,(b-a)/renderer.aspect("line")*1.6),0.45*opacity)
