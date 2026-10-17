## Actual visual affine state, cap planner, submitted ribbon and physical controls.
## Self-contained; PCK runs use this external absolute script, no missing fixture skip.
extends SceneTree
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Hold=preload("res://plugins/builtin/shape_tracks/hold.gd")
const Motion=preload("res://plugins/builtin/note_motion/runtime.gd")
class Probe extends RefCounted:
	var registry:PluginRegistry
	var landing:Dictionary
	var f:={"t":1.5,"fall":3.5,"tl":{0:[]}}
	func _light_at(_timeline,_tau)->Dictionary:return landing
const US=[0.49999999999999994,0.5,0.5000000000000001]
var checks:=0
var failures:=0
var cases:=0
var state_only:=false
var section_cache:={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func rect(a:float,b:float)->Dictionary:
	return {"nodes":[[a,1.],[b,1.],[b,5.],[a,5.]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func old_section(state:Dictionary,u:float)->Array:
	var x:float=state.x+(u-.5)*state.w;var best:=[];var distance:=INF
	for section in state.get("sections",[]):
		var d:=absf(x-clampf(x,section[0],section[1]))
		if d<distance:distance=d;best=section
	return best
func contract()->void:
	check(US[0]<US[1] and US[1]<US[2],"exact tie and its adjacent float64 inputs retained")
	var base:={"alive":true,"geometry":"shape","x":.5,"w":.8,"alpha":1.,"sections":[[.1,.4],[.6,.9]]}
	var before:=base.duplicate(true);var bad:=0;var wrong:=0;var bounded:=true;var exact:=true
	for u in US:
		var index:int=base.sections.find(old_section(base,u))
		exact=exact and Geometry.note_section(base,u)==old_section(base,u)
		for scale in [.25,1.,2.]:
			for sign in [-1.,1.]:
				for i in 257:
					var dx:float=sign*float(i)/1280.
					var visual:=Geometry.visual_transform(base,.5+dx,.8*scale)
					if visual.sections.find(Geometry.note_section(visual,u))!=index:bad+=1
					var nested:=Geometry.visual_transform(visual,float(visual.x)-.17,float(visual.w)*.7)
					if nested.sections.find(Geometry.note_section(nested,u))!=index:wrong+=1
					if visual.has("_visual_section_basis"):
						bounded=bounded and visual._visual_section_basis.size()==3 and is_same(visual._visual_section_basis,nested._visual_section_basis) and not is_same(visual._visual_section_basis.sections,base.sections)
					else:bounded=false
	check(bad==0,"direct affine stable nearest section, mismatches="+str(bad))
	check(wrong==0,"chained affine keeps original section basis, mismatches="+str(wrong))
	check(base==before,"affine selection never mutates original physical intervals")
	check(exact,"physical nearest-section formula/order bit-exact to original selector")
	check(bounded,"single owned three-field basis, no state reference or chain growth")
	print("AFFINE CONTRACT direct_mismatches=",bad," chained_mismatches=",wrong)
func dispatch_contract()->void:
	var scope:=PluginRegistry.standard().fork_scope();var probe:=Probe.new();probe.registry=scope
	var base:={"alive":true,"geometry":"probe","x":.5,"w":.8,"alpha":.75,"sections":[[.1,.4],[.6,.9]]}
	probe.landing=base
	var note:={"light":0,"t":2.,"u":.5,"motion":{"type":"horizontal","x0":.2,"ease":"linear"}}
	scope.records.track_geometry["probe"]={"note_x":Geometry.note_x}
	var fallback:=Motion.horizontal(probe,note,base)
	var expected:=base.duplicate(true);var dx:float=(.2-Geometry.note_x(base,.5))*(1.-(1.-(.5)/3.5))
	expected.alpha=1.
	expected.x+=dx
	for span in expected.sections:span[0]+=dx;span[1]+=dx
	check(fallback==expected,"geometry without optional callback retains exact old fallback")
	var called:=[0]
	scope.records.track_geometry.probe.visual_transform=func(state,x,w):called[0]+=1;return Geometry.visual_transform(state,x,w)
	var p:=PluginDeclarative.new();p.definitions={"motions":{"compose":{"x":"x + 0.4","w":"w * 0.5"}}}
	p._compile_formulas("motions","compose",p.definitions.motions.compose,["x","w"])
	var transformed:=p.motion(probe,note,base,"compose")
	probe.landing=transformed
	var final:=Motion.horizontal(probe,note,transformed)
	check(called[0]==2,"declarative then horizontal both use optional generic callback")
	check(final.sections.find(Geometry.note_section(final,.5))==base.sections.find(old_section(base,.5)),"declarative scale/translation then horizontal retain source-selected section")
	check(is_same(transformed.get("_visual_section_basis"),final.get("_visual_section_basis")),"chained provider calls share one minimal source basis")
	var lane:=base.duplicate(true);lane.geometry="lane";probe.landing=lane
	scope.records.track_geometry.lane["visual_transform"]=func(_s,_x,_w):called[0]+=100;return {}
	var lane_out:=Motion.horizontal(probe,note,lane)
	check(called[0]==2 and not lane_out.is_empty(),"lane never invokes optional geometry callback")
	scope.dispose()
func point_state(r,n:Dictionary,tau:float)->Dictionary:
	var point:=n.duplicate();point.t=tau
	return r._land_st(point,r._light_at(r.f.tl[0],tau))
func expected_section(r,n:Dictionary,tau:float)->Array:
	if section_cache.has(tau):return section_cache[tau]
	var base:Dictionary=r._light_at(r.f.tl[0],tau)
	var visual:=point_state(r,n,tau)
	var index:int=base.sections.find(old_section(base,float(n.u)))
	section_cache[tau]=visual.sections[index]
	return section_cache[tau]
func tau_of(r,s:float)->float:
	var p:float=(s-BuiltinRenderData.S0)/(1.-BuiltinRenderData.S0) if r.curve=="linear" else 1.-(1./s-1.)/BuiltinRenderData.PK
	return 1.5+(1.-p)*3.5
func in_selected(r,n:Dictionary,x:float,tau:float)->bool:
	var sec:=expected_section(r,n,tau)
	return x>=float(sec[0])-.00008 and x<=float(sec[1])+.00008
func run_case(u:float,x0:float,curve:String)->void:
	cases+=1;section_cache.clear()
	var label:="u=%.17f x0=%.1f %s" % [u,x0,curve]
	var hole:=rect(.1,.9);hole.holes=[rect(.4,.6)]
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[hole]}],"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":u,"motion":{"type":"horizontal","x0":x0,"ease":"linear"}}]}
	var folder:=ProjectSettings.globalize_path("user://affine-section-fixture")
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,label+" writable fixture")
	var session:=SongPluginSession.new();var report:=session.prepare(folder,raw,"affine-section")
	check(report.errors.is_empty() and not report.requires_trust,label+" selected built-in scope")
	if not report.errors.is_empty():session.close();return
	check(session.open().errors.is_empty(),label+" open")
	var core:=GameCore.new(session.registry);check(core.load_chart(session.chart_data) and core.notes.size()==1,label+" hold loaded")
	if core.notes.size()!=1:session.close();return
	var n:Dictionary=core.notes[0];check(n.u==u,label+" float64 u preserved")
	var r=session.registry.service_script("renderer").new();r.configure(session.registry)
	var lights:=core.light_states(1.5,1.);var by:={}
	for light in lights:by[light.id]=light
	r.f={"t":1.5,"fall":3.5,"reach":1.,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest();r.curve=curve;r.G=r._geo();r.TEX={"note":load("res://assets/tex/note.png"),"hold":GradientTexture2D.new()}
	var bad_states:=0;var physical:=true
	for i in 257:
		var tau:=2.+2.*float(i)/256.
		var base:Dictionary=r._light_at(core.tl[0],tau);var before:=base.duplicate(true)
		var visual:=point_state(r,n,tau);var expected:int=base.sections.find(old_section(base,u))
		if visual.sections.find(Geometry.note_section(visual,u))!=expected:bad_states+=1
		physical=physical and base==before and r._light_at(core.tl[0],tau)==before
	check(bad_states==0,label+" real horizontal section index stable, mismatches="+str(bad_states))
	check(physical,label+" actual physical sections unchanged")
	if state_only:
		print("AFFINE STATE ",label," mismatches=",bad_states);r.free();session.close();return
	var provider:Dictionary=session.registry.get_entry("track_geometry","shape");var original:Callable=provider.ribbon_mesh;var capture:=[]
	provider.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
		var data:Dictionary=original.call(renderer,note,state,a,b,t,f,opacity,fade,thin);capture.append(data);return data
	r._ribbon(r,n,r._land_st(n,by[0]),2.,4.,1.5,3.5,1.,0.)
	check(capture.size()==1,label+" actual RenderingServer submission provider captured")
	if capture.size()!=1:r.free();session.close();return
	var data:Dictionary=capture[0]
	check(data.errors.is_empty() and not data.indices.is_empty(),label+" nonempty in-budget actual body")
	var bad_vertices:=0;var bad_triangles:=0
	for i in data.points.size():
		if not data.points[i].is_finite() or not in_selected(r,n,float(data.plane[i].x),float(data.times[i])):bad_vertices+=1
	for i in range(0,data.indices.size(),3):
		var va:Vector2=data.plane[data.indices[i]];var vb:Vector2=data.plane[data.indices[i+1]];var vc:Vector2=data.plane[data.indices[i+2]]
		for w in [Vector3(1,1,1)/3.,Vector3(.1,.1,.8),Vector3(.1,.8,.1),Vector3(.8,.1,.1)]:
			var p:Vector2=va*w.x+vb*w.y+vc*w.z
			if not in_selected(r,n,p.x,tau_of(r,p.y)):bad_triangles+=1
	check(bad_vertices==0,label+" body vertices in same affine-selected section")
	check(bad_triangles==0,label+" submitted triangle samples stay in selected section without crossing hole")
	capture.clear();r._plan_notes();check(r._nd_notes.size()==2 and not r._nd_holds.is_empty(),label+" real planner emits both caps and body")
	var bad_caps:=0
	for d in r._nd_notes:
		var s:=float(d[5]);var sec:=expected_section(r,n,tau_of(r,s))
		if float(d[0])-float(d[2])*.5<r.G.x_of(float(sec[0]),s)-.002 or float(d[0])+float(d[2])*.5>r.G.x_of(float(sec[1]),s)+.002:bad_caps+=1
	check(bad_caps==0,label+" head and tail use same source-selected section as body")
	for draw in r._nd_holds:draw.call(r)
	check(not capture.is_empty() and not capture[0].indices.is_empty() and capture[0].errors.is_empty(),label+" planned body remains visible")
	core.playing=true;core.autoplay=true
	for i in int(ceil(core.end_time*240))+1:core.update(i/240.)
	check(core.stats.MISS==0 and core.stats.score==1010000,label+" unchanged physical autoplay full score")
	print("AFFINE BODY ",label," vertices=",data.points.size()," triangles=",data.indices.size()/3," state_mismatches=",bad_states," bad_vertices=",bad_vertices," bad_triangles=",bad_triangles," bad_caps=",bad_caps," score=",core.stats.score)
	r.free();session.close()
func _init()->void:
	KB.set_layout("ansi");state_only="--state-only" in OS.get_cmdline_user_args()
	contract();dispatch_contract()
	for curve in ["linear","deemo"]:
		for x0 in [.2,.8]:
			for u in US:run_case(u,x0,curve)
	var out:=[];var budget:={"steps":Hold.MAX_CELLS,"error":""}
	check(not Hold._refine(null,{},{},0.,1.,out,budget) and not budget.error.is_empty() and out.is_empty(),"true refinement work budget still explicitly rejects before work")
	check(PluginRegistry.standard().manifests.size()==4,"standard catalog remains four")
	print("AFFINE SECTION STABILITY: ",checks," checks, ",failures," failures; cases=",cases," state_only=",state_only)
	quit(0 if failures==0 else 1)
