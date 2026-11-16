extends SceneTree
## Headless version of export_cart_tuning.gd:  godot --headless -s res://tools/export_cart_tuning_cli.gd


func _initialize() -> void:
	CartTuningExport.export()
	quit()
