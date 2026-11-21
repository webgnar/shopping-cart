extends SceneTree
## Fails when a level or the cart changed since the browser version's copy was exported (mobile/levels/).
## Fix: godot --headless -s res://tools/export_mobile_levels_cli.gd   (then commit mobile/levels/)

const Export := preload("res://tools/mobile_level_export.gd")


func _initialize() -> void:
	var failures := 0
	var checks := [["cart", Export.CART_SCENE]]
	for d in Export.destinations():
		checks.append([d.key, d.scene])
		# An endless level's chunks (scenes/sandbox/chunks/) are exported one by one.
		var path: String = Export.out_path(d.key + ".json")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if data is Dictionary and data.has("stream"):
			for c in data.stream.chunks:
				checks.append([c.key, c.scene])
	for c in checks:
		var path: String = Export.out_path(c[0] + ".json")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var want := Export.source_hash(c[1])
		var have: String = data.get("source", "") if data is Dictionary else "missing"
		var ok: bool = have == want and (c[0] == "cart" or FileAccess.file_exists(Export.out_path(c[0] + ".glb")))
		if not ok:
			failures += 1
		print("%-5s %-14s %s" % ["PASS" if ok else "FAIL", c[0], "in sync" if ok else "out of date (export says %s, scenes say %s)" % [have, want]])
	if failures:
		print("Run: godot --headless -s res://tools/export_mobile_levels_cli.gd")
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
