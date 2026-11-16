extends SceneTree
## Checks that tuning/cart_tuning.json (read by the mobile web game) matches the cart scene and floor materials.
## If it fails, run res://tools/export_cart_tuning.gd (File > Run in the editor) or:
##   godot --headless -s res://tools/export_cart_tuning_cli.gd
##   godot --headless -s res://tests/tuning_sync_test.gd


func _initialize() -> void:
	var want := CartTuningExport.current()
	var have: Variant = JSON.parse_string(FileAccess.get_file_as_string(CartTuningExport.JSON_PATH))
	var bad := []
	for k in want:
		if str(k).begins_with("_"):
			continue
		if typeof(have) != TYPE_DICTIONARY or not have.has(k) or JSON.stringify(have[k]) != JSON.stringify(want[k]):
			bad.append("%s: file %s, scene %s" % [k, JSON.stringify(have.get(k) if typeof(have) == TYPE_DICTIONARY else null), JSON.stringify(want[k])])
	for b in bad:
		print("FAIL  ", b)
	print("RESULT: %s" % ("ALL PASS" if bad.is_empty() else "OUT OF SYNC: run res://tools/export_cart_tuning_cli.gd"))
	quit(1 if bad else 0)
