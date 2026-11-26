extends SceneTree
## Headless drive test: presses the real input actions and checks the cart does what real physics says.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/drive_test.gd
##
## Real physics is the spec (the hands push at handle height, 1 m, above the centre of mass, 0.42 m): a hard push
## pitches the cart nose-down and unloads the rear, and tips it over the front wheels once they're stopped (a curb);
## a pull or a brake unloads the front, and leaning back on the bar (S) of a rolling cart pops a wheelie. The player
## is a runner, so the cart launches like a sprint start and tops out where the legs do.

## The targets (zack's): a snappy launch and a fast run.
const LAUNCH_KMH := 10.0      ## km/h ...
const LAUNCH_S := 0.6         ## ... within this many seconds of both hands going down (allowed 0.15 s over)
const TOP_KMH := [20.0, 25.0] ## km/h the cart tops out between, both hands held on a flat lot
## Coasting with nobody holding it, the cart slows by rolling resistance and air drag. At 120 Hz Jolt lets a fast
## wheel sink into the floor (docs/DEV_NOTES.md, "Cart: wheels sink at speed"), which adds drag above about 3 m/s,
## so the check is made slow, where it is small.
const COAST_TOLERANCE := 0.06 ## m/s² the measured slowing may be off the prediction by

const SCENARIOS := [
	# name, actions held, seconds, check
	["idle", [], 5.0, "still"],
	["Q+E both push", ["push_left", "push_right"], 1.5, "forward_straight"],
	["A+D both pull", ["pull_left", "pull_right"], 1.5, "backward"],
	["E right push", ["push_right"], 1.5, "turns_left"],
	["Q left push", ["push_left"], 1.5, "turns_right"],
	["Q+D spin", ["push_left", "pull_right"], 1.2, "spins_right"],
	["W back up", ["lift"], 1.5, "rear_up"],
	["Q+E short push", ["push_left", "push_right"], 1.2, "flat"],
	["coast then rest", ["coast"], 30.0, "comes_to_rest"],
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


func _report(ok: bool, name: String, text: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-18s %s" % ["PASS" if ok else "FAIL", name, text])


func _press(keys: Array, down: bool) -> void:
	for a in keys:
		if down:
			Input.action_press(a)
		else:
			Input.action_release(a)


func _along(cart: ShoppingCart) -> float:
	var b := cart.frame.global_transform.basis
	return cart.frame.linear_velocity.dot(Vector3(b.x.x, 0, b.x.z).normalized())


func _pitch(cart: ShoppingCart) -> float:
	return rad_to_deg(asin(clampf(cart.frame.global_transform.basis.x.y, -1, 1)))


func _rear_y(cart: ShoppingCart) -> float:
	return minf(cart.wheels.RL.global_position.y, cart.wheels.RR.global_position.y)


func _front_y(cart: ShoppingCart) -> float:
	return minf(cart.wheels.FL.global_position.y, cart.wheels.FR.global_position.y)


func _run() -> void:
	await _wait(0.5)
	for sc in SCENARIOS:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(1.0)
		var cart: ShoppingCart = main.cart
		var p0 := cart.cart_origin()
		var h0 := cart.heading()
		if sc[3] == "wakes_and_moves":
			await _wait(4.0)
		var coast: bool = sc[1] == ["coast"]
		_press(["push_right"] if coast else sc[1], true)
		var max_pitch := 0.0
		var max_rear := 0.0
		var max_front := 0.0
		var ticks := int(sc[2] * Engine.physics_ticks_per_second)
		for i in ticks:
			if coast and i == int(Engine.physics_ticks_per_second):
				Input.action_release("push_right")
			await physics_frame
			max_pitch = maxf(max_pitch, absf(_pitch(cart)))
			max_rear = maxf(max_rear, _rear_y(cart))
			max_front = maxf(max_front, _front_y(cart))
		_press(["push_right"] if coast else sc[1], false)
		var d := cart.cart_origin() - p0
		var along := _along(cart)
		var turn := rad_to_deg(wrapf(cart.heading() - h0, -PI, PI))
		var ok := false
		match sc[3]:
			"still": ok = d.length() < 0.005 and absf(turn) < 0.1 and cart.frame.freeze
			"forward_straight": ok = along > 1.0 and absf(turn) < 12
			"backward": ok = along < -0.7 and absf(turn) < 25
			"turns_left": ok = turn > 20   # one held hand turns gently (tapping it turns harder, checked below)
			"turns_right": ok = turn < -20
			"spins_right": ok = turn < -60 and d.length() < 1.0
			"rear_up": ok = max_rear > 0.10 and max_front < 0.09
			"flat": ok = along > 2.0 and max_rear < 0.09 and max_front < 0.09 and cart.wheels_down() == 4
			"wakes_and_moves": ok = along > 1.0
			"comes_to_rest": ok = cart.frame.freeze
		_report(ok, sc[0], "moved %.2f m  speed along nose %+.2f m/s  turned %+4d deg  max pitch %4.1f  front wheels up to %.2f m  rear up to %.2f m  groceries %d/5  wheels down %d" % [
			Vector2(d.x, d.z).length(), along, roundi(turn), max_pitch, max_front, max_rear, cart.groceries_in_basket(), cart.wheels_down()])

	# Launch and top speed: both hands held on the open lot west of the test strip. The rear unloads as the push at
	# handle height pitches the cart nose-down (real physics), but on open ground the runner can't push harder than
	# the cart speeds up, so it stays on its wheels.
	main.spawn_cart(Vector3(-200, 0, -3), 0.0)
	await _wait(1.0)
	var run: ShoppingCart = main.cart
	var static_rear: float = run.wheel_load.RL + run.wheel_load.RR
	var static_front: float = run.wheel_load.FL + run.wheel_load.FR
	_press(["push_left", "push_right"], true)
	var t_launch := -1.0
	var top := 0.0
	var min_rear := INF
	var max_front_load := 0.0
	var min_pitch := 0.0
	for i in int(6.0 * Engine.physics_ticks_per_second):
		await physics_frame
		var v := _along(run)
		if t_launch < 0.0 and v * 3.6 >= LAUNCH_KMH:
			t_launch = float(i + 1) / Engine.physics_ticks_per_second
		top = maxf(top, v * 3.6)
		if i > Engine.physics_ticks_per_second:
			min_rear = minf(min_rear, run.wheel_load.RL + run.wheel_load.RR)
			max_front_load = maxf(max_front_load, run.wheel_load.FL + run.wheel_load.FR)
		min_pitch = minf(min_pitch, _pitch(run))
	_press(["push_left", "push_right"], false)
	_report(t_launch > 0.0 and t_launch <= LAUNCH_S + 0.15, "launch", "0 to %.0f km/h in %.2f s (target %.2f s)" % [LAUNCH_KMH, t_launch, LAUNCH_S])
	_report(top >= TOP_KMH[0] and top <= TOP_KMH[1] and run.wheels_down() == 4, "top speed",
		"%.1f km/h after 6 s of both hands (target %d to %d), %d wheels down" % [top, TOP_KMH[0], TOP_KMH[1], run.wheels_down()])
	_report(min_rear < 0.5 * static_rear and max_front_load > static_front and min_pitch < 0.0, "hard push, rear",
		"rear wheels carry down to %d N (%d standing), front up to %d N (%d), nose down to %+.1f deg" % [
			roundi(min_rear), roundi(static_rear), roundi(max_front_load), roundi(static_front), min_pitch])

	# A hard push with the front wheels stopped by a curb: nothing to speed up, so the push at handle height tips the
	# cart over the front wheels and the rear comes up. Let go once it's up and it drops back onto four wheels.
	main.spawn_cart(Vector3(22.9, 0, 0), 0.0)   # front wheels against the test strip's 15 cm curb
	await _wait(1.0)
	var cc: ShoppingCart = main.cart
	_press(["push_left", "push_right"], true)
	var rear_up := 0.0
	var t_curb := -1.0
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await physics_frame
		rear_up = maxf(rear_up, _rear_y(cc))
		if t_curb < 0.0 and _rear_y(cc) > 0.15:
			t_curb = float(i + 1) / Engine.physics_ticks_per_second
			break
	_press(["push_left", "push_right"], false)
	await _wait(3.0)
	_report(rear_up > 0.15 and cc.wheels_down() == 4, "push into curb", "rear wheels up to %.2f m (up after %.2f s), let go: %d wheels down, upright %.2f" % [
		rear_up, t_curb, cc.wheels_down(), cc.frame.global_basis.y.y])

	# Braking: run the cart up to speed, then pull back with both hands. The pull at handle height unloads the front
	# wheels as it slows the cart; the groceries stay in.
	main.spawn_cart(Vector3(-200, 0, -3), 0.0)
	await _wait(1.0)
	var bc: ShoppingCart = main.cart
	var b_front: float = bc.wheel_load.FL + bc.wheel_load.FR
	_press(["push_left", "push_right"], true)
	await _wait(1.8)
	_press(["push_left", "push_right"], false)
	var v0 := _along(bc)
	var p0 := bc.cart_origin()
	_press(["pull_left", "pull_right"], true)
	var t := 0.0
	var min_front := INF
	while t < 4.0 and _along(bc) > 0.05:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		min_front = minf(min_front, bc.wheel_load.FL + bc.wheel_load.FR)
	_press(["pull_left", "pull_right"], false)
	var dist := Vector2(bc.cart_origin().x - p0.x, bc.cart_origin().z - p0.z).length()
	_report(t < 4.0 and v0 / t > 3.0 and min_front < 0.6 * b_front and bc.groceries_in_basket() >= 4, "brake",
		"from %.1f km/h stopped in %.2f m and %.2f s (%.1f m/s²), front wheels carry down to %d N (%d standing), groceries %d/5" % [
			v0 * 3.6, dist, t, v0 / t, roundi(min_front), roundi(b_front), bc.groceries_in_basket()])

	# Pulling from rest: the player backpedals, so the cart backs no faster than they can.
	main.spawn_cart(Vector3(-200, 0, -3), 0.0)
	await _wait(1.0)
	var pc: ShoppingCart = main.cart
	_press(["pull_left", "pull_right"], true)
	var back := 0.0
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await physics_frame
		back = minf(back, _along(pc))
	_press(["pull_left", "pull_right"], false)
	_report(-back < pc.back_speed + 0.5 and -back > 0.5 * pc.back_speed, "pull from rest",
		"backs at up to %.1f m/s (the player backpedals at %.1f)" % [-back, pc.back_speed])

	# S leans back on the bar: on a rolling cart the press down and back pops the front wheels up (a second of it
	# swings the cart past its balance point, about 47 degrees, so with the hands off it goes over backwards). A tap
	# from rest only leans it.
	for sc in [[1.5, 1.0, "S on a rolling cart"], [0.0, 0.4, "S tap from rest"]]:
		main.spawn_cart(Vector3(-200, 0, -3), 0.0)
		await _wait(1.0)
		var sc_cart: ShoppingCart = main.cart
		if sc[0] > 0.0:
			_press(["push_left", "push_right"], true)
			await _wait(sc[0])
			_press(["push_left", "push_right"], false)
		Input.action_press("press")
		var front_up := 0.0
		var rear_top := 0.0
		for i in int(sc[1] * Engine.physics_ticks_per_second):
			await physics_frame
			front_up = maxf(front_up, _front_y(sc_cart))
			rear_top = maxf(rear_top, _rear_y(sc_cart))
		Input.action_release("press")
		await _wait(3.0)
		var ok: bool = (front_up > 0.12 and rear_top < 0.09) if sc[0] > 0.0 else (front_up < 0.09 and sc_cart.wheels_down() == 4)
		_report(ok, sc[2], "pressed %.1f s: front wheels up to %.2f m, rear up to %.2f m, then %d wheels down" % [sc[1], front_up, rear_top, sc_cart.wheels_down()])

	# Coasting: launched with nobody holding it, the cart slows by rolling resistance (rolling_resistance times g)
	# and air drag (half the air's density times drag_area times v², over the mass).
	for v_start in [2.5, 6.0]:
		main.spawn_cart(Vector3(-200, 0, -3), 0.0)
		await _wait(1.0)
		var kc: ShoppingCart = main.cart
		kc._wake()
		var fwd := kc.frame.global_basis.x
		for b in kc.net_bodies():
			b.linear_velocity = fwd * v_start
		for k in kc.wheels:
			kc.wheels[k].angular_velocity = kc.wheels[k].global_basis.z * (-v_start / kc.wheel_radius)
		await _wait(0.5)
		var va := _along(kc)
		await _wait(1.0)
		var vb := _along(kc)
		var decel := va - vb
		var vm := (va + vb) / 2.0
		var mass := kc.rig_mass()
		for g in kc.groceries:
			mass += g.mass
		var predicted := kc.rolling_resistance * 9.81 + 0.5 * 1.2 * kc.drag_area * vm * vm / mass
		if v_start < 3.0:
			_report(absf(decel - predicted) < COAST_TOLERANCE, "coast-down", "at %.1f m/s it slows %.2f m/s² (rolling and air predict %.2f)" % [vm, decel, predicted])
		else:
			print("info  %-18s at %.1f m/s it slows %.2f m/s² (rolling and air predict %.2f; the rest is the wheels sinking at 120 Hz)" % ["coast-down, fast", vm, decel, predicted])

	# Hand position: tapping a key moves that hand out along the bar, so tapping one hand turns the cart harder
	# than holding it.
	var turns := {}
	for mode in ["held", "tapped"]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		await _wait(0.8)
		var cart: ShoppingCart = main.cart
		var h0 := cart.heading()
		var grip := 0.0
		for i in int(1.5 * Engine.physics_ticks_per_second):
			var down: bool = mode == "held" or (i % 20) < 9   # 6 taps a second
			if down:
				Input.action_press("push_right")
			else:
				Input.action_release("push_right")
			await physics_frame
			grip = maxf(grip, cart.hand_grip.R)
		Input.action_release("push_right")
		turns[mode] = [rad_to_deg(wrapf(cart.heading() - h0, -PI, PI)), grip]
	var tap_ok: bool = turns.tapped[0] > 1.2 * turns.held[0] and turns.held[0] > 0.0 and turns.tapped[1] > 0.6
	if not tap_ok:
		failures += 1
	print("%-5s %-18s E held turned %+.0f deg, E tapped 6 a second turned %+.0f deg (hand out to %d%% of the bar)" % [
		"PASS" if tap_ok else "FAIL", "tapping turns", turns.held[0], turns.tapped[0], roundi(100 * turns.tapped[1])])

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
	# W lifts the handle until the arms can lift it no higher (handle_high): the rear comes up and stays held up,
	# then drops back onto four wheels when W is let go.
	main.spawn_cart(Vector3(-10, 0, -3), 0.0)
	await _wait(1.0)
	var wc: ShoppingCart = main.cart
	Input.action_press("lift")
	var w_rear := 0.0
	for i in int(4.0 * Engine.physics_ticks_per_second):
		await physics_frame
		w_rear = maxf(w_rear, _rear_y(wc))
	var w_up := wc.frame.global_basis.y.y
	Input.action_release("lift")
	await _wait(3.0)
	_report(w_rear > 0.2 and w_up > 0.4 and wc.wheels_down() == 4, "W held", "held 4 s: rear up to %.2f m without going over (up %.2f), let go: %d wheels down" % [w_rear, w_up, wc.wheels_down()])
	# Getting back up: lay the cart on its nose, on its back (the handle end) or on its side, let go, then hold one
	# hand key. The hand hauls it back onto its wheels without shoving it across the floor.
	for setup in ["nose", "back", "side"]:
		main.spawn_cart(Vector3(-10, 0, -3), 0.0)
		var rc: ShoppingCart = main.cart
		match setup:
			"nose": rc.transform = Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(-9.0, 1.0, -3))
			"back": rc.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(-10.0, 0.05, -3))
			"side": rc.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-10, 0.4, -3))
		await _wait(3.0)
		var down_up := rc.frame.global_transform.basis.y.y
		var was_fallen := rc.fallen
		var p_down := rc.cart_origin()
		Input.action_press("push_right")
		var t_up := -1.0
		for i in int(5.0 * Engine.physics_ticks_per_second):
			await physics_frame
			if rc.frame.global_transform.basis.y.y > 0.95:
				t_up = float(i + 1) / Engine.physics_ticks_per_second
				break
		Input.action_release("push_right")
		var slid := Vector2(rc.cart_origin().x - p_down.x, rc.cart_origin().z - p_down.z).length()
		await _wait(3.0)
		var up_ok := was_fallen and down_up < 0.3 and t_up > 0.0 and rc.wheels_down() == 4 and slid < 3.0   # one it rolls over from upside down travels a little
		if not up_ok:
			failures += 1
		print("%-5s %-18s lying at up %.2f (fallen %s), E held: %s, moved %.2f m, then %d / 4 wheels down" % [
			"PASS" if up_ok else "FAIL", "get up (" + setup + ")", down_up, was_fallen,
			("upright in %.2f s" % t_up) if t_up > 0.0 else "still down after 5 s", slid, rc.wheels_down()])
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
	# Child seat: at rest the seat flap stands folded up against the gate on its loops and the backrest lies folded back
	# over it. The gate swinging up carries both up with it (both hang on the gate, folded on their 0 stops).
	main.spawn_cart(Vector3(-10, 0, -3), 0.0)
	await _wait(1.0)
	cart = main.cart
	var seat_rest := _rel_deg(cart.gate, cart.child_seat)
	var flap_rest := _rel_deg(cart.gate, cart.seat_flap)
	var plastic_rest := _rel_deg(cart.seat_flap, cart.seat_plastic)
	var seat_up := 0.0
	var flap_up := 0.0
	var gate_up := 0.0
	var g_rest := cart.gate.global_transform.basis.y
	var s_rest := cart.child_seat.global_transform.basis.y
	for i in 120:
		cart.gate.apply_force(cart.frame.global_transform.basis.x * 60.0, cart.gate.global_transform.basis * Vector3(0.17, -0.5, 0))
		await physics_frame
		if i > 60:
			seat_up = maxf(seat_up, _rel_deg(cart.gate, cart.child_seat))
		if i > 100:   # the flap swings a little when the shove bangs the gate into its stop, then rides along
			flap_up = maxf(flap_up, _rel_deg(cart.gate, cart.seat_flap))
	gate_up = rad_to_deg(g_rest.angle_to(cart.gate.global_transform.basis.y))
	var seat_lift := rad_to_deg(s_rest.angle_to(cart.child_seat.global_transform.basis.y))
	await _wait(2.0)
	var seat_back := _rel_deg(cart.gate, cart.child_seat)
	var folded_ok := seat_rest < 2.0 and flap_rest < 2.0 and plastic_rest < 3.0 and gate_up > 45.0 and absf(seat_lift - gate_up) < 5.0 \
		and seat_up < 10.0 and flap_up < 10.0 and seat_back < 2.0
	if not folded_ok:
		failures += 1
	print("%-5s %-18s folded at rest: backrest %.1f deg, flap %.1f deg, plastic %.1f deg off their stops; gate up %.0f deg lifts the backrest %.0f deg (stays within %.1f deg of the gate, flap within %.1f)" % [
		"PASS" if folded_ok else "FAIL", "gate lifts seat", seat_rest, flap_rest, plastic_rest, gate_up, seat_lift, seat_up, flap_up])
	# Opening the seat: pull the backrest into the basket (it stays, leaning forward), then pull the flap down about
	# its loops until it lies level. Lifting the flap folds it back up against the gate; then the backrest goes back.
	main.spawn_cart(Vector3(-10, 0, -3), 0.0)
	await _wait(0.5)
	cart = main.cart
	var flap_loop := cart.seat_flap.global_position - cart.gate.global_position
	var flap_tip := Vector3(-0.017, 0.119, 0)   # the flap's free edge, folded (flap body frame)
	var seat_max := 0.0
	for i in 40:
		cart.child_seat.apply_force(cart.frame.global_transform.basis.x * 10.0, cart.child_seat.global_transform.basis * Vector3(-0.15, 0.45, 0))
		await physics_frame
		seat_max = maxf(seat_max, _rel_deg(cart.gate, cart.child_seat))
	await _wait(2.0)
	var seat_stays := _rel_deg(cart.gate, cart.child_seat)
	for i in 40:
		cart.seat_flap.apply_force(cart.frame.global_transform.basis.x * 8.0, cart.seat_flap.global_transform.basis * flap_tip)
		await physics_frame
	await _wait(2.0)
	var flap_open := _rel_deg(cart.gate, cart.seat_flap)
	var loop_moved := (cart.seat_flap.global_position - cart.gate.global_position - flap_loop).length()
	# The plastic lies on the open seat; lifted by its free edge it comes up off the seat, and let go it drops back.
	var plastic_on := _rel_deg(cart.seat_flap, cart.seat_plastic)
	var plastic_tip := Vector3(-0.017, 0.123, 0)   # the plastic's free edge, folded (plastic body frame)
	var plastic_up := 0.0
	for i in 30:
		cart.seat_plastic.apply_force(cart.frame.global_transform.basis.y * 3.0, cart.seat_plastic.global_transform.basis * plastic_tip)
		await physics_frame
		plastic_up = maxf(plastic_up, _rel_deg(cart.seat_flap, cart.seat_plastic))
	var flap_still := _rel_deg(cart.gate, cart.seat_flap)
	await _wait(2.0)
	var plastic_back := _rel_deg(cart.seat_flap, cart.seat_plastic)
	for i in 60:
		cart.seat_flap.apply_force((cart.frame.global_transform.basis.y - cart.frame.global_transform.basis.x) * 8.0,
			cart.seat_flap.global_transform.basis * flap_tip)
		await physics_frame
	await _wait(2.0)
	var flap_folded := _rel_deg(cart.gate, cart.seat_flap)
	for i in 40:
		cart.child_seat.apply_force(-cart.frame.global_transform.basis.x * 10.0, cart.child_seat.global_transform.basis * Vector3(-0.15, 0.45, 0))
		await physics_frame
	await _wait(2.0)
	var seat_folded := _rel_deg(cart.gate, cart.child_seat)
	var open_ok := seat_max > 25.0 and seat_max < 33.0 and seat_stays > 25.0 and seat_folded < 2.0
	if not open_ok:
		failures += 1
	print("%-5s %-18s pulled open %.0f deg, stayed open at %.0f deg, pushed back to %.1f deg" % [
		"PASS" if open_ok else "FAIL", "seat backrest", seat_max, seat_stays, seat_folded])
	var flap_ok := absf(flap_open - 98.0) < 4.0 and loop_moved < 0.01 and flap_folded < 3.0
	if not flap_ok:
		failures += 1
	print("%-5s %-18s pulled down level at %.0f deg (98), its loops moved %.1f mm, lifted back up to %.1f deg" % [
		"PASS" if flap_ok else "FAIL", "seat flap", flap_open, loop_moved * 1000.0, flap_folded])
	var plastic_ok := plastic_on < 3.0 and plastic_up > 30.0 and absf(flap_still - 98.0) < 4.0 and plastic_back < 3.0
	if not plastic_ok:
		failures += 1
	print("%-5s %-18s on the open seat %.1f deg, lifted off it %.0f deg (seat stayed at %.0f), dropped back to %.1f deg" % [
		"PASS" if plastic_ok else "FAIL", "seat plastic", plastic_on, plastic_up, flap_still, plastic_back])
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


## Degrees a hinged body has turned from its rest pose, relative to the body it hangs on.
func _rel_deg(parent: RigidBody3D, body: RigidBody3D) -> float:
	var rel := parent.global_transform.basis.inverse() * body.global_transform.basis
	return rad_to_deg(rel.get_rotation_quaternion().get_angle())
