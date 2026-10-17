extends SceneTree
const Document=preload("res://document.gd")
const Tools=preload("res://tools.gd")
const Server=preload("res://mcp_server.gd")
var server=Server.new()
var doc=Document.new()
var api=Tools.new()
var failures=0
var session=""
func _init() -> void: run.call_deferred()
func request(value: Dictionary) -> Dictionary:
	var http=HTTPRequest.new(); root.add_child(http)
	var headers=PackedStringArray(["Content-Type: application/json","Accept: application/json, text/event-stream"])
	if not session.is_empty(): headers.append("Mcp-Session-Id: "+session)
	http.request("http://127.0.0.1:%d/mcp" % server.port,headers,HTTPClient.METHOD_POST,JSON.stringify(value))
	var response=await http.request_completed
	for h in response[2]:
		if h.to_lower().begins_with("mcp-session-id:"): session=h.substr(15).strip_edges()
	var parsed=JSON.parse_string(response[3].get_string_from_utf8()) if not response[3].is_empty() else {}; http.queue_free()
	return parsed if parsed is Dictionary else {}
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures+=1
func run() -> void:
	AudioServer.set_bus_mute(0,true); KB.set_layout("ansi")
	doc.raw={"bpm":120,"timing":[{"t":0,"beat":0.5,"meter":4}],"lights":[{"t":0,"id":0,"type":"on","x":0.5,"w":0.8,"auto":true}],"notes":[]}; doc.core.load_chart(doc.raw)
	api.doc=doc; root.add_child(server); check(server.start(api,47900)==OK,"loopback server starts")
	var r=await request({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1"}}})
	check(r.has("result") and not session.is_empty(),"HTTP initialize with session header")
	r=await request({"jsonrpc":"2.0","method":"notifications/initialized"}); check(r.is_empty(),"notification HTTP 202")
	r=await request({"jsonrpc":"2.0","id":2,"method":"tools/list"}); check(r.get("result",{}).get("tools",[]).size()==api.NAMES.size(),"HTTP tools/list")
	r=await request({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"song_info","arguments":{}}}); check(not r.result.isError,"HTTP read tool")
	r=await request({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":"stale","ops":[]}}}); check(r.result.isError,"HTTP stale edit refused")
	r=await request({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":doc.revision(),"ops":[{"target":"notes","op":"add","value":{"t":3,"light":0,"u":0.5,"k":5,"kind":"tap","dur":0}}]}}}); check(not r.result.isError and doc.raw.notes.size()==1,"HTTP atomic edit accepted")
	r=await request({"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"notes","arguments":{"from":2,"to":4}}}); check(JSON.parse_string(r.result.content[0].text).notes.size()==1,"HTTP worker read returns notes")
	r=await request({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"notes","arguments":{"from":[]}}}); check(r.get("error",{}).get("code")==-32602,"HTTP invalid tool arguments refused")
	var rev=doc.revision()
	r=await request({"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":rev,"ops":[{"target":"lights","op":"add","value":{"t":0,"type":"on","id":[],"x":0.5,"w":0.2}}]}}}); check(r.result.isError and doc.revision()==rev,"malformed nested edit refused without mutation")
	var folder=ProjectSettings.globalize_path("res://evidence/http-version-"+str(Time.get_ticks_usec())); DirAccess.make_dir_recursive_absolute(folder)
	doc.path=folder.path_join("chart.json"); var file=FileAccess.open(doc.path,FileAccess.WRITE); file.store_string(Document.canonical(doc.raw)); file.close()
	doc.original=FileAccess.get_file_as_string(doc.path); doc.saved_revision=doc.revision()
	doc.version_store().initialize(); doc.version_store().commit("HTTP baseline",false)
	r=await request({"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"branch_create","arguments":{"name":"writing"}}}); check(not r.result.isError and not doc.busy,"HTTP deferred branch create releases document lock")
	doc.edit({"expected_revision":doc.revision(),"ops":[{"target":"notes","op":"update","index":0,"value":{"t":3.5}}]})
	doc.allow_save=true; doc.begin_group()
	r=await request({"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"commit","arguments":{"message":"blocked"}}}); check(r.result.isError,"HTTP commit permission refused")
	doc.version_store().allow_commit=true
	r=await request({"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"commit","arguments":{"message":"Claude: HTTP edit"}}}); check(not r.result.isError and doc.saved_revision==doc.revision(),"HTTP opted-in commit during Claude turn")
	r=await request({"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"branch_switch","arguments":{"name":"writing"}}}); check(not r.result.isError and doc.raw.notes[0].t==3,"HTTP branch switch synchronizes working model: "+JSON.stringify(r).left(300))
	doc.end_group()
	r=await request({"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"notes","arguments":{"version":"main","from":3.4,"to":3.6}}}); check(not r.result.isError and JSON.parse_string(r.result.content[0].text).notes.size()==1,"HTTP versioned notes without switching")
	print("CHARTER_HTTP failures=",failures)
	quit(1 if failures else 0)
