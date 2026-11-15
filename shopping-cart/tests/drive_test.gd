extends SceneTree
## Headless drive test: presses the real input actions and checks the cart does what the design says.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/drive_test.gd

const SCENARIOS := [
	# name, actions held, seconds, check
	["idle", [], 1.5, "still"],
	["Q+E both push", ["push_left", "push_right"], 3.0, "forward_straight"],
	["A+D both pull", ["pull_left", "pull_right"], 3.0, "backward"],
	["E right push", ["push_right"], 3.0, "turns_left"],
	["Q left push", ["push_left"], 3.0, "turns_right"],
	["Q+D spin", ["push_left", "pull_right"], 2.0, "spins_right"],
	["S press (wheelie)", ["press"], 1.5, "wheelie"],
	["W lift", ["lift"], 1.5, "rear_up"],
	["W+E lift right", ["lift", "push_right"], 1.5, "right_up"],
	["tile Q+E push", ["push_left", "push_right"], 3.0, "forward_straight"],
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
		for a in sc[1]:
			Input.action_press(a)
		var max_pitch := 0.0
		var max_rear := 0.0
		var max_front := 0.0
		var max_right_up := 0.0
		var ticks := int(sc[2] * Engine.physics_ticks_per_second)
		for i in ticks:
			await physics_frame
			var b := cart.frame.global_transform.basis
			max_pitch = maxf(max_pitch, absf(rad_to_deg(asin(b.x.y))))
			max_rear = maxf(max_rear, minf(cart.wheels.RL.global_position.y, cart.wheels.RR.global_position.y))
			max_front = maxf(max_front, minf(cart.wheels.FL.global_position.y, cart.wheels.FR.global_position.y))
			max_right_up = maxf(max_right_up, rad_to_deg(asin(b.z.y)))
		for a in sc[1]:
			Input.action_release(a)
		var d := cart.cart_origin() - p0
		var nose := cart.frame.global_transform.basis.x
		var along := cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())
		var turn := rad_to_deg(wrapf(cart.heading() - h0, -PI, PI))
		var ok := false
		match sc[3]:
			"still": ok = d.length() < 0.05 and absf(turn) < 3
			"forward_straight": ok = along > 1.0 and absf(turn) < 12
			"backward": ok = along < -0.7 and absf(turn) < 25
			"turns_left": ok = turn > 30
			"turns_right": ok = turn < -30
			"spins_right": ok = turn < -60 and d.length() < 1.0
			"wheelie": ok = max_front > 0.12 and max_rear < 0.09
			"rear_up": ok = max_rear > 0.10 and max_front < 0.09
			"right_up": ok = max_right_up > 5
		if not ok:
			failures += 1
		print("%-5s %-18s moved %.2f m  speed along nose %+.2f m/s  turned %+4d deg  max pitch %4.1f  front wheels up to %.2f m  rear up to %.2f m  groceries %d/5  wheels down %d" % [
			"PASS" if ok else "FAIL", sc[0], Vector2(d.x, d.z).length(), along, roundi(turn), max_pitch, max_front, max_rear,
			cart.groceries_in_basket(), cart.wheels_down()])
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
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
