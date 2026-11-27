extends SceneTree
## The guest half of tests/cart_collect_multiplayer_test.gd, started by it as a second Godot process:
##   godot --headless --path . -s res://tests/cart_collect_multiplayer_guest.gd -- <port> <result file>
## Joins 127.0.0.1, follows the host into the cart collection lot, and once the round is on pushes forward at a
## walking pace in pulses (its own keys, sent to the host) until it has returned two carts. Writes what it sees to
## <result file> (JSON): the phases, its cart held in the count, its points, its pop-ups and the results.

var net: NetSession
var out := ""
var result := {"phases": [], "locked_in_count": false, "toasts": []}


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
	var deadline := Time.get_ticks_msec() + 150000
	var game: CartCollect = null
	var done_at := -1
	var pushing := false
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		game = get_first_node_in_group("cart_collect") as CartCollect
		if game == null or net.level == null or net.level != current_scene:
			continue
		var phase := int(game.phase)
		if result.phases.is_empty() or result.phases[-1] != phase:
			result.phases.append(phase)
			_write()
		var own: ShoppingCart = current_scene.get("cart")
		var me := game._me()
		if phase == CartCollect.Phase.COUNTDOWN and own and own.locked:
			result.locked_in_count = true
		var toasts: String = game.hud.get_node("%Toasts").text
		for t in toasts.split("\n"):
			if t != "" and not t in result.toasts:
				result.toasts.append(t)
		# Push while the round is on and we haven't brought two carts in.
		if phase == CartCollect.Phase.COLLECTING and own and not me.is_empty() and me.returned < 2:
			# Our cart here passes through the host's carts (it only predicts), so its own speed says nothing about
			# the chain's: push in pulses, about half the time.
			pushing = (Time.get_ticks_msec() / 600) % 2 == 0
		else:
			pushing = false
		for a in ["push_left", "push_right"]:
			if pushing:
				Input.action_press(a)
			else:
				Input.action_release(a)
		if phase == CartCollect.Phase.DONE and done_at < 0:
			done_at = Time.get_ticks_msec()
		if done_at > 0 and Time.get_ticks_msec() - done_at > 500:
			result.final = {"points": me.get("points", -1), "returned": me.get("returned", -1)}
			result.results_panel = game.hud.get_node("%Results").visible
			result.table = game.hud.get_node("%Table").text
			_write()
			break
	_write()
	net.leave()
	quit()
