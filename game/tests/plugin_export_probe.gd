## Verify actual exported packs contain the same manifest-driven builtin catalog.
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ProjectSettings.load_resource_pack(args[0]):
		print("EXPORT PROBE: pack load failed"); quit(1); return
	var expected := ["standard_chart", "standard_rules", "standard_stage", "standard_render"]
	for id in args.slice(1):
		if id in expected:
			print("EXPORT PROBE: duplicate expected manifest ", id); quit(1); return
		expected.append(id)
	var missing := []
	for id in expected:
		var folder: String = "res://plugins/builtin/" + str(id)
		if not FileAccess.file_exists(folder + "/plugin.json"): missing.append(id + ": manifest")
		print("PACK ", id, " script FileAccess=", FileAccess.file_exists(folder + "/entry.gd"), " ResourceLoader=", ResourceLoader.exists(folder + "/entry.gd"))
	if not missing.is_empty():
		print("EXPORT PROBE: missing ", missing); quit(1); return
	KB.set_layout("ansi")
	var registry := PluginRegistry.standard()
	if registry.manifests.size() != 4 or not registry.errors.is_empty():
		print("EXPORT PROBE: incomplete standard registry"); quit(1); return
	var catalog := PluginRegistry.builtins()
	if catalog.manifests.size() != expected.size() or not catalog.errors.is_empty():
		print("EXPORT PROBE: incomplete optional catalog ", catalog.errors); quit(1); return
	for id in expected:
		if not catalog.manifests.has(id):
			print("EXPORT PROBE: missing optional catalog entry ", id); quit(1); return
	var core := GameCore.new()
	if not core.load_chart(ChartLib.demo()):
		print("EXPORT PROBE: demo load failed"); quit(1); return
	print("EXPORT PROBE: 4 manifests, ", registry.ordered("rules").size(), " rules, ", registry.ordered("elements").size(), " elements, demo total=", core.stats.total)
	print("EXPORT CATALOG: ", catalog.manifests.size(), " manifests; default core remains standard-only: ", core.registry.manifests.size() == 4)
	if core.registry.manifests.size() != 4:
		print("EXPORT PROBE: optional plugins leaked into the default core"); quit(1); return
	core = null
	quit()
