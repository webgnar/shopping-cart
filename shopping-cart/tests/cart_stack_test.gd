extends SceneTree
## Stacked (nested) carts in the parking lot: the stacks stand still, the player's cart nests into the back of a
## stack by pushing in, the herd rolls and turns as one without jitter, a hard yank pulls the cart back off, and a
## hard side knock pops a nest apart. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/cart_stack_test.gd

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/parking_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-30s %s" % ["PASS" if ok else "FAIL", name, detail])


func _keys(names: Array, down: bool) -> void:
	for a in ShoppingCart.ACTIONS:
		Input.action_release(a)
	if down:
		for a in names:
			Input.action_press(a)


## The fastest any body of these carts is moving, m/s (an exploding joint shows up here).
func _max_speed(carts: Array) -> float:
	var v := 0.0
	for c in carts:
		for b in c.bodies():
			v = maxf(v, b.linear_velocity.length())
	return v


## How far each nested cart sits from fully in, m (0 = fully in).
func _gaps(carts: Array) -> Array:
	var out := []
	for c in carts:
		if c.nest:
			out.append(snappedf(c.nest.get("linear_limit_x/upper_distance") - c.nest.slide(), 0.001))
	return out


## Rolls a box of `mass` kg at `speed` m/s into the side of `cart`'s basket.
func _ram(cart: ShoppingCart, mass: float, speed: float) -> void:
	var side := cart.frame.global_transform.basis.z.normalized()
	var ram := RigidBody3D.new()
	ram.mass = mass
	ram.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.4, 0.4, 0.4)
	ram.add_child(shape)
	main.add_child(ram)
	ram.global_position = cart.basket_centre() + Vector3(0, 0.25, 0) + side * 1.0
	ram.linear_velocity = -side * speed
	await _wait(1.2)
	ram.queue_free()


func _stack_named(n: String) -> Array:
	var cart: ShoppingCart = main.get_node("CartStacks/%s/Cart1" % n)
	return cart.stack()


func _run() -> void:
	# The level's bot carts roam the lot; take them out so they can't wander into the stacks mid-check.
	main.get_node("BotCarts").free()
	await _wait(1.0)
	var by_spawn := _stack_named("ByTheSpawn")
	var corral := _stack_named("InCorral2A")
	_check("stacks are built", by_spawn.size() == 3 and corral.size() == 4,
		"%d carts by the spawn, %d in corral 2A" % [by_spawn.size(), corral.size()])

	# Standing still: nothing creeps, nothing jitters, the noses stay fully in.
	var start: Vector3 = by_spawn[0].cart_origin()
	await _wait(3.0)
	var creep: float = (by_spawn[0].cart_origin() - start).length()
	var still := by_spawn.all(func(c): return c.frame.freeze) and corral.all(func(c): return c.frame.freeze)
	_check("stacks stand still", creep < 0.01 and still and _max_speed(by_spawn + corral) < 0.05,
		"crept %.3f m, all frozen %s, gaps %s %s" % [creep, still, _gaps(by_spawn), _gaps(corral)])
	var gates_up := true
	var angles := []
	for c in by_spawn:
		var a: float = (c.frame.global_basis.inverse() * c.gate.global_basis).get_euler().z
		angles.append(snappedf(a, 0.01))
		gates_up = gates_up and (a > 0.9 if c.nested_behind else a < 0.5)
	_check("gates swing up", gates_up, "gate angles %s (front to back)" % [angles])

	# Nest the player's cart: straight behind the stack, push in.
	var last: ShoppingCart = by_spawn[2]
	var behind := last.frame.global_transform * Vector3(-1.6, 0, 0)
	main.spawn_cart(Vector3(behind.x, 0, behind.z + 0.04), last.heading() + 0.05)
	await _wait(1.0)
	var cart: ShoppingCart = main.cart
	cart.power_ramp = 40.0
	_keys(["push_left", "push_right"], true)
	var t := 0.0
	while cart.nested_in == null and t < 6.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check("pushing in nests the cart", cart.nested_in == last, "nested after %.2f s" % t)
	var herd := cart.stack()
	var peak := 0.0
	var p0: Vector3 = herd[0].cart_origin()
	var jitter := 0.0
	for i in 5 * Engine.physics_ticks_per_second:
		await physics_frame
		peak = maxf(peak, _max_speed(herd))
		for c in herd:
			if c.nest:
				jitter = maxf(jitter, absf(c.frame.angular_velocity.y - c.nested_in.frame.angular_velocity.y))
	var moved: float = (herd[0].cart_origin() - p0).length()
	var v: float = herd[0].frame.linear_velocity.length()
	_check("herd rolls as one", herd.size() == 4 and moved > 2.0 and peak < 6.0,
		"%d carts, front moved %.2f m, at %.2f m/s, fastest body %.2f m/s, gaps %s" % [herd.size(), moved, v, peak, _gaps(herd)])
	_check("no wobble between carts", jitter < 1.5, "largest yaw-rate difference between nested carts %.2f rad/s" % jitter)
	var upright := herd.all(func(c): return c.frame.global_transform.basis.y.y > 0.95 and c.wheels_down() == 4)
	_check("every caster on the ground", upright, "")

	# Turning: one hand alone hardly turns a herd (every cart's fixed rear wheels scrub); pushing one side and
	# pulling the other does, slowly.
	_keys([], false)
	await _wait(3.0)
	var h0 := cart.heading()
	_keys(["push_right"], true)
	await _wait(2.0)
	var one_hand := absf(wrapf(cart.heading() - h0, -PI, PI))
	_keys([], false)
	await _wait(3.0)
	h0 = cart.heading()
	_keys(["push_right", "pull_left"], true)
	await _wait(2.0)
	var turned := absf(wrapf(cart.heading() - h0, -PI, PI))
	_check("herd turns, slowly", turned > deg_to_rad(6.0) and turned < deg_to_rad(60.0) and one_hand < turned and cart.stack().size() == 4,
		"one hand %.0f degrees in 2 s, push and pull %.0f degrees in 2 s" % [rad_to_deg(one_hand), rad_to_deg(turned)])

	# Coast to a stop, then yank back with both hands: the player's cart slides out and comes off.
	_keys([], false)
	await _wait(4.0)
	# A hard yank: past what the hands' caps allow (drive_max levels the pull off near 160 N a hand and
	# reverse_speed stops it at a backward walk), which would only roll the free-standing stack back with the cart.
	cart.power_ramp = 400.0
	cart.drive_max = 800.0
	cart.reverse_speed = 5.0
	_keys(["pull_left", "pull_right"], true)
	t = 0.0
	while cart.nested_in != null and t < 4.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_keys([], false)
	_check("yanking back pulls it off", cart.nested_in == null and herd[2].nested_behind == null and herd[0].stack().size() == 3,
		"came off after %.2f s, stack left with %d carts" % [t, herd[0].stack().size()])
	await _wait(2.0)
	_check("apart carts collide again", cart.ghosts.is_empty(), "%d ghosts left" % cart.ghosts.size())

	# A gentle bump on the side of the back cart of the stack by the spawn leaves it nested; something heavy
	# rolling hard into it pops that cart out.
	await _wait(2.0)
	var tail: ShoppingCart = by_spawn[2]
	await _ram(tail, 20.0, 1.0)
	_check("a gentle bump keeps the nest", tail.nested_in != null and _max_speed(by_spawn) < 3.0,
		"stack %d carts" % by_spawn[0].stack().size())
	await _wait(2.0)
	await _ram(tail, 60.0, 4.0)
	_check("a side knock breaks the nest", tail.nested_in == null and by_spawn[0].stack().size() == 2 and _max_speed(by_spawn) < 8.0,
		"stack now %d carts, fastest body %.2f m/s" % [by_spawn[0].stack().size(), _max_speed(by_spawn)])

	# Into corral 2A's open end: the cart nests onto the stack there, and shoving on rams the herd into the closed
	# end. The carts jam together; nothing flies apart.
	main.spawn_cart(Vector3(-1.3, 0, 10.5), -PI / 2)
	await _wait(1.0)
	cart = main.cart
	cart.power_ramp = 120.0
	_keys(["push_left", "push_right"], true)
	peak = 0.0
	var fastest := 0.0
	for i in 5 * Engine.physics_ticks_per_second:
		await physics_frame
		peak = maxf(peak, _max_speed(corral))
		fastest = maxf(fastest, cart.frame.linear_velocity.length())
	_keys([], false)
	await _wait(1.0)
	var jammed := cart.stack()
	var upright2 := jammed.all(func(c): return c.frame.global_transform.basis.y.y > 0.9)
	_check("nests in the corral", jammed.size() == 5, "%d carts, reached %.2f m/s" % [jammed.size(), fastest])
	_check("ramming the corral end holds", peak < 5.0 and upright2 and corral[0].cart_origin().z < 16.0,
		"fastest body %.2f m/s, all upright %s, gaps %s, front cart at z %.2f" % [peak, upright2, _gaps(jammed), corral[0].cart_origin().z])

	# Physics cost of the scene with the stacks in it.
	var t0 := Time.get_ticks_usec()
	await _wait(2.0)
	var per_step := float(Time.get_ticks_usec() - t0) / (2.0 * Engine.physics_ticks_per_second) / 1000.0
	print("INFO  %.2f ms per physics step with %d stacked carts" % [per_step, 7])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
