extends SceneTree
## Headless check of the cart's wheel sounds (scenes/cart/wheel_sound.tscn under each wheel of
## scenes/cart/cart.tscn), each driven by its own wheel's physics:
##  - every level: each wheel rolls on that level's floor while pushed, louder and higher the faster it goes,
##    with no scrub, knocks or landings on a straight push, and every sound stops once the cart is at rest;
##  - a wheelie: the wheels in the air go quiet while the others roll;
##  - a spin on the spot: the wheels slide sideways and scrub;
##  - landings, by each wheel's speed into the ground: a wheelie set down slams, a 5 cm drop taps, a 30 cm drop
##    slams, a cart set down gently is silent.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/rolling_sound_test.gd

const CASES := [
	# name, level, spawn (null: the level's CartSpawn), floor expected
	["sandbox", "res://scenes/main.tscn", null, ""],
	["parking lot", "res://scenes/levels/parking_lot.tscn", null, "asphalt"],
	["parking garage", "res://scenes/levels/parking_garage.tscn", null, "concrete"],
	["supermarket", "res://scenes/levels/supermarket.tscn", null, "tile"],
]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _report(ok: bool, name: String, text: String) -> void:
	if not ok:
		failures += 1
	print("%s  %-24s %s" % ["PASS" if ok else "FAIL", name, text])


static func sounds(cart: ShoppingCart) -> Dictionary:
	var d := {}
	for k in cart.wheels:
		d[k] = cart.wheels[k].get_node("WheelSound")
	return d


static func floor_name(ws: WheelSound) -> String:
	return ws.floor_sound.resource_path.get_file().get_basename() if ws.floor_sound else "air"


static func playing(cart: ShoppingCart) -> Array:
	var out := []
	for k in cart.wheels:
		var ws: WheelSound = cart.wheels[k].get_node("WheelSound")
		for p in [ws.roll_player, ws.scrub_player]:
			if p.playing:
				out.append("%s %s" % [k, p.name])
	return out


func _hold(actions: Array, seconds: float, each := Callable()) -> void:
	for a in actions:
		Input.action_press(a)
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		if each.is_valid():
			each.call()
	for a in actions:
		Input.action_release(a)


func _brake_to_rest(level: Node) -> void:
	Input.action_press("pull_left")
	Input.action_press("pull_right")
	for i in 4 * Engine.physics_ticks_per_second:
		await physics_frame
		if level.cart.frame.linear_velocity.length() < 0.1:
			break
	Input.action_release("pull_left")
	Input.action_release("pull_right")
	for i in 6 * Engine.physics_ticks_per_second:
		await physics_frame
		if level.cart.frame.freeze and playing(level.cart).is_empty():
			break


func _run() -> void:
	for c in CASES:
		var level: Node3D = load(c[1]).instantiate()
		root.add_child(level)
		await _wait(0.3)
		if c[2] != null:
			level.spawn_cart(c[2], 0.0)
		await _wait(1.5)
		var cart: ShoppingCart = level.cart
		var ws := sounds(cart)
		var rest_ok := playing(cart).is_empty()
		Input.action_press("push_left")
		Input.action_press("push_right")
		await _wait(0.12)
		var slow := {"gain": ws.RL.roll_gain, "pitch": ws.RL.roll_player.pitch_scale, "speed": ws.RL.roll_speed}
		var max_scrub := 0.0
		var knocks0 := 0
		for k in ws:
			knocks0 += ws[k].knocks + ws[k].landings
		for i in int(0.9 * Engine.physics_ticks_per_second):
			await physics_frame
			for k in ws:
				max_scrub = maxf(max_scrub, ws[k].scrub_gain)
		Input.action_release("push_left")
		Input.action_release("push_right")
		var floors := {}
		var all_rolling := true
		var knocks := -knocks0
		for k in ws:
			floors[floor_name(ws[k])] = true
			all_rolling = all_rolling and ws[k].roll_gain > 0.9 and ws[k].roll_player.playing
			knocks += ws[k].knocks + ws[k].landings
		var want: String = c[3]
		var floor_ok := floors.size() == 1 and (want == "" or floors.has(want))
		_report(rest_ok and floor_ok and all_rolling and ws.RL.roll_gain > slow.gain and ws.RL.roll_player.pitch_scale > slow.pitch
			and max_scrub < 0.2 and knocks == 0, c[0],
			"wheels on %s (want %s), all four rolling %s; RL %.2f m/s gain %.2f pitch %.2f -> %.2f m/s gain %.2f pitch %.2f; scrub %.2f, knocks %d" % [
			floors.keys(), want if want else "any", all_rolling, slow.speed, slow.gain, slow.pitch, ws.RL.roll_speed,
			ws.RL.roll_gain, ws.RL.roll_player.pitch_scale, max_scrub, knocks])
		await _brake_to_rest(level)
		_report(playing(cart).is_empty(), c[0] + " at rest", "quiet: playing %s" % [playing(cart)])
		level.queue_free()
		await _wait(0.2)

	# Wheel physics checks on the supermarket's open floor.
	var level: Node3D = load("res://scenes/levels/supermarket.tscn").instantiate()
	root.add_child(level)
	await _wait(1.5)
	var spawn: Marker3D = level.get_node("CartSpawn")
	var cart: ShoppingCart = level.cart
	var ws := sounds(cart)

	# Wheelie while rolling: push, then hold S. The front wheels lift and go quiet; the rear keep rolling.
	# (Lambdas capture locals by value, so the counts live in a dictionary.)
	await _hold(["push_left", "push_right"], 0.8)
	var n := {"up": 0, "quiet": 0, "rear": 0}
	await _hold(["press", "push_left", "push_right"], 0.7, func():
		if not ws.FL.grounded and not ws.FR.grounded:
			n.up += 1
			if ws.FL.roll_gain == 0.0 and ws.FR.roll_gain == 0.0:
				n.quiet += 1
			if ws.RL.roll_gain > 0.5 and ws.RR.roll_gain > 0.5:
				n.rear += 1)
	_report(n.up > 20 and n.quiet > 10 and n.rear > 10, "wheelie",
		"front wheels up %d ticks: front quiet %d, rear rolling %d" % [n.up, n.quiet, n.rear])
	# Setting the front wheels down again: they come down hard enough to slam.
	var l0: int = ws.FL.slams + ws.FR.slams
	await _wait(1.0)
	_report(ws.FL.slams + ws.FR.slams >= 2, "front wheels slam down", "%d slams as the front came down at %.2f m/s" % [
		ws.FL.slams + ws.FR.slams - l0, maxf(ws.FL.last_impact, ws.FR.last_impact)])
	await _brake_to_rest(level)

	# A straight push rolls without scrubbing (checked per level above). Shoved sideways, the wheels can't roll
	# that way: they slide along their axles and scrub.
	level.spawn_cart(spawn.global_position, spawn.global_rotation.y)
	await _wait(1.0)
	cart = level.cart
	ws = sounds(cart)
	var side := cart.frame.global_transform.basis.z.normalized()
	var m := {"slide": 0.0, "scrub": 0}
	await _hold(["push_left", "push_right"], 0.6, func():
		cart.frame.apply_central_force(side * 500.0)   # someone shoves it sideways as it rolls
		for k in ws:
			m.slide = maxf(m.slide, ws[k].slide)
		if ws.values().any(func(w): return w.scrub_gain > 0.5 and w.scrub_player.playing):
			m.scrub += 1)
	_report(m.scrub > 10, "sideways slide scrubs", "slid up to %.2f m/s, a wheel scrubbing for %d ticks" % [m.slide, m.scrub])
	await _brake_to_rest(level)

	# Drops: each wheel's speed into the ground as it touches picks silent, tap or slam, and the volume.
	for d in [[0.0, "silent"], [0.05, "tap"], [0.3, "slam"]]:
		level.spawn_cart(spawn.global_position + Vector3(0, d[0], 0), spawn.global_rotation.y)
		cart = level.cart
		await process_frame
		ws = sounds(cart)
		await _wait(1.0)
		var heard := 0
		var slammed := 0
		var impact := 0.0
		for k in ws:
			heard += ws[k].landings
			slammed += ws[k].slams
			impact = maxf(impact, ws[k].last_impact)
		var got := "silent" if heard == 0 else ("slam" if slammed >= 4 else ("tap" if slammed == 0 else "mixed"))
		_report(got == d[1], "drop %d cm" % roundi(d[0] * 100), "%s (want %s): %d landings, %d slams, hit at %.2f m/s" % [
			got, d[1], heard, slammed, impact])

	print("ROLLING SOUND: %s" % ("all passed" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
