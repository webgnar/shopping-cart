extends SceneTree
## Headless drive test: presses the real input actions and checks the cart does what the design says.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/drive_test.gd

const SCENARIOS := [
	# name, actions held, seconds, check
	["idle", [], 5.0, "still"],
	["Q+E both push", ["push_left", "push_right"], 3.0, "forward_straight"],
	["A+D both pull", ["pull_left", "pull_right"], 3.0, "backward"],
	["E right push", ["push_right"], 3.0, "turns_left"],
	["Q left push", ["push_left"], 3.0, "turns_right"],
	["Q+D spin", ["push_left", "pull_right"], 2.0, "spins_right"],
	["S press (wheelie)", ["press"], 1.5, "wheelie"],
	["W lift", ["lift"], 1.5, "rear_up"],
	["W+E lift right", ["lift", "push_right"], 1.5, "right_up"],
	["tile Q+E push", ["push_left", "push_right"], 3.0, "forward_straight"],
	["coast then rest", ["coast"], 12.0, "comes_to_rest"],
	["rested 4 s, then Q+E", ["push_left", "push_right"], 2.5, "wakes_and_moves"],
	["gear 1 Q+E", ["push_left", "push_right"], 3.0, "gear1"],
	["gear 5 Q+E", ["push_left", "push_right"], 4.0, "gear5"],
]

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _run() -> void:
	await _wait(0.5)
	for sc in SCENARIOS:
		var on_tile: bool = sc[0].begins_with("tile")
		main.spawn_cart(Vector3(2, 0, 0) if on_tile else Vector3(-10, 0, -3), 0.0)
		await _wait(1.0)
		var cart: ShoppingCart = main.cart
		var p0 := cart.cart_origin()
		var h0 := cart.heading()
		cart.set_gear(1 if sc[3] == "gear1" else (5 if sc[3] == "gear5" else 3))
		var was_asleep := false
		if sc[3] == "wakes_and_moves":
			await _wait(4.0)
			was_asleep = cart.frame.sleeping
		var coast: bool = sc[1] == ["coast"]
		for a in (["push_right"] if coast else sc[1]):
			Input.action_press(a)
		var max_pitch := 0.0
		var max_rear := 0.0
		var max_front := 0.0
		var max_right_up := 0.0
		var ticks := int(sc[2] * Engine.physics_ticks_per_second)
		for i in ticks:
			if coast and i == int(Engine.physics_ticks_per_second):
				Input.action_release("push_right")
			await physics_frame
			var b := cart.frame.global_transform.basis
			max_pitch = maxf(max_pitch, absf(rad_to_deg(asin(b.x.y))))
			max_rear = maxf(max_rear, minf(cart.wheels.RL.global_position.y, cart.wheels.RR.global_position.y))
			max_front = maxf(max_front, minf(cart.wheels.FL.global_position.y, cart.wheels.FR.global_position.y))
			max_right_up = maxf(max_right_up, rad_to_deg(asin(b.z.y)))
		for a in (["push_right"] if coast else sc[1]):
			Input.action_release(a)
		var d := cart.cart_origin() - p0
		var nose := cart.frame.global_transform.basis.x
		var along := cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())
		var turn := rad_to_deg(wrapf(cart.heading() - h0, -PI, PI))
		var ok := false
		match sc[3]:
			"still": ok = d.length() < 0.005 and absf(turn) < 0.1 and cart.frame.freeze
			"forward_straight": ok = along > 1.0 and absf(turn) < 12
			"backward": ok = along < -0.7 and absf(turn) < 25
			"turns_left": ok = turn > 30
			"turns_right": ok = turn < -30
			"spins_right": ok = turn < -60 and d.length() < 1.0
			"wheelie": ok = max_front > 0.12 and max_rear < 0.09
			"rear_up": ok = max_rear > 0.10 and max_front < 0.09
			"right_up": ok = max_right_up > 5
			"wakes_and_moves": ok = along > 1.0
			"gear1": ok = along > 0.8 and along < 1.4 and cart.wheels_down() == 4
			"gear5": ok = along > 3.0 and cart.wheels_down() == 4 and max_rear < 0.09
			"comes_to_rest": ok = cart.frame.freeze
		if not ok:
			failures += 1
		print("%-5s %-18s moved %.2f m  speed along nose %+.2f m/s  turned %+4d deg  max pitch %4.1f  front wheels up to %.2f m  rear up to %.2f m  groceries %d/5  wheels down %d" % [
			"PASS" if ok else "FAIL", sc[0], Vector2(d.x, d.z).length(), along, roundi(turn), max_pitch, max_front, max_rear,
			cart.groceries_in_basket(), cart.wheels_down()])
	# Braking: walk or run the cart up to speed, then pull back with both hands (body plants, arms extend).
	for gear_n in [3, 5]:
		for mode in ["coast", "brake"]:
			main.spawn_cart(Vector3(-14, 0, -3), 0.0)
			await _wait(0.5)
			var cart: ShoppingCart = main.cart
			cart.set_gear(gear_n)
			Input.action_press("push_left")
			Input.action_press("push_right")
			await _wait(3.0)
			Input.action_release("push_left")
			Input.action_release("push_right")
			var nose0 := cart.frame.global_transform.basis.x
			var v0 := cart.frame.linear_velocity.dot(Vector3(nose0.x, 0, nose0.z).normalized())
			var p0 := cart.cart_origin()
			if mode == "brake":
				Input.action_press("pull_left")
				Input.action_press("pull_right")
			var t := 0.0
			var max_pitch := 0.0
			var max_front := 0.0
			while t < 8.0:
				await physics_frame
				t += 1.0 / Engine.physics_ticks_per_second
				var b := cart.frame.global_transform.basis
				max_pitch = maxf(max_pitch, rad_to_deg(asin(b.x.y)))
				max_front = maxf(max_front, minf(cart.wheels.FL.global_position.y, cart.wheels.FR.global_position.y))
				var along := cart.frame.linear_velocity.dot(Vector3(b.x.x, 0, b.x.z).normalized())
				if along < 0.05:
					break
			Input.action_release("pull_left")
			Input.action_release("pull_right")
			var dist := Vector2(cart.cart_origin().x - p0.x, cart.cart_origin().z - p0.z).length()
			var ok := true
			if mode == "brake":
				ok = dist < 1.0 and t < 1.5 and max_pitch < 25.0 and cart.groceries_in_basket() >= 4
			print("%-5s %-18s from %.1f km/h: stopped in %.2f m and %.2f s  max nose-up %.1f deg  front wheels up to %.2f m  groceries %d/5" % [
				("PASS" if ok else "FAIL") if mode == "brake" else "info", "gear %d %s" % [gear_n, "pull back" if mode == "brake" else "let go"],
				v0 * 3.6, dist, t, max_pitch, max_front, cart.groceries_in_basket()])
			if not ok:
				failures += 1
	# Pulling is stronger than pushing: compare the first half second from rest.
	var accel := {}
	for pair in [["push", ["push_left", "push_right"]], ["pull", ["pull_left", "pull_right"]]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(0.5)
		var cart: ShoppingCart = main.cart
		cart.set_gear(3)
		for a in pair[1]:
			Input.action_press(a)
		await _wait(0.5)
		for a in pair[1]:
			Input.action_release(a)
		accel[pair[0]] = absf(cart.frame.linear_velocity.length())
	var pull_ok: bool = accel.pull > accel.push * 1.2
	if not pull_ok:
		failures += 1
	print("%-5s %-18s after 0.5 s from rest: pushing %.2f m/s, pulling %.2f m/s" % ["PASS" if pull_ok else "FAIL", "pull > push", accel.push, accel.pull])

	# Holding W or S keeps tipping the cart until it falls over (W onto its nose, S back onto the handle);
	# a short tap only leans it and it drops back onto four wheels.
	for tip in [["press", 4.0, true], ["lift", 4.0, true], ["press", 0.8, false], ["lift", 0.8, false]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(1.0)
		var tc: ShoppingCart = main.cart
		Input.action_press(tip[0])
		await _wait(tip[1])
		Input.action_release(tip[0])
		await _wait(3.0)
		var tb := tc.frame.global_transform.basis
		var fell := tb.y.y < 0.4
		var tip_ok: bool = fell == tip[2] and (fell or tc.wheels_down() == 4)
		if not tip_ok:
			failures += 1
		print("%-5s %-18s held %.1f s: %s (up %.2f, nose pitch %+d deg, wheels down %d)" % [
			"PASS" if tip_ok else "FAIL", ("S" if tip[0] == "press" else "W") + " held", tip[1],
			"fell over" if fell else "back on its wheels", tb.y.y, roundi(rad_to_deg(asin(clampf(tb.x.y, -1, 1)))), tc.wheels_down()])
	# Gate swings into the basket when shoved, and stops at its limit.
	main.spawn_cart(Vector3(-10, 0, -3), 0.0)
	await _wait(0.5)
	var cart: ShoppingCart = main.cart
	for g in cart.groceries:   # an empty basket, so the gate can fall back freely
		g.free()
	cart.groceries.clear()
	await _wait(0.2)
	var g0 := cart.gate.global_transform.basis.y
	for i in 20:
		cart.gate.apply_force(cart.frame.global_transform.basis.x * 25.0, cart.gate.global_transform.basis * Vector3(0.17, -0.5, 0))
		await physics_frame
	var g1 := cart.gate.global_transform.basis.y
	var swing := rad_to_deg(g0.angle_to(g1))
	await _wait(1.5)
	var settle := rad_to_deg(g0.angle_to(cart.gate.global_transform.basis.y))
	var gate_ok := swing > 10 and swing < 75 and settle < 5
	if not gate_ok:
		failures += 1
	print("%-5s %-18s swung %.0f deg when shoved, back to %.0f deg after" % ["PASS" if gate_ok else "FAIL", "gate", swing, settle])
	# A pinned cart still gets knocked when something hits it.
	main.spawn_cart(Vector3(-10, 0, -3), 0.0)
	await _wait(2.0)
	cart = main.cart
	var pinned := cart.frame.freeze
	var p_before := cart.cart_origin()
	var box := RigidBody3D.new()
	box.mass = 8.0
	box.collision_layer = ShoppingCart.LAYER_WORLD
	box.collision_mask = ShoppingCart.LAYER_WORLD | ShoppingCart.LAYER_CART
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(0.3, 0.3, 0.3)
	box.add_child(cs)
	box.position = cart.frame.global_transform * Vector3(0.55, 0.7, -1.2)
	main.add_child(box)
	box.linear_velocity = cart.frame.global_transform.basis.z * 4.0   # thrown at the cart's left side
	await _wait(1.5)
	var knocked := (cart.cart_origin() - p_before).length()
	var hit_ok := pinned and knocked > 0.03
	if not hit_ok:
		failures += 1
	print("%-5s %-18s pinned at rest: %s, moved %.2f m when a box hit it" % ["PASS" if hit_ok else "FAIL", "knocked when pinned", pinned, knocked])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
