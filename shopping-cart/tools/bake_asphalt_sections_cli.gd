extends SceneTree
## Bakes every AsphaltSection in a level so it loads without simulating:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tools/bake_asphalt_sections_cli.gd -- <level.tscn>
##   godot --headless --import
##   godot --headless -s res://tools/bake_asphalt_sections_cli.gd -- <level.tscn> --assign
## The first run simulates each section (needs a renderer for the colour map) and writes
## assets/asphalt/baked/<level>/<section>_color.webp and _height.res. The --assign run, after the colour maps are imported,
## sets each section's color_map and height_map in the level scene. Re-bake after changing a section's
## seed, year or road crew, or the simulator.

const OUT := "res://assets/asphalt/baked/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <level.tscn> [--assign]")
		quit(1)
		return
	var path := args[0] if args[0].begins_with("res://") else "res://" + args[0]
	var dir := OUT + path.get_file().get_basename() + "/"
	if "--assign" in args:
		_assign(path, dir)
	else:
		await _bake(path, dir)
	quit()


func _bake(path: String, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var level := (load(path) as PackedScene).instantiate()
	var sections := _sections(level)
	for s in sections:
		s.color_map = null
		s.height_map = null
	root.add_child(level)
	for i in 3:
		await process_frame
	for s in sections:
		var base: String = dir + String(s.name).to_snake_case()
		var color: Image = s.color_image.duplicate()
		color.clear_mipmaps()
		color.save_webp(ProjectSettings.globalize_path(base + "_color.webp"), true, 0.9)
		ResourceSaver.save(s.height_image, base + "_height.res", ResourceSaver.FLAG_COMPRESS)
		print("baked ", base)


func _assign(path: String, dir: String) -> void:
	var level := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	for s in _sections(level):
		var base: String = dir + String(s.name).to_snake_case()
		s.color_map = load(base + "_color.webp")
		s.height_map = load(base + "_height.res")
	var packed := PackedScene.new()
	packed.pack(level)
	ResourceSaver.save(packed, path)
	print("assigned ", path)


func _sections(level: Node) -> Array[AsphaltSection]:
	var out: Array[AsphaltSection] = []
	for n in level.find_children("*", "Node3D", true, false):
		if n is AsphaltSection:
			out.append(n)
	return out
