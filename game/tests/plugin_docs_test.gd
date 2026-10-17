## Run the bilingual JSON and script examples through actual API-1 sessions.
## --isolated-test-user [--docs-root=absolute-directory-containing-guides]
extends SceneTree

var checks := 0
var failures := 0
var docs_root := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content); file.close()

func _init() -> void:
	run.call_deferred()

func run() -> void:
	if not "--isolated-test-user" in OS.get_cmdline_user_args():
		push_error("Dedicated HOME/XDG and --isolated-test-user are required")
		quit(2); return
	docs_root = ProjectSettings.globalize_path("res://")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--docs-root="): docs_root = argument.trim_prefix("--docs-root=")
	KB.set_layout("ansi")
	if FileAccess.file_exists(SongPluginSession.TRUST_PATH): DirAccess.remove_absolute(SongPluginSession.TRUST_PATH)
	check(PluginRegistry.CATEGORIES == ["events", "note_kinds", "flags", "rules", "motions", "track_geometry", "channels", "elements", "validators"], "documented nine categories match actual registry; services are separate")
	for guide in ["PLUGINS_API.md", "PLUGINS_API.zh-CN.md"]: test_guide(guide)
	print("PLUGIN DOCS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_guide(name: String) -> void:
	var source := FileAccess.get_file_as_string(docs_root.path_join(name))
	check(not source.is_empty(), name + " exists")
	var fences := RegEx.new(); fences.compile("(?s)```json\\n(.*?)\\n```")
	var manifest := {}; var chart := {}
	var snippets := fences.search_all(source)
	check(snippets.size() >= 7, name + " has executable JSON examples")
	for snippet in snippets:
		var parsed := JSON.new()
		var status := parsed.parse(snippet.get_string(1))
		check(status == OK, name + " JSON example parses")
		if status != OK or not parsed.data is Dictionary: continue
		if parsed.data.has("provides"): manifest = parsed.data
		if parsed.data.has("bpm") and parsed.data.has("notes"): chart = parsed.data
	check(not manifest.is_empty() and not chart.is_empty(), name + " contains complete manifest and chart")
	if manifest.is_empty() or chart.is_empty(): return
	var folder := "user://p7_docs_examples/" + name + "/" + str(Time.get_ticks_usec())
	write(folder.path_join("plugins/glow_ring/plugin.json"), JSON.stringify(manifest))
	write(folder.path_join("chart.json"), JSON.stringify(chart))
	check(PluginLoader.validate_manifest(manifest).errors.is_empty(), name + " manifest matches actual loader schema")
	var session := SongPluginSession.new()
	var report := session.prepare(folder, chart, name)
	check(report.errors.is_empty() and not report.requires_trust, name + " example prepares without script trust")
	var opened := session.open()
	check(opened.errors.is_empty() and opened.loaded == ["glow_ring"], name + " actual declarative provider opens")
	if not opened.errors.is_empty(): session.close(); return
	var core := GameCore.new(session.registry)
	check(core.load_chart(session.chart_data) and core.chart.warnings.is_empty() and core.notes.size() == 1 and core.notes[0].ring == 1, name + " example normalizes real plugin field")
	core.autoplay = true; core.playing = true
	for step in 600: core.update(float(step) / 120.0)
	check(core.stats.score == 1010000 and core.stats.total == 1 and core.stats.MISS == 0, name + " example autoplay has one perfect judgement")
	core = null; session.close()
	var script_fences := RegEx.new(); script_fences.compile("(?s)```gdscript\\n(@static_unload.*?)\\n```")
	var entries := script_fences.search_all(source)
	check(entries.size() == 1, name + " has one complete script entry")
	if entries.size() != 1: return
	var scripted := manifest.duplicate(true)
	scripted.id = "my_package"; scripted.tier = "script"; scripted.entry = "entry.gd"
	scripted.provides = {"elements": ["my_decoration"]}; scripted.fields = []; scripted.erase("definitions")
	write(folder.path_join("plugins/my_package/plugin.json"), JSON.stringify(scripted))
	write(folder.path_join("plugins/my_package/entry.gd"), entries[0].get_string(1))
	var with_script := chart.duplicate(true)
	with_script.plugins = [{"id": "my_package", "version": "1.0.0"}]
	report = session.prepare(folder, with_script, name + " script")
	check(report.errors.is_empty() and report.requires_trust, name + " script entry example requires trust")
	check(session.remember_trust(true), name + " test explicitly approves isolated example")
	opened = session.open()
	check(opened.errors.is_empty() and not session.registry.get_entry("elements", "my_decoration").is_empty(), name + " exact documented GDScript compiles and installs")
	var owned: Object
	if session.registry != null:
		for entry in session.registry._owned:
			if entry.object is Node: owned = entry.object
	check(is_instance_valid(owned), name + " documented ownership retains node")
	session.close()
	check(not is_instance_valid(owned), name + " documented teardown cooperatively frees node")
