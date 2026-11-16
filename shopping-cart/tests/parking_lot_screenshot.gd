extends SceneTree
## Renders the parking lot level from a few viewpoints. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/parking_lot_screenshot.gd -- <output_prefix>

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/levels/parking_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://parking_lot"
	var out := "%s_%s.png" % [prefix, name]
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)


func _run() -> void:
	for i in 60:
		await process_frame
	await _shot("spawn")   # the game camera behind the cart at the spawn point
	main.set_process(false)   # take over the camera for overview shots
	var cam: Camera3D = main.camera
	cam.global_position = Vector3(-27, 14, 34)
	cam.look_at(Vector3(2, 0, 0))
	await _shot("overview")
	cam.global_position = Vector3(8, 1.7, 9)
	cam.look_at(Vector3(-2, 1.5, -16))
	await _shot("store")
	cam.global_position = Vector3(-6, 1.6, 2.5)
	cam.look_at(Vector3(-1.3, 0.6, -4))
	await _shot("corral")
	cam.global_position = Vector3(-1.5, 1.5, -8.8)
	cam.look_at(Vector3(-4.5, 0.6, -3.5))
	await _shot("car")
	cam.global_position = Vector3(-20.5, 2.2, -11.5)
	cam.look_at(Vector3(-25.8, 3.5, -1.0))
	await _shot("island")
	quit()
