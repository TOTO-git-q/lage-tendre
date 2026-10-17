## Data-backed API 1 providers. These callbacks are game-owned code, not pack code.
## Textures bypass resource remaps; shaders are read as canvas-only source with no includes.
class_name PluginDeclarative
extends RefCounted

const SUPPORTED := ["flags", "channels", "motions", "elements"]
const TEXTURES := ["png", "jpg", "jpeg", "webp"]
const PROTECTED_NOTE_FIELDS := ["t", "light", "u", "kind", "dur", "nw", "path", "k", "ex", "big", "grow", "wl", "state", "hitX", "lineX", "key_code", "chord", "hint"]
var fields := {}
var definitions := {}
var formulas := {}
var textures := {}
var shaders := {}
var runtime_errors := []

static func validate(manifest: Dictionary, folder: String) -> Dictionary:
	var errors := []
	var definitions: Variant = manifest.get("definitions", {})
	if typeof(definitions) != TYPE_DICTIONARY: return {"errors": ["Declarative definitions must be an object"]}
	var fields := {}
	for field in manifest.get("fields", []):
		if ChartCodec.path_parts(str(field.path)).is_empty(): errors.append("Invalid declarative field path: " + str(field.path))
		fields[str(field.path)] = field
	for category in manifest.provides:
		if not manifest.provides[category].is_empty() and category not in SUPPORTED:
			errors.append("Unsupported declarative category: " + str(category)); continue
		for id in manifest.provides[category]:
			var group: Variant = definitions.get(category, {})
			if typeof(group) != TYPE_DICTIONARY or typeof(group.get(id)) != TYPE_DICTIONARY:
				errors.append("Missing declarative definition: " + str(category) + "." + str(id)); continue
			var definition: Dictionary = group[id]
			var prefix := str(category) + "." + str(id) + ": "
			var allowed := []
			match category:
				"flags":
					allowed = ["field", "order"]
					var name := str(definition.get("field", ""))
					var parts := ChartCodec.path_parts(name)
					if parts.is_empty() or name.contains("[]") or parts[0].key in PROTECTED_NOTE_FIELDS or str(parts[0].key).begins_with("_"):
						errors.append(prefix + "flag field must be an unreserved note data path")
					if not fields.has("notes[]." + name): errors.append(prefix + "field schema is required: notes[]." + name)
				"channels":
					allowed = ["default", "min", "max"]
					for key in allowed:
						if not _finite(definition.get(key)): errors.append(prefix + "channel requires finite " + key)
					if _finite(definition.get("min")) and _finite(definition.get("max")) and _finite(definition.get("default")):
						if definition.min > definition.max or definition.default < definition.min or definition.default > definition.max:
							errors.append(prefix + "channel default/range mismatch")
				"motions":
					allowed = ["field", "x", "w", "alpha"]
					if not definition.has("x") and not definition.has("w") and not definition.has("alpha"):
						errors.append(prefix + "motion requires x, w or alpha formula")
					_validate_value_field(definition, fields, prefix, errors, false)
					for key in ["x", "w", "alpha"]:
						if definition.has(key):
							for error in PluginFormula.compile(definition[key]).errors: errors.append(prefix + key + ": " + str(error))
				"elements":
					allowed = ["kind", "field", "radius", "opacity", "width", "color", "order", "texture", "shader"]
					if definition.get("kind") != "glow_ring": errors.append(prefix + "only glow_ring elements are supported")
					_validate_value_field(definition, fields, prefix, errors, true)
					for key in ["radius", "opacity"]:
						for error in PluginFormula.compile(definition.get(key, "value" if key == "radius" else "alpha")).errors: errors.append(prefix + key + ": " + str(error))
					if not _finite(definition.get("width", 2.0)) or float(definition.get("width", 2.0)) <= 0.0 or float(definition.get("width", 2.0)) > 32.0:
						errors.append(prefix + "width must be in (0,32]")
					var color: Variant = definition.get("color", [1, 1, 1, 1])
					if typeof(color) != TYPE_ARRAY or color.size() != 4: errors.append(prefix + "color requires four components")
					else:
						for component in color:
							if not _finite(component) or float(component) < 0.0 or float(component) > 1.0: errors.append(prefix + "color components must be in [0,1]")
					for key in ["texture", "shader"]:
						if not definition.has(key): continue
						var asset: Variant = definition[key]
						if typeof(asset) != TYPE_STRING or asset not in manifest.assets:
							errors.append(prefix + key + " must name a listed asset"); continue
						var extension: String = str(asset).get_extension().to_lower()
						if (key == "texture" and extension not in TEXTURES) or (key == "shader" and extension != "gdshader"):
							errors.append(prefix + "wrong asset type for " + key)
			for key in definition:
				if key not in allowed: errors.append(prefix + "unsupported definition property: " + str(key))
			if definition.has("order") and (not _finite(definition.order) or float(definition.order) != floor(float(definition.order)) or absf(float(definition.order)) > 4096.0):
				errors.append(prefix + "order must be an integer within ±4096")
	for category in definitions:
		if category not in SUPPORTED or typeof(definitions[category]) != TYPE_DICTIONARY:
			errors.append("Unsupported declarative definition category: " + str(category)); continue
		for id in definitions[category]:
			if id not in manifest.provides.get(category, []): errors.append("Undeclared definition: " + str(category) + "." + str(id))
	for asset in manifest.assets:
		var extension: String = str(asset).get_extension().to_lower()
		if extension not in TEXTURES and extension not in ["gdshader", "json"]:
			errors.append("Unsupported declarative asset type: " + str(asset)); continue
		var checked := PluginPack.file_path(folder, str(asset))
		errors.append_array(checked.errors)
		if not checked.errors.is_empty(): continue
		if extension == "gdshader":
			var source := FileAccess.get_file_as_string(checked.path)
			# Includes can escape a declared asset set. No .tres/.res/.import loading.
			var include_pattern := RegEx.new(); include_pattern.compile("#")
			var comments := RegEx.new(); comments.compile("(?s)/\\*.*?\\*/|//[^\\n]*")
			var code := comments.sub(source, "", true)
			var type_pattern := RegEx.new(); type_pattern.compile("\\bshader_type\\s+([A-Za-z_][A-Za-z_0-9]*)\\s*;")
			var types := type_pattern.search_all(code)
			if include_pattern.search(source) or types.size() != 1 or types[0].get_string(1) != "canvas_item":
				errors.append("Declarative shader requires canvas_item and cannot use preprocessor directives: " + str(asset))
		elif extension == "json":
			var parser := JSON.new()
			if parser.parse(FileAccess.get_file_as_string(checked.path)) != OK: errors.append("Invalid declarative JSON asset: " + str(asset))
	return {"errors": errors}

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _validate_value_field(definition: Dictionary, fields: Dictionary, prefix: String, errors: Array, required: bool) -> void:
	if not definition.has("field"):
		if required: errors.append(prefix + "numeric note field is required")
		return
	var name := str(definition.field)
	var schema: Dictionary = fields.get("notes[]." + name, {})
	if ChartCodec.path_parts(name).is_empty() or name.contains("[]") or schema.get("type", "") not in ["number", "integer"]:
		errors.append(prefix + "field requires a numeric notes[]. schema")

static func install(registry: PluginRegistry, manifest: Dictionary, folder: String) -> Array:
	var validation := validate(manifest, folder)
	if not validation.errors.is_empty(): return validation.errors
	var provider := PluginDeclarative.new()
	provider.definitions = manifest.get("definitions", {}).duplicate(true)
	for field in manifest.fields: provider.fields[field.path] = field.duplicate(true)
	for asset in manifest.assets:
		var path: String = PluginPack.file_path(folder, str(asset)).path
		var extension: String = str(asset).get_extension().to_lower()
		if extension in TEXTURES:
			var data := Image.new()
			if data.load(path) != OK: return ["Cannot decode texture asset: " + str(asset)]
			provider.textures[asset] = ImageTexture.create_from_image(data)
		elif extension == "gdshader":
			var shader := Shader.new(); shader.code = FileAccess.get_file_as_string(path)
			provider.shaders[asset] = shader
	for category in manifest.provides:
		for id in manifest.provides[category]:
			var definition: Dictionary = provider.definitions[category][id]
			var item := {"declarative": true, "order": int(definition.get("order", 0))}
			match category:
				"flags": item.normalize = provider.normalize_flag.bind(id)
				"channels":
					item.default = float(definition.default); item.min = float(definition.min); item.max = float(definition.max)
				"motions":
					provider._compile_formulas(category, id, definition, ["x", "w", "alpha"])
					item.callback = provider.motion.bind(id)
				"elements":
					provider._compile_formulas(category, id, {"radius": definition.get("radius", "value"), "opacity": definition.get("opacity", "alpha")}, ["radius", "opacity"])
					# A private layer keeps optional shader state out of built-in layers.
					item.phase = "plugin." + str(manifest.id) + "." + str(id)
					item.order = int(definition.get("order", 41)); item.additive = true
					item.callback = provider.draw_ring.bind(id)
			registry.register(category, str(id), item)
	registry.own(provider)
	return []

func _compile_formulas(category: String, id: String, definition: Dictionary, keys: Array) -> void:
	var result := {}
	for key in keys:
		if definition.has(key): result[key] = PluginFormula.compile(definition[key]).formula
	formulas[category + "." + id] = result

static func get_field(note: Dictionary, path: String, fallback: Variant = null) -> Variant:
	var value: Variant = note
	for part in path.split("."):
		if typeof(value) != TYPE_DICTIONARY or not value.has(part): return fallback
		value = value[part]
	return value

static func set_field(note: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var current := note
	for i in parts.size() - 1:
		if typeof(current.get(parts[i])) != TYPE_DICTIONARY: current[parts[i]] = {}
		current = current[parts[i]]
	current[parts[-1]] = value

func normalize_flag(raw: Dictionary, note: Dictionary, id: String) -> void:
	var name: String = definitions.flags[id].field
	var schema: Dictionary = fields["notes[]." + name]
	var value: Variant = get_field(raw, name, schema.default)
	if not field_valid(value, schema): value = schema.default
	if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]: value = value.duplicate(true)
	set_field(note, name, value)

static func field_valid(value: Variant, schema: Dictionary) -> bool:
	match str(schema.type):
		"number", "integer":
			return _finite(value) and float(value) >= float(schema.min) and float(value) <= float(schema.max) and (schema.type != "integer" or float(value) == floor(float(value)))
		"boolean": return typeof(value) == TYPE_BOOL
		"string": return typeof(value) == TYPE_STRING
		"enum": return value in schema.get("enum", [])
		"array": return typeof(value) == TYPE_ARRAY
		"object": return typeof(value) == TYPE_DICTIONARY
	return false

func _inputs(renderer, note: Dictionary, state: Dictionary, definition: Dictionary) -> Dictionary:
	var fall := maxf(0.000001, float(renderer.f.get("fall", 1.0)))
	var t := float(renderer.f.get("t", 0.0))
	var name := str(definition.get("field", ""))
	var schema: Dictionary = fields.get("notes[]." + name, {})
	var value: Variant = get_field(note, name, schema.get("default", 0.0)) if not name.is_empty() else 0.0
	var progress: float=renderer.visual_progress(int(note.get("light",0)),float(note.get("t",0.0))) if renderer.has_method("visual_progress") else 1.0-(float(note.get("t",0.0))-t)/fall
	return {"t": t, "note_t": float(note.get("t", 0.0)), "progress": clampf(progress,0.0,1.0),
		"x": float(state.get("x", 0.5)), "w": float(state.get("w", 0.0)), "alpha": float(state.get("alpha", 1.0)),
		"u": float(note.get("u", 0.5)), "duration": float(note.get("dur", 0.0)), "value": value}

func motion(renderer, note: Dictionary, state: Dictionary, id: String) -> Dictionary:
	var definition: Dictionary = definitions.motions[id]
	var inputs := _inputs(renderer, note, state, definition)
	var next := state.duplicate(true)
	for key in formulas["motions." + id]:
		var result: Dictionary = formulas["motions." + id][key].evaluate(inputs)
		if not result.ok:
			_record_error("Motion " + id + ": " + result.error); return state
		var bounds: Array = {"x": [-2.0, 3.0], "w": [0.0, 4.0], "alpha": [0.0, 1.0]}[key]
		next[key] = clampf(result.value, bounds[0], bounds[1])
	# Geometry owns its visual intervals. Only changed envelopes need a hook;
	# lane and alpha-only motions retain the original data-only path.
	var new_x := float(next.get("x", inputs.x)); var new_w := float(next.get("w", inputs.w))
	if state.get("geometry", "lane") != "lane" and (new_x != float(inputs.x) or new_w != float(inputs.w)):
		var transform: Callable = renderer.registry.get_entry("track_geometry", str(state.geometry)).get("visual_transform", Callable())
		if transform.is_valid():
			var transformed: Dictionary = transform.call(state, new_x, new_w)
			if next.has("alpha"): transformed.alpha = next.alpha
			return transformed
	return next

## Build primitives separately so the real draw callback and headless tests share
## exactly the same geometry/formula computation.
func ring_primitives(renderer, id: String) -> Array:
	var result := []
	if renderer.f.is_empty() or not renderer.f.get("play", false) or renderer.G == null: return result
	var definition: Dictionary = definitions.elements[id]
	var fall := maxf(0.000001, float(renderer.f.get("fall", 1.0)))
	var t := float(renderer.f.get("t", 0.0))
	var colors: Array = definition.get("color", [1.0, 1.0, 1.0, 1.0])
	for note in renderer.f.get("notes", []):
		if note.get("state", "pending") not in ["pending", "holding"]: continue
		var p: float=renderer.visual_progress(int(note.light),float(note.t)) if renderer.has_method("visual_progress") else 1.0-(float(note.t)-t)/fall
		if p < 1.0 - float(renderer.f.get("reach", 1.0)) or p > 1.0: continue
		var by_id: Dictionary = renderer.f.get("light_by_id_raw", renderer.f.get("light_by_id", {}))
		if not by_id.has(note.light): continue
		var state: Dictionary = renderer._land_st(note, by_id[note.light])
		if not state.get("alive", false): continue
		var inputs := _inputs(renderer, note, state, definition)
		var radius: Dictionary = formulas["elements." + id].radius.evaluate(inputs)
		var opacity: Dictionary = formulas["elements." + id].opacity.evaluate(inputs)
		if not radius.ok or not opacity.ok:
			_record_error("Element " + id + ": " + str(radius.error if not radius.ok else opacity.error)); continue
		var point: Dictionary = renderer._note_at(state, note, p)
		var r := clampf(radius.value, 0.0, 4.0) * absf(float(point.kw))
		var alpha := clampf(opacity.value, 0.0, 1.0) * float(colors[3])
		if r <= 0.0 or alpha <= 0.0: continue
		result.append({"center": Vector2(point.x, point.y), "radius": r, "width": float(definition.get("width", 2.0)), "color": Color(colors[0], colors[1], colors[2], alpha)})
	return result

func draw_ring(renderer, canvas: CanvasItem, id: String) -> void:
	var definition: Dictionary = definitions.elements[id]
	if definition.has("shader") and not canvas.has_meta("declarative_shader"):
		var material := ShaderMaterial.new(); material.shader = shaders[definition.shader]
		canvas.material = material; canvas.set_meta("declarative_shader", true)
	# Custom layers follow the existing judgement-line transform without changing
	# any built-in draw algorithm or the physical hit geometry.
	if renderer.L.has("note") and canvas != renderer.L.note:
		canvas.rotation = renderer.L.note.rotation; canvas.position = renderer.L.note.position
	for primitive in ring_primitives(renderer, id):
		if definition.has("texture"):
			var diameter: float = primitive.radius * 2.0
			canvas.draw_texture_rect(textures[definition.texture], Rect2(primitive.center - Vector2.ONE * primitive.radius, Vector2.ONE * diameter), false, primitive.color)
		else:
			canvas.draw_arc(primitive.center, primitive.radius, 0.0, TAU, 64, primitive.color, primitive.width, true)

func _record_error(message: String) -> void:
	if runtime_errors.size() < 32 and message not in runtime_errors: runtime_errors.append(message)

static func validate_chart(raw: Dictionary, schemas: Array) -> Array:
	var errors := []
	for schema in schemas:
		var parts := ChartCodec.path_parts(str(schema.path))
		if not parts.is_empty(): _validate_at(raw, parts, 0, schema, "", errors)
	return errors

static func _validate_at(node: Variant, parts: Array, depth: int, schema: Dictionary, prefix: String, errors: Array) -> void:
	if typeof(node) != TYPE_DICTIONARY: return
	var part: Dictionary = parts[depth]
	if not node.has(part.key): return
	var label: String = prefix + str(part.key)
	if depth == parts.size() - 1:
		if not field_valid(node[part.key], schema):
			errors.append(label + " violates the declared " + str(schema.type) + " field schema")
		return
	if part.array:
		if typeof(node[part.key]) != TYPE_ARRAY:
			errors.append(label + " must be an array"); return
		for i in node[part.key].size(): _validate_at(node[part.key][i], parts, depth + 1, schema, label + "[" + str(i) + "].", errors)
	else:
		if typeof(node[part.key]) != TYPE_DICTIONARY:
			errors.append(label + " must be an object"); return
		_validate_at(node[part.key], parts, depth + 1, schema, label + ".", errors)
