## File-only pack inspection. Never ask ResourceLoader to inspect untrusted code.
class_name PluginPack
extends RefCounted

static func safe_relative(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or path.contains("\\"): return false
	for ch in path:
		if ch.unicode_at(0) < 32: return false
	for part in path.split("/"):
		if part in ["", ".", ".."]: return false
	return true

## Pure decomposition is platform independent, so drive/UNC handling is tested
## even on Linux. Actual inspection always uses this host's DirAccess semantics.
static func decompose_absolute(path: String) -> Dictionary:
	var normalized := path.replace("\\", "/")
	var root := ""
	var rest := ""
	if normalized.begins_with("//"):
		var parts := normalized.substr(2).split("/", false)
		if parts.size() < 2 or parts[0] in [".", "..", "?"] or parts[1] in [".", ".."]:
			return {"root": "", "parts": [], "errors": ["Invalid UNC pack path"]}
		root = "//" + parts[0] + "/" + parts[1] + "/"
		rest = "/".join(parts.slice(2))
	elif normalized.length() >= 3 and normalized.substr(1, 2) == ":/" and normalized.substr(0, 1).to_upper() in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		root = normalized.substr(0, 3); rest = normalized.substr(3)
	elif normalized.begins_with("/"):
		root = "/"; rest = normalized.substr(1)
	else: return {"root": "", "parts": [], "errors": ["Song pack folder must be absolute"]}
	return {"root": root, "parts": Array(rest.split("/", false)), "errors": []}

static func root_path(folder: String) -> Dictionary:
	var decomposed := decompose_absolute(ProjectSettings.globalize_path(folder))
	if not decomposed.errors.is_empty(): return {"path": "", "errors": decomposed.errors}
	var current: String = decomposed.root
	var depth := 0
	for part in decomposed.parts:
		if part == ".": continue
		if part == "..":
			if depth == 0: return {"path": "", "errors": ["Pack folder traverses its filesystem root"]}
			current = current.get_base_dir(); depth -= 1; continue
		var parent := DirAccess.open(current)
		if parent == null: return {"path": "", "errors": ["Cannot inspect pack folder: " + current]}
		if parent.is_link(part): return {"path": "", "errors": ["Symlink is not allowed in song pack path: " + current.path_join(part)]}
		current = current.path_join(part); depth += 1
	if not DirAccess.dir_exists_absolute(current): return {"path": "", "errors": ["Missing song pack folder: " + current]}
	return {"path": current.simplify_path(), "errors": []}

static func file_path(folder: String, relative: String) -> Dictionary:
	if not safe_relative(relative): return {"path": "", "errors": ["Unsafe pack path: " + relative]}
	var root := root_path(folder)
	if not root.errors.is_empty(): return root
	var current: String = root.path
	for part in relative.split("/"):
		var directory := DirAccess.open(current)
		if directory == null: return {"path": "", "errors": ["Missing pack folder: " + current]}
		if directory.is_link(part): return {"path": "", "errors": ["Symlink is not allowed in song pack: " + relative]}
		current = current.path_join(part)
	if not FileAccess.file_exists(current): return {"path": "", "errors": ["Missing pack file: " + relative]}
	return {"path": current, "errors": []}

static func read_object(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"value": {}, "errors": ["Cannot read JSON: " + path]}
	var parser := JSON.new()
	var text := file.get_as_text(); file.close()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"value": {}, "errors": ["Invalid JSON object: " + path]}
	return {"value": parser.data, "errors": []}

static func content_hash(folder: String) -> Dictionary:
	var checked := root_path(folder)
	if not checked.errors.is_empty(): return {"hash": "", "errors": checked.errors}
	var files := []; var errors := []
	_walk(checked.path, "", files, errors, 0)
	if not errors.is_empty(): return {"hash": "", "errors": errors}
	files.sort()
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update("LAgeTendre pack content v1\n".to_utf8_buffer())
	for relative in files:
		var path: String = str(checked.path).path_join(relative)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return {"hash": "", "errors": ["Cannot hash pack file: " + relative]}
		var size := file.get_length()
		var name: PackedByteArray = relative.to_utf8_buffer()
		context.update((str(name.size()) + ":").to_utf8_buffer()); context.update(name)
		context.update((":" + str(size) + ":").to_utf8_buffer())
		var remaining := size
		while remaining > 0:
			var bytes := file.get_buffer(mini(remaining, 524288))
			if bytes.is_empty():
				file.close(); return {"hash": "", "errors": ["Pack changed or failed while hashing: " + relative]}
			context.update(bytes); remaining -= bytes.size()
		var final_size := file.get_length(); file.close()
		if final_size != size: return {"hash": "", "errors": ["Pack changed while hashing: " + relative]}
	return {"hash": context.finish().hex_encode(), "errors": [], "files": files.size()}

static func _walk(root: String, relative: String, files: Array, errors: Array, depth: int) -> void:
	if depth > 128 or files.size() > 100000:
		errors.append("Pack exceeds safe file inspection limits"); return
	var directory := DirAccess.open(root.path_join(relative))
	if directory == null: errors.append("Cannot inspect pack directory: " + relative); return
	directory.include_hidden = true
	directory.include_navigational = false
	if directory.list_dir_begin() != OK: errors.append("Cannot list pack directory: " + relative); return
	var name := directory.get_next()
	while not name.is_empty():
		var child := name if relative.is_empty() else relative.path_join(name)
		if not safe_relative(child): errors.append("Unsafe pack filename: " + child)
		elif directory.is_link(name): errors.append("Symlink is not allowed in song pack: " + child)
		elif directory.current_is_dir(): _walk(root, child, files, errors, depth + 1)
		else: files.append(child)
		name = directory.get_next()
	directory.list_dir_end()

## Godot's GDScript preload cache can reuse a dependency despite IGNORE_DEEP.
## Each trusted session gets fresh paths and a verified byte-for-byte snapshot.
static func snapshot(folder: String, expected_hash: String) -> Dictionary:
	var checked := root_path(folder)
	if not checked.errors.is_empty(): return {"path": "", "errors": checked.errors}
	var storage := ProjectSettings.globalize_path("user://plugin_sessions").simplify_path()
	if (storage + "/").begins_with(str(checked.path).trim_suffix("/") + "/"):
		return {"path": "", "errors": ["Song pack contains plugin session storage; use a separate song folder"]}
	var files := []; var errors := []
	_walk(checked.path, "", files, errors, 0)
	if not errors.is_empty(): return {"path": "", "errors": errors}
	var destination := "user://plugin_sessions/" + expected_hash + "/" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	var status := DirAccess.make_dir_recursive_absolute(destination)
	if status != OK: return {"path": "", "errors": ["Cannot create trusted plugin snapshot: " + error_string(status)]}
	var safe := root_path(destination)
	if not safe.errors.is_empty(): return {"path": "", "errors": safe.errors}
	for relative in files:
		var source := file_path(checked.path, relative)
		if not source.errors.is_empty():
			remove_snapshot(safe.path); return {"path": "", "errors": source.errors}
		var target: String = str(safe.path).path_join(relative)
		status = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if status == OK: status = DirAccess.copy_absolute(source.path, target)
		if status != OK:
			remove_snapshot(safe.path); return {"path": "", "errors": ["Cannot copy trusted plugin snapshot: " + relative]}
	var hashed := content_hash(safe.path)
	if not hashed.errors.is_empty() or hashed.hash != expected_hash:
		remove_snapshot(safe.path)
		return {"path": "", "errors": ["Pack changed during trusted snapshot; prepare and choose trust again"] + hashed.errors}
	return {"path": safe.path, "errors": []}

static func remove_snapshot(path: String) -> void:
	var allowed := ProjectSettings.globalize_path("user://plugin_sessions").simplify_path() + "/"
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.begins_with(allowed): return
	# Never traverse an ancestor link even if a trusted script replaced a
	# snapshot's hash directory. The final component may itself be a link;
	# _remove_tree only unlinks that component.
	if not root_path(absolute.get_base_dir()).errors.is_empty(): return
	_remove_tree(absolute)

static func _remove_tree(path: String) -> void:
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null: return
	if parent.is_link(path.get_file()): DirAccess.remove_absolute(path); return
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true; directory.include_navigational = false
	if directory.list_dir_begin() != OK: return
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir() and not directory.is_link(name): _remove_tree(child)
		else: DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
