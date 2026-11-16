@tool
extends EditorScript
## Open this script in the editor and use File > Run (Ctrl+Shift+X) to copy the cart's settings to the
## mobile web game (see cart_tuning_export.gd).


func _run() -> void:
	CartTuningExport.export()
