## Real app smoke shared by P3/P4/P5. Optional fixture root, or real package path.
## --native-song-path=1 uses the unchanged production songs_dir beside the executable.
## --headless --audio-driver Dummy -s res://tests/builtin_demo_app_test.gd --
## --demo=shapes|motion|speed --songs-root=/absolute/external/songs
## Uses the existing working-copy menu entry when the later P6 index is absent.
extends SceneTree

class TestApp:
	extends "res://scripts/main.gd"
	var fixture_root := ""
	func songs_dir() -> String: return super.songs_dir() if fixture_root.is_empty() else fixture_root

const DEMOS := {"shapes":{"plugin":"shape_tracks","notes":10,"points":10},"motion":{"plugin":"note_motion","notes":3,"points":3},"speed":{"plugin":"fall_speed","notes":18,"points":28}}
const OPTIONAL := ["shape_tracks","note_motion","fall_speed"]
var checks := 0
var failures := 0
var app: TestApp
var selected := ""
var song_root := ""
var log_root := ""
var options := {}

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: "+label)

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=",true,1)
		if parts.size()==2: options[parts[0]]=parts[1]
	selected=str(options.get("demo","shapes"))
	song_root=str(options.get("songs-root",ProjectSettings.globalize_path("res://../songs")))
	_run.call_deferred()

func _audio_is_dummy() -> bool:
	# Godot consumes engine flags before exposing OS.get_cmdline_args().
	return AudioServer.get_driver_name()=="Dummy"

func _log_files() -> Array:
	var result := []
	for name in DirAccess.get_files_at(log_root):
		if name.ends_with(".json"): result.append(name)
	return result

func _check_log(before: Array,song: String,plugin: String) -> void:
	var found := []
	for name in _log_files():
		if name in before: continue
		var value: Variant=SU.load_json(log_root.path_join(name))
		if value is Dictionary and value.get("song","")==song: found.append({"name":name,"data":value})
	check(found.size()==1,"real completed app run writes one playlog: "+song)
	if found.size()!=1: return
	var item: Dictionary=found[0]
	check(item.data.reason=="result" and item.data.stats.score==1010000 and item.data.autoplay,"playlog retains full-score autoplay result")
	check(str(item.name).begins_with(song.replace("/","__")+"_"),"nested song filename is safely flattened")
	var ids := []
	for identity in item.data.get("plugins",[]): ids.append(str(identity).get_slice("@",0))
	check((plugin in ids and ids.size()==5) if not plugin.is_empty() else ids.size()==4,"playlog records only the current scope identity")

func _run_core(core: GameCore) -> void:
	var end: float=core.end_time
	for i in int(ceil(end*240.0))+2: core.update(float(i)/240.0)

func _standard_only(registry: PluginRegistry) -> bool:
	if registry.manifests.size()!=4: return false
	for id in PluginRegistry.STANDARD_IDS:
		if not registry.manifests.has(id): return false
	return true

func _run() -> void:
	check(DisplayServer.get_name()=="headless","smoke must run headless")
	check(_audio_is_dummy(),"smoke requires the actual Dummy audio driver")
	check(DEMOS.has(selected),"known demo parameter")
	check(song_root.is_absolute_path() and DirAccess.dir_exists_absolute(song_root),"absolute external songs root exists")
	if failures: _finish(); return
	var relative := "_plugin_demos/"+selected
	var folder := song_root.path_join(relative)
	check(FileAccess.file_exists(folder.path_join("chart.json")) and FileAccess.file_exists(folder.path_join("audio.wav")),"actual nested demo chart and audio exist")
	check(FileAccess.file_exists(song_root.path_join("_demo/audio.wav")),"ordinary B audio exists externally")
	if failures: _finish(); return
	log_root=OS.get_environment("CHARTER_PLAYLOG_DIR")
	if log_root.is_empty(): log_root=ProjectSettings.globalize_path("user://playlogs")
	check(DirAccess.make_dir_recursive_absolute(log_root)==OK,"isolated playlog folder is writable")
	if failures: _finish(); return
	AudioServer.set_bus_mute(0,true)
	app=TestApp.new()
	if options.get("native-song-path", "0") != "1": app.fixture_root=song_root
	else: check(app.songs_dir()==song_root and song_root==OS.get_executable_path().get_base_dir().path_join("songs"),"unmodified production path discovers the real package songs beside its executable")
	# Force safe launch even if this test HOME already has preferences.
	app.args["mute"]="1"; app.args["windowed"]="1"; app.args["autoplay"]="1"
	app.settings.keyguard=false; app.settings.fullscreen=false
	root.add_child(app); app.set_process(false)
	app.audio.set_muted(true); app.settings.autoplay=true; app.settings.hit_kind="off"
	var plugin: String=DEMOS[selected].plugin
	check(_standard_only(PluginRegistry.standard()),"immutable standard catalog starts with exactly four packages")
	var before := _log_files()
	check(app._test_working_copy(relative),"actual working-copy start accepts the nested path")
	check(app.state=="playing" and not app.screens.PluginTrust.visible,"built-in tier script starts without the trust UI")
	if app.state!="playing": await _cleanup(); _finish(); return
	check(app.songs_dir()==song_root and app.meta.dir==relative,"actual app retains external root and nested song identity")
	check(app.audio.music.stream is AudioStreamWAV and app.audio._running and AudioServer.is_bus_mute(0),"actual audio stream loads and starts silently")
	check(app._song_plugins!=null and not app._song_plugins.report.requires_trust and app._song_plugins.report.script_ids.is_empty(),"built-in packages need no external-script permission")
	check(PluginRegistry.builtins().manifests[plugin].tier=="script","selected optional built-in really is script-tier")
	check(app.core.registry.manifests.has(plugin) and app.R.registry.manifests.has(plugin),"actual GameCore and renderer use the selected scope")
	check(app.core.registry.manifests.size()==5,"scope contains four standards plus only its selected optional package")
	for id in OPTIONAL:
		if id!=plugin: check(not app.core.registry.manifests.has(id),"unselected optional package stays inactive: "+id)
	check(_standard_only(PluginRegistry.standard()),"selection never contaminates the standard catalog")
	check(app.core.notes.size()==int(DEMOS[selected].notes) and app.core.chart.warnings.is_empty(),"actual demo note count and zero validation warnings")
	check(app._pending_play.is_empty() and app._plugin_status.text.is_empty(),"startup has no pending trust or degraded notice")
	# Exercise the real app -> renderer frame path before deterministic core clock stepping.
	app._process(0.0)
	check(app.R.f.play and app.R.f.chart==app.core.chart,"real app sends the selected chart to its renderer")
	var renderer_ref: WeakRef=weakref(app.R); var session_ref: WeakRef=weakref(app._song_plugins)
	_run_core(app.core)
	var demo_stats := app.core.stats.duplicate(true)
	check(app.state=="result" and not app.core.playing,"actual GameCore finished signal enters app result state")
	check(demo_stats.total==int(DEMOS[selected].points) and demo_stats.PERFECT==demo_stats.total and demo_stats.MISS==0 and demo_stats.score==1010000,"selected demo autoplay is full score")
	_check_log(before,relative,plugin)
	await create_timer(3.4).timeout
	check(app.screens.Result.visible,"actual result panel opens after its existing animation delay")
	check(app._song_plugins==null and session_ref.get_ref()==null,"result teardown releases the selected session")
	check(renderer_ref.get_ref()==null,"result teardown destroys the selected renderer")
	check(not app._uses_song_plugins and not app._result_backdrop and _standard_only(app.R.registry),"result uses a clean standard renderer without plugin callbacks")
	# Ordinary original DEMO B uses the real existing menu entry and audio loader.
	app._quit_to_songs(); app.sel_i=0; app.sel_d=0
	before=_log_files(); app._play_selected()
	check(app.state=="playing" and app.meta.dir=="demo","ordinary unmodified B starts after selected demo")
	check(_standard_only(app.R.registry) and _standard_only(app.core.registry),"B has only the four standard providers")
	check(not app._uses_song_plugins and app._plugin_status.text.is_empty(),"B has no stale plugin mode or warning")
	var clean := GameCore.new(); check(clean.load_chart(ChartLib.demo()),"clean ordinary B reference loads")
	clean.autoplay=true; clean.playing=true; _run_core(clean)
	_run_core(app.core)
	var b_stats := app.core.stats.duplicate(true)
	check(b_stats==clean.stats,"B after plugin is numerically identical to clean B")
	check(b_stats.score==1010000 and b_stats.MISS==0 and b_stats.total==242,"ordinary B is 242/242 PERFECT full score")
	_check_log(before,"demo","")
	clean=null
	await create_timer(3.4).timeout
	check(app.screens.Result.visible and app._song_plugins==null,"ordinary result also releases its empty song session")
	check(_standard_only(PluginRegistry.standard()),"standard catalog remains exactly four at end")
	print("BUILTIN_DEMO_RESULT ",JSON.stringify({"demo":selected,"dir":relative,"songs_root":song_root,"plugin":plugin,"demo_stats":demo_stats,"ordinary_b":b_stats}))
	await _cleanup(); _finish()

func _cleanup() -> void:
	if is_instance_valid(app): app.queue_free(); app=null
	await process_frame
	await process_frame

func _finish() -> void:
	if failures==0: check(checks==(45 if options.get("native-song-path", "0")=="1" else 44),"all expected smoke assertions executed")
	print("BUILTIN DEMO APP ",selected,": ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
