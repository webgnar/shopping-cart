extends SceneTree
## Headless check of the parking garage level: the cart starts on the roof, and on every floor it rolls
## downhill on its own after a short push, staying on the deck. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/garage_test.gd

## [floor, aisle start (x, y, z), heading yaw, deck y at the far end of the floor]
const FLOORS := [
	[10, Vector3(13, 15.95, -3), 0.0, 14.4],
	[9, Vector3(41, 14.35, 3), PI, 12.8],
	[8, Vector3(13, 12.75, -3), 0.0, 11.2],
	[7, Vector3(41, 11.15, 3), PI, 9.6],
	[6, Vector3(13, 9.55, -3), 0.0, 8.0],
	[5, Vector3(55, 7.95, -3), 0.0, 6.4],
	[4, Vector3(83, 6.35, -14.4), PI, 4.8],
	[3, Vector3(55, 4.75, -3), 0.0, 3.2],
	[2, Vector3(83, 3.15, -14.4), PI, 1.6],
	[1, Vector3(55, 1.55, -3), 0.0, 0.0],
]

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/parking_garage.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %s" % ["PASS" if ok else "FAIL", what])


func _run() -> void:
	await _wait(2.0)
	var p: Vector3 = main.cart.cart_origin()
	_check(absf(p.y - 16.0) < 0.1 and p.x < 12.0 and main.cart.frame.freeze,
		"starts parked on the roof at (%.1f, %.2f, %.1f)" % [p.x, p.y, p.z])
	for f in FLOORS:
		var start: Vector3 = f[1]
		main.spawn_cart(start, f[2])
		main.cart.set_gear(3)
		await _wait(0.5)
		for a in ["push_left", "push_right"]:
			Input.action_press(a)
		await _wait(0.6)
		for a in ["push_left", "push_right"]:
			Input.action_release(a)
		await _wait(9.0)
		var end: Vector3 = main.cart.cart_origin()
		var dir := 1.0 if f[2] == 0.0 else -1.0
		var rolled := (end.x - start.x) * dir
		var t := clampf(rolled / 28.0, 0.0, 1.0)
		var deck := lerpf(start.y, f[3], t)
		var speed: float = main.cart.frame.linear_velocity.length()
		_check(rolled > 15.0 and end.y < start.y - 0.5 and absf(end.y - deck) < 0.3 and absf(end.z - start.z) < 2.5,
			"floor %-2d rolled %.1f m downhill, dropped %.2f m, %.1f km/h, %.2f m off the deck, drifted %.1f m sideways" % [
				f[0], rolled, start.y - end.y, speed * 3.6, end.y - deck, end.z - start.z])
	# Pushed across the flat halfway landing, the cart carries on straight onto floor 5 without a bump.
	main.spawn_cart(Vector3(44, 8.0, -3), 0.0)
	main.cart.set_gear(3)
	await _wait(0.5)
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	var crossed := false
	for i in 15 * Engine.physics_ticks_per_second:
		await physics_frame
		var q: Vector3 = main.cart.cart_origin()
		if q.x > 58.0:
			crossed = q.y < 8.0 and q.y > 7.0
			break
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	var q: Vector3 = main.cart.cart_origin()
	_check(crossed, "pushed across the halfway landing onto floor 5, now at (%.1f, %.2f, %.1f)" % [q.x, q.y, q.z])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
