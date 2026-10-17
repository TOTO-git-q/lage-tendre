## One chart's trust decision, scoped providers and cooperative lifetime.
## prepare() is file/data inspection only: untrusted Script resources are never loaded.
class_name SongPluginSession
extends RefCounted

const TRUST_PATH := "user://plugin_trust.json"
var registry: PluginRegistry
var identity := []
var score_key := ""
var chart_data := {}
var report := {"errors": [], "notices": [], "script_ids": [], "content_hash": "", "requires_trust": false, "identity": [], "score_key": ""}
var _folder := ""
var _raw := {}
var _chart_id := ""
var _prepared := false
var _hash := ""
var _selected := {}
var _folders := {}
var _ordered := []
var _builtin_ids := []
var _decision: Variant = null
var _opened := false
var _motion_router: MotionRouter
var _snapshot_root := ""

## A private dispatcher lets P2 use real motion providers without changing the
## legacy renderer's cached follow_track hot path for charts without plugins.
class MotionRouter extends RefCounted:
	var fallback: Callable
	var motions := {}
	func route(renderer, note: Dictionary, state: Dictionary) -> Dictionary:
		var motion: Variant = note.get("motion", {})
		var id := str(motion.get("type", "")) if typeof(motion) == TYPE_DICTIONARY else ""
		var callback: Callable = motions.get(id, Callable())
		return callback.call(renderer, note, state) if callback.is_valid() else fallback.call(renderer, note, state)

func prepare(folder: String, raw: Dictionary, chart_id: String) -> Dictionary:
	close()
	_folder = folder; _raw = raw.duplicate(true); _chart_id = chart_id
	report = {"errors": [], "notices": [], "script_ids": [], "content_hash": "", "requires_trust": false, "identity": [], "score_key": ""}
	_builtin_ids = PluginScores.STANDARD_IDS.duplicate()
	var base := PluginRegistry.standard()
	for id in _builtin_ids:
		if not base.manifests.has(id): report.errors.append("Missing standard built-in: " + str(id))
	var requirements: Variant = raw.get("plugins", [])
	if typeof(requirements) != TYPE_ARRAY:
		report.errors.append("Chart plugins must be an array of {id, version}")
		return report
	if raw.has("defaults_schema") and (typeof(raw.defaults_schema) not in [TYPE_INT, TYPE_FLOAT] or raw.defaults_schema != 1):
		report.errors.append("Unsupported chart defaults_schema")
	if raw.has("defaults_schema") and typeof(raw.get("defaults_omitted")) != TYPE_DICTIONARY:
		report.errors.append("Codec-marked chart requires defaults_omitted metadata")
	if not report.errors.is_empty(): return report
	# Critical legacy fast path: do not inspect the pack or neighboring plugins.
	if requirements.is_empty():
		_prepared = true
		_preview()
		chart_data = ChartCodec.expand(_raw, _schemas_for(_builtin_ids))
		return report
	var root := PluginPack.root_path(folder)
	if not root.errors.is_empty():
		report.errors.append_array(root.errors); return report
	_folder = root.path
	var done := {}; var visiting := {}; var requested := {}
	for requirement in requirements:
		if not _check_requirement(requirement, "chart"): continue
		if requested.has(requirement.id):
			report.errors.append("Duplicate chart plugin requirement: " + str(requirement.id)); continue
		requested[requirement.id] = true
		_resolve(requirement, "chart", done, visiting)
	if not report.errors.is_empty(): return report
	base = PluginRegistry.builtins()
	var local := []
	for manifest in _selected.values():
		if not base.manifests.has(manifest.id): local.append(manifest)
	var ordered := PluginLoader.dependency_order(local, base.manifests)
	report.errors.append_array(ordered.errors)
	_ordered = ordered.ordered
	for manifest in _ordered:
		var local_folder: String = _folders[manifest.id]
		if manifest.tier == "script":
			report.script_ids.append(manifest.id)
			report.errors.append_array(PluginPack.file_path(local_folder, manifest.entry).errors)
			for asset in manifest.assets: report.errors.append_array(PluginPack.file_path(local_folder, str(asset)).errors)
		else:
			for error in PluginDeclarative.validate(manifest, local_folder).errors:
				report.errors.append(str(manifest.id) + ": " + str(error))
	if not report.errors.is_empty(): return report
	report.script_ids.sort()
	var hashed := PluginPack.content_hash(_folder)
	report.errors.append_array(hashed.errors)
	if not report.errors.is_empty(): return report
	_hash = hashed.hash; report.content_hash = _hash
	var trust := _read_trust()
	for error in trust.errors: report.notices.append(str(error))
	_decision = _find_decision(trust.data)
	_prepared = true
	_preview()
	# Disabled script schemas are intentionally absent from the preview. open()
	# computes final data again from only the providers actually installed.
	chart_data = ChartCodec.expand(_raw, _schemas_for(_enabled_ids()))
	report.errors.append_array(_validate_chart_data(chart_data))
	return report

func _check_requirement(value: Variant, origin: String) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("id")) != TYPE_STRING or typeof(value.get("version")) != TYPE_STRING:
		report.errors.append(origin + " plugin requirement needs id and version strings"); return false
	var id_pattern := RegEx.new(); id_pattern.compile("^[a-z][a-z0-9_.-]*$")
	if not id_pattern.search(value.id):
		report.errors.append(origin + " has unsafe plugin id: " + str(value.id)); return false
	var version: String = value.version
	if version != "*" and PluginLoader.version_parts(version.trim_prefix("^")).is_empty():
		report.errors.append(origin + " has unsupported version range for " + str(value.id)); return false
	return true

func _resolve(requirement: Dictionary, origin: String, done: Dictionary, visiting: Dictionary) -> void:
	var id: String = requirement.id
	if visiting.has(id):
		report.errors.append("Plugin dependency cycle: " + origin + " -> " + id); return
	var base := PluginRegistry.builtins()
	var manifest: Dictionary = _selected.get(id, base.manifests.get(id, {}))
	if manifest.is_empty():
		var path := PluginPack.file_path(_folder, "plugins/" + id + "/plugin.json")
		if not path.errors.is_empty():
			report.errors.append("Missing or unsafe plugin %s required by %s: %s" % [id, origin, "; ".join(path.errors)]); return
		var value := PluginPack.read_object(path.path)
		if not value.errors.is_empty(): report.errors.append_array(value.errors); return
		var checked := PluginLoader.validate_manifest(value.value, path.path)
		if not checked.errors.is_empty(): report.errors.append_array(checked.errors); return
		manifest = checked.manifest
		if manifest.id != id:
			report.errors.append("Plugin folder/id mismatch: expected " + id + ", found " + str(manifest.id)); return
		_folders[id] = str(path.path).get_base_dir()
	if not PluginLoader.version_matches(str(manifest.version), requirement.version):
		report.errors.append("Plugin version mismatch: %s requires %s %s, found %s" % [origin, id, requirement.version, manifest.version]); return
	_selected[id] = manifest
	if base.manifests.has(id) and id not in _builtin_ids: _builtin_ids.append(id)
	if done.has(id): return
	visiting[id] = true
	for dependency in manifest.get("requires", []):
		if _check_requirement(dependency, id): _resolve(dependency, id, done, visiting)
	visiting.erase(id); done[id] = true

func _read_trust() -> Dictionary:
	if not FileAccess.file_exists(TRUST_PATH): return {"data": {"schema": 1, "decisions": {}}, "errors": []}
	var result := PluginPack.read_object(TRUST_PATH)
	if not result.errors.is_empty(): return {"data": {"schema": 1, "decisions": {}}, "errors": ["Saved plugin trust is unreadable; scripts need a new decision"]}
	var data: Dictionary = result.value
	if typeof(data.get("schema")) not in [TYPE_INT, TYPE_FLOAT] or data.schema != 1 or typeof(data.get("decisions")) != TYPE_DICTIONARY:
		return {"data": {"schema": 1, "decisions": {}}, "errors": ["Saved plugin trust has an unsupported format"]}
	return {"data": data, "errors": []}

func _find_decision(data: Dictionary) -> Variant:
	var value: Variant = data.get("decisions", {}).get(_hash)
	if typeof(value) == TYPE_DICTIONARY and typeof(value.get("allowed")) == TYPE_BOOL: return value.allowed
	return null

func _enabled_ids() -> Array:
	var enabled := _builtin_ids.duplicate()
	var unavailable := {}
	for manifest in _ordered:
		var blocked: bool = manifest.tier == "script" and _decision != true
		for requirement in manifest.get("requires", []):
			if unavailable.has(requirement.id): blocked = true
		if blocked: unavailable[manifest.id] = true
		else: enabled.append(manifest.id)
	return enabled

func _preview() -> void:
	var enabled := _enabled_ids()
	report.requires_trust = not report.script_ids.is_empty() and _decision == null
	var disabled := []
	for manifest in _ordered:
		if manifest.id not in enabled:
			var reason := "script trust has not been decided" if _decision == null else "script trust was denied"
			if manifest.tier != "script": reason = "required dependency is disabled"
			disabled.append(str(manifest.id) + ": " + reason)
	# Each preview can run after a trust choice without duplicating stale notices.
	report.notices = report.notices.filter(func(item): return not str(item).begins_with("Disabled plugin "))
	for item in disabled: report.notices.append("Disabled plugin " + item)
	report.disabled = disabled
	identity = _identity_for(enabled)
	score_key = PluginScores.key_for(_chart_id, identity)
	report.identity = identity.duplicate(); report.score_key = score_key

func _identity_for(ids: Array) -> Array:
	var result := []
	var base := PluginRegistry.standard()
	for id in ids:
		var manifest: Dictionary = _selected.get(id, base.manifests.get(id, {}))
		if not manifest.is_empty(): result.append(str(id) + "@" + str(manifest.version))
	result.sort()
	return result

func _schemas_for(ids: Array) -> Array:
	var result := []
	var base := PluginRegistry.standard()
	for id in ids:
		var manifest: Dictionary = _selected.get(id, base.manifests.get(id, {}))
		result.append_array(manifest.get("fields", []))
	return result

func _unchanged() -> bool:
	if _hash.is_empty(): return true
	var hashed := PluginPack.content_hash(_folder)
	if not hashed.errors.is_empty():
		report.errors.append_array(hashed.errors); _prepared = false; return false
	if hashed.hash != _hash:
		report.errors.append("Song pack content changed. Prepare it again before choosing trust or playing.")
		report.requires_trust = not report.script_ids.is_empty()
		_prepared = false; return false
	return true

func remember_trust(allowed: bool) -> bool:
	if not _prepared or report.script_ids.is_empty() or _hash.is_empty(): return false
	if not _unchanged(): return false
	var trust := _read_trust()
	if not trust.errors.is_empty():
		# Only an explicit new choice repairs corrupt state, after preserving the
		# original bytes. Reading/prepare never overwrites or silently allows it.
		var backup := TRUST_PATH + ".corrupt." + FileAccess.get_sha256(TRUST_PATH).substr(0, 16) + ".bak"
		if not FileAccess.file_exists(backup):
			var status := DirAccess.copy_absolute(TRUST_PATH, backup)
			if status != OK:
				report.errors.append("Cannot back up corrupt plugin trust history: " + error_string(status)); return false
		report.notices.append("Unreadable plugin trust history was backed up before recording your new choice.")
	trust.data.decisions[_hash] = {"allowed": allowed}
	var saved := ChartCodec.write_json_atomic(TRUST_PATH, trust.data)
	if not saved.ok:
		report.errors.append_array(saved.errors); return false
	_decision = allowed
	_preview()
	return true

func open() -> Dictionary:
	if _opened: return {"errors": ["Song plugin session is already open"], "disabled": [], "loaded": []}
	if not _prepared or not report.errors.is_empty():
		return {"errors": report.errors.duplicate() if not report.errors.is_empty() else ["Prepare the song plugin session first"], "disabled": [], "loaded": []}
	if not _unchanged(): return {"errors": report.errors.duplicate(), "disabled": [], "loaded": []}
	if not report.script_ids.is_empty():
		var trust := _read_trust()
		_decision = _find_decision(trust.data)
		_preview()
		if _decision == null: return {"errors": ["A trust decision is required for: " + ", ".join(report.script_ids)], "disabled": [], "loaded": []}
	chart_data = ChartCodec.expand(_raw, _schemas_for(_enabled_ids()))
	var data_errors := _validate_chart_data(chart_data)
	if not data_errors.is_empty():
		report.errors.append_array(data_errors)
		return {"errors": data_errors, "disabled": [], "loaded": []}
	registry = _builtin_scope()
	if not registry.errors.is_empty():
		var failures := registry.errors.duplicate(); registry.dispose(); registry = null
		report.errors.append_array(failures)
		return {"errors": failures, "disabled": [], "loaded": []}
	var paths := []
	if _decision == true and not report.script_ids.is_empty():
		var snapshot := PluginPack.snapshot(_folder, _hash)
		if not snapshot.errors.is_empty():
			registry.dispose(); registry = null
			report.errors.append_array(snapshot.errors)
			return {"loaded": [], "disabled": [], "errors": snapshot.errors}
		_snapshot_root = snapshot.path
	for manifest in _ordered:
		var manifest_folder: String = _folders[manifest.id] if _snapshot_root.is_empty() else _snapshot_root.path_join("plugins").path_join(manifest.id)
		paths.append(manifest_folder.path_join("plugin.json"))
	var result := PluginLoader.new().load_paths(paths, registry, _decision == true) if not paths.is_empty() else {"loaded": [], "errors": [], "disabled": []}
	if not result.errors.is_empty():
		registry.dispose(); registry = null
		if not _snapshot_root.is_empty(): PluginPack.remove_snapshot(_snapshot_root); _snapshot_root = ""
		report.errors.append_array(result.errors)
		return result
	_install_motion_dispatch()
	var active := _builtin_ids.duplicate(); active.append_array(result.loaded)
	identity = _identity_for(active)
	score_key = PluginScores.key_for(_chart_id, identity)
	report.identity = identity.duplicate(); report.score_key = score_key
	report.disabled = result.disabled.duplicate()
	chart_data = ChartCodec.expand(_raw, registry.field_schema())
	if chart_data.has("defaults_schema") and not result.disabled.is_empty():
		report.notices.append("Defaults from disabled script plugins are unavailable; their chart features are disabled.")
	_opened = true
	return result

func _validate_chart_data(data: Dictionary) -> Array:
	var errors := []
	var enabled := _enabled_ids()
	for manifest in _ordered:
		if manifest.tier == "declarative" and manifest.id in enabled:
			for error in PluginDeclarative.validate_chart(data, manifest.fields): errors.append(str(manifest.id) + ": " + str(error))
	return errors

## Polled by the UI only for plugin songs. Formula failures are bounded and
## deduplicated, while their failed draw/motion outputs are discarded safely.
func runtime_notices() -> Array:
	var notices: Array = report.get("notices", []).duplicate()
	if registry == null: return notices
	for owned in registry._owned:
		if owned.object is PluginDeclarative:
			for error in owned.object.runtime_errors:
				var message := str(owned.plugin) + ": " + str(error)
				if message not in notices: notices.append(message)
				if notices.size() >= 32: return notices
	return notices

func _builtin_scope() -> PluginRegistry:
	var scope := PluginRegistry.standard().fork_scope()
	var optional_paths := []
	for id in _builtin_ids:
		if id not in PluginScores.STANDARD_IDS: optional_paths.append("res://plugins/builtin/" + str(id) + "/plugin.json")
	if not optional_paths.is_empty():
		var result := PluginLoader.new().load_paths(optional_paths, scope, true)
		if not result.errors.is_empty(): scope.errors.append_array(result.errors)
	return scope

func _install_motion_dispatch() -> void:
	var available := {}
	for id in registry.records.motions:
		if id == "follow_track": continue
		var callback: Callable = registry.records.motions[id].get("callback", Callable())
		if callback.is_valid(): available[id] = callback
	if available.is_empty(): return
	var original := registry.get_entry("motions", "follow_track")
	var router := MotionRouter.new()
	_motion_router = router
	router.fallback = original.get("callback", Callable()); router.motions = available
	var routed := original.duplicate()
	routed.callback = router.route
	registry.records.motions.follow_track = routed

## The caller releases GameCore/Renderer/StageFx before closing the scope. Owned
## Nodes, registered signals and teardown hooks are cleaned; arbitrary script
## globals/external side effects remain the trusted author's responsibility.
func close() -> void:
	if registry != null:
		registry.dispose(); registry = null
	if not _snapshot_root.is_empty(): PluginPack.remove_snapshot(_snapshot_root); _snapshot_root = ""
	identity = []; score_key = ""; chart_data = {}
	_selected.clear(); _folders.clear(); _ordered.clear(); _builtin_ids.clear()
	_raw.clear(); _folder = ""; _chart_id = ""; _hash = ""
	_decision = null; _prepared = false; _opened = false; _motion_router = null
