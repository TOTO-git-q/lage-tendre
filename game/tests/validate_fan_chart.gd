## Trusted bridge: no submission Script is ever loaded. Uses the normal registry and GameCore.
extends SceneTree

func finish(result: Dictionary) -> void:
	print("FAN_RESULT ", JSON.stringify(result))
	quit(0)

func _init() -> void:
	KB.set_layout("ansi")
	var result := {"errors": [], "warnings": []}
	var folder: String = OS.get_cmdline_user_args()[0]
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("chart.json")))
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("info.json")))
	var stream: AudioStream = AudioStreamMP3.load_from_file(folder.path_join(info.audio)) if info.audio == "audio.mp3" else AudioStreamOggVorbis.load_from_file(folder.path_join(info.audio))
	if stream == null or stream.get_length() <= 0:
		result.errors.append("audio cannot be decoded or has no duration"); finish(result); return
	if float(info.preview) > stream.get_length(): result.errors.append("preview exceeds decoded audio duration")
	if not str(info.get("cover", "")).is_empty():
		var image := Image.load_from_file(folder.path_join(info.cover))
		if image == null or image.is_empty(): result.errors.append("cover cannot be decoded")
	var session := SongPluginSession.new()
	var prepared := session.prepare(folder, raw, "fan-made/" + folder.get_file())
	result.errors.append_array(prepared.errors)
	if not result.errors.is_empty(): session.close(); finish(result); return
	if not prepared.script_ids.is_empty():
		result.warnings.append("needs maintainer review: script-tier plugins disabled; autoplay covers only enabled declarative/built-in features")
		# A fresh isolated userdata root is supplied by Python. Record DENY, never ALLOW.
		if not session.remember_trust(false):
			result.errors.append("could not disable script plugins"); session.close(); finish(result); return
	var opened := session.open()
	result.errors.append_array(opened.errors)
	if not result.errors.is_empty(): session.close(); finish(result); return
	var chart := ChartLib.validate(session.chart_data, session.registry)
	if chart.is_empty(): result.errors.append("ChartLib returned no chart")
	else:
		# ChartLib normalizes invalid elements away and calls its diagnostics warnings.
		# Submissions must retain every note and have zero such diagnostics.
		for warning in chart.get("warnings", []): result.errors.append("ChartLib: " + str(warning))
		if chart.notes.size() != raw.notes.size(): result.errors.append("ChartLib dropped notes")
	if not result.errors.is_empty(): session.close(); finish(result); return
	var core := GameCore.new(session.registry)
	KB.set_layout("ansi")
	if not core.load_chart(session.chart_data):
		result.errors.append("GameCore could not load chart"); core = null; session.close(); finish(result); return
	if core.end_time > 1800:
		result.errors.append("chart exceeds 30 minute validation limit"); core = null; session.close(); finish(result); return
	var span := maxf(0.001, core.end_time - 1.4)
	if not core.notes.is_empty() and span > stream.get_length() + absf(float(raw.get("offset", 0))) + 0.1:
		result.errors.append("notes extend past decoded audio duration and chart offset")
	var human := {}
	for layout in KB.LAYOUT_NAMES:
		KB.set_layout(layout)
		var failures := 0
		for note in core.notes:
			var st := ChartLib.light_at(core.tl[note.light], note.t, session.registry)
			var x: float = st.x + (note.u - 0.5) * st.w
			var nearest := {}; var distance := INF
			for key in KB.list:
				if key.row == 2 and absf(key.cx - x) < distance:
					nearest = key; distance = absf(key.cx - x)
			if nearest.is_empty(): failures += 1; continue
			var hit = core.resolve_hit(nearest.cx, note.t, nearest.x0 / 15.0, (nearest.x0 + nearest.w) / 15.0, nearest.code)
			if hit == null or int(hit.id) != int(note.id): failures += 1
		human[layout] = failures
	KB.set_layout("ansi")
	var peak := 0; var start := 0
	for i in core.notes.size():
		while core.notes[i].t - core.notes[start].t >= 1.0: start += 1
		peak = maxi(peak, i - start + 1)
	result["notes"] = core.notes.size()
	result["duration"] = span
	result["nps"] = core.notes.size() / span
	result["peak_nps"] = peak
	result["human_key_failures"] = human
	core.autoplay = true; core.playing = true
	var t := 0.0
	while core.playing and t <= core.end_time + 2.0:
		core.update(t); t += 1.0 / 120.0
	result["stats"] = core.stats.duplicate(true)
	if core.playing or core.stats.PERFECT != core.stats.total or core.stats.GREAT != 0 or core.stats.GOOD != 0 or core.stats.MISS != 0:
		result.errors.append("autoplay did not finish with all PERFECT")
	core = null
	session.close()
	finish(result)
