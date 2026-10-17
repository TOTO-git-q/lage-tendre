## Motion only returns visual state. It never changes note times or hit geometry.
extends RefCounted
const TYPES := ["straight","follow_track","horizontal"]

static func finite(v) -> bool: return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v))

static func normalize(raw: Dictionary,note: Dictionary) -> void:
	var motion=raw.get("motion",{"type":"straight"})
	note["motion"]=motion.duplicate(true) if motion is Dictionary else motion
	if motion is Dictionary and not note.motion.has("type"): note.motion["type"]="straight"

static func horizontal_valid(motion: Dictionary) -> bool:
	for key in ["x0","begin","end"]:
		if motion.has(key) and not finite(motion[key]): return false
	if motion.get("ease","inout") not in SU.EASES: return false
	var begin := float(motion.get("begin",0.0)); var end := float(motion.get("end",1.0))
	return begin >= 0.0 and end <= 1.0 and end > begin and float(motion.get("x0",0.5)) >= -2.0 and float(motion.get("x0",0.5)) <= 3.0

static func validate(context: Dictionary) -> void:
	if context.chart.is_empty(): return
	for note in context.chart.notes:
		var motion=note.get("motion",{"type":"straight"})
		if not motion is Dictionary:
			context.chart.warnings.append("Note motion must be an object"); note.motion={"type":"straight"}; continue
		var type := str(motion.get("type","straight"))
		if context.registry.get_entry("motions",type).is_empty():
			context.chart.warnings.append("Unknown note motion: "+type); note.motion={"type":"straight"}; continue
		if type=="horizontal" and not horizontal_valid(motion):
			context.chart.warnings.append("Invalid horizontal motion at t="+str(note.t)); note.motion={"type":"straight"}

static func straight(renderer,note: Dictionary,state: Dictionary) -> Dictionary:
	var landing: Dictionary=renderer._light_at(renderer.f.tl.get(note.light,[]),float(note.t))
	if not landing.get("alive",false): return state
	var out := landing.duplicate()
	out.alpha=1.0
	return out

static func horizontal(renderer,note: Dictionary,state: Dictionary) -> Dictionary:
	var out := straight(renderer,note,state)
	if not out.get("alive",false): return out
	var motion: Dictionary=note.get("motion",{})
	var target: float=out.x+(note.u-0.5)*out.w
	if out.get("geometry","lane")!="lane":
		var position: Callable=renderer.registry.get_entry("track_geometry",str(out.geometry)).get("note_x",Callable())
		if position.is_valid(): target=position.call(out,float(note.u))
	var progress := clampf(renderer.visual_progress(int(note.light),float(note.t)) if renderer.has_method("visual_progress") else 1.0-(float(note.t)-float(renderer.f.t))/maxf(0.001,float(renderer.f.fall)),0.0,1.0)
	var begin := float(motion.get("begin",0.0)); var end := float(motion.get("end",1.0))
	# Validation guarantees end > begin. Preserve exact endpoints even for tiny windows.
	var f := 1.0 if progress>=end else 0.0 if progress<=begin else (progress-begin)/(end-begin)
	var dx := (float(motion.get("x0",0.5))-target)*(1.0-SU.ease_by(str(motion.get("ease","inout")),f))
	if out.get("geometry","lane")!="lane":
		var transform: Callable=renderer.registry.get_entry("track_geometry",str(out.geometry)).get("visual_transform",Callable())
		if transform.is_valid(): return transform.call(out,float(out.x)+dx,float(out.w))
	out=out.duplicate()
	out.x+=dx
	if out.has("sections"):
		out.sections=out.sections.duplicate(true)
		for section in out.sections: section[0]+=dx; section[1]+=dx
	return out

## Optional shape-hold tessellation hints, expressed through the renderer clock.
## The cubic eases have |second derivative| <= 12 on each half of inout.
## |amplitude| * 12 * dq^2 / 8 bounds their scalar chord error.
const HOLD_EASE_ERROR := 0.00001
const MAX_HOLD_CUTS := 2048
static func hold_cuts(renderer,note: Dictionary,ta: float,tb: float,x_range: Array) -> Dictionary:
	var motion: Dictionary=note.get("motion",{})
	if not horizontal_valid(motion): return {"times":[],"inset":0.0,"errors":["Invalid horizontal hold motion"]}
	var begin:=float(motion.get("begin",0.0)); var end:=float(motion.get("end",1.0))
	if x_range.size()!=2 or not finite(x_range[0]) or not finite(x_range[1]) or float(x_range[1])<float(x_range[0]):
		return {"times":[],"inset":0.0,"errors":["Horizontal hold requires a finite ordered target range"]}
	var x0:=float(motion.get("x0",0.5))
	var amplitude:=maxf(absf(x0-float(x_range[0])),absf(x0-float(x_range[1])))
	if amplitude>pow(float(MAX_HOLD_CUTS-2),2)*HOLD_EASE_ERROR/1.5:
		return {"times":[],"inset":0.0,"errors":["Horizontal hold cut budget exceeded; no partial mesh drawn"]}
	var step:=minf(0.01,sqrt(HOLD_EASE_ERROR/maxf(1.5*amplitude,1e-20)))
	var count:=maxi(2,int(ceil(1.0/step)))
	# Include the piecewise inout midpoint exactly, not merely near it.
	if count%2!=0: count+=1
	if count+1>MAX_HOLD_CUTS: return {"times":[],"inset":0.0,"errors":["Horizontal hold cut budget exceeded; no partial mesh drawn"]}
	var times:=[]
	for i in count+1:
		var p:=lerpf(begin,end,float(i)/count)
		var tau: float=renderer.visual_time(int(note.light),p) if renderer.has_method("visual_time") else float(renderer.f.t)+(1.0-p)*float(renderer.f.fall)
		if not is_finite(tau): return {"times":[],"inset":0.0,"errors":["Horizontal hold has non-finite visual time"]}
		if tau>ta and tau<tb: times.append(tau)
	# Inward margin for the scalar easing error and packed float32 rounding.
	return {"times":times,"inset":2.0*HOLD_EASE_ERROR+0.0000002,"errors":[]}

## Read-only conversion of the actual charter motion sidecar. IDs use the
## current editor's %.6f|light|k identity, not note index or invented u keys.
static func convert_sidecar(chart: Dictionary,sidecar: Dictionary,scope: PluginRegistry) -> Dictionary:
	if not sidecar.get("motions",{}) is Dictionary: return {"errors":["motions must be an object"]}
	if not chart.get("notes",[]) is Array: return {"errors":["notes must be an array"]}
	for note in chart.get("notes",[]):
		if not note is Dictionary or not finite(note.get("t")) or not finite(note.get("light")) or (note.has("u") and not finite(note.u)):
			return {"errors":["Malformed note in motion converter"]}
	var out := chart.duplicate(true); var remaining := sidecar.duplicate(true); var errors := []; var used := {}
	var normalized := ChartLib.validate(chart,scope)
	var timelines := ChartLib.build_timelines(normalized.lights,scope)
	for note in out.get("notes",[]):
		var key := "%.6f|%d|%d" % [float(note.t),int(note.light),int(note.get("k",-1))]
		if not sidecar.get("motions",{}).has(key): continue
		if used.has(key): errors.append("Ambiguous charter motion identity: "+key); continue
		used[key]=true
		var source=sidecar.motions[key]
		if not source is Dictionary or not source.get("params",{}) is Dictionary: errors.append("Invalid charter motion: "+key); continue
		var type := str(source.get("type",""))
		if type=="follow_track":
			if source.get("params",{}).get("amount",100.0)!=100.0:
				errors.append("Partial editor follow_track amount is not the standard runtime behavior: "+key); continue
			note["motion"]={"type":"follow_track"}
		elif type=="horizontal":
			var params: Dictionary=source.get("params",{})
			var st := ChartLib.light_at(timelines.get(int(note.light),[]),float(note.t),scope)
			if not st.alive: errors.append("No live landing track for "+key); continue
			var land: float=st.x+(float(note.get("u",0.5))-0.5)*st.w
			if st.get("geometry","lane")!="lane":
				var position: Callable=scope.get_entry("track_geometry",str(st.geometry)).get("note_x",Callable())
				if position.is_valid(): land=position.call(st,float(note.get("u",0.5)))
			var from_value=params.get("from",-3.0); var begin=params.get("begin",0.0); var end=params.get("end",70.0)
			if not finite(from_value) or not finite(begin) or not finite(end): errors.append("Non-finite charter motion: "+key); continue
			note["motion"]={"type":"horizontal","x0":land+float(from_value)/15.0,"begin":float(begin)/100.0,"end":float(end)/100.0,"ease":str(params.get("ease","out"))}
			if not horizontal_valid(note.motion): errors.append("Invalid charter horizontal parameters: "+key); continue
		else: errors.append("Unsupported charter motion: "+type); continue
		remaining.motions.erase(key)
	if not errors.is_empty(): return {"errors":errors}
	if not used.is_empty():
		var plugins: Array=out.get("plugins",[]).duplicate(true); var found := false
		for plugin in plugins:
			if plugin.get("id","")=="note_motion": found=true
		if not found: plugins.append({"id":"note_motion","version":"1.0.0"})
		out["plugins"]=plugins
	return {"chart":out,"sidecar":remaining,"errors":[]}
