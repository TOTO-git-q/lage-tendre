## Preparatory P5: exact SV integral, arrival, immutable judgement and visual composition.
extends SceneTree
const Profile=preload("res://plugins/builtin/fall_speed/profile.gd")
const Geometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Painter=preload("res://plugins/builtin/shape_tracks/render.gd")
var song_dir:=""
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func near(a: float,b: float,epsilon:=1e-8) -> bool: return absf(a-b)<=epsilon
func event(t: float,speed: float,dur:=0.0,ease:="linear") -> Dictionary: return {"t":t,"speed":speed,"dur":dur,"ease":ease}
func base_chart() -> Dictionary:
	return {"bpm":120,"lights":[{"id":0,"t":0.1,"type":"on","x":0.75,"w":0.3,"auto":true}],"notes":[{"light":0,"t":3.0,"u":0.5,"kind":"tap"}]}
func selected(raw: Dictionary,extra:=[]) -> SongPluginSession:
	var chart:=raw.duplicate(true); chart["plugins"]=[{"id":"fall_speed","version":"1.0.0"}]
	for id in extra: chart.plugins.append({"id":id,"version":"1.0.0"})
	var s:=SongPluginSession.new(); var report:=s.prepare(song_dir,chart,"sv-test")
	check(report.errors.is_empty() and not report.requires_trust,"explicit built-in speed session prepares")
	check(s.open().errors.is_empty(),"speed scope opens")
	return s
func make_renderer(core: GameCore):
	var r=core.registry.service_script("renderer").new(); r.configure(core.registry)
	r.S=StageFx.rest(); r.TEX.note=load("res://assets/tex/note.png")
	set_frame(r,core,2.3); return r
func set_frame(r,core: GameCore,t: float) -> void:
	var lights:=core.light_states(t,1.0); var by:={}
	for light in lights: by[light.id]=light
	r.f={"t":t,"fall":1.5,"reach":1.0,"perf":0.0,"dt":1.0/60,"tl":core.tl,"chart":core.chart,"notes":core.notes,"lights":lights,"light_by_id":by,"chords":core.chords,"play":true}
	r.G=r._geo()
func _init() -> void:
	KB.set_layout("ansi")
	var songs_root:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--songs-root="):songs_root=arg.substr(13)
	check(not songs_root.is_empty() and songs_root.is_absolute_path(),"explicit absolute songs-root required")
	if songs_root.is_empty() or not songs_root.is_absolute_path():quit(1);return
	song_dir=songs_root.path_join("_plugin_demos/speed")
	check(DirAccess.dir_exists_absolute(song_dir),"required external speed demo directory exists")
	if not DirAccess.dir_exists_absolute(song_dir):quit(1);return
	check(FileAccess.file_exists(song_dir.path_join("chart.json")),"required actual speed demo chart exists")
	if songs_root.is_empty() or not FileAccess.file_exists(song_dir.path_join("chart.json")):
		printerr("Required speed fixture unavailable; no silent skip");quit(1);return
	var raw=SU.load_json(song_dir.path_join("chart.json"))
	check(raw is Dictionary and raw.get("notes") is Array,"required speed fixture is an object with a notes array")
	if not raw is Dictionary or not raw.get("notes") is Array:quit(1);return
	check(raw.notes.size()==18,"actual speed fixture contains eighteen required notes")
	if raw.notes.size()!=18:quit(1);return
	_test_integrals()
	_test_validation()
	_test_neutral()
	_test_extremes()
	_test_composition()
	_test_game()
	check(PluginRegistry.standard().services.renderer.plugin=="standard_render","standard renderer service is never replaced globally")
	print("FALL SPEED: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func _test_integrals() -> void:
	var areas={"linear":0.5,"in":0.25,"out":0.75,"inout":0.5}
	var halves={"linear":0.125,"in":0.015625,"out":0.265625,"inout":0.0625}
	for ease in SU.EASES:
		var p:=Profile.compile([event(2,3,4,ease)])
		check(near(Profile.integral(p,2),2),"SV start prefix exact "+ease)
		check(near(Profile.integral(p,4),4+8*halves[ease]),"analytic half-ramp area "+ease)
		check(near(Profile.integral(p,6),6+8*areas[ease]),"analytic complete-ramp area "+ease)
		check(near(Profile.integral(p,8),12+8*areas[ease]),"constant tail area "+ease)
		for t in [-3.0,0.0,1.999,2.0,2.001,3.0,4.0,5.0,5.999,6.0,6.001,9.0]:
			check(near(Profile.time_at(p,Profile.integral(p,t)),t,1e-9),"strictly-positive integral inversion "+ease+" t="+str(t))
		for t in [2.2,3.1,4.4,5.7,7.0]:
			var derivative: float=(Profile.integral(p,t+0.00001)-Profile.integral(p,t-0.00001))/0.00002
			check(near(derivative,Profile.speed(p,t),1e-7),"integral derivative equals eased speed "+ease)
	var overlap:=Profile.compile([event(4,0.5,2,"out"),event(2,3,4,"linear")])
	check(near(overlap.events[1].from,2) and near(overlap.events[1].area,5),"later ramp truncates with continuous instantaneous speed")
	check(near(Profile.integral(overlap,6),6.75) and near(Profile.integral(overlap,7),7.25),"overlap eased area and tail are exact")
	for t in [3.999999,4.0,4.000001,5.0,5.99999,6.0,6.000001]:
		check(near(Profile.time_at(overlap,Profile.integral(overlap,t)),t,1e-9),"overlap boundary inverse "+str(t))
	var tie:=Profile.compile([event(2,3,4),event(2,2)])
	check(tie.events.size()==1 and near(Profile.speed(tie,2),2) and near(Profile.integral(tie,3),4),"last authored same-time SV event wins")
	var neutral:=Profile.compile([event(0,1),event(4,1,2,"inout")])
	for t in [0.0,0.1,1.3,4.0,4.9,6.0,100.0]: check(Profile.integral(neutral,t)==t and Profile.time_at(neutral,t)==t,"neutral SV is exactly identity")
func _test_validation() -> void:
	for bad in [0,-1,NAN,INF,0.049,8.001,"fast",{}]:
		var raw:=base_chart(); raw["track_speeds"]=[{"id":0,"speed":bad}]; raw["sv"]=[event(1,1)]; raw.sv[0].speed=bad
		var s:=selected(raw); var chart:=ChartLib.validate(s.chart_data,s.registry)
		check(chart.track_speeds.is_empty() and chart.sv.is_empty() and chart.warnings.size()>=2,"invalid speed is diagnosed and never applied "+str(bad)); s.close()
	for bad in [event(-1,1),event(1,1,-1),event(86400,1,1),{"t":1,"speed":1,"ease":[]},{"t":{},"speed":1},null]:
		var raw:=base_chart(); raw["sv"]=[bad]; var s:=selected(raw); var chart:=ChartLib.validate(s.chart_data,s.registry)
		check(chart.sv.is_empty() and not chart.warnings.is_empty(),"invalid SV event rejected safely"); s.close()
	for value in [[],0,{},null]:
		var raw:=base_chart(); raw["track_speeds"]=value; raw["sv"]=value
		var s:=selected(raw); var chart:=ChartLib.validate(s.chart_data,s.registry)
		check(chart._fall_neutral,"malformed speed containers are neutral"); s.close()
	var raw:=base_chart(); raw["track_speeds"]=[{"id":0,"speed":0.05},{"id":0,"speed":2},{"id":99,"speed":2}]; raw["sv"]=[event(0,8)]
	var s:=selected(raw); var chart:=ChartLib.validate(s.chart_data,s.registry)
	check(chart.track_speeds.size()==1 and chart.warnings.size()==2 and chart._fall_tracks[0]==0.05,"range endpoints accepted; duplicate/unknown IDs diagnosed")
	var oversized:=s.chart_data.duplicate(true); oversized.sv=[]
	for i in Profile.MAX_EVENTS+1: oversized.sv.append(event(i,1))
	check(ChartLib.validate(oversized,s.registry).sv.is_empty(),"SV cumulative event budget enforced before sorting")
	s.close()
func _test_neutral() -> void:
	var raw:=base_chart(); raw["track_speeds"]=[{"id":0,"speed":1}]
	var s:=selected(raw); var core:=GameCore.new(s.registry); core.load_chart(s.chart_data)
	var r=make_renderer(core); var standard:=BuiltinRendererRuntime.new(); standard.configure(PluginRegistry.standard())
	for fall in [0.6,1.5,3.5]:
		for i in 61:
			r.f.t=i/20.0; r.f.fall=fall; standard.f=r.f
			check(r.visual_progress(0,3.0)==1.0-(3.0-r.f.t)/fall and r.visual_progress(0,3.0)==standard.visual_progress(0,3.0),"neutral progress bit-exact at "+str(i))
	check(not r.uses_integrated_scroll(),"neutral renderer selects original implementation")
	for t in [1.7,2.0,2.4,2.8,3.0]:
		set_frame(r,core,t); standard.f=r.f; standard.S=StageFx.rest(); standard.G=standard._geo(); standard.TEX=r.TEX
		r._plan_notes(); standard._plan_notes()
		check(r._nd_notes==standard._nd_notes,"neutral actual note primitives exactly match legacy at "+str(t))
	r.free(); standard.free(); s.close()
func _test_extremes() -> void:
	for speed in [0.05,8.0]:
		var raw:=base_chart(); raw["track_speeds"]=[{"id":0,"speed":speed}]; raw["sv"]=[event(0,speed)]
		var session:=selected(raw); var core:=GameCore.new(session.registry); core.load_chart(session.chart_data)
		var r=make_renderer(core)
		for progress in [0.0,0.25,0.5,0.75,1.0]:
			var now: float=3.0-(1.0-progress)*1.5/(speed*speed)
			set_frame(r,core,now)
			check(near(r.visual_progress(0,3.0),progress,1e-9) if now>=0.0 else is_finite(r.visual_progress(0,3.0)),"extreme positive speed stays finite")
			check(near(r.visual_time(0,r.visual_progress(0,3.0)),3.0,1e-7),"extreme integral inverse across pre-event time")
		if speed==8.0:
			set_frame(r,core,3.0-0.75*1.5/64.0)
			r._plan_notes(); var ordinary: Array=r._nd_notes[0].duplicate()
			core.notes[0].grow=[0.5,1.5]; r._plan_notes()
			var expected: float=lerpf(0.5,1.5,0.25*0.25*(3.0-2.0*0.25))
			check(near(r._nd_notes[0][3]/ordinary[3],expected,1e-10),"grow uses integrated progress even above old minimum-fall clamp")
		r.free(); session.close()
func composed_chart() -> Dictionary:
	var outer={"nodes":[[0.1,0.5],[0.9,0.5],[0.9,7],[0.1,7]],"segs":[["linear"],["linear"],["linear"],["linear"]],"holes":[{"nodes":[[0.4,0.6],[0.6,0.6],[0.6,6.9],[0.4,6.9]],"segs":[["linear"],["linear"],["linear"],["linear"]]}]}
	return {"bpm":120,"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[outer]}],"track_speeds":[{"id":0,"speed":1.5}],"sv":[event(1,0.5,1,"out"),event(4,1.4,1,"in")],"notes":[{"t":3.0,"light":0,"u":0.8,"kind":"tap","motion":{"type":"horizontal","x0":0.2,"ease":"linear"}},{"t":4.0,"light":0,"u":0.8,"kind":"hold","dur":1.25,"motion":{"type":"horizontal","x0":0.2,"ease":"linear"}}]}
func install_ring(scope: PluginRegistry):
	var m={"id":"sv_ring_probe","version":"1.0.0","api":1,"tier":"declarative","title":"SV probe","author":"L’âge tendre","description":"Owned composition test","assets":[],"entry":"","fields":[{"path":"notes[].ring","type":"number","default":1,"unit":"scale","doc":"Ring scale","min":0,"max":2}],"provides":{"elements":["ring"]},"definitions":{"elements":{"ring":{"kind":"glow_ring","field":"ring","radius":"value * (0.5 + progress)","opacity":"1","width":2}}}}
	scope.begin_plugin(m); var errors:=PluginDeclarative.install(scope,m,song_dir); scope.end_plugin()
	check(errors.is_empty(),"real declarative ring installs for composition test")
	return scope._owned[-1].object
func _test_composition() -> void:
	var s:=selected(composed_chart(),["shape_tracks","note_motion"]); var provider=install_ring(s.registry)
	var core:=GameCore.new(s.registry); check(core.load_chart(s.chart_data) and core.chart.warnings.is_empty(),"shape + horizontal + SV + hold chart validates")
	var r=make_renderer(core); var n: Dictionary=core.notes[0]; var p: float=r.visual_progress(0,n.t)
	check(near(p,0.65),"integrated slow-SV progress expected at t2.3")
	var st: Dictionary=r._land_st(n,core.light_states(2.3,1.0)[0]); var target:=0.1+0.8*0.8
	check(near(r._geometry_note_x(st,n.u),lerpf(0.2,target,p)),"horizontal uses shared integrated progress")
	var rings: Array=provider.ring_primitives(r,"ring"); r._plan_notes()
	check(not rings.is_empty() and not r._nd_notes.is_empty(),"real ring and note primitives produced")
	var point: Dictionary=r._note_at(st,n,p)
	check(rings[0].center.distance_to(Vector2(r._nd_notes[0][0],r._nd_notes[0][1]))<0.0001,"declarative ring stays centered on speed/motion/shape note")
	check(near(rings[0].radius,(0.5+p)*absf(point.kw),0.0001),"declarative formula progress follows SV")
	var prepared: Dictionary=core.chart.lights[0].shape; var mesh:=Painter.mesh(r,prepared); var consistent: bool=not mesh.indices.is_empty()
	for i in mesh.plane.size():
		if not near(mesh.plane[i].y,r.s_of_p(r.visual_progress(0,float(mesh.times[i]))),0.000001): consistent=false; break
	check(consistent,"every shape vertex uses same integrated chart-time projection")
	check(near(r.visual_progress(0,r.visual_time(0,0)),0,1e-8),"shape horizon uses exact inverse integral")
	var hold: Dictionary=core.notes[1]; set_frame(r,core,3.6)
	var data: Dictionary=r.ribbon_mesh(hold,hold.t,minf(hold.t+hold.dur,r.visual_time(0,0)),3.6,1.0)
	var safe: bool=not data.indices.is_empty()
	for i in data.points.size():
		var time: float=data.times[i]; var row: Dictionary=r._hold_state(hold,time,hold.u); var section: Array=r._geometry_note_section(row,hold.u)
		if not is_finite(data.points[i].x) or not is_finite(data.points[i].y) or data.plane[i].x<section[0]-0.000001 or data.plane[i].x>section[1]+0.000001 or not near(data.plane[i].y,r.s_of_p(r.visual_progress(0,time)),0.000001): safe=false; break
	check(safe,"hold body uses inverse SV and stays inside shifted shape section")
	var sliding:=hold.duplicate(true); sliding.motion={"type":"straight"}; sliding.path=[[0.0,0.2,1.0],[1.25,0.8,1.0]]
	var split: Dictionary=r.ribbon_mesh(sliding,sliding.t,minf(sliding.t+sliding.dur,r.visual_time(0,0)),3.6,1.0)
	var separated: bool=not split.indices.is_empty()
	for i in range(0,split.indices.size(),3):
		var left:=false; var right:=false
		for j in 3:
			var x: float=split.plane[split.indices[i+j]].x
			left=left or x<0.5; right=right or x>0.5
		if left and right: separated=false; break
	check(separated,"slide ribbon never bridges the disconnected shape intervals")
	for time in [3.0,4.0,4.25,4.5,4.75,5.0,5.25]:
		set_frame(r,core,time)
		check(r.visual_progress(0,time)==1.0,"tap/hold head/body/tail arrives exactly at own time "+str(time))
		var landing: Dictionary=r._hold_state(hold,time,hold.u)
		check(near(r._geometry_note_x(landing,hold.u),target),"motion reaches unshifted judgement section exactly on time")
	set_frame(r,core,4.2); core.notes[0].state="hit"; core.notes[1].state="holding"; r._plan_notes()
	check(not r._nd_notes.is_empty() and not r._nd_holds.is_empty(),"actual combined hold planner emits body/head/tail draw data")
	r.free()
	core=GameCore.new(s.registry); core.load_chart(s.chart_data); core.playing=true; core.autoplay=true
	for i in int(ceil(core.end_time*240))+1: core.update(i/240.0)
	check(core.stats.MISS==0 and core.stats.PERFECT==core.stats.total and core.stats.score==1010000,"combined shape/motion/SV/hold autoplay full score")
	print("COMPOSED_AUTOPLAY ",JSON.stringify(core.stats)); s.close()
func _test_game() -> void:
	var raw: Dictionary=SU.load_json(song_dir+"/chart.json"); var s:=selected(raw)
	var core:=GameCore.new(s.registry); check(core.load_chart(s.chart_data),"speed demo loads")
	var r=make_renderer(core)
	for n in core.notes:
		for now in [0.0,2.5,4.0,5.5,7.0,8.0,float(n.t)]:
			set_frame(r,core,now)
			var p: float=r.visual_progress(n.light,n.t)
			check(is_finite(p) and near(r.visual_time(n.light,p),n.t,1e-7),"per-track speed/SV forward-inverse finite")
		set_frame(r,core,n.t); check(r.visual_progress(n.light,n.t)==1.0,"all demo heads arrive exactly")
	set_frame(r,core,2.5)
	check(r.visual_progress(0,3.0)<r.visual_progress(1,3.0),"fast and slow simultaneous notes occupy different depths")
	r.free(); core.playing=true; core.autoplay=true
	for i in int(ceil(core.end_time*240))+1: core.update(i/240.0)
	var legacy_raw:=raw.duplicate(true); legacy_raw.erase("plugins"); legacy_raw.erase("sv"); legacy_raw.erase("track_speeds")
	var legacy:=GameCore.new(); legacy.load_chart(legacy_raw); legacy.playing=true; legacy.autoplay=true
	for i in int(ceil(legacy.end_time*240))+1: legacy.update(i/240.0)
	check(core.stats==legacy.stats and core.stats.score==1010000 and core.stats.MISS==0,"SV autoplay is full score and identical to no-speed judgement")
	check(core.notes.size()==18,"speed demo contains 16 taps and 2 holds")
	print("SPEED_AUTOPLAY ",JSON.stringify(core.stats))
	var temp:=ProjectSettings.globalize_path("user://speed-recovery-output")
	check(DirAccess.make_dir_recursive_absolute(temp)==OK,"writable isolated compact-chart output")
	var compact:=temp.path_join("compact.chart.json")
	check(ChartCodec.save_file(compact,s.chart_data,s.registry.field_schema()).ok,"speed/SV default writer succeeds")
	var expanded:=ChartCodec.expand(SU.load_json(compact),s.registry.field_schema())
	check(ChartCodec._equal(expanded.track_speeds,s.chart_data.track_speeds) and ChartCodec._equal(expanded.sv,s.chart_data.sv),"speed/SV defaults roundtrip")
	s.close()
