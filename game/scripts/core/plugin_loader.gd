## The same manifest parser and dependency ordering serve built-ins and song packs.
class_name PluginLoader
extends RefCounted

const SAFE_ASSETS := ["json", "png", "jpg", "jpeg", "webp", "svg", "gdshader"]

static func safe_relative(path: String) -> bool:
	return PluginPack.safe_relative(path)

static func version_parts(version: String) -> Array:
	var regex := RegEx.new()
	regex.compile("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
	var found := regex.search(version)
	return [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))] if found else []

static func version_matches(actual: String, required: String) -> bool:
	if required == "*": return not version_parts(actual).is_empty()
	if required.begins_with("^"):
		var have := version_parts(actual); var want := version_parts(required.substr(1))
		if have.is_empty() or want.is_empty(): return false
		if have < want: return false
		return have[0] == want[0] if want[0] > 0 else (have[1] == want[1] if want[1] > 0 else have == want)
	return actual == required and not version_parts(actual).is_empty()

static func validate_manifest(value, path := "") -> Dictionary:
	var errors := []
	if typeof(value) != TYPE_DICTIONARY: return {"manifest": {}, "errors": ["Manifest must be an object: " + path]}
	var manifest: Dictionary = value.duplicate(true)
	for key in ["id", "version", "api", "tier", "title", "author", "description", "provides", "fields", "assets", "entry"]:
		if not manifest.has(key): errors.append("Manifest missing " + key + ": " + path)
	if not errors.is_empty(): return {"manifest": {}, "errors": errors}
	var identifier := RegEx.new(); identifier.compile("^[a-z][a-z0-9_.-]*$")
	if typeof(manifest.id) != TYPE_STRING or not identifier.search(str(manifest.id)): errors.append("Invalid plugin id")
	if typeof(manifest.version) != TYPE_STRING or version_parts(str(manifest.version)).is_empty(): errors.append("Version must be major.minor.patch")
	if typeof(manifest.api) not in [TYPE_INT, TYPE_FLOAT] or manifest.api != PluginRegistry.API: errors.append("Unsupported plugin API: " + str(manifest.api))
	if typeof(manifest.tier) != TYPE_STRING or manifest.tier not in ["script", "declarative"]: errors.append("Unknown plugin tier")
	for key in ["title", "author", "description"]:
		if typeof(manifest[key]) != TYPE_STRING or str(manifest[key]).strip_edges().is_empty(): errors.append("Invalid " + key)
	if typeof(manifest.provides) != TYPE_DICTIONARY: errors.append("provides must be an object")
	else:
		for category in manifest.provides:
			if category not in PluginRegistry.CATEGORIES or typeof(manifest.provides[category]) != TYPE_ARRAY:
				errors.append("Invalid provides category: " + str(category)); continue
			var seen := {}
			for id in manifest.provides[category]:
				if typeof(id) != TYPE_STRING or str(id).is_empty() or seen.has(id):
					errors.append("Invalid or duplicate provider id"); continue
				seen[id] = true
	if typeof(manifest.fields) != TYPE_ARRAY: errors.append("fields must be an array")
	else:
		var field_paths := {}
		for field in manifest.fields:
			if typeof(field) != TYPE_DICTIONARY:
				errors.append("Field metadata must be an object"); continue
			for key in ["path", "type", "unit", "default", "doc"]:
				if not field.has(key): errors.append("Field missing " + key)
			var field_type := str(field.get("type", ""))
			if field_type not in ["number", "integer", "boolean", "string", "enum", "array", "object"]: errors.append("Unsupported field type")
			for key in ["path", "unit", "doc"]:
				if typeof(field.get(key)) != TYPE_STRING or str(field.get(key, "")).is_empty(): errors.append("Field requires nonempty " + key)
			var field_path := str(field.get("path", ""))
			if field_paths.has(field_path): errors.append("Duplicate field path: " + field_path)
			field_paths[field_path] = true
			if field_type in ["number", "integer"]:
				for key in ["min", "max", "step", "default"]:
					if typeof(field.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(SU.num(field.get(key), NAN)):
						errors.append("Numeric field missing finite " + key)
				var low := SU.num(field.get("min"), 0.0); var high := SU.num(field.get("max"), 0.0)
				var default_value := SU.num(field.get("default"), 0.0)
				if low > high or default_value < low or default_value > high: errors.append("Field default/range mismatch")
				if SU.num(field.get("step"), 0.0) <= 0.0: errors.append("Field step must be positive")
				if field_type == "integer" and default_value != floor(default_value): errors.append("Integer field requires an integral default")
			elif field_type == "enum":
				if typeof(field.get("enum")) != TYPE_ARRAY or field.enum.is_empty(): errors.append("Enum field requires values")
				elif field.get("default") not in field.enum: errors.append("Enum default must be one of its values")
			else:
				var expected := {"boolean": TYPE_BOOL, "string": TYPE_STRING, "array": TYPE_ARRAY, "object": TYPE_DICTIONARY}
				if expected.has(field_type) and typeof(field.get("default")) != expected[field_type]: errors.append("Wrong field default type")
	if typeof(manifest.assets) != TYPE_ARRAY: errors.append("assets must be an array")
	else:
		for asset in manifest.assets:
			if typeof(asset) != TYPE_STRING or not safe_relative(str(asset)) or str(asset).get_extension().to_lower() not in SAFE_ASSETS:
				errors.append("Unsafe or unsupported asset: " + str(asset))
	if typeof(manifest.tier) == TYPE_STRING and manifest.tier == "declarative" and manifest.entry != null: errors.append("Declarative plugins cannot have a script entry")
	if typeof(manifest.tier) == TYPE_STRING and manifest.tier == "script" and manifest.entry == null: errors.append("Script plugin requires an entry")
	if manifest.entry != null and (typeof(manifest.entry) != TYPE_STRING or not safe_relative(str(manifest.entry)) or str(manifest.entry).get_extension() != "gd"):
		errors.append("Unsafe script entry")
	if typeof(manifest.get("requires", [])) != TYPE_ARRAY: errors.append("requires must be an array")
	else:
		for requirement in manifest.get("requires", []):
			if typeof(requirement) != TYPE_DICTIONARY or not requirement.has("id") or not requirement.has("version"):
				errors.append("Dependency requires id and version")
			elif typeof(requirement.id) != TYPE_STRING or not identifier.search(str(requirement.id)) or typeof(requirement.version) != TYPE_STRING:
				errors.append("Invalid dependency id/version")
			elif requirement.version != "*" and version_parts(str(requirement.version).trim_prefix("^")).is_empty():
				errors.append("Unsupported dependency version range")
	return {"manifest": manifest if errors.is_empty() else {}, "errors": errors}

static func dependency_order(manifests: Array, installed := {}) -> Dictionary:
	var by_id := {}; var errors := []; var ordered := []; var visiting := {}; var done := {}
	for manifest in manifests:
		if by_id.has(manifest.id) or installed.has(manifest.id): errors.append("Duplicate plugin id: " + str(manifest.id))
		by_id[manifest.id] = manifest
	if not errors.is_empty(): return {"ordered": [], "errors": errors}
	var visit: Callable
	visit = func(id: String, recurse: Callable) -> void:
		if done.has(id): return
		if visiting.has(id): errors.append("Dependency cycle at " + id); return
		visiting[id] = true
		for requirement in by_id[id].get("requires", []):
			var dependency: String = str(requirement.id)
			var found: Dictionary = by_id.get(dependency, installed.get(dependency, {}))
			if found.is_empty(): errors.append("Missing dependency %s for %s" % [dependency, id]); continue
			if not version_matches(str(found.version), str(requirement.version)):
				errors.append("Dependency version mismatch: " + dependency); continue
			if by_id.has(dependency): recurse.call(dependency, recurse)
		visiting.erase(id); done[id] = true; ordered.append(by_id[id])
	var ids := by_id.keys(); ids.sort()
	for id in ids: visit.call(id, visit)
	return {"ordered": ordered if errors.is_empty() else [], "errors": errors}

func load_builtin(registry: PluginRegistry) -> Dictionary:
	var paths := []
	for directory in DirAccess.get_directories_at("res://plugins/builtin"):
		var path: String = "res://plugins/builtin/" + directory + "/plugin.json"
		if FileAccess.file_exists(path): paths.append(path)
	return load_paths(paths, registry, true)

func load_paths(paths: Array, registry: PluginRegistry, scripts_trusted := false) -> Dictionary:
	var manifests := []; var errors := []; var folders := {}
	for path in paths:
		var checked := validate_manifest(SU.load_json(str(path)), str(path))
		errors.append_array(checked.errors)
		if not checked.manifest.is_empty():
			manifests.append(checked.manifest); folders[checked.manifest.id] = str(path).get_base_dir()
	if not errors.is_empty(): return {"loaded": [], "errors": errors, "disabled": []}
	var ordered := dependency_order(manifests, registry.manifests)
	if not ordered.errors.is_empty(): return {"loaded": [], "errors": ordered.errors, "disabled": []}
	# Registry changes are transactional. Trusted scripts are not sandboxed and may
	# have external side effects; the UI must say so before granting trust.
	var working := registry.fork_scope()
	var loaded := []; var disabled := []; var unavailable := {}
	for manifest in ordered.ordered:
		var reason := ""
		if manifest.tier == "script" and not scripts_trusted: reason = "script permission required"
		for requirement in manifest.get("requires", []):
			if unavailable.has(requirement.id): reason = "dependency disabled: " + str(requirement.id)
		if not reason.is_empty():
			unavailable[manifest.id] = true
			disabled.append(str(manifest.id) + ": " + reason)
			continue
		working.begin_plugin(manifest)
		if manifest.tier == "script":
			var entry_path: String = str(folders[manifest.id]).path_join(str(manifest.entry))
			# Exported GDScript is remapped to bytecode; FileAccess cannot resolve that remap.
			if not ResourceLoader.exists(entry_path): errors.append("Missing script entry for " + str(manifest.id))
			else:
				# External scripts and their dependencies must match the just-approved
				# bytes, never a previous song's cached Script/static state.
				var cache_mode := ResourceLoader.CACHE_MODE_REUSE if entry_path.begins_with("res://plugins/builtin/") else ResourceLoader.CACHE_MODE_IGNORE_DEEP
				var entry = ResourceLoader.load(entry_path, "Script", cache_mode)
				if entry == null or not entry.has_method("install"): errors.append("Missing install entry for " + str(manifest.id))
				else:
					if entry.has_method("teardown"): working.on_close(Callable(entry, "teardown"))
					entry.install(working, manifest, folders[manifest.id])
		else:
			errors.append_array(PluginDeclarative.install(working, manifest, folders[manifest.id]))
		for category in manifest.provides:
			for id in manifest.provides[category]:
				if working.get_entry(category, id).get("plugin", "") != manifest.id:
					errors.append("Plugin %s did not register declared %s: %s" % [manifest.id, category, id])
		for category in PluginRegistry.CATEGORIES:
			for entry in working.records[category].values():
				if entry.plugin == manifest.id and entry.id not in manifest.provides.get(category, []):
					errors.append("Plugin %s registered undeclared %s: %s" % [manifest.id, category, entry.id])
		working.end_plugin()
		loaded.append(manifest.id)
	errors.append_array(working.errors)
	if not errors.is_empty():
		working.dispose()
		return {"loaded": [], "errors": errors, "disabled": disabled}
	registry.adopt(working)
	return {"loaded": loaded, "errors": [], "disabled": disabled}
