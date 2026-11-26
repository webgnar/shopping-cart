extends SceneTree
## Renders the sandbox's measurement lanes (scenes/sandbox/measurement_lanes.tscn) from above and from the cart's
## camera at a few Start markers. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/lanes_screenshot.gd -- <out dir>

var main: Node3D
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String, frames := 30) -> void:
	for i in frames:
		await process_frame
	var path := out_dir.path_join("lanes_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


## Freezes the follow camera and looks from `from` at `at`.
func _view(from: Vector3, at: Vector3) -> void:
	main.set_process(false)
	main.camera.global_position = from
	main.camera.look_at(at)


func _run() -> void:
	main.hud._force_sign.visible = false
	await _shot("start", 10)
	_view(Vector3(-24, 9, 20), Vector3(0, 0, 20))
	await _shot("north")
	_view(Vector3(-9, 8, -11), Vector3(0, 0, -20))
	await _shot("pad")
	_view(Vector3(29, 5, -4), Vector3(46, 0, -20))
	await _shot("curbs_bumps")
	_view(Vector3(6, 4, -9), Vector3(19, 0.5, -20))
	await _shot("slopes")
	main.set_process(true)
	for lane in ["coast", "brake", "pad", "slope2", "slope5", "slope10", "curbs", "bumps"]:
		main._next_lane()
		await _shot("cam_" + lane, 60)
	quit()
