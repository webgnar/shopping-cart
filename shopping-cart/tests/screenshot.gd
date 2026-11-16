extends SceneTree
## Renders the prototype mid-wheelie (a hard push, front wheels up) and saves a screenshot. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/screenshot.gd -- <output.png>

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	main.spawn_cart(Vector3(2, 0, -1), 0.5)
	for i in 90:
		await process_frame
	# Push hard until the front wheels come up off the floor.
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	for i in 600:
		await physics_frame
		if minf(main.cart.wheels.FL.global_position.y, main.cart.wheels.FR.global_position.y) > 0.2:
			break
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://screenshot.png"
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)
	quit()
