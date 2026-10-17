extends SceneTree
const App=preload("res://app.gd")
class FixtureApp:
	extends "res://app.gd"
	var fixture_root=""
	func songs_root() -> String: return fixture_root if not fixture_root.is_empty() else super.songs_root()
var failures=0
var checks=0
var app
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
	AudioServer.set_bus_mute(0,true)
	root.position=Vector2i(-5000,-5000); root.size=Vector2i(1600,900)
	app=FixtureApp.new(); app.persist=false; app.silent=true; app.bridge.cli_enabled=false; root.add_child(app)
	await process_frame
	var temp=ProjectSettings.globalize_path("res://tests/out/scripts-visual-"+str(Time.get_ticks_usec()))
	copy_tree(ProjectSettings.globalize_path("res://../songs/_plugin_demos").simplify_path(),temp)
	var window=app.script_window
	check(not window.visible and not app.panes.scripts,"script window collapsed by default")
	var shortcut=InputEventKey.new(); shortcut.keycode=KEY_E; shortcut.ctrl_pressed=true; shortcut.shift_pressed=true; shortcut.pressed=true
	app._unhandled_key_input(shortcut)
	check(window.visible and app.scripts_b.active,"Ctrl+Shift+E toggles scripts")
	window.close(); check(not window.visible and not app.panes.scripts,"close updates remembered toggle")
	app.doc.open(temp.path_join("glow_ring/chart.json")); app._show_song_title()
	app.toggle_pane("scripts"); window.select_plugin("glow_ring")
	check(window.borderless and not app.popover.visible and not app.sheet.visible and not app.hint_card.visible,"caption inside frame and background overlays hidden")
	check(not window.details.tabs_visible and window.detail_tabs.tab_count==3,"one collapsible tab header")
	check(window.code.wrap_mode==TextEdit.LINE_WRAPPING_BOUNDARY,"JSON soft wraps")
	for id in ["fall_speed","note_motion","shape_tracks"]:
		window.select_plugin(id)
		check(not window.trust_button.visible and window.selected_row().read_only,"built-in never offers trust: "+id)
		window.confirm_trust(); check(not window.trust.visible,"built-in rejects trust dialog: "+id)
	window.select_plugin("glow_ring")
	check(window.code.text.contains('"glow_ring"') and window.code.editable,"plugin.json editable with code highlighting")
	var before=window.code.text; window.code.text=before+"\n"; window.changed_text()
	check(window.has_dirty() and "●" in window.tabs.get_tab_title(window.tabs.current_tab),"dirty tab and buffer")
	var save_key=InputEventKey.new(); save_key.keycode=KEY_S; save_key.ctrl_pressed=true; save_key.pressed=true
	window._unhandled_key_input(save_key); check(not window.has_dirty(),"file Ctrl+S action saves revision")
	var loaded=window.workspace.read("glow_ring","plugin.json")
	window.workspace.write("glow_ring","plugin.json",loaded.content+"\n",loaded.revision)
	window.code.text+="\n"; window.save_file()
	check(not window.pending_conflict.is_empty(),"external revision opens reload/overwrite choice")
	window.reload_conflict(); window.conflict.hide()
	check(not window.has_dirty(),"conflict reload adopts disk revision")
	loaded=window.workspace.read("glow_ring","plugin.json"); window.workspace.write("glow_ring","plugin.json",loaded.content+"\n",loaded.revision)
	window.code.text+="\n  "; window.save_file(); window.overwrite(); window.conflict.hide()
	check(not window.has_dirty() and window.workspace.read("glow_ring","plugin.json").content==window.code.text,"confirmed overwrite uses fresh revision and backup")
	window.select_plugin("glow_ring"); window.code.text=window.code.text.replace('"max": 4','"max": 6')
	window.changed_text()
	check(window.fields.get_child_count()>1 and window.fields.get_child(1).get_child(1).max_value==6,"live field preview follows unsaved manifest")
	window.save_file()
	window.size=Vector2i(1300,700); window.position=Vector2i(130,110); window.remember(); window.close(); window.show_workspace()
	check(window.size==Vector2i(1300,700) and window.position==Vector2i(130,110),"window geometry remembered")
	window.size=Vector2i(1400,760); window.position=Vector2i(100,80)
	var out=ProjectSettings.globalize_path("res://shots/scripts"); DirAccess.make_dir_recursive_absolute(out)
	for dims in [Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size=dims; await create_timer(0.3).timeout
		app.doc.open(temp.path_join("glow_ring/chart.json")); app._show_song_title(); window.refresh(); window.select_plugin("glow_ring")
		app.seek(4.0)
		window.details_toggle.button_pressed=true; window.details.visible=true; window.details.current_tab=1
		await shot(out,"glow-ring",dims)
		check(window.code.size.x>500 and window.code.size.y>180,"code area usable "+str(dims))
		check(window.fields.get_child_count()==2,"generated radius field "+str(dims))
		app.doc.open(temp.path_join("script_trust/chart.json")); app._show_song_title(); window.refresh(); window.select_plugin("trust_spark"); window.validate_selected()
		check(window.notice.text.contains("脚本包未信任") and not window.diagnostics.get_item_text(0).contains("pack not trusted"),"Chinese untrusted hint and diagnostics "+str(dims))
		window.select_file(window.file_names.find("entry.gd"))
		check(window.code.wrap_mode==TextEdit.LINE_WRAPPING_NONE,"GDScript keeps horizontal scrolling "+str(dims))
		window.select_file(window.file_names.find("plugin.json"))
		check(window.selected_row().status=="script-untrusted" and window.trust_button.visible,"untrusted script and human trust action "+str(dims))
		await shot(out,"script-untrusted",dims)
		window.details.current_tab=2
		window.standard.text=window.standard_source; window.standard.scroll_to_paragraph(0)
		await shot(out,"standard",dims)
		window.search_standard("install")
		check(window.standard_match>=0 and window.standard.text.contains("[bgcolor="),"searchable plugin standard "+str(dims))
		var first_match=window.standard_match; window.search_standard("install")
		check(window.standard_match>first_match,"standard search advances to next match "+str(dims))
	app.fixture_root=temp
	var launch=window.play_arguments()
	check(not launch.has("error") and launch.executable==OS.get_executable_path() and ProjectSettings.globalize_path("res://../game").simplify_path() in launch.arguments and "res://main.tscn" in launch.arguments and "--windowed" in launch.arguments and "--song=script_trust" in launch.arguments and "--from=4.0" in launch.arguments,"game play-test selects independent game project, scene, song, playhead and window mode")
	window.build_fields([{"path":"n","type":"number","min":0,"max":6,"step":0.25,"default":2},{"path":"e","type":"enum","enum":["a","b"],"default":"b"},{"path":"b","type":"boolean","default":true},{"path":"s","type":"string","default":"text"}])
	check(window.fields.get_child(1).get_child(1) is SpinBox and window.fields.get_child(2).get_child(1) is OptionButton and window.fields.get_child(3).get_child(1) is CheckBox and window.fields.get_child(4).get_child(1) is LineEdit,"number enum boolean string preview controls")
	app.light=true; app.apply_theme()
	check(window.background.color==preload("res://theme.gd").tokens(true).s1,"floating window follows light theme tokens")
	app.light=false; app.apply_theme()
	window.ask_claude(0)
	check(app.panes.assistant and app.assistant.composer.text.contains("trust_spark") and app.assistant.plugin_context.path=="plugin.json","Agent composer preloads plugin/file without sending")
	check(app.assistant.starter_prompt().contains("trust_spark"),"external Agent starter includes the unsent plugin request")
	print("CHARTER_PLUGINS_VISUAL checks=",checks," failures=",failures)
	app.queue_free(); await process_frame; await process_frame; await process_frame
	quit(1 if failures else 0)
func shot(out: String, name: String, dims: Vector2i) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var path=out.path_join("%s-%dx%d.png" % [name,dims.x,dims.y])
	var image=root.get_texture().get_image()
	check(image.get_size()==dims and image.save_png(path)==OK,"screenshot "+path.get_file())
