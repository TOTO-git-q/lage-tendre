## Optional visual motion. Standard follow_track stays owned by standard_render.
extends RefCounted
const Runtime=preload("res://plugins/builtin/note_motion/runtime.gd")
static func install(registry: PluginRegistry,_manifest: Dictionary,_folder: String) -> void:
	registry.register("motions","straight",{"callback":Runtime.straight})
	registry.register("motions","horizontal",{"callback":Runtime.horizontal,"hold_cuts":Runtime.hold_cuts})
	registry.register("flags","note_motion",{"target":"notes","order":20,"normalize":Runtime.normalize})
	registry.register("validators","note_motion",{"order":30,"callback":Runtime.validate})
