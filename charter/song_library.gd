extends RefCounted
## Song files, like a conversation list: scan a songs root into songs (grouped by song set, their
## game difficulties and editor working copies), create a new song, import charts / folders /
## song packages, export a song package or a lean chart, and add a difficulty to the game's song
## list (songs/index.json). Pure file logic with no UI, so it can be tested on a temporary root.
##
## Nothing here overwrites a file unless the caller passes overwrite = true; index.json is always
## backed up before it is rewritten.

const Document = preload("res://document.gd")
const AUDIO_EXT := ["mp3", "ogg", "wav"]
const COVER_NAMES := ["cover.jpg", "cover.png", "cover.jpeg", "cover.webp"]
const DIFFICULTIES := ["EX", "HARD", "NORMAL", "EASY"]
const PACKAGE_FORMAT := "lage-tendre-song"

static var _hash_cache: Dictionary = {}    # path -> [modified_time, sha256]

## ------------------------------------------------------------------ reading
static func read_index(root: String) -> Array:
	var p := root.path_join("index.json")
	if not FileAccess.file_exists(p): return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Array else []

static func audio_of(dir_path: String) -> String:
	for ext in AUDIO_EXT:
		var p := dir_path.path_join("audio." + ext)
		if FileAccess.file_exists(p): return p
	return ""

static func _audio_hash(path: String) -> String:
	if path.is_empty(): return ""
	var mt := FileAccess.get_modified_time(path)
	if _hash_cache.has(path) and _hash_cache[path][0] == mt: return _hash_cache[path][1]
	var h := FileAccess.get_sha256(path)
	_hash_cache[path] = [mt, h]
	return h

static func cover_of(root: String, dir: String, entry: Dictionary = {}) -> String:
	if not str(entry.get("cover", "")).is_empty() and FileAccess.file_exists(root.path_join(str(entry.cover))): return root.path_join(str(entry.cover))
	for name in COVER_NAMES:
		if FileAccess.file_exists(root.path_join(dir).path_join(name)): return root.path_join(dir).path_join(name)
	if entry.has("set"):
		for ext in ["jpg", "png"]:
			var p := root.path_join("_covers").path_join("%s.%s" % [entry.set, ext])
			if FileAccess.file_exists(p): return p
	return ""

static func chart_meta(dir_path: String) -> Dictionary:
	var p := dir_path.path_join("chart.json")
	if not FileAccess.file_exists(p): return {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not raw is Dictionary: return {}
	var meta: Dictionary = raw.get("meta", {}) if raw.get("meta", {}) is Dictionary else {}
	return {"title": str(meta.get("title", raw.get("title", ""))), "artist": str(meta.get("artist", "")), "difficulty": str(meta.get("difficulty", "")),
		"bpm": float(raw.get("bpm", 120.0)), "notes": (raw.get("notes", []) as Array).size() if raw.get("notes", []) is Array else 0}

## Songs grouped like the game's song select: one row per song set, with its indexed difficulties
## (chips) and the working copies (folders whose audio is byte-identical to an indexed difficulty).
## Folders starting with "_" are kept apart under a final "其他文件夹" group.
static func scan(root: String) -> Array:
	var index := read_index(root)
	var by_dir := {}
	for e in index:
		if e is Dictionary: by_dir[str(e.get("dir", ""))] = e
	var groups := {}       # key -> group
	var order := []
	var hash_to_key := {}
	var others := {"key": "_other", "title": "其他文件夹", "artist": "", "cover": "", "diffs": [], "copies": [], "other": true}
	var dirs: Array = Array(DirAccess.get_directories_at(root)) if DirAccess.dir_exists_absolute(root) else []
	if DirAccess.dir_exists_absolute(root.path_join("_plugin_demos")):
		for nested in DirAccess.get_directories_at(root.path_join("_plugin_demos")):
			dirs.append("_plugin_demos/" + nested)
	dirs.sort()
	# indexed difficulties first, so working copies can find their song by audio
	for dir in dirs:
		if not FileAccess.file_exists(root.path_join(dir).path_join("chart.json")) or not by_dir.has(dir): continue
		var e: Dictionary = by_dir[dir]
		var key := str(e.get("set", e.get("title", dir)))
		if not groups.has(key):
			groups[key] = {"key": key, "title": str(e.get("title", dir)), "artist": str(e.get("artist", "")), "cover": cover_of(root, dir, e), "diffs": [], "copies": []}
			order.append(key)
		groups[key].diffs.append({"dir": dir, "version": str(e.get("version", "")), "level": int(e.get("level", 0)), "notes": int(e.get("notes", 0)), "indexed": true})
		var h := _audio_hash(audio_of(root.path_join(dir)))
		if not h.is_empty() and not hash_to_key.has(h): hash_to_key[h] = key
	for dir in dirs:
		if not FileAccess.file_exists(root.path_join(dir).path_join("chart.json")) or by_dir.has(dir): continue
		var meta := chart_meta(root.path_join(dir))
		var item := {"dir": dir, "version": meta.get("difficulty", ""), "level": 0, "notes": int(meta.get("notes", 0)), "indexed": false}
		if str(dir).begins_with("_"): others.copies.append(item); continue
		var h := _audio_hash(audio_of(root.path_join(dir)))
		if hash_to_key.has(h): groups[hash_to_key[h]].copies.append(item); continue
		var title: String = meta.get("title", "") if not str(meta.get("title", "")).is_empty() else dir
		groups[dir] = {"key": dir, "title": title, "artist": meta.get("artist", ""), "cover": cover_of(root, dir), "diffs": [], "copies": [item]}
		order.append(dir)
	var out := []
	for k in order:
		groups[k].diffs.sort_custom(func(a, b): return a.level > b.level)
		out.append(groups[k])
	var fans := FanChartLibrary.discover(root)
	for notice in fans.notices: print("Fan-made charts: ", notice)
	if not fans.entries.is_empty():
		out.append({"key": "_fan-made", "title": FanChartLibrary.GROUP, "artist": "", "cover": "", "diffs": [], "copies": [], "other": true})
	for e in fans.entries:
		out.append({"key": e.dir, "title": e.title, "artist": e.artist, "cover": cover_of(root, e.dir, e), "diffs": [e], "copies": [], "fan_made": true})
	if not others.copies.is_empty(): out.append(others)
	return out

## ------------------------------------------------------------------ helpers
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"): out += ch
		elif not out.ends_with("_"): out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "song"

static func unique_dir(root: String, base: String) -> String:
	var name := base; var n := 2
	while DirAccess.dir_exists_absolute(root.path_join(name)): name = "%s_%d" % [base, n]; n += 1
	return name

static func stamp() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

static func load_audio(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3": return AudioStreamMP3.load_from_file(path)
		"ogg": return AudioStreamOggVorbis.load_from_file(path)
		"wav": return AudioStreamWAV.load_from_file(path)
	return null

static func audio_length(path: String) -> float:
	var s := load_audio(path)
	return s.get_length() if s != null else 0.0

## Peaks of the decoded audio for a waveform: one value (0..1) per `step` seconds.
static func peaks(path: String, step: float = 0.02, max_seconds: float = 600.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var s := load_audio(path)
	if s == null: return out
	var pb := s.instantiate_playback()
	if pb == null or not pb.has_method("mix_audio"): return out
	var rate := AudioServer.get_mix_rate()
	var per := maxi(1, int(rate * step))
	var total := int(minf(s.get_length(), max_seconds) * rate)
	pb.start(0.0)
	var done := 0; var acc := 0.0; var count := 0
	while done < total:
		var buf: PackedVector2Array = pb.mix_audio(1.0, mini(4096, total - done))
		if buf.is_empty(): break
		for v in buf:
			acc = maxf(acc, maxf(absf(v.x), absf(v.y))); count += 1
			if count >= per: out.append(minf(1.0, acc)); acc = 0.0; count = 0
		done += buf.size()
	return out

## The chart a new song starts from: its tempo, and one full-width carrier track that lives for
## the whole song, so notes can be placed straight away.
static func empty_chart(bpm: float, offset: float, title: String, artist: String, difficulty: String) -> Dictionary:
	return {"bpm": bpm, "offset": offset, "timing": [{"t": offset, "beat": 60.0 / bpm, "meter": 4}],
		"meta": {"title": title, "artist": artist, "difficulty": difficulty},
		"lights": [{"t": 0.0, "id": 0, "type": "on", "x": 0.5, "w": 1.0, "a": 0.5}], "notes": []}

static func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(text); f.close(); return true

static func _copy_dir(src: String, dst: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dst) != OK: return false
	for f in DirAccess.get_files_at(src):
		if DirAccess.copy_absolute(src.path_join(f), dst.path_join(f)) != OK: return false
	for d in DirAccess.get_directories_at(src):
		if not d.begins_with(".") and not _copy_dir(src.path_join(d), dst.path_join(d)): return false
	return true

## ------------------------------------------------------------------ new song
## opts: audio (path), title, artist, bpm, offset, difficulty, level, add_to_index (default true)
static func create_song(root: String, opts: Dictionary) -> Dictionary:
	var audio := str(opts.get("audio", ""))
	if not FileAccess.file_exists(audio): return {"error": "找不到音频文件，请重新选择"}
	var ext := audio.get_extension().to_lower()
	if not ext in AUDIO_EXT: return {"error": "音频需要是 mp3、ogg 或 wav"}
	var title := str(opts.get("title", "")).strip_edges()
	if title.is_empty(): return {"error": "请填写歌名"}
	var bpm := float(opts.get("bpm", 0.0))
	if bpm < 20.0 or bpm > 400.0: return {"error": "BPM 需要在 20 到 400 之间"}
	var difficulty := str(opts.get("difficulty", "EX")).strip_edges().to_upper()
	if difficulty.is_empty(): difficulty = "EX"
	var community: bool = opts.get("fan_made", false)
	if community and ext not in ["ogg", "mp3"]: return {"error": "社区谱面需要 OGG 或 MP3 音频"}
	if community and str(opts.get("artist", "")).strip_edges().is_empty(): return {"error": "请填写音乐作者"}
	var parent := root.path_join("fan-made") if community else root
	if community:
		if not PluginPack.root_path(root).errors.is_empty(): return {"error": "歌曲根目录不安全"}
		if DirAccess.make_dir_recursive_absolute(parent) != OK or not PluginPack.root_path(parent).errors.is_empty(): return {"error": "社区谱面目录不安全"}
	var base := (slug(title).left(35) + "_" + slug(difficulty).left(8)) if community else (slug(title) + "_" + slug(difficulty))
	var dir := unique_dir(parent, base)
	if community: dir = "fan-made/" + dir
	var path := root.path_join(dir)
	if DirAccess.make_dir_recursive_absolute(path) != OK: return {"error": "无法创建文件夹 " + path}
	if DirAccess.copy_absolute(audio, path.path_join("audio." + ext)) != OK: return {"error": "复制音频失败"}
	var artist := str(opts.get("artist", "")).strip_edges()
	var chart := empty_chart(bpm, float(opts.get("offset", 0.0)), title, artist, difficulty)
	if not _write(path.path_join("chart.json"), Document.canonical(chart)): return {"error": "写入 chart.json 失败"}
	var result := {"dir": dir, "path": path.path_join("chart.json"), "fan_made": community}
	if community:
		chart["audio"] = "audio." + ext
		if not _write(path.path_join("chart.json"), Document.canonical(chart)): return {"error": "写入谱面失败"}
		var info := {"title": title, "artist": artist, "version": difficulty, "level": int(opts.get("level", 0)), "bpm": bpm,
			"preview": 0, "audio": "audio." + ext, "chart_author": str(opts.get("chart_author", "填写谱师姓名")), "chart_license": "CC-BY-SA-4.0",
			"audio_license": {"id": "", "url": "", "evidence": ""}}
		if not _write(path.path_join("info.json"), JSON.stringify(info, "  ")): return {"error": "写入 info.json 失败"}
		if not _write(path.path_join("CREDITS.md"), "# Credits / 授权说明\n\nChart author / 谱师: " + str(info.chart_author) + "\n\nChart data: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).\n\nAudio author, licence URL and evidence: TODO\nCover licence (if any): TODO\nConversion original mapper permission_url (if any): TODO\n"): return {"error": "写入 CREDITS.md 失败"}
	elif opts.get("add_to_index", true):
		var idx := add_to_index(root, dir, {"set": str(opts.get("set", slug(title))), "version": difficulty, "level": int(opts.get("level", 0)), "title": title, "artist": artist})
		if idx.has("error"): return idx
		result["index_backup"] = idx.get("backup", "")
	return result

## ------------------------------------------------------------------ game song list
## Make sure `dir` is in songs/index.json (difficulty = set + version). Fills bpm, length, notes,
## audio and cover from the folder. Backs index.json up first. fields may override set, version,
## level, title, artist, cover, preview.
static func add_to_index(root: String, dir: String, fields: Dictionary = {}) -> Dictionary:
	if dir.begins_with("fan-made/"): return {"error": "社区谱面由 info.json 自动发现，无需加入 index.json"}
	var path := root.path_join(dir)
	if not FileAccess.file_exists(path.path_join("chart.json")): return {"error": "这个文件夹里没有 chart.json"}
	var audio := audio_of(path)
	if audio.is_empty(): return {"error": "这个文件夹里没有 audio.mp3 / ogg / wav，游戏无法播放"}
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("chart.json")))
	if not raw is Dictionary: return {"error": "chart.json 不是有效的谱面"}
	var meta: Dictionary = raw.get("meta", {}) if raw.get("meta", {}) is Dictionary else {}
	var index := read_index(root)
	var existing := {}
	var at := -1
	for i in index.size():
		if index[i] is Dictionary and str(index[i].get("dir", "")) == dir: existing = index[i]; at = i
	var entry := existing.duplicate(true)
	entry["dir"] = dir
	for k in ["set", "title", "artist", "version", "level", "cover", "preview"]:
		if fields.has(k): entry[k] = fields[k]
	if not entry.has("title"): entry["title"] = str(meta.get("title", dir))
	if not entry.has("artist"): entry["artist"] = str(meta.get("artist", ""))
	if not entry.has("set"): entry["set"] = slug(str(entry.title))
	if not entry.has("version"): entry["version"] = str(meta.get("difficulty", "EX")) if not str(meta.get("difficulty", "")).is_empty() else "EX"
	if not entry.has("level"): entry["level"] = 0
	for e in index:
		if e is Dictionary and str(e.get("dir", "")) != dir and str(e.get("set", "")) == str(entry.set) and str(e.get("version", "")) == str(entry.version):
			return {"error": "游戏歌单里这首歌已经有 %s 难度（%s），请换一个难度名" % [str(entry.version), str(e.get("dir", ""))]}
	entry["bpm"] = float(raw.get("bpm", 120.0))
	entry["audio"] = audio.get_file()
	entry["length"] = snappedf(audio_length(audio), 0.01)
	entry["notes"] = (raw.get("notes", []) as Array).size() if raw.get("notes", []) is Array else 0
	if not entry.has("preview"): entry["preview"] = -1.0
	if not entry.has("cover"):
		var c := cover_of(root, dir, entry)
		entry["cover"] = c.trim_prefix(root + "/") if not c.is_empty() else ""
	var backup := ""
	var index_path := root.path_join("index.json")
	if FileAccess.file_exists(index_path):
		backup = index_path + ".bak-" + stamp()
		if DirAccess.copy_absolute(index_path, backup) != OK: return {"error": "备份 index.json 失败，没有改动歌单"}
	if at >= 0: index[at] = entry
	else: index.append(entry)
	if not _write(index_path, JSON.stringify(index, " ", false)): return {"error": "写入 index.json 失败"}
	return {"entry": entry, "backup": backup, "added": at < 0}

## ------------------------------------------------------------------ audio
## Replace a song's audio with another file. The old audio is kept as audio.<ext>.bak-<time>.
static func replace_audio(dir_path: String, new_audio: String) -> Dictionary:
	if not FileAccess.file_exists(new_audio): return {"error": "找不到这个音频文件"}
	var ext := new_audio.get_extension().to_lower()
	if not ext in AUDIO_EXT: return {"error": "音频需要是 mp3、ogg 或 wav"}
	if FileAccess.file_exists(dir_path.path_join(".read-only")): return {"error": "这是受保护的原始歌曲，请在工作副本里替换音频"}
	var backups := []
	for e in AUDIO_EXT:
		var old := dir_path.path_join("audio." + e)
		if FileAccess.file_exists(old):
			var b := old + ".bak-" + stamp()
			if DirAccess.rename_absolute(old, b) != OK: return {"error": "无法备份原来的音频"}
			backups.append(b)
	if DirAccess.copy_absolute(new_audio, dir_path.path_join("audio." + ext)) != OK: return {"error": "复制音频失败"}
	return {"path": dir_path.path_join("audio." + ext), "backups": backups}

## ------------------------------------------------------------------ export
## The lean chart.json text of a folder (or of the given chart dictionary).
static func lean_text(raw: Dictionary) -> String:
	return Document.canonical(Document.lean(raw))

static func export_chart(src_dir: String, out_path: String, raw: Dictionary = {}, overwrite := false) -> Dictionary:
	if FileAccess.file_exists(out_path) and not overwrite: return {"error": "exists", "path": out_path}
	if raw.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(src_dir.path_join("chart.json")))
		if not v is Dictionary: return {"error": "chart.json 不是有效的谱面"}
		raw = v
	if not _write(out_path, lean_text(raw)): return {"error": "无法写入 " + out_path}
	return {"path": out_path}

## A song package (.zip): chart.json (lean), audio, cover, analysis.json, chart.ext.json when
## present, and manifest.json (title, artist, difficulties, a plugins list kept for later).
static func export_package(root: String, dir: String, out_path: String, raw: Dictionary = {}, overwrite := false) -> Dictionary:
	if FileAccess.file_exists(out_path) and not overwrite: return {"error": "exists", "path": out_path}
	var path := root.path_join(dir)
	if raw.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("chart.json")))
		if not v is Dictionary: return {"error": "chart.json 不是有效的谱面"}
		raw = v
	var audio := audio_of(path)
	if audio.is_empty(): return {"error": "这首歌没有音频文件，无法打包"}
	var entry := {}
	for e in read_index(root):
		if e is Dictionary and str(e.get("dir", "")) == dir: entry = e
	var meta: Dictionary = raw.get("meta", {}) if raw.get("meta", {}) is Dictionary else {}
	var cover := cover_of(root, dir, entry)
	var files := {"chart.json": lean_text(raw).to_utf8_buffer(), audio.get_file(): FileAccess.get_file_as_bytes(audio)}
	if not cover.is_empty(): files["cover." + cover.get_extension()] = FileAccess.get_file_as_bytes(cover)
	for extra in ["analysis.json", "chart.ext.json"]:
		if FileAccess.file_exists(path.path_join(extra)): files[extra] = FileAccess.get_file_as_bytes(path.path_join(extra))
	var manifest := {"format": PACKAGE_FORMAT, "format_version": 1,
		"title": str(entry.get("title", meta.get("title", dir))), "artist": str(entry.get("artist", meta.get("artist", ""))),
		"bpm": float(raw.get("bpm", 120.0)), "length": snappedf(audio_length(audio), 0.01),
		"difficulties": [{"version": str(entry.get("version", meta.get("difficulty", "EX"))), "level": int(entry.get("level", 0)),
			"notes": (raw.get("notes", []) as Array).size(), "chart": "chart.json"}],
		"files": files.keys(), "plugins": [], "exported_by": "L’âge tendre Charter", "exported_at": Time.get_datetime_string_from_system()}
	files["manifest.json"] = JSON.stringify(manifest, "  ", false).to_utf8_buffer()
	var tmp := out_path + ".charter-tmp"
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK: return {"error": "无法写入 " + out_path}
	for name in files:
		zip.start_file(name); zip.write_file(files[name]); zip.close_file()
	zip.close()
	if FileAccess.file_exists(out_path): DirAccess.remove_absolute(out_path)
	if DirAccess.rename_absolute(tmp, out_path) != OK: return {"error": "无法写入 " + out_path}
	return {"path": out_path, "files": manifest.files, "manifest": manifest}

## ------------------------------------------------------------------ import
## A chart.json for an existing song: becomes a new working copy next to it, with that song's audio.
static func import_chart(root: String, chart_file: String, audio_from_dir: String) -> Dictionary:
	var v = JSON.parse_string(FileAccess.get_file_as_string(chart_file)) if FileAccess.file_exists(chart_file) else null
	if not v is Dictionary or not v.has("notes") or not v.has("lights"): return {"error": "这不是一个谱面文件（需要有 notes 和 lights）"}
	var audio := audio_of(root.path_join(audio_from_dir))
	if audio.is_empty(): return {"error": "当前歌曲没有音频，无法给导入的谱面配音频"}
	var dir := unique_dir(root, audio_from_dir.trim_prefix("_") + "_import")
	var path := root.path_join(dir)
	DirAccess.make_dir_recursive_absolute(path)
	if DirAccess.copy_absolute(chart_file, path.path_join("chart.json")) != OK or DirAccess.copy_absolute(audio, path.path_join(audio.get_file())) != OK:
		return {"error": "复制文件失败"}
	return {"dir": dir, "path": path.path_join("chart.json")}

## A song folder (chart.json + audio) copied into the songs root.
static func import_folder(root: String, folder: String) -> Dictionary:
	if not FileAccess.file_exists(folder.path_join("chart.json")): return {"error": "这个文件夹里没有 chart.json"}
	if audio_of(folder).is_empty(): return {"error": "这个文件夹里没有 audio.mp3 / ogg / wav"}
	var dir := unique_dir(root, slug(folder.get_file()))
	if not _copy_dir(folder, root.path_join(dir)): return {"error": "复制文件夹失败"}
	return {"dir": dir, "path": root.path_join(dir).path_join("chart.json")}

## A song package or any zip holding chart.json + audio (at the top or inside one folder).
static func import_zip(root: String, zip_path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK: return {"error": "无法打开这个压缩包"}
	var names := zip.get_files()
	var prefix := ""
	for n in names:
		if n.get_file() == "chart.json": prefix = n.get_base_dir(); break
	if not (prefix.path_join("chart.json") if not prefix.is_empty() else "chart.json") in names: zip.close(); return {"error": "压缩包里没有 chart.json"}
	var manifest := {}
	var mpath := prefix.path_join("manifest.json") if not prefix.is_empty() else "manifest.json"
	if mpath in names:
		var m = JSON.parse_string(zip.read_file(mpath).get_string_from_utf8())
		if m is Dictionary: manifest = m
	var base := slug(str(manifest.get("title", zip_path.get_file().get_basename())))
	var dir := unique_dir(root, base)
	var path := root.path_join(dir)
	DirAccess.make_dir_recursive_absolute(path)
	var has_audio := false
	for n in names:
		if n.ends_with("/") or (not prefix.is_empty() and not n.begins_with(prefix + "/")): continue
		var rel := n.trim_prefix(prefix + "/") if not prefix.is_empty() else n
		if rel.contains("/") or rel.contains("..") or rel.is_empty(): continue
		if rel.get_basename() == "audio" and rel.get_extension().to_lower() in AUDIO_EXT: has_audio = true
		_write_bytes(path.path_join(rel), zip.read_file(n))
	zip.close()
	if not has_audio: return {"error": "压缩包里没有 audio.mp3 / ogg / wav", "dir": dir}
	return {"dir": dir, "path": path.path_join("chart.json"), "manifest": manifest}

static func _write_bytes(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_buffer(data); f.close()
