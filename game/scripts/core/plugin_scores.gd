## Versioned local records. Plugin combinations cannot overwrite standard scores.
class_name PluginScores
extends RefCounted

const STANDARD_IDS := ["standard_chart", "standard_render", "standard_rules", "standard_stage"]
var records := {}
var errors := []
var path := "user://best.json"
var _extra := {}
var _can_save := true

static func standard_identity() -> Array:
	var result := []
	for id in STANDARD_IDS:
		var manifest: Dictionary = PluginRegistry.standard().manifests.get(id, {})
		if not manifest.is_empty(): result.append(id + "@" + str(manifest.version))
	result.sort()
	return result

static func key_for(chart_id: String, identity: Array) -> String:
	var sorted := []
	for item in identity:
		var text := str(item)
		if text not in sorted: sorted.append(text)
	sorted.sort()
	# JSON framing prevents ambiguous chart ids and delimiter collisions.
	return JSON.stringify([chart_id, sorted])

func load_file(file_path := "user://best.json") -> Dictionary:
	path = file_path; records = {}; errors = []; _extra = {}; _can_save = true
	if not FileAccess.file_exists(path): return {"ok": true, "migrated": false, "errors": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Cannot read scores: " + path)
	var original := file.get_buffer(file.get_length()); file.close()
	var parser := JSON.new()
	if parser.parse(original.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _fail("Invalid score file; preserved without overwriting: " + path)
	var data: Dictionary = parser.data
	if typeof(data.get("schema")) in [TYPE_INT, TYPE_FLOAT] and data.schema == 2:
		if typeof(data.get("records")) != TYPE_DICTIONARY: return _fail("Score schema 2 requires records object")
		records = data.records.duplicate(true)
		_extra = data.duplicate(true); _extra.erase("schema"); _extra.erase("records")
		return {"ok": true, "migrated": false, "errors": []}
	if data.has("schema") and typeof(data.schema) in [TYPE_INT, TYPE_FLOAT]: return _fail("Unsupported score schema; preserved without overwriting")
	# Keep every legacy value, including fields we do not understand. Backup the
	# exact bytes before the first schema write. Never replace an older backup.
	var backup := path + ".legacy.bak"
	if FileAccess.file_exists(backup):
		var old := FileAccess.open(backup, FileAccess.READ)
		if old == null: return _fail("Cannot read legacy score backup")
		var same := old.get_buffer(old.get_length()) == original; old.close()
		if not same:
			backup = path + ".legacy." + original.hex_encode().sha256_text().substr(0, 16) + ".bak"
	if not FileAccess.file_exists(backup):
		var saved := FileAccess.open(backup, FileAccess.WRITE)
		if saved == null: return _fail("Cannot back up legacy scores; original preserved")
		saved.store_buffer(original); saved.flush()
		var code := saved.get_error(); saved.close()
		if code != OK: return _fail("Cannot flush legacy score backup; original preserved")
	var verified := FileAccess.open(backup, FileAccess.READ)
	if verified == null: return _fail("Cannot verify legacy score backup; original preserved")
	var backup_matches := verified.get_buffer(verified.get_length()) == original; verified.close()
	if not backup_matches: return _fail("Legacy score backup did not verify; original preserved")
	var identity := standard_identity()
	for id in data: records[key_for(str(id), identity)] = data[id].duplicate(true) if typeof(data[id]) in [TYPE_DICTIONARY, TYPE_ARRAY] else data[id]
	var saved := save_file()
	if not saved.ok: return {"ok": false, "migrated": false, "errors": errors.duplicate(), "backup": backup}
	return {"ok": true, "migrated": true, "errors": [], "backup": backup}

func _fail(message: String) -> Dictionary:
	errors.append(message); _can_save = false
	return {"ok": false, "migrated": false, "errors": errors.duplicate()}

func get_record(chart_id: String, identity: Array) -> Dictionary:
	return get_by_key(key_for(chart_id, identity))

func get_by_key(key: String) -> Dictionary:
	var value: Variant = records.get(key, {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func update_best(chart_id: String, identity: Array, stats: Dictionary) -> Dictionary:
	var key := key_for(chart_id, identity)
	var previous := get_by_key(key)
	var score := int(stats.get("score", 0))
	var result := {"new": previous.is_empty() or score > int(previous.get("score", 0)), "prev": int(previous.get("score", 0))}
	var next := previous.duplicate(true)
	if result.new:
		next.score = score
		next.acc = stats.get("accuracy", stats.get("acc", 0.0))
	if int(stats.get("MISS", 1)) == 0 or stats.get("fc", false) == true or previous.get("fc", false) == true: next.fc = true
	elif result.new: next.fc = false
	records[key] = next
	return result

func save_file() -> Dictionary:
	if not _can_save: return {"ok": false, "errors": errors.duplicate()}
	var data := _extra.duplicate(true); data.schema = 2; data.records = records
	var result := ChartCodec.write_json_atomic(path, data)
	if not result.ok: errors.append_array(result.errors)
	return result
