## godot --headless --audio-driver Dummy --path game -s
## res://plugins/builtin/shape_tracks/convert_ext.gd -- input/chart.json input/chart.ext.json output.json
## Writes a new output only; never overwrites the input chart or sidecar.
extends SceneTree
const Converter = preload("res://plugins/builtin/shape_tracks/converter.gd")
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3:
		printerr("Usage: -- chart.json chart.ext.json NEW-output.json"); quit(2); return
	if FileAccess.file_exists(args[2]): printerr("Output already exists; refusing to overwrite"); quit(2); return
	var chart=SU.load_json(args[0]); var side=SU.load_json(args[1])
	if not chart is Dictionary or not side is Dictionary: printerr("Inputs must be JSON objects"); quit(2); return
	var result := Converter.from_sidecar(chart,side)
	if not result.errors.is_empty(): printerr("; ".join(result.errors)); quit(1); return
	var file := FileAccess.open(args[2],FileAccess.WRITE)
	if file == null: printerr("Cannot create output"); quit(1); return
	file.store_string(JSON.stringify(result.chart,"  ",true)+"\n"); file.close()
	print("Converted ",result.migrated.size()," tracks. Original chart.ext.json is unchanged; unrelated extensions remain there.")
	quit(0)
