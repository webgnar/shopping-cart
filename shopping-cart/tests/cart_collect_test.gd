extends SceneTree
## Cart collection (scenes/levels/cart_collect_lot.tscn, console `collect`): the count holds every cart, then the
## player's cart (real keys) rams two loose carts from behind so they nest on, pushes the chain into the CART
## RETURN door, stops at the doorway while the two carts roll on in and cash in (10 + 15 points), and can't follow
## them in; a cart shoved in on its own is taken in for nobody's points; time's up shows the results.
##   godot --headless --fixed-fps 120 -s res://tests/cart_collect_test.gd

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/cart_collect_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-46s %s" % ["PASS" if ok else "FAIL", name, detail])


func _keys(names: Array) -> void:
	for a in ShoppingCart.ACTIONS:
		Input.action_release(a)
	for a in names:
		Input.action_press(a)


## Pushes at a walking pace (push when slow, let go when fast) until `done` is true or `seconds` run out.
func _push_until(cart: ShoppingCart, done: Callable, seconds: float) -> void:
	var t := 0.0
	var pushing := false
	while t < seconds and not done.call():
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


func _run() -> void:
	var game := get_first_node_in_group("cart_collect") as CartCollect
	await _wait(0.2)
	_check("30 loose carts in the lot", game.loose_carts().size() == 30, str(game.loose_carts().size()))
	_check("counting down, player held", game.phase == CartCollect.Phase.COUNTDOWN and main.cart.locked, "phase %d" % game.phase)
	_check("round is 5 minutes", is_equal_approx(game.duration, 300.0), "%.0f s" % game.duration)
	_keys(["push_left", "push_right"])
	await _wait(1.0)
	_check("keys do nothing during the count", main.cart.frame.linear_velocity.length() < 0.05, "")
	_keys([])
	while game.phase != CartCollect.Phase.COLLECTING:
		await physics_frame
	_check("GO: the player's cart is free", not main.cart.locked, "%.1f s left" % game.clock)

	# Two loose carts in a line in front of the door, and the player behind them, all facing in (-X).
	var a: ShoppingCart = game.loose_carts()[0]
	var b: ShoppingCart = game.loose_carts()[1]
	a.place(Vector3(2.0, 0, 0), PI)
	b.place(Vector3(4.5, 0, 0), PI)
	main.spawn_cart(Vector3(6.8, 0, 0), PI)
	main.cart.show_groceries(false)
	await _wait(0.5)
	var cart: ShoppingCart = main.cart
	var me: Dictionary = game.shoppers[0]
	await _push_until(cart, func(): return me.carrying >= 2, 20.0)
	_check("rammed from behind, both carts nest on", me.carrying == 2 and cart.stack().size() == 3,
		"pushing %d, stack %d" % [me.carrying, cart.stack().size()])

	var door_x := game.door.global_position.x
	await _push_until(cart, func(): return me.returned >= 2, 25.0)
	_check("both carts cash in", me.returned == 2, "%d returned" % me.returned)
	_check("10 + 15 points for a 2-cart drop", me.points == 25 and me.best_chain == 2, "%d points, chain %d" % [me.points, me.best_chain])
	_check("player's cart let go of them", cart.nested_in == null and me.carrying == 0, "")
	await _wait(0.3)
	var nose := (cart.frame.global_transform * Vector3(1.0, 0.5, 0)).x
	_check("player's cart stopped at the doorway", nose > door_x - 0.7, "nose at %.2f, door at %.2f" % [nose, door_x])
	var room := game.door.get_node("StoreRoom") as Node3D
	_check("returned carts put away in the store room",
		[a, b].all(func(c): return c.cart_origin().distance_to(room.global_position) < 4.0), "")

	# Keep pushing with nothing on the front: the doorway holds the cart back.
	await _push_until(cart, func(): return false, 3.0)
	nose = (cart.frame.global_transform * Vector3(1.0, 0.5, 0)).x
	_check("can't drive into the store", nose > door_x - 0.7 and me.points == 25, "nose at %.2f" % nose)

	# Back out, then shove a loose cart in on its own: taken in, no points.
	main.spawn_cart(Vector3(4.0, 0, 3.0), PI)
	var c: ShoppingCart = game.loose_carts()[2]
	c.place(Vector3(-7.0, 0, 0), PI)
	for body in c.bodies():
		body.linear_velocity = Vector3(-2.0, 0, 0)
	await _wait(2.5)
	_check("a cart shoved in alone is taken in for 0 points",
		game._returned.has(c) and me.points == 25, "%d points" % me.points)

	# Time's up.
	game.clock = 0.5
	await _wait(1.0)
	_check("time's up: results", game.phase == CartCollect.Phase.DONE and game.hud.get_node("%Results").visible, "")
	_check("player held after time's up", main.cart.locked, "")
	print(game.hud.get_node("%Table").text)
	print("%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
