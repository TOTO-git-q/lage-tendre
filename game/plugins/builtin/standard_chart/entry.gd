## Original chart syntax, note vocabulary, geometry and its validator.
extends RefCounted
const Runtime = preload("res://plugins/builtin/standard_chart/runtime.gd")

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	registry.register_service("chart", Runtime)
	for id in Runtime.TYPES:
		registry.register("events", id, {"target": "lights", "sample": Runtime.sample_light, "compile": Runtime.compile_light, "validate": Runtime.validate_light, "opens": id == "on", "closes": id == "off", "tail": 0.2 if id == "off" else 0.0, "pedal": id != "off", "cue_duration": id == "sweep"})
	registry.register("note_kinds", "tap", {"render": plan_tap, "holds": false})
	registry.register("note_kinds", "hold", {"render": plan_hold, "holds": true})
	registry.register("flags", "ex", {"target": "notes", "order": 0, "normalize": normalize_ex})
	registry.register("flags", "big", {"target": "notes", "order": 1, "normalize": normalize_big})
	registry.register("flags", "grow", {"target": "notes", "order": 2, "normalize": normalize_grow})
	registry.register("track_geometry", "lane", {"sample": Runtime.light_at, "sections": sections})
	registry.register("validators", "standard_chart", {"order": 0, "callback": validate})

static func validate(context: Dictionary) -> void:
	context.chart = Runtime.validate(context.raw, context.registry)

static func sections(state: Dictionary) -> Array:
	return [[state.x - state.w / 2.0, state.x + state.w / 2.0]] if state.get("alive", false) else []

static func normalize_ex(raw: Dictionary, note: Dictionary) -> void:
	note.ex = raw.get("ex", false) == true

static func normalize_big(raw: Dictionary, note: Dictionary) -> void:
	note.big = raw.get("big", false) == true
	note.wl = 1.0 if note.big else 0.0

static func normalize_grow(raw: Dictionary, note: Dictionary) -> void:
	note.grow = Runtime._grow_of(raw.get("grow"))

static func plan_tap(renderer, note: Dictionary, state: Dictionary, t: float, fall: float, p_min: float, p_quick: float, p_end: float) -> void:
	renderer._plan_tap(note, state, t, fall, p_min, p_quick, p_end)

static func plan_hold(renderer, note: Dictionary, state: Dictionary, t: float, fall: float, p_min: float, p_quick: float, p_end: float) -> void:
	renderer._plan_hold(note, state, t, fall, p_min, p_quick, p_end)
