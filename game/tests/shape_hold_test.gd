## Actual hold renderer primitives. Self-contained fixtures, no silent skips.
extends SceneTree
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
var checks:=0
var failures:=0
var mode:="shape"
var curve:="linear"
var folder:=""
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func rect(x0: float,x1: float,t0: float,t1: float) -> Dictionary:
	return {"nodes":[[x0,t0],[x1,t0],[x1,t1],[x0,t1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func fixture(name: String,shapes: Array,u:=.5,path:=[]) -> Dictionary:
	return {"name":name,"shapes":shapes,"u":u,"path":path}
func fixtures() -> Array:
	var hole:=rect(.1,.9,1,5); hole["holes"]=[rect(.4,.6,1.1,4.9)]
	var tiny:=rect(.1,.9,1,5); tiny["holes"]=[rect(.4,.6,2.0321,2.0339)]
	var tapered:={"nodes":[[.1,1],[.4,1],[.7,5],[.4,5]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
	var curved:={"nodes":[[.1,1],[.6,1],[.65,5],[.15,5]],"segs":[["linear"],["bezier",.8,2,.45,4],["linear"],["bezier",.05,4,.3,2]]}
	return [fixture("cubic_sides",[curved]),fixture("plain_rectangle",[rect(.1,.9,1,5)]),fixture("rectangular_hole",[hole]),fixture("changing_sections",[tapered]),fixture("disconnected_path_jump",[rect(.1,.35,1,5),rect(.65,.9,1,5)],.1,[[0,.1,1],[2,.9,1]]),fixture("hole_between_old_rows",[tiny])]
func raw_for(fix: Dictionary) -> Dictionary:
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":fix.shapes}],"notes":[{"t":2,"light":0,"kind":"hold","dur":2,"u":fix.u,"path":fix.path}]}
	if mode!="shape":
		raw.plugins.append({"id":"note_motion","version":"1.0.0"})
		raw.notes[0]["motion"]={"type":"straight"} if fix.name=="hole_between_old_rows" else {"type":"horizontal","x0":.2,"ease":"linear"}
	if mode in ["neutral","speed","ramp"]:
		raw.plugins.append({"id":"fall_speed","version":"1.0.0"})
		raw["track_speeds"]=[{"id":0,"speed":1.0 if mode=="neutral" else 1.2}]
		if mode=="ramp": raw["sv"]=[{"t":1,"speed":.5,"dur":1.5,"ease":"inout"},{"t":3,"speed":1.5,"dur":1.0,"ease":"out"}]
	return raw
func _init() -> void:
	KB.set_layout("ansi")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode=arg.substr(7)
		if arg.begins_with("--curve="): curve=arg.substr(8)
	check(curve in ["linear","deemo"],"explicit projection curve")
	check(mode in ["shape","motion","neutral","speed","ramp"],"explicit supported test mode")
	folder=ProjectSettings.globalize_path("user://shape-hold-fixture")
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"writable self-contained fixture root")
	for fix in fixtures(): run_fixture(fix)
	check(PluginRegistry.standard().manifests.size()==4,"default standard catalog still four")
	print("SHAPE HOLD ",mode," / ",curve,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func projected_time(r,s: float) -> float:
	var p: float=(s-BuiltinRenderData.S0)/(1.0-BuiltinRenderData.S0) if r.curve=="linear" else 1.0-(1.0/s-1.0)/BuiltinRenderData.PK
	return r.visual_time(0,p) if r.has_method("visual_time") else float(r.f.t)+(1.0-p)*float(r.f.fall)
func state_at(r,n: Dictionary,tau: float) -> Dictionary:
	var path: Array=r._path_at(n,clampf(tau-float(n.t),0.,float(n.dur)))
	var point:=n.duplicate(); point.t=tau; point.u=path[0]
	return r._land_st(point,r._light_at(r.f.tl[0],tau))
func inside(r,n: Dictionary,x: float,tau: float,epsilon:=0.00008) -> bool:
	for span in state_at(r,n,tau).get("sections",[]):
		if x>=float(span[0])-epsilon and x<=float(span[1])+epsilon: return true
	return false
func polygon_area(poly: PackedVector2Array) -> float:
	var total:=0.0
	for i in poly.size(): total+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(total)*.5
func run_fixture(fix: Dictionary) -> void:
	var s:=SongPluginSession.new(); var raw:=raw_for(fix)
	var report:=s.prepare(folder,raw,"shape-hold-"+fix.name)
	check(report.errors.is_empty() and not report.requires_trust,fix.name+" prepare built-in scope")
	if not report.errors.is_empty(): printerr(report.errors); s.close(); return
	check(s.open().errors.is_empty(),fix.name+" open selected scope")
	var core:=GameCore.new(s.registry)
	check(core.load_chart(s.chart_data) and core.notes.size()==1,fix.name+" required hold retained")
	if core.notes.size()!=1: s.close(); return
	var r=s.registry.service_script("renderer").new(); r.configure(s.registry)
	var n: Dictionary=core.notes[0]; var now:=1.5; var fall:=3.5
	var lights:=core.light_states(now,1.0); var by:={}
	for light in lights: by[light.id]=light
	r.f={"t":now,"fall":fall,"reach":1.0,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest(); r.curve=curve; r.G=r._geo()
	r.TEX={"note":load("res://assets/tex/note.png"),"hold":GradientTexture2D.new()}
	var st: Dictionary=r._land_st(n,by[0]); var capture:=[]
	var geometry: Dictionary=s.registry.get_entry("track_geometry","shape")
	var original: Callable=geometry.get("ribbon_mesh",Callable())
	check(original.is_valid(),fix.name+" production shape mesh provider exists")
	if original.is_valid():
		geometry.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
			var result: Dictionary=original.call(renderer,note,state,a,b,t,f,opacity,fade,thin)
			capture.append(result); return result
	# This is the real production drawing call, including the RenderingServer
	# triangle submission. The recorded data is precisely its provider result.
	r._ribbon(r,n,st,2.,4.,now,fall,1.,0.)
	var data: Dictionary={}
	if not capture.is_empty(): data=capture[0]
	elif r.has_method("ribbon_mesh"): data=r.ribbon_mesh(n,2.,4.,now,1.)
	check(not data.is_empty() and not data.get("indices",[]).is_empty(),fix.name+" actual ribbon emitted triangles")
	if data.is_empty(): r.free(); s.close(); return
	check(data.get("errors",[]).is_empty(),fix.name+" finite in-budget mesh")
	check(data.points.size()==data.plane.size() and data.times.size()==data.points.size(),fix.name+" draw data has exact paired source coordinates")
	var bad_vertices:=0; var bad_triangles:=0; var finite:=true; var mapped:=true
	for i in data.points.size():
		var v: Vector2=data.plane[i]; var p: Vector2=data.points[i]
		finite=finite and p.is_finite() and v.is_finite() and is_finite(float(data.times[i]))
		mapped=mapped and p.distance_to(Vector2(r.G.x_of(v.x,v.y),r.G.y_of(v.y)))<.002
		# Raster polygons are closed; a topology cut can belong to either
		# incident face although judgement uses a half-open time convention.
		var tau: float=data.times[i]
		if not inside(r,n,v.x,tau) and not inside(r,n,v.x,tau-0.00000002) and not inside(r,n,v.x,tau+0.00000002): bad_vertices+=1
	for j in range(0,data.indices.size(),3):
		var a: Vector2=data.plane[data.indices[j]]; var b: Vector2=data.plane[data.indices[j+1]]; var c: Vector2=data.plane[data.indices[j+2]]
		var bad:=false
		for w in [Vector3(1,1,1)/3.,Vector3(.1,.1,.8),Vector3(.1,.8,.1),Vector3(.8,.1,.1)]:
			var v: Vector2=a*w.x+b*w.y+c*w.z
			if not inside(r,n,v.x,projected_time(r,v.y)): bad=true
		if bad: bad_triangles+=1
	check(finite,fix.name+" no NaN/Inf")
	check(mapped,fix.name+" actual vertices use curved-field mapping")
	check(bad_vertices==0,fix.name+" all vertices inside each row's real visual sections")
	check(bad_triangles==0,fix.name+" triangle interiors never bridge a gap")
	if fix.name=="hole_between_old_rows":
		var intersection_area:=0.0
		for j in range(0,data.indices.size(),3):
			var triangle:=PackedVector2Array()
			for k in 3:
				var ix: int=data.indices[j+k]; triangle.append(Vector2(data.plane[ix].x,data.times[ix]))
			for poly in Geometry2D.intersect_polygons(triangle,PackedVector2Array([Vector2(.4,2.0321),Vector2(.6,2.0321),Vector2(.6,2.0339),Vector2(.4,2.0339)])):
				intersection_area+=polygon_area(poly)
		check(intersection_area<0.0000001,"exact triangle intersection catches sub-row hole, area="+str(intersection_area))
	# Exercise the actual hold planner (head/body/tail), not only the mesh entry.
	capture.clear(); r._plan_notes()
	check(not r._nd_holds.is_empty(),fix.name+" actual note planner schedules body")
	for draw in r._nd_holds: draw.call(r)
	check(not capture.is_empty(),fix.name+" actual scheduled body uses geometry provider")
	check(r._nd_notes.size()==2,fix.name+" visible head and tail emitted")
	var caps_inside:=true
	for d in r._nd_notes:
		var tau:=projected_time(r,float(d[5])); var spans: Array=state_at(r,n,tau).get("sections",[])
		var contained:=false
		for span in spans:
			var lo: float=r.G.x_of(float(span[0]),float(d[5])); var hi: float=r.G.x_of(float(span[1]),float(d[5]))
			if float(d[0])-float(d[2])*.5>=lo-.002 and float(d[0])+float(d[2])*.5<=hi+.002: contained=true
		if not contained: caps_inside=false
	check(caps_inside,fix.name+" head and tail widths use their own actual sections")
	if fix.name=="plain_rectangle" and original.is_valid():
		var bad: Dictionary=original.call(r,n,st,2.,4.,NAN,fall,1.,0.,1.)
		check(not bad.errors.is_empty() and bad.indices.is_empty(),"non-finite frame rejected before draw")
		bad=original.call(r,n,st,2.,2.,now,fall,1.,0.,1.)
		check(bad.errors.is_empty() and bad.indices.is_empty(),"degenerate duration emits no triangles")
		r.f.fall=0.0000000001
		bad=original.call(r,n,st,2.,4.,now,r.f.fall,1.,0.,1.)
		check(not bad.errors.is_empty() and bad.indices.is_empty() and bad.points.is_empty(),"cell budget rejects before loops and returns no partial mesh")
		capture.clear(); n.erase("_ribbon_warning")
		r._ribbon(r,n,st,2.,4.,now,r.f.fall,1.,0.)
		check(n.get("_ribbon_warning",false) and not capture.is_empty() and capture[0].indices.is_empty(),"actual draw visibly diagnoses budget rejection once")
		r.f.fall=fall
	if mode=="neutral" and original.is_valid():
		var baseline:=BuiltinRendererRuntime.new(); baseline.configure(s.registry); baseline.f=r.f; baseline.G=r.G; baseline.S=r.S; baseline.TEX=r.TEX; baseline.curve=r.curve
		var baseline_data: Dictionary=original.call(baseline,n,st,2.,4.,now,fall,1.,0.,1.)
		check(data==baseline_data,fix.name+" explicit neutral SV primitive data bit-exact to standard shape renderer")
		baseline._plan_notes()
		check(r._nd_notes==baseline._nd_notes,fix.name+" neutral head and tail primitives bit-exact")
		baseline.free()
	core.playing=true; core.autoplay=true
	for i in int(ceil(core.end_time*240))+1: core.update(i/240.0)
	check(core.stats.MISS==0 and core.stats.score==1010000,fix.name+" actual hold autoplay full score")
	print("HOLD ",mode," / ",fix.name,": vertices=",data.points.size()," bad_vertices=",bad_vertices," triangles=",data.indices.size()/3," bad_triangles=",bad_triangles," score=",core.stats.score)
	r.free(); s.close()
