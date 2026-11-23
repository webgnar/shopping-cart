extends SceneTree
## Renders generated parking lots (scenes/levels/generated_lot.tscn) at each stall angle, and the 90 degree lot
## on aged asphalt (scenes/levels/lot90.tscn). From the Godot project:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/lot_generator_screenshot.gd -- <out dir>
## Writes <angle>_overview.png for 90/60/45/30 (60 and 30 with one-way aisles), plus 90_entrance.png and
## 45_island.png from near the ground; lot90_overview.png, lot90_entrance.png and lot90_stalls.png.

const LEVEL := "res://scenes/levels/generated_lot.tscn"
const LOT90 := "res://scenes/levels/lot90.tscn"

## options (or the level, for lot90), shot name, camera position, look at
const SHOTS := [
	[LOT90, "lot90_overview", Vector3(-10, 30, 0), Vector3(26, 0, 0)],
	[LOT90, "lot90_entrance", Vector3(-5, 1.6, 1.5), Vector3(8, 0.3, -3)],
	[LOT90, "lot90_stalls", Vector3(14, 2.2, -2), Vector3(20, 0, -9)],
	[{ stall_angle = 90, seed = 1 }, "90_overview", Vector3(-12, 38, 0), Vector3(30, 0, 0)],
	[{ stall_angle = 90, seed = 1 }, "90_entrance", Vector3(-5, 1.6, 1.5), Vector3(8, 0.3, -3)],
	[{ stall_angle = 60, two_way = false, seed = 2 }, "60_overview", Vector3(-12, 38, 0), Vector3(30, 0, 0)],
	[{ stall_angle = 45, seed = 3 }, "45_overview", Vector3(-12, 38, 0), Vector3(30, 0, 0)],
	[{ stall_angle = 45, seed = 3 }, "45_island", Vector3(4, 1.8, 2), Vector3(10.5, 0.2, 9)],
	[{ stall_angle = 30, two_way = false, seed = 4 }, "30_overview", Vector3(-12, 38, 0), Vector3(30, 0, 0)],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://lot_gen"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	for s: Array in SHOTS:
		if s[0] is String:
			change_scene_to_file(s[0])
		else:
			LotGenerator.next_options = s[0]
			change_scene_to_file(LEVEL)
		for i in 30:
			await process_frame
		for layer in current_scene.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		var cam := Camera3D.new()
		current_scene.add_child(cam)
		cam.fov = 60.0
		cam.far = 400.0
		cam.look_at_from_position(s[2], s[3])
		cam.current = true
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, s[1]])
	quit()
