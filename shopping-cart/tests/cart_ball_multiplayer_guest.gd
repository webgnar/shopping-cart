extends SceneTree
## The guest half of tests/cart_ball_multiplayer_test.gd, started by it as a second Godot process:
##   godot --headless --path . -s res://tests/cart_ball_multiplayer_guest.gd -- <port> <result file>
## Joins 127.0.0.1, follows the host into the Cart Ball arena and writes what it sees of the match to <result file>
## (JSON) until full time: the phases, its team, scores, its own cart held at kickoff, the replay camera, full time.

var net: NetSession
var out := ""
var result := {"phases": [], "replay_camera": false, "locked_at_kickoff": false, "team": -1, "scores": []}


func _initialize() -> void:
	_run.call_deferred()


func _write() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[1]
	net = root.get_node("Net")
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("cart") == null:
		await physics_frame
	net.join("127.0.0.1", int(args[0]))
	var deadline := Time.get_ticks_msec() + 120000
	var game: CartBall = null
	var done_at := -1
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		game = get_first_node_in_group("cart_ball") as CartBall
		if game == null or net.level == null or net.level != current_scene:
			continue
		var phase := int(game.phase)
		if result.phases.is_empty() or result.phases[-1] != phase:
			result.phases.append(phase)
			result.scores.append(game.score.duplicate())
			_write()
		result.team = int(game.my_team())
		var own: ShoppingCart = current_scene.get("cart")
		if phase == CartBall.Phase.KICKOFF and own and own.locked:
			result.locked_at_kickoff = true
		if phase == CartBall.Phase.REPLAY and game.replay_camera.current and game.hud.get_node("%ReplayTag").visible:
			result.replay_camera = true
		if phase == CartBall.Phase.FULL_TIME and done_at < 0:
			done_at = Time.get_ticks_msec()
		if done_at > 0 and Time.get_ticks_msec() - done_at > 500:
			result.final = game.score.duplicate()
			result.full_time_panel = game.hud.get_node("%FullTime").visible
			result.final_line = game.hud.get_node("%FinalLine").text
			result.status = game.hud.get_node("%Status").text
			_write()
			break
	_write()
	net.leave()
	quit()
