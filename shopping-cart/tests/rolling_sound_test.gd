extends SceneTree
## Headless check of the cart's rolling sound (scenes/cart/cart.tscn, Frame/RollingSound): in every level the
## sound for that level's floor plays while the cart is pushed, louder and higher the faster it goes, and every
## sound stops once the cart is at rest.
## Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/rolling_sound_test.gd

const CASES := [
	# name, level, spawn (null: the level's CartSpawn), sound expected
	["sandbox asphalt", "res://scenes/main.tscn", Vector3(-10, 0, -3), "Asphalt"],
	["parking lot", "res://scenes/levels/parking_lot.tscn", null, "Asphalt"],
	["parking garage", "res://scenes/levels/parking_garage.tscn", null, "Concrete"],
	["supermarket", "res://scenes/levels/supermarket.tscn", null, "Tile"],
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
	print("%s  %-18s %s" % ["PASS" if ok else "FAIL", name, text])


func _playing(rs: CartRollingSound) -> Array:
	return rs.get_children().filter(func(c): return c is RollingSurfaceSound and c.playing).map(func(c): return String(c.name))


func _run() -> void:
	for c in CASES:
		var level: Node3D = load(c[1]).instantiate()
		root.add_child(level)
		await _wait(0.3)
		if c[2] != null:
			level.spawn_cart(c[2], 0.0)
		await _wait(1.5)
		var rs: CartRollingSound = level.cart.get_node("Frame/RollingSound")
		var rest_ok := _playing(rs).is_empty()
		Input.action_press("push_left")
		Input.action_press("push_right")
		await _wait(0.12)
		var slow_gain: float = rs.surface.gain if rs.surface else 0.0
		var slow_pitch: float = rs.surface.pitch_scale if rs.surface else 0.0
		var slow_speed := rs.speed
		await _wait(0.9)
		Input.action_release("push_left")
		Input.action_release("push_right")
		var sound := String(rs.surface.name) if rs.surface else "none"
		var playing := _playing(rs)
		var fast_gain: float = rs.surface.gain if rs.surface else 0.0
		var fast_pitch: float = rs.surface.pitch_scale if rs.surface else 0.0
		_report(rest_ok and sound == c[3] and playing == [c[3]] and fast_gain > slow_gain and fast_pitch > slow_pitch,
			c[0], "%s (expected %s), playing %s, %.2f m/s gain %.2f pitch %.2f -> %.2f m/s gain %.2f pitch %.2f" % [
			sound, c[3], playing, slow_speed, slow_gain, slow_pitch, rs.speed, fast_gain, fast_pitch])
		# Pull back to brake it to a stop, let go, and it goes quiet.
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
			if level.cart.frame.freeze and _playing(rs).is_empty():
				break
		_report(_playing(rs).is_empty(), c[0] + " rest", "quiet at rest: playing %s, speed %.2f" % [_playing(rs), rs.speed])
		level.queue_free()
		await _wait(0.2)
	print("ROLLING SOUND: %s" % ("all passed" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
