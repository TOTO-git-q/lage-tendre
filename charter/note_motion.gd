extends RefCounted
## Note motion plugins (open set). A note falls straight to its landing position unless it has a
## motion; a motion only changes where it travels during the fall and always ends exactly at the
## landing position, so judgement stays track-centric. Stored in chart.ext.json until the engine
## supports it. Each plugin in res://motions/ declares:
##   const ID, LABEL; static params() -> [{key,label,unit,default,min,max,step} | {key,label,options}]
##   static offset(p, r, ctx) -> x offset (normalized line units) from the landing x when r seconds remain
##   static start(p, ctx) -> offset where the note appears (for the drag handle), or NAN if none
##   static with_start(p, offset, ctx) -> params after dragging the start handle

const FALL := 1.3
const BUILTIN := ["res://motions/horizontal.gd", "res://motions/follow_track.gd"]
static var _types: Array = []

static func types() -> Array:
	if not _types.is_empty(): return _types
	var paths := BUILTIN.duplicate()
	for file in DirAccess.get_files_at("res://motions"):
		var path := "res://motions/" + file.trim_suffix(".remap")
		if path.ends_with(".gd") and not path in paths: paths.append(path)
	for path in paths:
		var script = load(path)
		if script != null: _types.append(script)
	return _types

static func find(id: String):
	for t in types():
		if t.ID == id: return t
	return null

static func defaults(id: String) -> Dictionary:
	var t = find(id)
	var out := {}
	if t == null: return out
	for p in t.params(): out[p.key] = p.default
	return out

## Sampled path for drawing: [[r, x], ...] from appearance (r = FALL) to landing (r = 0).
static func path(motion: Dictionary, ctx: Dictionary, steps: int = 24) -> Array:
	var t = find(str(motion.get("type", "")))
	var out := []
	if t == null: return out
	var p: Dictionary = defaults(t.ID); p.merge(motion.get("params", {}), true)
	for i in steps + 1:
		var r := FALL * (1.0 - float(i) / steps)
		out.append([r, float(ctx.land_x) + t.offset(p, r, ctx)])
	return out
