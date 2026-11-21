extends SceneTree
## Renders the sandbox (the endless parking lot) from a few viewpoints, including from 2 km away to show the lot
## carrying on. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/sandbox_screenshot.gd -- <output_prefix> [scene]

var main: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	main = load(args[1] if args.size() > 1 else "res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://sandbox"
	var out := "%s_%s.png" % [prefix, name]
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)


func _view(from: Vector3, at: Vector3) -> void:
	main.camera.global_position = from
	main.camera.look_at(at)


func _run() -> void:
	for i in 60:
		await process_frame
	await _shot("spawn")   # the game camera behind the cart at the spawn point
	main.set_process(false)   # take over the camera for the other shots
	_view(Vector3(-30, 22, 40), Vector3(10, 0, 0))
	await _shot("overview")
	_view(Vector3(8, 2.2, 3.5), Vector3(30, 0.3, 0))
	await _shot("test_strip")
	_view(Vector3(47.5, 1.6, 13.25), Vector3(53.5, 2.5, 4.75))
	await _shot("island")
	# Far away: the chunks stream in around the cart, so the lot looks the same 2 km out.
	main.spawn_cart(Vector3(2000, 0.05, 2000), 0.0)
	_view(Vector3(2000, 22, 2040), Vector3(2040, 0, 2000))
	for i in 60:
		await process_frame
	await _shot("far")
	quit()
