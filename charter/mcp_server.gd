extends Node
## Loopback-only Streamable HTTP, bounded incremental parsing, one request per connection.
var tcp = TCPServer.new()
var peers: Array = []
var port = 47800
var api
var session = ""
var config_path = "user://charter_mcp.json"
var workers: Array=[]

signal activity_changed
var activity: Array = []
var clients: Dictionary = {}
var token_enabled = false
var access_token = ""
var port_note = ""
var excluded: Array = []
var settings_path = "user://charter_connection.json"
var last_edit_client = ""
var last_edit_at = 0
var last_edit_revision = ""
var last_edit_path = ""
var edit_epoch = 0

func cancel_pending() -> void:
	edit_epoch += 1

func endpoint() -> String:
	return "http://127.0.0.1:%d/mcp" % port

func write_config() -> void:
	var config = {"type":"http","url":endpoint()}
	if token_enabled: config["headers"] = {"Authorization":"Bearer "+access_token}
	var f = FileAccess.open(config_path,FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"mcpServers":{"charter":config}})); f.close()
	f = FileAccess.open(settings_path,FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"port":port,"token_enabled":token_enabled,"access_token":access_token})); f.close()

func set_token(enabled: bool, regenerate: bool = false) -> void:
	token_enabled = enabled
	if access_token.is_empty() or regenerate: access_token = Crypto.new().generate_random_bytes(32).hex_encode()
	clients.clear(); write_config(); activity_changed.emit()

static func parse_excluded(text: String) -> Array:
	var ranges = []; var regex = RegEx.new(); regex.compile("^\\s*([0-9]+)\\s+([0-9]+)")
	for line in text.split("\n"):
		var found = regex.search(line)
		if found: ranges.append([int(found.get_string(1)),int(found.get_string(2))])
	return ranges

func start(tools_api, preferred = 47800) -> Error:
	api = tools_api
	var saved = JSON.parse_string(FileAccess.get_file_as_string(settings_path)) if FileAccess.file_exists(settings_path) else {}
	if saved is Dictionary:
		preferred = int(saved.get("port",preferred)); token_enabled = saved.get("token_enabled",false); access_token = str(saved.get("access_token",""))
	if access_token.is_empty(): access_token = Crypto.new().generate_random_bytes(32).hex_encode()
	var detected = OS.get_name() != "Windows"
	if OS.get_name() == "Windows":
		var out = []; var code = OS.execute("netsh",PackedStringArray(["interface","ipv4","show","excludedportrange","protocol=tcp"]),out,true)
		excluded = parse_excluded("\n".join(out)); detected = code == 0
	var candidates = []
	if detected:
		if preferred >= 1024 and preferred <= 65535: candidates.append(preferred)
		for n in range(18080,18280):
			if n != preferred: candidates.append(n)
	candidates.append(0)
	for n in candidates:
		if n > 0 and excluded.any(func(r): return n >= r[0] and n <= r[1]): continue
		if tcp.listen(n,"127.0.0.1") == OK:
			port = tcp.get_local_port(); session = Crypto.new().generate_random_bytes(24).hex_encode()
			port_note = "OS-assigned port (excluded range detection unavailable or fixed ports busy)" if n == 0 else ("Fixed port selected outside excluded ranges" if n != preferred else "Fixed port")
			write_config(); return OK
	return ERR_CANT_CREATE

func set_port(value: int) -> Dictionary:
	if value < 1024 or value > 65535: return {"error":"port must be 1024..65535"}
	if not peers.is_empty() or not workers.is_empty(): return {"error":"wait until active calls finish"}
	var probe = TCPServer.new()
	if excluded.any(func(r): return value >= r[0] and value <= r[1]): return {"error":"port is in a Windows excluded range"}
	if value == port: return {"port":port}
	if probe.listen(value,"127.0.0.1") != OK: return {"error":"port is busy"}
	tcp.stop(); tcp = probe; port = value; clients.clear(); port_note = "Fixed port"; write_config(); activity_changed.emit()
	return {"port":port}

func record(p: Dictionary, ok: bool) -> void:
	if not p.has("tool"): return
	var row = {"tool":str(p.tool).left(128),"time":Time.get_datetime_string_from_system().get_slice("T",1),"ok":ok,"client":p.get("client","")}
	activity.append(row)
	if activity.size() > 100: activity.pop_front()
	activity_changed.emit()

func accept_edit(candidate, job: Dictionary) -> void:
	var entry = candidate.undo_stack[-1]
	var who: String = job.peer.get("client", "")
	var now = Time.get_ticks_msec()
	# Do not cross user edits, document switches, other clients, or an idle gap.
	if api.doc.group_before.is_empty():
		entry.author = "Agent"; entry.label = "External Agent: " + str(clients.get(who,{}).get("name","client"))
		if who == last_edit_client and now-last_edit_at < 1500 and api.doc.path == last_edit_path and api.doc.revision() == last_edit_revision and not api.doc.undo_stack.is_empty() and api.doc.undo_stack[-1].author == "Agent":
			var previous = api.doc.undo_stack.pop_back(); entry.before = previous.before; entry.ext_before = previous.ext_before
	api.doc.undo_stack.append(entry); api.doc.redo_stack.clear()
	api.doc.ext = candidate.ext; api.doc.raw = candidate.raw; api.doc.core = candidate.core
	last_edit_client = who; last_edit_at = now; last_edit_revision = api.doc.revision(); last_edit_path = api.doc.path; api.doc.changed.emit()

func _process(_dt: float) -> void:
	for job in workers.duplicate():
		if not job.thread.is_alive():
			var completed=job.thread.wait_to_finish()
			if not completed is Dictionary: completed={"result":{"error":"validation worker failed; document unchanged"}}
			var value=completed.result
			if job.get("name","") != "song_create" and job.get("epoch",edit_epoch) != edit_epoch: value = {"error":"agent stopped; pending operation cancelled"}
			if job.get("version_command",false): api.doc.busy=false
			if job.get("name","") != "song_create" and not value.has("error") and (job.revision!=api.doc.revision() or job.get("path",api.doc.path)!=api.doc.path): value={"error":"stale document or revision while validating","revision":api.doc.revision()}
			if completed.has("document") and completed.document.raw!=api.doc.raw and job.get("locks",{})!=api.doc.locked_tracks: value={"error":"track locks changed while validating; retry"}
			if api.doc.busy and not job.get("version_command",false) and completed.has("document") and completed.document.raw!=api.doc.raw: value={"error":"version operation in progress; retry edit"}
			if not value.has("error") and completed.has("document"):
				var candidate=completed.document
				if job.get("version_command",false):
					if job.get("name","")=="commit" and candidate.raw!=api.doc.raw:
						api.doc.raw=candidate.raw; api.doc.core=candidate.core; api.doc.group_before=candidate.group_before
					api.doc.original=candidate.original; api.doc.saved_revision=candidate.saved_revision
					api.doc.version_store().last_commit_size=candidate.version_store().last_commit_size
					if job.get("name","")=="branch_switch":
						api.doc.ext=candidate.ext; api.doc.raw=candidate.raw; api.doc.core=candidate.core; api.doc.undo_stack=candidate.undo_stack; api.doc.redo_stack=[]; api.doc.group_before=candidate.group_before; api.doc.changed.emit()
				elif candidate.raw!=api.doc.raw:
					accept_edit(candidate,job)
			if completed.has("jobs"):
				for id in completed.jobs: api.jobs[id]=completed.jobs[id]
			respond(job.peer,200,{"jsonrpc":"2.0","id":job.id,"result":tool_result(value)})
			workers.erase(job)
	if tcp.is_connection_available(): peers.append({"tcp":tcp.take_connection(),"bytes":PackedByteArray(),"started":Time.get_ticks_msec()})
	for p in peers.duplicate():
		var conn: StreamPeerTCP=p.tcp; conn.poll()
		if conn.get_status()!=StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec()-p.started>10000:
			conn.disconnect_from_host(); peers.erase(p); continue
		if p.get("waiting",false): continue
		var available=conn.get_available_bytes()
		if available>0:
			var data=conn.get_data(mini(available,65536))
			if data[0]!=OK: conn.disconnect_from_host(); peers.erase(p); continue
			p.bytes.append_array(data[1])
		if p.bytes.size()>2*1024*1024: respond(p,413,{"error":"request too large"}); continue
		var split=-1; var scan=0
		while scan+3<p.bytes.size() and scan<65536:
			if p.bytes[scan]==13 and p.bytes[scan+1]==10 and p.bytes[scan+2]==13 and p.bytes[scan+3]==10: split=scan; break
			scan+=1
		if split<0: continue
		var header=p.bytes.slice(0,split).get_string_from_utf8(); var length=0; var sid=""; var origin=""; var authorization=""
		for line in header.split("\r\n"):
			if line.to_lower().begins_with("content-length:"): length=int(line.get_slice(":",1).strip_edges())
			if line.to_lower().begins_with("mcp-session-id:"): sid=line.get_slice(":",1).strip_edges()
			if line.to_lower().begins_with("authorization:"): authorization=line.substr(14).strip_edges()
			if line.to_lower().begins_with("origin:"): origin=line.substr(7).strip_edges()
		if length<0 or length>2*1024*1024: respond(p,413,{}); continue
		var header_bytes=split+4
		if p.bytes.size()<header_bytes+length: continue
		if not valid_origin(origin): respond(p,403,{}); continue
		if token_enabled and authorization != "Bearer "+access_token: respond(p,401,{"error":"authorization required"}); continue
		if header.begins_with("DELETE /mcp HTTP/1."):
			clients.erase(sid); respond(p,200,{}); continue
		if not header.begins_with("POST /mcp HTTP/1."): respond(p,405,{}); continue
		var request=JSON.parse_string(p.bytes.slice(header_bytes,header_bytes+length).get_string_from_utf8())
		if not request is Dictionary: respond(p,400,{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}); continue
		if not request.get("params",{}) is Dictionary: respond(p,400,{"error":"params must be an object"}); continue
		if request.get("method","")!="initialize" and not clients.has(sid): respond(p,404,{"error":"missing or invalid MCP session"}); continue
		if request.get("method","") == "initialize":
			if clients.size() >= 256: clients.erase(clients.keys()[0])
			sid = Crypto.new().generate_random_bytes(24).hex_encode()
			clients[sid] = {"name":str(request.get("params",{}).get("clientInfo",{}).get("name","client")).left(64),"seen":Time.get_ticks_msec()}
		p["client"] = sid
		if clients.has(sid): clients[sid].seen = Time.get_ticks_msec()
		var params=request.get("params",{})
		if request.get("method","")=="tools/call" and params is Dictionary:
			p["tool"] = str(params.get("name",""))
			var validation=validate_arguments(params)
			if not validation.is_empty():
				respond(p,200,{"jsonrpc":"2.0","id":request.get("id"),"error":{"code":-32602,"message":validation}}); continue
		if request.get("method","") == "tools/call" and request.has("id") and params.get("name","") == "preview_frame":
			p["waiting"] = true; preview_response.call_deferred(p,request); continue
		var worker_names=["edit","camera_move","track_create","track_move","notes","analysis","track_state","camera","tracks","diff","compare_stats","take_range","versions","branch_create","branch_switch","commit","chart_plugins_set","osu_convert_draft","osu_parse","attachment_read","attachment_image","song_create"]
		if params is Dictionary and params.get("name","")=="simulate" and not params.get("arguments",{}).has("job_id"): worker_names.append("simulate")
		if request.get("method","")=="tools/call" and request.has("id") and params is Dictionary and params.get("arguments",{}) is Dictionary and params.get("name","") in worker_names:
			p["waiting"]=true
			if workers.size() >= 8: respond(p,503,{"error":"too many active tool calls; retry"}); continue
			var job={"thread":Thread.new(),"peer":p,"id":request.id,"revision":api.doc.revision(),"path":api.doc.path,"epoch":edit_epoch}
			var snapshot=api.doc.raw.duplicate(true); var ext_snapshot=api.doc.ext.duplicate(true); var locks=api.doc.locked_tracks.duplicate(); var args=params.get("arguments",{}).duplicate(true); var name=params.name
			var version_command=name in ["branch_create","branch_switch","commit"]
			if version_command and api.doc.busy:
				respond(p,200,{"jsonrpc":"2.0","id":request.id,"result":{"content":[{"type":"text","text":"{\"error\":\"version operation in progress\"}"}],"isError":true}}); continue
			job["version_command"]=version_command; job["name"]=name
			if version_command: api.doc.busy=true
			job["locks"]=locks
			var store=api.attachments; var songs_root=api.songs_root; var song_path=api.doc.path; var music=api.doc.music; var song_meta=api.doc.song_meta
			var original=api.doc.original; var saved_revision=api.doc.saved_revision; var allow_save=api.doc.allow_save; var allow_commit=api.doc.version_store().allow_commit; var group=api.doc.group_before.duplicate(true); var history=api.doc.undo_stack.duplicate(true)
			job.thread.start(func():
				var candidate=preload("res://document.gd").new(); candidate.ext=ext_snapshot; candidate.raw=snapshot; candidate.locked_tracks=locks; candidate.refresh_core()
				candidate.path=song_path; candidate.music=music; candidate.song_meta=song_meta
				if version_command:
					candidate.original=original; candidate.saved_revision=saved_revision; candidate.allow_save=allow_save; candidate.version_store().allow_commit=allow_commit; candidate.group_before=group; candidate.undo_stack=history
				var tools=preload("res://tools.gd").new(); tools.doc=candidate; tools.attachments=store; tools.songs_root=songs_root
				var result=tools.call_tool(name,args)
				if name == "song_create": return {"result":result,"jobs":tools.jobs}
				return {"result":result,"document":candidate,"jobs":tools.jobs}
			)
			workers.append(job); continue
		var result=dispatch_rpc(request)
		respond(p,202 if result.is_empty() else 200,result)

func dispatch_rpc(r: Dictionary) -> Dictionary:
	if not r.has("id"): return {}
	var out={"jsonrpc":"2.0","id":r.id}
	if r.get("jsonrpc","")!="2.0": out.error={"code":-32600,"message":"Invalid Request"}; return out
	match r.get("method",""):
		"initialize": out.result={"protocolVersion":"2025-03-26","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"charter","version":"0.1.0"}}
		"ping": out.result={}
		"tools/list": out.result={"tools":api.list_tools()}
		"tools/call":
			var params=r.get("params",{})
			if not params is Dictionary or not str(params.get("name","")) in api.NAMES:
				out.error={"code":-32602,"message":"Unknown tool"}
			elif not params.get("arguments",{}) is Dictionary: out.error={"code":-32602,"message":"Arguments must be an object"}
			else:
				var value=api.call_tool(params.name,params.get("arguments",{}))
				out.result=tool_result(value)
		_: out.error={"code":-32601,"message":"Method not found"}
	return out

func validate_arguments(params: Dictionary) -> String:
	for tool in api.list_tools():
		if tool.name==params.get("name",""): return check_schema(params.get("arguments",{}),tool.inputSchema,"arguments")
	return "Unknown tool"

func check_schema(value, schema: Dictionary, path: String) -> String:
	if schema.has("oneOf"):
		for option in schema.oneOf:
			if check_schema(value,option,path).is_empty(): return ""
		return path+": invalid value type"
	var type=schema.get("type","")
	if type=="object":
		if not value is Dictionary: return path+": expected object"
		for key in schema.get("required",[]):
			if not value.has(key): return path+": missing "+key
		for key in value:
			if schema.get("properties",{}).has(key):
				var error=check_schema(value[key],schema.properties[key],path+"."+key)
				if not error.is_empty(): return error
			elif schema.get("additionalProperties",true)==false: return path+": unknown property "+key
	elif type=="array":
		if not value is Array: return path+": expected array"
		if value.size()>schema.get("maxItems",10000): return path+": too many items"
		for i in value.size():
			var error=check_schema(value[i],schema.get("items",{}),path+"["+str(i)+"]")
			if not error.is_empty(): return error
	elif type=="number" or type=="integer":
		if not (value is int or value is float) or not is_finite(float(value)): return path+": expected finite number"
		if type=="integer" and float(value)!=floorf(float(value)): return path+": expected integer"
		if value<schema.get("minimum",-INF) or value>schema.get("maximum",INF): return path+": outside range"
	elif type=="boolean" and not value is bool: return path+": expected boolean"
	elif type=="string" and not value is String: return path+": expected string"
	if schema.has("enum") and not value in schema.enum: return path+": unknown value"
	return ""

func respond(p: Dictionary, code: int, value: Dictionary) -> void:
	var body="" if value.is_empty() and code==202 else JSON.stringify(value)
	var bytes=body.to_utf8_buffer()
	var h="HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nMcp-Session-Id: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code,"OK" if code<300 else "Error",p.get("client",session),bytes.size()]
	record(p,code < 300 and not value.has("error") and not value.get("result",{}).get("isError",false))
	p.tcp.put_data(h.to_utf8_buffer()+bytes); p.tcp.disconnect_from_host(); peers.erase(p)

func _exit_tree() -> void:
	for job in workers: job.thread.wait_to_finish()
	for p in peers: p.tcp.disconnect_from_host()
	tcp.stop()

static func tool_result(value: Dictionary) -> Dictionary:
	return {"content":value.get("_mcp_content",[{"type":"text","text":JSON.stringify(value)}]),"isError":value.has("error")}

static func valid_origin(origin: String) -> bool:
	if origin.is_empty(): return true
	var regex = RegEx.new(); regex.compile("^http://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?$")
	return regex.search(origin) != null

func preview_response(p: Dictionary, request: Dictionary) -> void:
	var value = {"error":"live rendering preview unavailable"}
	if api.app != null: value = await api.app.agent_preview(float(request.params.get("arguments",{}).get("at",0)))
	respond(p,200,{"jsonrpc":"2.0","id":request.id,"result":tool_result(value)})
