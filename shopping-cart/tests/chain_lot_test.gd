extends SceneTree
## The cart chain lot (scenes/levels/chain_lot.tscn, console `chain`): the player's cart ploughs down the line of
## single carts ahead of the spawn and nests them one by one into a long chain, then turns and stops with it.
## Prints how the chain behaves (length, nest gaps, fishtail, fastest body) and checks it holds together.
##   godot --headless --fixed-fps 120 -s res://tests/chain_lot_test.gd

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/chain_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-34s %s" % ["PASS" if ok else "FAIL", name, detail])


func _keys(names: Array) -> void:
	for a in ShoppingCart.ACTIONS:
		Input.action_release(a)
	for a in names:
		Input.action_press(a)


func _max_speed(carts: Array) -> float:
	var v := 0.0
	for c in carts:
		for b in c.bodies():
			v = maxf(v, b.linear_velocity.length())
	return v


## m each nested cart sits from fully in (0 = fully in).
func _gaps(carts: Array) -> Array:
	var out := []
	for c in carts:
		if c.nest:
			out.append(snappedf(c.nest.get("linear_limit_x/upper_distance") - c.nest.slide(), 0.01))
	return out


## Largest yaw between neighbours in the chain, degrees.
func _kink(carts: Array) -> float:
	var k := 0.0
	for i in range(1, carts.size()):
		k = maxf(k, absf(rad_to_deg(wrapf(carts[i].heading() - carts[i - 1].heading(), -PI, PI))))
	return k


func _report(t: float, cart: ShoppingCart) -> void:
	var s := cart.stack()
	print("t=%5.1f  chain=%2d  speed=%.2f  fastest_body=%.2f  kink=%4.1f deg  fallen=%d  gaps=%s" % [
		t, s.size(), cart.frame.linear_velocity.length(), _max_speed(s), _kink(s),
		s.filter(func(c): return c.fallen).size(), _gaps(s)])


func _run() -> void:
	await _wait(1.5)
	var line: Array = main.get_node("Carts/Line").get_children()
	var still := true
	for c in main.get_node("Carts").find_children("*", "ShoppingCart", true, false):
		still = still and _max_speed([c]) < 0.05
	_check("spare carts stand still", still, "")

	# Plough down the line, keeping to a walking pace (push when slow, let go when fast).
	var cart: ShoppingCart = main.cart
	var t := 0.0
	var worst := 0.0
	var max_len := 1
	var pushing := false
	while t < 60.0 and cart.stack().size() < line.size() + 1:
		var v := cart.frame.linear_velocity.dot(cart.frame.global_transform.basis.x.normalized())
		if v < 1.0 and not pushing:
			pushing = true
			_keys(["push_left", "push_right"])
		elif v > 1.6 and pushing:
			pushing = false
			_keys([])
		await _wait(0.1)
		t += 0.1
		worst = maxf(worst, _max_speed(cart.stack()))
		max_len = maxi(max_len, cart.stack().size())
		if is_equal_approx(fmod(t, 2.0), 0.0) or fmod(t + 0.05, 2.0) < 0.1:
			_report(t, cart)
	_report(t, cart)
	_check("whole line nested into one chain", cart.stack().size() == line.size() + 1,
			"%d carts after %.1f s (longest %d)" % [cart.stack().size(), t, max_len])
	_check("no body ran away while chaining", worst < 6.0, "fastest %.2f m/s" % worst)

	# Turn the chain: right hand pushes, left hand eases.
	print("-- turning (E held, then E + A)")
	var h0 := [cart.stack()[0].heading(), cart.heading()]
	_keys(["push_right"])
	for i in 4:
		await _wait(1.0)
		_report(t + i + 1, cart)
	_keys(["push_right", "pull_left"])
	for i in 4:
		await _wait(1.0)
		_report(t + i + 5, cart)
	var after_turn := cart.stack().size()
	print("turned: front cart %.1f deg, player's cart %.1f deg" % [rad_to_deg(wrapf(cart.stack()[0].heading() - h0[0], -PI, PI)), rad_to_deg(wrapf(cart.heading() - h0[1], -PI, PI))])
	_check("chain survives a turn", after_turn == line.size() + 1, "%d carts" % after_turn)

	# Let go: it should come to rest and freeze as one.
	print("-- let go")
	_keys([])
	for i in 2:
		await _wait(5.0)
		print("  +%d s: frozen %d/%d, fastest %.3f" % [5 * (i + 1), cart.stack().filter(func(c): return c.frame.freeze).size(), cart.stack().size(), _max_speed(cart.stack())])
	_report(t + 18, cart)
	var frozen := cart.stack().all(func(c): return c.frame.freeze)
	for c in cart.stack():
		for b in c.bodies():
			if b.linear_velocity.length() > 0.02:
				print("  still moving: %s/%s %.3f m/s  frozen=%s idle=%.1f" % [c.name, b.name, b.linear_velocity.length(), c.frame.freeze, c._idle_time])
	_check("chain falls asleep (freezes)", frozen, "fastest %.3f m/s" % _max_speed(cart.stack()))

	# Yank back: the player's cart pulls off the back of the chain.
	print("-- yank back (A + D)")
	_keys(["pull_left", "pull_right"])
	await _wait(2.5)
	_keys([])
	_report(t + 21, cart)
	var rest: ShoppingCart = line[0]
	print("rest of the chain: %d carts" % rest.stack().size())
	_check("player's cart pulls off the back", cart.nested_in == null, "chain now %d" % cart.stack().size())
	print("%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
