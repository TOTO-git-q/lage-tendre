extends SceneTree
const Document=preload("res://document.gd")
const Workspace=preload("res://plugin_workspace.gd")
var failures=0
var checks=0
var temp=""
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",message)
func copy_tree(source: String, target: String) -> void:
	DirAccess.make_dir_recursive_absolute(target)
	for file in DirAccess.get_files_at(source):
		if not file.ends_with(".uid") and not file.ends_with(".import"): DirAccess.copy_absolute(source.path_join(file),target.path_join(file))
	for dir in DirAccess.get_directories_at(source): copy_tree(source.path_join(dir),target.path_join(dir))
func _init() -> void: run.call_deferred()
func run() -> void:
	KB.set_layout("ansi"); AudioServer.set_bus_mute(0,true)
	temp=ProjectSettings.globalize_path("res://tests/out/charter-plugins-"+str(Time.get_ticks_usec()))
	var demos=ProjectSettings.globalize_path("res://../songs/_plugin_demos").simplify_path()
	copy_tree(demos,temp)
	var d=Document.new(); var w=Workspace.new(); w.doc=d
	for name in DirAccess.get_directories_at(temp):
		var path=temp.path_join(name).path_join("chart.json")
		if not FileAccess.file_exists(path): continue
		var bytes=FileAccess.get_file_as_bytes(path)
		check(not d.open(path).has("error"),"demo opens "+name)
		check(d.save().get("unchanged",false) and FileAccess.get_file_as_bytes(path)==bytes,"byte-identical no-op save "+name)
		var before=d.raw.duplicate(true)
		d.raw["author_probe"]={"unknown":[],"enabled":false}
		d.revision_cache=""
		check(not d.save().has("error"),"save intentional extension "+name)
		d.open(path)
		var restored=d.raw.duplicate(true); restored.erase("author_probe")
		check(restored==before and d.raw.author_probe=={"unknown":[],"enabled":false},"all plugin/unknown keys survive edited save "+name)
	d.open(temp.path_join("glow_ring/chart.json"))
	var listed=w.list_plugins()
	check(listed.plugins.size()>=8,"local, optional and standard catalog")
	check(listed.plugins.any(func(p): return p.id=="glow_ring" and "canvas.png" in p.files and not "canvas.png" in p.text_files),"binary assets listed but not editable as text")
	var text=w.read("glow_ring","plugin.json")
	check(text.has("revision") and text.data_only,"read text and revision")
	check(w.read("glow_ring","../chart.json").has("error"),"traversal refused")
	for path in ["/chart.json","C:/chart.json","entry.gd:ads","sub/../../chart.json","canvas.png","../glow_ring/plugin.json"]:
		check(w.read("glow_ring",path).has("error"),"unsafe/nontext path refused "+path)
	check(w.write("standard_chart","plugin.json","{}","").has("error"),"built-ins read-only")
	check(w.write("glow_ring","plugin.json",text.content,"wrong").has("error"),"stale write atomic")
	check(w.write("glow_ring","note.txt","x".repeat(Workspace.LIMIT+1),"").has("error"),"256 KB write cap")
	var written=w.write("glow_ring","plugin.json",text.content+"\n",text.revision)
	check(not written.has("error") and FileAccess.file_exists(written.get("backup","")),"revision write with backup")
	check(w.read("glow_ring","plugin.json").revision!=text.revision,"revision changes after write")
	check(w.validate_plugin("glow_ring").status=="ok","real declarative validator")
	for template in ["visual","event","script"]:
		var result=w.create("sample_"+template,template,"Sample "+template)
		check(not result.has("error") and result.validation.status in ["ok","script-untrusted"],"clean template "+template+" "+JSON.stringify(result.get("validation",{})))
	check(w.create("../escape","visual","Unsafe").has("error"),"unsafe create refused")
	check(w.create("sample_visual","visual","Existing").has("error"),"create preserves existing plugin")
	for template in ["visual","event"]:
		var result=w.create("dashed-"+template+".v1",template,"Dashed id")
		check(not result.has("error") and result.validation.status=="ok","template supports dotted/dashed id "+template)
	var revision=d.revision(); var before=d.raw.duplicate(true); var count=d.undo_stack.size()
	var bindings=d.raw.plugins.duplicate(true); bindings.append({"id":"sample_visual","version":"1.0.0"})
	check(w.set_bindings(bindings,"stale").has("error"),"stale chart bindings refused")
	check(not w.set_bindings(bindings,revision).has("error") and d.undo_stack.size()==count+1,"bindings are one transaction")
	d.undo(); check(d.raw==before,"binding undo lossless")
	d.redo(); check(d.raw.plugins==bindings,"binding redo")
	check(w.set_bindings([{"id":"missing","version":"1.0.0"}],d.revision()).has("error"),"missing dependency refused")
	# An observable static initializer must not execute even on reading/listing/validation.
	d.open(temp.path_join("script_trust/chart.json"))
	var marker="user://plugin_demos/trust_spark_loaded.txt"
	var marker_before=FileAccess.get_file_as_bytes(marker) if FileAccess.file_exists(marker) else PackedByteArray()
	var manifest=w.read("trust_spark","plugin.json")
	# Make this temp pack a previously unseen hash, without changing the source demo.
	w.write("trust_spark","probe.txt","Untrusted "+str(Time.get_ticks_usec()),"")
	var script_path=ProjectSettings.globalize_path(d.path.get_base_dir().path_join("plugins/trust_spark/entry.gd"))
	check(not ResourceLoader.has_cached(script_path),"untrusted script not cached before")
	check(w.list_plugins().plugins.any(func(p): return p.id=="trust_spark" and p.status=="script-untrusted"),"untrusted status visible")
	var validated=w.validate_plugin("trust_spark")
	check(validated.status=="script-untrusted" and validated.script_instances==0,"untrusted validate creates no script instance")
	check(validated.diagnostics.any(func(p): return "script not checked: pack not trusted" in p.message),"explicit unchecked script notice")
	check(not ResourceLoader.has_cached(script_path),"untrusted script never loaded")
	check((FileAccess.get_file_as_bytes(marker) if FileAccess.file_exists(marker) else PackedByteArray())==marker_before,"untrusted static side effect absent")
	# Symlink/junction escape, including the plugin root and an inner directory.
	var output=[]; var link=d.path.get_base_dir().path_join("plugins/link_escape")
	var code=OS.execute("cmd.exe",PackedStringArray(["/c","mklink","/J",link.replace("/","\\"),temp.path_join("glow_ring/plugins/glow_ring").replace("/","\\")]),output,true)
	check(code==0,"temporary junction created for containment test")
	if code==0:
		check(w.read("link_escape","plugin.json").has("error"),"junction read refused")
		check(w.write("link_escape","plugin.json","{}","").has("error"),"junction write refused")
		DirAccess.remove_absolute(link)
	d.open(temp.path_join("glow_ring/chart.json"))
	check(Document.lean({"notes":[],"lights":[],"opaque":[]}).has("opaque"),"unknown empty keys survive legacy minimization")
	var state=w.trust_state(); var trust_session=SongPluginSession.new(); var trust_data=trust_session._read_trust().data
	trust_data.decisions[state.content_hash]={"allowed":1}
	ChartCodec.write_json_atomic(SongPluginSession.TRUST_PATH,trust_data)
	check(not w.trust_state().trusted,"numeric trust flag cannot impersonate game boolean trust")
	check(w.author_trust().get("trusted",false) and w.trust_state().trusted,"human author action records real hash trust")
	check(w.validate_plugin("sample_script").status=="ok","trusted script syntax checked without install")
	var script_file=w.read("sample_script","entry.gd")
	var modified=w.write("sample_script","entry.gd",script_file.content+"\n# edited\n",script_file.revision)
	check(not modified.trusted and "must re-trust" in modified.trust_notice,"write invalidates whole-pack trust")
	check(w.validate_plugin("sample_script").status=="script-untrusted","edited script is not syntax-loaded")
	# File writes are included in the existing song-local version workflow.
	d.open(temp.path_join("glow_ring/chart.json")); var versions=d.version_store()
	check(not versions.initialize().has("error"),"song history initializes in temp copy")
	check(not versions.commit("Plugin initial",false).has("error"),"song version includes plugins")
	check("plugins/glow_ring/plugin.json" in versions.git(["ls-files"]).text,"plugin manifest tracked")
	check(not versions.branch_create("plugin_base").has("error"),"plugin version branch created")
	var file=w.read("glow_ring","plugin.json"); w.write("glow_ring","plugin.json",file.content+"\n",file.revision)
	check(not versions.clean() and not versions.plugin_diff("HEAD","working").get("patch","").is_empty(),"plugin edits visible in history and diff")
	check(versions.plugin_diff("working","working").patch.is_empty(),"same-version plugin diff is empty")
	check(not versions.commit("Plugin update",false).has("error"),"plugin edit committed in temporary song history")
	check(not versions.branch_switch("plugin_base").has("error") and w.read("glow_ring","plugin.json").content==file.content,"plugin branch switch restores file bytes")
	if "plugin_standard" in preload("res://tools.gd").NAMES: await mcp_checks(d,w)
	print("CHARTER_PLUGINS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func mcp_checks(d, w) -> void:
	var api=preload("res://tools.gd").new(); api.doc=d
	var server=preload("res://mcp_server.gd").new(); root.add_child(server)
	check(server.start(api,0)==OK,"plugin MCP loopback server starts")
	var initialized=await http_request(server,{"jsonrpc":"2.0","id":0,"method":"initialize"})
	check(initialized.has("result"),"plugin HTTP session initialized")
	var calls={"plugin_standard":{},"plugin_list":{},"plugin_read":{"id":"glow_ring","path":"plugin.json"},"plugin_create":{"id":"mcp_visual","template":"visual","title":"MCP visual"},"plugin_validate":{"id":"glow_ring"},"chart_plugins_set":{"plugins":d.raw.get("plugins",[]),"expected_revision":d.revision()}}
	var file=w.read("glow_ring","plugin.json")
	calls.plugin_write={"id":"glow_ring","path":"plugin.json","content":file.content+"\n","expected_revision":file.revision}
	for name in calls:
		var request={"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":name,"arguments":calls[name]}}
		check(server.validate_arguments(request.params).is_empty(),"MCP schema "+name)
		var reply=await http_request(server,request)
		check(reply.has("result") and not reply.result.get("isError",true),"MCP round trip "+name)
	var standard=api.call_tool("plugin_standard",{})
	check(JSON.stringify(standard).to_utf8_buffer().size()<12*1024,"standard index under 12 KB")
	for section in standard.sections:
		check(not api.call_tool("plugin_standard",{"section":section}).has("error"),"standard section "+section)
	check(not api.NAMES.any(func(n): return "trust" in n),"no MCP trust tool")
	check(server.validate_arguments({"name":"plugin_write","arguments":{"id":"x"}})!="","MCP required revision/content")
	server.queue_free(); await process_frame

var http_session=""
func http_request(server, value: Dictionary) -> Dictionary:
	var http=HTTPRequest.new(); http.timeout=20; root.add_child(http)
	var headers=PackedStringArray(["Content-Type: application/json","Accept: application/json, text/event-stream"])
	if not http_session.is_empty(): headers.append("Mcp-Session-Id: "+http_session)
	http.request("http://127.0.0.1:%d/mcp" % server.port,headers,HTTPClient.METHOD_POST,JSON.stringify(value))
	var response=await http.request_completed
	for header in response[2]:
		if header.to_lower().begins_with("mcp-session-id:"): http_session=header.substr(15).strip_edges()
	var reply=JSON.parse_string(response[3].get_string_from_utf8()); http.queue_free()
	return reply if reply is Dictionary else {}
