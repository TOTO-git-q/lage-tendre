## Opt-in shape syntax; old lights remain on the original code path.
extends RefCounted
const Geometry = preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Painter = preload("res://plugins/builtin/shape_tracks/render.gd")
const Hold = preload("res://plugins/builtin/shape_tracks/hold.gd")
const VERSION := "1.0.0"
static var _compiler_token := RefCounted.new()

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	registry.register("validators", "shape_tracks_prepare", {"order": -20,"callback": prepare})
	registry.register("validators", "shape_tracks_finish", {"order": 20,"callback": finish})
	registry.register("events", "shape_track", {"target": "lights","opens": true,"compile": compile_shape,"sample": sample_shape,"validate": validate_event})
	registry.register("events", "shape_track_cue", {"target":"lights","pedal":true,"cue_duration":true,"compile":compile_shape,"sample":sample_shape,"validate":validate_event})
	registry.register("events", "shape_track_end", {"target": "lights","closes": true,"compile": compile_end,"sample": sample_end,"validate": validate_end})
	registry.register("track_geometry", "shape", {"sections": sections,"note_state": note_state,"note_x": Geometry.note_x,"note_section": Geometry.note_section,"visual_transform":Geometry.visual_transform,"hold_plan":Hold.plan,"ribbon_mesh":Hold.mesh})
	registry.register("elements", "shape_surfaces", {"phase":"track","order":13,"additive":false,"callback":Painter.surfaces})
	registry.register("elements", "shape_edges", {"phase":"beam","order":20,"additive":true,"callback":Painter.edges})

static func declared(raw: Dictionary) -> bool:
	if not raw.get("plugins",[]) is Array: return false
	for plugin in raw.get("plugins", []):
		if plugin is Dictionary and plugin.get("id") == "shape_tracks" and PluginLoader.version_matches(VERSION,str(plugin.get("version",""))): return true
	return false

static func prepare(context: Dictionary) -> void:
	var raw = context.raw
	if raw is String: raw=JSON.parse_string(raw)
	if not raw is Dictionary or not raw.has("tracks"): return
	context["shape_tracks_warnings"] = []
	var warns: Array = context.shape_tracks_warnings
	if not declared(raw):
		warns.append("tracks: declare shape_tracks@1.0.0 in plugins to enable shapes"); return
	if not raw.tracks is Array or raw.tracks.size()>Geometry.MAX_TRACKS:
		warns.append("tracks: expected array of at most 64 tracks"); return
	if not raw.get("lights",[]) is Array:
		warns.append("lights: expected array"); context.raw=raw.duplicate(true); context.raw.lights=[]; return
	var budget:=Geometry.new_budget()
	var next: Dictionary=raw.duplicate(true)
	next["lights"] = next.get("lights", []).filter(func(e): return not (e is Dictionary and is_same(e.get("_shape_compiler"),_compiler_token)))
	context["shape_tracks"] = []
	var ids := {}
	for e in next.lights:
		if e is Dictionary and Geometry.valid_id(e.get("id")): ids[int(e.id)]=true
	for i in raw.tracks.size():
		var track=raw.tracks[i]; var tag := "tracks[%d]" % i
		if not track is Dictionary or not Geometry.valid_id(track.get("id")):
			warns.append(tag+": invalid id"); continue
		var id := int(track.id)
		if id > 2147483647: warns.append(tag+": id exceeds supported range"); continue
		if not track.get("charter",{}) is Dictionary or not track.get("charter",{}).get("lights",[]) is Array:
			warns.append(tag+": invalid charter metadata"); continue
		if not Geometry._take(budget,"metadata",track.get("charter",{}).get("lights",[]).size()):
			warns.append(tag+": original cue metadata budget exceeded"); continue
		var bad_cue := false
		for cue in track.get("charter",{}).get("lights",[]):
			if not cue is Dictionary or not Geometry.bounded(cue.get("t"),Geometry.MAX_TIME) or not Geometry.bounded(cue.get("dur",0.0),Geometry.MAX_TIME):
				bad_cue=true
			elif cue.get("from","LR") not in ["L","R","LR"] or not cue.get("auto",false) is bool: bad_cue=true
		if bad_cue: warns.append(tag+": invalid original cue metadata"); continue
		if ids.has(id): warns.append(tag+": id conflicts with another track or lights"); continue
		if track.get("geometry","shape") != "shape": warns.append(tag+": unsupported geometry"); continue
		if not track.get("shapes") is Array or track.shapes.is_empty(): warns.append(tag+": shapes must be a nonempty array"); continue
		var compiled := Geometry.prepare(track,budget)
		if not compiled.errors.is_empty(): warns.append_array(compiled.errors); continue
		if not is_finite(compiled.lo) or not is_finite(compiled.hi) or compiled.lo < 0 or compiled.hi-compiled.lo <= Geometry.EPS:
			warns.append(tag+": need a positive finite time span"); continue
		compiled["trapezoids"] = Geometry.trapezoids(compiled,budget)
		if not compiled.errors.is_empty(): warns.append_array(compiled.errors); continue
		ids[id]=true
		context.shape_tracks.append(track.duplicate(true))
		next.lights.append({"t":compiled.lo,"id":id,"type":"shape_track","dur":compiled.hi-compiled.lo,"shape":compiled,"_shape_compiler":_compiler_token,"auto":true})
		# Keep original pedal cues without running the old envelope geometry.
		var cues: Array=track.get("charter",{}).get("lights",[])
		if cues.is_empty():
			cues=[]
			for shape in track.shapes:
				cues.append_array(shape.get("pulses",[]))
				for time in shape.get("pins",{}):
					var pin: Dictionary=shape.pins[time].duplicate(true)
					pin["t"]=float(time); pin["type"]="on"; cues.append(pin)
		for cue in cues:
			if cue.get("type","") == "off" or cue.get("auto",false): continue
			var ct := float(cue.get("t",compiled.lo))
			if ct < compiled.lo or ct >= compiled.hi: continue
			next.lights.append({"t":ct,"id":id,"type":"shape_track_cue","dur":float(cue.get("dur",0.0)) if cue.get("type","")=="sweep" else 0.0,"shape":compiled,"_shape_compiler":_compiler_token,"from":cue.get("from","LR"),"auto":false})
		next.lights.append({"t":compiled.hi,"id":id,"type":"shape_track_end","_shape_compiler":_compiler_token,"auto":true})
	context.raw=next

static func finish(context: Dictionary) -> void:
	if context.chart.is_empty(): return
	if context.has("shape_tracks_warnings"): context.chart.warnings.append_array(context.shape_tracks_warnings)
	if context.has("shape_tracks"):
		context.chart["tracks"]=context.shape_tracks
		context.chart["plugins"]=context.raw.get("plugins",[]).duplicate(true)
		var ids := {}
		for track in context.shape_tracks: ids[int(track.id)]=true
		var prepared := {}
		for event in context.chart.lights:
			if event.type == "shape_track": prepared[event.id]=event.shape
		var retained := []
		for note in context.chart.notes:
			if ids.has(int(note.light)):
				note["geometry"]="shape"
				var shape: Dictionary=prepared[note.light]
				var spans := []
				for trap in shape.trapezoids: spans.append([trap.t0,trap.t1])
				var covered := false
				for span in Geometry.union(spans):
					if note.t >= span[0]-1e-9 and note.t+note.dur <= span[1]+1e-9: covered=true; break
				if not covered or Geometry.sections(shape,note.t).is_empty():
					context.chart.warnings.append("shape note at %s crosses an empty lifetime" % note.t); continue
			retained.append(note)
		context.chart.notes=retained

static func validate_event(context: Dictionary) -> void:
	# Compiler-only payloads cannot be authored as an alternate public light syntax.
	if not is_same(context.raw.get("_shape_compiler"),_compiler_token):
		context.warnings.append(context.tag+": shape_track is an internal compiled event"); return
	context.chart.lights.append(context.raw)

static func validate_end(context: Dictionary) -> void:
	if not is_same(context.raw.get("_shape_compiler"),_compiler_token):
		context.warnings.append(context.tag+": shape_track_end is an internal compiled event"); return
	context.chart.lights.append(context.raw)

static func compile_shape(context: Dictionary) -> void:
	context.segments.append(context.event)

static func compile_end(context: Dictionary) -> void:
	context.segments.append(context.event)

static func sample_shape(segment: Dictionary,t: float) -> Dictionary:
	var state := Geometry.sample(segment.shape,t)
	if segment.type == "shape_track_cue": state.pulse=maxf(0.0,1.0-(t-segment.t)/0.25)
	return state

static func sample_end(_segment: Dictionary,_t: float) -> Dictionary:
	return ChartLib.DEAD

static func sections(state: Dictionary) -> Array:
	return state.get("sections", []) if state.get("alive",false) else []

static func note_state(renderer,note: Dictionary,_state: Dictionary) -> Dictionary:
	# Shape time is also note depth: sample the note's landing slice, not the
	# current judgement slice. A future shape is visible before it reaches the line.
	return renderer._light_at(renderer.f.tl.get(note.light,[]),note.t)
