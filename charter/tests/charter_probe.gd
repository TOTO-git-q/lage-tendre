## Pure validator/geometry oracle for Python parity tests; input is a temporary JSON copy.
extends SceneTree

func _init() -> void:
	KB.set_layout("ansi")
	var args := OS.get_cmdline_user_args()
	var payload = SU.load_json(args[0])
	var out := []
	for raw in payload.charts:
		var c := ChartLib.validate(raw)
		out.append({"warnings": c.get("warnings", []), "notes": c.get("notes", []), "lights": c.get("lights", [])})
	var geometry := []
	var event_chart := ChartLib.validate({"lights": payload.get("events", [])})
	var tl := ChartLib.build_timelines(event_chart.lights)
	for query in payload.get("queries", []):
		geometry.append(ChartLib.light_at(tl.get(int(query[0])), query[1]))
	print("CHARTER_JSON:", JSON.stringify({"charts": out, "geometry": geometry}))
	quit()
