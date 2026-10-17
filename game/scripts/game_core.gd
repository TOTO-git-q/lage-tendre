## Compatibility facade; all behavior is supplied by registered plugins (API 1).
class_name GameCore
extends RefCounted

const MIN_OVERLAP = BuiltinGameData.MIN_OVERLAP
const HOME = BuiltinGameData.HOME
signal ripple(xl: float, level: float)
signal judged(grade: String, xl: float, dt: float)
signal cue_judged(cue: Dictionary, grade: String)
signal pressed(code: String, xl: float)
signal hold_end(note: Dictionary)
signal combo_break(combo: int)
signal finished(stats: Dictionary)
static var cut_windows := false         # 2026-10-18 owner: no midpoint cut -- in-track presses are never thrown away (was the CHUNITHM cut)
static var cluster_guard := false       # 2026-10-18 owner: slap guard off (it turned valid presses into strays)
static var cut_same_track := true       # 2026-10-16 replay of a real play: cut only between notes of the same track (MISS 129 -> 66)
static var cut_by_landing := true       # 2026-10-18: when the cut is on, it looks at where the notes land (one key wide)
static var snap := false                 # 2026-10-18 owner: no adsorption -- an early press outside GOOD is just a stray
static var regrade := true               # 2026-10-18: an early (past PERFECT) tap is provisional; a closer press before t+PERFECT re-judges it
static var fifo_compensate := true      # 2026-10-18: first come first served; skip to the next note when the oldest is past GREAT and the next is within PERFECT
static var cluster_s := SU.CLUSTER
static var cluster_reach := SU.CLUSTER_REACH

var registry: PluginRegistry
var _runtime: RefCounted

func _init(scope: PluginRegistry = null) -> void:
	registry = scope if scope != null else PluginRegistry.standard()
	_runtime = registry.service_script("game_session").new()
	_runtime.configure(registry)
	_runtime.ripple.connect(_forward_ripple)
	_runtime.judged.connect(_forward_judged)
	_runtime.cue_judged.connect(_forward_cue_judged)
	_runtime.pressed.connect(_forward_pressed)
	_runtime.hold_end.connect(_forward_hold_end)
	_runtime.combo_break.connect(_forward_combo_break)
	_runtime.finished.connect(_forward_finished)

var chart: Dictionary:
	get: return _runtime.chart
	set(value): _runtime.chart = value

var tl: Dictionary:
	get: return _runtime.tl
	set(value): _runtime.tl = value

var ids: Array:
	get: return _runtime.ids
	set(value): _runtime.ids = value

var notes: Array:
	get: return _runtime.notes
	set(value): _runtime.notes = value

var cues: Array:
	get: return _runtime.cues
	set(value): _runtime.cues = value

var chords: Array:
	get: return _runtime.chords
	set(value): _runtime.chords = value

var end_time: float:
	get: return _runtime.end_time
	set(value): _runtime.end_time = value

var stats: Dictionary:
	get: return _runtime.stats
	set(value): _runtime.stats = value

var down: Dictionary:
	get: return _runtime.down
	set(value): _runtime.down = value

var space_down: bool:
	get: return _runtime.space_down
	set(value): _runtime.space_down = value

var space_cue: Variant:
	get: return _runtime.space_cue
	set(value): _runtime.space_cue = value

var rel: Array:
	get: return _runtime.rel
	set(value): _runtime.rel = value

var hit_log: Array:
	get: return _runtime.hit_log
	set(value): _runtime.hit_log = value

var strays: Array:
	get: return _runtime.strays
	set(value): _runtime.strays = value

var autoplay: bool:
	get: return _runtime.autoplay
	set(value): _runtime.autoplay = value

var playing: bool:
	get: return _runtime.playing
	set(value): _runtime.playing = value

var clock_now: float:
	get: return _runtime.clock_now
	set(value): _runtime.clock_now = value

var stage: StageFx:
	get: return _runtime.stage
	set(value): _runtime.stage = value

var _hits: Array:
	get: return _runtime._hits
	set(value): _runtime._hits = value

var autoplay_extra: int:
	get: return _runtime.autoplay_extra
	set(value): _runtime.autoplay_extra = value

var autoplay_extra_ms: float:
	get: return _runtime.autoplay_extra_ms
	set(value): _runtime.autoplay_extra_ms = value

var debug_blocked: Array:
	get: return _runtime.debug_blocked
	set(value): _runtime.debug_blocked = value

var xp: Array:
	get: return _runtime.xp
	set(value): _runtime.xp = value

func _forward_ripple(xl: float, level: float) -> void:
	ripple.emit(xl, level)

func _forward_judged(grade: String, xl: float, dt: float) -> void:
	judged.emit(grade, xl, dt)

func _forward_cue_judged(cue: Dictionary, grade: String) -> void:
	cue_judged.emit(cue, grade)

func _forward_pressed(code: String, xl: float) -> void:
	pressed.emit(code, xl)

func _forward_hold_end(note: Dictionary) -> void:
	hold_end.emit(note)

func _forward_combo_break(combo: int) -> void:
	combo_break.emit(combo)

func _forward_finished(stats: Dictionary) -> void:
	finished.emit(stats)

func _new_stats(total: int) -> Dictionary:
	return _runtime._new_stats(total)

func _recalc() -> void:
	_runtime._recalc()

func _log_hit(dt: float, grade: String) -> void:
	_runtime._log_hit(dt, grade)

func _count(grade: String, d: int, crit := false) -> void:
	_runtime._count(grade, d, crit)

func _combo_for(grade: String) -> void:
	_runtime._combo_for(grade)

static func grade_of(d: float) -> String:
	return PluginRegistry.standard().service_script("game_session").grade_of(d)

func load_chart(raw) -> bool:
	return _runtime.load_chart(raw)

func reset_run() -> void:
	_runtime.reset_run()

func _cut_windows() -> void:
	_runtime._cut_windows()

func _one_key_reaches(p: Array, q: Array) -> bool:
	return _runtime._one_key_reaches(p, q)

func _fingering() -> void:
	_runtime._fingering()

func skip_before(t0: float) -> void:
	_runtime.skip_before(t0)

func light_states(t: float, reach: float) -> Array:
	return _runtime.light_states(t, reach)

func resolve_hit(xk: float, ts: float, k0: float, k1: float, code := ""):
	return _runtime.resolve_hit(xk, ts, k0, k1, code)

func press_key(code: String, ts: float):
	return _runtime.press_key(code, ts)

func _chord_begun(n: Dictionary, ts: float) -> void:
	_runtime._chord_begun(n, ts)

func _snap_target(ts: float, k0: float, k1: float):
	return _runtime._snap_target(ts, k0, k1)

func _land_snap(n: Dictionary) -> void:
	_runtime._land_snap(n)

func _catch(n: Dictionary, ts: float, st: Dictionary) -> bool:
	return _runtime._catch(n, ts, st)

func release_key(code: String, ts: float) -> void:
	_runtime.release_key(code, ts)

func _hold_kept(n: Dictionary, ts: float) -> bool:
	return _runtime._hold_kept(n, ts)

func _hold_step(n: Dictionary, ts: float) -> void:
	_runtime._hold_step(n, ts)

func release_all(ts: float) -> void:
	_runtime.release_all(ts)

func press_space(ts: float):
	return _runtime.press_space(ts)

func release_space(ts: float) -> void:
	_runtime.release_space(ts)

func _fail_cue(c: Dictionary) -> void:
	_runtime._fail_cue(c)

func _miss_note(n: Dictionary) -> void:
	_runtime._miss_note(n)

func _miss_cue(c: Dictionary) -> void:
	_runtime._miss_cue(c)

func _auto_key(n: Dictionary) -> String:
	return _runtime._auto_key(n)

func _extra_key(n: Dictionary, code: String) -> String:
	return _runtime._extra_key(n, code)

func _autoplay(ts: float) -> void:
	_runtime._autoplay(ts)

func update(ts: float) -> void:
	_runtime.update(ts)

func _record_cue_hit(cue: Dictionary, ts: float) -> void:
	_runtime._record_cue_hit(cue, ts)

