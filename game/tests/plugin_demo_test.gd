## P6 real sample-pack checks. Use an isolated HOME/XDG with Dummy audio.
## Refuses to run against a non-test user directory unless explicitly requested.
## --songs-root=<absolute external songs> is required for compiled-PCK fixtures.
extends SceneTree

const MARKER := "user://plugin_demos/trust_spark_loaded.txt"
const AUDIO_SHA := "ee03f7aab8dc52a8f43167a10514f1f557647f98129a62a40de3e3eeee74f50c"
var checks := 0
var failures := 0
var evidence := {}
var songs := ""
var assets_root := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1; print("FAIL ", label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	if not "--isolated-test-user" in OS.get_cmdline_user_args():
		push_error("Pass --isolated-test-user only with a dedicated writable HOME/XDG.")
		quit(2); return
	KB.set_layout("ansi")
	songs = ProjectSettings.globalize_path("res://../songs")
	assets_root = ProjectSettings.globalize_path("res://assets")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--songs-root="): songs = argument.trim_prefix("--songs-root=")
		if argument.begins_with("--assets-root="): assets_root = argument.trim_prefix("--assets-root=")
	check(AudioServer.get_driver_name() == "Dummy", "real Dummy audio driver is required")
	check(songs.is_absolute_path() and DirAccess.dir_exists_absolute(songs), "required absolute external songs directory exists")
	check(FileAccess.file_exists(songs.path_join("_plugin_demos/index.json")), "required separate demo index exists")
	check(assets_root.is_absolute_path() and FileAccess.file_exists(assets_root.path_join("tex/receptor.png")), "required original asset-byte reference exists externally; compiled textures are remapped")
	for id in ["glow_ring", "script_trust"]:
		var chart_path := pack(id).path_join("chart.json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(chart_path)) if FileAccess.file_exists(chart_path) else null
		check(parsed is Dictionary and parsed.get("notes") is Array and parsed.notes.size() == 72 and FileAccess.file_exists(pack(id).path_join("audio.wav")), id + " real chart and audio are present; notes is the required 72-entry array")
	if failures:
		print("PLUGIN DEMOS: %d checks, %d failures" % [checks, failures])
		quit(1); return
	DirAccess.make_dir_recursive_absolute("user://p6_demo_tests")
	for file in [SongPluginSession.TRUST_PATH, MARKER, "user://p6_demo_tests/best.json"]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	var standard := PluginRegistry.standard()
	var initial := standard.records.duplicate(true)
	test_index()
	var declared_stats := test_declarative()
	test_trust(declared_stats)
	test_changed_hash()
	check(standard.records == initial, "sample songs leave shared standard catalog unchanged")
	test_song_b()
	evidence.checks = checks; evidence.failures = failures
	DirAccess.make_dir_recursive_absolute("user://p6_demo_tests")
	SU.save_json("user://p6_demo_tests/results.json", evidence)
	print("PLUGIN DEMOS: %d checks, %d failures" % [checks, failures])
	print("EVIDENCE ", JSON.stringify(evidence))
	quit(1 if failures else 0)

func pack(id: String) -> String:
	return songs.path_join("_plugin_demos").path_join(id)

func raw_for(id: String) -> Dictionary:
	return SU.load_json(pack(id).path_join("chart.json"))

func test_index() -> void:
	var index: Array = SU.load_json(songs.path_join("_plugin_demos/index.json"), [])
	var by_id := {}
	for entry in index:
		check(not by_id.has(entry.dir), "demo menu directory is unique: " + str(entry.dir))
		by_id[entry.dir] = entry
	check(index.size() == 5, "separate demo menu supplement has five entries")
	for id in ["glow_ring", "script_trust"]:
		var entry: Dictionary = by_id.get("_plugin_demos/" + id, {})
		check(not entry.is_empty() and entry.notes == raw_for(id).notes.size() and entry.length == 70 and entry.audio == "audio.wav", id + " menu metadata matches actual package")
		check(FileAccess.file_exists(songs.path_join(str(entry.get("cover", "")))), id + " reuses an existing cover")
	for row in [["shapes", 10], ["motion", 3], ["speed", 18]]:
		var entry: Dictionary = by_id.get("_plugin_demos/" + row[0], {})
		check(not entry.is_empty() and entry.notes == row[1], row[0] + " menu metadata matches that package author's supplied index contract")

func autoplay(session: SongPluginSession, label: String) -> Dictionary:
	var core := GameCore.new(session.registry)
	check(core.load_chart(session.chart_data), label + " loads into actual GameCore")
	check(core.chart.notes.size() == 72, label + " has 72 real notes")
	check(core.chart.warnings.is_empty(), label + " validates without warnings: " + str(core.chart.warnings))
	check(core.notes[0].ring > 0.0, label + " plugin field reaches normalized runtime notes")
	core.autoplay = true; core.playing = true
	var step := 0
	while core.playing and step < 6000:
		core.update(float(step) / 120.0); step += 1
	var stats := core.stats.duplicate(true)
	check(not core.playing and stats.score == 1010000 and stats.MISS == 0 and stats.PERFECT == stats.total, label + " autoplay all perfect/full score")
	print("AUTOPLAY ", label, " ", JSON.stringify(stats))
	core = null
	return stats

func ring_geometry(session: SongPluginSession, label: String) -> void:
	var core := GameCore.new(session.registry)
	core.load_chart(session.chart_data)
	var renderer := Renderer.new(session.registry)
	var states := {}; var t := 9.25
	for state in core.light_states(t, 1.0): states[state.id] = state
	renderer.f = {"play": true, "t": t, "fall": 1.5, "reach": 1.0, "notes": core.notes, "tl": core.tl, "light_by_id": states}
	renderer.G = renderer._runtime._geo()
	var provider: PluginDeclarative = session.registry.get_entry("elements", "glow_ring").callback.get_object()
	var primitives := provider.ring_primitives(renderer._runtime, "glow_ring")
	check(primitives.size() >= 3, label + " produces actual visible ring primitives")
	var finite := true
	for primitive in primitives:
		finite = finite and primitive.center.is_finite() and is_finite(primitive.radius) and primitive.radius > 0 and primitive.color.a > 0
	check(finite, label + " ring geometry is finite and nonempty")
	check(provider.textures.has("canvas.png") and provider.shaders.has("ring.gdshader"), label + " loads actual listed texture and shader")
	check(session.runtime_notices().is_empty() if label == "declarative" else not session.runtime_notices().is_empty(), label + " runtime notice state matches enabled providers")
	provider = null; renderer.free(); renderer = null; core = null

func test_declarative() -> Dictionary:
	var folder := pack("glow_ring")
	check(FileAccess.get_sha256(folder.path_join("audio.wav")) == AUDIO_SHA, "declarative audio exact existing-project copy")
	check(FileAccess.get_sha256(folder.path_join("plugins/glow_ring/canvas.png")) == FileAccess.get_sha256(assets_root.path_join("tex/receptor.png")), "shader canvas exact existing-project copy")
	var manifest: Dictionary = SU.load_json(folder.path_join("plugins/glow_ring/plugin.json"))
	check(manifest.tier == "declarative" and manifest.entry == null and manifest.fields[0].path == "notes[].ring", "declarative sample documents real ring schema")
	check(not DirAccess.dir_exists_absolute(folder.path_join("plugins/trust_spark")), "declarative sample contains no script plugin")
	var session := SongPluginSession.new()
	var report := session.prepare(folder, raw_for("glow_ring"), "_plugin_demos/glow_ring")
	check(report.errors.is_empty() and not report.requires_trust and report.script_ids.is_empty(), "declarative prepare needs no script trust")
	var opened := session.open()
	check(opened.errors.is_empty() and opened.disabled.is_empty() and opened.loaded == ["glow_ring"], "declarative sample installs actual provider")
	ring_geometry(session, "declarative")
	var stats := autoplay(session, "declarative")
	evidence.declarative = {"identity": session.identity.duplicate(), "stats": stats, "content_hash": report.content_hash}
	session.close()
	check(session.registry == null, "declarative session closes")
	return stats

func test_trust(declared_stats: Dictionary) -> void:
	var folder := pack("script_trust")
	check(FileAccess.get_sha256(folder.path_join("audio.wav")) == AUDIO_SHA, "script sample audio exact existing-project copy")
	var session := SongPluginSession.new()
	var report := session.prepare(folder, raw_for("script_trust"), "_plugin_demos/script_trust")
	check(report.errors.is_empty() and report.requires_trust and report.script_ids == ["trust_spark"], "first script sample prepare requests trust")
	check(not FileAccess.file_exists(MARKER), "prepare never executes even static initializer")
	check(not session.open().errors.is_empty() and not FileAccess.file_exists(MARKER), "unknown trust blocks load without executing")
	check(session.remember_trust(false), "explicit sample denial persists")
	var opened := session.open()
	check(opened.errors.is_empty() and opened.loaded == ["glow_ring"] and opened.disabled.size() == 1, "denial keeps independent declarative provider")
	check(not FileAccess.file_exists(MARKER), "denial never executes static initializer")
	check(session.registry.get_entry("elements", "trust_spark").is_empty(), "denied script render callback absent")
	check("trust_spark" in "; ".join(session.runtime_notices()), "denied plugin name remains visibly reportable")
	ring_geometry(session, "denied")
	var denied_stats := autoplay(session, "script-denied")
	check(denied_stats == declared_stats, "denial preserves every judgement statistic")
	var denied_identity := session.identity.duplicate(); var denied_key := session.score_key
	session.close()
	report = session.prepare(folder, raw_for("script_trust"), "_plugin_demos/script_trust")
	check(report.errors.is_empty() and not report.requires_trust and report.score_key == denied_key, "unchanged content remembers denial")
	check(session.remember_trust(true), "explicit allow can replace denial")
	opened = session.open()
	check(opened.errors.is_empty() and opened.disabled.is_empty() and opened.loaded == ["glow_ring", "trust_spark"], "allow installs real script plus declarative")
	check(FileAccess.file_exists(MARKER), "allow actually executes script static initializer")
	check(not session.registry.get_entry("elements", "trust_spark").is_empty(), "allowed script registers actual render callback")
	var owned: Object
	for entry in session.registry._owned:
		if entry.object is Node and entry.object.name == "TrustSparkDemoState": owned = entry.object
	check(is_instance_valid(owned) and owned.get_meta("demo_script_active", false), "script creates cooperatively owned node")
	var allowed_stats := autoplay(session, "script-allowed")
	check(allowed_stats == denied_stats, "allowed visuals preserve every judgement statistic")
	check(session.score_key != denied_key and "trust_spark@1.0.0" in session.identity, "enabled script gets distinct active identity and score key")
	var scores := PluginScores.new(); scores.load_file("user://p6_demo_tests/best.json")
	scores.update_best("_plugin_demos/script_trust", denied_identity, denied_stats)
	scores.update_best("_plugin_demos/script_trust", session.identity, allowed_stats)
	check(scores.records.size() == 2 and scores.save_file().errors.is_empty(), "allowed and denied sample results remain separate")
	evidence.script_denied = {"identity": denied_identity, "stats": denied_stats}
	evidence.script_allowed = {"identity": session.identity.duplicate(), "stats": allowed_stats, "content_hash": report.content_hash}
	session.close()
	check(not is_instance_valid(owned) and not FileAccess.file_exists(MARKER), "close frees owned node and script teardown removes its marker")
	report = session.prepare(folder, raw_for("script_trust"), "_plugin_demos/script_trust")
	check(report.errors.is_empty() and not report.requires_trust, "unchanged allowed content does not prompt again")
	opened = session.open()
	check(opened.errors.is_empty() and FileAccess.file_exists(MARKER), "remembered allow actually reopens fresh script session")
	session.close()
	check(not FileAccess.file_exists(MARKER), "second close removes second session marker")

func copy_tree(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return false
	var directory := DirAccess.open(source)
	if directory == null: return false
	directory.include_hidden = true; directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			if directory.is_link(name): return false
			if directory.current_is_dir():
				if not copy_tree(source.path_join(name), destination.path_join(name)): return false
			elif DirAccess.copy_absolute(source.path_join(name), destination.path_join(name)) != OK: return false
		name = directory.get_next()
	directory.list_dir_end(); return true

func test_changed_hash() -> void:
	var folder := "user://p6_demo_tests/mutable_pack_" + str(Time.get_ticks_usec())
	check(copy_tree(pack("script_trust"), folder), "copy only test pack into isolated user directory")
	var session := SongPluginSession.new()
	var report := session.prepare(folder, raw_for("script_trust"), "copied-demo")
	check(report.errors.is_empty() and not report.requires_trust, "identical pack bytes share recorded content decision")
	var old_hash: String = report.content_hash
	var file := FileAccess.open(folder.path_join("README.md"), FileAccess.READ_WRITE)
	file.seek_end(); file.store_string("\nChanged content for isolated test.\n"); file.close()
	check(not session.open().errors.is_empty() and not FileAccess.file_exists(MARKER), "changed pack between prepare and open cannot execute")
	report = session.prepare(folder, raw_for("script_trust"), "copied-demo")
	check(report.errors.is_empty() and report.requires_trust and report.content_hash != old_hash, "non-code content change requires a fresh trust decision")
	check(session.remember_trust(false) and session.open().errors.is_empty(), "changed sample can explicitly deny while retaining rings")
	check(not FileAccess.file_exists(MARKER), "changed denied pack never runs script")
	session.close()

func test_song_b() -> void:
	var raw := ChartLib.demo()
	var session := SongPluginSession.new()
	var report := session.prepare("/not-inspected-for-a-legacy-song", raw, "demo")
	check(report.errors.is_empty() and report.content_hash == "" and session.open().errors.is_empty(), "legacy B opens without neighboring pack scan")
	check(session.identity == PluginScores.standard_identity() and session.registry.get_entry("elements", "glow_ring").is_empty() and session.registry.get_entry("elements", "trust_spark").is_empty(), "B has only standard identity and no sample providers")
	var clean := GameCore.new(PluginRegistry.standard()); var after := GameCore.new(session.registry)
	clean.load_chart(raw); after.load_chart(session.chart_data)
	clean.autoplay = true; after.autoplay = true; clean.playing = true; after.playing = true
	var step := 0
	while clean.playing and step < 20000:
		clean.update(float(step) / 120.0); after.update(float(step) / 120.0); step += 1
	check(clean.stats == after.stats and after.stats.score == 1010000, "sample A then legacy B numerical state equals clean B")
	evidence.legacy_b = after.stats.duplicate(true)
	clean = null; after = null; session.close()
