## Compatibility data exported by the built-in plugin.
class_name BuiltinStageData
extends RefCounted

const CH := {
	"exposure": [0.85, 0.25, 1.15], "zoom": [1.0, 0.96, 1.06], "roll": [0.0, -3.0, 3.0], "pitch": [0.0, -43.0, 65.0],
	"vpx": [0.0, -77.0, 77.0], "bow": [1.0, 0.85, 1.3], "rush": [1.0, 0.5, 3.0], "flash": [0.0, 0.0, 0.25],
	"trauma": [0.0, 0.0, 0.5], "kick": [0.0, 0.0, 1.0],
	"line_y": [0.0, -0.04, 0.04], "line_tilt": [0.0, -2.0, 2.0], "line_glow": [1.0, 0.5, 1.5],
}
const MODE := {
	"full": {"zoom": 1.0, "roll": 1.0, "trauma": 1.0, "flash": 1.0, "vpx": 1.0, "pitch": 1.0},
	"reduced": {"zoom": 0.5, "roll": 0.0, "trauma": 0.0, "flash": 0.4, "vpx": 0.6, "pitch": 1.0},
	"off": {"zoom": 0.0, "roll": 0.0, "trauma": 0.0, "flash": 0.0, "vpx": 0.0, "pitch": 0.0},
}
