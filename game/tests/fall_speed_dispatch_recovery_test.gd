## Newly authored recovery coverage for all three P5 shape-hold delegation sites.
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func missing_callbacks(r,n:Dictionary,st:Dictionary,geometry:Dictionary,plans:Array,meshes:Array,mode:String)->void:
	var saved_plan:Callable=geometry.hold_plan;var saved_mesh:Callable=geometry.ribbon_mesh
	geometry.erase("hold_plan");geometry.erase("ribbon_mesh");plans.clear();meshes.clear();r._nd_notes.clear();r._nd_holds.clear()
	r._plan_hold(n,st,1.5,3.5,0.,r.visual_progress(0,2.),r.visual_progress(0,4.))
	check(plans.is_empty() and r._nd_notes.size()==2 and not r._nd_holds.is_empty(),mode+" missing optional planner retains real integrated caps/body")
	for draw in r._nd_holds:draw.call(r)
	check(meshes.is_empty(),mode+" missing optional ribbon uses renderer fallback without stale dispatch")
	var data:Dictionary=r.ribbon_mesh(n,2.,4.,1.5,1.)
	var same_clock:bool=not data.indices.is_empty();var nonlinear:=false
	for i in data.times.size():
		var tau:=float(data.times[i]);var p:float=r.visual_progress(0,tau)
		same_clock=same_clock and data.points[i].is_finite() and absf(float(data.plane[i].y)-r.s_of_p(p))<.000001
		nonlinear=nonlinear or absf(p-(1.-(tau-1.5)/3.5))>.001
	check(same_clock,mode+" missing callback fallback mesh preserves every integrated row")
	check(nonlinear,mode+" missing callback cannot silently use linear clock")
	geometry.hold_plan=saved_plan;geometry.ribbon_mesh=saved_mesh
func run_case(mode:String)->void:
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"},{"id":"fall_speed","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[{"nodes":[[.1,1.],[.9,1.],[.9,5.],[.1,5.]],"segs":[["linear"],["linear"],["linear"],["linear"]]}]}],"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":.5,"motion":{"type":"straight"}}],"track_speeds":[{"id":0,"speed":1. if mode=="neutral" else 1.2}]}
	if mode=="ramp":raw.sv=[{"t":1.,"speed":.5,"dur":1.5,"ease":"inout"},{"t":3.,"speed":1.5,"dur":1.,"ease":"out"}]
	var folder:=ProjectSettings.globalize_path("user://dispatch-recovery");check(DirAccess.make_dir_recursive_absolute(folder)==OK,mode+" writable fixture")
	var session:=SongPluginSession.new();var report:=session.prepare(folder,raw,"dispatch-"+mode)
	check(report.errors.is_empty() and not report.requires_trust,mode+" prepare built-in scope")
	if not report.errors.is_empty():session.close();return
	check(session.open().errors.is_empty(),mode+" scope opens")
	var core:=GameCore.new(session.registry);check(core.load_chart(session.chart_data) and core.notes.size()==1,mode+" actual core note retained")
	var n:Dictionary=core.notes[0];var r=session.registry.service_script("renderer").new();r.configure(session.registry)
	var lights:=core.light_states(1.5,1.);var by:={}
	for light in lights:by[light.id]=light
	r.f={"t":1.5,"fall":3.5,"reach":1.,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest();r.curve="deemo";r.G=r._geo();r.TEX={"note":load("res://assets/tex/note.png"),"hold":GradientTexture2D.new()}
	var geometry:Dictionary=session.registry.get_entry("track_geometry","shape")
	var original_plan:Callable=geometry.hold_plan;var original_mesh:Callable=geometry.ribbon_mesh;var plans:=[];var meshes:=[]
	geometry.hold_plan=func(renderer,note,state,t,fall,pmin,phead,ptail):
		plans.append([note.t,t,fall,phead,ptail]);original_plan.call(renderer,note,state,t,fall,pmin,phead,ptail)
	geometry.ribbon_mesh=func(renderer,note,state,a,b,t,fall,alpha,fade,thin):
		var data:Dictionary=original_mesh.call(renderer,note,state,a,b,t,fall,alpha,fade,thin);meshes.append({"times":[a,b,t,fall],"data":data});return data
	var st:Dictionary=r._land_st(n,by[0]);var head:float=r.visual_progress(0,2.);var tail:float=r.visual_progress(0,4.)
	r._plan_hold(n,st,1.5,3.5,0.,head,tail)
	check(plans.size()==1 and r._nd_notes.size()==2 and not r._nd_holds.is_empty(),mode+" real hold planner delegates once and emits caps/body")
	for draw in r._nd_holds:draw.call(r)
	check(meshes.size()==1 and not meshes[0].data.indices.is_empty() and meshes[0].data.errors.is_empty(),mode+" planned body uses actual registered mesh")
	meshes.clear();r._ribbon(r,n,st,2.,4.,1.5,3.5,1.,0.)
	check(meshes.size()==1 and meshes[0].times==[2.,4.,1.5,3.5],mode+" actual _ribbon delegates unchanged arguments")
	check(not meshes[0].data.indices.is_empty() and meshes[0].data.errors.is_empty(),mode+" actual RenderingServer body nonempty")
	var actual:Dictionary=meshes[0].data;meshes.clear()
	var direct:Dictionary=r.ribbon_mesh(n,2.,4.,1.5,1.)
	check(meshes.size()==1 and direct==actual,mode+" public ribbon_mesh delegates and returns identical primitives")
	check(r.uses_integrated_scroll()==(mode!="neutral"),mode+" neutral and integrated modes exercised")
	if mode!="neutral":missing_callbacks(r,n,st,geometry,plans,meshes,mode)
	core.playing=true;core.autoplay=true
	for i in int(ceil(core.end_time*240))+1:core.update(i/240.)
	check(core.stats.MISS==0 and core.stats.score==1010000,mode+" full-score real hold judgement unchanged")
	print("DISPATCH ",mode," vertices=",actual.points.size()," triangles=",actual.indices.size()/3," score=",core.stats.score)
	r.free();session.close()
func _init()->void:
	KB.set_layout("ansi")
	for mode in ["neutral","positive","ramp"]:run_case(mode)
	check(PluginRegistry.standard().manifests.size()==4,"standard catalog still four")
	print("FALL SPEED DISPATCH RECOVERY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
