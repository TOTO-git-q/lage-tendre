## Music + hit sounds + the master clock (port of [3] AUDIO).
## Chart time is derived from what is being HEARD: playback position + time since the last mix
## - output latency (the standard Godot rhythm-game sync), kept as a rate-1 linear model on the
## microsecond tick clock so key events can be converted with their own timestamps.
class_name AudioEngine
extends Node

var music := AudioStreamPlayer.new()
var preview := AudioStreamPlayer.new()
var sfx := {}
var muted := false
var debug := false

var song_offset := 0.0        # chart time at which audio sample 0 plays
var _started := false          # audio running (false during the lead-in before song_offset)
var _running := false
var _paused := false
var _lead_t0 := 0.0
var _lead_ticks := 0
var _a := 0.0                  # model: chart time _a at tick _ticks
var _ticks := 0
var _valid := false
var _cache := {}               # path -> AudioStream

func _ready() -> void:
	add_child(music)
	add_child(preview)
	music.bus = "Master"
	for name in ["wood", "deep", "crisp", "pedal", "pedalLR"]:
		var p := AudioStreamPlayer.new()
		p.stream = _make_sfx(name)
		p.max_polyphony = 8
		p.volume_db = linear_to_db(0.75 if name in ["wood", "deep", "crisp"] else 0.55)
		add_child(p)
		sfx[name] = p
	if muted:
		AudioServer.set_bus_mute(0, true)

func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)

# ---------------------------------------------------------------- loading
func load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	var ext := path.get_extension().to_lower()
	if ext == "mp3": s = AudioStreamMP3.load_from_file(path)
	elif ext == "ogg": s = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "wav": s = AudioStreamWAV.load_from_file(path)
	if s:
		if _cache.size() > 6: _cache.clear()
		_cache[path] = s
	return s

# ---------------------------------------------------------------- transport
## start the chart at chart time from_t (earlier objects are skipped by the game); audio sample 0 = chart offset
func play(stream: AudioStream, offset: float, from_t: float) -> void:
	stop()
	music.stream = stream
	song_offset = offset
	_running = true
	_paused = false
	_started = false
	_lead_t0 = from_t
	_lead_ticks = SU.ticks()
	_a = from_t
	_ticks = _lead_ticks
	_valid = true
	if from_t >= offset:
		music.play(from_t - offset)
		_started = true

func stop() -> void:
	music.stop()
	_running = false
	_started = false

func pause() -> void:
	if not _running: return
	_paused = true
	music.stream_paused = true

func resume() -> void:
	if not _running: return
	if _started:
		music.stream_paused = false
	else:
		_lead_t0 = _a
		_lead_ticks = SU.ticks()
	_paused = false
	_ticks = SU.ticks()       # the model continues from the frozen time

func is_paused() -> bool:
	return _paused

## called once per frame
func sync(now: int) -> void:
	if not _running or _paused: return
	if not _started:
		var t := _lead_t0 + (now - _lead_ticks) / 1e6
		_a = t; _ticks = now
		if t >= song_offset:
			music.play(t - song_offset)
			_started = true
		return
	var est := _a + (now - _ticks) / 1e6
	if not music.playing:                       # song ended before the chart: keep the tick clock
		_a = est; _ticks = now
		return
	var raw := music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() + song_offset
	var err := raw - est
	if debug and absf(err) > 0.03: print("[clock] snap %+.1f ms at t=%.3f" % [err * 1000.0, raw])
	_a = raw if absf(err) > 0.03 else est + err * 0.06
	_ticks = now

## chart time being heard at tick `usec` (key events use their own arrival tick)
func time_at(usec: int) -> float:
	if _paused: return _a
	return _a + (usec - _ticks) / 1e6

func now_time() -> float:
	return time_at(SU.ticks())

# ---------------------------------------------------------------- song preview (song select)
func preview_play(path: String, at: float) -> void:
	preview_stop()
	var s := load_stream(path)
	if s == null: return
	preview.stream = s
	preview.volume_db = -60.0
	preview.play(maxf(0.0, at))
	var tw := create_tween()
	tw.tween_property(preview, "volume_db", linear_to_db(0.55), 1.2)
	tw.tween_interval(12.0)
	tw.tween_property(preview, "volume_db", -60.0, 2.0)
	tw.tween_callback(preview.stop)

func preview_stop() -> void:
	preview.stop()

# ---------------------------------------------------------------- hit sounds (pre-rendered, played on keydown)
var _last_hit := 0

## key hit sound; presses within 25 ms (a chord) sound once -- stacked copies only phase and clip
func hit(kind: String) -> void:
	var now := SU.ticks()
	if now - _last_hit < 25000 or not sfx.has(kind):
		return
	_last_hit = now
	sfx[kind].play()

func pedal(yellow: bool) -> void:
	(sfx.pedalLR if yellow else sfx.pedal).play()

## Hit sounds are layered for weight: a short transient click (placement in time), a pitched body whose
## pitch drops quickly (the "thump" that gives mass), and a low layer; soft-clipped and normalised.
func _make_sfx(name: String) -> AudioStreamWAV:
	var sr := 44100
	var dur: float = {"wood": 0.16, "deep": 0.22, "crisp": 0.12, "pedal": 0.3, "pedalLR": 0.45}[name]
	var n := int(sr * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ph := 0.0
	var ph2 := 0.0
	var prev_noise := 0.0
	var peak := 0.0
	for i in n:
		var t := float(i) / sr
		var nz := rng.randf() * 2.0 - 1.0
		var hp := nz - prev_noise                 # crude high-pass: the click is all edge, no hiss body
		prev_noise = nz
		var v := 0.0
		match name:
			"wood":
				var f := 200.0 + 140.0 * exp(-t * 60.0)
				ph += TAU * f / sr
				v = 0.5 * hp * exp(-t * 900.0) + 0.75 * sin(ph) * exp(-t * 38.0) 					+ 0.25 * sin(TAU * 620.0 * t) * exp(-t * 90.0) + 0.12 * sin(TAU * 1180.0 * t) * exp(-t * 140.0) 					+ 0.35 * sin(TAU * 95.0 * t) * exp(-t * 25.0)
			"deep":
				var f := 85.0 + 120.0 * exp(-t * 45.0)
				ph += TAU * f / sr
				ph2 += TAU * 2.0 * f / sr
				v = 0.35 * hp * exp(-t * 1000.0) + 0.9 * sin(ph) * exp(-t * 20.0) + 0.22 * sin(ph2) * exp(-t * 60.0) 					+ 0.08 * nz * exp(-t * 70.0)
			"crisp":
				var f := 300.0 + 150.0 * exp(-t * 80.0)
				ph += TAU * f / sr
				v = 0.45 * hp * exp(-t * 1200.0) + 0.3 * sin(TAU * 1750.0 * t) * exp(-t * 55.0) 					+ 0.12 * sin(TAU * 3500.0 * t) * exp(-t * 90.0) + 0.5 * sin(ph) * exp(-t * 60.0)
			"pedal":
				v = 0.9 * sin(TAU * (55.0 + 90.0 * exp(-t * 30.0)) * t) * exp(-t * 11.0) + 0.12 * nz * exp(-t * 60.0)
			_:
				v = 0.85 * sin(TAU * (60.0 + 110.0 * exp(-t * 28.0)) * t) * exp(-t * 9.0) + 0.10 * sin(TAU * 1760.0 * t) * exp(-t * 8.0) + 0.08 * sin(TAU * 2640.0 * t) * exp(-t * 9.0)
		v = tanh(v * 1.3)
		var fade := clampf((dur - t) / 0.01, 0.0, 1.0)  # no click at the end
		buf[i] = v * fade
		peak = maxf(peak, absf(buf[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	var g := 0.89 / maxf(peak, 1e-6)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = data
	return w
