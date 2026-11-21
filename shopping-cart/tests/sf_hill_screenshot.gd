extends SceneTree
## Renders the San Francisco hill level from a few viewpoints. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/sf_hill_screenshot.gd -- <output_prefix>

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/levels/sf_hill.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://sf_hill"
	var out := "%s_%s.png" % [prefix, name]
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)


func _look(from: Vector3, at: Vector3) -> void:
	main.camera.global_position = from
	main.camera.look_at(at)


func _run() -> void:
	for i in 60:
		await process_frame
	await _shot("spawn")   # the game camera behind the cart at the top
	main.set_process(false)   # take over the camera
	var c1: Vector3 = main.get_node("Street/Crossing1").global_position
	var c4: Vector3 = main.get_node("Street/Crossing4").global_position
	var c5: Vector3 = main.get_node("Street/Crossing5").global_position
	_look(Vector3(c1.x - 14, c1.y + 1.6, 2), Vector3(c1.x + 60, c1.y - 12, 0))
	await _shot("crest")         # looking down the first hill from the top crossing
	_look(Vector3(c1.x - 12, c1.y + 1.4, 3.5), Vector3(c1.x + 2, c1.y + 0.6, -12))
	await _shot("cross_traffic")
	_look(Vector3(c5.x - 3, c5.y + 1.7, 4.5), Vector3(c4.x + 20, c4.y + 8, -2))
	await _shot("steep_from_below")   # the 31% block from the foot of it
	_look(Vector3(c4.x + 30, c4.y - 4.6, -3.0), Vector3(c4.x + 24, c4.y - 1.5, 14))
	await _shot("houses")
	_look(Vector3(c5.x - 30, c5.y + 22, 0), Vector3(c5.x + 120, -2, 0))
	await _shot("to_the_bay")
	_look(Vector3(c1.x - 120, c1.y + 60, 90), Vector3(c4.x, c4.y, 0))
	await _shot("overview")
	quit()
