## P4 boundary regressions. Optional P5 modes have no hard P5 script dependency.
extends SceneTree
const Motion=preload("res://plugins/builtin/note_motion/runtime.gd")
var checks:=0
var failures:=0
var mode:="motion"
var folder:=""
var max_screen_error:=0.0
var max_scanline_error:=0.0
const PIXEL_TOLERANCE:=0.25
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func rect(x0:float,x1:float,t0:float,t1:float)->Dictionary:
	return {"nodes":[[x0,t0],[x1,t0],[x1,t1],[x0,t1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func fixture(motion:Dictionary)->Dictionary:
	var shape:=rect(.1,.9,1.,5.);shape.holes=[rect(.4,.6,1.1,4.9)]
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"},{"id":"note_motion","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[shape]}],"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":.25,"motion":motion}]}
	if mode!="motion":
		raw.plugins.append({"id":"fall_speed","version":"1.0.0"})
		raw.track_speeds=[{"id":0,"speed":1.0 if mode=="neutral" else 1.2}]
		if mode=="ramp":raw.sv=[{"t":1.,"speed":.5,"dur":1.5,"ease":"inout"},{"t":3.,"speed":1.5,"dur":1.,"ease":"out"}]
	return raw
func inverse_y(r,y:float)->float:
	var lo:=0.;var hi:=1.25
	for i in 45:
		var mid:float=(lo+hi)*.5
		if r.G.y_of(mid)<y:lo=mid
		else:hi=mid
	return (lo+hi)*.5
func progress_at_s(r,s:float)->float:
	if r.curve=="linear":return (s-BuiltinRenderData.S0)/(1.-BuiltinRenderData.S0)
	return 1.-(1./s-1.)/BuiltinRenderData.PK if s<=1. else 1.+(s-1.)/BuiltinRenderData.PK
func time_at(r,p:float)->float:
	return r.visual_time(0,p) if r.has_method("visual_time") else float(r.f.t)+(1.-p)*float(r.f.fall)
func progress_at(r,tau:float)->float:
	return r.visual_progress(0,tau) if r.has_method("visual_progress") else 1.-(tau-float(r.f.t))/float(r.f.fall)
func expected_dx(m:Dictionary,p:float)->float:
	var q:=1. if p>=float(m.end) else 0. if p<=float(m.begin) else (p-float(m.begin))/(float(m.end)-float(m.begin))
	return (.1-.3)*(1.-SU.ease_by(m.ease,q))
func spans_at(r,m:Dictionary,p:float,s:float)->Array:
	var dx:=expected_dx(m,p)
	return [[r.G.x_of(.1+dx,s),r.G.x_of(.4+dx,s)],[r.G.x_of(.6+dx,s),r.G.x_of(.9+dx,s)]]
func nearest_x(x:float,spans:Array)->float:
	var result:=INF
	for span in spans:result=minf(result,absf(x-clampf(x,span[0],span[1])))
	return result
func inspect(r,m:Dictionary,data:Dictionary)->Dictionary:
	var bad:=0;var worst:=0.;var raw_worst:=0.;var cache:={};var boundary_lines:=[]
	# Very narrow valid motion may be shorter than a packed float32 screen row.
	# Measure a 2-D geometric distance to true filled boundary slices there,
	# not an impossible zero horizontal-error requirement at a rounded y value.
	for p in [float(m.begin),(float(m.begin)+float(m.end))*.5,float(m.end)]:
		var s:float=r.s_of_p(p)
		boundary_lines.append({"y":r.G.y_of(s),"spans":spans_at(r,m,p,s)})
	for i in range(0,data.indices.size(),3):
		var a:Vector2=data.points[data.indices[i]];var b:Vector2=data.points[data.indices[i+1]];var c:Vector2=data.points[data.indices[i+2]];var outside:=false
		for weight in [Vector3(1,1,1)/3.,Vector3(.5,.5,0),Vector3(.5,0,.5),Vector3(0,.5,.5),Vector3(.1,.1,.8),Vector3(.1,.8,.1),Vector3(.8,.1,.1)]:
			var point:Vector2=a*weight.x+b*weight.y+c*weight.z
			if not cache.has(point.y):
				var s:=inverse_y(r,point.y);cache[point.y]=spans_at(r,m,progress_at_s(r,s),s)
			var error:=nearest_x(point.x,cache[point.y]);raw_worst=maxf(raw_worst,error)
			for boundary in boundary_lines:
				var dy:float=point.y-float(boundary.y)
				if absf(dy)<error:
					var dx:=nearest_x(point.x,boundary.spans);error=minf(error,sqrt(dx*dx+dy*dy))
			worst=maxf(worst,error)
			if error>PIXEL_TOLERANCE:outside=true
		if outside:bad+=1
	return {"bad":bad,"error":worst,"scanline":raw_worst}
func make_renderer(s:SongPluginSession,core:GameCore,now:float,curve:String):
	var r=s.registry.service_script("renderer").new();r.configure(s.registry)
	var lights:=core.light_states(now,1.0);var by:={}
	for light in lights:by[light.id]=light
	r.f={"t":now,"fall":3.5,"reach":1.,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true,"perf":0.,"dt":0.}
	r.S=StageFx.rest();r.curve=curve;r.G=r._geo();r.TEX={"hold":GradientTexture2D.new(),"note":load("res://assets/tex/note.png")}
	return r
func run_case(ease:String,window:Array,curve:String)->void:
	var motion:={"type":"horizontal","x0":.1,"begin":window[0],"end":window[1],"ease":ease}
	var tag:=mode+"/"+curve+"/"+ease+"/"+str(window)
	var session:=SongPluginSession.new();var report:=session.prepare(folder,fixture(motion),"motion-boundary")
	check(report.errors.is_empty() and not report.requires_trust,tag+" prepare selected built-ins")
	if not report.errors.is_empty():session.close();return
	check(session.open().errors.is_empty(),tag+" selected session opens")
	var core:=GameCore.new(session.registry);check(core.load_chart(session.chart_data) and core.notes.size()==1,tag+" retains real hold")
	if core.notes.size()!=1:session.close();return
	var now:=2.0 if float(window[0])>.99 else 1.5
	var r=make_renderer(session,core,now,curve);var n:Dictionary=core.notes[0]
	# The fixture's independent closed form is checked against the actual motion
	# callback before it is used for screen containment of submitted triangles.
	for q in [0.,.125,.25,.5,.75,.875,1.]:
		var p:=lerpf(window[0],window[1],q);var tau:float=time_at(r,p)
		var point:=n.duplicate();point.t=tau
		var state:Dictionary=r._land_st(point,r._light_at(core.tl[0],tau))
		if state.alive:
			check(absf(float(state.sections[0][0])-(.1+expected_dx(motion,progress_at(r,tau))))<1e-9,tag+" real callback matches closed-form slice q="+str(q))
	var captured:=[];var provider:Dictionary=session.registry.get_entry("track_geometry","shape");var original:Callable=provider.ribbon_mesh
	provider.ribbon_mesh=func(renderer,note,state,a,b,t,f,opacity,fade,thin):
		var data:Dictionary=original.call(renderer,note,state,a,b,t,f,opacity,fade,thin);captured.append(data);return data
	var st:Dictionary=r._land_st(n,r._light_at(core.tl[0],2.))
	r._ribbon(r,n,st,2.,4.,now,3.5,1.,0.)
	check(captured.size()==1,tag+" actual RenderingServer path invokes provider")
	if captured.is_empty():r.free();session.close();return
	var data:Dictionary=captured[0]
	check(data.errors.is_empty() and not data.indices.is_empty(),tag+" legal narrow window keeps finite nonempty mesh")
	check(data.points.size()<=65536,tag+" vertex budget retained")
	var finite:=true
	for p in data.points:finite=finite and p.is_finite()
	check(finite,tag+" no NaN or Inf")
	var measured:=inspect(r,motion,data)
	check(measured.bad==0,tag+" all sampled actual screen triangles within 0.25 logical px of true filled region")
	max_screen_error=maxf(max_screen_error,measured.error);max_scanline_error=maxf(max_scanline_error,measured.scanline)
	# Critical progress boundaries are represented, even when they lie between
	# the former 29 endpoint samples. Closed float32 rows have finite precision.
	var hint:Dictionary=Motion.hold_cuts(r,n,2.,4.,[.1,.9])
	check(hint.errors.is_empty(),tag+" explicit cut hints stay in budget")
	for p in [float(window[0]),(float(window[0])+float(window[1]))*.5,float(window[1])]:
		var tau:float=time_at(r,p)
		if tau>2. and tau<4.:
			var found:=false
			for t in hint.times:
				if absf(float(t)-tau)<1e-12:found=true
			check(found,tag+" contains required begin/mid/end cut")
	if mode=="neutral":
		var baseline:=BuiltinRendererRuntime.new();baseline.configure(session.registry);baseline.f=r.f;baseline.G=r.G;baseline.S=r.S;baseline.TEX=r.TEX;baseline.curve=r.curve
		check(original.call(baseline,n,st,2.,4.,now,3.5,1.,0.,1.)==data,tag+" neutral SV actual mesh equals standard renderer")
		baseline.free()
	r._plan_notes()
	check(r._nd_notes.size()==2,tag+" real planner retains head and tail caps")
	var caps_inside:=true
	for cap in r._nd_notes:
		var s_cap:=float(cap[5]);var spans:=spans_at(r,motion,progress_at_s(r,s_cap),s_cap);var contained:=false
		for span in spans:
			if float(cap[0])-float(cap[2])*.5>=float(span[0])-.002 and float(cap[0])+float(cap[2])*.5<=float(span[1])+.002:contained=true
		caps_inside=caps_inside and contained
	check(caps_inside,tag+" actual cap widths stay in their own visual sections")
	core.playing=true;core.autoplay=true
	for i in int(ceil(core.end_time*240))+1:core.update(i/240.0)
	check(core.stats.score==1010000 and core.stats.MISS==0,tag+" unchanged real hold judgement full score")
	print("MOTION CASE ",tag," vertices=",data.points.size()," triangles=",data.indices.size()/3," outside=",measured.bad," error_logical_px=",measured.error," scanline_logical_px=",measured.scanline)
	r.free();session.close()
func endpoints()->void:
	var session:=SongPluginSession.new();var raw:=fixture({"type":"horizontal","x0":.1,"begin":.5,"end":.5000001,"ease":"linear"})
	# Every sampled endpoint must be inside this deliberately longer fixture.
	raw.tracks[0].shapes[0].nodes[2][1]=8.;raw.tracks[0].shapes[0].nodes[3][1]=8.
	raw.tracks[0].shapes[0].holes[0].nodes[2][1]=7.9;raw.tracks[0].shapes[0].holes[0].nodes[3][1]=7.9
	var report:=session.prepare(folder,raw,"motion-endpoints");check(report.errors.is_empty(),"endpoint session prepares")
	check(session.open().errors.is_empty(),"endpoint session opens")
	var core:=GameCore.new(session.registry);check(core.load_chart(session.chart_data),"endpoint real chart loads")
	var r=make_renderer(session,core,1.5,"linear");var n:Dictionary=core.notes[0]
	for pair in [[.5,.5000001],[.9999999,1.],[0.,.0000001],[0.,1.]]:
		for ease in SU.EASES:
			n.motion={"type":"horizontal","x0":.1,"begin":pair[0],"end":pair[1],"ease":ease}
			check(Motion.horizontal_valid(n.motion),"every positive narrow window remains legal")
			# Set now from the integrated clock's monotonic inverse by shifting the
			# head time for the point; keep now fixed so this also covers P5.
			for p in [float(pair[0]),float(pair[1]),1.]:
				var point:=n.duplicate();point.t=time_at(r,p)
				var st:Dictionary=r._land_st(point,r._light_at(core.tl[0],float(point.t)))
				check(st.alive,"required endpoint fixture slice exists")
				if not st.alive:r.free();session.close();return
				var target:=.1 if p==float(pair[0]) else .3
				check(absf(r._geometry_note_x(st,.25)-target)<0.00000001,"exact begin/end/landing for "+str(pair)+" "+ease+" p="+str(p))
	for pair in [[.5,.5],[.6,.5],[-.1,.5],[.5,1.1]]:
		check(not Motion.horizontal_valid({"begin":pair[0],"end":pair[1]}),"invalid interval stays invalid")
	n.motion={"type":"horizontal","x0":3.,"begin":0.,"end":1.,"ease":"inout"}
	var legal:Dictionary=Motion.hold_cuts(r,n,2.,4.,[-8.,8.])
	check(legal.errors.is_empty(),"maximum legal x range fits explicit cut budget")
	var bad:Dictionary=Motion.hold_cuts(r,n,2.,4.,[-1e9,1e9])
	check(not bad.errors.is_empty() and bad.times.is_empty(),"cut over-budget reports error with no partial hints")
	r.free();session.close()
func _init()->void:
	KB.set_layout("ansi")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
	check(mode in ["motion","neutral","speed","ramp"],"explicit test scope mode")
	folder=ProjectSettings.globalize_path("user://motion-boundaries")
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"required writable fixture directory")
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://plugins/builtin/note_motion/plugin.json"))
	check(manifest is Dictionary,"actual packaged motion manifest exists and parses")
	if manifest is Dictionary:
		for path in ["notes[].motion.begin","notes[].motion.end"]:
			var found:=false
			for field in manifest.get("fields",[]):
				if field.get("path","")==path:
					found=true
					check(float(field.get("min",-1.))==0. and float(field.get("max",-1.))==1.,path+" metadata permits every legal positive window")
					check(float(field.get("step",0.))==.01 and "begin < end" in field.get("doc",""),path+" joint condition and editor step documented")
			check(found,path+" required author metadata exists")
	endpoints()
	for curve in ["linear","deemo"]:
		for ease in SU.EASES:
			for window in [[.5,.5001],[.5,.5000001],[.9999999,1.],[0.,1.]]:run_case(ease,window,curve)
	check(PluginRegistry.standard().manifests.size()==4,"standard catalog remains exactly four")
	print("MOTION BOUNDARIES ",mode,": ",checks," checks, ",failures," failures; max screen distance logical px=",max_screen_error," raw scanline logical px=",max_scanline_error)
	quit(0 if failures==0 else 1)
