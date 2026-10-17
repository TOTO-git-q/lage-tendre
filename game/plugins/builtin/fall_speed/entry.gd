## Optional renderer service; standard scopes never enter the scroll implementation.
extends RefCounted
const Profile=preload("res://plugins/builtin/fall_speed/profile.gd")
const Runtime=preload("res://plugins/builtin/fall_speed/renderer.gd")
static func install(registry: PluginRegistry,_manifest: Dictionary,_folder: String) -> void:
	registry.register_service("renderer",Runtime,true)
	registry.register("validators","fall_speed",{"order":40,"callback":validate})

static func validate(context: Dictionary) -> void:
	if context.chart.is_empty(): return
	var raw=context.raw
	if raw is String: raw=JSON.parse_string(raw)
	if not raw is Dictionary: return
	var warns: Array=context.chart.warnings; var tracks:=[]; var speeds:={}; var events:=[]; var ids:={}
	for event in context.chart.lights: ids[int(event.id)]=true
	var source_tracks=raw.get("track_speeds",[])
	if not source_tracks is Array or source_tracks.size()>Profile.MAX_TRACKS:
		warns.append("track_speeds must be an array of at most 1024 entries"); source_tracks=[]
	for item in source_tracks:
		if not item is Dictionary or not Profile.finite(item.get("id")) or float(item.id)<0 or float(item.id)>2147483647 or float(item.id)!=floorf(float(item.id)) or not Profile.valid_speed(item.get("speed",1.0)):
			warns.append("track_speeds requires a valid ID and speed in [0.05,8]; entry ignored"); continue
		var id:=int(item.id)
		if not ids.has(id) or speeds.has(id): warns.append("Unknown or duplicate track_speeds ID: "+str(id)); continue
		speeds[id]=float(item.get("speed",1.0)); tracks.append({"id":id,"speed":speeds[id]})
	var source_events=raw.get("sv",[])
	if not source_events is Array or source_events.size()>Profile.MAX_EVENTS:
		warns.append("sv must be an array of at most 1024 events"); source_events=[]
	for item in source_events:
		if not item is Dictionary or not Profile.finite(item.get("t")) or not Profile.valid_speed(item.get("speed")) or not Profile.finite(item.get("dur",0.0)) or item.get("ease","linear") not in SU.EASES:
			warns.append("Invalid SV fields; event ignored"); continue
		var t:=float(item.t); var dur:=float(item.get("dur",0.0))
		if t<0 or dur<0 or t+dur>Profile.MAX_TIME: warns.append("SV requires 0 <= t <= t+dur <= 86400; event ignored"); continue
		events.append({"t":t,"speed":float(item.speed),"dur":dur,"ease":str(item.get("ease","linear"))})
	context.chart["track_speeds"]=tracks; context.chart["sv"]=events
	context.chart["_fall_profile"]=Profile.compile(events); context.chart["_fall_tracks"]=speeds
	context.chart["_fall_neutral"]=context.chart._fall_profile.neutral
	for speed in speeds.values():
		if speed!=1.0: context.chart._fall_neutral=false
