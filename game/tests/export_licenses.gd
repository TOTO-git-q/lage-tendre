## Extract the license notices of the installed engine, without network access.
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1); return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		quit(1); return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\nBundled components\n\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(), "  ") + "\n\n")
	for name in Engine.get_license_info():
		file.store_string(str(name) + "\n" + str(Engine.get_license_info()[name]) + "\n\n")
	file.close()
	quit()
