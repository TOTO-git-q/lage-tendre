## API 1 P2 security/lifecycle/data tests. All fixtures live in isolated user://.
extends SceneTree

var checks := 0
var failures := 0
var root_folder := "user://p2_session_fixtures"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1; print("FAIL ", label)

func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text); file.close()

func manifest(id: String, tier := "declarative") -> Dictionary:
	return {"id": id, "version": "1.0.0", "api": 1, "tier": tier, "title": id, "author": "Tests", "description": "Generated local fixture", "provides": {}, "fields": [], "assets": [], "entry": "entry.gd" if tier == "script" else null}

func plugin(folder: String, data: Dictionary, script := "") -> void:
	var base := folder.path_join("plugins").path_join(data.id)
	write(base.path_join("plugin.json"), JSON.stringify(data))
	if not script.is_empty(): write(base.path_join("entry.gd"), script)

func number_field(path: String, default_value := 0.0) -> Dictionary:
	return {"path": path, "type": "number", "unit": "keys", "min": 0.0, "max": 4.0, "step": 0.25, "default": default_value, "doc": "Test number"}

func visual_manifest() -> Dictionary:
	var data := manifest("visual")
	data.provides = {"flags": ["ring", "motion"], "channels": ["aura"], "motions": ["test_sway"], "elements": ["glow_ring"]}
	data.fields = [number_field("notes[].ring"), {"path": "notes[].motion", "type": "object", "unit": "motion", "default": {}, "doc": "Visual motion selector"}]
	data.definitions = {"flags": {"ring": {"field": "ring"}, "motion": {"field": "motion"}}, "channels": {"aura": {"default": 0.25, "min": 0.0, "max": 1.0}},
		"motions": {"test_sway": {"x": "x + 0.2 * (1 - progress)", "alpha": "alpha"}},
		"elements": {"glow_ring": {"kind": "glow_ring", "field": "ring", "radius": "value", "opacity": "clamp(alpha, 0, 1)", "color": [0.3, 0.7, 1.0, 0.8], "width": 2.0, "order": 41}}}
	return data

func raw_chart(requirements := []) -> Dictionary:
	var raw := {"bpm": 120, "lights": [{"t": 0.0, "id": 0, "type": "on", "x": 0.5, "w": 0.5, "a": 1.0, "auto": true}],
		"notes": [{"t": 2.0, "light": 0, "u": 0.5, "kind": "tap", "ring": 1.5, "motion": {"type": "test_sway"}}], "fx": [{"t": 0.0, "type": "tween", "ch": "aura", "to": 99.0, "dur": 0.1}]}
	if not requirements.is_empty(): raw.plugins = requirements
	return raw

func requirement(id: String, version := "1.0.0") -> Dictionary:
	return {"id": id, "version": version}

func script_source(label: String) -> String:
	return "@static_unload\nextends RefCounted\nconst Dep = preload(\"dep.gd\")\nstatic func _static_init():\n\tvar f = FileAccess.open(\"user://p2_static_executed\", FileAccess.WRITE)\n\tf.store_string(\"" + label + "\")\nstatic func install(registry, _manifest, _folder):\n\tvar node = Node.new()\n\tnode.name = \"OwnedByScript\"\n\tregistry.own(node)\n\tregistry.connect_owned(Engine.get_main_loop().process_frame, tick)\n\tregistry.register(\"rules\", \"script_rule\", {\"phase\": \"p2_fixture\", \"callback\": rule})\nstatic func rule(context):\n\tcontext.value = Dep.value()\nstatic func tick():\n\tvar f = FileAccess.open(\"user://p2_signal_executed\", FileAccess.WRITE)\n\tf.store_string(\"yes\")\nstatic func teardown(_registry):\n\tvar f = FileAccess.open(\"user://p2_teardown_executed\", FileAccess.WRITE)\n\tf.store_string(\"" + label + "\")\n"

func _init() -> void:
	call_deferred("run_tests")

func remove_fixture_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var child := path.path_join(name)
			if directory.current_is_dir() and not directory.is_link(name): remove_fixture_tree(child)
			else: DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end(); DirAccess.remove_absolute(path)

func run_tests() -> void:
	remove_fixture_tree(root_folder)
	KB.set_layout("ansi")
	for marker in ["user://plugin_trust.json", "user://p2_static_executed", "user://p2_signal_executed", "user://p2_teardown_executed"]:
		if FileAccess.file_exists(marker): DirAccess.remove_absolute(marker)
	test_malformed_values()
	test_formula()
	test_paths()
	test_codec()
	test_scores()
	test_session()
	print("SONG PLUGIN SESSION: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func test_formula() -> void:
	for row in [["1 + 2 * 3", {}, 7.0], ["sin(pi / 2) + max(2, 3)", {}, 4.0], ["clamp(x + 0.5, 0, 1)", {"x": 0.8}, 1.0], ["lerp(x, w, progress)", {"x": 0.2, "w": 0.8, "progress": 0.5}, 0.5], [".5 + 1e-2", {}, 0.51]]:
		var compiled := PluginFormula.compile(row[0])
		check(compiled.errors.is_empty(), "formula compiles " + row[0])
		if compiled.formula != null:
			var result: Dictionary = compiled.formula.evaluate(row[1])
			check(result.ok and absf(result.value - row[2]) < 0.000001, "formula calculates " + row[0])
	for attack in ["load('user://evil.gd')", "preload(\"x\")", "FileAccess.open(1, 2)", "OS.execute(1)", "x.get_class()", "self", "get_script()", "randf()", "print(1)", "str(1)", "[1][0]", "{1:2}", "Vector2(1,2)", "x[0]", "x.call(1)", "true", "INF", "NAN", "x && 1", "1; 2", "1 # comment", "\"1\"", "unknown + 1", "x(1)", "1e999", "(".repeat(25) + "1" + ")".repeat(25), "1+".repeat(100) + "1", "1".repeat(513)]:
		check(not PluginFormula.compile(attack).errors.is_empty(), "formula rejects " + attack.left(50))
	for source in ["sqrt(-1)", "1 / 0", "exp(10000)"]:
		var compiled := PluginFormula.compile(source)
		check(compiled.errors.is_empty() and not compiled.formula.evaluate({}).ok, "formula rejects nonfinite result " + source)
	var formula: PluginFormula = PluginFormula.compile("x").formula
	for bad in [NAN, INF, {}, [], "1", true, Node2D]: check(not formula.evaluate({"x": bad}).ok, "formula rejects nonscalar input")

func test_paths() -> void:
	for row in [["/tmp/song", "/", ["tmp", "song"]], ["C:/Users/Test/song", "C:/", ["Users", "Test", "song"]], ["D:\\music\\song", "D:/", ["music", "song"]], ["//server/share/song", "//server/share/", ["song"]], ["\\\\server\\share\\song", "//server/share/", ["song"]]]:
		var value := PluginPack.decompose_absolute(row[0])
		check(value.errors.is_empty() and value.root == row[1] and value.parts == row[2], "absolute path decomposition " + row[0])
	for bad in ["relative/song", "C:relative", "//server", "//../share/song", "//?/C:/path"]: check(not PluginPack.decompose_absolute(bad).errors.is_empty(), "reject invalid absolute path " + bad)
	for bad in ["../x", "x/../y", "./x", "x//y", "/x", "C:/x", "x\\y", "res://x", "x\nq", ""]: check(not PluginPack.safe_relative(bad), "reject relative traversal " + bad)
	var folder := root_folder.path_join("hash")
	write(folder.path_join("a.txt"), "bc"); write(folder.path_join("hidden/.data"), "secret")
	var first := PluginPack.content_hash(folder)
	check(first.errors.is_empty() and first.hash.length() == 64 and first.files == 2, "hash covers hidden nested content")
	check(first.hash == PluginPack.content_hash(folder).hash, "hash stable")
	DirAccess.rename_absolute(folder.path_join("a.txt"), folder.path_join("ab.txt"))
	write(folder.path_join("ab.txt"), "c")
	check(first.hash != PluginPack.content_hash(folder).hash, "hash length framing binds names and bytes")
	write(folder.path_join("hidden/.data"), "changed")
	check(first.hash != PluginPack.content_hash(folder).hash, "hash binds hidden files")
	var access := DirAccess.open(folder)
	var status := access.create_link(ProjectSettings.globalize_path(folder.path_join("ab.txt")), "linked.txt")
	check(status == OK, "create isolated symlink test fixture")
	if status == OK:
		check(not PluginPack.content_hash(folder).errors.is_empty(), "hash refuses symlink")
		check(not PluginPack.file_path(folder, "linked.txt").errors.is_empty(), "asset refuses symlink")
		DirAccess.remove_absolute(folder.path_join("linked.txt"))

func test_codec() -> void:
	var schemas := [number_field("notes[].ring"), {"path": "notes[].style.alpha", "default": 1.0}, {"path": "meta.settings.enabled", "default": false}, {"path": "notes[].layers[].gain", "default": 0.0}]
	var raw := {"unknown": {"x": [1, 2]}, "notes": [{"ring": 0.0, "style": {"alpha": 1.0, "unknown": 9}, "layers": [{"gain": 0.0, "keep": 3}, {"gain": 2.0}]}, {"ring": 2.0, "style": {"alpha": 0.25}}, {"ring": false}], "meta": {"settings": {"enabled": false, "unknown": true}}}
	var original := raw.duplicate(true)
	var compact := ChartCodec.compact(raw, schemas)
	check(raw == original, "compact does not mutate input")
	check(not compact.notes[0].has("ring") and compact.notes[1].ring == 2.0 and compact.notes[2].ring == false, "compact strips exact numeric default only")
	check(compact.unknown == raw.unknown and compact.notes[0].style.unknown == 9 and compact.meta.settings.unknown, "compact preserves unknown fields recursively")
	check(not compact.notes[0].layers[0].has("gain") and compact.notes[0].layers[1].gain == 2.0, "nested array defaults compact")
	var path := root_folder.path_join("lean.json")
	check(ChartCodec.save_file(path, raw, schemas).ok, "codec save succeeds")
	var saved: Dictionary = SU.load_json(path)
	check(saved.defaults_schema == 1 and saved.defaults_omitted.has("notes[].ring"), "saved chart records only removed defaults")
	var restored := ChartCodec.expand(saved, schemas); restored.erase("defaults_schema"); restored.erase("defaults_omitted")
	check(ChartCodec._equal(restored, original), "nested defaults save/load roundtrip exact")
	check(ChartCodec.expand(raw, schemas) == raw, "unmarked legacy chart never expanded")
	var original_bytes := FileAccess.get_file_as_string(path)
	var partial_schemas := schemas.slice(1)
	var blocked := ChartCodec.save_file(path, saved, partial_schemas)
	check(not blocked.ok and "notes[].ring" in "; ".join(blocked.errors), "save refuses unavailable disabled plugin schema")
	check(FileAccess.get_file_as_string(path) == original_bytes, "blocked default-schema save preserves exact original bytes")
	check(ChartCodec.save_file(path, saved, schemas).ok, "restored plugin schema permits resave")
	var resolved := ChartCodec.expand(SU.load_json(path), schemas); resolved.erase("defaults_schema"); resolved.erase("defaults_omitted")
	check(ChartCodec._equal(resolved, original), "missing then restored schema roundtrip lossless")
	var broken := saved.duplicate(true); broken.defaults_omitted["notes[].ring"] = [[999]]
	var safe_bytes := FileAccess.get_file_as_string(path)
	check(not ChartCodec.save_file(path, broken, schemas).ok and FileAccess.get_file_as_string(path) == safe_bytes, "malformed omission coordinates never overwrite chart")
	var legacy := raw_chart(); legacy.erase("fx"); legacy.notes[0].erase("motion"); legacy.notes[0].erase("ring")
	legacy.lights[0].x = 0.3; legacy.lights[0].w = 0.4; legacy.lights[0].a = 0.7
	legacy.lights.append({"t": 1.0, "id": 0, "type": "sweep", "x": 0.6, "w": 0.4, "dur": 0.5})
	var standard := PluginRegistry.standard()
	var before := ChartLib.validate(legacy, standard)
	check(ChartCodec.save_file(path, legacy, standard.field_schema()).ok, "contextual legacy chart saved")
	var after_raw := ChartCodec.expand(SU.load_json(path), standard.field_schema())
	check(not after_raw.lights[1].has("a") and not after_raw.lights[1].has("tint") and not after_raw.lights[1].has("ease"), "contextual sweep omissions preserved")
	var after := ChartLib.validate(after_raw, standard)
	check(ChartCodec._equal(before, after), "contextual chart normalized output unchanged")
	check(ChartLib.build_timelines(before.lights, standard) == ChartLib.build_timelines(after.lights, standard), "contextual timelines unchanged")

func test_scores() -> void:
	var file := root_folder.path_join("best.json")
	var legacy := {"chart": {"score": 100, "acc": 0.25, "fc": true, "unknown": {"preserve": 7}}, "odd": [1, 2, "unknown"], "schema": {"score": 3}}
	var original := JSON.stringify(legacy, "  ") + "\n"
	write(file, original)
	var scores := PluginScores.new()
	var result := scores.load_file(file)
	check(result.ok and result.migrated, "legacy scores migrate")
	check(FileAccess.get_file_as_string(result.backup) == original, "legacy backup exact bytes")
	var identity := PluginScores.standard_identity()
	check(identity.size() == 4, "standard identity stable four packages")
	check(ChartCodec._equal(scores.records[PluginScores.key_for("chart", identity)], legacy.chart), "migration preserves unknown record fields")
	check(ChartCodec._equal(scores.records[PluginScores.key_for("odd", identity)], legacy.odd), "migration preserves even unusual legacy values")
	check(ChartCodec._equal(scores.records[PluginScores.key_for("schema", identity)], legacy.schema), "legacy chart named schema preserved")
	check(PluginScores.key_for("chart", identity) == PluginScores.key_for("chart", [identity[3], identity[1], identity[0], identity[2], identity[0]]), "score identity order canonical")
	var modified := identity.duplicate(); modified.append("script@1.0.0")
	check(PluginScores.key_for("chart", identity) != PluginScores.key_for("chart", modified), "plugin score separation")
	check(PluginScores.key_for("a|b", ["c"]) != PluginScores.key_for("a", ["b|c"]), "score keys unambiguous")
	var update := scores.update_best("chart", identity, {"score": 200, "accuracy": 0.9, "MISS": 1})
	check(update.new and update.prev == 100 and scores.get_record("chart", identity).fc, "higher score preserves previous FC")
	check(scores.get_record("chart", identity).unknown.preserve == 7, "best update retains extra fields")
	scores.update_best("chart", modified, {"score": 999, "accuracy": 1.0, "MISS": 0})
	check(scores.get_record("chart", identity).score == 200 and scores.get_record("chart", modified).score == 999, "modified result cannot overwrite standard")
	check(scores.save_file().ok, "schema 2 scores save")
	var next := PluginScores.new(); result = next.load_file(file)
	check(result.ok and not result.migrated and ChartCodec._equal(next.records, scores.records), "migration idempotent and roundtrip lossless")
	var copy := next.get_record("chart", identity); copy.score = 0
	check(next.get_record("chart", identity).score == 200, "score access defensive copy")
	write(file, "{broken")
	check(not next.load_file(file).ok and not next.save_file().ok and FileAccess.get_file_as_string(file) == "{broken", "corrupt scores preserved")
	write(file, '{"schema":3,"records":{"future":7}}')
	check(not next.load_file(file).ok and not next.save_file().ok, "unknown score schema preserved")

func test_session() -> void:
	var folder := root_folder.path_join("song")
	var visual := visual_manifest(); plugin(folder, visual)
	var script := manifest("scripted", "script"); script.provides = {"rules": ["script_rule"]}
	script.requires = [requirement("standard_rules")]
	plugin(folder, script, script_source("one"))
	write(folder.path_join("plugins/scripted/dep.gd"), 'extends RefCounted\nstatic func value(): return "one"\n')
	write(folder.path_join("audio.dat"), "fixture audio bytes")
	var dependent := manifest("dependent"); dependent.requires = [requirement("scripted")]
	plugin(folder, dependent)
	var raw := raw_chart([requirement("visual"), requirement("dependent")])
	write(folder.path_join("chart.json"), JSON.stringify(raw))
	var base := PluginRegistry.standard()
	var base_counts := {}; for category in base.records: base_counts[category] = base.records[category].size()
	var session := SongPluginSession.new()
	var result := session.prepare(folder, raw, "song")
	check(result.errors.is_empty() and result.requires_trust and result.script_ids == ["scripted"], "prepare resolves required script closure without execution")
	check(not FileAccess.file_exists("user://p2_static_executed"), "prepare never executes script static initializer")
	check(result.identity.size() == 5 and "visual@1.0.0" in result.identity and "scripted@1.0.0" not in result.identity, "unknown trust previews degraded enabled identity")
	check(not session.open().errors.is_empty() and session.registry == null, "unknown trust cannot open scripts")
	check(not FileAccess.file_exists("user://p2_static_executed"), "unknown open does not execute static initializer")
	check(session.remember_trust(false), "deny decision persisted")
	result = session.open()
	check(result.errors.is_empty() and result.disabled.size() == 2 and result.loaded == ["visual"], "denial disables script and dependent, preserves independent declarative")
	check(not FileAccess.file_exists("user://p2_static_executed"), "denied script never loads, including static initializer")
	check(session.report.notices.size() >= 2 and not session.registry.manifests.has("scripted"), "disabled plugin ids visible in persistent notices")
	var denied_key := session.score_key
	var chart := ChartLib.validate(session.chart_data, session.registry)
	check(chart.notes.size() == 1 and chart.notes[0].ring == 1.5 and chart.notes[0].motion.type == "test_sway", "declarative flags execute actual note normalization")
	var stage := StageFx.new(session.registry); stage.build(chart)
	check(stage.at(1.0).aura == 1.0, "declarative stage channel actually bounded")
	var renderer := Renderer.new(session.registry)
	renderer.f = {"play": true, "t": 1.25, "fall": 1.5, "reach": 1.0, "notes": chart.notes, "tl": ChartLib.build_timelines(chart.lights, session.registry), "light_by_id": {0: {"alive": true, "x": 0.5, "w": 0.5, "alpha": 1.0}}}
	renderer.G = renderer._runtime._geo()
	var moved: Dictionary = renderer._land_st(chart.notes[0], {"alive": true, "x": 0.5, "w": 0.5, "alpha": 1.0})
	check(absf(moved.x - 0.6) < 0.000001, "actual Renderer dispatches custom declarative visual motion")
	var owner: PluginDeclarative = session.registry.get_entry("elements", "glow_ring").callback.get_object()
	var primitives := owner.ring_primitives(renderer._runtime, "glow_ring")
	check(primitives.size() == 1 and primitives[0].radius > 0 and primitives[0].color.a > 0, "declarative glow ring generates actual render primitives")
	var core := GameCore.new(session.registry); check(core.load_chart(session.chart_data), "declarative chart loads in real game")
	core.playing = true; core.press_key("KeyH", 2.0)
	check(core.stats.PERFECT == 1, "visual motion does not change physical judgement")
	core = null; stage = null; renderer.free(); renderer = null; owner = null
	session.close()
	check(session.registry == null and session.identity.is_empty() and session.chart_data.is_empty(), "close clears session state")
	result = session.prepare(folder, raw, "song")
	check(result.errors.is_empty() and not result.requires_trust, "unchanged content remembers denial")
	check(session.remember_trust(true), "explicit allow replaces denial for same hash")
	var connection_count := process_frame.get_connections().size()
	result = session.open()
	check(result.errors.is_empty() and result.disabled.is_empty() and result.loaded == ["scripted", "dependent", "visual"], "allow installs dependency order")
	check(FileAccess.get_file_as_string("user://p2_static_executed") == "one", "allowed script static initializer runs")
	check(session.score_key != denied_key and "scripted@1.0.0" in session.identity, "enabled and degraded scores separate")
	var context := {"value": ""}; RulePipeline.new(session.registry).run("p2_fixture", context)
	check(context.value == "one", "allowed actual script rule and dependency execute")
	var owned: Object = session.registry._owned[0].object
	check(is_instance_valid(owned) and process_frame.get_connections().size() == connection_count + 1, "script ownership and signal recorded")
	session.close()
	check(not is_instance_valid(owned), "close frees plugin-owned node")
	check(process_frame.get_connections().size() == connection_count and FileAccess.get_file_as_string("user://p2_teardown_executed") == "one", "close disconnects owned signals and runs teardown")
	session.close()
	check(process_frame.get_connections().size() == connection_count, "close is idempotent")
	for category in base_counts: check(base.records[category].size() == base_counts[category], "base catalog untouched " + category)
	result = session.prepare(folder, raw, "song")
	check(not result.requires_trust, "same hash allow remembered")
	write(folder.path_join("audio.dat"), "changed pack content")
	check(not session.remember_trust(true) and not session.open().errors.is_empty(), "hash change between prompt and decision/open fails closed")
	result = session.prepare(folder, raw, "song")
	check(result.requires_trust, "noncode pack change requires fresh trust")
	plugin(folder, script, script_source("two"))
	write(folder.path_join("plugins/scripted/dep.gd"), 'extends RefCounted\nstatic func value(): return "two"\n')
	result = session.prepare(folder, raw, "song")
	check(result.requires_trust and session.remember_trust(true), "changed source and dependency reapproved")
	result = session.open(); context.value = ""; RulePipeline.new(session.registry).run("p2_fixture", context)
	check(result.errors.is_empty() and context.value == "two" and FileAccess.get_file_as_string("user://p2_static_executed") == "two", "changed script and preload bypass stale resource caches")
	session.close()
	result = session.prepare("/nonexistent/never/inspect", raw_chart(), "legacy")
	check(result.errors.is_empty() and result.content_hash == "" and not result.requires_trust, "legacy no-plugin fast path never scans or hashes folder")
	result = session.open()
	check(result.errors.is_empty() and session.identity == PluginScores.standard_identity() and session.registry.records.motions.size() == 1, "song B has clean standard identity and motion catalog")
	var original := GameCore.new(base); var next := GameCore.new(session.registry)
	original.load_chart(raw_chart()); next.load_chart(raw_chart()); original.playing = true; next.playing = true; original.autoplay = true; next.autoplay = true
	var t := 0.0
	while t < 6.0: original.update(t); next.update(t); t += 1.0 / 60.0
	check(original.stats == next.stats and next.stats.score == 1010000, "A then B exact clean-start standard numerical state")
	original = null; next = null; session.close()
	test_diagnostics(folder, raw)
	test_declarative_rejections(folder)
	test_recovery_and_errors(folder)

func test_diagnostics(folder: String, raw: Dictionary) -> void:
	var session := SongPluginSession.new()
	for requirements in [[requirement("missing")], [requirement("visual", "2.0.0")], [requirement("standard_rules", "2.0.0")], [requirement("../escape")], [{"id": "visual"}], [requirement("visual"), requirement("visual")]]:
		var chart := raw.duplicate(true); chart.plugins = requirements
		check(not session.prepare(folder, chart, "bad").errors.is_empty(), "clear requirement diagnostic " + str(requirements))
	var a := manifest("cycle_a"); a.requires = [requirement("cycle_b")]
	var b := manifest("cycle_b"); b.requires = [requirement("cycle_a")]
	plugin(folder, a); plugin(folder, b)
	var chart := raw.duplicate(true); chart.plugins = [requirement("cycle_a")]
	check("cycle" in ";".join(session.prepare(folder, chart, "bad").errors), "dependency cycle diagnosed")
	a.requires = [requirement("absent_dependency")]; plugin(folder, a)
	check("absent_dependency" in ";".join(session.prepare(folder, chart, "bad").errors), "missing dependency id diagnosed")
	a.requires = [requirement("visual", "9.0.0")]; plugin(folder, a)
	check("version mismatch" in ";".join(session.prepare(folder, chart, "bad").errors), "dependency version diagnosed")
	var empty := raw.duplicate(true); empty.plugins = []
	check(session.prepare("/missing", empty, "empty").content_hash == "", "empty plugin array also legacy fast path")
	session.close()

func test_declarative_rejections(folder: String) -> void:
	var data := visual_manifest(); var base := folder.path_join("plugins/visual")
	for category in ["events", "note_kinds", "track_geometry", "rules", "validators"]:
		var bad := data.duplicate(true); bad.provides[category] = ["bad"]; bad.definitions[category] = {"bad": {}}
		check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "unsupported declarative category rejected " + category)
	var bad := data.duplicate(true); bad.definitions.erase("motions")
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "missing declarative definition rejected")
	bad = data.duplicate(true); bad.definitions.elements.glow_ring.unknown = 1
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "unsupported definition property rejected")
	bad = data.duplicate(true); bad.definitions.flags.ring.field = "ex"
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "declarative flag cannot override judgement fields")
	bad = data.duplicate(true); bad.definitions.motions.test_sway.x = "load(1)"
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "declarative formula attack rejected during prepare")
	bad = data.duplicate(true); bad.definitions.channels.aura.min = 2
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "bad channel bounds rejected")
	bad = data.duplicate(true); bad.definitions.elements.glow_ring.texture = "unlisted.png"
	check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "unlisted texture rejected")
	for code in ['shader_type canvas_item;\n#include "outside.gdshaderinc"', 'shader_type canvas_item;\n/* comment */ #include "outside.gdshaderinc"', 'shader_type canvas_item;\n# include "outside.gdshaderinc"', 'shader_type spatial; void fragment() {}', '// shader_type canvas_item;\nshader_type spatial;', 'shader_type canvas_item; shader_type spatial;']:
		bad = data.duplicate(true); bad.assets = ["ring.gdshader"]; bad.definitions.elements.glow_ring.shader = "ring.gdshader"
		write(base.path_join("ring.gdshader"), code)
		check(not PluginDeclarative.validate(bad, base).errors.is_empty(), "shader external/include/type escape rejected")
	var texture := Image.create(2, 2, false, Image.FORMAT_RGBA8); texture.fill(Color.WHITE)
	check(texture.save_png(base.path_join("ring.png")) == OK, "generated local texture fixture")
	write(base.path_join("ring.gdshader"), "shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV) * COLOR; }")
	data.assets = ["ring.png", "ring.gdshader"]; data.definitions.elements.glow_ring.texture = "ring.png"; data.definitions.elements.glow_ring.shader = "ring.gdshader"
	check(PluginDeclarative.validate(data, base).errors.is_empty(), "safe listed texture and shader accepted")
	var scope := PluginRegistry.standard().fork_scope(); scope.begin_plugin(data)
	check(PluginDeclarative.install(scope, data, base).is_empty(), "safe assets load directly without scripted resource import")
	scope.end_plugin(); scope.dispose()

func test_recovery_and_errors(folder: String) -> void:
	var data := visual_manifest(); plugin(folder, data)
	var raw := raw_chart([requirement("visual")])
	var session := SongPluginSession.new()
	for value in [-1, 5, "bad", false, {}, [], NAN, INF]:
		var invalid := raw.duplicate(true); invalid.notes[0].ring = value
		var report := session.prepare(folder, invalid, "invalid")
		check(not report.errors.is_empty() and "ring" in "; ".join(report.errors), "invalid declarative chart value diagnosed " + str(value))
	data.definitions.motions.test_sway.x = "sqrt(-1)"
	plugin(folder, data)
	check(session.prepare(folder, raw, "runtime").errors.is_empty() and session.open().errors.is_empty(), "runtime-rejected formula can safely open")
	var renderer := Renderer.new(session.registry)
	renderer.f = {"t": 1.0, "fall": 1.5}
	var state := {"x": 0.5, "w": 0.5, "alpha": 1.0, "alive": true}
	for i in 4: check(renderer._land_st(raw.notes[0], state) == state, "invalid formula leaves visual state unchanged")
	var notices := session.runtime_notices()
	check(notices.size() == 1 and "finite" in str(notices[0]), "runtime formula failure visible and deduplicated")
	renderer.free(); renderer = null; session.close()
	data = visual_manifest(); plugin(folder, data)
	var scripted := manifest("scripted", "script"); scripted.provides = {"rules": ["script_rule"]}
	plugin(folder, scripted, script_source("recovered"))
	write(folder.path_join("plugins/scripted/dep.gd"), 'extends RefCounted\nstatic func value(): return "recovered"\n')
	raw = raw_chart([requirement("visual"), requirement("scripted")])
	var broken := "{invalid saved trust"
	write(SongPluginSession.TRUST_PATH, broken)
	var report := session.prepare(folder, raw, "recovery")
	check(report.errors.is_empty() and report.requires_trust and not report.notices.is_empty(), "corrupt trust is unknown and visibly reported")
	check(not session.open().errors.is_empty() and FileAccess.get_file_as_string(SongPluginSession.TRUST_PATH) == broken, "reading corrupt trust never overwrites or allows scripts")
	var hash := FileAccess.get_sha256(SongPluginSession.TRUST_PATH).substr(0, 16)
	check(session.remember_trust(false), "explicit denial recovers corrupt trust safely")
	check(FileAccess.get_file_as_string(SongPluginSession.TRUST_PATH + ".corrupt." + hash + ".bak") == broken, "corrupt trust backup exact")
	check(session.open().errors.is_empty() and not session.runtime_notices().is_empty(), "recovered denial opens independent declarative parts with notice")
	session.close()
	# Self-describing default omission metadata works through the actual session.
	var lean := raw_chart([requirement("visual")]); lean.notes[0].ring = 0.0
	var schemas := PluginRegistry.standard().field_schema(); schemas.append_array(data.fields)
	var chart_path := folder.path_join("chart.json")
	check(ChartCodec.save_file(chart_path, lean, schemas).ok, "plugin lean chart written")
	var saved: Dictionary = SU.load_json(chart_path)
	check(not saved.notes[0].has("kind") and not saved.notes[0].has("ring"), "saved lean chart omits declared defaults")
	report = session.prepare(folder, saved, "lean")
	check(report.errors.is_empty() and session.open().errors.is_empty(), "lean chart resolves actual session defaults")
	var core := GameCore.new(session.registry)
	check(core.load_chart(session.chart_data) and core.notes.size() == 1 and core.notes[0].ring == 0.0, "real game loads lean defaults without losing notes")
	core = null; session.close()
	# Snapshot cleanup never follows a link created by a trusted plugin.
	var snapshot := PluginPack.snapshot(folder, PluginPack.content_hash(folder).hash)
	check(snapshot.errors.is_empty(), "snapshot preserves verified pack bytes")
	if snapshot.errors.is_empty():
		var external := root_folder.path_join("keep_outside_snapshot")
		write(external.path_join("sentinel.txt"), "keep")
		var dir := DirAccess.open(snapshot.path)
		check(dir.create_link(ProjectSettings.globalize_path(external), "external_link") == OK, "trusted snapshot symlink fixture created")
		PluginPack.remove_snapshot(snapshot.path)
		check(FileAccess.get_file_as_string(external.path_join("sentinel.txt")) == "keep" and not DirAccess.dir_exists_absolute(snapshot.path), "snapshot cleanup unlinks without following symlinks")
	var outside := root_folder.path_join("outside_ancestor")
	write(outside.path_join("pid/sentinel.txt"), "keep ancestor")
	var storage := DirAccess.open("user://plugin_sessions")
	check(storage.create_link(ProjectSettings.globalize_path(outside), "ancestor_link") == OK, "snapshot ancestor link fixture created")
	PluginPack.remove_snapshot("user://plugin_sessions/ancestor_link/pid")
	check(FileAccess.get_file_as_string(outside.path_join("pid/sentinel.txt")) == "keep ancestor", "snapshot cleanup refuses symlinked ancestor")
	DirAccess.remove_absolute("user://plugin_sessions/ancestor_link")
	check(storage.create_link(ProjectSettings.globalize_path(outside), "direct_link") == OK, "snapshot final-component link fixture created")
	PluginPack.remove_snapshot("user://plugin_sessions/direct_link")
	check(not storage.is_link("direct_link") and FileAccess.get_file_as_string(outside.path_join("pid/sentinel.txt")) == "keep ancestor", "snapshot cleanup unlinks final-component link only")
	# A registry-transaction failure also executes cooperative teardown and
	# removes the snapshot, without changing the standard scope.
	var failure := manifest("failed", "script"); failure.provides = {"rules": ["never_registered"]}
	var source := '@static_unload\nextends RefCounted\nstatic func install(registry, _manifest, _folder):\n\tregistry.own(Node.new())\nstatic func teardown(_registry):\n\tvar f = FileAccess.open("user://p2_failed_teardown", FileAccess.WRITE)\n\tf.store_string("done")\n'
	plugin(folder, failure, source)
	var bad := raw_chart([requirement("failed")])
	check(session.prepare(folder, bad, "failed").requires_trust and session.remember_trust(true), "failed transaction fixture explicitly trusted")
	check(not session.open().errors.is_empty() and session.registry == null and session._snapshot_root.is_empty(), "failed install clears scope and snapshot")
	check(FileAccess.get_file_as_string("user://p2_failed_teardown") == "done", "failed install runs teardown")
	session.close()

func test_malformed_values() -> void:
	var session := SongPluginSession.new()
	for value in [null, {}, [], "bad", true]:
		var raw := raw_chart(); raw.defaults_schema = value
		check(not session.prepare("/unused", raw, "invalid").errors.is_empty(), "invalid codec marker rejected without engine error")
		check(ChartCodec.expand(raw, []) == raw, "codec preserves unknown marker value")
		var data := manifest("invalid"); data.tier = value
		check(not PluginLoader.validate_manifest(data).errors.is_empty(), "invalid tier rejected without engine error")
	var raw := raw_chart(); raw.defaults_schema = 1
	check(not session.prepare("/unused", raw, "invalid").errors.is_empty(), "lean chart without omission metadata rejected clearly")
	check(not PluginPack.snapshot("user://", "unused").errors.is_empty(), "snapshot storage cannot be nested inside original pack")
	for value in [[], {}, 2, true]:
		write(SongPluginSession.TRUST_PATH, JSON.stringify({"schema": value, "decisions": {}}))
		check(not session._read_trust().errors.is_empty(), "malformed trust schema handled as unknown")
	DirAccess.remove_absolute(SongPluginSession.TRUST_PATH)
