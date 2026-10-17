## Compatibility facade for the standard plugin's unchanged rank thresholds.
class_name Ranks

const Data = preload("res://plugins/builtin/standard_rules/ranks.gd")
const TIERS = Data.TIERS

static func _provider() -> Script:
	return PluginRegistry.standard().service_script("ranks")

static func rank_of(score: int) -> String: return _provider().rank_of(score)
static func index_of(name: String) -> int: return _provider().index_of(name)
static func min_of(name: String) -> int: return _provider().min_of(name)
static func next_of(name: String) -> Dictionary: return _provider().next_of(name)
static func tint_of(name: String) -> Color: return _provider().tint_of(name)
static func glow_of(name: String) -> float: return _provider().glow_of(name)
static func demo_stats(name: String) -> Dictionary: return _provider().demo_stats(name)
