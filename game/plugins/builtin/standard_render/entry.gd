## Every real draw layer and its ordered elements use the same registry as song plugins.
extends RefCounted
const Runtime = preload("res://plugins/builtin/standard_render/runtime.gd")

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	registry.register_service("renderer", Runtime)
	registry.register("motions", "follow_track", {"callback": follow_track})
	registry.register("elements", "background", {"order": 0, "setup": background})
	registry.register("elements", "key_guides", {"phase": "track", "order": 10, "additive": false, "callback": key_guides, "repeat_mipmap": false})
	registry.register("elements", "dividers", {"phase": "track", "order": 11, "additive": false, "callback": dividers, "repeat_mipmap": false})
	registry.register("elements", "tracks", {"phase": "track", "order": 12, "additive": false, "callback": tracks, "repeat_mipmap": false})
	registry.register("elements", "lane_edges", {"phase": "beam", "order": 20, "additive": true, "callback": lane_edges, "repeat_mipmap": true})
	registry.register("elements", "judgement_line", {"phase": "beam", "order": 21, "additive": true, "callback": judgement_line, "repeat_mipmap": true})
	registry.register("elements", "pedal_receptors", {"phase": "beam", "order": 22, "additive": true, "callback": pedal_receptors, "repeat_mipmap": true})
	registry.register("elements", "holds", {"phase": "holds", "order": 30, "additive": true, "callback": holds, "repeat_mipmap": false})
	registry.register("elements", "notes", {"phase": "note", "order": 40, "additive": false, "callback": notes, "repeat_mipmap": false})
	registry.register("elements", "hit_effects", {"phase": "fx", "order": 50, "additive": true, "callback": hit_effects, "repeat_mipmap": false})
	registry.register("elements", "hud", {"phase": "hud", "order": 60, "additive": false, "callback": hud, "repeat_mipmap": false})
	registry.register("elements", "hud_additive", {"phase": "hud_add", "order": 70, "additive": true, "callback": hud_additive, "repeat_mipmap": false})
	registry.register("elements", "grain", {"order": 80, "setup": grain})
	registry.register("elements", "vignette", {"order": 90, "setup": vignette})

static func follow_track(renderer, note: Dictionary, state: Dictionary) -> Dictionary:
	return renderer._follow_track_state(note, state)

static func background(renderer) -> void: renderer._setup_background()
static func grain(renderer) -> void: renderer._setup_grain()
static func vignette(renderer) -> void: renderer._setup_vignette()
static func key_guides(renderer, canvas: CanvasItem) -> void: renderer._paint_key_guides(canvas)
static func dividers(renderer, canvas: CanvasItem) -> void: renderer._paint_dividers(canvas)
static func tracks(renderer, canvas: CanvasItem) -> void: renderer._paint_track_surfaces(canvas)
static func lane_edges(renderer, canvas: CanvasItem) -> void: renderer._paint_lane_edges(canvas)
static func judgement_line(renderer, canvas: CanvasItem) -> void: renderer._paint_judge_line(canvas)
static func pedal_receptors(renderer, canvas: CanvasItem) -> void: renderer._paint_pedal_receptors(canvas)
static func holds(renderer, canvas: CanvasItem) -> void: renderer._paint_holds(canvas)
static func notes(renderer, canvas: CanvasItem) -> void: renderer._paint_note_sprites(canvas)
static func hit_effects(renderer, canvas: CanvasItem) -> void: renderer._paint_fx(canvas)
static func hud(renderer, canvas: CanvasItem) -> void: renderer._paint_hud(canvas)
static func hud_additive(renderer, canvas: CanvasItem) -> void: renderer._paint_hud_add(canvas)
