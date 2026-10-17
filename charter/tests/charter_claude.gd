extends SceneTree
const App=preload("res://app.gd")
var app
var transcript: FileAccess
var used_info=false
var used_notes=false
var result_error=false
func _init() -> void: run.call_deferred()
func run() -> void:
	app=App.new(); root.add_child(app)
	app.audio.set_muted(true)
	transcript=FileAccess.open("res://evidence/claude_bridge_roundtrip.jsonl",FileAccess.WRITE)
	app.bridge.message.connect(func(value):
		transcript.store_line(JSON.stringify(value)); transcript.flush()
		if value.get("type","")=="assistant":
			for content in value.get("message",{}).get("content",[]):
				if content.get("name","")=="mcp__charter__song_info": used_info=true
				if content.get("name","")=="mcp__charter__notes": used_notes=true
		if value.get("type","")=="result": result_error=value.get("is_error",false)
	)
	app.bridge.done.connect(func(value):
		transcript.store_line(JSON.stringify({"bridge_done":value,"used_song_info":used_info,"used_notes":used_notes,"is_error":result_error})); transcript.close()
		print("CLAUDE_BRIDGE done info=",used_info," notes=",used_notes," error=",result_error," stderr=",value.get("stderr",""))
		quit(0 if used_info and used_notes and not result_error else 1)
	)
	var result=app.bridge.send("Read only. Use song_info and notes for bar 44 (from 44.1 to 45.1). Do not edit or save. Report title, revision, count, first three note times and fingering keys.")
	print("CLAUDE_BRIDGE launch ",result)
	if result.has("error"): quit(1); return
	await create_timer(150).timeout
	app.bridge.stop(); print("CLAUDE_BRIDGE timeout"); quit(1)
