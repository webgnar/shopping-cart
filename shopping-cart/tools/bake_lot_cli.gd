extends SceneTree
## Generates a level's LotGenerator lot into the level scene, so it is saved with it (like the generator's
## Generate button in the editor). For a lot paved with asphalt sections, bake those afterwards:
##   godot --headless -s res://tools/bake_lot_cli.gd -- <level.tscn>
##   xvfb-run godot --rendering-method gl_compatibility -s res://tools/bake_asphalt_sections_cli.gd -- <level.tscn>
##   godot --headless --import
##   godot --headless -s res://tools/bake_asphalt_sections_cli.gd -- <level.tscn> --assign


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <level.tscn>")
		quit(1)
		return
	var path := args[0] if args[0].begins_with("res://") else "res://" + args[0]
	var level := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	for g in level.find_children("*", "Node3D", true, false):
		if g is LotGenerator:
			# Out of the tree nothing is built yet: curbs and island fills build from their saved settings on load.
			g.generate_into(level)
			print("generated %s: %d stalls" % [g.name, g.stall_count])
	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("saved %s (%s)" % [path, error_string(err)])
	quit()
