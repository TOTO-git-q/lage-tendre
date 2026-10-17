## API 1 contract tests. All generated fixtures stay in user:// under an isolated test HOME.
extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func manifest(id: String) -> Dictionary:
	return {"id": id, "version": "1.0.0", "api": 1, "tier": "declarative", "title": id,
		"author": "Test", "description": "Local API fixture", "provides": {}, "fields": [], "assets": [], "entry": null}

func write_fixture(id: String, value: Dictionary, script := "") -> String:
	var folder := "user://p1_plugins/" + id
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder + "/plugin.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
	if not script.is_empty():
		file = FileAccess.open(folder + "/entry.gd", FileAccess.WRITE)
		file.store_string(script); file.close()
	return folder + "/plugin.json"

func _init() -> void:
	KB.set_layout("ansi")
	var base := PluginRegistry.standard()
	check(base.errors.is_empty() and base.manifests.size() == 4, "all four standard built-ins load through manifests")
	var counts := {"events": 7, "note_kinds": 2, "flags": 3, "rules": 19, "motions": 1, "track_geometry": 1, "channels": 13, "elements": 14, "validators": 1}
	for category in counts: check(base.records[category].size() == counts[category], "catalog " + category)
	for category in ["events", "rules", "motions", "track_geometry", "channels", "elements", "validators"]:
		for provider in base.ordered(category): check(base.manifests.has(provider.plugin), "provider ownership " + provider.id)
	check(base.field_schema().size() == 36, "complete original field catalog")
	check(is_same(base.get_entry("events", "on"), base.records.events.on), "lookup returns original provider identity")
	var missing_category := base.get_entry("absent_category", "absent")
	missing_category["probe"] = true
	check(base.get_entry("absent_category", "absent").is_empty(), "missing category returns a fresh empty dictionary")
	var missing_provider := base.get_entry("events", "absent")
	missing_provider["probe"] = true
	check(base.get_entry("events", "absent").is_empty(), "missing provider returns a fresh empty dictionary")
	var fields := base.field_schema(); fields[0].doc = "mutated copy"
	check(base.field_schema()[0].doc != "mutated copy", "field schema defensive copy")
	for id in base.manifests:
		check(PluginLoader.validate_manifest(base.manifests[id]).errors.is_empty(), "builtin manifest " + id)
	for value in [null, [], "text", 1, {}, {"id": "x"}]:
		check(not PluginLoader.validate_manifest(value).errors.is_empty(), "reject malformed manifest " + str(value))
	for key in ["api", "version", "provides", "fields", "assets", "entry", "requires"]:
		var invalid := manifest("invalid")
		invalid[key] = {"api": 2, "version": "1.0", "provides": [], "fields": {}, "assets": ["../bad.png"], "entry": "entry.gd", "requires": [null]}[key]
		check(not PluginLoader.validate_manifest(invalid).errors.is_empty(), "reject invalid " + key)
	for path in ["../bad.png", "/tmp/bad.png", "a/../b.png", "res://x.png", "a\\b.png", ""]:
		check(not PluginLoader.safe_relative(path), "reject unsafe path " + path)
	check(PluginLoader.safe_relative("textures/ring.png"), "accept nested asset path")
	for field in [
		{"path": "notes[].x", "type": "number", "unit": "keys", "default": 1, "doc": "x"},
		{"path": "notes[].x", "type": "number", "unit": "keys", "default": 2, "min": 0, "max": 1, "step": 0.1, "doc": "x"},
		{"path": "notes[].x", "type": "enum", "unit": "kind", "default": "b", "enum": ["a"], "doc": "x"},
		{"path": "notes[].x", "type": "boolean", "unit": "flag", "default": 1, "doc": "x"}]:
		var invalid := manifest("invalid"); invalid.fields = [field]
		check(not PluginLoader.validate_manifest(invalid).errors.is_empty(), "reject malformed field")
	for row in [["1.2.3", "1.2.3", true], ["1.2.3", "^1.0.0", true], ["2.0.0", "^1.0.0", false], ["1.0.0", "^1.2.0", false], ["0.2.5", "^0.2.0", true], ["0.3.0", "^0.2.0", false], ["0.0.2", "^0.0.1", false], ["1.2.3", "*", true], ["01.2.3", "*", false]]:
		check(PluginLoader.version_matches(row[0], row[1]) == row[2], "version " + str(row))
	var a := manifest("a"); var b := manifest("b"); var c := manifest("c")
	b.requires = [{"id": "a", "version": "^1.0.0"}]; c.requires = [{"id": "b", "version": "1.0.0"}]
	var sorted := PluginLoader.dependency_order([c, b, a])
	check(sorted.errors.is_empty() and sorted.ordered.map(func(item): return item.id) == ["a", "b", "c"], "stable topological order")
	check(not PluginLoader.dependency_order([b]).errors.is_empty(), "missing dependency")
	check(not PluginLoader.dependency_order([a, a]).errors.is_empty(), "duplicate plugin")
	check(PluginLoader.dependency_order([b], {"a": a}).errors.is_empty(), "installed dependency")
	a.requires = [{"id": "c", "version": "*"}]
	check(not PluginLoader.dependency_order([a, b, c]).errors.is_empty(), "dependency cycle")
	a.erase("requires"); a.version = "2.0.0"
	check(not PluginLoader.dependency_order([a, b]).errors.is_empty(), "dependency version mismatch")
	var scope := base.fork_scope()
	scope.begin_plugin(manifest("test_providers"))
	check(not scope.register("missing", "bad", {}), "reject unknown category")
	check(not scope.register("flags", "ex", {}), "reject unrequested duplicate")
	scope.errors.clear()
	var trace := []
	scope.register("rules", "test_b", {"phase": "test", "order": 20, "callback": func(_context): trace.append("b")})
	scope.register("rules", "test_a", {"phase": "test", "order": 10, "callback": func(_context): trace.append("a")})
	scope.register("rules", "test_c", {"phase": "test", "order": 30, "callback": func(context): trace.append("c"); context.stop = true})
	scope.register("rules", "test_d", {"phase": "test", "order": 40, "callback": func(_context): trace.append("d")})
	RulePipeline.new(scope).run("test", {})
	check(trace == ["a", "b", "c"], "ordered rule pipeline and stop")
	trace.clear()
	scope.register("elements", "test_draw_b", {"phase": "test", "order": 20, "callback": func(_renderer, _canvas): trace.append("b")})
	scope.register("elements", "test_draw_a", {"phase": "test", "order": 10, "callback": func(_renderer, _canvas): trace.append("a")})
	var canvas := Node2D.new()
	RenderPipeline.new(scope).draw("test", canvas, canvas)
	check(trace == ["a", "b"], "ordered render pipeline")
	canvas.free()
	check(base.get_entry("rules", "test_a").is_empty(), "scope registration isolation")
	var custom_event := base.get_entry("events", "on").duplicate()
	custom_event.validate = special_validate; custom_event.compile = special_compile; custom_event.sample = special_sample
	scope.register("events", "special_on", custom_event)
	scope.register("note_kinds", "special_tap", {"holds": false, "render": special_draw})
	scope.register("flags", "special_flag", {"normalize": func(raw, note): note.special_flag = raw.get("special_flag", 0)})
	scope.register("validators", "special_validator", {"order": 10, "callback": func(context): context.chart.custom_validated = true})
	var raw := {"bpm": 120, "lights": [{"t": 0, "id": 0, "type": "special_on", "x": 0.5, "w": 0.5, "auto": true}], "notes": [{"t": 2, "light": 0, "u": 0.5, "kind": "special_tap", "special_flag": 7}]}
	var chart := ChartLib.validate(raw, scope)
	check(chart.warnings.is_empty() and chart.notes.size() == 1 and chart.custom_validated, "event/note-kind/validator dispatch")
	check(chart.notes[0].special_flag == 7, "flag normalization retained")
	var timelines := ChartLib.build_timelines(chart.lights, scope)
	check(ChartLib.light_at(timelines[0], 2.0, scope).x == 0.5, "custom event compilation and sampling")
	var core := GameCore.new(scope)
	check(core.load_chart(raw), "custom chart loads through scoped GameCore")
	check(core.notes[0].special_flag == 7, "extension fields survive session setup")
	core.playing = true; core.press_key("KeyH", 2.0)
	check(core.stats.PERFECT == 1 and core.stats.MISS == 0, "custom tap uses standard judgement")
	core = null
	var renderer := Renderer.new(scope)
	renderer.f = {"play": true, "t": 1.5, "fall": 1.5, "reach": 1.0, "chords": [], "notes": [{"t": 2.0, "dur": 0.0, "kind": "special_tap", "light": 0, "state": "pending"}],
		"light_by_id": {0: {"alive": true, "x": 0.5, "w": 0.5, "alpha": 1.0}}, "tl": timelines}
	renderer._plan_notes()
	check(renderer.last_combo == 17, "custom note kind executes its render callback")
	renderer.free()
	scope.register("motions", "follow_track", {"callback": func(_renderer, _note, state): var moved = state.duplicate(); moved.x = 0.25; return moved}, true)
	renderer = Renderer.new(scope)
	check(renderer._land_st({}, {"x": 0.5}).x == 0.25, "registered motion callback controls visual state")
	renderer.free()
	# A geometry provider actually controls hit resolution, not just metadata.
	scope.register("track_geometry", "lane", {"sections": func(_state): return []}, true)
	core = GameCore.new(scope); core.load_chart(raw); core.playing = true
	check(core.press_key("KeyH", 2.0) == null and core.stats.judged == 0, "registered geometry controls cross-section hits")
	core = null
	var stage := StageFx.new(scope)
	scope.register("channels", "custom_channel", {"default": 0.25, "min": 0.0, "max": 1.0})
	stage = StageFx.new(scope); stage.build(chart)
	check(stage.at(2.0).custom_channel == 0.25, "registered stage channel evaluated")
	stage = null
	scope.register("events", "fx.custom", {"target": "fx", "compile": func(runtime, event): runtime.rings.append(event.t)})
	stage = StageFx.new(scope)
	var fx_chart := chart.duplicate(true); fx_chart.fx = [{"t": 1.25, "type": "custom"}]
	stage.build(fx_chart)
	check(stage.rings == [1.25], "custom stage event uses registry compilation")
	stage = null
	scope.end_plugin()
	var loader := PluginLoader.new()
	var scripted := manifest("fixture_script"); scripted.tier = "script"; scripted.entry = "entry.gd"; scripted.provides = {"rules": ["fixture_tick"]}
	var source := "extends RefCounted\nstatic func install(registry, _manifest, _folder):\n\tvar file = FileAccess.open(\"user://p1_script_executed\", FileAccess.WRITE)\n\tfile.store_string(\"yes\")\n\tregistry.register(\"rules\", \"fixture_tick\", {\"phase\": \"fixture\", \"callback\": tick})\nstatic func tick(context):\n\tcontext.value += 1\n"
	var script_path := write_fixture("fixture_script", scripted, source)
	if FileAccess.file_exists("user://p1_script_executed"): DirAccess.remove_absolute("user://p1_script_executed")
	var isolated := base.fork_scope()
	var denied := loader.load_paths([script_path], isolated, false)
	check(denied.errors.is_empty() and denied.disabled.size() == 1 and denied.loaded.is_empty(), "untrusted script explicitly disabled")
	check(not FileAccess.file_exists("user://p1_script_executed") and not isolated.manifests.has("fixture_script"), "untrusted script never loaded or installed")
	var accepted := loader.load_paths([script_path], isolated, true)
	check(accepted.errors.is_empty() and accepted.loaded == ["fixture_script"] and FileAccess.file_exists("user://p1_script_executed"), "trusted same-manifest script installed")
	var value := {"value": 0}; RulePipeline.new(isolated).run("fixture", value)
	check(value.value == 1, "loaded script's real rule executes")
	var missing := manifest("missing_script"); missing.tier = "script"; missing.entry = "entry.gd"
	var missing_path := write_fixture("missing_script", missing)
	var before := isolated.manifests.duplicate(true)
	var failed := loader.load_paths([missing_path], isolated, true)
	check(not failed.errors.is_empty() and isolated.manifests == before, "failed load is registry-atomic")
	var declared := manifest("declared"); declared.provides = {"flags": ["declarative_flag"]}
	declared.fields = [{"path": "notes[].declarative_flag", "type": "boolean", "unit": "flag", "default": false, "doc": "Test flag"}]
	declared.definitions = {"flags": {"declarative_flag": {"field": "declarative_flag"}}}
	var declared_path := write_fixture("declared", declared)
	check(loader.load_paths([declared_path], isolated, false).errors.is_empty() and isolated.get_entry("flags", "declarative_flag").declarative, "declarative catalog loads without script trust")
	isolated.dispose()
	check(isolated.manifests.is_empty() and base.manifests.size() == 4, "scope disposal leaves built-ins intact")
	isolated = null; scope.dispose(); scope = null
	print("PLUGIN REGISTRY: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

static func special_validate(context: Dictionary) -> void:
	var standard := context.duplicate()
	standard.type = "on"
	BuiltinChartRuntime.validate_light(standard)
	if not context.chart.lights.is_empty(): context.chart.lights[-1].type = "special_on"

static func special_compile(context: Dictionary) -> void:
	var event: Dictionary = context.event.duplicate(); event.type = "on"
	context.event = event
	BuiltinChartRuntime.compile_light(context)
	context.segments[-1].type = "special_on"

static func special_sample(segment: Dictionary, t: float) -> Dictionary:
	var standard := segment.duplicate(); standard.type = "on"
	return BuiltinChartRuntime.sample_light(standard, t)

static func special_draw(renderer, _note, _state, _t, _fall, _p_min, _p_quick, _p_end) -> void:
	renderer.last_combo = 17
