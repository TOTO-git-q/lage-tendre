## Exact legacy arithmetic/search witnesses, including cache invalidation and seeks.
extends SceneTree
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 8: printerr("FAIL ", label)

func legacy_light(segs: Array, t: float, scope: PluginRegistry) -> Dictionary:
	if segs.is_empty(): return BuiltinChartRuntime.DEAD
	var index := -1
	for k in segs.size():
		if segs[k].t <= t + 1e-9: index = k
		else: break
	if index < 0: return BuiltinChartRuntime.DEAD
	var callback: Callable = scope.get_entry("events", str(segs[index].type)).get("sample", Callable())
	return callback.call(segs[index], t) if callback.is_valid() else BuiltinChartRuntime.DEAD

func _init() -> void: run.call_deferred()

func run() -> void:
	KB.set_layout("ansi")
	var scope := PluginRegistry.standard()
	for song in ["fixture_dense", "_demo", "demo"]:
		var raw: Dictionary = ChartLib.demo() if song == "demo" else SU.load_json(ProjectSettings.globalize_path("res://../game/tests/fixtures/dense/chart.json" if song == "fixture_dense" else "res://../songs/" + song + "/chart.json"))
		var core := GameCore.new(scope)
		check(core.load_chart(raw), "chart loads")
		check(not core.tl.is_empty() and not core.notes.is_empty(), "nonempty chart/timeline witness")
		for segments in core.tl.values():
			var times := [-100.0, 0.0, 9999.0]
			for seg in segments:
				for offset in [-0.001, -2e-9, -1e-9, 0.0, 1e-9, 0.001, 0.15, 0.3]: times.append(seg.t + offset)
			# Reverse order exercises arbitrary backward seeks with no cursor state.
			times.reverse()
			for t in times: check(BuiltinChartRuntime.light_at(segments, t, scope) == legacy_light(segments, t, scope), "exact timeline sample " + song)
			if segments.size() > 1:
				var tied: Array = [segments[0].duplicate(true), segments[1].duplicate(true)]
				tied[1].t = tied[0].t
				check(BuiltinChartRuntime.light_at(tied, tied[0].t, scope) == legacy_light(tied, tied[0].t, scope), "last tied segment wins")
	var g := BuiltinRenderData.Geo.new()
	g.l = 0.0; g.r = 1920.0; g.D = 1920.0; g.cx = 864.0; g.key_w = 128.0
	for mode in range(5):
		g.hy = 97.2 + mode * 11.0; g.jy = 830.0 - mode * 7.0
		g.arc = mode * 0.2; g.gam = 0.30 + mode * 0.03
		g.z = mode * 0.07; g.shy = mode * 0.2; g.vpx = mode * 13.0; g.shear = mode * 0.017
		# Change public fields on a populated cache without build_inverse().
		for i in 251:
			var s := i / 200.0
			var ww := 0.0 if s >= 1.0 else pow(1.0 - maxf(0.0, s), 1.5)
			var yb: float = g.yb(s)
			check(g.y_of(s) == g.jy + (yb - g.jy) * (1.0 + g.z * ww) + g.shy * ww, "exact cached y")
			for xl in [-0.1, 0.0, 0.15, 0.5, 1.0, 1.1]:
				var x: float = g.cx + (xl - BuiltinRenderData.AXIS) * g.D * pow(maxf(s, 0.0), g.gam) * (1.0 + g.z * ww) + g.vpx * ww + (g.jy - yb) * g.shear * ww
				check(g.x_of(xl, s) == x, "exact cached x")
	var renderer := BuiltinRendererRuntime.new()
	for run_index in 2:
		var notes := []
		for i in 100:
			notes.append({"t": i * 0.25, "dur": 18.0 if i % 9 == 0 else 0.0,
				"state": ["pending", "hit", "holding", "miss", "skip"][i % 5]})
		renderer.f = {"notes": notes}
		for t in [-1.0, 0.0, 1.0, 8.0, 17.25, 25.0, 40.0, 10.0]:
			for fall in [0.6, 1.5, 3.5]:
				for reach in [0.25, 1.0]:
					var expected := []
					var actual := []
					for i in notes.size():
						if eligible(notes[i], t, fall, reach): expected.append(i)
					for i in range(renderer._first_visible_note(t, fall), notes.size()):
						if 1.0 - (notes[i].t - t) / fall < 1.0 - reach - 0.05: break
						if eligible(notes[i], t, fall, reach): actual.append(i)
					check(actual == expected, "visibility index preserves long holds, states, resets and seeks")
	renderer.free()
	print("PERF EQUIVALENCE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func eligible(n: Dictionary, t: float, fall: float, reach: float) -> bool:
	if n.state == "skip": return false
	var quick: float = 1.0 - (n.t - t) / fall
	var tail: float = 1.0 - (n.t + n.dur - t) / fall
	return not (quick < 1.0 - reach - 0.05 or (tail > 1.2 and not (n.state in ["miss", "pending"] and t - n.t < 1.0)))
