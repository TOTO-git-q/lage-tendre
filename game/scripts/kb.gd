## Physical keyboard model (port of [1] KEYBOARD).  The judgement line is the main block, 15 units wide
## (one letter key = 1u); every key keeps its real x range.  The letter rows are identical in ANSI / ISO /
## JIS, so charts never depend on the layout -- only the keys around the edges differ.
class_name KB

const LAYOUT_NAMES := ["ansi", "ansi65", "iso", "jis"]

static var layout := "ansi"
static var list: Array = []           # [{code, row, x0, w, cx}]
static var by_code := {}

static func _digits() -> Array:
	var a := []
	for i in 10:
		a.append(["Digit" + str((i + 1) % 10), 1.0 + i, 1.0])
	return a

static func _letters(s: String, x0: float) -> Array:
	var a := []
	for i in s.length():
		a.append(["Key" + s[i], x0 + i, 1.0])
	return a

static func rows(name: String) -> Array:
	var d := _digits()
	match name:
		"iso":
			return [
				[["Backquote", 0.0, 1.0]] + d + [["Minus", 11.0, 1.0], ["Equal", 12.0, 1.0], ["Backspace", 13.0, 2.0]],
				[["Tab", 0.0, 1.5]] + _letters("QWERTYUIOP", 1.5) + [["BracketLeft", 11.5, 1.0], ["BracketRight", 12.5, 1.0], ["Enter", 13.5, 1.5]],
				[["CapsLock", 0.0, 1.75]] + _letters("ASDFGHJKL", 1.75) + [["Semicolon", 10.75, 1.0], ["Quote", 11.75, 1.0], ["Backslash", 12.75, 1.0]],
				[["ShiftLeft", 0.0, 1.25], ["IntlBackslash", 1.25, 1.0]] + _letters("ZXCVBNM", 2.25) + [["Comma", 9.25, 1.0], ["Period", 10.25, 1.0], ["Slash", 11.25, 1.0], ["ShiftRight", 12.25, 2.75]],
			]
		"jis":
			return [
				[["Backquote", 0.0, 1.0]] + d + [["Minus", 11.0, 1.0], ["Equal", 12.0, 1.0], ["IntlYen", 13.0, 1.0], ["Backspace", 14.0, 1.0]],
				[["Tab", 0.0, 1.5]] + _letters("QWERTYUIOP", 1.5) + [["BracketLeft", 11.5, 1.0], ["BracketRight", 12.5, 1.0], ["Enter", 13.5, 1.5]],
				[["CapsLock", 0.0, 1.75]] + _letters("ASDFGHJKL", 1.75) + [["Semicolon", 10.75, 1.0], ["Quote", 11.75, 1.0], ["Backslash", 12.75, 1.0]],
				[["ShiftLeft", 0.0, 2.25]] + _letters("ZXCVBNM", 2.25) + [["Comma", 9.25, 1.0], ["Period", 10.25, 1.0], ["Slash", 11.25, 1.0], ["IntlRo", 12.25, 1.0], ["ShiftRight", 13.25, 1.75]],
			]
		"ansi65":                      # 75% / 65% and laptops whose right Shift is short (1.75u, the arrow key beside it)
			var a: Array = rows("ansi")
			a[3] = a[3].slice(0, a[3].size() - 1) + [["ShiftRight", 12.25, 1.75]]
			return a
		_:
			return [
				[["Backquote", 0.0, 1.0]] + d + [["Minus", 11.0, 1.0], ["Equal", 12.0, 1.0], ["Backspace", 13.0, 2.0]],
				[["Tab", 0.0, 1.5]] + _letters("QWERTYUIOP", 1.5) + [["BracketLeft", 11.5, 1.0], ["BracketRight", 12.5, 1.0], ["Backslash", 13.5, 1.5]],
				[["CapsLock", 0.0, 1.75]] + _letters("ASDFGHJKL", 1.75) + [["Semicolon", 10.75, 1.0], ["Quote", 11.75, 1.0], ["Enter", 12.75, 2.25]],
				[["ShiftLeft", 0.0, 2.25]] + _letters("ZXCVBNM", 2.25) + [["Comma", 9.25, 1.0], ["Period", 10.25, 1.0], ["Slash", 11.25, 1.0], ["ShiftRight", 12.25, 2.75]],
			]

static func set_layout(name: String) -> void:
	if not name in LAYOUT_NAMES:
		name = "ansi"
	layout = name
	list.clear()
	by_code.clear()
	var r := 0
	for row in rows(name):
		for k in row:
			var e := {"code": k[0], "row": r, "x0": k[1], "w": k[2], "cx": (k[1] + k[2] / 2.0) / 15.0}
			list.append(e)
			by_code[k[0]] = e
		r += 1

## the line runs from the left Shift's left edge to the right Shift's right edge (= the screen edges); charts are in
## 15 units, so on a keyboard whose right Shift ends earlier the 15-unit line reaches past the right screen edge
static func span() -> float:
	return by_code.ShiftRight.x0 + by_code.ShiftRight.w if by_code.has("ShiftRight") else 15.0

static func is_key(code: String) -> bool:
	return by_code.has(code)

static func x_of(code: String) -> float:
	return by_code[code].cx if by_code.has(code) else 0.5

static func centers_in(a: float, b: float) -> int:
	var n := 0
	for k in list:
		if k.cx >= a - SU.EPS and k.cx <= b + SU.EPS:
			n += 1
	return n

# ---------------------------------------------------------------- Godot key -> code name
const _NAMED := {
	KEY_QUOTELEFT: "Backquote", KEY_MINUS: "Minus", KEY_EQUAL: "Equal", KEY_BACKSPACE: "Backspace", KEY_TAB: "Tab",
	KEY_BRACKETLEFT: "BracketLeft", KEY_BRACKETRIGHT: "BracketRight", KEY_BACKSLASH: "Backslash", KEY_CAPSLOCK: "CapsLock",
	KEY_SEMICOLON: "Semicolon", KEY_APOSTROPHE: "Quote", KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_COMMA: "Comma",
	KEY_PERIOD: "Period", KEY_SLASH: "Slash", KEY_SPACE: "Space", KEY_YEN: "IntlYen", KEY_SECTION: "IntlBackslash",
	KEY_JIS_KANA: "KanaMode", KEY_JIS_EISU: "NonConvert", KEY_ESCAPE: "Escape",
	KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight",
}

## physical position name of a key event ("KeyA", "ShiftLeft", "Space", ...), or "" if unknown
static func code_of(e: InputEventKey) -> String:
	var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k == KEY_SHIFT:
		return "ShiftRight" if e.location == KEY_LOCATION_RIGHT else "ShiftLeft"
	return _NAMED.get(k, "")

## keys that act as the pedal: Space everywhere; JIS thumbs also reach the IME keys beside a short space bar
static func is_pedal(code: String) -> bool:
	return code == "Space" or code == "NonConvert" or code == "KanaMode" or code == "Convert"

## codes that only exist on one layout family (auto-detect)
static func hint(code: String) -> String:
	if code in ["IntlYen", "IntlRo", "NonConvert", "Convert", "KanaMode"]:
		return "jis"
	if code == "IntlBackslash":
		return "iso"
	return ""

static func label(code: String) -> String:
	if layout == "jis":
		var j := {"Backquote": "半", "Equal": "^", "BracketLeft": "@", "BracketRight": "[", "Quote": ":", "Backslash": "]"}
		if j.has(code):
			return j[code]
	if layout == "iso" and code == "Backslash":
		return "#"
	var m := {"Backquote": "`", "Minus": "-", "Equal": "=", "Backspace": "⌫", "Tab": "Tab", "BracketLeft": "[", "BracketRight": "]",
		"Backslash": "\\", "CapsLock": "Caps", "Semicolon": ";", "Quote": "'", "Enter": "⏎", "ShiftLeft": "⇧", "ShiftRight": "⇧",
		"Comma": ",", "Period": ".", "Slash": "/", "IntlBackslash": "\\", "IntlYen": "¥", "IntlRo": "ろ"}
	if m.has(code):
		return m[code]
	return code.trim_prefix("Key").trim_prefix("Digit")
