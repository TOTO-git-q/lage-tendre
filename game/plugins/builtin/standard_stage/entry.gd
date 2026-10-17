## Original stage events and bounded camera/fx channels.
extends RefCounted
const Runtime = preload("res://plugins/builtin/standard_stage/runtime.gd")

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	registry.register_service("stage", Runtime)
	for id in Runtime.CH:
		var values: Array = Runtime.CH[id]
		registry.register("channels", id, {"default": values[0], "min": values[1], "max": values[2]})
	for id in ["tween", "impulse", "ring"]:
		registry.register("events", "fx." + id, {"target": "fx", "compile": compile_event})

static func compile_event(stage, event: Dictionary) -> void:
	stage._compile_event(event)
