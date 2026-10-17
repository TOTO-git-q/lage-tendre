## Actual band submission equivalence and bounded packed-index cache isolation.
extends SceneTree
var checks := 0
var failures := 0
var baseline := ""
var allow_cached_reference := false
var candidate_source := "res://plugins/builtin/standard_render/runtime.gd"
var reference_script: GDScript
var candidate_script: GDScript
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)
func original_indices(n: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in n:
		var j := i * 2
		result.append_array([j, j + 1, j + 2, j + 1, j + 3, j + 2])
	return result
func captured_script(path: String) -> GDScript:
	var source := FileAccess.get_file_as_string(path)
	var first := source.find("func band(")
	var last := source.find("\n## The tracks", first)
	check(first >= 0 and last > first, "actual band source boundaries: " + path)
	if first < 0 or last <= first: return null
	var body := source.substr(first, last - first)
	var submission := "RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())"
	check(body.count(submission) == 1, "exact real band submission found: " + path)
	if body.count(submission) != 1: return null
	# Preserve the exact production body. Wrap only its final real submission.
	body = body.replace(submission, "_capture_submit(c.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())")
	var script := GDScript.new()
	script.source_code = 'extends "res://plugins/builtin/standard_render/runtime.gd"\nvar captured := []\n' + body + '''
func _capture_submit(canvas: RID, indices: PackedInt32Array, points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array, bones: PackedInt32Array, weights: PackedFloat32Array, texture: RID) -> void:
	captured.append({"canvas":canvas,"indices":indices,"points":points,"colors":colors,"uvs":uvs,"bones":bones,"weights":weights,"texture":texture})
	RenderingServer.canvas_item_add_triangle_array(canvas, indices, points, colors, uvs, bones, weights, texture)
'''
	var error := script.reload()
	check(error == OK, "mechanical actual-submit capture compiles: " + path)
	return script if error == OK else null
func set_geometry(r: BuiltinRendererRuntime, mode: int) -> void:
	r.S = StageFx.rest(); r.f = {"t":4.125}
	if mode == 2:
		r.S.zoom = 1.13; r.S.roll = 7.0; r.S.pitch = 17.0
		r.S.trauma = 0.21; r.S.vpx = 43.0; r.S.line_y = -0.03
	r.G = r._geo()
	if mode == 0:
		# Exact affine y chooses every n, while x keeps the real curved field.
		r.G.hy = 0.0; r.G.jy = 1000.0; r.G.arc = 0.0; r.G.z = 0.0
		r.G.shy = 0.0; r.G.shear = 0.13; r.G.vpx = 23.0
	elif mode == 3:
		r.G.arc = 0.4; r.G.z = -0.12; r.G.shear = -0.11
	r.G.build_inverse()
func same_submission(old, current, canvas: CanvasItem, texture: Texture2D, args: Array, label: String) -> void:
	old.captured.clear(); current.captured.clear()
	var all_args := [canvas, texture]
	all_args.append_array(args)
	old.callv("band", all_args); current.callv("band", all_args)
	check(old.captured.size() == 1 and current.captured.size() == 1, label + " both really submit")
	if old.captured.size() != 1 or current.captured.size() != 1: return
	var a: Dictionary = old.captured[0]; var b: Dictionary = current.captured[0]
	for field in ["canvas", "indices", "points", "colors", "uvs", "bones", "weights", "texture"]:
		check(a[field] == b[field], label + " exact " + field)
func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--allow-cached-reference": allow_cached_reference = true
		if argument.begins_with("--baseline-runtime="): baseline = argument.trim_prefix("--baseline-runtime=")
		if argument.begins_with("--candidate-runtime="): candidate_source = argument.trim_prefix("--candidate-runtime=")
	check(baseline.is_absolute_path() and FileAccess.file_exists(baseline), "required absolute pre-cache production source exists")
	if baseline.is_empty() or not FileAccess.file_exists(baseline): quit(1); return
	var baseline_source := FileAccess.get_file_as_string(baseline)
	check(allow_cached_reference or not baseline_source.contains("func _band_indices("), "reference source is pre-cache or an explicitly selected frozen performance control")
	reference_script = captured_script(baseline)
	check(FileAccess.file_exists(candidate_source), "required exact candidate source exists for source or compiled test")
	if not FileAccess.file_exists(candidate_source): quit(1); return
	candidate_script = captured_script(candidate_source)
	if reference_script == null or candidate_script == null: quit(1); return
	var r := BuiltinRendererRuntime.new()
	var other := BuiltinRendererRuntime.new()
	check(r._band_indices_cache.is_empty() and other._band_indices_cache.is_empty(), "each renderer starts with its own empty cache")
	for n in range(2, 161):
		var expected := original_indices(n)
		var cold: PackedInt32Array = r._band_indices(n)
		check(cold == expected and cold.size() == n * 6, "cold index values n=" + str(n))
		check(r._band_indices(n) == expected, "warm index values n=" + str(n))
		cold[0] = -17; cold.append(-19); cold.resize(2)
		check(r._band_indices(n) == expected, "returned packed-array mutations cannot poison cache n=" + str(n))
		var first: PackedInt32Array = r._band_indices(n)
		var second: PackedInt32Array = r._band_indices(n)
		first[0] = -23
		check(second == expected, "independent simultaneous return values n=" + str(n))
		check(other._band_indices_cache.is_empty(), "cache remains instance-local n=" + str(n))
	check(r._band_indices_cache.size() == 159, "exactly 159 possible topology entries")
	for value in [-100, 0, 1, 161, 1000000000]:
		check(r._band_indices(value) == original_indices(clampi(value, 2, 160)), "out-of-range requests clamp safely " + str(value))
	check(r._band_indices_cache.size() == 159, "out-of-range requests cannot grow cache")
	var old = reference_script.new(); var current = candidate_script.new()
	var canvas := Node2D.new(); var texture := GradientTexture2D.new()
	set_geometry(old, 0); set_geometry(current, 0)
	for n in range(2, 161):
		var s1 := (float(n) + 0.125) * 5.0 / 1000.0
		var args := [-0.15, 0.87, 0.0, s1, 0.73, 0.09, 17.25 if n % 2 == 0 else 0.0, -0.2, 1.3, Color(0.23, 0.61, 0.97, 0.4)]
		same_submission(old, current, canvas, texture, args, "all n=" + str(n))
		check(current.captured[0].indices.size() == n * 6, "actual field selected requested n=" + str(n))
		# The recorder receives the very array passed to RenderingServer.
		current.captured[0].indices[0] = -31
		check(current._band_indices(n) == original_indices(n), "submitted array mutation remains isolated n=" + str(n))
	for mode in [1, 2, 3]:
		set_geometry(old, mode); set_geometry(current, mode)
		for sample in [[0.1,0.9,0.0,1.25,1.7,0.0,0.0,0.0,1.0,Color.WHITE], [0.65,0.15,0.2,0.91,0.25,0.2,150.0,0.25,0.9,Color(0.4,0.2,0.7,0.8)], [-0.3,1.3,0.5,0.5001,0.004,-0.1,900.0,-2.0,2.0,Color(1.4,-0.3,0.7,0.2)]]:
			same_submission(old, current, canvas, texture, sample, "real stage/curve mode=" + str(mode))
	var before: int = current._band_indices_cache.size()
	for sample in [[null,1.0,0.0,1.0], [texture,0.003,0.0,1.0], [texture,-2.0,0.0,1.0], [texture,1.0,1.0,1.0], [texture,1.0,1.0,0.0]]:
		old.captured.clear(); current.captured.clear()
		old.band(canvas,sample[0],0.1,0.9,sample[2],sample[3],sample[1],0.0)
		current.band(canvas,sample[0],0.1,0.9,sample[2],sample[3],sample[1],0.0)
		check(old.captured.is_empty() and current.captured.is_empty(), "early-return remains submission-free")
		check(current._band_indices_cache.size() == before, "early-return does not touch topology cache")
	old.free(); current.free(); canvas.free(); r.free(); other.free()
	print("BAND INDEX CACHE: ", checks, " checks, ", failures, " failures; all 159 n values; 168 exact actual-submit pairs")
	quit(0 if failures == 0 else 1)
