## Silent Xvfb visual evidence for the shape plugin. No audio is opened.
extends SceneTree
var options := {}
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=",true,1)
		if pair.size()==2: options[pair[0]]=pair[1]
	capture.call_deferred()

func capture() -> void:
	if DisplayServer.get_name()=="headless": printerr("Xvfb is required for pixels"); quit(1); return
	root.size=Vector2i(1600,900); root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	KB.set_layout("ansi")
	var scope := PluginRegistry.new()
	var paths := []
	for id in ["standard_chart","standard_stage","standard_rules","standard_render","shape_tracks"]:
		paths.append("res://plugins/builtin/"+id+"/plugin.json")
	var loaded := PluginLoader.new().load_paths(paths,scope,true)
	if not loaded.errors.is_empty(): printerr(loaded.errors); quit(1); return
	var core := GameCore.new(scope)
	if not core.load_chart(SU.load_json("res://../songs/_plugin_demos/shapes/chart.json")):
		printerr("Cannot load shape demo"); quit(1); return
	var renderer := Renderer.new(scope); root.add_child(renderer)
	renderer._rng.seed=20261017; renderer.hint_mode="off"; renderer.curve=str(options.get("curve","linear"))
	core.stage.mode="off"; core.playing=true
	var t := float(options.get("time","1.9")); var fall := float(options.get("fall","4.5"))
	core.skip_before(t)
	var lights := core.light_states(t,1.0); var by_id := {}
	for light in lights: by_id[light.id]=light
	var fd := {"t":t,"fxT":t,"perf":0.0,"dt":1.0/60,"lights":lights,"light_by_id":by_id,"notes":core.notes,"cues":core.cues,
		"fall":fall,"reach":1.0,"tl":core.tl,"chart":core.chart,"phase":0.0,"stats":core.stats,"play":true,"space_down":false,
		"hit_log":[],"chords":core.chords,"meta":{"title":"SHAPE TRACKS","artist":"L’âge tendre","version":"STAR + HEART","dir":"_plugin_demos/shapes","level":1},
		"progress":t/core.end_time,"countdown":0.0,"ending":{}}
	renderer.frame(fd,core.stage)
	for _i in 3: await RenderingServer.frame_post_draw
	var output: String=options.get("out","")
	if output.is_empty() or root.get_texture().get_image().save_png(output)!=OK:
		printerr("Cannot write screenshot"); renderer.free(); quit(1); return
	print("SHAPE CAPTURE 1600x900 t=",t," fall=",fall," curve=",renderer.curve," -> ",output)
	renderer.free(); quit(0)
