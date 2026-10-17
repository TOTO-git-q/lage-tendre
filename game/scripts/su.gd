## Shared constants and small helpers (port of [0] UTIL / CONSTANTS).
class_name SU

const LW := 1920.0
## The game clock.  Normally the wall clock; while Godot's Movie Maker records (--write-movie, --fixed-fps N, and -- --movie-fps=N) it is the
## frame clock, so audio, notes and frames stay locked together however slowly the frames are rendered.
static var _movie_fps := -1.0
static func ticks() -> int:
	if _movie_fps < 0.0:
		_movie_fps = 0.0
		if not Engine.get_write_movie_path().is_empty():
			_movie_fps = float(ProjectSettings.get_setting("editor/movie_writer/fps", 60))
			for x in OS.get_cmdline_user_args():           # Godot keeps --fixed-fps to itself: repeat it as --movie-fps=N
				if x.begins_with("--movie-fps="): _movie_fps = float(x.substr(12))
	if _movie_fps > 0.0:
		return 1000000 + int(round(Engine.get_process_frames() * 1e6 / _movie_fps))
	return Time.get_ticks_usec()
const LH := 1080.0
const JUDGE_Y := 0.88 * 1080.0
const APPROACH := 1.6                 # pedal cue pre-announce time (s)
# Judgement (after CHUNITHM / NOSTALGIA, tuned for a satisfying feel):
#   CRITICAL ±40 ms (shown as PERFECT, +1 % bonus)  PERFECT ±80 ms (full score)  GREAT ±120 ms (80 %)
#   GOOD ±160 ms (50 %); combo survives everything but MISS.  Presses earlier than the GOOD window are
#   simply ignored -- no early-press penalty.
# 2026-10-16: widened after a real run (75 % of hits within +-66 ms, 91 % within +-100): keyboard play on a
# dense two-hand chart is looser than a touch screen, so PERFECT covers +-80 and GREAT / GOOD give more credit
const WIN_CRITICAL := 0.040
const WIN_PERFECT := 0.080
const WIN_GREAT := 0.120
const WIN_GOOD := 0.160
const CREDIT_GREAT := 0.8
const SNAP_EARLY := 0.30           # an early press latches the next normal note of its light landing within this
const CREDIT_GOOD := 0.5
# every key counts as 1 key wider on each side (2026-10-16, was 0.6): a key right next to a light still hits it.
# With the dark G|H gap two keys wide, home-row keys still belong to one hand only; only the middle column of the
# other rows (Y / 6 / B) now reaches both hands' lights -- such a press simply takes the nearest note in time.
const KEY_PAD := 1.0 / 15.0
const LIGHT_OVER := 1.6 / 15.0          # lights may spill this far past the line ends (edge keys still reach them)
const HOLD_EARLY := 0.2               # a held pedal cue released this early (or 25 % of its length) still completes
# CHUNITHM-style (2026-10-16): two notes one key can reach split their windows at the midpoint between them
# ("縦連判定"), fixed by the chart -- a stray second key right after a hit can no longer eat the next note.  Notes this
# close in time are a chord and do not cut each other.  Holds score a combo tick every eighth note (two per beat,
# as Seaurchin's LongInjectionPerBeat; CHUNITHM: 16ths under 120 BPM, quarters from 240) instead of an end judgement.
const CHORD_EPS := 0.02
# a chord is played as quick successive taps (owner, 2026-10-16): once one of its notes is hit, the others take the
# next presses first for this long, graded from that first press -- two hands a little apart no longer miss
const CHORD_FOLLOW := 0.15
# smashing (owner, 2026-10-16: a player who slaps two keys for every note must still get an All Perfect): the other keys of
# one slap land within a few ms of the key that scored.  For this long after a hit, a press within CLUSTER_REACH keys of it
# (and of the slap's last key) may only take notes of the same moment (chord partners), never a later or earlier note.
# 12 ms = the smallest round window that swallows a slap whose second key trails by 8 ms; a longer one (20 ms+) starts to
# eat the other hand's note in real play (replay of the owner's log: MISS 66 -> 70 at 20 ms, 80 at 40 ms), and the
# reach keeps the guard to ONE hand: the other hand's key (3+ keys away) is never held back.
const CLUSTER := 0.012
const CLUSTER_REACH := 2.0
# hold ticks after UMIGURI (judgeWindows: long.limitJcr / limitJst / limitAtk = 3 / 6 / 9 frames): a tick is graded by
# how long no key was in the hold's light since the last tick -- <= 50 ms CRITICAL, <= 100 ms PERFECT, <= 150 ms GOOD,
# longer MISS.  The hold never breaks for good: keys back in the light earn the following ticks again.
const HOLD_GAP_CRIT := 0.05
const HOLD_GAP_PERFECT := 0.10
const HOLD_GAP_GOOD := 0.15
static func hold_tick(bpm: float) -> float:
	var beat := 60.0 / maxf(bpm, 1.0)
	return beat / 4.0 if bpm < 120.0 else (beat if bpm >= 240.0 else beat / 2.0)
const EPS := 1e-6
const KEY_UNIT := 1.0 / 15.0
const YEL := Color(1.0, 210.0 / 255.0, 74.0 / 255.0)
const HOLD_COL := Color(0.74, 0.87, 0.97)   # 2026-10-16: a touch less saturated (was 0.62, 0.88, 1.0)         # holds / slides: ice blue (CHUNITHM slides are blue; cool against the
                                                 # warm yellow protected notes and gold pedal, never read as a white beam)

static func ease_in_out(f: float) -> float:
	return 4.0 * f * f * f if f < 0.5 else 1.0 - pow(-2.0 * f + 2.0, 3.0) / 2.0

static func ease_out(a: float) -> float:
	return 1.0 - pow(1.0 - a, 3.0)

## sweep easing by name (VOEZ-style track motion): "inout" (default), "linear", "in", "out"
const EASES := ["inout", "linear", "in", "out"]
static func ease_by(name: String, f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	match name:
		"linear": return f
		"in": return f * f * f
		"out": return 1.0 - pow(1.0 - f, 3.0)
	return ease_in_out(f)

static func num(v, d: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else d

static func load_json(path: String, default_value = null):
	if not FileAccess.file_exists(path):
		return default_value
	var txt := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(txt)
	return default_value if v == null else v

static func save_json(path: String, value) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(value))
		f.close()
