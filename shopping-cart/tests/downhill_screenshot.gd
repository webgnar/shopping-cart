extends SceneTree
## Renders the downhill highway from a few viewpoints. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/downhill_screenshot.gd -- <out dir>

var main: Node3D
var dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		dir = args[0]
	main = load("res://scenes/levels/downhill_highway.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	var out := dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)


func _at(offset: float, lateral := 0.0, up := 0.0) -> Vector3:
	var curve: Curve3D = (main.get_node("Road") as Path3D).curve
	var xf := curve.sample_baked_with_rotation(offset)
	return xf.origin + xf.basis.x * lateral + Vector3.UP * up


func _look(from: Vector3, at: Vector3) -> void:
	main.camera.global_position = from
	main.camera.look_at(at)


func _run() -> void:
	for i in 60:
		await process_frame
	await _shot("spawn")   # the game camera behind the cart on the grid
	main.set_process(false)   # take over the camera
	main.hud.visible = false
	_look(_at(10, 0, 3), _at(160, 0, -10))
	await _shot("top_looking_down")
	_look(_at(250, -4.6, 1.6), _at(320, -1.0, -3))
	await _shot("halfway")
	_look(_at(330, 1.5, 1.7), _at(230, 0, 0))
	await _shot("looking_back_up")
	_look(_at(560, 2, 3), _at(400, 0, 30))
	await _shot("from_the_finish")
	_look(_at(620, 0, 25), _at(150, 0, 0))
	await _shot("from_below")
	quit()
