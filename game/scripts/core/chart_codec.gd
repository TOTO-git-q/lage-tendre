## A lossless compact writer: unknown fields and nondefault values are untouched.
## Defaults are removed only at an explicit schema path, including nested arrays.
class_name ChartCodec
extends RefCounted

static func path_parts(path: String) -> Array:
	var result := []
	var segment := RegEx.new()
	segment.compile("^[A-Za-z_][A-Za-z0-9_]*(?:\\[\\])?$")
	for part in path.split("."):
		if not segment.search(part): return []
		result.append({"key": part.trim_suffix("[]"), "array": part.ends_with("[]")})
	return result

static func compact(raw: Dictionary, schemas: Array) -> Dictionary:
	return _compact_details(raw, schemas).data

static func _compact_details(raw: Dictionary, schemas: Array) -> Dictionary:
	var result := raw.duplicate(true)
	var omitted := {}
	for schema in schemas:
		if typeof(schema) != TYPE_DICTIONARY or not schema.has("default"): continue
		var parts := path_parts(str(schema.get("path", "")))
		var positions := []
		if not parts.is_empty(): _strip(result, parts, 0, schema.default, positions, [])
		if not positions.is_empty(): omitted[str(schema.path)] = positions
	return {"data": result, "omitted": omitted}

static func _equal(a: Variant, b: Variant) -> bool:
	# JSON has one numeric category; booleans must never compare equal to 0 or 1.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return a == b
	if typeof(a) != typeof(b): return false
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _equal(a[i], b[i]): return false
		return true
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equal(a[key], b[key]): return false
		return true
	return a == b

static func _strip(node: Variant, parts: Array, depth: int, default_value: Variant, positions: Array, indices: Array) -> void:
	if typeof(node) != TYPE_DICTIONARY: return
	var part: Dictionary = parts[depth]
	if not node.has(part.key): return
	if depth == parts.size() - 1:
		# A leaf with [] is a field describing the array itself, never a request to
		# remove matching elements (which would change note positions/counts).
		if _equal(node[part.key], default_value):
			node.erase(part.key); positions.append(indices.duplicate())
		return
	if part.array:
		if typeof(node[part.key]) == TYPE_ARRAY:
			for i in node[part.key].size():
				var next := indices.duplicate(); next.append(i)
				_strip(node[part.key][i], parts, depth + 1, default_value, positions, next)
	else:
		_strip(node[part.key], parts, depth + 1, default_value, positions, indices)

static func save_file(path: String, raw: Dictionary, schemas: Array) -> Dictionary:
	var source := expand(raw, schemas)
	var errors := _omission_errors(raw, source, schemas)
	if not errors.is_empty(): return {"ok": false, "errors": errors}
	# These two reserved keys belong to the codec, not to the chart vocabulary.
	source.erase("defaults_schema"); source.erase("defaults_omitted")
	var result := _compact_details(source, schemas)
	result.data.defaults_schema = 1
	result.data.defaults_omitted = result.omitted
	return write_json_atomic(path, result.data)

static func write_json_atomic(path: String, value: Variant) -> Dictionary:
	var temp := path + ".tmp." + str(OS.get_process_id()) + "." + str(Time.get_ticks_usec())
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return {"ok": false, "errors": ["Cannot write " + path + ": " + error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "errors": ["Cannot flush " + path + ": " + error_string(status)]}
	status = DirAccess.rename_absolute(temp, path)
	if status != OK:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "errors": ["Cannot replace " + path + ": " + error_string(status)]}
	return {"ok": true, "errors": []}

## Restore only omissions recorded by save_file. Existing contextual omissions
## (e.g. sweep inherits x/w/a) are never expanded into constant schema defaults.
static func expand(raw: Dictionary, schemas: Array) -> Dictionary:
	var result := raw.duplicate(true)
	if typeof(result.get("defaults_schema")) not in [TYPE_INT, TYPE_FLOAT] or result.defaults_schema != 1 or typeof(result.get("defaults_omitted")) != TYPE_DICTIONARY: return result
	var by_path := {}
	for schema in schemas:
		if typeof(schema) == TYPE_DICTIONARY and schema.has("default"): by_path[str(schema.get("path", ""))] = schema
	var paths: Array = result.defaults_omitted.keys()
	paths.sort_custom(func(a, b): return str(a).split(".").size() < str(b).split(".").size() if str(a).split(".").size() != str(b).split(".").size() else str(a) < str(b))
	for path in paths:
		if not by_path.has(path) or typeof(result.defaults_omitted[path]) != TYPE_ARRAY: continue
		var parts := path_parts(str(path))
		if parts.is_empty(): continue
		for indices in result.defaults_omitted[path]:
			if typeof(indices) == TYPE_ARRAY: _fill_selected(result, parts, 0, by_path[path].default, indices, 0)
	return result

static func _fill_selected(node: Variant, parts: Array, depth: int, default_value: Variant, indices: Array, index_position: int) -> void:
	if typeof(node) != TYPE_DICTIONARY: return
	var part: Dictionary = parts[depth]
	if depth == parts.size() - 1:
		if index_position == indices.size() and not node.has(part.key):
			node[part.key] = default_value.duplicate(true) if typeof(default_value) in [TYPE_DICTIONARY, TYPE_ARRAY] else default_value
		return
	if not node.has(part.key):
		if part.array: return
		node[part.key] = {}
	if part.array:
		if typeof(node[part.key]) != TYPE_ARRAY or index_position >= indices.size(): return
		var at: Variant = indices[index_position]
		if typeof(at) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(at)) or at != floor(float(at)) or at < 0 or at >= node[part.key].size(): return
		_fill_selected(node[part.key][int(at)], parts, depth + 1, default_value, indices, index_position + 1)
	else: _fill_selected(node[part.key], parts, depth + 1, default_value, indices, index_position)

## A disabled/missing plugin must not erase omission records that only its schema
## can restore. Refuse before touching the destination, including malformed maps.
static func _omission_errors(raw: Dictionary, expanded: Dictionary, schemas: Array) -> Array:
	if not raw.has("defaults_schema"): return []
	if typeof(raw.defaults_schema) not in [TYPE_INT, TYPE_FLOAT] or raw.defaults_schema != 1 or typeof(raw.get("defaults_omitted")) != TYPE_DICTIONARY:
		return ["Cannot save chart with unsupported or malformed default omission metadata"]
	var known := {}
	for schema in schemas:
		if typeof(schema) == TYPE_DICTIONARY and schema.has("default"): known[str(schema.get("path", ""))] = true
	var errors := []
	for path in raw.defaults_omitted:
		if not known.has(path):
			errors.append("Cannot save compact chart: schema unavailable for " + str(path)); continue
		var parts := path_parts(str(path))
		if parts.is_empty() or typeof(raw.defaults_omitted[path]) != TYPE_ARRAY:
			errors.append("Cannot save malformed omission metadata: " + str(path)); continue
		for indices in raw.defaults_omitted[path]:
			if typeof(indices) != TYPE_ARRAY or not _omission_present(expanded, parts, 0, indices, 0):
				errors.append("Cannot resolve default omission: " + str(path))
	return errors

static func _omission_present(node: Variant, parts: Array, depth: int, indices: Array, index_position: int) -> bool:
	if typeof(node) != TYPE_DICTIONARY: return false
	var part: Dictionary = parts[depth]
	if not node.has(part.key): return false
	if depth == parts.size() - 1: return index_position == indices.size()
	if part.array:
		if typeof(node[part.key]) != TYPE_ARRAY or index_position >= indices.size(): return false
		var at: Variant = indices[index_position]
		if typeof(at) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(at)) or at != floor(float(at)) or at < 0 or at >= node[part.key].size(): return false
		return _omission_present(node[part.key][int(at)], parts, depth + 1, indices, index_position + 1)
	return _omission_present(node[part.key], parts, depth + 1, indices, index_position)
