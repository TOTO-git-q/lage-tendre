## Focused P4 preparation. Full P0 graphics/performance gate is separate.
extends SceneTree
const Motion=preload("res://plugins/builtin/note_motion/runtime.gd")
const ShapeGeometry=preload("res://plugins/builtin/shape_tracks/geometry.gd")
const EditOps=preload("res://scripts/chart_models/edit_ops.gd")
const EditorHorizontal=preload("res://scripts/chart_models/horizontal.gd")
var songs_root:=ProjectSettings.globalize_path("res://../songs")
var demo_dir:=""
var fixture_chart: Dictionary={}
var output_dir:="user://plugin-focused-tests/p4-motion"
var checks:=0
var failures:=0
var session: SongPluginSession
var scope: PluginRegistry
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)
func near(a: float,b: float) -> bool: return absf(a-b)<1e-8
func lane() -> Dictionary:
	return {"bpm":120,"lights":[{"id":0,"t":0.1,"type":"on","x":0.2,"w":0.2,"auto":true},{"id":0,"t":1.7,"type":"sweep","x":0.8,"w":0.3,"dur":1.0,"ease":"inout","auto":true}],"notes":[{"t":3.0,"light":0,"u":0.25,"kind":"tap"}]}
func scoped(raw: Dictionary,shape:=false) -> SongPluginSession:
	var input:=raw.duplicate(true)
	input["plugins"]=[{"id":"note_motion","version":"1.0.0"}]
	if shape: input.plugins.append({"id":"shape_tracks","version":"1.0.0"})
	var selected:=SongPluginSession.new()
	var report:=selected.prepare(demo_dir,input,"motion-test")
	check(report.errors.is_empty() and not report.requires_trust,"built-in motion session prepares without song-script trust")
	check(selected.open().errors.is_empty(),"motion session opens with P2 router")
	return selected
func renderer(registry: PluginRegistry,chart: Dictionary) -> BuiltinRendererRuntime:
	var r:=BuiltinRendererRuntime.new(); r.configure(registry)
	r.f={"t":1.5,"fall":1.5,"perf":0.0,"tl":ChartLib.build_timelines(chart.lights,registry)}
	r.S=StageFx.rest(); r.G=r._geo(); r.TEX.note=load("res://assets/tex/note.png")
	return r
## External songs are explicit for packed runs; generated files stay writable.
func prepare_test_paths() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--songs-root="): songs_root=argument.trim_prefix("--songs-root=")
	check(songs_root.is_absolute_path(),"songs-root is an absolute filesystem path")
	if not songs_root.is_absolute_path(): return false
	demo_dir=songs_root.path_join("_plugin_demos/motion")
	check(DirAccess.dir_exists_absolute(demo_dir),"required motion demo directory exists")
	if not DirAccess.dir_exists_absolute(demo_dir): return false
	var chart_path:=demo_dir.path_join("chart.json")
	check(FileAccess.file_exists(chart_path),"required real motion chart fixture exists")
	if not FileAccess.file_exists(chart_path): return false
	var loaded=SU.load_json(chart_path)
	var valid: bool=loaded is Dictionary and loaded.get("notes") is Array and not loaded.get("notes",[]).is_empty()
	check(valid,"required motion chart fixture is a nonempty chart object")
	if not valid: return false
	fixture_chart=loaded
	var made:=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	check(made==OK,"user output directory is writable")
	return made==OK
func _init() -> void:
	KB.set_layout("ansi")
	if not prepare_test_paths(): quit(1); return
	session=scoped(lane()); scope=session.registry
	_test_defaults_and_legacy()
	_test_horizontal()
	_test_shape_composition()
	_test_validation()
	_test_converter()
	_test_judgement()
	session.close()
	check(PluginRegistry.standard().get_entry("motions","straight").is_empty(),"closing opt-in scope leaves standard motions unchanged")
	check(checks==183,"full expected P4 assertion count before final guard")
	print("NOTE MOTION: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func _test_defaults_and_legacy() -> void:
	var raw:=lane(); var legacy:=ChartLib.validate(raw,PluginRegistry.standard())
	var active:=ChartLib.validate(session.chart_data,scope)
	check(not legacy.notes[0].has("motion"),"old chart has no added motion metadata")
	check(active.notes[0].motion.type=="straight","enabled plugin defaults to straight")
	check(scope.get_entry("motions","follow_track").plugin=="standard_render","follow_track retains standard provider ownership")
	var old:=renderer(PluginRegistry.standard(),legacy); var current:=renderer(scope,active)
	var n: Dictionary=active.notes[0]
	var target:=ChartLib.light_at(current.f.tl[0],3.0,scope)
	for i in 31:
		var t:=1.5+i/20.0; old.f.t=t; current.f.t=t
		var st:=ChartLib.light_at(old.f.tl[0],t,PluginRegistry.standard())
		var expected:=old._follow_track_state(legacy.notes[0],st)
		check(old._land_st(legacy.notes[0],st)==expected,"legacy literal follow_track state at "+str(t))
		var follow:=n.duplicate(true); follow.motion={"type":"follow_track"}
		check(current._land_st(follow,st)==expected,"explicit follow_track exact standard state at "+str(t))
		var straight:=current._land_st(n,st)
		check(near(straight.x,target.x) and near(straight.w,target.w),"straight stays at final landing slice "+str(t))
	old.free(); current.free()
	var compact_path:=output_dir.path_join("compact.chart.json")
	check(ChartCodec.save_file(compact_path,session.chart_data,scope.field_schema()).ok,"compact writer records omissions")
	var compact: Dictionary=SU.load_json(compact_path)
	var expanded:=ChartCodec.expand(compact,scope.field_schema())
	check(ChartLib.validate(expanded,scope).notes[0].motion.type=="straight","compact defaults roundtrip straight in selected scope")
func _test_horizontal() -> void:
	var chart:=ChartLib.validate(session.chart_data,scope); var r:=renderer(scope,chart)
	var n: Dictionary=chart.notes[0].duplicate(true); n.motion={"type":"horizontal","x0":0.1,"ease":"linear","begin":0.2,"end":0.8}
	var target: float=0.8+(n.u-0.5)*0.3
	for pair in [[0.0,0.1],[0.2,0.1],[0.5,lerpf(0.1,target,0.5)],[0.8,target],[1.0,target]]:
		r.f.t=3.0-(1.0-pair[0])*1.5
		var original:=ChartLib.light_at(r.f.tl[0],r.f.t,scope); var saved:=original.duplicate(true)
		var st:=r._land_st(n,original)
		check(near(st.x+(n.u-0.5)*st.w,pair[1]),"horizontal start/ease/end/landing "+str(pair[0]))
		check(original==saved,"visual motion never mutates shared light state")
	for ease in SU.EASES:
		n.motion.ease=ease; r.f.t=2.1
		var st:=r._land_st(n,ChartLib.light_at(r.f.tl[0],r.f.t,scope))
		var k:=SU.ease_by(ease,(0.4-0.2)/(0.8-0.2))
		check(near(st.x+(n.u-0.5)*st.w,lerpf(0.1,target,k)),"horizontal exact standard ease "+ease)
	r.free()
func _test_shape_composition() -> void:
	var shape={"nodes":[[0.1,1],[0.9,1],[0.9,4],[0.1,4]],"segs":[["linear"],["linear"],["linear"],["linear"]],"holes":[{"nodes":[[0.4,1.1],[0.6,1.1],[0.6,3.9],[0.4,3.9]],"segs":[["linear"],["linear"],["linear"],["linear"]]}]}
	var raw={"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[shape]}],"notes":[{"t":3.0,"light":0,"u":0.9,"kind":"tap","motion":{"type":"horizontal","x0":0.2,"ease":"linear"}}]}
	var both:=scoped(raw,true); var chart:=ChartLib.validate(both.chart_data,both.registry); var r:=renderer(both.registry,chart)
	check(chart.warnings.is_empty() and chart.notes.size()==1,"shape + motion chart validates together")
	var compact_path:=output_dir.path_join("shape_motion.compact.json")
	check(ChartCodec.save_file(compact_path,both.chart_data,both.registry.field_schema()).ok,"shape + motion defaults save succeeds")
	var saved_raw: Dictionary=SU.load_json(compact_path)
	var reload_session:=scoped(saved_raw,true)
	var reloaded:=ChartLib.validate(reload_session.chart_data,reload_session.registry)
	check(reloaded.warnings.is_empty() and reloaded.notes.size()==1 and ChartCodec._equal(reloaded.tracks,chart.tracks),"shape defaults/metadata roundtrip through final P2 codec")
	check(reloaded.notes[0].motion==chart.notes[0].motion,"motion defaults roundtrip in shape scope")
	reload_session.close()
	var n: Dictionary=chart.notes[0]; var landing:=ChartLib.light_at(r.f.tl[0],n.t,both.registry)
	var saved:=landing.duplicate(true); var target:=ShapeGeometry.note_x(landing,n.u)
	for p in [0.0,0.25,0.5,1.0]:
		r.f.t=n.t-(1.0-p)*r.f.fall
		var st:=r._land_st(n,landing); var x:=r._geometry_note_x(st,n.u); var section:=r._geometry_note_section(st,n.u)
		check(near(x,lerpf(0.2,target,p)),"shape base state precedes visual motion "+str(p))
		check(st.sections.size()==2 and section[0]<=x and x<=section[1],"shape sections/clip shift with visual note "+str(p))
		check(landing==saved,"shape judgement sections stay immutable")
		r._cur_note=n; r._cur_lw=st.w; r._cur_st=st
		r._draw_note(null,r._note_at(st,n,p),1.0)
		check(not r._nd_notes.is_empty(),"shape/motion clipped note remains drawable")
		var draw: Array=r._nd_notes[-1]
		check(is_finite(draw[0]) and is_finite(draw[2]) and draw[2]>0,"composed note size is finite and positive")
	r.free(); both.close()
func _test_validation() -> void:
	for invalid in [null,[],3,"horizontal",{"type":"missing"},{"type":"horizontal","x0":NAN},{"type":"horizontal","x0":INF},{"type":"horizontal","x0":4},{"type":"horizontal","begin":0.5,"end":0.5},{"type":"horizontal","begin":-0.2},{"type":"horizontal","end":2},{"type":"horizontal","ease":"missing"},{"type":"horizontal","x0":{}}]:
		var raw:=session.chart_data.duplicate(true); raw.notes[0].motion=invalid
		var chart:=ChartLib.validate(raw,scope)
		check(chart.notes[0].motion.type=="straight" and not chart.warnings.is_empty(),"invalid motion safely falls back "+str(invalid))
func _test_converter() -> void:
	var raw:=lane(); raw.notes[0]["k"]=2
	var key:=EditOps.motion_key(raw.notes[0]); check(key=="3.000000|0|2","real charter identity")
	var params={"from":-3.0,"begin":20.0,"end":70.0,"ease":"out"}
	var side={"shapes":{"keep":{}},"motions":{key:{"type":"horizontal","params":params},"unmatched":{"type":"follow_track"}}}
	var saved:=raw.duplicate(true); var saved_side:=side.duplicate(true)
	var converted:=Motion.convert_sidecar(raw,side,scope)
	check(converted.errors.is_empty(),"actual charter sidecar converts")
	check(raw==saved and side==saved_side,"converter does not mutate input")
	if not converted.errors.is_empty(): return
	check(converted.sidecar.motions.has("unmatched") and converted.sidecar.shapes==side.shapes,"unmatched editor sidecar state retained")
	var chart:=ChartLib.validate(converted.chart,scope); var r:=renderer(scope,chart); var n: Dictionary=chart.notes[0]
	var land: float=0.8+(n.u-0.5)*0.3
	for p in [0.0,0.2,0.4,0.7,1.0]:
		r.f.t=n.t-(1-p)*r.f.fall
		var st:=r._land_st(n,ChartLib.light_at(r.f.tl[0],r.f.t,scope))
		check(near(st.x+(n.u-0.5)*st.w-land,EditorHorizontal.offset(params,(1-p)*1.3,{})),"converter matches actual editor horizontal offset "+str(p))
	r.free()
	var ambiguous:=raw.duplicate(true); ambiguous.notes.append(raw.notes[0].duplicate(true))
	check(not Motion.convert_sidecar(ambiguous,side,scope).errors.is_empty(),"ambiguous editor identities explicitly rejected")
	for bad in [{"type":"follow_track","params":{"amount":50}},{"type":"horizontal","params":{"end":0}},{"type":"horizontal","params":{"from":NAN}},{"type":"horizontal","params":{"ease":"invalid"}}]:
		var invalid_side:=side.duplicate(true); invalid_side.motions[key]=bad
		check(not Motion.convert_sidecar(raw,invalid_side,scope).errors.is_empty(),"unsupported editor motion never silently approximated")
func _test_judgement() -> void:
	var raw={"bpm":120,"lights":[{"id":0,"t":0.1,"type":"on","x":0.8,"w":0.15,"auto":true}],"notes":[{"t":3.0,"light":0,"u":0.5,"kind":"tap","motion":{"type":"horizontal","x0":0.05,"begin":0.95,"end":1.0}}]}
	var scoped_chart:=scoped(raw); var core:=GameCore.new(scoped_chart.registry); core.load_chart(scoped_chart.chart_data); core.playing=true
	check(core.press_key("KeyA",2.925)==null and core.stats.judged==0,"key at visual-only x cannot hit remote original track")
	check(core.press_key("KeyL",2.925)!=null and core.stats.GREAT==1,"original track hits while note is still at remote visual x (75 ms early = GREAT under the 50/80 ms windows)")
	scoped_chart.close()
	var demo: Dictionary=fixture_chart.duplicate(true); var demo_session:=scoped(demo)
	core=GameCore.new(demo_session.registry); core.load_chart(demo_session.chart_data); core.playing=true
	core.press_key("KeyF",3.0)
	check(core.stats.PERFECT==1,"one chord press judges one note")
	core=GameCore.new(demo_session.registry); core.load_chart(demo_session.chart_data); core.playing=true; core.autoplay=true
	for i in int(ceil(core.end_time*240))+1: core.update(i/240.0)
	check(core.stats.MISS==0 and core.stats.PERFECT==3 and core.stats.score==1010000,"outward chord autoplay full score")
	print("MOTION_AUTOPLAY ",JSON.stringify(core.stats))
	demo_session.close()
