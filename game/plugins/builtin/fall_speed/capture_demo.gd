## Silent Xvfb visual evidence for integrated fall speed. No audio is opened.
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
	var session := SongPluginSession.new()
	var folder := "res://../songs/_plugin_demos/speed"
	var raw: Dictionary=SU.load_json(folder+("/combined.chart.json" if options.get("variant","")=="combined" else "/chart.json"))
	if str(options.get("variant","")).begins_with("neutral"):
		raw.sv=[]; raw.track_speeds=[{"id":0,"speed":1},{"id":1,"speed":1}]
		if options.get("variant","")=="neutral_standard": raw.plugins=[]
	var report := session.prepare(folder,raw,"speed-demo")
	if not report.errors.is_empty(): printerr(report.errors); quit(1); return
	var loaded := session.open()
	if not loaded.errors.is_empty(): printerr(loaded.errors); quit(1); return
	var scope := session.registry
	var core := GameCore.new(scope)
	if not core.load_chart(session.chart_data):
		printerr("Cannot load speed demo"); quit(1); return
	var renderer := Renderer.new(scope); root.add_child(renderer)
	renderer._rng.seed=20261017; renderer.hint_mode="off"; renderer.curve=str(options.get("curve","deemo"))
	core.stage.mode="off"; core.playing=true
	var t := float(options.get("time","2.5")); var fall := float(options.get("fall","1.5"))
	core.skip_before(t)
	var lights := core.light_states(t,1.0); var by_id := {}
	for light in lights: by_id[light.id]=light
	var fd := {"t":t,"fxT":t,"perf":0.0,"dt":1.0/60,"lights":lights,"light_by_id":by_id,"notes":core.notes,"cues":core.cues,
		"fall":fall,"reach":1.0,"tl":core.tl,"chart":core.chart,"phase":0.0,"stats":core.stats,"play":true,"space_down":false,
		"hit_log":[],"chords":core.chords,"meta":{"title":"TWO SPEEDS, ONE PULSE","artist":"L’âge tendre","version":"FALL SPEED + SV","dir":"_plugin_demos/speed","level":1},
		"progress":t/core.end_time,"countdown":0.0,"ending":{}}
	renderer.frame(fd,core.stage)
	for _i in 3: await RenderingServer.frame_post_draw
	var output: String=options.get("out","")
	if output.is_empty() or root.get_texture().get_image().save_png(output)!=OK:
		printerr("Cannot write screenshot"); renderer.free(); quit(1); return
	print("SPEED CAPTURE 1600x900 t=",t," fall=",fall," curve=",renderer.curve," -> ",output)
	renderer.free(); session.close(); quit(0)
