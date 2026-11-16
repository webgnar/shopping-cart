extends SceneTree
## Headless: copies every level and the cart rig to the mobile web game (see tools/mobile_level_export.gd).
##   godot --headless -s res://tools/export_mobile_levels_cli.gd [-- garage market ...]


func _init() -> void:
	await process_frame
	var only := Array(OS.get_cmdline_user_args())
	await preload("res://tools/mobile_level_export.gd").export_all(self, only)
	quit()
