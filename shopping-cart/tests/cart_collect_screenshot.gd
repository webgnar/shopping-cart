extends SceneTree
## Renders cart collection: the count at the store's CART RETURN door, a chain of carts being pushed down an aisle,
## the chain going in at the door, an overhead view of the lot and the results. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility --fixed-fps 120 -s res://tests/cart_collect_screenshot.gd -- <out dir>
## The lot renders slowly in software GL, so it only draws for the shots.

var main: Node3D
var game: CartCollect


func _initialize() -> void:
	main = load("res://scenes/levels/cart_collect_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(name: String) -> void:
	RenderingServer.render_loop_enabled = true
	await _frames(3)
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var path := dir.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)
	RenderingServer.render_loop_enabled = false


func _keys(names: Array) -> void:
	for a in ShoppingCart.ACTIONS:
		Input.action_release(a)
	for a in names:
		Input.action_press(a)


## Pushes at a walking pace until `done` is true or `seconds` run out.
func _push_until(done: Callable, seconds: float) -> void:
	var t := 0.0
	var pushing := false
	while t < seconds and not done.call():
		var cart: ShoppingCart = main.cart
		var v := cart.frame.linear_velocity.dot(cart.frame.global_transform.basis.x.normalized())
		if v < 0.9 and not pushing:
			pushing = true
			_keys(["push_left", "push_right"])
		elif v > 1.4 and pushing:
			pushing = false
			_keys([])
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_keys([])


func _line(xs: Array, z: float) -> void:
	var list := game.loose_carts()
	for i in xs.size():
		list[i].place(Vector3(xs[i], 0, z), PI)


func _run() -> void:
	game = get_first_node_in_group("cart_collect") as CartCollect
	main.cam_dist = 5.5
	main.cam_pitch = 0.3
	main.cam_yaw = PI   # looking back at the store from the lot
	RenderingServer.render_loop_enabled = false
	while game.clock > 1.6:
		await physics_frame
	await _shot("collect_countdown.png")
	while game.phase != CartCollect.Phase.COLLECTING:
		await physics_frame
	var me: Dictionary = game.shoppers[0]
	# A chain down the aisle.
	main.cam_yaw = 0.35
	main.cam_dist = 6.0
	_line([22.0, 24.5, 27.0, 29.5], 9.0)
	main.spawn_cart(Vector3(32.0, 0, 9.0), PI)
	await _wait(0.5)
	await _push_until(func(): return me.carrying >= 4, 25.0)
	await _push_until(func(): return main.cart.cart_origin().x < 20.0, 10.0)
	await _shot("collect_chain.png")
	# A chain going in at the door.
	_line([24.0, -0.5, 2.0, 4.5], 0.0)   # the first one is out of the way
	main.spawn_cart(Vector3(6.8, 0, 0), PI)
	main.cam_yaw = 0.5
	main.cam_dist = 4.5
	await _wait(0.5)
	await _push_until(func(): return me.carrying >= 3, 20.0)
	await _push_until(func(): return me.returned >= 1, 20.0)
	await _wait(0.15)
	await _shot("collect_drop.png")
	await _wait(1.0)
	await _shot("collect_cashed_in.png")
	# Overhead.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(40, 38, 0), Vector3(18, 0, 0))
	cam.fov = 60.0
	cam.current = true
	await _frames(10)
	await _shot("collect_overview.png")
	cam.current = false
	main.camera.current = true
	main.cam_yaw = 0.0
	main.cam_dist = 6.0
	main.spawn_cart(Vector3(4.0, 0, 9.0), PI)   # back out in the lot
	await _wait(0.5)
	game.clock = 0.2
	await _wait(0.5)
	await _shot("collect_results.png")
	quit()
