## Actual submitted triangle scanlines against each true moving shape slice.
extends SceneTree
const Hold=preload("res://plugins/builtin/shape_tracks/hold.gd")
var failures:=0
var cases:=0
func rect(x0:float,x1:float,t0:float,t1:float)->Dictionary:
	return {"nodes":[[x0,t0],[x1,t0],[x1,t1],[x0,t1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func run_case(label:String,shapes:Array,path:Array,cuts:Array,ease:String,curve:String)->void:
	cases+=1
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":shapes}],"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":.25,"path":path,"motion":{"type":"horizontal","x0":.1,"begin":0.,"end":1.,"ease":ease}}]}
	var folder:=ProjectSettings.globalize_path("user://motion-target-fixture");DirAccess.make_dir_recursive_absolute(folder)
	var session:=SongPluginSession.new();var report:=session.prepare(folder,raw,"target-probe")
	if not report.errors.is_empty() or not session.open().errors.is_empty():printerr("FIXTURE ",report);failures+=1;return
	var core:=GameCore.new(session.registry);core.load_chart(session.chart_data)
	var r=session.registry.service_script("renderer").new();r.configure(session.registry)
	r.f={"t":1.5,"fall":3.5,"reach":1.,"tl":core.tl,"chart":core.chart,"play":true};r.S=StageFx.rest();r.curve=curve;r.G=r._geo();r.TEX={"hold":GradientTexture2D.new()}
	var n:Dictionary=core.notes[0];var capture:=[];var provider:Dictionary=session.registry.get_entry("track_geometry","shape");var real:Callable=provider.ribbon_mesh
	provider.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
		var data:Dictionary=real.call(renderer,note,state,a,b,t,f,opacity,fade,thin);capture.append(data);return data
	r._ribbon(r,n,r._land_st(n,r._light_at(core.tl[0],2.)),2.,4.,1.5,3.5,1.,0.)
	if capture.size()!=1 or capture[0].indices.is_empty() or not capture[0].errors.is_empty():printerr("MESH ",label," ",capture);failures+=1;r.free();session.close();return
	var data:Dictionary=capture[0]
	for knot in path:
		var tau:=2.+float(knot[0])
		if tau<=2. or tau>=4.:continue
		var found:=false
		for value in data.times:
			if absf(float(value)-tau)<1e-10:found=true
		if not found:printerr("REQUIRED PATH KNOT MISSING ",label," ",tau);failures+=1
	var bad:=0;var worst:=0.;var geometric_worst:=0.
	for tau in cuts:
		var point:=n.duplicate();point.t=float(tau);point.u=r._path_at(n,float(tau)-2.)[0]
		var state:Dictionary=r._land_st(point,r._light_at(core.tl[0],float(tau)))
		if not state.alive:printerr("REQUIRED SLICE MISSING ",tau);failures+=1;continue
		var near_spans:=[]
		# Only sub-float32-row tolerance: every comparison slice is a true
		# filled section, so this is an upper bound on 2-D distance, not a skip.
		for delta in [-.0000001,0.,.0000001]:
			var near:=point.duplicate();near.t=float(tau)+delta;near.u=r._path_at(n,float(near.t)-2.)[0]
			var near_state:Dictionary=r._land_st(near,r._light_at(core.tl[0],float(near.t)))
			var near_s:float=r.s_of_p(1.-(float(near.t)-1.5)/3.5)
			for sec in near_state.get("sections",[]):near_spans.append([r.G.x_of(sec[0],near_s),r.G.x_of(sec[1],near_s),r.G.y_of(near_s)])
		var s:float=r.s_of_p(1.-(float(tau)-1.5)/3.5);var y:float=r.G.y_of(s);var spans:=[]
		for sec in state.sections:spans.append([r.G.x_of(sec[0],s),r.G.x_of(sec[1],s)])
		for i in range(0,data.indices.size(),3):
			var tri:=[data.points[data.indices[i]],data.points[data.indices[i+1]],data.points[data.indices[i+2]]];var xs:=[]
			for j in 3:
				var a:Vector2=tri[j];var b:Vector2=tri[(j+1)%3]
				if a.y==b.y or y<minf(a.y,b.y) or y>maxf(a.y,b.y):continue
				xs.append(lerpf(a.x,b.x,(y-a.y)/(b.y-a.y)))
			if xs.size()<2:continue
			xs.sort();var width:float=xs[-1]-xs[0];var inside:=0.
			for sec in spans:inside+=maxf(0.,minf(xs[-1],sec[1])-maxf(xs[0],sec[0]))
			var error:=maxf(0.,width-inside);worst=maxf(worst,error)
			var distance:=0.
			for q in [0.,.25,.5,.75,1.]:
				var x:=lerpf(xs[0],xs[-1],q);var nearest:=INF
				for sec in near_spans:
					var dx:float=x-clampf(x,sec[0],sec[1]);var dy:float=y-sec[2]
					nearest=minf(nearest,sqrt(dx*dx+dy*dy))
				distance=maxf(distance,nearest)
			geometric_worst=maxf(geometric_worst,distance)
			if distance>.25:bad+=1
	print("VARIABLE TARGET ",label,"/",ease,"/",curve," triangles=",data.indices.size()/3," outside_scanlines=",bad," raw_overlap_logical_px=",worst," max_2d_logical_px=",geometric_worst)
	if bad>0:failures+=1
	r.free();session.close()
func _init()->void:
	KB.set_layout("ansi")
	var work:={"steps":Hold.MAX_CELLS,"error":""};var out:=[]
	var refused:bool=not Hold._refine(null,{}, {},0.,1.,out,work)
	if not refused or work.error.is_empty() or not out.is_empty():failures+=1;printerr("REFINEMENT BUDGET FAILURE")
	print("REFINEMENT BUDGET explicit_error=",not work.error.is_empty()," no_partial_rows=",out.is_empty())
	var fast:={"nodes":[[.1,1.],[.4,1.],[.4,2.121],[.95,2.123],[.95,5.],[.65,5.],[.65,2.123],[.1,2.121]],"segs":[["linear"],["linear"],["linear"],["linear"],["linear"],["linear"],["linear"],["linear"]]}
	var shapes:=[rect(.1,.35,1.,5.),rect(.65,.9,1.,5.)]
	var path:=[[0.,.1,1.],[.121,.1,1.],[.123,.9,1.],[.125,.1,1.],[2.,.1,1.]]
	for curve in ["linear","deemo"]:
		for ease in SU.EASES:
			run_case("fast_slant",[fast],[],[2.1211,2.1215,2.122,2.1225,2.1229],ease,curve)
			run_case("short_path_turn",shapes,path,[2.1215,2.121999,2.122,2.122001,2.1225,2.123,2.1235,2.123999,2.124,2.124001,2.1245],ease,curve)
	print("VARIABLE TARGET cases=",cases," failures=",failures);quit(0 if failures==0 else 1)
