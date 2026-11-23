extends SceneTree
## Headless check of Cart Ball. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/cart_ball_test.gd
## From the sandbox, the console's `ball` loads the arena and starts a match: the ball sits frozen on the centre spot,
## your cart and the two Red bots on their kickoff spots, all held through 3, 2, 1. Left alone, the Red striker takes
## the ball into the Green goal while the keeper stays home; the goal is replayed, slowed down, from the sideline
## camera. Then (bots gone) holding both pushes drives the cart into the ball and moves it. A ball rolled over the Red line scores for Green, over the Green line for Red; each goal shows
## GOAL! and a replay (a push key skips it), then a new kickoff. A ball out of the arena goes back on the spot, and the
## first team to five goals wins.

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


func _release_all() -> void:
	for a in ["push_left", "push_right", "pull_left", "pull_right"]:
		Input.action_release(a)


## Rolls the ball from `at` with `vel` and waits up to `seconds` for a goal.
func _roll(game: CartBall, at: Vector3, vel: Vector3, seconds := 3.0) -> void:
	game.ball.global_position = at
	game.ball.linear_velocity = vel
	game.ball.angular_velocity = Vector3.ZERO
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		if game.phase != CartBall.Phase.PLAYING:
			return


func _run() -> void:
	console = root.get_node("Console")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	console.open()
	_check(console.run_command("ball"), "ball is a console command")
	await _frames(10)
	var level := current_scene
	_check(level != null and level.scene_file_path == "res://scenes/levels/cart_ball_arena.tscn",
		"ball fast-travels to the arena (%s)" % (level.scene_file_path if level else "nothing"))
	var game := get_first_node_in_group("cart_ball") as CartBall
	_check(game != null, "the arena has a CartBall match")
	if game == null:
		quit(1)
		return
	await _frames(2)
	var spot: Vector3 = game.ball_spawn.global_position
	var bots := game.bots()
	_check(game.phase == CartBall.Phase.KICKOFF, "kickoff count running (phase %d)" % game.phase)
	_check(game.score == [0, 0] and game.clock == 0.0 and game.goals_to_win == 5, "0-0, clock at 0:00, first to %d" % game.goals_to_win)
	_check(game.ball.global_position.distance_to(spot) < 0.05, "ball on the centre spot")
	_check(level.cart.cart_origin().distance_to(game.kickoff_spot.global_position) < 0.15, "your cart on the kickoff spot")
	_check(bots.size() == 2 and bots.all(func(b): return b.team == CartBall.Team.RED), "two Red bots (%d)" % bots.size())
	var bot_starts := bots.map(func(b): return b.cart.cart_origin())

	# Hold both pushes through the count: nothing moves, bots included.
	var start: Vector3 = level.cart.cart_origin()
	Input.action_press("push_left")
	Input.action_press("push_right")
	while game.phase == CartBall.Phase.KICKOFF:
		await physics_frame
	var bots_moved := 0.0
	for i in bots.size():
		bots_moved = maxf(bots_moved, bots[i].cart.cart_origin().distance_to(bot_starts[i]))
	_check(level.cart.cart_origin().distance_to(start) < 0.05 and bots_moved < 0.05,
		"everyone is held until GO (you %.3f m, bots up to %.3f m)" % [level.cart.cart_origin().distance_to(start), bots_moved])
	_check(game.phase == CartBall.Phase.PLAYING and not level.cart.locked and not game.ball.freeze,
		"GO: playing, hands free, ball loose")
	_release_all()

	# The Red bots on their own (your cart parked out of the way): the striker takes the ball to the Green goal, the
	# keeper stays home.
	level.cart.place(Vector3(-6, 0, 8), 0.0)
	var keeper: BallBot = bots.filter(func(b): return b.role == BallBot.Role.KEEPER)[0]
	var keeper_wander := 0.0
	var t := 0.0
	while game.phase == CartBall.Phase.PLAYING and t < 30.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		keeper_wander = maxf(keeper_wander, keeper.cart.cart_origin().distance_to(game.red_goal.global_position))
	_check(game.score == [0, 1], "the Red striker scores on its own (%s after %.1f s)" % [str(game.score), t])
	_check(keeper_wander < 6.0, "the Red keeper stays by its goal (up to %.1f m out)" % keeper_wander)

	# The replay: GOAL!, then the last seconds again from the sideline camera, then the kickoff.
	while game.phase == CartBall.Phase.GOAL:
		await physics_frame
	_check(game.phase == CartBall.Phase.REPLAY, "after GOAL! comes the replay (phase %d)" % game.phase)
	await _frames(2)
	_check(game.replay_camera.current and game.hud.get_node("%ReplayTag").visible, "watched from the replay camera, REPLAY on screen")
	var xs := []
	var replay_time := 0.0
	while game.phase == CartBall.Phase.REPLAY:
		await physics_frame
		replay_time += 1.0 / Engine.physics_ticks_per_second
		xs.append(game.ball.global_position.x)
	_check(xs.size() > 10 and xs.min() < -9.0 and xs.max() > xs.min() + 4.0 and xs.max() < -1.0 or
		xs.size() > 10 and xs.min() < -15.0,
		"the replay shows the ball going in (x from %.1f to %.1f)" % [xs.max() if xs.size() else 0.0, xs.min() if xs.size() else 0.0])
	_check(replay_time > game.replay_seconds / game.replay_speed * 0.8, "slowed down (%.1f s for %.1f s of play)" %
		[replay_time, game.replay_seconds])
	await _frames(2)
	_check(game.phase == CartBall.Phase.KICKOFF and not game.replay_camera.current and not level.cart.puppet
		and bots.all(func(b): return not b.cart.puppet and b.cart.cart_origin().distance_to(bot_starts[bots.find(b)]) < 0.15),
		"then the kickoff: your camera back, bots back on their spots")

	# The rest is about the rules: the bots leave.
	for b in bots:
		b.cart.queue_free()
	Input.action_press("push_left")
	Input.action_press("push_right")
	while game.phase == CartBall.Phase.KICKOFF:
		await physics_frame

	# Drive straight at the ball.
	var touched := false
	for i in int(8.0 * Engine.physics_ticks_per_second):
		await physics_frame
		if game.ball.global_position.distance_to(spot) > 1.0:
			touched = true
			break
	_release_all()
	_check(touched, "pushing into the ball moves it (ball %.2f m off the spot, cart at x %.2f)" %
		[game.ball.global_position.distance_to(spot), level.cart.cart_origin().x])
	_check(game.ball.global_position.y > 0.5 and game.ball.global_position.y < 3.0,
		"the ball stays on the floor (y %.2f)" % game.ball.global_position.y)

	# Out of the arena: back on the spot, no goal.
	await _roll(game, Vector3(0, 0.7, 30), Vector3.ZERO, 0.1)
	# (your cart is still by the spot here, so the ball may land against it)
	_check(Vector2(game.ball.global_position.x, game.ball.global_position.z).length() < 1.5 and game.score == [0, 1],
		"a ball out of the arena goes back on the spot, no goal (%s, %s)" % [game.ball.global_position, str(game.score)])

	# Roll it into the Red goal: Green scores.
	await _roll(game, Vector3(12.5, 0.66, 0.5), Vector3(5, 0, 0))
	_check(game.phase == CartBall.Phase.GOAL and game.score == [1, 1], "into the Red goal: Green scores (%s)" % str(game.score))
	await _frames(2)
	_check(game.hud.visible and game.hud.get_node("%Banner").text == "GOAL!" and game.hud.get_node("%GreenScore").text == "1",
		"GOAL! on screen and the scoreboard says 1-1")
	# A push key skips the replay.
	while game.phase != CartBall.Phase.REPLAY:
		await physics_frame
	await _frames(3)
	Input.action_press("push_left")
	await _frames(2)
	Input.action_release("push_left")
	_check(game.phase == CartBall.Phase.KICKOFF, "a push key skips the replay")
	while game.phase != CartBall.Phase.PLAYING:
		await physics_frame
	_check(game.ball.global_position.distance_to(spot) < 0.05 and
		level.cart.cart_origin().distance_to(game.kickoff_spot.global_position) < 0.15,
		"after the goal: ball and cart back on their spots for the kickoff")
	# A ball just short of the line is no goal.
	await _roll(game, Vector3(-13.0, 0.66, -1), Vector3(-0.8, 0, 0), 3.0)
	var short := game.ball.global_position.x
	_check(game.phase == CartBall.Phase.PLAYING and game.score == [1, 1],
		"a ball rolling onto the Green line but not all the way over is no goal (stopped at x %.2f)" % short)

	# Into the Green goal: Red scores.
	await _roll(game, Vector3(-12.5, 0.66, -1), Vector3(-5, 0, 0))
	_check(game.score == [1, 2], "into the Green goal: Red scores (%s)" % str(game.score))
	while game.phase != CartBall.Phase.PLAYING:
		await physics_frame

	_check(game.clock > 5.0, "the clock counts up the match time (%.1f s)" % game.clock)

	# First to five: Green's fifth goal wins it, after its replay.
	game.score = [4, 2]
	await _roll(game, Vector3(12.5, 0.66, 0.5), Vector3(5, 0, 0))
	_check(game.score == [5, 2], "Green's fifth goal (%s)" % str(game.score))
	while game.phase in [CartBall.Phase.GOAL, CartBall.Phase.REPLAY]:
		await physics_frame
	_check(game.phase == CartBall.Phase.FULL_TIME, "first to five: the match is over (phase %d)" % game.phase)
	await _frames(2)
	_check(game.hud.get_node("%FullTime").visible and game.hud.get_node("%FinalLine").text == "Green wins!",
		"full-time panel: %s" % game.hud.get_node("%FinalLine").text)

	# `ball` again starts a new match.
	console.open()
	console.run_command("ball")
	await _frames(10)
	game = get_first_node_in_group("cart_ball") as CartBall
	await _frames(2)
	_check(game != null and game.phase == CartBall.Phase.KICKOFF and game.score == [0, 0], "ball again: a new match")

	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
