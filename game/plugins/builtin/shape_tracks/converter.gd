## Actual charter chart.ext.json adapter. This is deliberately read-only with
## respect to charter/. Shapes retain every TrackShape.to_dict field verbatim.
extends RefCounted
const Geometry = preload("res://plugins/builtin/shape_tracks/geometry.gd")
const Shape = preload("res://scripts/chart_models/track_shape.gd")
const Adapter = preload("res://scripts/chart_models/track_adapter.gd")

static func input_errors(chart: Dictionary,sidecar: Dictionary) -> Array:
	for key in ["tracks","lights","plugins"]:
		if not chart.get(key,[]) is Array: return [key+" must be an array"]
	for key in ["shapes","motions"]:
		if not sidecar.get(key,{}) is Dictionary: return ["sidecar "+key+" must be an object"]
	if chart.get("tracks",[]).size()>Geometry.MAX_TRACKS: return ["too many shape tracks"]
	for light in chart.get("lights",[]):
		if not light is Dictionary or not Geometry.valid_id(light.get("id")) or not Geometry.bounded(light.get("t"),Geometry.MAX_TIME): return ["Malformed legacy light"]
	for plugin in chart.get("plugins",[]):
		if not plugin is Dictionary or not plugin.get("id") is String or not plugin.get("version") is String: return ["Malformed plugin requirement"]
	var budget:=Geometry.new_budget(); var ids:={}
	for track in chart.get("tracks",[]):
		if not track is Dictionary or not Geometry.valid_id(track.get("id")): return ["Malformed track identity"]
		if ids.has(int(track.id)): return ["Duplicate track identity"]
		ids[int(track.id)]=true
		if not track.get("charter",{}) is Dictionary: return ["charter metadata must be an object"]
		var original: Dictionary=track.get("charter",{})
		if not original.get("lights",[]) is Array or not original.get("record",{}) is Dictionary: return ["Malformed original charter record"]
		for light in original.get("lights",[]):
			if not light is Dictionary or not Geometry.valid_id(light.get("id")) or not Geometry.bounded(light.get("t"),Geometry.MAX_TIME): return ["Malformed original charter light"]
		if track.get("geometry","shape")!="shape": continue
		var prepared:=Geometry.prepare(track,budget)
		if not prepared.errors.is_empty(): return prepared.errors
		Geometry.trapezoids(prepared,budget)
		if not prepared.errors.is_empty(): return prepared.errors
	return []

## Godot JSON parses every number as float. The current editor hashes integer
## id/tint values before saving, so its valid on-disk signature may otherwise
## fail after reload. Rehydrate only the two integer fields the adapter emits;
## never ignore the signature or repair changed numeric values.
static func signature_matches(events: Array, expected: String) -> bool:
	if Adapter.signature(events) == expected: return true
	var typed := events.duplicate(true)
	for include_pulses in [false,true]:
		for event in typed:
			if event.get("type", "") == "pulse" and not include_pulses: continue
			for key in ["id","tint"]:
				if event.has(key) and Geometry.finite_number(event[key]) and float(event[key]) == floor(float(event[key])): event[key]=int(event[key])
		if Adapter.signature(typed) == expected: return true
	return false

static func from_sidecar(chart: Dictionary, sidecar: Dictionary) -> Dictionary:
	var invalid:=input_errors(chart,sidecar)
	if not invalid.is_empty(): return {"errors":invalid}
	var out := chart.duplicate(true); var remaining := sidecar.duplicate(true); var errors := []; var migrated := []
	if sidecar.get("shapes",{}).size()>Geometry.MAX_TRACKS: return {"errors":["sidecar shape track count exceeds 64"]}
	var tracks: Array=out.get("tracks",[]).duplicate(true)
	var used := {}
	for track in tracks: used[int(track.id)]=true
	for key in sidecar.get("shapes",{}):
		var record=sidecar.shapes[key]
		if not str(key).is_valid_int() or not Geometry.valid_id(float(key)) or not record is Dictionary:
			errors.append("Invalid shape sidecar entry: "+str(key)); continue
		var id := int(key); var events := []
		for e in chart.get("lights",[]):
			if int(e.get("id",-1)) == id: events.append(e)
		if not signature_matches(events,str(record.get("signature",""))):
			errors.append("Stale shape signature for track %d; no geometry replaced" % id); continue
		if used.has(id): errors.append("Track ID already present: %d" % id); continue
		if not record.get("shapes") is Array or record.shapes.is_empty() or record.shapes.size()>Geometry.MAX_COMPONENTS: errors.append("Missing shapes for track %d" % id); continue
		var issues := []
		for shape in record.shapes:
			issues.append_array(Geometry.validate_path(shape))
			if shape is Dictionary and shape.get("id",id) != id: issues.append("Sidecar shape ID mismatch")
		if not issues.is_empty(): errors.append_array(issues); continue
		# Preserve original approximating events for a byte-value-exact reverse
		# conversion. They are editor metadata and never run alongside the shape.
		tracks.append({"id":id,"geometry":"shape","shapes":record.shapes.duplicate(true),"charter":{"record":record.duplicate(true),"lights":events.duplicate(true)}})
		used[id]=true; migrated.append(id)
	if not errors.is_empty(): return {"errors":errors}
	out["lights"] = chart.get("lights",[]).filter(func(e): return int(e.get("id",-1)) not in migrated)
	if not tracks.is_empty(): out["tracks"]=tracks
	var plugins: Array=out.get("plugins",[]).duplicate(true); var found := false
	for plugin in plugins:
		if plugin.get("id","") == "shape_tracks":
			found=true
			if not PluginLoader.version_matches("1.0.0",str(plugin.get("version",""))): return {"errors":["Existing shape_tracks version is incompatible"]}
	if not migrated.is_empty() and not found: plugins.append({"id":"shape_tracks","version":"1.0.0"})
	if not plugins.is_empty(): out["plugins"]=plugins
	invalid=input_errors(out,remaining)
	if not invalid.is_empty(): return {"errors":invalid}
	for id in migrated: remaining.shapes.erase(str(id))
	return {"chart":out,"sidecar":remaining,"migrated":migrated,"errors":[]}

static func to_sidecar(chart: Dictionary, sidecar: Dictionary = {}) -> Dictionary:
	var invalid:=input_errors(chart,sidecar)
	if not invalid.is_empty(): return {"errors":invalid}
	var out := chart.duplicate(true); var side := sidecar.duplicate(true); var errors := []; var retained := []
	if not side.has("shapes"): side["shapes"]={}
	if not side.has("motions"): side["motions"]={}
	var lights: Array=out.get("lights",[]).duplicate(true)
	for track in chart.get("tracks",[]):
		if track.get("geometry","shape") != "shape": retained.append(track); continue
		var id := int(track.id)
		for e in lights:
			if int(e.get("id",-1)) == id: errors.append("Track conflicts with legacy light ID %d" % id)
		var events := []; var record := {}; var original: Dictionary=track.get("charter",{})
		if original.has("record") and original.record.get("shapes",[]) == track.shapes:
			if not original.has("lights") or not signature_matches(original.lights,str(original.record.get("signature",""))):
				errors.append("Stale original charter record"); continue
			events=original.lights.duplicate(true); record=original.record.duplicate(true)
		else:
			var inherit := {"a":-1.0,"tint":-1}
			for shape in track.shapes:
				if not shape.get("holes",[]).is_empty(): errors.append("The current charter cannot serialize holes losslessly; keep the formal tracks field"); continue
				var converted: Dictionary=Adapter.to_events(Shape.from_dict(shape),inherit)
				events.append_array(converted.events); inherit=converted.final
			record={"signature":Adapter.signature(events),"shapes":track.shapes.duplicate(true),"approximated":true,"reason":"Closed shape track"}
		lights.append_array(events); side.shapes[str(id)]=record
	if not errors.is_empty(): return {"errors":errors}
	lights.sort_custom(func(a,b): return a.t < b.t if a.t != b.t else a.id < b.id)
	out["lights"]=lights
	if retained.is_empty(): out.erase("tracks")
	else: out.tracks=retained
	if out.has("plugins"):
		out.plugins=out.plugins.filter(func(p): return p.get("id","") != "shape_tracks")
		if out.plugins.is_empty(): out.erase("plugins")
	return {"chart":out,"sidecar":side,"errors":[]}
