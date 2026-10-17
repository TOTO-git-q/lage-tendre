extends RefCounted
## Song-local git only. No implicit initialization, commits, remotes, or source imports.
var document_ref: WeakRef
var doc:
	get: return document_ref.get_ref()
	set(value): document_ref=weakref(value)
var allow_commit=false
var last_commit_size=0

func folder() -> String:
	return ProjectSettings.globalize_path(doc.path).get_base_dir().simplify_path()

func git(args: Array) -> Dictionary:
	var output=[]
	var argv=PackedStringArray(["--no-optional-locks","-C",folder()])
	for arg in args: argv.append(str(arg))
	var code=OS.execute("git",argv,output,true)
	return {"code":code,"text":"".join(output).strip_edges()}

func enabled() -> bool:
	return DirAccess.dir_exists_absolute(folder().path_join(".git"))

func initialize() -> Dictionary:
	if not doc.group_before.is_empty(): return {"error":"finish Claude turn first"}
	if enabled(): return list_versions()
	var result=git(["init","--initial-branch=main"])
	if result.code!=0: return {"error":result.text}
	var file=FileAccess.open(folder().path_join(".gitignore"),FileAccess.READ)
	var existing=file.get_as_text() if file else ""
	file=FileAccess.open(folder().path_join(".gitignore"),FileAccess.WRITE)
	if not file: return {"error":"cannot write song .gitignore"}
	file.store_string(existing+"\n# Charter local history\naudio.*\n*.bak-*\n*.charter-*\n*cache*\nanalysis.json\n")
	file.close()
	return list_versions()

func list_versions() -> Dictionary:
	if not enabled(): return {"enabled":false,"branches":[],"commits":[],"working_copy":doc.revision()}
	var branches=[]; var commits=[]
	var result=git(["for-each-ref","--format=%(refname:short)","refs/heads/"])
	if result.code!=0: return {"error":result.text}
	for line in result.text.split("\n",false): branches.append(line)
	result=git(["log","--all","-60","--format=%H%x09%aI%x09%an%x09%s"])
	if result.code==0:
		for line in result.text.split("\n",false):
			var fields=line.split("\t")
			if fields.size()>=4: commits.append({"id":fields[0],"time":fields[1],"author":fields[2],"message":fields[3]})
	return {"enabled":true,"branches":branches,"commits":commits,"current":git(["branch","--show-current"]).text,"working_copy":doc.revision(),"dirty":not clean(),"plugin_files":git(["status","--porcelain","--","plugins/"]).text.left(65536)}

func valid_ref(ref: String) -> bool:
	return not ref.is_empty() and not ref.begins_with("-") and not ref.contains(":") and not ref.contains("\n") and not ref.contains("\\")

func read(ref: String) -> Dictionary:
	if ref in ["","working"]: return {"chart":doc.raw.duplicate(true)}
	if not enabled() or not valid_ref(ref): return {"error":"unknown or invalid version"}
	var result=git(["show",ref+":chart.json"])
	var chart=JSON.parse_string(result.text) if result.code==0 else null
	if not chart is Dictionary or not chart.get("notes") is Array or not chart.get("lights") is Array: return {"error":"version has no valid chart.json", "version":ref}
	return {"chart":chart}

func clean() -> bool:
	return doc.revision()==doc.saved_revision and git(["status","--porcelain","--","chart.json","plugins/",".gitattributes"]).text.is_empty()

func branch_create(name: String) -> Dictionary:
	if not enabled() or not valid_ref(name): return {"error":"enable versions first; provide a valid branch name"}
	var check=git(["check-ref-format","--branch",name])
	if check.code!=0: return {"error":check.text}
	var result=git(["branch",name])
	return {"error":result.text} if result.code!=0 else list_versions()

func branch_switch(name: String) -> Dictionary:
	if not enabled() or not valid_ref(name) or not clean() or (not doc.group_before.is_empty() and doc.group_before.raw!=doc.raw): return {"error":"save/commit or undo working changes before switching"}
	# Only checkout the chart, never audio, analysis or unrelated user files.
	if not name in list_versions().get("branches",[]): return {"error":"branch not found"}
	for file in git(["ls-files"]).text.split("\n",false):
		if not file in ["chart.json",".gitignore",".gitattributes"] and not (file.begins_with("plugins/") and PluginPack.safe_relative(file)): return {"error":"repository tracks other files; switching is refused to preserve them"}
	var result=git(["switch",name])
	if result.code!=0: return {"error":result.text}
	var grouped=not doc.group_before.is_empty()
	var loaded=doc.open(doc.path)
	if grouped: doc.group_before={"raw":doc.raw.duplicate(true),"size":0}
	last_commit_size=0
	return loaded

func rename_branch(old: String, next: String) -> Dictionary:
	if not enabled() or not valid_ref(old) or not valid_ref(next): return {"error":"invalid branch"}
	var result=git(["branch","-m",old,next])
	return {"error":result.text} if result.code!=0 else list_versions()

func delete_branch(name: String, confirmed: bool) -> Dictionary:
	if not confirmed or not enabled() or name==git(["branch","--show-current"]).text or not valid_ref(name): return {"error":"confirmation required; cannot delete current branch"}
	var result=git(["branch","-D",name])
	return {"error":result.text} if result.code!=0 else list_versions()

func commit(message: String, from_mcp=true) -> Dictionary:
	if from_mcp and not allow_commit: return {"error":"user has not enabled Claude commits"}
	if from_mcp and not doc.allow_save: return {"error":"user has not enabled Claude saves"}
	if not enabled() or (not from_mcp and not doc.group_before.is_empty()): return {"error":"enable versions and finish active turn first"}
	if message.strip_edges().is_empty(): return {"error":"commit message required"}
	var protected=FileAccess.file_exists(doc.path.get_base_dir().path_join(".read-only"))
	var saved={"unchanged":true} if protected and doc.revision()==doc.saved_revision and FileAccess.get_file_as_string(doc.path)==doc.original else doc.save(from_mcp)
	if saved.has("error"): return saved
	# Even an unedited first version uses canonical formatting; regular no-op saves stay byte preserving.
	if not protected and saved.get("unchanged",false) and doc.original!=doc.canonical(doc.raw):
		doc.saved_revision=""
		saved=doc.save(from_mcp)
		if saved.has("error"): return saved
	var paths=["add","--","chart.json",".gitignore"]
	if DirAccess.dir_exists_absolute(folder().path_join("plugins")) or not git(["ls-files","--","plugins/"]).text.is_empty():
		var attributes=preserve_plugin_bytes()
		if attributes.has("error"): return attributes
		paths.append_array(["plugins/",".gitattributes"])
	var result=git(paths)
	if result.code!=0: return {"error":result.text}
	result=git(["-c","user.name="+("Claude" if from_mcp else "Charter user"),"-c","user.email=charter@localhost","commit","-m",message])
	if result.code!=0: return {"error":result.text}
	last_commit_size=doc.undo_stack.size()
	return list_versions()

func preserve_plugin_bytes() -> Dictionary:
	# Global autocrlf must not change a script/file revision when switching writings.
	var directory=DirAccess.open(folder())
	if directory==null or directory.is_link(".gitattributes"): return {"error":"unsafe song .gitattributes"}
	var path=folder().path_join(".gitattributes")
	var original=FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var rule="plugins/** -text"
	if Array(original.split("\n")).any(func(line): return line.strip_edges()==rule): return {}
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path,path+".bak-"+str(Time.get_ticks_usec()))!=OK: return {"error":"cannot back up song .gitattributes"}
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not file: return {"error":"cannot preserve plugin version bytes"}
	file.store_string(original+"\n# Charter: preserve plugin content revisions\n"+rule+"\n"); file.close()
	return {}

func plugin_diff(base: String, other: String) -> Dictionary:
	if base==other: return {"patch":"","untracked":"","truncated":false}
	if not enabled(): return {"files":[],"patch":""}
	if not valid_ref(base) or not valid_ref(other): return {"error":"invalid version"}
	var args=["diff","--no-ext-diff","--no-textconv"]
	if base!="working": args.append(base)
	if other!="working": args.append(other)
	if base=="working" and other!="working": args.append("-R")
	args.append_array(["--","plugins/"])
	var result=git(args)
	return {"error":result.text} if result.code!=0 else {"patch":result.text.left(65536),"truncated":result.text.length()>65536,"untracked":git(["ls-files","--others","--exclude-standard","--","plugins/"]).text.left(65536) if "working" in [base,other] else ""}

func import_variant(source: String, name: String) -> Dictionary:
	if not enabled() or not clean() or not valid_ref(name): return {"error":"commit working chart first and choose a new branch"}
	var check=git(["check-ref-format","--branch",name])
	if check.code!=0: return {"error":check.text}
	if git(["show-ref","--verify","refs/heads/"+name]).code==0: return {"error":"branch already exists"}
	var chart=JSON.parse_string(FileAccess.get_file_as_string(source))
	if not chart is Dictionary or not chart.get("notes") is Array or not chart.get("lights") is Array: return {"error":"invalid variant chart"}
	# A separate temporary index avoids switching or replacing the user's working chart.
	var temporary=folder().path_join(".git/charter-import.json")
	var file=FileAccess.open(temporary,FileAccess.WRITE); file.store_string(doc.canonical(chart)); file.close()
	var blob=git(["hash-object","-w",temporary])
	DirAccess.remove_absolute(temporary)
	if blob.code!=0: return {"error":blob.text}
	var blob_hash=blob.text.split("\n",false)[0].strip_edges()
	for line in blob.text.split("\n",false):
		if line.strip_edges().length()==40: blob_hash=line.strip_edges()
	var previous=OS.get_environment("GIT_INDEX_FILE")
	OS.set_environment("GIT_INDEX_FILE",folder().path_join(".git/charter-import-index"))
	var base=git(["read-tree","HEAD"])
	var update=git(["update-index","--add","--cacheinfo","100644",blob_hash,"chart.json"]) if base.code==0 else base
	var tree=git(["write-tree"]) if update.code==0 else update
	if previous.is_empty(): OS.unset_environment("GIT_INDEX_FILE")
	else: OS.set_environment("GIT_INDEX_FILE",previous)
	DirAccess.remove_absolute(folder().path_join(".git/charter-import-index"))
	if tree.code!=0: return {"error":tree.text}
	var parent=git(["rev-parse","HEAD"])
	var result=git(["-c","user.name=Charter user","-c","user.email=charter@localhost","commit-tree",tree.text,"-p",parent.text,"-m","Import writing: "+name])
	if result.code!=0: return {"error":result.text}
	result=git(["update-ref","refs/heads/"+name,result.text])
	return {"error":result.text} if result.code!=0 else list_versions()

func semantic(a: Dictionary, b: Dictionary, lo=0.0, hi=INF) -> Dictionary:
	var changes=[]; var bindings=[]; var heat={}; var counts={"added":0,"removed":0,"moved":0,"changed":0}
	for target in ["notes","lights","fx"]:
		var left=a.get(target,[]); var right=b.get(target,[]); var used={}; var pending=[]
		# Match identical objects first, independent of ordering and insertion offsets.
		var buckets={}
		for j in right.size():
			var key=signature(target,right[j])
			if not buckets.has(key): buckets[key]=[]
			buckets[key].append(j)
		for i in left.size():
			var key=signature(target,left[i])
			if buckets.has(key) and not buckets[key].is_empty():
				var matched=int(buckets[key].pop_front()); used[matched]=true
				if target=="notes" and (left[i].get("light")!=right[matched].get("light") or left[i].get("u")!=right[matched].get("u")) and left[i].t>=lo and left[i].t<hi:
					bindings.append({"target":"notes","kind":"changed","before_index":i,"after_index":matched,"before":left[i],"after":right[matched],"meaning":"carrier reseating; musical fields unchanged"})
			else: pending.append(i)
		for i in pending:
			var before=left[i]; var best=-1; var distance=INF
			for j in right.size():
				if used.has(j): continue
				var after=right[j]
				var identity="light" if target=="notes" else ("id" if target=="lights" else "ch")
				if before.get(identity)!=after.get(identity) or before.get("kind",before.get("type"))!=after.get("kind",after.get("type")): continue
				var delta=absf(float(before.t)-float(after.t))
				if delta<distance and delta<2.0: best=j; distance=delta
			var after=right[best] if best>=0 else null
			if best>=0: used[best]=true
			var kind="removed" if after==null else ("moved" if before.t!=after.t or (target=="notes" and (before.get("k")!=after.get("k") or before.get("u")!=after.get("u"))) else "changed")
			if (before.t>=lo and before.t<hi) or (after!=null and after.t>=lo and after.t<hi):
				changes.append({"target":target,"kind":kind,"before_index":i,"after_index":best,"before":before,"after":after,"time_delta_seconds":float(after.t)-float(before.t) if after!=null else 0})
		for j in right.size():
			if not used.has(j) and right[j].t>=lo and right[j].t<hi: changes.append({"target":target,"kind":"added","before":null,"after":right[j],"after_index":j})
	for change in changes:
		counts[change.kind]+=1
		var event=change.after if change.after!=null else change.before
		var bar=str(doc.position(event.t).bar); heat[bar]=heat.get(bar,0)+1
	return {"changes":changes,"carrier_reassignments":bindings,"counts":counts,"per_bar_heat":heat,"units":{"time_delta_seconds":"chart seconds","per_bar_heat":"changed musical/stage events per musical bar; carrier_reassignments listed separately"}}

func signature(target: String, event: Dictionary) -> String:
	var normalized=event.duplicate(true)
	# Fingering is explicit in v3: carrier reseating does not create a new musical note.
	if target=="notes" and normalized.has("k"):
		normalized.erase("light"); normalized.erase("u")
	return JSON.stringify(doc.sorted_value(normalized))

func take_range(ref: String, lo: float, hi: float, revision: String, author="user") -> Dictionary:
	if hi<=lo or not is_finite(lo) or not is_finite(hi): return {"error":"invalid range"}
	var version=read(ref)
	if version.has("error"): return version
	var ops=[]
	for target in ["notes","lights","fx"]:
		var current=doc.raw.get(target,[])
		for i in range(current.size()-1,-1,-1):
			if current[i].t>=lo and current[i].t<hi: ops.append({"target":target,"op":"delete","index":i})
		for item in version.chart.get(target,[]):
			if item.t>=lo and item.t<hi: ops.append({"target":target,"op":"add","value":item})
	return doc.edit({"expected_revision":revision,"label":"这段用 "+ref+" 的写法","ops":ops},author)
