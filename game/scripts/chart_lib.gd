## Compatibility facade; all behavior is supplied by registered plugins (API 1).
class_name ChartLib

const TYPES = BuiltinChartData.TYPES
const FROMS = BuiltinChartData.FROMS
const DEAD = BuiltinChartData.DEAD

static func _provider() -> Script:
	return PluginRegistry.standard().service_script("chart")

static func centers(x: float, w: float) -> int:
	return _provider().centers(x, w)

static func build_timelines(events: Array, scope: PluginRegistry = null) -> Dictionary:
	var registry := scope if scope != null else PluginRegistry.standard()
	return registry.service_script("chart").build_timelines(events, registry)

static func light_at(segs, t: float, scope: PluginRegistry = null) -> Dictionary:
	var registry := scope if scope != null else PluginRegistry.standard()
	return registry.service_script("chart").light_at(segs, t, registry)

static func _grow_of(v) -> Array:
	return _provider()._grow_of(v)

static func build_cues(events: Array, scope: PluginRegistry = null) -> Array:
	var registry := scope if scope != null else PluginRegistry.standard()
	return registry.service_script("chart").build_cues(events, registry)

static func demo() -> Dictionary:
	return _provider().demo()

static func validate(raw, scope: PluginRegistry = null) -> Dictionary:
	var registry := scope if scope != null else PluginRegistry.standard()
	var context := {"raw": raw, "chart": {}, "registry": registry}
	for validator in registry.ordered("validators"):
		var callback: Callable = validator.get("callback", Callable())
		if callback.is_valid(): callback.call(context)
	return context.chart
