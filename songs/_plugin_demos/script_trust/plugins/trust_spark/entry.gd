@static_unload
extends RefCounted

# Relative preloads are fresh inside the verified per-session snapshot.
const Palette = preload("spark_palette.gd")
const MARKER := "user://plugin_demos/trust_spark_loaded.txt"
static var owned_state: Node

# This observable side effect deliberately demonstrates why trust is required
# before ResourceLoader.load, not merely before install(). It contains no user data.
static func _static_init() -> void:
	DirAccess.make_dir_recursive_absolute(MARKER.get_base_dir())
	var file := FileAccess.open(MARKER, FileAccess.WRITE)
	if file != null:
		file.store_string("The trusted demo's GDScript was loaded.\n"); file.close()

static func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:
	owned_state = registry.own(Node.new())
	owned_state.name = "TrustSparkDemoState"
	owned_state.set_meta("demo_script_active", true)
	registry.register("elements", "trust_spark", {"phase": "plugin.trust_spark", "order": 43, "additive": true, "callback": draw})

static func draw(renderer, canvas: CanvasItem) -> void:
	if renderer.f.is_empty() or not renderer.f.get("play", false): return
	var color := Palette.color()
	renderer.text(canvas, "SCRIPT ACTIVE", 960.0, 112.0, 15, 0.75, "center", 3, Fonts.ui(), color)
	var t := float(renderer.f.t)
	var fall := maxf(0.001, float(renderer.f.fall))
	var states: Dictionary = renderer.f.get("light_by_id_raw", renderer.f.get("light_by_id", {}))
	for note in renderer.f.notes:
		if note.state != "pending" or not states.has(note.light): continue
		var progress: float = renderer.visual_progress(int(note.light), float(note.t)) if renderer.has_method("visual_progress") else 1.0 - (float(note.t) - t) / fall
		if progress < 0.0 or progress > 1.0: continue
		var state: Dictionary = renderer._land_st(note, states[note.light])
		if not state.get("alive", false): continue
		var point: Dictionary = renderer._note_at(state, note, progress)
		var radius: float = absf(point.kw) * (0.8 if note.big else 0.58)
		for i in 4:
			var angle := t * 1.5 + float(i) * PI / 2.0
			var center := Vector2(point.x, point.y) + Vector2(cos(angle), sin(angle)) * radius
			var size: float = maxf(1.5, float(point.s) * 4.5)
			var diamond := PackedVector2Array([center + Vector2(0, -size), center + Vector2(size * 0.6, 0), center + Vector2(0, size), center + Vector2(-size * 0.6, 0)])
			canvas.draw_colored_polygon(diamond, Color(color.r, color.g, color.b, color.a * progress))

static func teardown(_registry: PluginRegistry) -> void:
	# The registry frees the owned node. Drop the plugin's own static reference.
	owned_state = null
	if FileAccess.file_exists(MARKER): DirAccess.remove_absolute(MARKER)
