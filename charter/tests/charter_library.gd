extends SceneTree
## Song files on a temporary songs root: new song, game song list (index.json), library grouping,
## export (song package zip, lean chart), import (zip, chart.json, folder), never overwriting.

const Lib = preload("res://song_library.gd")
const Document = preload("res://document.gd")
const Ops = preload("res://edit_ops.gd")
var failed := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed += 1

func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir): return
	for d in DirAccess.get_directories_at(dir): _clear(dir.path_join(d)); DirAccess.remove_absolute(dir.path_join(d))
	for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))

func _init() -> void:
	KB.set_layout("ansi")
	var base := ProjectSettings.globalize_path("res://evidence/temp_library")
	_clear(base)
	var root := base.path_join("songs"); var out := base.path_join("out")
	DirAccess.make_dir_recursive_absolute(root); DirAccess.make_dir_recursive_absolute(out)
	var src_song := ProjectSettings.globalize_path("res://../game/tests/fixtures/dense").simplify_path()
	var audio := ProjectSettings.globalize_path("res://../songs/_demo/audio.wav")
	# an existing game song list with one song
	DirAccess.make_dir_recursive_absolute(root.path_join("old_ex"))
	DirAccess.copy_absolute(src_song.path_join("chart.json"), root.path_join("old_ex/chart.json"))
	DirAccess.copy_absolute(audio, root.path_join("old_ex/audio.wav"))
	var f := FileAccess.open(root.path_join("index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify([{"dir": "old_ex", "set": "old", "title": "Old Song", "artist": "Someone", "version": "EX", "bpm": 202.0, "length": 134.0, "audio": "audio.wav", "cover": "", "preview": -1.0, "notes": 1, "level": 11}]))
	f.close()
	var index_before := FileAccess.get_file_as_string(root.path_join("index.json"))
	# the new song gets its own audio: two seconds of a generated wav
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = 22050; wav.stereo = false
	var pcm := PackedByteArray(); pcm.resize(22050 * 2 * 2)
	for i in 22050 * 2: pcm.encode_s16(i * 2, int(sin(i * 0.05) * 8000.0))
	wav.data = pcm; wav.save_to_wav(base.path_join("tone.wav"))
	var tone := base.path_join("tone.wav")

	# ---- new song
	check(Lib.create_song(root, {"audio": audio, "title": "", "bpm": 120}).has("error"), "new song needs a title")
	check(Lib.create_song(root, {"audio": audio, "title": "x", "bpm": 5}).has("error"), "new song refuses an impossible BPM")
	var made := Lib.create_song(root, {"audio": tone, "title": "Test Song!", "artist": "Me", "bpm": 150.0, "offset": 1.25, "difficulty": "hard", "level": 7})
	check(not made.has("error") and made.dir == "test_song_hard", "new song folder created: " + str(made))
	var dir := root.path_join(str(made.get("dir", "")))
	check(FileAccess.file_exists(dir.path_join("audio.wav")) and FileAccess.get_sha256(dir.path_join("audio.wav")) == FileAccess.get_sha256(tone), "audio copied byte for byte")
	check(Lib.peaks(dir.path_join("audio.wav"), 0.02).size() > 90, "waveform peaks decode for the first-beat view")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("chart.json")))
	check(raw is Dictionary and raw.notes.is_empty() and raw.lights.size() == 1 and absf(float(raw.timing[0].beat) - 0.4) < 1e-9 and float(raw.offset) == 1.25, "empty chart with tempo and one carrier track")
	var v := ChartLib.validate(raw)
	check(v.get("warnings", []).is_empty(), "empty chart validates without warnings: " + str(v.get("warnings", [])))
	var doc = Document.new()
	doc.open(dir.path_join("chart.json"))
	var place: Dictionary = Ops.placement(doc, 4.0, 3, 0.0)
	check(place.ok, "a note can be placed on the new song straight away: " + str(place))
	var index = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("index.json")))
	var entry := {}
	for e in index:
		if e.dir == made.dir:
			entry = e
	check(index.size() == 2 and entry.get("version", "") == "HARD" and int(entry.get("level", 0)) == 7 and absf(float(entry.get("length", 0)) - 2.0) < 0.05 and entry.get("title", "") == "Test Song!", "new song added to index.json: " + str(entry))
	var backups := Array(DirAccess.get_files_at(root)).filter(func(n): return n.begins_with("index.json.bak-"))
	check(backups.size() == 1 and FileAccess.get_file_as_string(root.path_join(backups[0])) == index_before, "index.json backed up before the change")

	# ---- library grouping: a working copy with the same audio sits under its song
	DirAccess.make_dir_recursive_absolute(root.path_join("old_copy"))
	DirAccess.copy_absolute(src_song.path_join("chart.json"), root.path_join("old_copy/chart.json"))
	DirAccess.copy_absolute(audio, root.path_join("old_copy/audio.wav"))
	DirAccess.make_dir_recursive_absolute(root.path_join("_scratch"))
	DirAccess.copy_absolute(src_song.path_join("chart.json"), root.path_join("_scratch/chart.json"))
	var groups := Lib.scan(root)
	var old := {}
	for g in groups:
		if g.key == "old":
			old = g
	check(not old.is_empty() and old.diffs.size() == 1 and old.copies.size() >= 1 and old.copies.any(func(c): return c.dir == "old_copy"), "working copy grouped under its song by audio")
	check(groups[-1].get("other", false) and groups[-1].copies[0].dir == "_scratch", "underscore folders kept apart at the end")

	# ---- game song list: duplicate difficulty refused, a copy can join as a new difficulty
	var dup := Lib.add_to_index(root, "old_copy", {"set": "old", "version": "EX", "level": 11})
	check(dup.has("error"), "same song + same difficulty refused")
	var joined := Lib.add_to_index(root, "old_copy", {"set": "old", "title": "Old Song", "artist": "Someone", "version": "MASTER", "level": 12})
	index = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("index.json")))
	check(not joined.has("error") and joined.added and index.size() == 3 and index[2].set == "old" and index[2].version == "MASTER" and int(index[2].notes) > 100, "working copy joins the game song list")
	var again := Lib.add_to_index(root, "old_copy", {"level": 13})
	index = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("index.json")))
	check(not again.added and index.size() == 3 and int(index[2].level) == 13 and index[2].version == "MASTER", "adding again updates the entry instead of duplicating it")

	# ---- export: song package and lean chart, never overwriting silently
	var zip_path := out.path_join("old.zip")
	var pkg := Lib.export_package(root, "old_ex", zip_path)
	check(not pkg.has("error") and FileAccess.file_exists(zip_path), "song package written")
	var reader := ZIPReader.new(); reader.open(zip_path)
	var names := Array(reader.get_files())
	check("chart.json" in names and "audio.wav" in names and "manifest.json" in names, "package holds chart, audio and manifest: " + str(names))
	var manifest = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	check(manifest is Dictionary and manifest.format == Lib.PACKAGE_FORMAT and manifest.title == "Old Song" and manifest.difficulties[0].version == "EX" and manifest.plugins is Array, "manifest names song, difficulties and a plugins list")
	var packed := reader.read_file("chart.json").get_string_from_utf8()
	var src_raw = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("old_ex/chart.json")))
	check(packed == Lib.lean_text(src_raw), "package chart is the lean chart")
	check(JSON.stringify(ChartLib.validate(JSON.parse_string(packed)).get("notes", []).size()) == JSON.stringify(ChartLib.validate(src_raw).get("notes", []).size()), "lean chart plays the same notes")
	check(reader.read_file("audio.wav").size() == FileAccess.get_file_as_bytes(audio).size(), "package audio complete")
	reader.close()
	var mtime := FileAccess.get_modified_time(zip_path)
	check(Lib.export_package(root, "old_ex", zip_path).get("error", "") == "exists" and FileAccess.get_modified_time(zip_path) == mtime, "existing package not overwritten without asking")
	check(not Lib.export_package(root, "old_ex", zip_path, {}, true).has("error"), "overwrite only when confirmed")
	var chart_out := out.path_join("old.chart.json")
	check(not Lib.export_chart(root.path_join("old_ex"), chart_out).has("error") and FileAccess.get_file_as_string(chart_out) == Lib.lean_text(src_raw), "lean chart.json exported")
	check(Lib.export_chart(root.path_join("old_ex"), chart_out).get("error", "") == "exists", "existing chart.json not overwritten without asking")

	# ---- import
	var imp := Lib.import_zip(root, zip_path)
	check(not imp.has("error") and FileAccess.file_exists(root.path_join(str(imp.dir)).path_join("chart.json")) and FileAccess.file_exists(root.path_join(str(imp.dir)).path_join("audio.wav")), "song package imports into a new folder: " + str(imp.get("dir", imp)))
	var imp2 := Lib.import_chart(root, chart_out, "old_ex")
	check(not imp2.has("error") and FileAccess.file_exists(root.path_join(str(imp2.dir)).path_join("audio.wav")), "chart.json imports as a working copy with the song's audio")
	var imp3 := Lib.import_folder(root, root.path_join("old_ex"))
	check(not imp3.has("error") and imp3.dir != "old_ex" and FileAccess.file_exists(root.path_join(str(imp3.dir)).path_join("chart.json")), "song folder imports without replacing the original")
	check(Lib.import_chart(root, root.path_join("index.json"), "old_ex").has("error"), "a file that is not a chart is refused")
	print("CHARTER_LIBRARY failures=", failed)
	quit(1 if failed else 0)
