extends SceneTree
## Cart Ball with two players on one machine: this process hosts the arena and starts a second Godot as the guest
## (tests/cart_ball_multiplayer_guest.gd), which joins over 127.0.0.1. Real time (no --fixed-fps), about a minute:
##   godot --headless -s res://tests/cart_ball_multiplayer_test.gd
## Checks: a kickoff's count waits while the guest loads the arena; the guest is put on Red at a Red kickoff spot
## and the bots go to the bench; its cart is held through the count; goals at both ends count on the host and reach the guest, which watches the replay from the replay camera;
## first to five ends the match and the guest sees full time with the right score.

var failures := 0
var net: NetSession
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-44s %s" % ["PASS" if ok else "FAIL", name, detail])


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await physics_frame


func _until(game: CartBall, phase: CartBall.Phase, seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while game.phase != phase and Time.get_ticks_msec() < end:
		await physics_frame


func _goal(game: CartBall, into_red: bool) -> void:
	await _until(game, CartBall.Phase.PLAYING, 15.0)
	game.ball.global_position = Vector3(12.5 if into_red else -12.5, 0.66, 0.5)
	game.ball.linear_velocity = Vector3(5 if into_red else -5, 0, 0)
	await _until(game, CartBall.Phase.GOAL, 5.0)


func _run() -> void:
	net = root.get_node("Net")
	out = ProjectSettings.globalize_path("user://cart_ball_guest_result.json")
	DirAccess.remove_absolute(out)
	var port := 24900 + randi() % 200
	change_scene_to_file("res://scenes/levels/cart_ball_arena.tscn")
	await _wait(0.5)
	_check("hosts", net.host(port), "port %d" % port)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/cart_ball_multiplayer_guest.gd", "--", str(port), out])
	var deadline := Time.get_ticks_msec() + 40000
	var game := get_first_node_in_group("cart_ball") as CartBall
	while net._guests.is_empty() and Time.get_ticks_msec() < deadline:
		await physics_frame
	# A kickoff while the guest is still loading the arena: the count waits for it.
	game.start()
	var held := 0
	var ran_early := false
	while not net._guests.is_empty() and not net.guests_loaded() and Time.get_ticks_msec() < deadline:
		await physics_frame
		if net.guests_loaded():
			break
		held += 1
		ran_early = ran_early or game.phase != CartBall.Phase.KICKOFF or game._phase_time > 0.0
	_check("guest joins and loads the arena", not net._guests.is_empty() and net.guests_loaded(), "")
	_check("kickoff count waits while the guest loads", held > 0 and not ran_early, "%d ticks held" % held)
	await _until(game, CartBall.Phase.PLAYING, 6.0)
	_check("then the count runs", game.phase == CartBall.Phase.PLAYING, "")
	if net._guests.is_empty():
		OS.kill(pid)
		_finish()
		return
	var gid: int = net._guests.keys()[0]
	await _wait(1.0)

	# A new match with the guest in it.
	game.start()
	await _wait(0.2)
	var teams := {}
	for p in game.players:
		teams[p.id] = p.team
	_check("host on Green, guest on Red", teams.get(1) == CartBall.Team.GREEN and teams.get(gid) == CartBall.Team.RED, str(teams))
	var guest_cart: ShoppingCart = net.carts[gid]
	var spot := (game.red_spots.get_child(0) as Node3D).global_position
	_check("guest's cart on the Red kickoff spot", guest_cart.cart_origin().distance_to(spot) < 0.2,
		"%.2f m off" % guest_cart.cart_origin().distance_to(spot))
	var benched := game.bots().all(func(b): return not b.active and b.cart.cart_origin().z > 12.0)
	_check("the bots wait on the bench", not game.bots_playing() and benched, "")
	_check("guest's cart held through the count", guest_cart.locked, "")
	await _until(game, CartBall.Phase.PLAYING, 6.0)
	_check("GO: the guest's cart is free", not guest_cart.locked, "")

	await _goal(game, true)
	_check("Green scores", game.score == [1, 0], str(game.score))
	await _until(game, CartBall.Phase.REPLAY, 5.0)
	_check("the host replays it", game.phase == CartBall.Phase.REPLAY, "")
	await _goal(game, false)
	_check("Red scores", game.score == [1, 1], str(game.score))
	game.score = [4, 1]
	await _until(game, CartBall.Phase.KICKOFF, 15.0)
	await _goal(game, true)
	await _until(game, CartBall.Phase.FULL_TIME, 15.0)
	_check("first to five: full time", game.phase == CartBall.Phase.FULL_TIME and game.score == [5, 1], str(game.score))

	var r := {}
	deadline = Time.get_ticks_msec() + 20000
	while not r.has("final") and Time.get_ticks_msec() < deadline:
		await _wait(0.25)
		if FileAccess.file_exists(out):
			var data = JSON.parse_string(FileAccess.get_file_as_string(out))
			r = data if data is Dictionary else {}
	_check("guest reports", r.has("final"), str(r))
	if r.has("final"):
		var seen: Array = r.phases.map(func(x): return int(x))
		_check("guest sees kickoff, play, goal, replay, full time", [1, 2, 3, 4, 5].all(func(x): return x in seen), str(seen))
		_check("guest knows it's on Red", int(r.team) == CartBall.Team.RED, r.status)
		_check("guest's own cart held at kickoff", r.locked_at_kickoff, "")
		_check("guest watches the replay from the replay camera", r.replay_camera, "")
		_check("guest sees full time, 5-1, Green wins", r.full_time_panel and r.final == [5.0, 1.0] and r.final_line == "Green wins!",
			"%s %s" % [str(r.final), r.final_line])
	_finish()


func _finish() -> void:
	net.leave()
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
