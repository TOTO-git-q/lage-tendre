## Recovery revision: every result/log is newly produced, never reconstructed.
## Inspect production mesh data, real _ribbon submission and real draw callbacks.
extends SceneTree
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Painter=preload("res://plugins/builtin/shape_tracks/render.gd")
var checks:=0
var failures:=0
var cases:=0
var songs_root:=""
var quick:=false
var worst_distance:=0.0
var worst_horizontal:=0.0
class DrawProbe extends Node2D:
	var renderer
	var calls:=0
	func _draw()->void:
		Painter.surfaces(renderer,self);Painter.edges(renderer,self);calls+=1
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func polygon(nodes:Array)->Dictionary:
	return {"nodes":nodes,"segs":[["linear"],["linear"],["linear"],["linear"]]}
func fixture(config:Dictionary)->Dictionary:
	var shape:=polygon([[.1,1.],[.9,1.],[1.3,5.],[.5,5.]])
	shape.holes=[polygon([[.41,1.1],[.61,1.1],[.99,4.9],[.79,4.9]])]
	return {"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"},{"id":"fall_speed","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[shape]}],"track_speeds":[{"id":0,"speed":config.get("speed",1.)}],"sv":config.get("sv",[]),"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":.47,"motion":{"type":"straight"}}]}
func make_renderer(session:SongPluginSession,core:GameCore,now:float,fall:float,curve:String):
	var r=session.registry.service_script("renderer").new();r.configure(session.registry)
	var lights:=core.light_states(now,1.);var by:={}
	for light in lights:by[light.id]=light
	r.f={"t":now,"fall":fall,"reach":1.,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest();r.curve=curve;r.G=r._geo();r.TEX={"note":load("res://assets/tex/note.png"),"hold":GradientTexture2D.new(),"line":load("res://assets/tex/line.png")};return r
func inverse_s(r,y:float)->float:
	var lo:float=r.s_of_p(0.);var hi:=1.25
	for i in 48:
		var mid:=(lo+hi)*.5
		if r.G.y_of(mid)<y:lo=mid
		else:hi=mid
	return (lo+hi)*.5
func progress_s(r,s:float)->float:
	return (s-BuiltinRenderData.S0)/(1.-BuiltinRenderData.S0) if r.curve=="linear" else 1.-(1./s-1.)/BuiltinRenderData.PK if s<=1. else 1.+(s-1.)/BuiltinRenderData.PK
func true_distance2(r,prepared:Dictionary,tau:float,p:Vector2)->float:
	var s:float=r.s_of_p(r.visual_progress(0,tau));var y:float=r.G.y_of(s);var best:=INF
	for span in Geometry.sections(prepared,tau):
		var x0:float=r.G.x_of(span[0],s);var x1:float=r.G.x_of(span[1],s)
		var dx:float=float(p.x)-clampf(float(p.x),x0,x1);var dy:float=float(p.y)-y
		best=minf(best,dx*dx+dy*dy)
	return best
func distance_upper(r,prepared:Dictionary,point:Vector2,tau:float,raw:float)->float:
	if raw<=.02:return raw
	# Every candidate is on an actual filled slice with its own real projected y.
	# A minimum over these points is a valid upper bound, not an exact global min.
	var best:=raw*raw;var first:=maxf(float(r.f.t),float(prepared.lo));var last:=minf(float(prepared.hi)-1e-9,r.visual_time(0,0.))
	var times:=[first,last,clampf(tau,first,last)]
	for i in 17:times.append(lerpf(first,last,float(i)/16.))
	for d in [-.000001,-.0000001,.0000001,.000001]:times.append(clampf(tau+d,first,last))
	# Derive oracle sampling knots from the unchanged compiled input profile,
	# not the new production cut API, so before/after use identical truth samples.
	var events:Array=r.f.chart.get("_fall_profile",{}).get("events",[])
	for i in events.size():
		var event:Dictionary=events[i];var a:=float(event.t);var b:=a+float(event.dur)
		if i+1<events.size():b=minf(b,float(events[i+1].t))
		for value in [a,b,a+float(event.dur)*.5]:
			if value>=first and value<=last:times.append(value)
	times.sort()
	var selected:=0
	for i in times.size():
		var value:=true_distance2(r,prepared,times[i],point)
		if value<best:best=value;selected=i
	var lo:float=times[maxi(0,selected-1)];var hi:float=times[mini(times.size()-1,selected+1)]
	for i in 24:
		var a:=lerpf(lo,hi,.3819660112501051);var b:=lerpf(lo,hi,.6180339887498949)
		var da:=true_distance2(r,prepared,a,point);var db:=true_distance2(r,prepared,b,point)
		best=minf(best,minf(da,db))
		if da<db:hi=b
		else:lo=a
	return sqrt(best)
func inspect(r,prepared:Dictionary,data:Dictionary,label:String)->void:
	check(data.get("errors",[]).is_empty() and not data.get("indices",[]).is_empty(),label+" nonempty in-budget production mesh")
	var cache:={};var bad:=0;var worst:=0.;var horizontal:=0.;var finite:=true
	for p in data.get("points",[]):finite=finite and p.is_finite()
	for i in range(0,data.get("indices",[]).size(),3):
		var a:Vector2=data.points[data.indices[i]];var b:Vector2=data.points[data.indices[i+1]];var c:Vector2=data.points[data.indices[i+2]]
		for weight in [Vector3(1,1,1)/3.,Vector3(.5,.5,0),Vector3(.5,0,.5),Vector3(0,.5,.5),Vector3(.1,.1,.8),Vector3(.1,.8,.1),Vector3(.8,.1,.1)]:
			var point:Vector2=a*weight.x+b*weight.y+c*weight.z
			if not cache.has(point.y):
				var s:=inverse_s(r,point.y);var tau:float=r.visual_time(0,progress_s(r,s));var spans:=[]
				for span in Geometry.sections(prepared,clampf(tau,prepared.lo+1e-9,prepared.hi-1e-9)):
					spans.append([r.G.x_of(span[0],s),r.G.x_of(span[1],s)])
				cache[point.y]={"tau":tau,"spans":spans}
			var row:Dictionary=cache[point.y];var raw:=INF
			for span in row.spans:raw=minf(raw,absf(float(point.x)-clampf(float(point.x),span[0],span[1])))
			var distance:=distance_upper(r,prepared,point,float(row.tau),raw)
			worst=maxf(worst,distance);horizontal=maxf(horizontal,raw)
			if distance>.25:bad+=1
	check(finite,label+" every submitted point finite")
	check(bad==0,label+" sampled true-slice 2D upper bound <= .25 logical px")
	worst_distance=maxf(worst_distance,worst);worst_horizontal=maxf(worst_horizontal,horizontal)
	print("PROJECTED ",label," vertices=",data.points.size()," triangles=",data.indices.size()/3," outside_samples=",bad," distance_upper_logical_px=",worst," raw_horizontal_logical_px=",horizontal)
func draw_real(r,label:String)->void:
	var canvas:=DrawProbe.new();canvas.renderer=r;root.add_child(canvas)
	await process_frame;RenderingServer.force_draw(false);await process_frame
	check(canvas.calls>0,label+" actual surfaces/edges DrawingServer context invoked")
	canvas.free()
func run_case(config:Dictionary,curve:String)->void:
	cases+=1;var label:String=config.name+"/"+curve
	var folder:=ProjectSettings.globalize_path("user://projection-recovery");check(DirAccess.make_dir_recursive_absolute(folder)==OK,label+" writable fixture")
	var session:=SongPluginSession.new();var report:=session.prepare(folder,fixture(config),label)
	check(report.errors.is_empty() and not report.requires_trust,label+" built-in prepare")
	if not report.errors.is_empty():session.close();return
	check(session.open().errors.is_empty(),label+" selected scope opens")
	var core:=GameCore.new(session.registry);check(core.load_chart(session.chart_data),label+" chart loaded")
	var r=make_renderer(session,core,3.1,3.5,curve);var prepared:Dictionary=core.tl[0][0].shape
	var surface:=Painter.mesh(r,prepared);inspect(r,prepared,surface,label+" surface")
	check(surface==Painter.mesh(r,prepared),label+" repeated real surface planner data identical")
	var n:Dictionary=core.notes[0];var captured:=[];var provider:Dictionary=session.registry.get_entry("track_geometry","shape");var real:Callable=provider.ribbon_mesh
	provider.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
		var data:Dictionary=real.call(renderer,note,state,a,b,t,f,opacity,fade,thin);captured.append(data);return data
	r._ribbon(r,n,r._land_st(n,r._light_at(core.tl[0],2.)),3.1,4.,3.1,3.5,1.,0.)
	check(captured.size()==1,label+" actual _ribbon uses registered production provider")
	if captured.size()==1:inspect(r,prepared,captured[0],label+" hold")
	if config.name=="neutral":
		var baseline:=BuiltinRendererRuntime.new();baseline.configure(session.registry);baseline.f=r.f;baseline.G=r.G;baseline.S=r.S;baseline.curve=curve;baseline.TEX=r.TEX
		check(surface==Painter.mesh(baseline,prepared),label+" neutral surface data exactly legacy")
		if captured.size()==1:check(captured[0]==real.call(baseline,n,{},3.1,4.,3.1,3.5,1.,0.,1.),label+" neutral body data exactly legacy")
		baseline.free()
	var saved:float=r.f.t;r.f.t=2.;check(r.visual_progress(0,2.)==1.,label+" exact head arrival");r.f.t=4.;check(r.visual_progress(0,4.)==1.,label+" exact tail arrival");r.f.t=saved
	await draw_real(r,label)
	core.playing=true;core.autoplay=true
	for i in int(ceil(core.end_time*240))+1:core.update(i/240.)
	check(core.stats.MISS==0 and core.stats.score==1010000,label+" actual GameCore hold autoplay full score")
	r.free();session.close()
func _init()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--songs-root="):songs_root=arg.substr(13)
		if arg=="--quick":quick=true
	call_deferred("run")
func run()->void:
	KB.set_layout("ansi")
	var configs:=[{"name":"step","sv":[{"t":0.,"speed":8.},{"t":3.25,"speed":.05}]}]
	if not quick:
		configs.append_array([{"name":"neutral"},{"name":"positive","speed":1.2},{"name":"overlap","sv":[{"t":0.,"speed":2.},{"t":2.8,"speed":.05,"dur":1.,"ease":"inout"},{"t":3.25,"speed":8.,"dur":.3,"ease":"out"},{"t":3.25,"speed":.5,"dur":.7,"ease":"in"}]}])
		for ease in SU.EASES:configs.append({"name":"ramp-"+ease,"sv":[{"t":0.,"speed":8.},{"t":3.1,"speed":.05,"dur":.3,"ease":ease}]})
	for curve in ["linear","deemo"]:
		for config in configs:await run_case(config,curve)
	print("SCROLL PROJECTION RECOVERY: ",checks," checks, ",failures," failures; cases=",cases," max_distance_upper_logical_px=",worst_distance," max_raw_horizontal_logical_px=",worst_horizontal)
	quit(0 if failures==0 else 1)
