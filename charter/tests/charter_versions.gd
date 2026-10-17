extends SceneTree
const Document=preload("res://document.gd")
const Tools=preload("res://tools.gd")
var failures=0
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures+=1
func _init() -> void: run.call_deferred()
func run() -> void:
	AudioServer.set_bus_mute(0,true); KB.set_layout("ansi")
	var dir=ProjectSettings.globalize_path("res://evidence/version-test-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(dir)
	var source=ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json").simplify_path()
	DirAccess.copy_absolute(source,dir.path_join("chart.json"))
	# Variant with identical notes and different lights (tints shifted), written next to the temp repo.
	var variant_dir=dir+"-variant"; DirAccess.make_dir_recursive_absolute(variant_dir)
	# lean like the committed main branch (a saved chart drops default fields such as nw = 1), so only tints differ
	var variant_chart=Document.lean(JSON.parse_string(FileAccess.get_file_as_string(source)))
	for e in variant_chart.lights:
		if e.has("tint"): e.tint=(int(e.tint)+1)%10
	var variant=variant_dir.path_join("chart.json")
	var vf=FileAccess.open(variant,FileAccess.WRITE); vf.store_string(JSON.stringify(variant_chart)); vf.close()
	var doc=Document.new(); doc.open(dir.path_join("chart.json")); var versions=doc.version_store(); var api=Tools.new(); api.doc=doc
	check(not api.call_tool("versions",{}).enabled,"read versions does not initialize")
	check(not versions.enabled(),"no implicit repo")
	check(not versions.initialize().has("error"),"explicit temp repo initialization")
	check(versions.commit("blocked").has("error"),"MCP commit opt-in enforced")
	check(not versions.commit("Initial original",false).has("error"),"initial user commit in temp copy")
	var imported=versions.import_variant(variant,"fable2")
	check(not imported.has("error"),"variant import branch without source mutation: "+JSON.stringify(imported))
	if imported.has("error"): quit(1); return
	var first_variant=variant
	check(not versions.import_variant(first_variant,"fable").has("error"),"first variant imported on a separate temporary branch")
	check(versions.git(["branch","--show-current"]).text=="main","import does not switch working branch")
	var diff=api.call_tool("diff",{"base":"main","other":"fable2"})
	var note_changes=0; var light_changes=0
	for change in diff.get("changes",[]):
		if change.target=="notes": note_changes+=1
		if change.target=="lights": light_changes+=1
	check(note_changes==0 and light_changes>0,"known variants have identical notes and changed lights: "+JSON.stringify(diff.get("counts",{})))
	var before=doc.revision()
	check(api.call_tool("notes",{"version":"fable2","from":"44.1","to":"45.1"}).notes.size()>0,"version read without switching")
	check(doc.revision()==before,"version read preserves working chart")
	check(not versions.branch_create("alternative").has("error"),"create writing")
	check(not versions.rename_branch("alternative","renamed").has("error"),"rename writing")
	check(versions.delete_branch("main",true).has("error") and versions.delete_branch("renamed",false).has("error"),"branch deletion guards")
	check(not versions.delete_branch("renamed",true).has("error"),"confirmed non-current deletion")
	# Synthetic seams allow an exact take/undo round trip independent of legacy charts.
	var synthetic={"bpm":120,"lights":[{"t":0,"id":1,"type":"on","x":0.5,"w":0.8,"a":0,"auto":true}],"notes":[{"t":4,"light":1,"u":0.5,"k":5,"kind":"tap","dur":0}],"fx":[]}
	doc.raw=synthetic; doc.refresh_core(); doc.saved_revision=""; doc.original=FileAccess.get_file_as_string(doc.path)
	var committed=versions.commit("Synthetic base",false)
	check(not committed.has("error"),"canonical saved commit: "+JSON.stringify(committed))
	check(Document.canonical(JSON.parse_string(FileAccess.get_file_as_string(doc.path)))==Document.canonical(doc.raw),"canonical JSON equality")
	check(Document.canonical(doc.raw)==Document.canonical(Document.sorted_value(doc.raw)),"stable canonical key order")
	versions.branch_create("synthetic")
	doc.edit({"expected_revision":doc.revision(),"ops":[{"target":"notes","op":"update","index":0,"value":{"t":5}}]})
	var changed=doc.revision(); var steps=doc.undo_stack.size()
	check(versions.branch_switch("synthetic").has("error"),"dirty branch switch refused")
	check(not versions.take_range("synthetic",3,6,doc.revision()).has("error"),"take range accepted")
	check(doc.raw.notes[0].t==4 and doc.undo_stack.size()==steps+1,"passage copied as one undo step")
	doc.undo(); check(doc.revision()==changed,"take range undo exact round trip")
	check(versions.take_range("synthetic",3,6,"stale").has("error"),"take range stale rejection")
	check(not DirAccess.dir_exists_absolute(source.get_base_dir().path_join(".git")),"real source repo remains absent")
	var receipt=FileAccess.open("res://evidence/versions.json",FileAccess.WRITE); receipt.store_string(JSON.stringify({"temp":dir,"failures":failures,"known_diff":diff.counts},"  ")); receipt.close()
	print("CHARTER_VERSIONS failures=",failures); quit(1 if failures else 0)
