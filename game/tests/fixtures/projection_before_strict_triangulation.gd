## P5-only curved projection of already-clipped filled polygons.
## Adaptive screen boundaries are triangulated after projection, rather than
## joining mapped endpoints across an SV discontinuity or a curved hole edge.
extends RefCounted
const SAMPLE_ERROR_PX:=0.015625
const MAX_DEPTH:=20
const MAX_STEPS:=65536

static func budget(renderer,id: int,a: float,b: float,limit: int) -> Dictionary:
	var cuts: Array=renderer.visual_time_cuts(id,a,b) if renderer.has_method("visual_time_cuts") else []
	for p in [0.0,1.0,1.25]:
		var tau:float=renderer.visual_time(id,p)
		if tau>a and tau<b:cuts.append(tau)
	cuts.sort()
	return {"cuts":cuts,"steps":0,"vertices":0,"limit":limit,"error":"","sample_error":0.0}

static func _sample(renderer,id: int,a: Array,b: Array,k: float) -> Array:
	var x:=lerpf(a[0],b[0],k);var tau:=lerpf(a[1],b[1],k)
	var s:float=renderer.s_of_p(renderer.visual_progress(id,tau))
	return [x,tau,s,renderer.G.x_of(x,s),renderer.G.y_of(s)]

static func _distance(p: Array,a: Array,b: Array) -> float:
	var dx:float=b[3]-a[3];var dy:float=b[4]-a[4]
	var length:=dx*dx+dy*dy
	var q:=clampf(((float(p[3])-float(a[3]))*dx+(float(p[4])-float(a[4]))*dy)/length,0.0,1.0) if length>0.0 else 0.0
	return sqrt(pow(float(p[3])-lerpf(a[3],b[3],q),2)+pow(float(p[4])-lerpf(a[4],b[4],q),2))

static func _append(out: Array,p: Array,work: Dictionary) -> bool:
	for value in p:
		if not is_finite(float(value)):work.error="Shape projection produced non-finite coordinates";return false
	if not Vector2(p[3],p[4]).is_finite():work.error="Shape projection exceeds packed coordinate range";return false
	work.vertices+=1
	if work.vertices>int(work.limit):work.error="Shape projection vertex budget exceeded; no partial mesh drawn";return false
	out.append(p);return true

static func _segment(renderer,id: int,a: Array,b: Array,pa: Array,pb: Array,out: Array,work: Dictionary,depth:=0) -> bool:
	work.steps+=1
	if work.steps>MAX_STEPS:work.error="Shape projection work budget exceeded; no partial mesh drawn";return false
	if a[1]==b[1]:return _append(out,pb,work)
	var worst:=0.0;var middle:=[]
	for i in range(1,8):
		var point:=_sample(renderer,id,a,b,float(i)/8.0)
		for value in point:
			if not is_finite(float(value)):work.error="Shape projection produced non-finite coordinates";return false
		if not Vector2(point[3],point[4]).is_finite():work.error="Shape projection exceeds packed coordinate range";return false
		worst=maxf(worst,_distance(point,pa,pb))
		if i==4:middle=point
	if worst>SAMPLE_ERROR_PX:
		var midpoint:=[middle[0],middle[1]]
		if depth>=MAX_DEPTH or midpoint==a or midpoint==b:
			work.error="Shape projection precision/depth budget exceeded; no partial mesh drawn";return false
		return _segment(renderer,id,a,midpoint,pa,middle,out,work,depth+1) and _segment(renderer,id,midpoint,b,middle,pb,out,work,depth+1)
	work.sample_error=maxf(float(work.sample_error),worst)
	return _append(out,pb,work)

static func _edge(renderer,id: int,a: Array,b: Array,out: Array,work: Dictionary) -> bool:
	var parts:=[0.0,1.0]
	if a[1]!=b[1]:
		var lo:=minf(a[1],b[1]);var hi:=maxf(a[1],b[1])
		for i in range(work.cuts.bsearch(lo),work.cuts.bsearch(hi)):
			var tau:=float(work.cuts[i])
			if tau>lo:parts.append((tau-float(a[1]))/(float(b[1])-float(a[1])))
	parts.sort()
	for i in parts.size()-1:
		if parts[i+1]<=parts[i]:continue
		var pa:=_sample(renderer,id,a,b,parts[i]);var pb:=_sample(renderer,id,a,b,parts[i+1])
		if not _segment(renderer,id,[pa[0],pa[1]],[pb[0],pb[1]],pa,pb,out,work):return false
	return true

static func edge(renderer,id: int,a: Array,b: Array,work: Dictionary) -> Array:
	var out:=[]
	if not _append(out,_sample(renderer,id,a,b,0.0),work):return []
	if not _edge(renderer,id,a,b,out,work):return []
	return out

static func polygon(renderer,id: int,poly: Array,work: Dictionary) -> Dictionary:
	var vertices:=[];var points:=PackedVector2Array()
	if poly.size()<3:return {"vertices":vertices,"points":points,"indices":PackedInt32Array()}
	if not _append(vertices,_sample(renderer,id,poly[0],poly[0],0.0),work):return {}
	for i in poly.size():
		if not _edge(renderer,id,poly[i],poly[(i+1)%poly.size()],vertices,work):return {}
	vertices.pop_back()
	var unique:=[]
	for vertex in vertices:
		var point:=Vector2(vertex[3],vertex[4])
		if points.is_empty() or point!=points[-1]:points.append(point);unique.append(vertex)
	if points.size()>1 and points[0]==points[-1]:points.resize(points.size()-1);unique.pop_back()
	if points.size()<3:return {"vertices":[],"points":PackedVector2Array(),"indices":PackedInt32Array()}
	# Normalize only triangulation input; submit the unchanged screen points.
	# This preserves valid thin polygons without float32 screen-area cancellation.
	var lo:=points[0];var hi:=points[0]
	for point in points:lo=lo.min(point);hi=hi.max(point)
	var span:=hi-lo
	if span.x==0.0 or span.y==0.0:return {"vertices":[],"points":PackedVector2Array(),"indices":PackedInt32Array()}
	var local:=PackedVector2Array()
	for point in points:local.append((point-lo)/span)
	var indices:=Geometry2D.triangulate_polygon(local)
	if indices.is_empty():
		var area:=0.0
		for i in points.size():area+=float(points[i].x)*float(points[(i+1)%points.size()].y)-float(points[(i+1)%points.size()].x)*float(points[i].y)
		if absf(area)>0.00001:work.error="Shape projected polygon triangulation failed; no partial mesh drawn";return {}
		return {"vertices":[],"points":PackedVector2Array(),"indices":PackedInt32Array()}
	return {"vertices":unique,"points":points,"indices":indices}
