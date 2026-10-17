## Fixed, ordered dispatch. Providers own the rules; this runner knows no note kinds.
class_name RulePipeline
extends RefCounted

var _phases := {}

func _init(registry: PluginRegistry) -> void:
	for entry in registry.ordered("rules"):
		var phase := str(entry.get("phase", ""))
		if phase.is_empty() or not entry.get("callback", Callable()).is_valid(): continue
		if not _phases.has(phase): _phases[phase] = []
		_phases[phase].append(entry.callback)

func run(phase: String, context: Dictionary) -> void:
	for callback in _phases.get(phase, []):
		if context.get("stop", false): break
		callback.call(context)
