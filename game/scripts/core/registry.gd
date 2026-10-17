## Plugin API 1. Catalogs contain providers, never song/session state.
class_name PluginRegistry
extends RefCounted

const API := 1
const CATEGORIES := ["events", "note_kinds", "flags", "rules", "motions", "track_geometry", "channels", "elements", "validators"]
var records := {}
var services := {}
var manifests := {}
var fields := []
var errors := []
var _owner := ""
var _owned := []
var _connections := []
var _teardowns := []
var _disposing := false
static var _builtins: PluginRegistry
static var _standard: PluginRegistry
const STANDARD_IDS := ["standard_chart", "standard_render", "standard_rules", "standard_stage"]

func _init() -> void:
	for category in CATEGORIES: records[category] = {}

static func builtins() -> PluginRegistry:
	if _builtins == null:
		var registry := PluginRegistry.new()
		var loader = load("res://scripts/core/plugin_loader.gd").new()
		var result: Dictionary = loader.load_builtin(registry)
		if not result.errors.is_empty():
			push_error("Built-in plugins: " + "; ".join(result.errors))
		_builtins = registry
	return _builtins

## Separate immutable standard registry, never a filtered copy of a catalog in
## which an optional built-in may have replaced an original provider.
static func standard() -> PluginRegistry:
	if _standard == null:
		var registry := PluginRegistry.new()
		var paths := []
		for id in STANDARD_IDS: paths.append("res://plugins/builtin/" + id + "/plugin.json")
		var loader = load("res://scripts/core/plugin_loader.gd").new()
		var result: Dictionary = loader.load_paths(paths, registry, true)
		if not result.errors.is_empty():
			push_error("Standard plugins: " + "; ".join(result.errors))
		_standard = registry
	return _standard

func begin_plugin(manifest: Dictionary) -> void:
	_owner = str(manifest.id)
	manifests[_owner] = manifest.duplicate(true)
	for field in manifest.get("fields", []):
		var copy: Dictionary = field.duplicate(true)
		copy["plugin"] = _owner
		fields.append(copy)

func end_plugin() -> void:
	_owner = ""

func register(category: String, id: String, provider: Dictionary, replace := false) -> bool:
	if not records.has(category):
		errors.append("Unknown registry category: " + category); return false
	if id.is_empty() or _owner.is_empty():
		errors.append("Registration requires an id and active plugin"); return false
	if records[category].has(id) and not replace:
		errors.append("Duplicate %s provider: %s" % [category, id]); return false
	var item := provider.duplicate()
	item["id"] = id; item["plugin"] = _owner
	item["order"] = int(item.get("order", 0))
	records[category][id] = item
	return true

func register_service(id: String, script: Script, replace := false) -> bool:
	if _owner.is_empty() or script == null:
		errors.append("Invalid service: " + id); return false
	if services.has(id) and not replace:
		errors.append("Duplicate service: " + id); return false
	services[id] = {"script": script, "plugin": _owner}
	return true

func service_script(id: String) -> Script:
	if not services.has(id):
		push_error("Missing plugin service: " + id); return null
	return services[id].script

func get_entry(category: String, id: String) -> Dictionary:
	# Avoid allocating two unused fallback dictionaries on every successful lookup.
	var entries: Variant = records.get(category)
	if entries != null:
		var value: Variant = entries.get(id)
		if value != null: return value
	return {}

func ordered(category: String, phase := "") -> Array:
	var entries := []
	for entry in records.get(category, {}).values():
		if phase.is_empty() or entry.get("phase", "") == phase: entries.append(entry)
	entries.sort_custom(func(a, b): return a.order < b.order if a.order != b.order else str(a.id) < str(b.id))
	return entries

func field_schema() -> Array:
	return fields.duplicate(true)

func fork_scope() -> PluginRegistry:
	var scope := PluginRegistry.new()
	scope.records = records.duplicate(true)
	scope.services = services.duplicate()
	scope.manifests = manifests.duplicate(true)
	scope.fields = fields.duplicate(true)
	return scope

## Cooperative ownership only. Trusted GDScript is never a sandbox.
func own(value: Object) -> Object:
	if value == null or _owner.is_empty():
		errors.append("Owned object requires an active plugin"); return null
	_owned.append({"plugin": _owner, "object": value})
	return value

## Called in reverse installation order, with this scope as its sole argument.
## A plugin's optional static teardown(registry) is registered by the loader.
func on_close(callback: Callable) -> bool:
	if _owner.is_empty() or not callback.is_valid():
		errors.append("Teardown requires an active plugin and valid callback"); return false
	_teardowns.append({"plugin": _owner, "callback": callback})
	return true

func connect_owned(source: Signal, callback: Callable, flags := 0) -> Error:
	if _owner.is_empty() or not callback.is_valid():
		errors.append("Owned connection requires an active plugin"); return ERR_INVALID_PARAMETER
	var status := source.connect(callback, flags)
	if status == OK: _connections.append({"plugin": _owner, "signal": source, "callback": callback})
	return status

## Commit a transactional load without sharing its ownership lists with the base.
func adopt(working: PluginRegistry) -> void:
	records = working.records; services = working.services
	manifests = working.manifests; fields = working.fields
	_owned.append_array(working._owned); working._owned.clear()
	_connections.append_array(working._connections); working._connections.clear()
	_teardowns.append_array(working._teardowns); working._teardowns.clear()

func dispose() -> void:
	if self == _builtins or self == _standard or _disposing: return
	_disposing = true
	for i in range(_teardowns.size() - 1, -1, -1):
		var callback: Callable = _teardowns[i].callback
		if callback.is_valid(): callback.call(self)
	_teardowns.clear()
	for connection in _connections:
		var source: Signal = connection.signal
		if not source.is_null() and is_instance_valid(source.get_object()) and source.is_connected(connection.callback):
			source.disconnect(connection.callback)
	_connections.clear()
	for i in range(_owned.size() - 1, -1, -1):
		var object: Object = _owned[i].object
		if is_instance_valid(object) and not object is RefCounted: object.free()
	_owned.clear()
	records.clear(); services.clear(); manifests.clear(); fields.clear(); errors.clear(); _owner = ""
	_disposing = false
