## Layer/z ordering and provider dispatch, with no concrete drawing in the core.
class_name RenderPipeline
extends RefCounted

var elements := []
var groups := {}

func _init(registry: PluginRegistry) -> void:
	elements = registry.ordered("elements")
	for entry in elements:
		var phase := str(entry.get("phase", ""))
		if phase.is_empty(): continue
		if not groups.has(phase): groups[phase] = []
		groups[phase].append(entry)

func draw(phase: String, renderer: Node2D, canvas: CanvasItem) -> void:
	for entry in groups.get(phase, []):
		var callback: Callable = entry.get("callback", Callable())
		if callback.is_valid(): callback.call(renderer, canvas)
