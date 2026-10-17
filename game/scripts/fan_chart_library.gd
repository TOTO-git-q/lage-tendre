## Shared, file-only community discovery. Never loads song scripts or resources.
class_name FanChartLibrary
extends RefCounted

const GROUP := "社区谱面 FAN-MADE"

static func valid_slug(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9][a-z0-9_-]{0,47}$")
	return pattern.search(value) != null

static func text(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 256: return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return false
	return true

static func number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func read_entry(root: String, slug: String) -> Dictionary:
	var errors := []
	if not valid_slug(slug): return {"errors": ["invalid slug"], "entry": {}}
	var dir := "fan-made/" + slug
	var checked := PluginPack.file_path(root, dir + "/info.json")
	if not checked.errors.is_empty(): return {"errors": checked.errors, "entry": {}}
	var file := FileAccess.open(checked.path, FileAccess.READ)
	if file == null or file.get_length() > 65536: return {"errors": ["info.json unreadable or exceeds 64 KiB"], "entry": {}}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary:
		return {"errors": ["info.json must be a JSON object"], "entry": {}}
	var row: Dictionary = parsed.data.duplicate(true)
	for key in ["title", "artist", "version", "chart_author", "chart_license"]:
		if not text(row.get(key)): errors.append("invalid " + key)
	for key in ["audio_license"]:
		if not row.get(key) is Dictionary: errors.append("missing " + key)
	if not number(row.get("bpm"), 20, 400): errors.append("invalid bpm")
	if not number(row.get("level"), 0, 100) or float(row.get("level", 0)) != floorf(float(row.get("level", 0))): errors.append("invalid level")
	if not number(row.get("preview"), -1, 86400): errors.append("invalid preview")
	var audio = row.get("audio", "")
	if audio not in ["audio.mp3", "audio.ogg"]: errors.append("audio must be audio.mp3 or audio.ogg")
	else: errors.append_array(PluginPack.file_path(root, dir.path_join(audio)).errors)
	var cover = row.get("cover", "")
	if cover not in ["", "cover.png", "cover.jpg"]: errors.append("invalid cover filename")
	elif not str(cover).is_empty(): errors.append_array(PluginPack.file_path(root, dir.path_join(cover)).errors)
	errors.append_array(PluginPack.file_path(root, dir + "/chart.json").errors)
	if not errors.is_empty(): return {"errors": errors, "entry": {}}
	row["dir"] = dir
	row["set"] = "fan-made/" + slug
	row["group"] = GROUP
	row["cover"] = dir.path_join(cover) if not str(cover).is_empty() else ""
	row["length"] = 0.0
	row["notes"] = 0
	var chart_file := FileAccess.open(root.path_join(dir + "/chart.json"), FileAccess.READ)
	if chart_file == null or chart_file.get_length() > 8388608: return {"errors": ["chart.json unreadable or exceeds 8 MiB"], "entry": {}}
	var chart_json := JSON.new()
	if chart_json.parse(chart_file.get_as_text()) != OK or not chart_json.data is Dictionary or not chart_json.data.get("notes") is Array or not chart_json.data.get("lights") is Array:
		return {"errors": ["chart.json must contain notes and lights arrays"], "entry": {}}
	for note in chart_json.data.notes:
		if not note is Dictionary or not number(note.get("t"), 0, 86400) or not number(note.get("dur", 0), 0, 86400):
			return {"errors": ["invalid note time"], "entry": {}}
		row.length = maxf(row.length, float(note.t) + float(note.get("dur", 0)))
	row.length += 1.4
	row.notes = chart_json.data.notes.size()
	return {"errors": [], "entry": row}

static func discover(root: String) -> Dictionary:
	var entries := []; var notices := []
	var folder := root.path_join("fan-made")
	if not DirAccess.dir_exists_absolute(folder): return {"entries": entries, "notices": notices}
	# Inspect the ancestor before listing; the songs root itself may not be a link.
	var safe := PluginPack.root_path(folder)
	if not safe.errors.is_empty(): return {"entries": [], "notices": safe.errors}
	for name in DirAccess.get_directories_at(folder):
		if name.begins_with("_") or name.begins_with("."): continue
		var result := read_entry(root, name)
		if result.errors.is_empty(): entries.append(result.entry)
		else: notices.append("%s: %s; ignored" % [name, "; ".join(result.errors)])
	entries.sort_custom(func(a, b):
		var at: String = a.title.to_lower(); var bt: String = b.title.to_lower()
		return a.dir < b.dir if at == bt else at < bt)
	return {"entries": entries, "notices": notices}
