extends RefCounted
## Data-only authoring. Never open a SongPluginSession or instance pack scripts here.
const LIMIT = 256 * 1024
const TEXT = ["gd", "gdshader", "md", "txt", "json"]
var doc

func folder() -> String:
	return ProjectSettings.globalize_path(doc.path).get_base_dir() if doc != null and not doc.path.is_empty() else ""

static func valid_id(id: String) -> bool:
	var pattern=RegEx.new(); pattern.compile("^[a-z][a-z0-9_.-]*$")
	return pattern.search(id)!=null and id.length()<=100

func location(id: String, path: String, builtin=false) -> Dictionary:
	if not valid_id(id) or not PluginPack.safe_relative(path) or path.get_extension().to_lower() not in TEXT: return {"error":"unsafe plugin text path"}
	var base="res://plugins/builtin" if builtin else folder().path_join("plugins")
	if not builtin and folder().is_empty(): return {"error":"open a song first"}
	var checked=PluginPack.root_path(base.path_join(id))
	if not checked.errors.is_empty(): return {"error":"; ".join(checked.errors)}
	var current=str(checked.path)
	for part in path.split("/"):
		var parent=DirAccess.open(current)
		if parent==null or parent.is_link(part): return {"error":"missing folder or symlink in plugin path"}
		current=current.path_join(part)
	return {"path":current}

func is_builtin(id: String) -> bool:
	return PluginRegistry.builtins().manifests.has(id)

func read(id: String, path: String) -> Dictionary:
	var target=location(id,path,is_builtin(id))
	if target.has("error"): return target
	var file=FileAccess.open(target.path,FileAccess.READ)
	if not file: return {"error":"cannot read plugin text"}
	if file.get_length()>LIMIT: return {"error":"plugin text exceeds 256 KB"}
	var bytes=file.get_buffer(file.get_length()); file.close()
	if bytes.has(0): return {"error":"not UTF-8 text"}
	var text=bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes: return {"error":"not UTF-8 text"}
	return {"id":id,"path":path,"content":text,"revision":text.sha256_text(),"read_only":is_builtin(id),"data_only":true}

func write(id: String, path: String, content: String, expected: String) -> Dictionary:
	if doc.busy: return {"error":"version operation in progress"}
	if is_builtin(id): return {"error":"built-in plugins are read-only"}
	if content.to_utf8_buffer().size()>LIMIT or content.to_utf8_buffer().has(0): return {"error":"plugin text must be UTF-8, at most 256 KB"}
	var target=location(id,path)
	if target.has("error"): return target
	var exists=FileAccess.file_exists(target.path)
	var actual=FileAccess.get_sha256(target.path) if exists else ""
	if expected!=actual: return {"error":"stale revision","revision":actual}
	var suffix=".bak-"+str(Time.get_ticks_usec())
	var backup=str(target.path)+suffix if exists else ""
	if exists and DirAccess.copy_absolute(target.path,backup)!=OK: return {"error":"backup failed"}
	var temp=str(target.path)+".charter-tmp-"+str(Time.get_ticks_usec())
	if FileAccess.file_exists(temp) or DirAccess.open(str(target.path).get_base_dir()).is_link(temp.get_file()): return {"error":"unsafe temporary file"}
	var file=FileAccess.open(temp,FileAccess.WRITE)
	if not file: return {"error":"cannot write temporary plugin text"}
	file.store_string(content); file.close()
	# Recheck after backup and temp write, including every ancestor link.
	var again=location(id,path)
	if again.has("error") or (FileAccess.get_sha256(target.path) if FileAccess.file_exists(target.path) else "")!=actual:
		DirAccess.remove_absolute(temp); return {"error":"stale revision or unsafe path while saving"}
	if DirAccess.rename_absolute(temp,target.path)!=OK: return {"error":"atomic replacement failed"}
	var result={"id":id,"path":path,"revision":FileAccess.get_sha256(target.path),"backup":backup,"history":"Saved in the song working tree; Save Version commits plugins too."}
	result.merge(trust_state())
	return result

func trust_state() -> Dictionary:
	var hash=PluginPack.content_hash(folder())
	if not hash.errors.is_empty(): return {"trusted":false,"trust_notice":"Cannot hash this pack: "+"; ".join(hash.errors)}
	var session=SongPluginSession.new(); session._hash=hash.hash
	var store=session._read_trust()
	var trusted=store.errors.is_empty() and session._find_decision(store.data)==true
	session.close()
	return {"trusted":trusted,"content_hash":hash.hash,"trust_notice":"Current pack hash is trusted." if trusted else "Script pack is untrusted; the player/author must re-trust. Editing any pack file changes its hash."}

func files_at(base: String, relative="", depth=0, text_only=true) -> Array:
	var result=[]
	if depth>8: return result
	var dir=DirAccess.open(base.path_join(relative))
	if dir==null: return result
	for name in dir.get_files():
		var path=relative.path_join(name) if not relative.is_empty() else name
		if not dir.is_link(name) and (not text_only or name.get_extension().to_lower() in TEXT) and not name.contains(".bak-") and not name.contains(".charter-tmp-"): result.append(path)
	for name in dir.get_directories():
		if not dir.is_link(name): result.append_array(files_at(base,relative.path_join(name),depth+1,text_only))
	result.sort()
	return result.slice(0,128)

func list_plugins() -> Dictionary:
	if folder().is_empty(): return {"plugins":[],"empty":"Open a song to author plugins."}
	var rows=[]; var local=folder().path_join("plugins")
	var ids=Array(DirAccess.get_directories_at(local)) if DirAccess.dir_exists_absolute(local) else []
	var builtin=PluginRegistry.builtins().manifests
	for id in builtin: ids.append(id)
	ids.sort()
	for id in ids.slice(0,128):
		var built=builtin.has(id)
		var result=read(id,"plugin.json")
		var manifest=JSON.parse_string(result.get("content",""))
		if not manifest is Dictionary: manifest={"id":id,"title":id,"version":"?","tier":"declarative"}
		var row=manifest.duplicate(true); row.id=id; row.read_only=built; row.standard=id in PluginRegistry.STANDARD_IDS
		row.bound=row.standard or doc.raw.get("plugins",[]).any(func(p): return p is Dictionary and p.get("id")==id)
		var base="res://plugins/builtin/"+id if built else local.path_join(id)
		row.files=files_at(base,"",0,false); row.text_files=files_at(base)
		var checked=validate_plugin(id,false)
		row.status=checked.status; row.diagnostics=checked.diagnostics
		if JSON.stringify(rows).to_utf8_buffer().size()+JSON.stringify(row).to_utf8_buffer().size()>LIMIT-2048: break
		rows.append(row)
	return {"plugins":rows,"revision":doc.revision(),"data_only":true,"limit":LIMIT,"truncated":rows.size()<ids.size()}

func diagnostic(message: String, file="plugin.json", line=1, severity="error") -> Dictionary:
	return {"message":message,"file":file,"line":line,"severity":severity}

func validate_plugin(id="", check_syntax=true) -> Dictionary:
	if folder().is_empty(): return {"error":"open a song first"}
	var chart=doc.raw.duplicate(true); var diagnostics=[]; var manifest={}
	if not id.is_empty():
		var text=read(id,"plugin.json")
		if text.has("error"): return {"status":"errors","diagnostics":[diagnostic(text.error)]}
		var parser=JSON.new()
		if parser.parse(text.content)!=OK: return {"status":"errors","diagnostics":[diagnostic(parser.get_error_message(),"plugin.json",parser.get_error_line())]}
		var checked=PluginLoader.validate_manifest(parser.data)
		for error in checked.errors: diagnostics.append(diagnostic(str(error)))
		if not diagnostics.is_empty(): return {"status":"errors","diagnostics":diagnostics}
		manifest=checked.manifest
		if manifest.id!=id: return {"status":"errors","diagnostics":[diagnostic("Folder/id mismatch")]}
		var bindings=chart.get("plugins",[]).duplicate(true) if chart.get("plugins",[]) is Array else []
		bindings=bindings.filter(func(p): return p is Dictionary and p.get("id")!=id)
		if not id in PluginRegistry.STANDARD_IDS: bindings.append({"id":id,"version":manifest.version})
		chart.plugins=bindings
	var session=SongPluginSession.new()
	var report=session.prepare(folder(),chart,folder().get_file())
	for error in report.errors: diagnostics.append(diagnostic(str(error)))
	# Only game-owned built-ins and validated declarative providers are installed.
	# Script providers remain disabled even for trusted packs; this is a syntax/data check.
	if report.errors.is_empty():
		var scope=session._builtin_scope(); var paths=[]
		for item in session._ordered:
			if item.tier=="script": scope.begin_plugin(item); scope.end_plugin()
			if item.tier=="declarative" and item.id in session._enabled_ids(): paths.append(str(session._folders[item.id]).path_join("plugin.json"))
		var installed=PluginLoader.new().load_paths(paths,scope,false)
		for error in installed.errors: diagnostics.append(diagnostic(str(error)))
		var normalized=ChartLib.validate(session.chart_data.duplicate(true),scope)
		for warning in normalized.get("warnings",[]): diagnostics.append(diagnostic(str(warning),"chart.json",1,"warning"))
		scope.dispose()
	var state=trust_state() if not report.script_ids.is_empty() else {"trusted":false}
	var relevant_scripts=report.script_ids.duplicate() if id.is_empty() else []
	if not id.is_empty():
		var pending=[id]; var visited={}
		while not pending.is_empty() and visited.size()<128:
			var current=pending.pop_back()
			if visited.has(current): continue
			visited[current]=true
			var item=session._selected.get(current,{})
			if current in report.script_ids: relevant_scripts.append(current)
			for dependency in item.get("requires",[]): pending.append(dependency.id)
	var snapshot={"path":"","errors":[]}
	if check_syntax and state.trusted: snapshot=PluginPack.snapshot(folder(),state.content_hash)
	for error in snapshot.errors: diagnostics.append(diagnostic(str(error)))
	for script_id in report.script_ids:
		var script_manifest=session._selected.get(script_id,{})
		if not state.trusted:
			diagnostics.append(diagnostic("script not checked: pack not trusted",str(script_manifest.get("entry","")),1,"notice"))
		elif check_syntax and snapshot.errors.is_empty():
			# --check-only parses trusted source in a child without installing providers.
			var trusted_folder=str(snapshot.path).path_join("plugins/"+script_id)
			var checked_files=files_at(trusted_folder)
			for path in checked_files:
				if path.get_extension().to_lower()!="gd": continue
				var output=[]
				var code=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--check-only","--script",trusted_folder.path_join(path)]),output,true)
				if code!=0:
					var message="".join(output); var line=1
					var pattern=RegEx.new(); pattern.compile("\\.gd:(\\d+)")
					var found=pattern.search(message)
					if found: line=int(found.get_string(1))
					diagnostics.append(diagnostic(message.left(4096),path,line))
	if not str(snapshot.path).is_empty(): PluginPack.remove_snapshot(snapshot.path)
	var errors=diagnostics.filter(func(d): return d.severity=="error")
	var status="ok" if errors.is_empty() else "errors"
	if not errors.is_empty() and errors.any(func(d): return "dependency" in d.message.to_lower() or "missing or unsafe plugin" in d.message.to_lower()): status="missing-dependency"
	if errors.is_empty() and not relevant_scripts.is_empty() and not state.trusted: status="script-untrusted"
	session.close()
	return {"status":status,"diagnostics":diagnostics.slice(0,128),"data_only":true,"script_instances":0}

func set_bindings(plugins, expected: String, author="user") -> Dictionary:
	if not plugins is Array or plugins.size()>64: return {"error":"plugins must be an array of at most 64 bindings"}
	if expected!=doc.revision(): return {"error":"stale revision","revision":doc.revision()}
	var chart=doc.raw.duplicate(true); chart.plugins=plugins
	var session=SongPluginSession.new(); var report=session.prepare(folder(),chart,folder().get_file())
	var errors=report.errors.duplicate(); session.close()
	if not errors.is_empty(): return {"error":"plugin binding refused","diagnostics":errors}
	return doc.edit({"expected_revision":expected,"label":"插件绑定","ops":[{"target":"plugins","value":plugins}]},author)

func create(id: String, template: String, title: String) -> Dictionary:
	if doc.busy: return {"error":"version operation in progress"}
	if folder().is_empty() or not valid_id(id) or is_builtin(id): return {"error":"open a song and choose a unique safe plugin id"}
	if not template in ["visual","event","script"] or title.strip_edges().is_empty(): return {"error":"choose visual/event/script and a title"}
	var root=PluginPack.root_path(folder())
	if not root.errors.is_empty(): return {"error":"; ".join(root.errors)}
	var plugins=folder().path_join("plugins"); var parent=DirAccess.open(folder())
	if parent.is_link("plugins"): return {"error":"symlink plugins folder refused"}
	if DirAccess.dir_exists_absolute(plugins.path_join(id)) or FileAccess.file_exists(plugins.path_join(id)): return {"error":"plugin already exists"}
	if DirAccess.make_dir_recursive_absolute(plugins.path_join(id))!=OK: return {"error":"cannot create plugin folder"}
	var manifest={"id":id,"version":"1.0.0","api":PluginRegistry.API,"tier":"declarative","title":title,"author":"Charter author","description":"Created in Charter","provides":{},"fields":[],"assets":[],"entry":null,"requires":[{"id":"standard_render","version":"1.0.0"}]}
	var field=id.replace("-","_").replace(".","_")
	if field!=id: field+="_"+id.sha256_text().substr(0,8)
	if template=="visual":
		manifest.provides={"flags":[id],"elements":[id]}
		manifest.fields=[{"path":"notes[]."+field,"type":"number","unit":"keys","min":0,"max":4,"step":0.25,"default":0,"doc":"Outer halo radius in keys; zero hides the halo."}]
		manifest.definitions={"flags":{id:{"field":field}},"elements":{id:{"kind":"glow_ring","field":field,"radius":"value","opacity":"alpha","color":[0.42,0.78,1,0.85],"width":2,"order":41}}}
	elif template=="event":
		# API 1 declarative tier cannot define arbitrary event callbacks. Standard
		# tween/impulse syntax targets this declared channel instead.
		manifest.provides={"channels":[id]}
		manifest.fields=[{"path":"fx[]."+field,"type":"number","unit":"ratio","min":0,"max":1,"step":0.05,"default":0,"doc":"Preview strength. Use standard tween/impulse events with ch="+id}]
		manifest.definitions={"channels":{id:{"default":0,"min":0,"max":1}}}
	else:
		manifest.tier="script"; manifest.entry="entry.gd"; manifest.provides={"elements":[id]}
		var source="extends RefCounted\n\n# Trusted pack contract; author trust is required before the game loads this.\nstatic func install(registry: PluginRegistry, _manifest: Dictionary, _folder: String) -> void:\n\tregistry.register(\"elements\", \"%s\", {\"phase\": \"plugin.%s\", \"order\": 43, \"additive\": true, \"callback\": draw})\n\nstatic func draw(_renderer, _canvas: CanvasItem) -> void:\n\tpass\n\nstatic func teardown(_registry: PluginRegistry) -> void:\n\tpass\n" % [id,id]
		var entry=write(id,"entry.gd",source,"")
		if entry.has("error"): return entry
	var result=write(id,"plugin.json",JSON.stringify(manifest,"  ")+"\n","")
	if result.has("error"): return result
	result["validation"]=validate_plugin(id)
	return result

## Called only by the human confirmation button, deliberately absent from MCP.
func author_trust() -> Dictionary:
	var chart=doc.raw.duplicate(true); var bindings=chart.get("plugins",[]).duplicate(true)
	for row in list_plugins().get("plugins",[]):
		if not row.read_only and row.get("tier")=="script" and not bindings.any(func(p): return p.id==row.id): bindings.append({"id":row.id,"version":row.version})
	chart.plugins=bindings
	var session=SongPluginSession.new(); var report=session.prepare(folder(),chart,folder().get_file())
	var allowed=report.errors.is_empty() and session.remember_trust(true)
	var errors=report.errors.duplicate(); session.close()
	return {"trusted":allowed,"errors":errors,"notice":"Editing pack contents changes the hash; re-trust before the next play."}
