extends RefCounted
## Data-only osu reader and deterministic draft importer. No runtime Python or ZIP extraction.
const Store = preload("res://attachments.gd")
const Document = preload("res://document.gd")
const SHIFT = 2.0
var api

func parse_text(text: String) -> Dictionary:
	text = text.trim_prefix("\ufeff").replace("\r", "")
	if not text.begins_with("osu file format v"): return {"error":"not an osu beatmap"}
	var sections = {}; var section = ""; var kv = {}; var timing = []; var notes = []; var background = ""
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.is_empty() or line.begins_with("//"): continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length()-2); sections[section] = true; continue
		if section in ["General", "Metadata", "Difficulty"] and ":" in line:
			kv[section + "." + line.get_slice(":", 0).strip_edges()] = line.substr(line.find(":")+1).strip_edges()
		elif section == "Events":
			var p = line.split(",")
			if p.size() >= 3 and p[0] in ["0", "Background"] and background.is_empty(): background = p[2].strip_edges().trim_prefix('"').trim_suffix('"')
		elif section == "TimingPoints":
			var p = line.split(",")
			if p.size() < 2 or not p[0].is_valid_float() or not p[1].is_valid_float(): return {"error":"invalid timing point"}
			var t = float(p[0]); var beat = float(p[1]); var uninherited = p.size() < 7 or p[6] == "1"
			if not is_finite(t) or not is_finite(beat) or beat == 0 or (uninherited and beat < 0): return {"error":"invalid beat length"}
			var point = {"t_ms":t, "uninherited":uninherited, "meter":maxi(1,int(p[2])) if p.size()>2 else 4}
			if uninherited: point["bpm"] = 60000.0/beat; point["beat_ms"] = beat
			else: point["sv"] = clampf(-100.0/beat, 0.1, 10.0)
			timing.append(point)
		elif section == "HitObjects":
			var p = line.split(",")
			if p.size() < 5 or not p[0].is_valid_float() or not p[2].is_valid_float() or not p[3].is_valid_int(): return {"error":"invalid hit object"}
			var t = float(p[2]); var x = float(p[0]); var type = int(p[3])
			if not is_finite(t) or t < 0 or not is_finite(x): return {"error":"invalid hit object position/time"}
			var n = {"t_ms":t,"x":x}
			if type & 128:
				if p.size() < 6 or not p[5].get_slice(":",0).is_valid_float(): return {"error":"invalid hold end"}
				n["end_ms"] = float(p[5].get_slice(":",0))
				if not is_finite(n.end_ms) or n.end_ms < t: return {"error":"hold ends before start"}
			notes.append(n)
			if notes.size() > 100000: return {"error":"beatmap exceeds 100000 notes"}
	var mode = int(kv.get("General.Mode","0")); var keys = int(float(kv.get("Difficulty.CircleSize","0")))
	var metadata = {}
	for key in ["Title","TitleUnicode","Artist","ArtistUnicode","Creator","Version","Source","Tags"]: metadata[key.to_snake_case()] = kv.get("Metadata."+key, "")
	var out = {"mode":mode,"key_count":keys,"metadata":metadata,"audio_filename":kv.get("General.AudioFilename",""),"background":background,"preview_time_ms":int(kv.get("General.PreviewTime","-1")),"timing_points":timing}
	if mode != 3: out["error"] = "unsupported mode: only osu!mania (mode 3) can be converted"; return out
	if keys < 1 or keys > 18: return {"error":"invalid mania key count"}
	timing.sort_custom(func(a,b): return a.t_ms < b.t_ms)
	if not timing.any(func(p): return p.uninherited): return {"error":"missing uninherited timing point"}
	notes.sort_custom(func(a,b): return a.t_ms < b.t_ms or (a.t_ms == b.t_ms and a.x < b.x))
	var chords = {}; var seconds = {}; var bars = {}; var holds = 0; var end = 0.0; var max_chord = 0; var seen = {}; var duplicate_count = 0; var clean = []
	var red = timing.filter(func(p): return p.uninherited); var seg = 0; var bar_start = 0.0
	for n in notes:
		n["column"] = clampi(floori(n.x * keys / 512.0),0,keys-1); n.erase("x")
		var identity = str(n.column)+":"+str(n.t_ms)
		if seen.has(identity): duplicate_count += 1; continue
		seen[identity] = true; clean.append(n)
		while seg+1 < red.size() and red[seg+1].t_ms <= n.t_ms:
			bar_start += (red[seg+1].t_ms-red[seg].t_ms)/red[seg].beat_ms/red[seg].meter; seg += 1
		var bar = floori(bar_start+(n.t_ms-red[seg].t_ms)/red[seg].beat_ms/red[seg].meter)
		bars[str(bar)] = bars.get(str(bar),0)+1
		chords[n.t_ms] = chords.get(n.t_ms,0)+1; max_chord = maxi(max_chord,chords[n.t_ms])
		var second = floori(n.t_ms/1000.0); seconds[str(second)] = seconds.get(str(second),0)+1
		if n.has("end_ms"): holds += 1
		end = maxf(end,n.get("end_ms",n.t_ms))
	out["notes"] = clean
	out["summary"] = {"notes":clean.size(),"holds":holds,"length_ms":end,"max_chord":max_chord,"density_per_bar":bars,"nps":seconds,"duplicates_removed":duplicate_count}
	return out

func parse(a: Dictionary) -> Dictionary:
	var id = str(a.get("id","")); var entry = str(a.get("entry",a.get("osu_entry",""))); var row = api.attachments.find(id)
	if row.is_empty(): return {"error":"unknown attachment"}
	if row.kind in ["osz","zip"] and entry.is_empty():
		var listing = api.attachments.entries(id)
		if listing.has("error"): return listing
		var difficulties = []
		for e in listing.entries:
			if e.entry.get_extension().to_lower() != "osu": continue
			if difficulties.size() >= 128: return {"error":"too many difficulties (128 maximum)"}
			var parsed = parse({"id":id,"entry":e.entry,"limit":1})
			for k in ["notes","next_offset","offset","done"]: parsed.erase(k)
			# The listing stays compact; full bar/NPS arrays are available when selecting an entry.
			if parsed.has("summary"): parsed.summary.erase("density_per_bar"); parsed.summary.erase("nps")
			difficulties.append(parsed)
		return {"difficulties":difficulties,"untrusted":true}
	var bytes = api.attachments.data(id,entry,8*1024*1024)
	if bytes.has("error"): return bytes
	var text: String = bytes.data.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes.data: return {"error":"beatmap must be UTF-8"}
	var out = parse_text(text); out["entry"] = entry; out["untrusted"] = true
	if out.has("notes"):
		var offset = maxi(0,int(a.get("offset",0))); var limit = clampi(int(a.get("limit",256)),1,1000); var count: int = out.notes.size()
		out.notes = out.notes.slice(offset,offset+limit); out["offset"] = offset; out["next_offset"] = mini(count,offset+limit); out["done"] = offset+limit >= count
	return out

func full_map(a: Dictionary) -> Dictionary:
	var id = str(a.get("id",a.get("from_attachment",""))); var entry = str(a.get("osu_entry",a.get("entry","")))
	var data = api.attachments.data(id,entry,8*1024*1024)
	if data.has("error"): return data
	var text: String = data.data.get_string_from_utf8()
	if text.to_utf8_buffer() != data.data: return {"error":"beatmap must be UTF-8"}
	return parse_text(text)

func create(a: Dictionary) -> Dictionary:
	var id = str(a.get("from_attachment","")); var row = api.attachments.find(id); var entry = str(a.get("osu_entry",""))
	if row.is_empty(): return {"error":"unknown attachment"}
	var map = full_map(a)
	if map.has("error"): return map
	var audio_name: String = map.audio_filename
	var source_entry = entry.get_base_dir().path_join(audio_name) if not entry.get_base_dir().is_empty() else audio_name
	if not Store.safe_entry(source_entry): return {"error":"unsafe audio filename"}
	var audio = {}
	if row.kind in ["zip","osz"]: audio = api.attachments.data(id,source_entry)
	else:
		# A loose .osu cannot authorize reading neighbouring files. Attach the audio separately.
		for other in api.attachments.items:
			if other.name == audio_name: audio = api.attachments.data(other.id); break
	if audio.is_empty() or audio.has("error"): return {"error":"audio missing; for loose .osu attach its audio file too","audio_filename":audio_name}
	var ext = audio_name.get_extension().to_lower()
	if ext not in ["mp3","ogg","wav"]: return {"error":"unsupported audio format"}
	var name = str(a.get("dir","osu_"+str(map.metadata.title).validate_filename())).strip_edges()
	if not valid_dir(name): return {"error":"dir must be a single safe folder name"}
	var root: String = api.songs_root; var dir = name; var n = 2; var reserved = false
	if not DirAccess.dir_exists_absolute(root) and DirAccess.make_dir_recursive_absolute(root) != OK: return {"error":"cannot open songs library"}
	# Directory creation is the reservation. Concurrent MCP clients cannot both own one song.
	for attempt in 1000:
		var candidate = root.path_join(dir)
		if not DirAccess.dir_exists_absolute(candidate) and not FileAccess.file_exists(candidate):
			if DirAccess.make_dir_absolute(candidate) == OK: reserved = true; break
			if not DirAccess.dir_exists_absolute(candidate) and not FileAccess.file_exists(candidate): return {"error":"cannot create song folder"}
		dir = name+"_"+str(n); n += 1
	if not reserved: return {"error":"song folder name has too many collisions"}
	var destination = root.path_join(dir)
	var timing = []
	for p in map.timing_points:
		if p.uninherited: timing.append({"t":p.t_ms/1000.0+SHIFT,"beat":p.beat_ms/1000.0,"meter":p.meter})
	var meta = {"title":a.get("title",map.metadata.title),"artist":a.get("artist",map.metadata.artist),"difficulty":a.get("version",map.metadata.version),"level":a.get("level",0),"source":"osu!mania: "+map.metadata.creator+" / "+map.metadata.version,"osu_sha256":row.sha256,"osu_entry":entry}
	var chart = {"title":meta.title,"meta":meta,"offset":SHIFT,"bpm":60000.0/(timing[0].beat*1000.0),"timing":timing,"lights":[{"t":0,"id":0,"type":"on","x":0.5,"w":1.0,"auto":true}],"notes":[],"fx":[]}
	var f = FileAccess.open(destination.path_join("audio."+ext),FileAccess.WRITE)
	if not f: return {"error":"cannot write audio","dir":dir}
	f.store_buffer(audio.data); f.close()
	var bg: String = map.background
	if not bg.is_empty():
		var bg_entry = entry.get_base_dir().path_join(bg) if not entry.get_base_dir().is_empty() else bg
		var bg_args = {"id":id,"entry":bg_entry}
		if row.kind not in ["zip","osz"]:
			bg_args = {}
			for other in api.attachments.items:
				if other.name == bg: bg_args = {"id":other.id}; break
		if not bg_args.is_empty():
			var cover = api.attachments.image_content(bg_args)
			if not cover.has("error"):
				f = FileAccess.open(destination.path_join("cover.png"),FileAccess.WRITE)
				if f: f.store_buffer(Marshalls.base64_to_raw(cover._mcp_content[0].data)); f.close()
	f = FileAccess.open(destination.path_join("chart.json"),FileAccess.WRITE)
	if not f: return {"error":"cannot write chart","dir":dir}
	f.store_string(Document.canonical(chart)); f.close()
	var document = Document.new(); document.raw = chart
	return {"dir":dir,"revision":document.revision(),"game_index_changed":false,"draft":true}

static func valid_dir(dir: String) -> bool:
	if dir.get_slice(".",0).to_upper() in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]: return false
	return not dir.is_empty() and dir.length() <= 120 and Store.safe_entry(dir) and not "/" in dir and dir == dir.validate_filename() and not dir.ends_with(".") and not dir.ends_with(" ")

func convert(a: Dictionary) -> Dictionary:
	var map = full_map(a)
	if map.has("error"): return map
	var count: int = map.key_count
	if count < 4 or count > 10: return {"error":"draft conversion supports 4K through 10K; parser supports all mania key counts"}
	var doc = api.doc; var row = api.attachments.find(str(a.get("id","")))
	if doc.raw.get("meta",{}).get("osu_sha256","") != row.get("sha256","missing") or doc.raw.meta.get("osu_entry","") != str(a.get("osu_entry","")) or not doc.raw.notes.is_empty() or not doc.raw.get("fx",[]).is_empty(): return {"error":"open the new empty song created from this attachment/difficulty first"}
	var left = count/2; var right = count-left; var keys = []; var right_start = 6 if right <= 5 else 5
	for i in left: keys.append(4-left+i)
	for i in right: keys.append(right_start+i)
	# Default 4K = D F | J K. 9/10K extend the left hand to G, keeping unique home keys.
	if left == 5:
		for i in left: keys[i] = i
	var mapping = a.get("mapping",[])
	if not mapping is Array or (not mapping.is_empty() and mapping.size() != count): return {"error":"mapping must contain one key name or {key,track} per column"}
	var groups = {}; var columns = []
	for i in count:
		var m = mapping[i] if not mapping.is_empty() else str(Document.KEYS[keys[i]])
		var key = str(m.get("key","")) if m is Dictionary else str(m)
		var k = Document.KEYS.find(key.to_upper())
		if k < 0 or key.length() != 1: return {"error":"mapping key must be a home-row key","column":i}
		if columns.any(func(c): return c.k == k): return {"error":"mapping keys must be unique"}
		var track = int(m.get("track",0 if i<left else 1)) if m is Dictionary else (0 if i<left else 1)
		if track < 0 or track > 100000: return {"error":"mapping track out of range"}
		if not groups.has(track): groups[track] = {"lo":k,"hi":k}
		groups[track].lo = mini(groups[track].lo,k); groups[track].hi = maxi(groups[track].hi,k); columns.append({"k":k,"track":track})
	var ops = []
	for i in range(doc.raw.lights.size()-1,-1,-1): ops.append({"target":"lights","op":"delete","index":i})
	for track in groups:
		var g = groups[track]; var x = (2.25+(g.lo+g.hi)/2.0)/15.0; var w = (g.hi-g.lo+1.0)/15.0
		g["x"] = x; g["w"] = w
		ops.append({"target":"lights","op":"add","value":{"t":0,"id":track,"type":"on","x":x,"w":w,"auto":true}})
	for n in map.notes:
		var c = columns[n.column]; var g = groups[c.track]; var note = {"t":n.t_ms/1000.0+SHIFT,"light":c.track,"u":((2.25+c.k)/15.0-g.x)/g.w+0.5,"k":c.k,"kind":"tap"}
		if n.has("end_ms") and n.end_ms-n.t_ms >= 80: note.kind = "hold"; note["dur"] = (n.end_ms-n.t_ms)/1000.0
		ops.append({"target":"notes","op":"add","value":note})
	var result = doc.edit({"expected_revision":a.get("expected_revision",doc.revision()),"label":"osu!mania draft","ops":ops},api.author)
	result["mapping"] = columns; result["notes"] = map.notes.size(); result["warnings"] = doc.core.chart.warnings
	return result
