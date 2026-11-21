extends SceneTree
## Renders the stacked carts in the parking lot: the stack by the spawn, the player's cart nested into it and
## pushing the herd, and the stack in corral 2A. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/cart_stack_screenshot.gd -- <output_prefix>

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/levels/parking_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 20:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://cart_stack"
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("SCREENSHOT %s_%s.png" % [prefix, name])


func _run() -> void:
	main.get_node("BotCarts").free()
	for i in 90:
		await physics_frame
	main.set_process(false)
	var cam: Camera3D = main.camera
	cam.global_position = Vector3(-6.3, 1.5, -5.6)
	cam.look_at(Vector3(-7.9, 0.55, -7.6))
	await _shot("stack")
	cam.global_position = Vector3(-1.3 + 1.6, 1.7, 12.6)
	cam.look_at(Vector3(-1.3, 0.5, 15.0))
	await _shot("corral")
	# Nest the player's cart into the stack by the spawn and push the herd along.
	var last: ShoppingCart = main.get_node("CartStacks/ByTheSpawn/Cart3")
	var behind := last.frame.global_transform * Vector3(-1.5, 0, 0)
	main.spawn_cart(Vector3(behind.x, 0, behind.z), last.heading())
	for i in 60:
		await physics_frame
	main.set_process(true)
	main.cart.power_ramp = 30.0
	Input.action_press("push_left")
	Input.action_press("push_right")
	for i in 240:
		await physics_frame
	Input.action_release("push_left")
	await _shot("pushing")
	Input.action_release("push_right")
	main.set_process(false)
	PhysicsServer3D.set_active(false)   # hold the herd still for the close-ups
	var front: ShoppingCart = main.cart.stack()[0]
	var p := front.frame.global_position
	var n := front.frame.global_basis.x
	cam.global_position = p + n * 1.6 + Vector3(0, 1.1, 1.6)
	cam.look_at(p + Vector3(0, 0.45, 0) - n * 0.4)
	await _shot("herd")
	cam.global_position = p - n * 0.2 + Vector3(0, 0.25, 1.3)
	cam.look_at(p + Vector3(0, 0.25, 0) - n * 0.2)
	await _shot("trays")
	quit()
