## Deliberately small scalar language. No objects, strings, property access or calls
## outside this list ever reach Expression; executable scripts are a separate tier.
class_name PluginFormula
extends RefCounted

const INPUTS := ["t", "note_t", "progress", "x", "w", "alpha", "u", "duration", "value", "pi", "tau"]
const FUNCTIONS := ["abs", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt", "pow", "exp", "log", "floor", "ceil", "round", "sign", "fmod", "posmod", "clamp", "min", "max", "lerp", "inverse_lerp", "smoothstep", "deg_to_rad", "rad_to_deg"]
const MAX_LENGTH := 512
const MAX_TOKENS := 128
var _expression: Expression
var source := ""

static func compile(value: Variant) -> Dictionary:
	var code: String
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
		code = str(value)
	elif typeof(value) == TYPE_STRING:
		code = value
	else:
		return {"errors": ["Formula must be a finite number or scalar expression"], "formula": null}
	var errors := _lexical_check(code)
	if not errors.is_empty(): return {"errors": errors, "formula": null}
	var result := PluginFormula.new()
	result.source = code
	result._expression = Expression.new()
	if result._expression.parse(code, PackedStringArray(INPUTS)) != OK:
		return {"errors": ["Invalid formula: " + result._expression.get_error_text()], "formula": null}
	return {"errors": [], "formula": result}

static func _lexical_check(code: String) -> Array:
	if code.is_empty() or code.length() > MAX_LENGTH: return ["Formula length must be 1..%d" % MAX_LENGTH]
	var token := RegEx.new()
	token.compile("^(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?|^[A-Za-z_][A-Za-z_0-9]*")
	var offset := 0
	var count := 0
	var depth := 0
	while offset < code.length():
		var ch := code.substr(offset, 1)
		if ch in [" ", "\t", "\n", "\r"]:
			offset += 1; continue
		count += 1
		if count > MAX_TOKENS: return ["Formula has too many tokens"]
		var found := token.search(code.substr(offset))
		if found:
			var word := found.get_string()
			var next := code.substr(offset + word.length()).strip_edges()
			if word.substr(0, 1) in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_":
				if next.begins_with("("):
					if word not in FUNCTIONS: return ["Formula function is not allowed: " + word]
				elif word not in INPUTS: return ["Formula input is not allowed: " + word]
			else:
				# Bound exponents before Godot's string conversion so malformed input
				# never emits engine overflow warnings during a safe validation pass.
				if word.length() > 64: return ["Formula number is too long"]
				var exponent_at := word.to_lower().find("e")
				if exponent_at >= 0 and absf(float(word.substr(exponent_at + 1))) > 308.0:
					return ["Formula numeric exponent is out of range"]
				if not is_finite(float(word)): return ["Formula number is not finite"]
			offset += word.length(); continue
		if ch not in ["+", "-", "*", "/", "%", "(", ")", ","]:
			return ["Formula token is not allowed: " + ch]
		if ch == "(": depth += 1
		if ch == ")": depth -= 1
		if depth < 0 or depth > 24: return ["Formula nesting is invalid or too deep"]
		offset += 1
	if depth != 0: return ["Formula parentheses are unbalanced"]
	return []

func evaluate(inputs := {}) -> Dictionary:
	var values := []
	for name in INPUTS:
		var value: Variant = PI if name == "pi" else (TAU if name == "tau" else inputs.get(name, 0.0))
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {"ok": false, "value": 0.0, "error": "Formula input must be finite scalar: " + name}
		values.append(float(value))
	var result: Variant = _expression.execute(values, null, false, true)
	if _expression.has_execute_failed():
		return {"ok": false, "value": 0.0, "error": "Formula evaluation failed: " + _expression.get_error_text()}
	if typeof(result) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(result)):
		return {"ok": false, "value": 0.0, "error": "Formula result must be a finite scalar"}
	return {"ok": true, "value": float(result), "error": ""}
