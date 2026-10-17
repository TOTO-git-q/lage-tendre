## Exact integral of positive piecewise eased scroll velocity; no clock/judgement changes.
extends RefCounted
const MIN_SPEED:=0.05
const MAX_SPEED:=8.0
const MAX_TIME:=86400.0
const MAX_EVENTS:=1024
const MAX_TRACKS:=1024
static func finite(v) -> bool: return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v))
static func valid_speed(v) -> bool: return finite(v) and float(v)>=MIN_SPEED and float(v)<=MAX_SPEED

static func ease_area(ease: String,u: float) -> float:
	u=clampf(u,0.0,1.0)
	match ease:
		"linear": return u*u*0.5
		"in": return u*u*u*u*0.25
		"out": return u-(1.0-pow(1.0-u,4.0))*0.25
		_: return pow(u,4.0) if u<=0.5 else u-0.5+pow(1.0-u,4.0)

static func span_area(event: Dictionary,elapsed: float) -> float:
	if event.dur<=0.0: return elapsed*float(event.speed)
	var ramp:=minf(maxf(0.0,elapsed),float(event.dur))
	return float(event.from)*ramp+(float(event.speed)-float(event.from))*float(event.dur)*ease_area(event.ease,ramp/float(event.dur))+maxf(0.0,elapsed-float(event.dur))*float(event.speed)

static func event_speed(event: Dictionary,t: float) -> float:
	if event.dur<=0.0: return float(event.speed)
	return lerpf(float(event.from),float(event.speed),SU.ease_by(event.ease,(t-float(event.t))/float(event.dur)))

## Stable source order breaks same-time ties: the last authored event wins.
## A later event truncates an earlier ramp at its actual instantaneous speed.
static func compile(events: Array) -> Dictionary:
	var ordered:=[]; var index:=0
	for event in events:
		var item: Dictionary=event.duplicate(); item["_i"]=index; index+=1; ordered.append(item)
	ordered.sort_custom(func(a,b): return a.t<b.t if a.t!=b.t else a._i<b._i)
	var unique:=[]
	for event in ordered:
		if not unique.is_empty() and event.t==unique[-1].t: unique[-1]=event
		else: unique.append(event)
	var out:=[]; var neutral:=true
	for event in unique:
		var item: Dictionary=event.duplicate(); item.erase("_i")
		item["from"]=1.0 if out.is_empty() else event_speed(out[-1],float(event.t))
		item["area"]=float(event.t) if out.is_empty() else float(out[-1].area)+span_area(out[-1],float(event.t)-float(out[-1].t))
		if float(item.speed)!=1.0: neutral=false
		out.append(item)
	return {"events":out,"neutral":neutral}

static func at(profile: Dictionary,t: float) -> int:
	var events: Array=profile.events; var lo:=0; var hi:=events.size()
	while lo<hi:
		var mid: int=(lo+hi)/2
		if float(events[mid].t)<=t: lo=mid+1
		else: hi=mid
	return lo-1

static func integral(profile: Dictionary,t: float) -> float:
	if profile.neutral: return t
	var i:=at(profile,t)
	if i<0: return t
	var event: Dictionary=profile.events[i]
	return float(event.area)+span_area(event,t-float(event.t))

static func speed(profile: Dictionary,t: float) -> float:
	var i:=at(profile,t)
	return 1.0 if i<0 else event_speed(profile.events[i],t)

static func time_at(profile: Dictionary,area: float) -> float:
	if profile.neutral: return area
	var events: Array=profile.events
	if events.is_empty() or area<float(events[0].area): return area
	var lo:=0; var hi:=events.size()
	while lo<hi:
		var mid: int=(lo+hi)/2
		if float(events[mid].area)<=area: lo=mid+1
		else: hi=mid
	var event: Dictionary=events[lo-1]
	var target:=area-float(event.area)
	var ramp_area:=span_area(event,float(event.dur))
	if event.dur<=0.0 or target>=ramp_area:
		return float(event.t)+float(event.dur)+(target-ramp_area)/float(event.speed)
	var a:=0.0; var b:=float(event.dur)
	for i in 56:
		var mid:=(a+b)*0.5
		if span_area(event,mid)<target: a=mid
		else: b=mid
	return float(event.t)+(a+b)*0.5
