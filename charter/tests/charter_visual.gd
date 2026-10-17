extends SceneTree
const Vocab=preload("res://vocabulary.gd")
var core=GameCore.new()
var view: SubViewport
var renderer: Node2D
func _init() -> void: run.call_deferred()
func frame() -> Dictionary:
	var t=55.4; var lights=core.light_states(t,1.0); var by={}
	for l in lights: by[l.id]=l
	return {"t":t,"fxT":t,"perf":t,"dt":0,"lights":lights,"light_by_id":by,"notes":core.notes,"cues":core.cues,"fall":2.3,"reach":1.0,"tl":core.tl,"chart":core.chart,"phase":core.chart.timing[0].t,"stats":core.stats,"play":true,"space_down":false,"hit_log":[],"chords":core.chords,"meta":{},"progress":0.5,"countdown":0,"ending":{}}
func render_image(r: Node2D, stage: StageFx) -> Image:
	r.frame(frame(),stage)
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	AudioServer.set_bus_mute(0,true); KB.set_layout("ansi")
	core.load_chart(SU.load_json(ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json").simplify_path()))
	view=SubViewport.new(); view.size=Vector2i(480,270); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var original: Image
	var historical="res://evidence/renderer.before.txt"
	if FileAccess.file_exists(historical):
		var source=FileAccess.get_file_as_string(historical).replace("class_name Renderer","# baseline renderer")
		var script=GDScript.new(); script.source_code=source
		if script.reload()!=OK: quit(1); return
		var baseline=Node2D.new(); baseline.set_script(script); baseline.scale=Vector2.ONE*0.25; view.add_child(baseline)
		original=await render_image(baseline,core.stage)
		original.save_png("res://evidence/default_before.png")
		view.remove_child(baseline); baseline.queue_free()
	else:
		# Historical comparison was diagnostic only; still run every current assertion.
		print("HISTORICAL_RENDERER_BASELINE_SKIPPED: missing renderer.before.txt")
	renderer=Renderer.new(); renderer.scale=Vector2.ONE*0.25; view.add_child(renderer)
	var current=await render_image(renderer,core.stage)
	current.save_png("res://evidence/default_after.png")
	if original!=null:
		var baseline_identical=original.get_data()==current.get_data()
		print("BASELINE_FILE_PIXEL_IDENTICAL=",baseline_identical," (renderer.before.txt predates later game-side renderer edits)")
	var explicit_chart=core.chart.duplicate(true)
	explicit_chart.fx=[{"t":0,"type":"tween","ch":"zoom","to":1.0,"dur":0.01},{"t":0,"type":"tween","ch":"line_y","to":0.0,"dur":0.01},{"t":0,"type":"tween","ch":"line_tilt","to":0.0,"dur":0.01},{"t":0,"type":"tween","ch":"line_glow","to":1.0,"dur":0.01}]
	var explicit_stage=StageFx.new(); explicit_stage.build(explicit_chart)
	var no_events_chart=core.chart.duplicate(true); no_events_chart.fx=[{"t":0,"type":"tween","ch":"zoom","to":1.0,"dur":0.01}]
	var plain_stage=StageFx.new(); plain_stage.build(no_events_chart)
	var plain=await render_image(renderer,plain_stage)
	var explicit=await render_image(renderer,explicit_stage)
	var identical=plain.get_data()==explicit.get_data()
	print("DEFAULT_PIXEL_IDENTICAL=",identical," (line channels at their defaults change nothing)")
	var test_chart=core.chart.duplicate(true)
	test_chart.fx=[{"t":0,"type":"tween","ch":"roll","to":3,"dur":0.01},{"t":0,"type":"tween","ch":"line_tilt","to":1,"dur":0.01},{"t":0,"type":"tween","ch":"line_y","to":0.04,"dur":0.01}]
	var test_stage=StageFx.new(); test_stage.build(test_chart)
	var fd=frame(); fd.chart=fd.chart.duplicate(true); fd.chart.meta["line_follow_roll"]=true
	renderer.frame(fd,test_stage)
	var follow_ok=absf(rad_to_deg(renderer.L.track.rotation)-2)<0.00001 and absf(renderer.G.jy-SU.JUDGE_Y-0.04*SU.LH)<0.00001
	for name in ["track","beam","holds","note","fx"]: follow_ok=follow_ok and renderer.L[name].transform.is_equal_approx(renderer.L.track.transform)
	print("LINE_FOLLOW_CLAMP_SHARED_GEOMETRY=",follow_ok)
	identical=identical and follow_ok
	var vocab=Vocab.data(); var sheet=Image.create(480*7,300*vocab.size(),false,Image.FORMAT_RGBA8); sheet.fill(Color("151515"))
	var row=0
	var font=SystemFont.new(); font.font_names=PackedStringArray(["Segoe UI","Microsoft YaHei UI"])
	var label=Label.new(); label.add_theme_font_override("font",font); label.add_theme_color_override("font_color",Color.WHITE); label.add_theme_font_size_override("font_size",19); view.add_child(label)
	for ch in vocab:
		var col=0
		for level in vocab[ch].levels:
			var stage=StageFx.new(); var chart=core.chart.duplicate(true)
			chart.fx=[{"t":0,"type":"tween","ch":ch,"to":level.value,"dur":0.01,"ease":"linear"}]; stage.build(chart)
			label.text=ch+" · "+level.word+" · "+str(level.value)+" "+vocab[ch].unit
			var image=await render_image(renderer,stage)
			sheet.blit_rect(image,Rect2i(0,0,480,270),Vector2i(col*480,row*300)); col+=1
		row+=1
	sheet.save_png("res://evidence/vocab_sheet.png")
	print("VOCAB_SHEET levels rendered")
	quit(0 if identical else 1)
