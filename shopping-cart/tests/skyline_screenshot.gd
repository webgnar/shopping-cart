extends SceneTree
## Renders the parking garage's Manhattan skyline from a few spots and prints the frame's draw calls and
## triangles with and without it. Needs a window (or xvfb-run) and the local skyline files
## (`tools/manhattan_skyline.sh`):
##   godot -s res://tests/skyline_screenshot.gd -- <out dir>

const SHOTS := {
	"roof_east": [Vector3(20, 17.5, -3), Vector3(120, 30, -3)],
	"roof_north": [Vector3(40, 17.5, -3), Vector3(40, 40, -120)],
	"roof_west": [Vector3(80, 17.5, -3), Vector3(-40, 35, 10)],
	"roof_south": [Vector3(40, 17.5, 8), Vector3(60, 30, 120)],
	"street_exit": [Vector3(100, 1.6, 30), Vector3(0, 20, 30)],
	"overview": [Vector3(-60, 60, 90), Vector3(50, 5, -5)],
}

var level: Node3D


func _initialize() -> void:
	level = load("res://scenes/levels/parking_garage.tscn").instantiate()
	root.add_child(level)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://skyline"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	level.add_child(cam)
	for i in 30:
		await process_frame
	for shot: String in SHOTS:
		var spot: Array = SHOTS[shot]
		cam.current = true
		cam.look_at_from_position(spot[0], spot[1])
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, shot])
		print("SHOT ", shot)
	# Cost: the roof view with and without the skyline.
	cam.look_at_from_position(SHOTS.roof_east[0], SHOTS.roof_east[1])
	for state: bool in [true, false]:
		level.get_node("Skyline").visible = state
		for i in 30:
			await process_frame
		var vp := root.get_viewport_rid()
		print("SKYLINE %s: %d draws, %d triangles" % [
			"on" if state else "off",
			RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)])
	quit()
