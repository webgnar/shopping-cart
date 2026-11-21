extends SceneTree
## Headless check of the parking garage race. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/race_test.gd
## From the sandbox, the console's `race` loads the garage and lines the player and the three bot carts up on the
## roof's grid; nobody can move during 3, 2, 1 (keys held all through it do nothing); at GO the clock starts and the
## carts can go. Then the player's cart is put just before the finish line and pushed over it: it finishes first
## with that time. The bots race down the garage on their own; after finish_grace the race ends and the results
## list everyone. The bots take about three minutes (headless that's a minute or two of real time). Last, `race` again from inside the garage starts over.

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


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _run() -> void:
	console = root.get_node("Console")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	console.open()
	_check(console.run_command("race"), "race is a console command")
	await _frames(10)
	var level := current_scene
	_check(level != null and level.scene_file_path == "res://scenes/levels/parking_garage.tscn",
		"race fast-travels to the parking garage (%s)" % (level.scene_file_path if level else "nothing"))
	var race := get_first_node_in_group("race") as Race
	_check(race != null, "the garage has a Race")
	if race == null:
		quit(1)
		return
	await _frames(2)
	_check(race.phase == Race.Phase.COUNTDOWN, "counting down (phase %d, %.2f s to go)" % [race.phase, race.clock])
	_check(race.racers.size() == 4, "4 racers: you and 3 bots (%s)" % ", ".join(race.racers.map(func(r): return r.name)))
	# Everyone is on the roof grid, in its slots.
	var marks := race.slots()
	var on_grid := true
	for i in race.racers.size():
		var c := race.cart_of(race.racers[i])
		if c == null or c.cart_origin().distance_to(marks[i].global_position) > 0.15:
			on_grid = false
			print("      %s at %s, slot %s" % [race.racers[i].name, c.cart_origin() if c else "?", marks[i].global_position])
	_check(on_grid, "everyone lined up on the roof grid")

	# Hold both pushes through the count: nobody moves.
	var start: Vector3 = level.cart.cart_origin()
	var bot_starts := race.racers.slice(1).map(func(r): return race.cart_of(r).cart_origin())
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	var shown := {}
	while race.phase == Race.Phase.COUNTDOWN:
		shown[ceili(race.clock)] = true
		await physics_frame
	var moved: float = level.cart.cart_origin().distance_to(start)
	var bots_moved := 0.0
	for i in bot_starts.size():
		bots_moved = maxf(bots_moved, race.cart_of(race.racers[i + 1]).cart_origin().distance_to(bot_starts[i]))
	_check(shown.has(3) and shown.has(2) and shown.has(1), "the count shows 3, 2, 1 (%s)" % str(shown.keys()))
	_check(moved < 0.05 and bots_moved < 0.05, "nobody moves before GO (you %.3f m, bots up to %.3f m)" % [moved, bots_moved])
	_check(race.phase == Race.Phase.RACING and not level.cart.locked, "GO: racing and the hands are free")
	await _wait(1.0)
	moved = level.cart.cart_origin().distance_to(start)
	_check(moved > 0.3, "after GO the held pushes move the cart (%.2f m in 1 s)" % moved)
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	var bots_going := 0
	for i in bot_starts.size():
		if race.cart_of(race.racers[i + 1]).cart_origin().distance_to(bot_starts[i]) > 0.5:
			bots_going += 1
	_check(bots_going == 3, "the bots set off (%d of 3)" % bots_going)

	# Put the player's cart just before the line and push it over.
	await _wait(2.0)
	var line: Vector3 = race.finish.global_position
	level.spawn_cart(Vector3(line.x - 3.0, 0.0, -3.0), 0.0)
	await _wait(0.3)
	var t0 := race.clock
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	for i in 8 * Engine.physics_ticks_per_second:
		await physics_frame
		if race.racers[0].time >= 0.0:
			break
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	var me: Dictionary = race.racers[0]
	_check(me.time >= t0 and me.time < t0 + 8.0, "you cross the finish line and get a time (%s)" % RaceHUD.format_time(me.time))
	_check(race.results()[0].name == "You", "you are first in the results")

	# Let the bots race down the garage until the grace runs out.
	race.finish_grace = 300.0
	var bot_progress := []
	for s in 290:
		await _wait(1.0)
		if race.phase == Race.Phase.DONE:
			break
	for i in range(1, race.racers.size()):
		var r: Dictionary = race.racers[i]
		var c := race.cart_of(r)
		bot_progress.append("%s %s at x %.0f y %.1f" % [r.name, RaceHUD.format_time(r.time) if r.time >= 0.0 else "still going",
			c.cart_origin().x, c.cart_origin().y])
	print("      " + "; ".join(bot_progress))
	var bots_finished := race.racers.slice(1).filter(func(r): return r.time >= 0.0).size()
	_check(bots_finished >= 2, "bots race down all ten floors to the finish (%d of 3 finished)" % bots_finished)
	_check(race.phase == Race.Phase.DONE, "the race ends once everyone is over the line")
	_check(race.hud.get_node("%Results").visible and race.results().size() == 4, "the results show all 4 racers")
	_check(not level.cart.locked, "after the race the cart is free")

	# race again from inside the garage: everyone back on the grid, counting down.
	console.open()
	console.run_command("race nobots")
	await _frames(3)
	_check(current_scene == level, "race from inside the garage stays in the garage")
	_check(race.phase == Race.Phase.COUNTDOWN and race.racers.size() == 1 and not race.hud.get_node("%Results").visible,
		"race nobots starts over with just you (%d racers)" % race.racers.size())
	_check(level.cart.cart_origin().distance_to(marks[0].global_position) < 0.15, "you're back on the grid")

	print("RACE TEST: %s" % ("ALL PASS" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
