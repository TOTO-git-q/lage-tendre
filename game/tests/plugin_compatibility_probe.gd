## Run the same probe on P0 and P1; compare the resulting JSON structurally.
extends SceneTree

func _init() -> void:
	KB.set_layout("ansi")
	var output := []
	for index in 32:
		var shift := float(index % 5 - 2) / 30.0
		var chart := {"bpm": [90.0, 120.0, 180.0, 250.0][index % 4], "offset": -0.125 + index * 0.01,
			"timing": [{"t": 0, "beat": 0.5, "meter": 4}], "meta": {}, "lights": [
				{"t": 0.0, "id": 0, "type": "on", "x": 0.5, "w": 0.6, "from": "L", "a": 0.4, "tint": 2},
				{"t": 1.0, "id": 0, "type": "sweep", "x": 0.5 + shift, "w": 0.7, "dur": 0.4, "ease": SU.EASES[index % 4], "from": "LR", "a": 0.9, "tint": 7},
				{"t": 3.0, "id": 0, "type": "pulse", "from": "R"},
				{"t": 4.0, "id": 0, "type": "jump", "x": 0.45, "w": 0.5, "from": "L"},
				{"t": 7.0, "id": 0, "type": "off"}], "notes": [
				{"t": 2.0, "light": 0, "u": 0.15, "kind": "tap", "ex": index % 2 == 0, "big": index % 3 == 0, "grow": [0.3, 1.2], "nw": 1.5},
				{"t": 2.0, "light": 0, "u": 0.5, "kind": "tap", "k": 5},
				{"t": 2.0, "light": 0, "u": 0.85, "kind": "tap"},
				{"t": 3.5, "light": 0, "u": 0.4, "kind": "hold", "dur": 2.5, "path": [[0, 0.4, 1], [1.0, 0.7, 2], [2.5, 0.4, 1]], "grow": [0.5, 1]}]}
		if index % 2:
			chart.meta.twitch = [[2.0, -1.0]]
			chart.fx = [{"t": 1.0, "type": "tween", "ch": "line_y", "to": 0.03, "dur": 0.6},
				{"t": 2.0, "type": "impulse", "ch": "zoom", "amp": 0.03}, {"t": 2.5, "type": "ring"}]
		var normalized := ChartLib.validate(JSON.stringify(chart) if index % 3 == 0 else chart)
		var timelines := ChartLib.build_timelines(normalized.lights)
		var samples := []
		for step in 65: samples.append(ChartLib.light_at(timelines[0], step * 0.125))
		var core := GameCore.new(); core.load_chart(chart)
		var notes := []
		for note in core.notes:
			notes.append({"t": note.t, "kind": note.kind, "ticks": note.ticks, "k": note.k, "hint": note.hint, "w_e": note.w_e, "w_l": note.w_l})
		var stages := {}
		for mode in ["full", "reduced", "off"]:
			core.stage.mode = mode; stages[mode] = []
			for step in 17: stages[mode].append(core.stage.at(step * 0.5))
		output.append({"chart": normalized, "timelines": timelines, "cues": ChartLib.build_cues(normalized.lights), "samples": samples,
			"notes": notes, "stats": core.stats, "end_time": core.end_time, "stages": stages})
		core = null
	var ranks := []
	for score in [0, 599999, 600000, 699999, 700000, 799999, 800000, 899999, 900000, 924999, 925000, 949999, 950000, 974999, 975000, 999999, 1000000, 1007499, 1007500, 1010000]:
		var rank := Ranks.rank_of(score)
		ranks.append({"score": score, "rank": rank, "index": Ranks.index_of(rank), "min": Ranks.min_of(rank), "next": Ranks.next_of(rank), "tint": str(Ranks.tint_of(rank)), "glow": Ranks.glow_of(rank)})
	var path := OS.get_cmdline_user_args()[0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"charts": output, "ranks": ranks})); file.close()
	print("COMPATIBILITY PROBE: 32 charts, 2080 timeline samples, 1632 stage samples, 20 rank boundaries")
	quit()
