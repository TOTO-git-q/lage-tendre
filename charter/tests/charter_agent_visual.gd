extends SceneTree
var failures = 0
var app
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func frames(n: int = 3) -> void:
	for i in n: await process_frame
func run() -> void:
	var preference_file = "user://agent_backend.json"
	var previous_preference = FileAccess.get_file_as_string(preference_file) if FileAccess.file_exists(preference_file) else ""
	var preferences = FileAccess.open(preference_file,FileAccess.WRITE); preferences.store_string("{}"); preferences.close()
	print("AGENT_VISUAL_PID=",OS.get_process_id())
	AudioServer.set_bus_mute(0,true)
	app = preload("res://app.gd").new(); app.persist = false; app.silent = true; app.bridge.cli_enabled = false
	root.size = Vector2i(1600,900); root.add_child(app); await frames()
	var panel = app.assistant; var store = app.api.attachments
	panel.new_conversation()
	app._agent_files_dropped(PackedStringArray([ProjectSettings.globalize_path("res://tests/fixtures/generated/original.osz"),ProjectSettings.globalize_path("res://tests/fixtures/generated/text.txt")]))
	var deadline = Time.get_ticks_msec()+10000
	while (panel.copy_thread != null or not panel.copy_paths.is_empty()) and Time.get_ticks_msec() < deadline: await process_frame
	await frames()
	check(panel.backend == "external" and panel.selector.item_count == 1 and panel.title.text == "Agent", "no CLI defaults to external Agent")
	check(app.panes.assistant and store.items.size() == 2 and panel.attachment_chips.get_child_count() == 2 and panel.attachment_quick.get_child_count() == 3,"window drop opens panel with two chips and osu quick requests")
	check(is_instance_valid(panel.external_page) and app.server.endpoint() in panel.external_page.snippets()[0],"external page real endpoint and snippets")
	app.server.set_token(true)
	check(panel.external_page.snippets().all(func(s): return app.server.access_token in s),"all snippets include enabled bearer token")
	app.server.set_token(false)
	var connection = JSON.parse_string(FileAccess.get_file_as_string(app.server.config_path)); check(connection.mcpServers.charter.url == app.server.endpoint(),"charter_mcp.json reflects live connection")
	var args = preload("res://agent_backends.gd").codex_arguments("test prompt",app.server.endpoint(),"test_token","test-session")
	check(args[0] == "exec" and "--json" in args and "read-only" in args and args[-3] == "resume" and args[-2] == "test-session" and "mcp_servers.charter.url="+JSON.stringify(app.server.endpoint()) in args and Array(args).any(func(a): return "Bearer test_token" in a),"Codex argument construction: JSON, read-only, MCP URL/token, resume")
	var fixture = store.items[0]
	var old_path: String = app.doc.path
	var parsed = app.api.call_tool("song_create",{"from_attachment":fixture.id,"osu_entry":"original-4k.osu","dir":"agent_visual_"+str(Time.get_ticks_usec())})
	check(not parsed.has("error"),"visual creates original library-only fixture")
	# Open via live MCP application hook while retaining attached conversation.
	var opened = app.api.call_tool("song_open",{"dir":parsed.dir})
	check(not opened.has("error") and store.items.size() == 2,"live song_open preserves attachment conversation")
	var converted = app.api.call_tool("osu_convert_draft",{"id":fixture.id,"osu_entry":"original-4k.osu"})
	check(not converted.has("error"),"live draft conversion")
	panel.set_backends({"claude":true,"codex":true})
	check(panel.selector.item_count == 3 and panel.backend == "claude","selector exposes available built-ins, default first")
	panel._select_backend(1)
	panel.set_backends({"claude":true,"codex":true})
	check(panel.backend == "codex","backend selection remembered")
	panel._select_backend(2)
	check(panel.backend == "external" and store.items.size() == 2,"backend switches share attachments")
	app.seek(3.0); app.panes.assistant = true; app.panes.inspector = false; app.panes.assistant_w = 520.0; app.apply_panes(true)
	var shots = ProjectSettings.globalize_path("res://shots/agent-io"); DirAccess.make_dir_recursive_absolute(shots)
	for size in [Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size = size; DisplayServer.window_set_size(size); await frames(8); await create_timer(0.2).timeout; await RenderingServer.frame_post_draw
		var image = root.get_texture().get_image(); image.save_png(shots.path_join("external-agent-%dx%d.png" % [size.x,size.y]))
		check(image.get_size() == size,"external Agent screenshot %s" % size)
	var http = HTTPRequest.new(); root.add_child(http)
	var headers = PackedStringArray(["Content-Type: application/json"])
	http.request(app.server.endpoint(),headers,HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":1,"method":"initialize"}))
	var response = await http.request_completed
	for h in response[2]:
		if h.to_lower().begins_with("mcp-session-id:"): headers.append("Mcp-Session-Id: "+h.substr(15).strip_edges())
	http.request(app.server.endpoint(),headers,HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"preview_frame","arguments":{"at":3.0}}}))
	response = await http.request_completed
	var result = JSON.parse_string(response[3].get_string_from_utf8())
	check(not result.get("result",{}).get("isError",true),"preview_frame via real HTTP returns image")
	if not result.get("result",{}).get("isError",true):
		var image = Image.new(); image.load_png_from_buffer(Marshalls.base64_to_raw(result.result.content[0].data))
		var bright = 0
		for y in range(0,image.get_height(),16):
			for x in range(0,image.get_width(),16):
				if image.get_pixel(x,y).get_luminance() > 0.02: bright += 1
		check(image.get_width() <= 1280 and bright > 10,"preview_frame is real non-black game render")
		image.save_png(shots.path_join("preview-frame.png"))
	var before_agent_edit = app.doc.revision()
	http.request(app.server.endpoint(),headers,HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"edit","arguments":{"expected_revision":before_agent_edit,"ops":[{"target":"fx","op":"add","value":{"t":3,"type":"ring"}}]}}}))
	response = await http.request_completed
	check(panel.external_page.calls.text.contains("edit") and panel.external_page.calls.text.contains("ok"),"external page displays live MCP activity")
	panel.external_page.undo_agent()
	check(app.doc.revision() == before_agent_edit,"external page Undo last agent step restores revision")
	var rejected = app.api.call_tool("song_open",{"dir":parsed.dir,"discard":true})
	check(rejected.has("error") and app.has_node("AgentOpenConfirm"),"dirty live document opens GUI confirmation")
	app.get_node("AgentOpenConfirm").confirmed.emit()
	check(not app.api.call_tool("song_open",{"dir":parsed.dir,"discard":true}).has("error"),"GUI-confirmed discard opens exact requested song")
	check(app.api.open_confirmed.is_empty(),"discard confirmation is single-use")
	# Remove just this newly created original fixture song, preserving the library and existing songs.
	var destination = app.api.songs_root.path_join(parsed.dir)
	for file in DirAccess.get_files_at(destination): DirAccess.remove_absolute(destination.path_join(file))
	DirAccess.remove_absolute(destination)
	app.doc.path = old_path
	panel.new_conversation(); app.queue_free(); http.queue_free(); await frames(3)
	if previous_preference.is_empty(): DirAccess.remove_absolute(preference_file)
	else:
		preferences = FileAccess.open(preference_file,FileAccess.WRITE); preferences.store_string(previous_preference); preferences.close()
	print("CHARTER_AGENT_VISUAL failures=",failures); quit(1 if failures else 0)
