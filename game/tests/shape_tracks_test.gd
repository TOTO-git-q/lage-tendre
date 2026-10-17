## Preparatory P3 focused checks. Full P0 gate remains a separate parent step.
extends SceneTree
const Geometry = preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Converter = preload("res://plugins/builtin/shape_tracks/converter.gd")
const Shape = preload("res://scripts/chart_models/track_shape.gd")
const Adapter = preload("res://scripts/chart_models/track_adapter.gd")
const Painter = preload("res://plugins/builtin/shape_tracks/render.gd")
var scope: PluginRegistry
var checks := 0
var failures := 0
var songs_root := ProjectSettings.globalize_path("res://../songs")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL: "+label)

func _validate(raw) -> Dictionary: return ChartLib.validate(raw,scope)

func close(a: float,b: float,tol:=1e-7) -> bool: return absf(a-b) <= tol

func rect(x0: float,x1: float,t0: float,t1: float) -> Dictionary:
	return {"nodes":[[x0,t0],[x1,t0],[x1,t1],[x0,t1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}

func track(shapes: Array,id:=0) -> Dictionary: return {"id":id,"geometry":"shape","shapes":shapes}

func chart(tracks: Array,notes: Array) -> Dictionary:
	return {"bpm":120,"offset":0,"plugins":[{"id":"shape_tracks","version":"1.0.0"}],"lights":[],"tracks":tracks,"notes":notes,"meta":{"stage":"off"}}

func note(t: float,u:=0.5,id:=0) -> Dictionary: return {"t":t,"light":id,"u":u,"kind":"tap"}

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--songs-root="): songs_root=argument.trim_prefix("--songs-root=")
	KB.set_layout("ansi")
	scope=PluginRegistry.new()
	var paths := []
	for id in ["standard_chart","standard_stage","standard_rules","standard_render","shape_tracks"]:
		paths.append("res://plugins/builtin/"+id+"/plugin.json")
	var loaded := PluginLoader.new().load_paths(paths,scope,true)
	check(loaded.errors.is_empty(),"explicit chart-scoped built-in selection")
	_test_sections()
	_test_curves()
	_test_converter()
	_test_game()
	_test_render_mesh()
	_test_validation()
	_test_budgets()
	print("SHAPE TRACKS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func _test_sections() -> void:
	var r := Geometry.prepare(track([rect(0.1,0.9,1,3)]))
	for t in [1.0,1.001,2.0,2.999]:
		var s := Geometry.sections(r,t)
		check(s.size()==1 and close(s[0][0],0.1) and close(s[0][1],0.9),"rectangle interior/lower boundary %s" % t)
	for t in [0.999,3.0,3.1,NAN,INF]: check(Geometry.sections(r,t).is_empty(),"outside and non-finite are empty")
	var with_hole := rect(0.1,0.9,1,3); with_hole["holes"]=[rect(0.4,0.6,1.5,2.5)]
	var multi := Geometry.prepare(track([with_hole,rect(0.8,1.0,1,3)]))
	var split := Geometry.sections(multi,2.0)
	check(split.size()==2 and close(split[0][0],0.1) and close(split[0][1],0.4) and close(split[1][0],0.6) and close(split[1][1],1.0),"component union with explicit hole")
	check(Geometry.sections(multi,1.4).size()==1,"hole lower lifetime boundary")
	check(Geometry.sections(multi,2.5).size()==1,"hole upper boundary excluded")
	var fill_hole := Geometry.prepare(track([with_hole,rect(0.45,0.55,1,3)]))
	check(Geometry.sections(fill_hole,2).size()==3,"another component can refill a hole")
	var unioned := Geometry.union([[0.3,0.5],[0.1,0.3],[0.2,0.4],[0.8,0.9],[NAN,1.0],[0.7,0.7]])
	check(unioned.size()==2 and close(unioned[0][0],0.1) and close(unioned[0][1],0.5),"sorted union merges touching/overlapping intervals")
	var degenerate := Geometry.prepare(track([{"nodes":[[0.2,1],[0.3,1],[0.4,1]],"segs":[["linear"],["linear"],["linear"]]}]))
	check(Geometry.sections(degenerate,1).is_empty(),"horizontal degenerate outline is empty")
	var bow := {"nodes":[[0.1,1],[0.9,3],[0.1,3],[0.9,1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
	var selfcross := Geometry.prepare(track([bow]))
	check(Geometry.sections(selfcross,2).is_empty(),"self-crossing tangent vertex has zero width")
	check(Geometry.sections(selfcross,1.5).size()==1,"self-crossing outline even-odd fill")
	var duplicate := rect(0.1,0.9,1,3); duplicate.nodes.insert(1,[0.1,1]); duplicate.segs.insert(1,["linear"])
	check(Geometry.sections(Geometry.prepare(track([duplicate])),2)==Geometry.sections(r,2),"repeated vertex does not change fill")

func _test_curves() -> void:
	for ease in ["linear","in","out","inout"]:
		var s = Shape.preset("rect",0.1,0.8,1.0,5.0)
		s.nodes[1].x=0.35; s.nodes[2].x=0.95
		s.segs[0].ease=ease; s.segs[2].ease=ease
		var p := Geometry.prepare(track([s.to_dict()]))
		for k in 21:
			var f := k/21.0; var t := 1+4*f
			var iv := Geometry.sections(p,t)
			check(iv.size()==1 and close(iv[0][0],0.1+0.25*SU.ease_by(ease,f)) and close(iv[0][1],0.8+0.15*SU.ease_by(ease,f)),"exact charter named ease including reversed edge "+ease)
	var heart = Shape.preset("heart",0.08,0.92,2.0,6.0); heart.id=1
	var prepared := Geometry.prepare(track([heart.to_dict()],1))
	check(Geometry.sections(prepared,5.6).size()==2,"cubic heart has separate lobes above cleft")
	for k in 81:
		var st := Geometry.sample(prepared,1.99+k*0.051)
		check(is_finite(st.x) and is_finite(st.w) and is_finite(st.alpha),"heart finite over tangent and endpoints")
	# A cubic edge folds back in time; roots must include all monotone branches.
	var loop := {"nodes":[[0.1,1],[0.9,1],[0.5,4]],"segs":[["bezier",0.3,5,0.7,-1],["linear"],["linear"]]}
	var lp := Geometry.prepare(track([loop]))
	check(lp.lo < 1 or lp.hi > 4 or lp.components[0].edges[0].turns.size()==4,"independent cubic time extrema retained")
	for k in 50:
		for iv in Geometry.sections(lp,k*0.1): check(is_finite(iv[0]) and is_finite(iv[1]) and iv[1]>iv[0],"folded cubic finite ordered intervals")
	# Custom cubic's extrema occur at t=2.5. A tangent never creates a spurious area.
	var cap := {"nodes":[[0.1,1],[0.9,1],[0.5,0]],"segs":[["bezier",0.2,3,0.8,3],["linear"],["linear"]]}
	var cp := Geometry.prepare(track([cap]))
	check(close(cp.hi,2.5) and Geometry.sections(cp,2.5).is_empty(),"cubic maximum is excluded exactly")
	check(Geometry.sections(cp,2.5-1e-7).size()==1,"arbitrarily near tangent remains a real interval")

func _test_converter() -> void:
	var star=Shape.preset("star",0.06,0.94,1.0,5.0); star.id=3
	star.props=[{"t":1.0,"a":0.8,"tint":2},{"t":5.0,"a":0.4,"tint":5}]
	star.pins={"1.000000":{"auto":true,"flash":0.6}}; star.keep={"3.000000":true}
	star.pulses=[{"t":3.0,"id":3,"type":"pulse","from":"LR","auto":true}]
	star.off_extra={"custom":"preserve"}; star.open_end=false
	var events: Array=Adapter.to_events(star,{"a":-1.0,"tint":-1}).events
	var record := {"signature":Adapter.signature(events),"shapes":[star.to_dict()],"approximated":true,"reason":"星形"}
	var base := {"bpm":120,"lights":events,"notes":[note(3,0.5,3)]}
	var side := {"about":"charter fixture","shapes":{"3":record},"motions":{"3.000000|3|-1":{"type":"horizontal","params":{"from":3.0,"begin":0.0,"end":70.0,"ease":"inout"}}}}
	var converted := Converter.from_sidecar(base,side)
	check(converted.errors.is_empty(),"actual charter sidecar imports")
	if not converted.errors.is_empty(): return
	check(converted.chart.tracks[0].shapes[0]==star.to_dict(),"all actual TrackShape fields are lossless")
	check(converted.chart.lights.is_empty() and converted.chart.notes==base.notes,"only approximate track events replaced; note references unchanged")
	check(converted.sidecar.motions==side.motions and converted.sidecar.shapes.is_empty(),"unrelated note motions survive")
	var exported := Converter.to_sidecar(converted.chart,converted.sidecar)
	check(exported.errors.is_empty(),"formal chart exports into current charter")
	check(exported.sidecar==side,"sidecar exact value roundtrip including signature/extras")
	check(Adapter.signature(exported.chart.lights)==Adapter.signature(base.lights),"original approximating events exact signature roundtrip")
	check(Shape.from_dict(converted.chart.tracks[0].shapes[0]).to_dict()==star.to_dict(),"unmodified charter model reads canonical shape")
	var disk_base=SU.load_json(songs_root.path_join("_plugin_demos/shapes/charter.chart.json"))
	var disk_side=SU.load_json(songs_root.path_join("_plugin_demos/shapes/chart.ext.json"))
	check(disk_base is Dictionary and disk_side is Dictionary,"serialized charter fixture files are required")
	if disk_base is Dictionary and disk_side is Dictionary:
		var disk := Converter.from_sidecar(disk_base,disk_side)
		check(disk.errors.is_empty(),"serialized actual charter fixture imports")
		if disk.errors.is_empty():
			var reverse := Converter.to_sidecar(disk.chart,disk.sidecar)
			check(reverse.errors.is_empty() and reverse.sidecar==disk_side,"serialized fixture roundtrip remains exact")
	var stale := side.duplicate(true); stale.shapes["3"].signature="stale"
	check(not Converter.from_sidecar(base,stale).errors.is_empty(),"stale sidecar fails closed")
	var edited := base.duplicate(true); edited.lights[0].x+=0.01
	check(not Converter.from_sidecar(edited,side).errors.is_empty(),"signature repair never accepts changed numeric geometry")
	check(base.lights==events and side.shapes["3"]==record,"converter never mutates inputs")
	# Checked-in fixtures come from this actual adapter, not a second invented schema.
	if OS.get_cmdline_user_args().has("--write-fixtures"):
		SU.save_json(songs_root.path_join("_plugin_demos/shapes/charter.chart.json"),base)
		SU.save_json(songs_root.path_join("_plugin_demos/shapes/chart.ext.json"),side)
		SU.save_json(songs_root.path_join("_plugin_demos/shapes/converted.chart.json"),converted.chart)

func star_info() -> Dictionary:
	var star=Shape.preset("star",0.02,0.98,2.0,6.0); star.id=0
	star.props=[{"t":2.0,"a":1.0,"tint":3}]
	var tr := track([star.to_dict()]); var p := Geometry.prepare(tr)
	for i in 400:
		var t := 2+i*0.01; var iv := Geometry.sections(p,t)
		if iv.size()!=2: continue
		var left := ""; var right := ""; var gap := ""
		for k in KB.list:
			if k.row != 2: continue
			if k.cx > iv[0][0] and k.cx < iv[0][1]: left=k.code
			if k.cx > iv[1][0] and k.cx < iv[1][1]: right=k.code
			var k0: float=k.x0/15.0-SU.KEY_PAD; var k1: float=(k.x0+k.w)/15.0+SU.KEY_PAD
			if k0 > iv[0][1] and k1 < iv[1][0]: gap=k.code
		if left!="" and right!="" and gap!="": return {"track":tr,"prepared":p,"t":t,"left":left,"right":right,"gap":gap,"sections":iv}
	return {}

func _test_game() -> void:
	var info := star_info()
	check(not info.is_empty(),"star has two reachable disconnected home-key intervals")
	if info.is_empty(): return
	print("STAR_SECTIONS t=",info.t," intervals=",info.sections," keys=",info.left,",",info.right," gap=",info.gap)
	for key in [info.left,info.right]:
		var core := GameCore.new(scope); var raw := chart([info.track],[note(info.t)])
		check(core.load_chart(raw) and core.notes.size()==1 and core.chart.warnings.is_empty(),"shape loads with shared notes.light")
		core.playing=true
		var hit=core.press_key(key,info.t)
		check(hit!=null and core.stats.PERFECT==1 and core.stats.MISS==0,"real GameCore key reaches either star interval "+key)
		check(core.light_states(info.t,1.0)[0].get("geometry","")=="shape","shape metadata reaches renderer")
	var hole_press := GameCore.new(scope)
	hole_press.load_chart(chart([info.track],[note(info.t)])); hole_press.playing=true
	check(hole_press.press_key(info.gap,info.t)==null and hole_press.stats.judged==0,"press wholly inside star gap cannot hit envelope")
	var twin := GameCore.new(scope)
	twin.load_chart(chart([info.track],[note(info.t,0.0),note(info.t,1.0)])); twin.playing=true
	check(twin.notes.size()==2,"star chord retains two notes")
	twin.press_key(info.left,info.t)
	check(twin.stats.PERFECT==1,"one physical press judges one note")
	twin.press_key(info.right,info.t)
	check(twin.stats.PERFECT==2,"second physical press judges second note")
	check(twin._runtime._one_key_reaches_sections([[0.0,0.1],[0.8,0.9]],[[0.4,0.5],[0.8,0.9]]),"midpoint overlap considers second section")
	var heart=Shape.preset("heart",0.08,0.92,7.0,11.0); heart.id=1; heart.props=[{"t":7.0,"a":0.9,"tint":4}]
	heart.segs[0]={"ease":"bezier","h1":Vector2(0.58,7.8),"h2":Vector2(0.92,8.2)}
	heart.segs[5]={"ease":"bezier","h1":Vector2(0.08,8.2),"h2":Vector2(0.42,7.8)}
	var notes := [note(3.0),note(3.5),note(4.0),note(info.t,0.0),note(info.t,1.0),note(8.0,0.5,1),note(8.5,0.5,1),note(9.0,0.3,1),note(10.3,0.15,1),note(10.3,0.85,1)]
	var demo := chart([info.track,track([heart.to_dict()],1)],notes)
	demo["title"]="Star and heart"; demo["audio"]="audio.wav"
	var core := GameCore.new(scope); core.load_chart(demo); core.playing=true; core.autoplay=true
	for i in int(ceil(core.end_time*240))+1: core.update(i/240.0)
	check(core.stats.MISS==0 and core.stats.score==1010000 and core.stats.PERFECT==notes.size(),"star + cubic-heart autoplay full score")
	print("SHAPE_AUTOPLAY ",JSON.stringify(core.stats))
	if OS.get_cmdline_user_args().has("--write-fixtures"): SU.save_json(songs_root.path_join("_plugin_demos/shapes/chart.json"),demo)

func _test_render_mesh() -> void:
	var info := star_info()
	if info.is_empty(): return
	var prepared: Dictionary=info.prepared
	prepared["trapezoids"]=Geometry.trapezoids(prepared)
	var renderer := BuiltinRendererRuntime.new()
	renderer.configure(scope); renderer.f={"t":3.8,"fall":2.5,"reach":1.0}; renderer.S=StageFx.rest(); renderer.G=renderer._geo()
	var data := Painter.mesh(renderer,prepared)
	check(data.indices.size()>30 and data.points.size()==data.plane.size(),"shape tessellates in x/s before curved field mapping")
	var finite := true
	for p in data.points:
		if not is_finite(p.x) or not is_finite(p.y): finite=false
	check(finite,"all mapped visual vertices finite")
	check(data.points.size()>prepared.components[0].source.nodes.size()*8,"nonlinear field edges subdivided")
	# Mesh triangle centroids must never cover a shape hole or separated gap.
	var safe := true
	for i in range(0,data.indices.size(),3):
		var ids := [data.indices[i],data.indices[i+1],data.indices[i+2]]
		var x := 0.0; var t := 0.0
		for index in ids: x+=data.plane[index].x/3.0; t+=data.times[index]/3.0
		var inside := false
		for iv in Geometry.sections(prepared,t):
			if x >= iv[0]-0.0001 and x <= iv[1]+0.0001: inside=true
		if not inside: safe=false; break
	check(safe,"triangulation leaves star concavities empty")
	renderer.free()

func _test_validation() -> void:
	var raw := chart([track([rect(0.1,0.9,1,3)])],[note(2)])
	var valid := _validate(raw)
	check(valid.notes.size()==1 and valid.warnings.is_empty(),"minimal shape chart validates")
	check(_validate(valid).notes.size()==1,"validated chart can be reloaded without duplicate internal events")
	for kind in ["shape_track","shape_track_cue","shape_track_end"]:
		var authored := {"plugins":[{"id":"shape_tracks","version":"1.0.0"}],"lights":[{"t":1.0,"id":0,"type":kind,"shape":{"components":[null]},"_shape_compiler":{}}],"notes":[]}
		var blocked := _validate(authored)
		check(blocked.lights.is_empty() and not blocked.warnings.is_empty(),"JSON cannot forge internal compiler event "+kind)
	for invalid in [{"pins":[]},{"pins":{"2.0":2}},{"props":{}},{"props":[{"t":1.0}]},{"props":[{"t":1.0,"a":INF,"tint":0}]},{"holes":3},{"holes":[{"nodes":[],"segs":[],"holes":3}]},{"pulses":[false]},{"open_end":[]},{"keep":3}]:
		var malformed := raw.duplicate(true); malformed.tracks[0].shapes[0].merge(invalid,true); malformed.notes=[]
		var rejected := _validate(malformed)
		check(rejected.lights.is_empty() and not rejected.warnings.is_empty(),"malformed shape metadata rejected "+str(invalid.keys()))
	var undeclared := raw.duplicate(true); undeclared.erase("plugins")
	check(_validate(undeclared).notes.is_empty(),"shape syntax is opt-in even while P1 autoloads manifests")
	var bad := raw.duplicate(true); bad.tracks[0].shapes[0].nodes[1][0]=NAN
	check(not _validate(bad).warnings.is_empty(),"non-finite shape rejected without NaN state")
	var conflict := raw.duplicate(true); conflict.lights=[{"t":1.0,"id":0,"type":"on","x":0.5,"w":0.8,"auto":true}]
	check(not _validate(conflict).warnings.is_empty(),"lane/shape identity collision is reported")
	var gap := chart([track([rect(0.1,0.9,1,2),rect(0.1,0.9,3,4)])],[{"t":1.5,"light":0,"u":0.5,"kind":"hold","dur":2.0}])
	check(_validate(gap).notes.is_empty(),"hold cannot cross a disconnected lifetime")
	var cue_shape := rect(0.1,0.9,1,3); cue_shape["pins"]={"1.000000":{"from":"L","auto":false}}
	var cues := GameCore.new(scope); cues.load_chart(chart([track([cue_shape])],[note(2)]))
	check(cues.cues.size()==1 and cues.cues[0].from=="L","charter pin retains its pedal cue")
	var legacy := {"lights":[{"t":1.0,"id":0,"type":"on","x":0.5,"w":0.8,"auto":true}],"notes":[note(2)]}
	var clean := _validate(legacy)
	check(not clean.has("tracks") and not clean.notes[0].has("geometry"),"old lane chart gains no shape state")

func _test_budgets() -> void:
	for field in ["x","time","handle_x","handle_time"]:
		var shape:=rect(0.1,0.9,1,3)
		if field=="x": shape.nodes[0][0]=1e308
		if field=="time": shape.nodes[0][1]=1e308
		if field.begins_with("handle"):
			shape.segs[0]=["bezier",0.2,1.0,0.8,1.0]; shape.segs[0][1 if field=="handle_x" else 2]=1e308
		var p:=Geometry.prepare(track([shape]))
		check(not p.errors.is_empty() and p.components.is_empty(),"finite overflow-scale "+field+" rejected before coefficients")
		var parsed:=_validate(chart([track([shape])],[]))
		check(parsed.lights.is_empty() and not parsed.warnings.is_empty(),"overflow-scale chart has diagnostic and no compiled event")
	check(Geometry._turns([1e308,1e308,1e308,1e308]).is_empty(),"non-finite derived derivative/discriminant fails closed")
	var wide:=Geometry.prepare(track([rect(-8,8,0,86400)]))
	check(wide.errors.is_empty() and Geometry.sections(wide,43200)==[[-8.0,8.0]],"documented broad coordinate bounds remain valid")
	var dense:=rect(0.1,0.9,1,3)
	for i in Geometry.MAX_PATH_NODES: dense.nodes.append([0.1,1.0]); dense.segs.append(["linear"])
	check(not Geometry.prepare(track([dense])).errors.is_empty(),"node budget rejects before edge compilation")
	var many:=[]
	for i in Geometry.MAX_COMPONENTS+1: many.append(rect(0.1,0.9,1,3))
	check(not Geometry.prepare(track(many)).errors.is_empty(),"component budget rejected")
	var holes:=rect(0.1,0.9,1,3); holes.holes=[]
	for i in Geometry.MAX_HOLES+1: holes.holes.append(rect(0.3,0.4,1.5,2.5))
	check(not Geometry.prepare(track([holes])).errors.is_empty(),"hole budget rejected")
	var large:=rect(0.1,0.9,1,3)
	while large.nodes.size()<Geometry.MAX_PATH_NODES: large.nodes.append([0.1,1.0]); large.segs.append(["linear"])
	var global:=Geometry.new_budget()
	check(not Geometry.prepare(track([large,large,large,large,large]),global).errors.is_empty(),"aggregate node budget includes all components")
	var demo: Dictionary=SU.load_json(songs_root.path_join("_plugin_demos/shapes/chart.json"))
	var heart: Dictionary=demo.tracks[1].shapes[0]
	var excessive:=Geometry.prepare(track([heart,heart,heart]))
	check(Geometry.trapezoids(excessive).is_empty() and not excessive.errors.is_empty() and not excessive.has("visual_edge_count"),"flattened edge budget rejects before quadratic sweep")
	for key in ["edges","pairs","sweep","mesh_vertices"]:
		var budget:=Geometry.new_budget(); budget[key]=Geometry.LIMITS[key]
		var p:=Geometry.prepare(track([rect(0.1,0.9,1,3)]),budget)
		check(Geometry.trapezoids(p,budget).is_empty() and not p.errors.is_empty(),"shared chart budget bounds "+key)
	var budget:=Geometry.new_budget()
	for t in demo.tracks:
		var p:=Geometry.prepare(t,budget); var mesh:=Geometry.trapezoids(p,budget)
		check(p.errors.is_empty() and not mesh.is_empty(),"real demo stays within aggregate limits")
		print("SHAPE_BUDGET id=",t.id," edges=",p.visual_edge_count," traps=",mesh.size()," vertex_bound=",p.mesh_vertex_bound)
	print("SHAPE_BUDGET_TOTAL ",JSON.stringify(budget))
	for bad in [{"tracks":{}},{"tracks":[null]},{"tracks":[{"id":{}}]},{"lights":3},{"lights":[null]},{"lights":[{"id":{},"t":1}]},{"plugins":[null]}]:
		check(not Converter.from_sidecar(bad,{}).errors.is_empty(),"forward converter rejects malformed containers "+str(bad))
		check(not Converter.to_sidecar(bad).errors.is_empty(),"reverse converter rejects malformed containers "+str(bad))
	for side in [{"shapes":[]},{"motions":[]},{"shapes":{"0":null}}]:
		check(not Converter.from_sidecar({"lights":[],"notes":[]},side).errors.is_empty(),"converter rejects malformed sidecar object")
	var bad_meta: Dictionary=demo.duplicate(true); bad_meta.tracks[0].charter={"record":[],"lights":{}}
	check(not Converter.to_sidecar(bad_meta).errors.is_empty(),"reverse converter rejects malformed cached record")
	var invalid_lights:=chart([track([rect(0.1,0.9,1,3)])],[]); invalid_lights.lights=3
	check(not _validate(invalid_lights).warnings.is_empty(),"shape prepare safely rejects non-array lights")
