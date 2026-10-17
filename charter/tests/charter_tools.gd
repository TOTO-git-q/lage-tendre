extends SceneTree
const Document=preload("res://document.gd")
const Tools=preload("res://tools.gd")
var failed=0
func check(ok: bool, text: String) -> void:
	print("PASS " if ok else "FAIL ",text)
	if not ok: failed+=1
func _init() -> void: run.call_deferred()
func run() -> void:
	KB.set_layout("ansi"); AudioServer.set_bus_mute(0,true)
	var d=Document.new(); var api=Tools.new(); api.doc=d
	d.open(ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json").simplify_path())
	var timings={}
	for name in ["song_info","time_map","selection","tracks","track_state","notes","camera","music","analysis","history"]:
		var start=Time.get_ticks_usec()
		var result=api.call_tool(name,{"from":"44.1","to":"45.1","points":["44.1","44.1+3/16"]})
		timings[name]=(Time.get_ticks_usec()-start)/1000.0
		check(not result.has("error"),"read "+name+" %.2f ms" % timings[name])
	var f=FileAccess.open("res://evidence/api_timings.json",FileAccess.WRITE); f.store_string(JSON.stringify(timings,"  ")); f.close()
	var notes=api.call_tool("notes",{"from":"44.1","to":"45.1"}).notes
	check(not notes.is_empty(),"bar 44 notes present")
	for n in notes:
		check(d.raw.notes[n.id].t==n.t and int(d.raw.notes[n.id].light)==int(n.light),"raw identity "+str(n.id))
	check(api.call_tool("music",{"from":"44.1","to":"45.1"}).available,"analysis JSON loaded")
	check(not api.call_tool("music",{"from":"44.1","to":"45.1"}).bars.is_empty(),"music bars survive JSON numeric types")
	var synthetic={"bpm":120,"timing":[{"t":0,"beat":0.5,"meter":4}],"lights":[{"t":0,"type":"on","id":0,"x":0.5,"w":0.8,"a":0,"auto":true}],"notes":[{"t":3,"kind":"hold","light":0,"u":0.5,"k":5,"dur":1},{"t":5,"kind":"tap","light":0,"u":0.5,"k":5,"dur":0}]}
	d.raw=synthetic; d.refresh_core()
	d.locked_tracks[0]=true
	check(api.call_tool("track_move",{"expected_revision":d.revision(),"id":0,"dx_keys":0.25}).has("error"),"locked track refuses MCP mutation")
	d.locked_tracks.clear()
	var before=d.revision(); var before_bytes=JSON.stringify(d.raw)
	var move=api.call_tool("track_move",{"expected_revision":before,"id":0,"dx_keys":0.25,"notes_follow":true})
	check(not move.has("error"),"notes-follow track movement")
	var st=ChartLib.light_at(d.core.tl[0],3)
	check(absf((st.x+(d.raw.notes[0].u-0.5)*st.w)*15-7.25)<0.00001,"notes-follow retains landing key")
	d.undo(); check(JSON.stringify(d.raw)==before_bytes,"track move undo")
	var camera=api.call_tool("camera_move",{"expected_revision":d.revision(),"at":"2.1","move":"推","to":"近","speed":"缓","ease":"缓入缓出"})
	check(not camera.has("error") and d.raw.get("fx",[]).size()>0 and d.raw.fx[0].ch=="zoom","camera phrase writes engine tween "+JSON.stringify(camera))
	if camera.has("error"): quit(1); return
	check(absf(d.raw.fx[0].dur-2)<0.00001,"local beat speed conversion")
	d.begin_group()
	api.call_tool("camera_move",{"expected_revision":d.revision(),"at":"3.1","ch":"line_y","to":"上浮"})
	api.call_tool("camera_move",{"expected_revision":d.revision(),"at":"3.1","ch":"line_glow","to":"亮"})
	var group_size=d.undo_stack.size(); var summary=d.end_group()
	check(d.undo_stack.size()==group_size-1 and summary.changed,"one Claude turn one undo step")
	d.undo(); check(d.raw.fx.size()==1,"turn undo preserves earlier camera event")
	var moved=api.call_tool("edit",{"expected_revision":d.revision(),"ops":[{"target":"notes","op":"update","index":0,"value":{"t":6}}]})
	check(not moved.has("error") and d.core.notes[0].raw_id==1 and d.core.notes[1].raw_id==0,"raw IDs survive reordered core notes")
	d.undo()
	check(api.call_tool("set_selection",{"notes":[999999]}).has("error"),"invalid selection indices refused")
	for player in ["autoplay","home","offset","fat_finger"]:
		var job=api.call_tool("simulate",{"player":player,"offset_ms":30 if player=="offset" else 0})
		var polls=0
		while api.poll_job(job.job_id).status!="done" and polls<2000:
			api.tick_jobs(); polls+=1
		var result=api.call_tool("simulate",{"job_id":job.job_id})
		check(result.status=="done" and result.stats.MISS==0,"deferred "+player+" simulation")
	var rev=d.revision()
	var remove=api.call_tool("edit",{"expected_revision":rev,"ops":[{"target":"notes","op":"delete","index":1},{"target":"notes","op":"delete","index":0},{"target":"lights","op":"delete","index":0}]})
	check(not remove.has("error") and d.raw.notes.is_empty(),"delete track and notes in same transaction")
	print("CHARTER_TOOLS failures=",failed)
	quit(1 if failed else 0)
