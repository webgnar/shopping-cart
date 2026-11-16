extends SceneTree
## Headless drive test: presses the real input actions and checks the cart does what the design says.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/drive_test.gd

const SCENARIOS := [
	# name, actions held, seconds, check
	["idle", [], 5.0, "still"],
	["Q+E both push", ["push_left", "push_right"], 1.5, "forward_straight"],
	["A+D both pull", ["pull_left", "pull_right"], 1.5, "backward"],
	["E right push", ["push_right"], 1.5, "turns_left"],
	["Q left push", ["push_left"], 1.5, "turns_right"],
	["Q+D spin", ["push_left", "pull_right"], 1.2, "spins_right"],
	["Q+E short push", ["push_left", "push_right"], 1.2, "flat"],
	["Q+E hard push", ["push_left", "push_right"], 2.1, "wheelie"],
	["A+D hard pull", ["pull_left", "pull_right"], 2.6, "rear_up"],
	["tile Q+E push", ["push_left", "push_right"], 1.5, "forward_straight"],
	["coast then rest", ["coast"], 12.0, "comes_to_rest"],
	["rested 4 s, then Q+E", ["push_left", "push_right"], 1.5, "wakes_and_moves"],
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
		var ticks := int(sc[2] * Engine.physics_ticks_per_second)
		for i in ticks:
			if coast and i == int(Engine.physics_ticks_per_second):
				Input.action_release("push_right")
			await physics_frame
			var b := cart.frame.global_transform.basis
			max_pitch = maxf(max_pitch, absf(rad_to_deg(asin(b.x.y))))
			max_rear = maxf(max_rear, minf(cart.wheels.RL.global_position.y, cart.wheels.RR.global_position.y))
			max_front = maxf(max_front, minf(cart.wheels.FL.global_position.y, cart.wheels.FR.global_position.y))
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
			"flat": ok = along > 2.0 and max_rear < 0.09 and max_front < 0.09 and cart.wheels_down() == 4
			"wakes_and_moves": ok = along > 1.0
			"comes_to_rest": ok = cart.frame.freeze
		if not ok:
			failures += 1
		print("%-5s %-18s moved %.2f m  speed along nose %+.2f m/s  turned %+4d deg  max pitch %4.1f  front wheels up to %.2f m  rear up to %.2f m  groceries %d/5  wheels down %d" % [
			"PASS" if ok else "FAIL", sc[0], Vector2(d.x, d.z).length(), along, roundi(turn), max_pitch, max_front, max_rear,
			cart.groceries_in_basket(), cart.wheels_down()])
	# Braking: walk or run the cart up to speed (push for 1 or 1.8 s), then pull back with both hands (body plants,
	# arms extend).
	for push_s in [1.0, 1.8]:
		for mode in ["coast", "brake"]:
			main.spawn_cart(Vector3(-14, 0, -3), 0.0)
			await _wait(0.5)
			var cart: ShoppingCart = main.cart
			Input.action_press("push_left")
			Input.action_press("push_right")
			await _wait(push_s)
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
				ok = dist < 0.08 * v0 * 3.6 and t < 1.5 and max_pitch < 25.0 and cart.groceries_in_basket() >= 4
			print("%-5s %-18s from %.1f km/h: stopped in %.2f m and %.2f s  max nose-up %.1f deg  front wheels up to %.2f m  groceries %d/5" % [
				("PASS" if ok else "FAIL") if mode == "brake" else "info", "%.1f s push, %s" % [push_s, "pull" if mode == "brake" else "let go"],
				v0 * 3.6, dist, t, max_pitch, max_front, cart.groceries_in_basket()])
			if not ok:
				failures += 1
	# Pushing and pulling share one base and ramp: compare the first half second from rest.
	var accel := {}
	for pair in [["push", ["push_left", "push_right"]], ["pull", ["pull_left", "pull_right"]]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(0.5)
		var cart: ShoppingCart = main.cart
		for a in pair[1]:
			Input.action_press(a)
		await _wait(0.5)
		for a in pair[1]:
			Input.action_release(a)
		accel[pair[0]] = absf(cart.frame.linear_velocity.length())
	var pull_ok: bool = absf(accel.pull - accel.push) < 0.1 * accel.push
	if not pull_ok:
		failures += 1
	print("%-5s %-18s after 0.5 s from rest: pushing %.2f m/s, pulling %.2f m/s" % ["PASS" if pull_ok else "FAIL", "pull = push", accel.push, accel.pull])

	# Countering a spin: pull one hand to spin, then pull with the other hand instead. The second hand works
	# against the spin, so it grabs the bar and stops it within a second (then turns the cart the other way).
	for counter in [[["pull_left"], ["pull_right"], "A spin, then D"], [["push_left", "pull_right"], ["pull_left", "push_right"], "Q+D spin, then A+E"]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(1.0)
		var sc_cart: ShoppingCart = main.cart
		for a in counter[0]:
			Input.action_press(a)
		await _wait(1.5)
		var w0 := rad_to_deg(sc_cart.frame.angular_velocity.y)
		for a in counter[0]:
			Input.action_release(a)
		for a in counter[1]:
			Input.action_press(a)
		var t_stop := -1.0
		var min_wheels := 4
		for i in int(1.5 * Engine.physics_ticks_per_second):
			await physics_frame
			min_wheels = mini(min_wheels, sc_cart.wheels_down())
			if t_stop < 0.0 and rad_to_deg(sc_cart.frame.angular_velocity.y) * signf(w0) < 10.0:
				t_stop = float(i + 1) / Engine.physics_ticks_per_second
		for a in counter[1]:
			Input.action_release(a)
		var stop_ok := absf(w0) > 90.0 and t_stop > 0.0 and t_stop < 1.0 and min_wheels >= 2
		if not stop_ok:
			failures += 1
		print("%-5s %-18s spinning %+d deg/s, stopped in %.2f s (wheels down at least %d)" % [
			"PASS" if stop_ok else "FAIL", counter[2], roundi(w0), t_stop, min_wheels])
	# Hand power tips the cart: keep pushing hard and the front wheels lift (wheelie) until it goes over; keep
	# pulling hard and the rear wheels lift until it goes over. Let go as soon as an end lifts
	# and it drops back onto four wheels.
	for tip in [["push", 4.0, true], ["pull", 4.0, true], ["push", 0.0, false], ["pull", 0.0, false]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(1.0)
		var tc: ShoppingCart = main.cart
		var keys: Array = [tip[0] + "_left", tip[0] + "_right"]
		for a in keys:
			Input.action_press(a)
		var held := 0.0
		var lifted := 0.0
		while held < 6.0:
			await physics_frame
			held += 1.0 / Engine.physics_ticks_per_second
			var end_up := minf(tc.wheels.FL.global_position.y, tc.wheels.FR.global_position.y) if tip[0] == "push" \
				else minf(tc.wheels.RL.global_position.y, tc.wheels.RR.global_position.y)
			if end_up > 0.15 and lifted == 0.0:
				lifted = held
			if lifted > 0.0 and held >= lifted + tip[1]:
				break
		for a in keys:
			Input.action_release(a)
		await _wait(3.0)
		var tb := tc.frame.global_transform.basis
		var fell := tb.y.y < 0.7   # well off upright: on its nose, its handle or its side
		var pitch := roundi(rad_to_deg(asin(clampf(tb.x.y, -1, 1))))
		var tip_ok: bool = lifted > 0.0 and fell == tip[2] and (fell or tc.wheels_down() == 4)
		if not tip_ok:
			failures += 1
		print("%-5s %-18s %s end lifted after %.1f s, let go %.1f s later: %s (up %.2f, nose pitch %+d deg, wheels down %d)" % [
			"PASS" if tip_ok else "FAIL", "hard " + tip[0], "front" if tip[0] == "push" else "rear", lifted, tip[1],
			"fell over" if fell else "back on its wheels", tb.y.y, pitch, tc.wheels_down()])
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
	# Child seat: the flap lifts when pushed and drops back onto its stop. The backrest folds back flat against the
	# gate and stays there (it leans back once folded), until it is pushed forward again.
	for part in [["seat flap", "seat_flap", Vector3(0.13, 0, 0), Vector3.UP, 6.0, 20.0, 110.0],
			["seat backrest", "child_seat", Vector3(0.13, 0.47, 0), Vector3.LEFT, 10.0, 5.0, 33.0]]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(0.5)
		cart = main.cart
		var body: RigidBody3D = cart.get(part[1])
		var rest: Basis = cart.gate.global_transform.basis.inverse() * body.global_transform.basis
		var start: float = rad_to_deg(Basis.IDENTITY.get_rotation_quaternion().angle_to(rest.get_rotation_quaternion()))
		var b0: Vector3 = body.global_transform.basis.y
		var max_swing := 0.0
		for i in 30:
			var dir: Vector3 = cart.frame.global_transform.basis * part[3]
			body.apply_force(dir * part[4], body.global_transform.basis * part[2])
			await physics_frame
			max_swing = maxf(max_swing, rad_to_deg(b0.angle_to(body.global_transform.basis.y)))
		await _wait(2.0)
		var stays: float = rad_to_deg(b0.angle_to(body.global_transform.basis.y))
		if part[1] == "child_seat":
			for i in 30:
				body.apply_force(cart.frame.global_transform.basis.x * part[4], body.global_transform.basis * part[2])
				await physics_frame
			await _wait(2.0)
		var back: float = rad_to_deg(b0.angle_to(body.global_transform.basis.y))
		var ok: bool = start < 2.0 and max_swing > part[5] and max_swing < part[6] and back < 3.0
		if part[1] == "child_seat":
			ok = ok and stays > 25.0
		if not ok:
			failures += 1
		print("%-5s %-18s at rest %.1f deg off its stop, swung %.0f deg when pushed, settled at %.0f deg, back to %.1f deg after" % [
			"PASS" if ok else "FAIL", part[0], start, max_swing, stays, back])
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
