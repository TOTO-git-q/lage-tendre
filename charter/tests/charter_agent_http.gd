extends SceneTree
const Server = preload("res://mcp_server.gd")
var server = Server.new()
var api = preload("res://tools.gd").new()
var doc = preload("res://document.gd").new()
var store = preload("res://attachments.gd").new()
var session = ""
var failures = 0
var sequence = 0
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func request(method: String, params: Dictionary = {}, extra: PackedStringArray = []) -> Dictionary:
	var http = HTTPRequest.new(); root.add_child(http); http.timeout = 30
	var headers = PackedStringArray(["Content-Type: application/json","Accept: application/json, text/event-stream"])
	if not session.is_empty(): headers.append("Mcp-Session-Id: "+session)
	headers.append_array(extra); sequence += 1
	http.request(server.endpoint(),headers,HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":sequence,"method":method,"params":params}))
	var response = await http.request_completed
	for h in response[2]:
		if h.to_lower().begins_with("mcp-session-id:"): session = h.substr(15).strip_edges()
	var parsed = JSON.parse_string(response[3].get_string_from_utf8()); http.queue_free()
	return {"code":response[1],"body":parsed if parsed is Dictionary else {}}
func call_tool(name: String, args: Dictionary = {}) -> Dictionary:
	var r = await request("tools/call",{"name":name,"arguments":args})
	if r.body.has("error"): return r.body
	var content = r.body.get("result",{}).get("content",[])
	if content.is_empty(): return {"error":"empty HTTP tool content","response":r}
	if content[0].type == "image": return {"image":content[0]}
	return JSON.parse_string(content[0].text)
func run() -> void:
	AudioServer.set_bus_mute(0,true); KB.set_layout("ansi")
	api.doc = doc; api.attachments = store; store.start()
	api.songs_root = ProjectSettings.globalize_path("res://../dist/agent-io/http-songs"); DirAccess.make_dir_recursive_absolute(api.songs_root)
	root.add_child(server); check(server.start(api,18081) == OK,"loopback server starts")
	server.set_token(false); var r = await request("initialize",{"clientInfo":{"name":"agent-e2e"}})
	check(r.code == 200 and not session.is_empty(),"token off accepts initialize")
	var first_session = session
	var row = store.attach(ProjectSettings.globalize_path("res://tests/fixtures/generated/original.osz"))
	var parsed = await call_tool("osu_parse",{"id":row.id}); check(parsed.difficulties.size() == 2,"HTTP osu difficulty parse")
	var created = await call_tool("song_create",{"from_attachment":row.id,"osu_entry":"original-4k.osu","dir":"http_fixture"})
	check(not created.has("error"),"HTTP create unique song")
	var opened = await call_tool("song_open",{"dir":created.dir}); check(not opened.has("error"),"HTTP open new song")
	var converted = await call_tool("osu_convert_draft",{"id":row.id,"osu_entry":"original-4k.osu"})
	check(not converted.has("error") and doc.raw.notes.size() == 26,"HTTP worker converts draft")
	var undo_size = doc.undo_stack.size()
	var ops = []
	for id in [20,21]:
		ops.append({"target":"lights","op":"add","value":{"t":1,"id":id,"type":"on","x":0.5,"w":0.1,"auto":true}})
		ops.append({"target":"lights","op":"add","value":{"t":2,"id":id,"type":"sweep","x":0.7,"w":0.1,"dur":1,"ease":"linear","auto":true}})
	var edited = await call_tool("edit",{"expected_revision":doc.revision(),"ops":ops})
	check(not edited.has("error"),"HTTP add two sweeps with existing edit")
	edited = await call_tool("camera_move",{"expected_revision":doc.revision(),"at":3,"ch":"zoom","to":1.05})
	check(not edited.has("error") and doc.raw.fx.size() == 1,"HTTP existing camera_move")
	check(doc.undo_stack.size() <= undo_size+1 and doc.undo_stack[-1].author == "Agent","same-client burst is one labelled undo step")
	var analysis = await call_tool("analysis",{}); check(not analysis.has("error"),"HTTP analysis reports warnings: "+JSON.stringify(analysis).left(300))
	var job = await call_tool("simulate",{"player":"autoplay"})
	var deadline = Time.get_ticks_msec()+30000
	while job.get("status","") != "done" and Time.get_ticks_msec() < deadline:
		api.tick_jobs(); await process_frame; job = await call_tool("simulate",{"job_id":job.job_id})
	check(job.get("status","") == "done" and job.get("nonperfect_notes",[1]).is_empty(),"MCP end-to-end autoplay all PERFECT: "+JSON.stringify(job))
	var image = await call_tool("attachment_image",{"id":row.id,"entry":"bg.png"}); check(image.has("image") and image.image.mimeType == "image/png","HTTP transports native MCP image content")
	check((await call_tool("save",{})).has("error") and (await call_tool("commit",{"message":"denied"})).has("error"),"GUI save/commit opt-ins enforced")
	check((await call_tool("attachment_read",{"id":"missing"})).has("error"),"HTTP attachment errors returned")
	check(server.activity.any(func(c): return c.tool == "attachment_read" and not c.ok) and server.activity.any(func(c): return c.tool == "osu_convert_draft" and c.ok),"live activity contains ok/error without payloads")
	session = ""; r = await request("initialize",{"clientInfo":{"name":"second-client"}}); check(session != first_session,"independent external client sessions")
	r = await request("ping",{},PackedStringArray(["Origin: http://127.0.0.1:123.evil.test"])); check(r.code == 403,"spoofed Origin refused")
	server.set_token(true); session = ""; r = await request("initialize"); check(r.code == 401,"token on rejects missing bearer")
	r = await request("initialize",{},PackedStringArray(["Authorization: Bearer wrong"])); check(r.code == 401,"wrong bearer refused")
	r = await request("initialize",{},PackedStringArray(["Authorization: Bearer "+server.access_token])); check(r.code == 200,"valid bearer accepted over real HTTP")
	var before = server.access_token; server.set_token(true,true); check(server.access_token != before,"token regeneration invalidates previous token")
	r = await request("initialize",{},PackedStringArray(["Authorization: Bearer "+before])); check(r.code == 401,"old token rejected")
	server.set_token(false); session = ""; r = await request("initialize"); check(r.code == 200,"token off accepts requests again")
	check(Server.parse_excluded("  44620 48715 *\n  50000 50059").size() == 2,"Windows excluded-range parser")
	var simultaneous = {}; var clients_http = []
	for index in 2:
		var http = HTTPRequest.new(); root.add_child(http); clients_http.append(http); var key = index
		http.request_completed.connect(func(_result,_code,_headers,body): simultaneous[key] = JSON.parse_string(body.get_string_from_utf8()))
		http.request(server.endpoint(),PackedStringArray(["Content-Type: application/json","Mcp-Session-Id: "+session]),HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":500+index,"method":"tools/call","params":{"name":"song_create","arguments":{"from_attachment":row.id,"osu_entry":"original-4k.osu","dir":"concurrent"}}}))
	deadline = Time.get_ticks_msec()+10000
	while simultaneous.size() < 2 and Time.get_ticks_msec() < deadline: await process_frame
	var unique = []
	for response in simultaneous.values():
		var value = JSON.parse_string(response.result.content[0].text)
		if not value.has("error"): unique.append(value.dir)
	check(unique.size() == 2 and unique[0] != unique[1],"concurrent song_create reserves distinct folders without overwriting")
	for http in clients_http: http.queue_free()
	var pending = HTTPRequest.new(); root.add_child(pending)
	var revision = doc.revision(); var additions = []
	for i in 2000: additions.append({"target":"fx","op":"add","value":{"t":3+i*0.001,"type":"ring"}})
	pending.request(server.endpoint(),PackedStringArray(["Content-Type: application/json","Mcp-Session-Id: "+session]),HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":999,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":revision,"ops":additions}}}))
	deadline = Time.get_ticks_msec()+5000
	while server.workers.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(not server.workers.is_empty(),"long edit validation runs off UI thread")
	server.cancel_pending()
	var response = await pending.request_completed
	var stopped = JSON.parse_string(response[3].get_string_from_utf8())
	check(stopped.result.isError and doc.revision() == revision,"Stop cancels pending edits before document adoption")
	pending.request(server.endpoint(),PackedStringArray(["Content-Type: application/json","Mcp-Session-Id: "+session]),HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":1000,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":revision,"ops":additions}}}))
	deadline = Time.get_ticks_msec()+5000
	while server.workers.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	var original_path = doc.path; doc.path += "-other-song-same-revision"
	response = await pending.request_completed; doc.path = original_path
	stopped = JSON.parse_string(response[3].get_string_from_utf8())
	check(stopped.result.isError and doc.revision() == revision,"worker cannot adopt edits into another song with identical revision")
	pending.queue_free()
	var starter = preload("res://agent_backends.gd").starter(api,server.endpoint()); check(row.id in starter and row.name in starter and server.endpoint() in starter,"starter contains actual attachment ids/names/endpoint")
	store.delete_conversation(); server.queue_free(); await process_frame
	print("CHARTER_AGENT_HTTP failures=",failures); quit(1 if failures else 0)
