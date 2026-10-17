## P2 visual isolation: render a real script-plugin song A, unload it, then use the
## unchanged P0 driver for song B. Compare to a separate clean B process.
extends "res://tests/capture_render.gd"

func _warm_fonts() -> void:
	# System-font atlas placement otherwise depends on A's title glyphs and can
	# produce one-channel rounding noise in B. Both processes warm the same atlas.
	var warm := Node2D.new()
	warm.draw.connect(func():
		var glyphs := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~·’"
		for style in [[Fonts.ui(), 1, 26], [Fonts.ui(), 2, 16], [Fonts.hud(), 2, 44], [Fonts.hud(), 2, 17], [Fonts.hud(), 0, 150], [Fonts.hud(), 3, 58], [Fonts.hud(), 8, 12], [Fonts.hud(), 4, 11], [Fonts.hud(), 5, 11]]:
			warm.draw_string(Fonts.spaced(style[0], style[1]), Vector2(0, 200), glyphs, HORIZONTAL_ALIGNMENT_LEFT, -1, style[2], Color.WHITE))
	root.add_child(warm)
	await RenderingServer.frame_post_draw
	warm.free()

func _run() -> void:
	if DisplayServer.get_name() != "headless": await _warm_fonts()
	if args.get("warm-plugin", "0") == "1":
		if DisplayServer.get_name() == "headless":
			push_error("A real renderer is required for lifecycle pixels"); quit(1); return
		root.size = Vector2i(1600, 900)
		root.content_scale_size = Vector2i(1920, 1080)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		KB.set_layout("ansi")
		var folder := "user://p2_visual_pack"
		DirAccess.make_dir_recursive_absolute(folder.path_join("plugins/visual_fixture"))
		var manifest := {"id": "visual_fixture", "version": "1.0.0", "api": 1, "tier": "script", "title": "Visual isolation fixture", "author": "Local tests", "description": "Distinct temporary draw layer", "provides": {"elements": ["temporary_overlay"]}, "fields": [], "assets": [], "entry": "entry.gd"}
		SU.save_json(folder.path_join("plugins/visual_fixture/plugin.json"), manifest)
		var source := FileAccess.open(folder.path_join("plugins/visual_fixture/entry.gd"), FileAccess.WRITE)
		source.store_string("extends RefCounted\nstatic func install(registry, _manifest, _folder):\n\tregistry.register(\"elements\", \"temporary_overlay\", {\"phase\": \"temporary_overlay\", \"order\": 120, \"callback\": paint})\nstatic func paint(_renderer, canvas):\n\tcanvas.draw_rect(Rect2(0, 0, 300, 150), Color(1, 0, 1, 1))\n")
		source.close()
		var raw := ChartLib.demo(); raw.plugins = [{"id": "visual_fixture", "version": "1.0.0"}]
		SU.save_json(folder.path_join("chart.json"), raw)
		var session := SongPluginSession.new()
		var prepared := session.prepare(ProjectSettings.globalize_path(folder), raw, "visual_fixture_a")
		if not prepared.errors.is_empty() or not session.remember_trust(true):
			push_error("Cannot prepare lifecycle fixture: " + str(prepared)); quit(1); return
		var opened := session.open()
		if not opened.errors.is_empty(): push_error(str(opened)); quit(1); return
		core = GameCore.new(session.registry); core.load_chart(session.chart_data)
		core.autoplay = true; core.playing = true
		renderer = Renderer.new(session.registry); root.add_child(renderer)
		renderer._rng.seed = SEED; renderer.note_scale = 1.5; renderer.hint_mode = "off"
		meta = {"title": "A", "artist": "Fixture", "version": "TEST", "dir": "A", "level": 1}
		for index in range(31):
			_frame(float(index) / FPS, float(index) / FPS)
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var pixel := image.get_pixel(80, 60)
		if pixel.r < 0.99 or pixel.b < 0.99 or pixel.g > 0.01:
			push_error("Plugin A's actual draw provider did not appear: " + str(pixel)); quit(1); return
		if args.has("a-out"): image.save_png(str(args["a-out"]))
		var old_renderer: WeakRef = weakref(renderer)
		renderer.free(); renderer = null; core = null
		session.close(); session = null
		await process_frame
		if old_renderer.get_ref() != null or not PluginRegistry.builtins().get_entry("elements", "temporary_overlay").is_empty():
			push_error("Plugin A leaked into the next session"); quit(1); return
		meta.clear()
		print("LIFECYCLE A: actual magenta layer drawn, renderer released, base catalog unchanged")
	await super._run()
