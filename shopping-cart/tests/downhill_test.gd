extends SceneTree
## Headless check of the downhill highway race. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/downhill_test.gd
## `race downhill` loads the highway and lines the player up on the grid at the top; after 3, 2, 1, GO the test
## drives the cart down with the real keys (steering and braking the way the racing bots do) and checks
## the cart stays on the road the whole way, never drops through it, and crosses the finish line with a time.

const TIME_LIMIT := 300.0   ## s of game time to get down
const RACE_SPEED := 3.5     ## m/s the test driver holds

var console: DebugConsole
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %s" % ["PASS" if ok else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _run() -> void:
	console = root.get_node("Console")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	console.open()
	_check(console.run_command("race downhill nobots"), "race downhill is a console command")
	await _frames(10)
	var level := current_scene
	_check(level != null and level.scene_file_path == "res://scenes/levels/downhill_highway.tscn",
		"it travels to the downhill highway (%s)" % (level.scene_file_path if level else "nothing"))
	var race := get_first_node_in_group("race") as Race
	if race == null:
		_check(false, "the highway has a Race")
		quit(1)
		return
	await _frames(2)
	_check(race.phase == Race.Phase.COUNTDOWN, "counting down")
	var road := level.get_node("Road") as Path3D
	var curve := road.curve
	var length := curve.get_baked_length()
	var top_y := curve.sample_baked(0.0).y
	var bottom_y := curve.sample_baked(length).y
	print("      road %.0f m long, drops %.1f m" % [length, top_y - bottom_y])
	_check(top_y - bottom_y > 100.0, "the highway drops more than 100 m")
	while race.phase != Race.Phase.RACING:
		await physics_frame
	var t := 0.0
	var worst_off := 0.0
	var worst_drop := 0.0
	var top_speed := 0.0
	while race.phase == Race.Phase.RACING and race.racers[0].time < 0.0 and t < TIME_LIMIT:
		var cart: ShoppingCart = level.cart
		var at := cart.frame.global_position
		var off := curve.get_closest_offset(at)
		var centre := curve.sample_baked(off)
		var ahead := curve.sample_baked(minf(off + 12.0, length))
		var side := Vector3(at.x - centre.x, 0, at.z - centre.z).length()
		worst_off = maxf(worst_off, side)
		worst_drop = maxf(worst_drop, centre.y - at.y)
		top_speed = maxf(top_speed, cart.frame.linear_velocity.length())
		# Steer like a racing bot (scripts/cart_bot.gd): a force wanted from each hand, pushed or pulled toward with
		# the real keys. It brakes with a pull when it runs faster than RACE_SPEED down the hill.
		var nose := cart.frame.global_basis.x
		var speed := cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())
		var err := wrapf(atan2(-(ahead.z - at.z), ahead.x - at.x) - cart.heading(), -PI, PI)
		var forward := clampf(60.0 * (RACE_SPEED - speed), -90.0, 90.0)
		var steer := 45.0 * err - 25.0 * cart.frame.angular_velocity.y
		var want := {"left": clampf(forward - steer, -90.0, 90.0), "right": clampf(forward + steer, -90.0, 90.0)}
		for hand in want:
			var w: float = want[hand]
			var p: float = cart.hand_power["L" if hand == "left" else "R"]
			_key("push_" + hand, w > 3.0 and p < w)
			_key("pull_" + hand, w < -3.0 and p > w)
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	for a in ["push_left", "push_right", "pull_left", "pull_right"]:
		_key(a, false)
	print("      down in %.1f s, top speed %.1f m/s, furthest from the centre line %.2f m, deepest below the road %.2f m"
		% [t, top_speed, worst_off, worst_drop])
	_check(worst_off < 5.3, "the cart stays between the barriers")
	_check(worst_drop < 0.5, "the cart never drops through the road")
	var me: Dictionary = race.racers[0]
	_check(me.time > 0.0, "the cart crosses the finish line with a time (%s)" % RaceHUD.format_time(me.time))
	print("%s: %d failed" % ["PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)
