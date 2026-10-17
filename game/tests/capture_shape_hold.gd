## Independent silent screenshots: actual GameCore and actual hold planner.
## Run as an external absolute -s; no changes to the frozen implementation.
extends SceneTree
var options:={}
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.trim_prefix("--").split("=",true,1)
		if pair.size()==2: options[pair[0]]=pair[1]
	capture.call_deferred()
func rect(x0: float,x1: float,t0: float,t1: float) -> Dictionary:
	return {"nodes":[[x0,t0],[x1,t0],[x1,t1],[x0,t1]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
func capture() -> void:
	if DisplayServer.get_name()=="headless" or AudioServer.get_driver_name()!="Dummy":
		printerr("Requires Xvfb and --audio-driver Dummy");quit(2);return
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);KB.set_layout("ansi")
	var variant:=str(options.get("variant","hole"));var shape: Dictionary
	if variant=="hole":
		shape=rect(.1,.9,1,5);shape["holes"]=[rect(.4,.6,1.1,4.9)]
	elif variant=="changing":
		shape={"nodes":[[.1,1],[.4,1],[.7,5],[.4,5]],"segs":[["linear"],["linear"],["linear"],["linear"]]}
	else:printerr("Expected --variant=hole|changing");quit(2);return
	shape["props"]=[{"t":1.,"a":.8,"tint":4}]
	var raw:={"bpm":120,"plugins":[{"id":"shape_tracks","version":"1.0.0"}],"lights":[],"tracks":[{"id":0,"geometry":"shape","shapes":[shape]}],"notes":[{"t":2.,"light":0,"kind":"hold","dur":2.,"u":.5}]}
	var scope:=PluginRegistry.standard().fork_scope()
	var loaded:=PluginLoader.new().load_paths(["res://plugins/builtin/shape_tracks/plugin.json"],scope,true)
	if not loaded.errors.is_empty():printerr(loaded.errors);quit(2);return
	var core:=GameCore.new(scope)
	if not core.load_chart(raw) or core.notes.size()!=1 or not core.chart.warnings.is_empty():printerr("Required hold fixture failed");quit(2);return
	core.stage.mode="off";core.playing=true;core.autoplay=true
	var t:=float(options.get("time","2.8"));var fall:=1.5
	for i in int(ceil(t*240.))+1:core.update(minf(i/240.,t))
	if core.notes[0].state!="holding":printerr("Actual autoplay did not hold note");quit(2);return
	var renderer:=Renderer.new(scope);root.add_child(renderer)
	renderer._rng.seed=20261017;renderer.hint_mode="off";renderer.curve="deemo"
	var lights:=core.light_states(t,1.);var by:={}
	for light in lights:by[light.id]=light
	var frame:={"t":t,"fxT":t,"perf":0.,"dt":0.,"lights":lights,"light_by_id":by,"notes":core.notes,"cues":core.cues,"fall":fall,"reach":1.,"tl":core.tl,"chart":core.chart,"phase":0.,"stats":core.stats,"play":true,"space_down":false,"hit_log":[],"chords":core.chords,"meta":{"title":"SHAPE HOLD: "+variant.to_upper(),"artist":"L’âge tendre","version":"DEEMO / 1.5 S","dir":"shape-hold-review","level":1},"progress":t/core.end_time,"countdown":0.,"ending":{}}
	renderer.frame(frame,core.stage)
	if renderer._runtime._nd_holds.is_empty():printerr("Actual planner emitted no hold body");renderer.free();quit(2);return
	for _i in 4:await RenderingServer.frame_post_draw
	var out:=str(options.get("out",""))
	if out.is_empty() or root.get_texture().get_image().save_png(out)!=OK:printerr("Cannot write screenshot");renderer.free();quit(2);return
	print("SHAPE HOLD ACTUAL CAPTURE variant=",variant," t=",t," curve=deemo fall=1.5 caps=",renderer._runtime._nd_notes.size()," bodies=",renderer._runtime._nd_holds.size()," autoplay_state=",core.notes[0].state," -> ",out)
	renderer.free();scope.dispose();quit(0)
