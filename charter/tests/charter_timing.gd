extends SceneTree
## 歌曲设置 timing on a temporary copy: BPM edits move only the grid; the explicit re-time keeps
## every event's bar.beat; offset and whole-chart shift; undo / redo; validator unchanged; lean
## save keeps the tempo map; MCP cannot edit song timing.

const Document = preload("res://document.gd")
const Timing = preload("res://song_timing.gd")
var failed := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed += 1

func _init() -> void:
	KB.set_layout("ansi")
	var dir := ProjectSettings.globalize_path("res://evidence/temp_timing")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
	var src := ProjectSettings.globalize_path("res://../game/tests/fixtures/dense").simplify_path()
	DirAccess.copy_absolute(src.path_join("chart.json"), dir.path_join("chart.json"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../songs/_demo/audio.wav"), dir.path_join("audio.wav"))
	var doc = Document.new()
	doc.open(dir.path_join("chart.json"))
	var times := []
	for n in doc.raw.notes: times.append(float(n.t))
	var warn0 := JSON.stringify(ChartLib.validate(doc.raw).warnings)
	var old_timing: Array = doc.timing().duplicate(true)
	var probe := float(doc.raw.notes[200].t)
	var old_pos: String = doc.position(probe).bar_beat
	var old_bpm := 60.0 / float(old_timing[0].beat)

	# ---- BPM edit moves only the grid
	var timing := [{"t": float(old_timing[0].t), "beat": 60.0 / 180.0, "meter": 4}]
	var r: Dictionary = doc.edit({"expected_revision": doc.revision(), "label": "BPM", "ops": [{"target": "song", "value": {"timing": timing}}]})
	check(not r.has("error"), "BPM edit accepted: " + str(r.get("error", "")))
	var same := true
	for i in doc.raw.notes.size(): same = same and float(doc.raw.notes[i].t) == times[i]
	check(same, "BPM edit leaves every note at its chart second")
	check(doc.position(probe).bar_beat != old_pos, "the grid moved (bar.beat of a note changed: %s -> %s)" % [old_pos, doc.position(probe).bar_beat])
	check(absf(float(doc.raw.bpm) - 180.0) < 1e-6, "chart.bpm follows timing[0]")
	check(JSON.stringify(ChartLib.validate(doc.raw).warnings) == warn0, "validator warnings unchanged by a BPM edit")
	doc.undo()
	check(absf(60.0 / float(doc.timing()[0].beat) - old_bpm) < 1e-6 and doc.position(probe).bar_beat == old_pos, "undo restores the tempo map")
	doc.redo()
	check(absf(float(doc.raw.bpm) - 180.0) < 1e-6, "redo applies it again")

	# ---- explicit re-time: every event keeps its musical position
	var old_segs := Timing.segments(old_timing); var new_segs := Timing.segments(doc.timing())
	var moved := Timing.retime(doc.raw, old_timing, doc.timing())
	r = doc.edit({"expected_revision": doc.revision(), "label": "retime", "ops": [{"target": "song", "value": {"notes": moved.notes, "lights": moved.lights, "fx": moved.get("fx", []), "meta": moved.get("meta", {})}}]})
	check(not r.has("error"), "re-time accepted by the rules: " + str(r))
	var worst := 0.0
	for i in doc.raw.notes.size():
		worst = maxf(worst, absf(Timing.beats_at(new_segs, float(doc.raw.notes[i].t)) - Timing.beats_at(old_segs, times[i])))
	check(worst < 0.002, "re-timed notes keep their beat position (worst %.5f beats)" % worst)
	var b_old := roundi(Timing.beats_at(old_segs, times[200]) * 48.0); var b_new := roundi(Timing.beats_at(new_segs, float(doc.raw.notes[200].t)) * 48.0)
	check(b_old == b_new, "note 200 keeps its position on the 1/48-beat grid (%s before, %s now)" % [old_pos, doc.position(float(doc.raw.notes[200].t)).bar_beat])
	check(JSON.stringify(ChartLib.validate(doc.raw).warnings) == warn0, "validator warnings unchanged by the re-time")
	var hold_ok := true
	for i in doc.raw.notes.size():
		var n: Dictionary = doc.raw.notes[i]
		if n.get("kind", "") == "hold" and float(n.get("dur", 0)) > 0:
			var nb := Timing.beats_at(new_segs, float(n.t) + float(n.dur)) - Timing.beats_at(new_segs, float(n.t))
			hold_ok = hold_ok and nb > 0
	check(hold_ok, "hold lengths re-timed by their ends")
	doc.undo()
	same = true
	for i in doc.raw.notes.size(): same = same and float(doc.raw.notes[i].t) == times[i]
	check(same, "the re-time is one undo step")
	doc.undo()

	# ---- offset: audio only, or the whole chart with the audio
	var off0 := float(doc.raw.get("offset", 0.0))
	r = doc.edit({"expected_revision": doc.revision(), "label": "offset", "ops": [{"target": "song", "value": {"offset": off0 + 0.25}}]})
	same = true
	for i in doc.raw.notes.size(): same = same and float(doc.raw.notes[i].t) == times[i]
	check(not r.has("error") and absf(float(doc.raw.offset) - off0 - 0.25) < 1e-9 and same, "offset edit moves only the audio")
	doc.undo()
	var shifted := Timing.shift(doc.raw, 0.5)
	r = doc.edit({"expected_revision": doc.revision(), "label": "shift", "ops": [{"target": "song", "value": {"notes": shifted.notes, "lights": shifted.lights, "fx": shifted.get("fx", []), "meta": shifted.get("meta", {}), "timing": shifted.timing, "offset": shifted.offset}}]})
	check(not r.has("error"), "whole-chart shift accepted: " + str(r.get("error", "")))
	check(absf(float(doc.raw.offset) - off0 - 0.5) < 1e-9 and absf(float(doc.raw.notes[200].t) - times[200] - 0.5) < 1e-6, "shift moves notes and audio together")
	check(doc.position(float(doc.raw.notes[200].t)).bar_beat == old_pos, "shifted notes keep their bar.beat")
	check(Timing.shift(doc.raw, -9999.0).has("error"), "a shift before 0 s is refused")
	doc.undo()
	check(absf(float(doc.raw.offset) - off0) < 1e-9, "shift undone in one step")

	# ---- guards and save
	check(doc.edit({"expected_revision": doc.revision(), "ops": [{"target": "song", "value": {"timing": timing}}]}, "Claude").has("error"), "MCP (Claude) cannot edit song timing")
	check(doc.edit({"expected_revision": doc.revision(), "ops": [{"target": "song", "value": {"timing": [{"t": 1.0, "beat": 0.001}]}}]}).has("error"), "impossible BPM refused")
	doc.edit({"expected_revision": doc.revision(), "label": "BPM", "ops": [{"target": "song", "value": {"timing": [{"t": float(old_timing[0].t), "beat": 60.0 / 190.0, "meter": 4}, {"t": 60.0, "beat": 60.0 / 200.0, "meter": 3}]}}]})
	var saved: Dictionary = doc.save()
	var back = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("chart.json")))
	check(not saved.has("error") and back.timing.size() == 2 and absf(float(back.bpm) - 190.0) < 1e-6 and int(back.timing[1].meter) == 3, "lean save keeps the tempo map and bpm in sync")
	print("CHARTER_TIMING failures=", failed)
	quit(1 if failed else 0)
