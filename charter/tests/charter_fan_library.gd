extends SceneTree
## Actual library widgets and community creation on an isolated root.
const Lib = preload("res://song_library.gd")
const Library = preload("res://ui/library.gd")
const NewSong = preload("res://ui/new_song.gd")
const Owned = preload("res://tests/owned_nodes.gd")
class TestApp:
	extends "res://app.gd"
	var fixture_root := ""
	func songs_root() -> String: return fixture_root
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _init() -> void: run.call_deferred()
func run() -> void:
	var folder: String = OS.get_cmdline_user_args()[0]
	KB.set_layout("ansi")
	var before_nodes := Owned.snapshot()
	var app := TestApp.new(); app.fixture_root = folder
	app._scan_songs()
	check("fan-made/alpha" in app.song_dirs and not "fan-made/_template" in app.song_dirs, "actual charter app scans nested submissions and excludes template")
	app.doc.path = folder.path_join("fan-made/alpha/chart.json")
	check(app.current_dir() == "fan-made/alpha", "charter app retains nested song identity")
	app.doc.path = folder.get_base_dir().path_join("external/chart.json")
	check(app.current_dir() == "external", "external charter documents retain basename identity")
	app.free(); app = null; Owned.release_since(before_nodes)
	var library := Library.new(); library.root = folder
	root.add_child(library); library.rescan()
	var titles := []; var head := false
	for g in library.groups:
		if g.key == "_fan-made": head = g.title == FanChartLibrary.GROUP
		if g.get("fan_made", false): titles.append(g.title)
	check(head and titles == ["Alpha original", "Zulu original"], "actual charter library has sorted fan rows under community header")
	check(library.rows.any(func(row): return row.kind == "head" and row.group.key == "_fan-made"), "community header reaches library UI rows")
	var index := folder.path_join("index.json")
	var before := FileAccess.get_file_as_string(index) if FileAccess.file_exists(index) else ""
	var wizard := NewSong.new(); root.add_child(wizard); wizard.root = folder; wizard.open(true)
	check(wizard.fan_made and wizard.heading.text == "新建社区谱面", "new-song wizard offers community mode")
	wizard.audio_path = folder.path_join("fan-made/alpha/audio.mp3")
	wizard.title_edit.text = "Created Community"; wizard.artist_edit.text = "Fixture generator"
	var made := {}
	wizard.created.connect(func(result): made.merge(result))
	wizard._create()
	check(not made.is_empty() and made.get("dir", "").begins_with("fan-made/"), "wizard creates nested community song")
	if not made.is_empty():
		var path: String = made.path.get_base_dir()
		var info = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("info.json")))
		var chart = JSON.parse_string(FileAccess.get_file_as_string(made.path))
		check(info is Dictionary and info.title == "Created Community" and info.chart_license == "CC-BY-SA-4.0" and info.audio_license is Dictionary, "community info metadata and licence skeleton written")
		var credits := FileAccess.get_file_as_string(path.path_join("CREDITS.md"))
		check(credits.contains("\n\nChart author") and not credits.contains("\\n"), "community credits skeleton has real Markdown paragraphs")
		check(chart is Dictionary and chart.lights.size() == 1 and chart.notes.is_empty() and ChartLib.validate(chart).warnings.is_empty(), "one-carrier v3 chart skeleton validates")
		check(Lib.add_to_index(folder, made.dir).has("error"), "community entries cannot be added to shared index")
	check((FileAccess.get_file_as_string(index) if FileAccess.file_exists(index) else "") == before, "new community song leaves shared index exact")
	wizard.free(); library.free()
	for i in 3: await process_frame
	print("FAN LIBRARY: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)
