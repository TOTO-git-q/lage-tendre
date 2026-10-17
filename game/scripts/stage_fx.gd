## Compatibility facade; all behavior is supplied by registered plugins (API 1).
class_name StageFx
extends RefCounted

const CH = BuiltinStageData.CH
const MODE = BuiltinStageData.MODE

var registry: PluginRegistry
var _runtime: RefCounted

func _init(scope: PluginRegistry = null) -> void:
	registry = scope if scope != null else PluginRegistry.standard()
	_runtime = registry.service_script("stage").new()
	_runtime.configure(registry)

var tw: Dictionary:
	get: return _runtime.tw
	set(value): _runtime.tw = value

var imp: Array:
	get: return _runtime.imp
	set(value): _runtime.imp = value

var rings: Array:
	get: return _runtime.rings
	set(value): _runtime.rings = value

var mode: String:
	get: return _runtime.mode
	set(value): _runtime.mode = value

var summary: Dictionary:
	get: return _runtime.summary
	set(value): _runtime.summary = value

static func ease_fn(name: String, k: float) -> float:
	return PluginRegistry.standard().service_script("stage").ease_fn(name, k)

func _analyse(chart: Dictionary) -> Dictionary:
	return _runtime._analyse(chart)

func _bar_at(A: Dictionary, t: float) -> int:
	return _runtime._bar_at(A, t)

func _onset_at_or_after(A: Dictionary, t: float, within: float):
	return _runtime._onset_at_or_after(A, t, within)

func _onset_before(A: Dictionary, t: float):
	return _runtime._onset_before(A, t)

func _plan(chart: Dictionary) -> Array:
	return _runtime._plan(chart)

func _lint(ev: Array, chart: Dictionary) -> Array:
	return _runtime._lint(ev, chart)

func build(chart: Dictionary) -> void:
	_runtime.build(chart)

func _base(c: String, t: float, upto := -1) -> float:
	return _runtime._base(c, t, upto)

func at(t: float) -> Dictionary:
	return _runtime.at(t)

static func rest() -> Dictionary:
	return PluginRegistry.standard().service_script("stage").rest()

