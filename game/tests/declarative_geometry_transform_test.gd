## P4 composition follow-on. Production declarative motion, geometry dispatch,
## cap primitives and physical judgement; --body also checks the partner hold mesh.
extends SceneTree
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
var checks:=0
var failures:=0
var include_body:=false
var include_speed:=false
var folder:=""
var definitions:={
	"shift":{"x":"x + 0.4"},
	"widen":{"w":"w * 2"},
	"shrink":{"w":"w * 0.25"},
	"zero":{"w":"0"},
	"alpha_only":{"alpha":"alpha * 0.5"},
	"combined":{"x":"x - 0.2","w":"w * 0.5","alpha":"0.25"},
	"animated":{"x":"x + 0.2 * (1 - progress)","w":"w * (0.5 + 0.5 * progress)","alpha":"0.8"}}
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func near(a: float,b: float) -> bool: return absf(a-b)<0.000001
func same_sections(a: Array,b: Array) -> bool:
	if a.size()!=b.size(): return false
	for i in a.size():
		if a[i].size()!=2 or b[i].size()!=2 or not near(float(a[i][0]),float(b[i][0])) or not near(float(a[i][1]),float(b[i][1])): return false
	return true
func rect(x0: float,x1: float) -> Dictionary:
	return {"nodes":[[x0,1.],[x1,1.],[x1,5.],[x0,5.]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func fixtures() -> Array:
	var hole:=rect(.1,.9); hole["holes"]=[rect(.4,.6)]
	return [{"name":"rectangle","shapes":[rect(.1,.3)],"u":.5},
		{"name":"hole","shapes":[hole],"u":.2},
		{"name":"disconnected","shapes":[rect(.1,.3),rect(.7,.9)],"u":.2}]
func write_json(path: String,data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
func provider() -> PluginDeclarative:
	var p:=PluginDeclarative.new(); p.definitions={"motions":definitions.duplicate(true)}
	for id in definitions: p._compile_formulas("motions",id,definitions[id],definitions[id].keys())
	return p
func expected(base: Dictionary,id: String,progress:=1.) -> Dictionary:
	var x:=float(base.x); var w:=float(base.w); var alpha:=float(base.alpha)
	match id:
		"shift": x+=.4
		"widen": w*=2.
		"shrink": w*=.25
		"zero": w=0.
		"alpha_only": alpha*=.5
		"combined": x-=.2; w*=.5; alpha=.25
		"animated": x+=.2*(1.-progress); w*=.5+.5*progress; alpha=.8
	var spans:=[]
	if w>0. and float(base.w)>0.:
		for span in base.sections: spans.append([x+(float(span[0])-float(base.x))*w/float(base.w),x+(float(span[1])-float(base.x))*w/float(base.w)])
	return {"x":x,"w":w,"alpha":alpha,"sections":spans,"alive":base.alive and w>0.}
func raw_for(fix: Dictionary,id: String,speed: bool) -> Dictionary:
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"},{"id":"transform_probe","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":fix.shapes}],"notes":[{"t":2.,"light":0,"u":fix.u,"kind":"hold","dur":2.,"motion":{"type":id}}]}
	if speed:
		raw.plugins.append({"id":"fall_speed","version":"1.0.0"}); raw["track_speeds"]=[{"id":0,"speed":1.2}]
	return raw
func target_at(r,n: Dictionary,id: String,tau: float) -> Dictionary:
	var base:=ChartLib.light_at(r.f.tl[int(n.light)],tau,r.registry)
	var progress: float=r.visual_progress(int(n.light),tau) if r.has_method("visual_progress") else 1.-(tau-float(r.f.t))/float(r.f.fall)
	return expected(base,id,clampf(progress,0.,1.))
func target_for_depth(r,n: Dictionary,id: String,s: float) -> Dictionary:
	var progress: float=(s-BuiltinRenderData.S0)/(1.-BuiltinRenderData.S0)
	var tau: float=r.visual_time(int(n.light),progress) if r.has_method("visual_time") else float(r.f.t)+(1.-progress)*float(r.f.fall)
	return target_at(r,n,id,tau)
func make_frame(core: GameCore,r,now:=1.5) -> void:
	var lights:=core.light_states(now,1.); var by:={}
	for st in lights: by[st.id]=st
	r.f={"t":now,"fall":3.5,"reach":1.,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest(); r.curve="linear"; r.G=r._geo(); r.TEX={"note":load("res://assets/tex/note.png"),"hold":GradientTexture2D.new()}
func run_dispatch_contract() -> void:
	var scope:=PluginRegistry.standard().fork_scope(); var r:=BuiltinRendererRuntime.new(); r.configure(scope)
	r.f={"t":1.5,"fall":3.5}; var p:=provider(); var note:={"light":0,"t":2.,"u":.5,"dur":2.}
	var calls:=[0]
	scope.records.track_geometry["probe"]={"visual_transform":func(state,new_x,new_w):
		calls[0]+=1
		var copy: Dictionary=state.duplicate(true); copy.x=new_x; copy.w=new_w; copy["vendor_transformed"]=true
		copy.sections=[[new_x-new_w*.5,new_x+new_w*.5]]; return copy}
	var source:={"alive":true,"geometry":"probe","x":.2,"w":.2,"alpha":.8,"sections":[[.1,.3]],"vendor_data":{"keep":7}}
	var old:=source.duplicate(true); var out:=p.motion(r,note,source,"shift")
	check(calls[0]==1 and out.get("vendor_transformed",false),"generic core dispatches unknown custom geometry transform")
	check(near(out.x,.6) and near(out.w,.2) and near(out.alpha,.8),"transform callback receives final coordinates")
	check(source==old,"custom callback path leaves original state unchanged")
	out=p.motion(r,note,source,"alpha_only")
	check(calls[0]==1 and near(out.alpha,.4),"alpha-only skips geometry callback")
	out=p.motion(r,note,source,"combined")
	check(calls[0]==2 and near(out.x,0.) and near(out.w,.1) and near(out.alpha,.25),"all formulas use original inputs and alpha survives transform")
	var lane:=source.duplicate(true); lane.geometry="lane"; var lane_before:=lane.duplicate(true)
	scope.records.track_geometry.lane["visual_transform"]=func(_s,_x,_w): calls[0]+=100; return {}
	out=p.motion(r,note,lane,"shift")
	var legacy:=lane.duplicate(true); legacy.x+=.4
	check(out==legacy and lane==lane_before and calls[0]==2,"legacy lane output remains exact and bypasses optional callback")
	scope.records.track_geometry["probe"].erase("visual_transform")
	out=p.motion(r,note,source,"widen")
	legacy=source.duplicate(true); legacy.w*=2.
	check(out==legacy and source==old,"missing optional transform preserves existing generic motion semantics")
	r.free(); scope.dispose()
func run_shape_transform_contract() -> void:
	var source:={"alive":true,"geometry":"shape","x":.5,"w":.8,"alpha":.7,"sections":[[.1,.3],[.4,.6],[.7,.9]],"shape":{"trapezoids":[{"t0":1.,"t1":5.}]},"vendor_data":{"keep":7}}
	var before:=source.duplicate(true)
	var moved:=Geometry.visual_transform(source,1.,1.6)
	check(same_sections(moved.sections,[[.2,.6],[.8,1.2],[1.4,1.8]]),"direct shape callback affine mapping preserves three disconnected intervals")
	check(is_same(moved.shape,source.shape) and moved.alpha==source.alpha and moved.vendor_data==source.vendor_data,"compiled shape stays shared read-only and metadata is preserved")
	check(not is_same(moved.sections,source.sections) and not is_same(moved.sections[0],source.sections[0]),"visual interval arrays are independently owned")
	moved.sections[0][0]=-7.
	check(source==before,"editing returned visual intervals cannot alter original hit geometry")
	var zero:=Geometry.visual_transform(source,.25,0.)
	check(not zero.alive and zero.sections.is_empty() and zero.x==.25 and zero.w==0.,"direct zero width collapses invisibly without division")
	var dead:=source.duplicate(true); dead.alive=false
	check(not Geometry.visual_transform(dead,.5,1.).alive,"visual transform never revives dead geometry")
	var degenerate:=source.duplicate(true); degenerate.w=0.
	var empty:=Geometry.visual_transform(degenerate,.5,1.)
	check(not empty.alive and empty.sections.is_empty(),"zero source width cannot divide or fabricate intervals")
	for x in [NAN,INF,-INF]:
		var hidden:=Geometry.visual_transform(source,x,1.)
		check(not hidden.alive and hidden.sections.is_empty() and is_finite(float(hidden.x)) and is_finite(float(hidden.w)),"invalid target x is invisible with finite fallback")
	for width in [NAN,INF,-INF,-1.]:
		var hidden:=Geometry.visual_transform(source,.5,width)
		check(not hidden.alive and hidden.sections.is_empty() and is_finite(float(hidden.x)) and is_finite(float(hidden.w)),"invalid target width is invisible with finite fallback")
	for key in ["x","w"]:
		var invalid:=source.duplicate(true); invalid[key]=NAN
		var hidden:=Geometry.visual_transform(invalid,.5,1.)
		check(not hidden.alive and hidden.sections.is_empty() and is_finite(float(hidden.x)) and is_finite(float(hidden.w)),"invalid source envelope is invisible with finite fallback")
	var tiny:={"alive":true,"x":0.,"w":1e-300,"sections":[[-5e-301,5e-301]]}
	var expanded:=Geometry.visual_transform(tiny,.5,4.)
	check(expanded.alive and same_sections(expanded.sections,[[-1.5,2.5]]),"normalize before scaling avoids overflow for tiny positive envelopes")
	check(source==before,"all callback boundary probes leave original state untouched")
func run_fixture(fix: Dictionary,id: String,speed: bool) -> void:
	var label:="%s/%s/%s" % [fix.name,id,"sv" if speed else "standard"]
	var session:=SongPluginSession.new(); var raw:=raw_for(fix,id,speed)
	var report:=session.prepare(folder,raw,label)
	check(report.errors.is_empty() and not report.requires_trust,label+" declarative prepare needs no script approval")
	if not report.errors.is_empty(): printerr(report.errors); session.close(); return
	var opened:=session.open(); check(opened.errors.is_empty(),label+" opens real selected scope")
	if not opened.errors.is_empty(): printerr(opened.errors); session.close(); return
	check(session.identity.has("fall_speed@1.0.0")==speed and session.registry.manifests.size()==(8 if speed else 7),label+" only explicit optional plugin scope is enabled")
	var core:=GameCore.new(session.registry); check(core.load_chart(session.chart_data) and core.notes.size()==1,label+" hold normalizes")
	if core.notes.size()!=1: session.close(); return
	var r=session.registry.service_script("renderer").new(); r.configure(session.registry); make_frame(core,r)
	var n: Dictionary=core.notes[0]; var note_before:=n.duplicate(true)
	var base:=ChartLib.light_at(core.tl[0],float(n.t),session.registry); var original:=base.duplicate(true)
	var visual: Dictionary=r._land_st(n,base); var target:=target_at(r,n,id,float(n.t))
	check(near(visual.x,target.x) and near(visual.w,target.w) and near(visual.alpha,target.alpha),label+" visual envelope and alpha")
	check(same_sections(visual.get("sections",[]),target.sections),label+" every filled interval follows affine envelope")
	check(visual.alive==target.alive,label+" zero width has empty inactive geometry")
	check(base==original and n==note_before,label+" original state and note remain unchanged")
	check(ChartLib.light_at(core.tl[0],float(n.t),session.registry)==original,label+" compiled geometry remains unchanged")
	check(visual.get("shape",{}).get("trapezoids",[])==base.shape.trapezoids,label+" transform never rewrites compiled trapezoids")
	if id!="zero":
		var x:=Geometry.note_x(visual,float(n.u)); var expected_state:=visual.duplicate(true); expected_state.sections=target.sections
		check(near(x,Geometry.note_x(expected_state,float(n.u))),label+" note_x uses transformed filled intervals")
		var finite:=true
		for span in visual.sections: finite=finite and is_finite(float(span[0])) and is_finite(float(span[1])) and span[0]<=span[1]
		check(finite,label+" transformed sections finite and ordered")
	r._plan_notes()
	if id=="zero":
		check(r._nd_notes.is_empty() and r._nd_holds.is_empty(),label+" zero width schedules no cap or body")
	else:
		check(r._nd_notes.size()==2 and r._nd_holds.size()==1,label+" real planner produces head/body/tail")
		var caps_inside:=true
		for cap in r._nd_notes:
			var contained:=false
			var cap_target:=target_for_depth(r,n,id,float(cap[5]))
			for span in cap_target.sections:
				var lo: float=r.G.x_of(float(span[0]),float(cap[5])); var hi: float=r.G.x_of(float(span[1]),float(cap[5]))
				if float(cap[0])-float(cap[2])*.5>=lo-.002 and float(cap[0])+float(cap[2])*.5<=hi+.002: contained=true
			if not contained: caps_inside=false
		check(caps_inside,label+" actual cap quads stay inside transformed sections")
	if include_body: inspect_body(r,session.registry,n,visual,target,label,id)
	# This is the original judgement engine. Visual transforms must not reach it.
	var reference:=GameCore.new(session.registry); var plain:=raw.duplicate(true); plain.notes[0].motion={"type":"straight"}
	check(reference.load_chart(plain),label+" physical control loads")
	core.playing=true; core.autoplay=true; reference.playing=true; reference.autoplay=true
	for i in int(ceil(maxf(core.end_time,reference.end_time)*120.))+1:
		core.update(i/120.); reference.update(i/120.)
	check(core.stats==reference.stats and core.hit_log==reference.hit_log,label+" exact stats and hit log equal untransformed control")
	check(core.stats.MISS==0 and core.stats.score==1010000,label+" full-score physical hold remains reachable")
	r.free(); core=null; reference=null; session.close()
func inspect_body(r,scope: PluginRegistry,n: Dictionary,visual: Dictionary,target: Dictionary,label: String,id: String) -> void:
	var geom: Dictionary=scope.get_entry("track_geometry","shape"); var callback: Callable=geom.get("ribbon_mesh",Callable()); var captured:=[]
	check(callback.is_valid(),label+" actual body provider exists")
	if not callback.is_valid(): return
	geom.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
		var data: Dictionary=callback.call(renderer,note,state,a,b,t,f,opacity,fade,thin); captured.append(data); return data
	r._ribbon(r,n,visual,2.,4.,1.5,3.5,1.,0.)
	check(captured.size()==1,label+" actual production ribbon calls provider")
	if captured.is_empty(): return
	var mesh: Dictionary=captured[0]
	check(mesh.get("errors",[]).is_empty(),label+" body returns no errors")
	if id=="zero":
		check(mesh.indices.is_empty() and mesh.points.is_empty(),label+" zero width has no body triangles"); return
	check(not mesh.indices.is_empty(),label+" transformed body is visible")
	var inside:=true; var finite:=true
	for v in mesh.plane:
		finite=finite and v.is_finite(); var found:=false
		var vertex_target:=target_for_depth(r,n,id,float(v.y))
		for span in vertex_target.sections:
			if v.x>=float(span[0])-.00008 and v.x<=float(span[1])+.00008: found=true
		if not found: inside=false
	var valid_indices:=true
	for index in mesh.indices: valid_indices=valid_indices and index>=0 and index<mesh.points.size()
	check(finite and valid_indices,label+" body finite and all indices in range")
	check(inside,label+" body vertices follow transformed filled intervals")
	var triangle_inside:=true
	for i in range(0,mesh.indices.size(),3):
		var a: Vector2=mesh.plane[mesh.indices[i]]; var b: Vector2=mesh.plane[mesh.indices[i+1]]; var c: Vector2=mesh.plane[mesh.indices[i+2]]
		for w in [Vector3(1.,1.,1.)/3.,Vector3(.1,.1,.8),Vector3(.1,.8,.1),Vector3(.8,.1,.1)]:
			var point: Vector2=a*w.x+b*w.y+c*w.z; var x: float=point.x; var found:=false
			var triangle_target:=target_for_depth(r,n,id,float(point.y))
			for span in triangle_target.sections:
				if x>=float(span[0])-.00008 and x<=float(span[1])+.00008: found=true
			if not found: triangle_inside=false
	check(triangle_inside,label+" body triangles never join the transformed hole")
func _init() -> void: call_deferred("run")
func run() -> void:
	KB.set_layout("ansi")
	include_body="--body" in OS.get_cmdline_user_args()
	include_speed="--with-speed" in OS.get_cmdline_user_args()
	if "--expect-packed" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists("res://scripts/core/plugin_declarative.gd.remap") and FileAccess.file_exists("res://plugins/builtin/shape_tracks/geometry.gd.remap"),"external driver resolves actual compiled production helpers")
		check(not FileAccess.file_exists("res://tests/declarative_geometry_transform_test.gd"),"original export preset excludes test source")
	folder=ProjectSettings.globalize_path("user://declarative-transform-fixture")
	var data:={"id":"transform_probe","version":"1.0.0","api":1,"tier":"declarative","title":"Transform probe","author":"Tests","description":"Generated data-only motion fixtures","provides":{"motions":definitions.keys()},"fields":[],"assets":[],"entry":null,"definitions":{"motions":definitions}}
	write_json(folder.path_join("plugins/transform_probe/plugin.json"),data)
	run_dispatch_contract()
	run_shape_transform_contract()
	for fix in fixtures():
		for id in definitions: run_fixture(fix,str(id),false)
	if include_speed:
		for id in definitions: run_fixture(fixtures()[1],str(id),true)
	check(PluginRegistry.standard().manifests.size()==4 and not PluginRegistry.standard().get_entry("track_geometry","lane").has("visual_transform"),"standard base scope unmodified")
	print("DECLARATIVE GEOMETRY ","WITH SV " if include_speed else "P4 ","BODY" if include_body else "STATE/CAPS",": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
