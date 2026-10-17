## Per-run evidence for Charter. Persistence never changes scoring or chart timing.
extends RefCounted

var active := false
var song := ""
var started := 0.0
var run_settings := {}
var markers := []
var start_t := 0.0
var plugin_identity := []

func begin(song_dir: String, settings: Dictionary, from_t: float, identity: Array = []) -> void:
	active = true
	song = song_dir
	started = Time.get_unix_time_from_system()
	run_settings = settings.duplicate(true)
	start_t = from_t
	plugin_identity = identity.duplicate()
	markers.clear()

func mark(t_chart: float) -> void:
	if active:
		markers.append({"t_chart": t_chart, "t_wall": Time.get_unix_time_from_system()})

func _item(n: Dictionary, cue := false) -> Dictionary:
	var state: String = n.get("state", "pending")
	var grade: String = "MISS" if state in ["miss", "fail"] else n.get("grade", "")
	return {"id": n.id, "t": n.t, "kind": ("hold" if n.get("dur", 0.0) > 0.0 else "tap") if cue else n.kind,
		"k": -1 if cue else n.get("k", -1), "state": state, "grade": grade,
		"hitDt": n.get("hitDt") if state in ["hit", "holding", "done", "fail"] else null,
		"key": n.get("key", ""), "dur": n.get("dur", 0.0)}

func finish(core: GameCore, reason: String) -> String:
	if not active: return ""
	var ns := []
	var cs := []
	for n in core.notes: ns.append(_item(n))
	for c in core.cues: cs.append(_item(c, true))
	var data := {"schema": 1, "song": song, "started_unix": started, "ended_unix": Time.get_unix_time_from_system(),
		"reason": reason, "from_t": start_t, "autoplay": core.autoplay, "settings": run_settings,
		"notes": ns, "cues": cs, "markers": markers.duplicate(true), "strays": core.strays.duplicate(true), "stats": core.stats.duplicate(true)}
	if not plugin_identity.is_empty(): data["plugins"] = plugin_identity.duplicate()
	var folder := "user://playlogs"
	# Test runs can keep their evidence inside an isolated writable workspace.
	if not OS.get_environment("CHARTER_PLAYLOG_DIR").is_empty():
		folder = OS.get_environment("CHARTER_PLAYLOG_DIR")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("Cannot create playlogs directory"); return ""
	var path := folder.path_join("%s_%d_%d.json" % [song.replace("/", "__").replace("\\", "__"), int(started * 1000000.0), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write playlog: " + path); return ""
	file.store_string(JSON.stringify(data))
	file.close()
	active = false
	print("playlog saved: ", ProjectSettings.globalize_path(path))
	return path
