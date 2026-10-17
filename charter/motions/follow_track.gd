extends RefCounted
## 跟随轨道: the note rides its track while falling (the look of every chart written so far).
const ID := "follow_track"
const LABEL := "跟随轨道"

static func params() -> Array:
	return [{"key": "amount", "label": "跟随程度", "unit": "%", "default": 100.0, "min": 0.0, "max": 100.0, "step": 10.0}]

static func offset(p: Dictionary, r: float, ctx: Dictionary) -> float:
	var doc = ctx.doc; var n: Dictionary = ctx.note
	var segs: Array = doc.core.tl.get(int(n.light), [])
	var land = doc.state_at(segs, float(n.t)); var then = doc.state_at(segs, float(n.t) - r)
	if not land.alive or not then.alive: return 0.0
	var x_then: float = then.x + (float(n.u) - 0.5) * then.w
	var x_land: float = land.x + (float(n.u) - 0.5) * land.w
	return (x_then - x_land) * float(p.amount) / 100.0

static func start(_p: Dictionary, _ctx: Dictionary) -> float:
	return NAN

static func with_start(p: Dictionary, _x: float, _ctx: Dictionary) -> Dictionary:
	return p
