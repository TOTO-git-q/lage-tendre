## Ordered standard judgement stages. Numerical rules remain in the original runtime.
extends RefCounted
const Runtime = preload("res://plugins/builtin/standard_rules/runtime.gd")

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	registry.register_service("game_session", Runtime)
	registry.register_service("ranks", preload("res://plugins/builtin/standard_rules/ranks.gd"))
	var updates := [["clock", clock], ["autoplay", autoplay], ["note_update", notes], ["cue_update", cues], ["finish", finish]]
	for index in updates.size():
		registry.register("rules", updates[index][0], {"phase": "update", "order": index * 10, "callback": updates[index][1]})
	registry.register("rules", "fingering", {"phase": "reset", "order": 0, "callback": fingering})
	registry.register("rules", "midpoint_cut", {"phase": "reset", "order": 10, "callback": midpoint})
	var presses := ["key_input", "nearest_time", "slap_guard", "early_snap", "chord_follow", "note_head", "scoring", "hit_feedback"]
	for index in presses.size():
		registry.register("rules", presses[index], {"phase": "key_press", "order": index * 10, "callback": Callable(Runtime, "rule_" + presses[index])})
	for id in ["yellow_catch", "hold_body", "pedal", "release"]:
		registry.register("rules", id, {"phase": id, "order": 0, "callback": Callable(Runtime, "rule_" + id)})

static func clock(context: Dictionary) -> void: context.runtime.clock_now = context.t
static func autoplay(context: Dictionary) -> void:
	if context.runtime.autoplay: context.runtime._autoplay(context.t)
static func notes(context: Dictionary) -> void: context.runtime._update_notes(context.t)
static func cues(context: Dictionary) -> void: context.runtime._update_cues(context.t)
static func finish(context: Dictionary) -> void: context.runtime._finish_update(context.t)
static func fingering(context: Dictionary) -> void: context.runtime._fingering()
static func midpoint(context: Dictionary) -> void: context.runtime._cut_windows()
