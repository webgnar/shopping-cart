extends SceneTree
## Headless: bakes the navigation mesh of every level that has a NavigationRegion3D (what the bot carts drive on)
## and saves it to the region's own resource file (assets/navigation/<level>.tres). Same as selecting the region in
## the editor and pressing Bake NavigationMesh. Run again after moving shelves, cars, walls or anything solid.
##   godot --headless -s res://tools/bake_navigation_cli.gd [-- res://scenes/levels/supermarket.tscn ...]
##
## Each navigation mesh parses the static colliders of the nodes in its group (the level root is in the group
## "navigation_geometry", with its children), so loose props and carts are left out.

const LEVELS := ["res://scenes/levels/supermarket.tscn", "res://scenes/levels/parking_lot.tscn",
	"res://scenes/levels/parking_garage.tscn"]


func _init() -> void:
	await process_frame
	var only := Array(OS.get_cmdline_user_args())
	for path in (only if not only.is_empty() else LEVELS):
		var level: Node = (load(path) as PackedScene).instantiate()
		# Bake from the scene as saved: scripts that build or move things at start don't run (no _ready on a
		# node outside the tree is fine; the level root's script only spawns the player's cart).
		level.set_script(null)
		root.add_child(level)
		await process_frame
		for region: NavigationRegion3D in level.find_children("*", "NavigationRegion3D", true, false):
			var nm := region.navigation_mesh
			var t := Time.get_ticks_msec()
			region.bake_navigation_mesh(false)
			var err := ResourceSaver.save(nm, nm.resource_path)
			print("NAV %s/%s: %d polygons, %d vertices, %d ms -> %s (%s)" % [path.get_file(), region.name,
				nm.get_polygon_count(), nm.get_vertices().size(), Time.get_ticks_msec() - t, nm.resource_path,
				"ok" if err == OK else error_string(err)])
		level.queue_free()
		await process_frame
	quit()
