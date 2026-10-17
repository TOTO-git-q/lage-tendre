extends RefCounted
## Raw JSON is the persistence authority; validated GameCore data is a read model.
signal changed
const KEYS = "ASDFGHJKL;'"
var revision_cache=""
var timing_cache: Array=[]
var raw: Dictionary = {}:
	set(value):
		raw=value; revision_cache=""; timing_cache=[]
var path = ""
var original = ""
var saved_revision = ""
var selection: Dictionary = {"from": 0.0, "to": 0.0, "tracks": [], "notes": [], "fx": []}
var undo_stack: Array = []
var redo_stack: Array = []
var core = GameCore.new()
var music: Dictionary = {}
var song_meta: Dictionary={}
var allow_save = false
var busy=false
var versions
var group_before: Dictionary = {}
var locked_tracks: Dictionary={}
## Editor data the engine cannot read yet (general track shapes, note motions). Lives only in the
## sidecar chart.ext.json next to chart.json; never written into chart.json.
var ext: Dictionary = {"shapes": {}, "motions": {}}
var ext_saved := ""
var shape_memo: Dictionary = {}   # session only: edited track shapes by event signature (keeps user nodes)
var _check_rev := ""
var _check_warn: Array = []
var _check_cov: Array = []

func version_store():
	if versions==null:
		versions=preload("res://versions.gd").new(); versions.doc=self
	return versions

static func sorted_value(value):
	if value is float and is_finite(value) and absf(value)<9007199254740991.0 and value==floorf(value): return int(value)
	if value is Dictionary:
		var result={}; var keys=value.keys(); keys.sort()
		for key in keys: result[key]=sorted_value(value[key])
		return result
	if value is Array:
		var result=[]
		for item in value: result.append(sorted_value(item))
		return result
	return value

static func canonical(value: Dictionary) -> String:
	var lines=[]; var keys=value.keys(); keys.sort()
	for key in keys:
		var item=value[key]
		if key in ["notes","lights","fx"] and item is Array:
			var events=[]
			for event in item: events.append("    "+JSON.stringify(sorted_value(event)))
			lines.append("  "+JSON.stringify(key)+": [\n"+",\n".join(events)+"\n  ]")
		else: lines.append("  "+JSON.stringify(key)+": "+JSON.stringify(sorted_value(item)))
	return "{\n"+",\n".join(lines)+"\n}\n"

func refresh_core() -> void:
	core.load_chart(raw)
	decorate_notes()

func decorate_notes() -> void:
	var identities={}
	for i in raw.get("notes",[]).size():
		var n=raw.notes[i]
		var key=JSON.stringify([float(n.t),int(n.light),float(n.u),n.get("kind","tap"),float(n.get("dur",0)) if n.get("kind","")=="hold" else 0.0])
		if not identities.has(key): identities[key]=[]
		identities[key].append(i)
	for n in core.notes:
		var key=JSON.stringify([float(n.t),int(n.light),float(n.u),n.kind,float(n.dur)])
		n["raw_id"]=identities[key].pop_front() if identities.has(key) and not identities[key].is_empty() else -1

func revision() -> String:
	if revision_cache.is_empty():
		var text=JSON.stringify(raw)
		if not ext_empty(): text+=JSON.stringify(ext)
		revision_cache=text.sha256_text()
	return revision_cache

func ext_empty() -> bool:
	return ext.get("shapes",{}).is_empty() and ext.get("motions",{}).is_empty()

func ext_path() -> String:
	return path.get_base_dir().path_join("chart.ext.json") if not path.is_empty() else ""

func open(file: String) -> Dictionary:
	if busy: return {"error":"version operation in progress"}
	var text = FileAccess.get_file_as_string(file)
	var value = JSON.parse_string(text)
	if not value is Dictionary or not value.has("notes") or not value.has("lights"):
		return {"error": "Not a chart JSON object"}
	raw = value; path = file; original = text
	ext={"shapes":{},"motions":{}}
	if FileAccess.file_exists(ext_path()):
		var side=JSON.parse_string(FileAccess.get_file_as_string(ext_path()))
		if side is Dictionary: ext={"shapes":side.get("shapes",{}),"motions":side.get("motions",{})}
	ext_saved=JSON.stringify(ext)
	revision_cache=""; saved_revision = revision(); undo_stack.clear(); redo_stack.clear()
	locked_tracks.clear()
	KB.set_layout("ansi"); refresh_core()
	var m = JSON.parse_string(FileAccess.get_file_as_string(file.get_base_dir().path_join("analysis.json"))) if FileAccess.file_exists(file.get_base_dir().path_join("analysis.json")) else {}
	music = m if m is Dictionary else {}
	song_meta=music.get("song_info",{}).duplicate(true)
	var index_path=file.get_base_dir().get_base_dir().path_join("index.json")
	if FileAccess.file_exists(index_path):
		var entries=JSON.parse_string(FileAccess.get_file_as_string(index_path))
		if entries is Array:
			for entry in entries:
				if entry.get("dir","")==file.get_base_dir().get_file(): song_meta=entry.duplicate(true); break
	changed.emit()
	return {"revision": revision(), "warnings": core.chart.warnings}

func timing() -> Array:
	if not timing_cache.is_empty(): return timing_cache
	var out: Array = raw.get("timing", []).duplicate(true)
	if out.is_empty(): out = [{"t": raw.get("offset", 0.0), "beat": 60.0 / raw.get("bpm", 120.0), "meter": 4}]
	out.sort_custom(func(a,b): return a.t < b.t)
	var bar = 0.0
	for i in out.size():
		if i > 0: bar += (out[i].t-out[i-1].t)/out[i-1].beat/out[i-1].get("meter",4)
		out[i]["bar"] = bar
	timing_cache=out
	return timing_cache

func seconds(v) -> float:
	if v is float or v is int: return float(v)
	var parts = str(v).split("+")
	var bb = parts[0].split(".")
	if parts.size()>2 or bb.size() != 2 or not bb[0].is_valid_int() or not bb[1].is_valid_int() or int(bb[1])<1: return NAN
	var bar = float(bb[0]); var beat = float(bb[1])-1.0
	var segs = timing(); var s = segs[0]
	for x in segs:
		if x.bar <= bar: s = x
	if beat>=int(s.get("meter",4)): return NAN
	var extra = 0.0
	if parts.size() > 1:
		var f = parts[1].split("/")
		if f.size() != 2 or not f[0].is_valid_int() or not f[1].is_valid_int() or float(f[1]) <= 0: return NAN
		extra = float(f[0])/float(f[1])*4.0
	return s.t + ((bar-s.bar)*s.get("meter",4)+beat+extra)*s.beat

func position(t: float) -> Dictionary:
	var s = timing()[0]
	for x in timing():
		if x.t <= t: s = x
	var beats = (t-s.t)/s.beat
	if absf(beats-roundf(beats))<0.0000001: beats=roundf(beats)
	var b = s.bar + floor(beats/s.get("meter",4))
	var within = fposmod(beats,float(s.get("meter",4)))
	var word="%d.%d" % [b,floor(within)+1]
	var fraction=fposmod(within,1.0)
	if fraction>0.0000001:
		var numerator=roundi(fraction*48)
		var divisor=192
		if absf(fraction-numerator/48.0)>=0.00001: numerator=roundi(fraction*1000000); divisor=4000000
		var a=numerator; var z=divisor
		while z!=0:
			var rem=a%z; a=z; z=rem
		word+="+%d/%d" % [numerator/a,divisor/a]
	return {"seconds": t, "audio_seconds": t-raw.get("offset",0.0), "bar": b, "beat": within+1.0, "bar_beat": word, "beat_seconds": s.beat}

func grid(lo: float, hi: float, div: int) -> Array:
	var out=[]
	if div<=0: return out
	var segments=timing()
	for i in segments.size():
		var s=segments[i]; var begin=maxf(lo,s.t) if i>0 else lo
		var end=minf(hi,segments[i+1].t) if i+1<segments.size() else hi
		var step=s.beat*4.0/div
		var t=s.t+ceil((begin-s.t)/step-0.0000001)*step
		while t<end-0.0000001 and out.size()<8192:
			out.append(position(t)); t+=step
	return out

func coverage(candidate: Dictionary, validated: Dictionary={}) -> Array:
	var out: Array = []
	var c = ChartLib.validate(candidate) if validated.is_empty() else validated
	if c.is_empty(): return [{"reason":"invalid chart"}]
	var tl = ChartLib.build_timelines(c.lights)
	var lifetimes={}
	for id in tl:
		lifetimes[id]=[]
		for e in tl[id]:
			if e.type=="on": lifetimes[id].append([float(e.t),INF])
			elif e.type=="off" and not lifetimes[id].is_empty(): lifetimes[id][-1][1]=float(e.t)
	for i in candidate.get("notes",[]).size():
		var n = candidate.notes[i]; var t = float(n.get("t",0)); var end = t+float(n.get("dur",0))
		var segs = tl.get(int(n.get("light",-1)),[])
		var st = state_at(segs,t)
		var k = int(n.get("k",-1))
		if k<0 or k>10: k=clampi(roundi((st.x+(float(n.get("u",0.5))-0.5)*st.w)*15.0-2.25),0,10)
		var reason = ""
		var x = (2.25+k)/15.0
		if not st.alive or x < st.x-st.w/2.0-SU.KEY_PAD or x > st.x+st.w/2.0+SU.KEY_PAD:
			reason = "landing key is outside live track (KEY_PAD included)"
		var start = t-1.3
		var continuous=false
		for interval in lifetimes.get(int(n.get("light",-1)),[]):
			if start>=interval[0]-SU.EPS and end<=interval[1]+SU.EPS: continuous=true
		if not continuous: reason="track must be continuously alive from t-1.3 s through hold end"
		if not reason.is_empty(): out.append({"note":i,"t":t,"reason":reason})
	return out

static func state_at(segs: Array, t: float) -> Dictionary:
	var lo=0; var hi=segs.size()-1; var found=-1
	while lo<=hi:
		var mid=(lo+hi)/2
		if segs[mid].t<=t+1e-9: found=mid; lo=mid+1
		else: hi=mid-1
	return ChartLib.light_at([segs[found]],t) if found>=0 else ChartLib.DEAD

func edit(args: Dictionary, author = "user") -> Dictionary:
	if busy: return {"error":"version operation in progress"}
	if author=="user" and not group_before.is_empty(): return {"error":"stop or finish the Claude turn before manual edits"}
	if args.get("expected_revision","") != revision(): return {"error":"stale revision", "revision":revision()}
	var next = raw.duplicate(true)
	var ops = args.get("ops",[])
	var whole_chart := false   # a song-level transform (re-time / shift) that rewrites every event
	if not ops is Array or ops.size() > 10000: return {"error":"ops must be an array of at most 10000 operations"}
	for i in ops.size():
		var op = ops[i]
		var target = str(op.get("target","notes"))
		if target == "meta":
			if not op.get("value") is Dictionary: return {"error":"meta must be an object","operation":i}
			next.meta = op.value.duplicate(true); continue
		if target == "plugins":
			if not op.get("value") is Array or op.value.size()>64: return {"error":"invalid plugin bindings"}
			var session=SongPluginSession.new()
			var candidate=next.duplicate(true); candidate.plugins=op.value.duplicate(true)
			var report=session.prepare(path.get_base_dir(),candidate,path.get_base_dir().get_file())
			var errors=report.errors.duplicate(); session.close()
			if not errors.is_empty(): return {"error":"plugin binding refused","diagnostics":errors}
			if op.value.is_empty(): next.erase("plugins")
			else: next.plugins=op.value.duplicate(true)
			continue
		if target == "song":
			# song timing and whole-chart re-timing: only from the editor's 歌曲设置 page, not over MCP
			if author != "user": return {"error":"song timing is edited in the editor (歌曲设置)","operation":i}
			var song_error = _apply_song(next, op.get("value"))
			if not song_error.is_empty(): return {"error":song_error,"operation":i}
			if op.get("value") is Dictionary and op.value.has("notes"): whole_chart = true
			continue
		if not target in ["notes","lights","fx"]: return {"error":"unknown target", "operation":i}
		if not next.has(target): next[target] = []
		var list = next[target]; var action = op.get("op","")
		var index = int(op.get("index",-1))
		if target in ["notes","lights"]:
			var field="light" if target=="notes" else "id"
			var previous_id=int(list[index].get(field,-1)) if index>=0 and index<list.size() else -1
			if op.get("value",{}) is Dictionary and op.get("value",{}).has(field) and not (op.value[field] is float or op.value[field] is int): return {"error":"track identity must be numeric","operation":i}
			var new_id=int(op.get("value",{}).get(field,previous_id)) if op.get("value",{}) is Dictionary else previous_id
			if locked_tracks.get(previous_id,false) or locked_tracks.get(new_id,false): return {"error":"track is locked","operation":i,"track":previous_id}
		if action == "add":
			if not op.get("value") is Dictionary: return {"error":"value must be object", "operation":i}
			list.append(op.value.duplicate(true))
		elif index < 0 or index >= list.size(): return {"error":"index out of bounds", "operation":i}
		elif action == "delete": list.remove_at(index)
		elif action == "update":
			if not op.get("value") is Dictionary: return {"error":"value must be object", "operation":i}
			list[index].merge(op.value,true)
		else: return {"error":"unknown operation", "operation":i}
	# Validate structure before handing malformed objects to the game validator.
	for target in ["notes","lights","fx"]:
		for item in next.get(target,[]):
			if not item is Dictionary or not item.has("t") or not (item.t is float or item.t is int) or not is_finite(float(item.t)) or float(item.t)<0:
				return {"error":"invalid finite nonnegative t", "target":target}
			for field in ["x","w","u","dur","a","k","id","light","nw","tint","to","amp","attack","decay"]:
				if item.has(field) and (not (item[field] is int or item[field] is float) or not is_finite(float(item[field]))): return {"error":"field must be a finite number","field":field,"target":target}
			if target == "notes" and (not item.has("light") or not item.has("u") or float(item.u)<0 or float(item.u)>1): return {"error":"note requires light and u in 0..1"}
			if target == "lights" and (not item.has("id") or not item.get("type","") in ChartLib.TYPES): return {"error":"invalid track event"}
			if target == "fx" and (not item.get("type","") in ["tween","impulse","ring"] or (item.type != "ring" and not StageFx.CH.has(item.get("ch","")))): return {"error":"invalid fx"}
	var validated = ChartLib.validate(next)
	if _check_rev != revision():
		var current=ChartLib.validate(raw)
		_check_warn=current.warnings; _check_cov=coverage(raw,current); _check_rev=revision()
	var before_warn = _check_warn
	for w in validated.warnings:
		if not w in before_warn: return {"error":"game validator refused", "reason":w}
	var failures = coverage(next,validated)
	# Existing legacy violations are visible in analysis; do not make unrelated legacy charts uneditable.
	var old_failures = _check_cov
	for f in failures:
		# a legacy violation stays tolerated while neither the note nor its own track's geometry changes
		var unchanged = f.note < raw.notes.size() and f.note < next.notes.size() and raw.notes[f.note] == next.notes[f.note] and track_geometry(raw,int(next.notes[f.note].get("light",-1)))==track_geometry(next,int(next.notes[f.note].get("light",-1)))
		# a whole-chart transform moves every note; a note that already broke the same rule stays tolerated
		if whole_chart and old_failures.any(func(o): return o.note == f.note and o.reason == f.reason): continue
		if not unchanged or not f in old_failures: return {"error":"track rule refused", "detail":f}
	var next_ext=args.get("ext",null)
	if not next_ext is Dictionary: next_ext=prune_ext(next)
	if next == raw and next_ext == ext: return {"revision":revision(),"diff":"no change"}
	var entry={"before":raw.duplicate(true),"after":next.duplicate(true),"ext_before":ext.duplicate(true),"ext_after":next_ext.duplicate(true),"label":args.get("label","Edit"),"author":author,"coalesce":str(args.get("coalesce",""))}
	# A continuous gesture (scrub, wheel, drag) is one undo step: merge into the previous entry.
	if not entry.coalesce.is_empty() and not undo_stack.is_empty() and undo_stack[-1].get("coalesce","")==entry.coalesce and undo_stack[-1].author==author and redo_stack.is_empty():
		var previous=undo_stack.pop_back(); entry.before=previous.before; entry.ext_before=previous.get("ext_before",entry.ext_before)
	undo_stack.append(entry)
	redo_stack.clear(); raw = next; ext = next_ext; revision_cache=""; refresh_core()
	_check_rev=revision(); _check_warn=validated.warnings; _check_cov=failures
	changed.emit()
	return {"revision":revision(),"diff":{"operations":ops.size(),"label":args.get("label","Edit"),"author":author}}

## Song-level fields from the 歌曲设置 page: timing (tempo map), offset (where audio second 0 sits
## on the chart clock) and, for the explicit re-time / shift actions, whole notes / lights / fx
## lists. chart.bpm always follows timing[0] (the game reads both).
func _apply_song(next: Dictionary, value) -> String:
	if not value is Dictionary: return "song value must be an object"
	if value.has("timing"):
		var list = value.timing
		if not list is Array or list.is_empty() or list.size() > 512: return "timing must be a non-empty list"
		var clean=[]
		for s in list:
			if not s is Dictionary or not (s.get("t") is float or s.get("t") is int) or not (s.get("beat") is float or s.get("beat") is int): return "timing segment needs t and beat"
			var beat=float(s.beat); var meter=int(s.get("meter",4))
			if not is_finite(float(s.t)) or not is_finite(beat) or beat < 60.0/600.0 or beat > 60.0/20.0: return "BPM must be between 20 and 600"
			if meter < 1 or meter > 16: return "meter must be 1..16"
			clean.append({"t":float(s.t),"beat":beat,"meter":meter})
		clean.sort_custom(func(a,b): return a.t < b.t)
		for k in range(1, clean.size()):
			if clean[k].t - clean[k-1].t < 0.01: return "two tempo segments start at the same time"
		next.timing = clean
		next.bpm = snappedf(60.0/clean[0].beat, 0.0001)
	if value.has("offset"):
		if not (value.offset is float or value.offset is int) or not is_finite(float(value.offset)): return "offset must be a finite number"
		next.offset = float(value.offset)
	for target in ["notes","lights","fx"]:
		if value.has(target):
			if not value[target] is Array: return target+" must be a list"
			next[target] = value[target].duplicate(true)
	if value.has("meta"):
		if not value.meta is Dictionary: return "meta must be an object"
		next.meta = value.meta.duplicate(true)
	return ""

## Sidecar shapes whose track events were changed by something other than the shape editor
## (MCP, a plain event edit) are dropped: chart.json is then the authority again.
func prune_ext(next: Dictionary) -> Dictionary:
	var out=ext.duplicate(true)
	if out.get("shapes",{}).is_empty(): return out
	var by_id={}
	for e in next.get("lights",[]):
		var id=str(int(e.get("id",-1)))
		if not by_id.has(id): by_id[id]=[]
		by_id[id].append(e)
	for id in out.shapes.keys():
		if preload("res://track_adapter.gd").signature(by_id.get(id,[]))!=out.shapes[id].get("signature",""): out.shapes.erase(id)
	return out

static func track_geometry(chart: Dictionary, id: int) -> Array:
	var out=[]
	for e in chart.get("lights",[]):
		if int(e.get("id",-1))==id:
			var g=e.duplicate(); g.erase("a"); g.erase("tint"); out.append(g)
	return out

func undo() -> Dictionary:
	if busy: return {"error":"version operation in progress"}
	if not group_before.is_empty(): return {"error":"finish or stop the Claude turn before undo"}
	if undo_stack.is_empty(): return {"error":"nothing to undo"}
	var e = undo_stack.pop_back(); redo_stack.append(e); raw = e.before.duplicate(true); ext = e.get("ext_before",ext).duplicate(true); revision_cache=""; refresh_core(); changed.emit()
	return {"revision":revision(),"label":e.label}

func redo() -> Dictionary:
	if busy: return {"error":"version operation in progress"}
	if not group_before.is_empty(): return {"error":"finish or stop the Claude turn before redo"}
	if redo_stack.is_empty(): return {"error":"nothing to redo"}
	var e = redo_stack.pop_back(); undo_stack.append(e); raw = e.after.duplicate(true); ext = e.get("ext_after",ext).duplicate(true); revision_cache=""; refresh_core(); changed.emit()
	return {"revision":revision(),"label":e.label}

func begin_group(label: String = "Claude turn", author: String = "Claude") -> void:
	group_before = {"raw":raw.duplicate(true),"ext":ext.duplicate(true),"size":undo_stack.size(),"label":label,"author":author}

func end_group() -> Dictionary:
	if group_before.is_empty(): return {}
	var before = group_before.raw
	undo_stack.resize(group_before.size)
	if before != raw: undo_stack.append({"before":before,"after":raw.duplicate(true),"ext_before":group_before.get("ext",ext),"ext_after":ext.duplicate(true),"label":group_before.get("label","Agent turn"),"author":group_before.get("author","Agent")})
	group_before = {}
	var diff={}
	for target in ["notes","lights","fx"]:
		var ids=[]; var old=before.get(target,[]); var next=raw.get(target,[])
		for i in maxi(old.size(),next.size()):
			if i>=old.size() or i>=next.size() or old[i]!=next[i]: ids.append(i)
		diff[target]=ids
	return {"changed": before != raw,"revision":revision(),"diff":diff}

func save(from_mcp = false) -> Dictionary:
	if busy: return {"error":"version operation in progress"}
	if from_mcp and not allow_save: return {"error":"user has not enabled allow Claude to save"}
	if FileAccess.file_exists(path.get_base_dir().path_join(".read-only")): return {"error":"protected source song; open a working copy"}
	if FileAccess.get_file_as_string(path) != original: return {"error":"chart changed externally; reopen before save"}
	if revision() == saved_revision: return {"revision":revision(),"unchanged":true}
	var backup = path+".bak-"+str(Time.get_unix_time_from_system()).replace(".","-")
	if DirAccess.copy_absolute(path,backup) != OK: return {"error":"backup failed"}
	var side=save_ext()
	if side.has("error"): return side
	# The game reads the lean chart identically (lean() verifies), so the working model adopts it too.
	var compact=lean(raw)
	if compact!=raw:
		raw=compact; refresh_core()
		# an open assistant turn compares against its start; lean that too (same chart for the game)
		if not group_before.is_empty(): group_before.raw=lean(group_before.raw)
	var text = canonical(raw)
	var temp = path+".charter-tmp"
	var f = FileAccess.open(temp,FileAccess.WRITE)
	if not f: return {"error":"cannot write temp chart"}
	f.store_string(text); f.close()
	if DirAccess.rename_absolute(temp,path) != OK: return {"error":"atomic replacement failed", "backup":backup}
	original = text; saved_revision = revision()
	return {"revision":revision(),"backup":backup,"path":path,"sidecar":side.get("path","")}

func save_ext() -> Dictionary:
	var file=ext_path(); var text=JSON.stringify(ext)
	if text==ext_saved and (FileAccess.file_exists(file) or ext_empty()): return {}
	if ext_empty():
		if FileAccess.file_exists(file):
			DirAccess.copy_absolute(file,file+".bak-"+str(Time.get_unix_time_from_system()).replace(".","-"))
			DirAccess.remove_absolute(file)
		ext_saved=text; return {}
	var f=FileAccess.open(file,FileAccess.WRITE)
	if not f: return {"error":"cannot write chart.ext.json"}
	f.store_string(JSON.stringify({"about":"L'age tendre Charter: track shapes and note motions the game engine cannot read yet. chart.json stays playable without this file.","shapes":ext.get("shapes",{}),"motions":ext.get("motions",{})},"  ",true)); f.close()
	ext_saved=text
	return {"path":file}

## The chart without fields equal to what the game assumes anyway. Only used when the game's
## validator reads the lean chart identically; otherwise the chart is written unchanged.
static func lean(value: Dictionary) -> Dictionary:
	# Plugin fields and codec metadata must round-trip without legacy minimization.
	if value.has("plugins") or value.has("tracks") or value.has("sv"): return value.duplicate(true)
	var out=value.duplicate(true)
	for key in out.keys():
		if key in ["notes","lights"]: continue
		if key in ["fx","meta","timing"] and (out[key] is Array or out[key] is Dictionary) and out[key].is_empty(): out.erase(key)
	for e in out.get("lights",[]):
		if not e is Dictionary: continue
		var type=str(e.get("type",""))
		if e.get("from","LR")=="LR": e.erase("from")
		if e.get("auto",null)==false: e.erase("auto")
		if type=="off":
			for k in ["x","w","a","tint","dur","ease","from"]: e.erase(k)
		elif type=="pulse":
			for k in ["x","w","a","tint","dur","ease"]: e.erase(k)
		elif type=="on": e.erase("dur"); e.erase("ease")
		elif str(e.get("ease",""))=="inout": e.erase("ease")
	for n in out.get("notes",[]):
		if not n is Dictionary: continue
		if str(n.get("kind",""))=="tap": n.erase("dur"); n.erase("path")
		for k in ["big","ex"]:
			if n.get(k,null)==false: n.erase(k)
		if n.has("nw") and (n.nw is float or n.nw is int) and float(n.nw)==1.0: n.erase("nw")
		if n.has("k") and (n.k is float or n.k is int) and int(n.k)<0: n.erase("k")
		if n.get("path",null) is Array and n.path.is_empty(): n.erase("path")
		if n.get("grow",null) is Array and n.grow.is_empty(): n.erase("grow")
	var a=ChartLib.validate(value); var b=ChartLib.validate(out)
	return out if JSON.stringify(sorted_value(a))==JSON.stringify(sorted_value(b)) else value
