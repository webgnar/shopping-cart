extends SceneTree
## The guest half of tests/multiplayer_test.gd, started by it as a second Godot process:
##   godot --headless --path . -s res://tests/multiplayer_guest.gd -- <port or join code> <result file> [--rendezvous=<url>]
## Joins 127.0.0.1 (or the game with that join code), pushes its cart for a moment, waits for every cart to stop, then follows the host through its
## levels. After each step it rewrites <result file> (JSON) with what it saw, for the host test to check.

var net: NetSession
var out := ""
var result := {"levels": {}}


func _initialize() -> void:
	_run.call_deferred()


func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _write() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await physics_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var where: String = args[0]
	out = args[1]
	net = root.get_node("Net")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.5)
	if NetSession.is_join_code(where):
		net.join_online(where)
	else:
		net.join("127.0.0.1", int(where))
	var deadline := Time.get_ticks_msec() + 30000
	while not (net.level and net.carts.has(1) and net.stats.snapshots_received > 10):
		if Time.get_ticks_msec() > deadline:
			result.error = "never got snapshots"
			_write()
			quit(1)
			return
		await physics_frame
	await _wait(0.5)
	var own: ShoppingCart = net.carts[net.my_id]
	var host_cart: ShoppingCart = net.carts[1]
	result.phase1 = {"id": net.my_id, "own_start": _v(own.cart_origin()), "host_start": _v(host_cart.cart_origin())}
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(2.5)
	Input.action_release("push_left")
	Input.action_release("push_right")
	# Every cart has stopped once the host has said so for a while.
	var still := 0.0
	deadline = Time.get_ticks_msec() + 40000
	while still < 1.5 and Time.get_ticks_msec() < deadline:
		await physics_frame
		var moving := own.puppet_velocity.length() > 0.02 or host_cart.puppet_velocity.length() > 0.02
		still = 0.0 if moving else still + 1.0 / Engine.physics_ticks_per_second
	await _wait(0.5)
	result.phase1.merge({"own_end": _v(own.cart_origin()), "host_end": _v(host_cart.cart_origin()),
		"own_frozen": own.frame.freeze, "snapshots": net.stats.snapshots_received})
	_write()
	# Follow the host from level to level until it ends the test. In the endless sandbox the host first moves our
	# cart far away: report the ground we see there.
	var seen := current_scene.scene_file_path if current_scene else ""
	var start_pos := own.cart_origin()
	var race_seen := {"phases": {}, "counts": {}}
	while true:
		await physics_frame
		# A race the host starts: what we see of it (the count, our cart held still, the results).
		var race := get_first_node_in_group("race") as Race
		if race and race.phase != Race.Phase.IDLE and not result.has("race"):
			race_seen.phases[race.phase] = true
			if race.phase == Race.Phase.COUNTDOWN:
				race_seen.counts[ceili(race.clock)] = true
				race_seen["hud_shown"] = race.hud.visible and race.hud.get_node("%Countdown").visible
			if race.phase == Race.Phase.DONE:
				var me := race.results().filter(func(r): return r.id == net.my_id)
				result.race = {"phases": race_seen.phases.keys(), "counts": race_seen.counts.keys(),
					"hud_shown": race_seen.get("hud_shown", false), "racers": race.racers.size(),
					"my_time": me[0].time if not me.is_empty() else -2.0,
					"results_shown": race.hud.get_node("%Results").visible}
				_write()
		if not result.has("far") and is_instance_valid(own) and own.cart_origin().distance_to(start_pos) > 150.0:
			await _wait(2.5)
			var streamer: ChunkStreamer = current_scene.get_node("Chunks")
			var p := own.cart_origin() - streamer.global_position
			var cell := Vector2i(floori(p.x / streamer.chunk_size), floori(p.z / streamer.chunk_size))
			var frozen := true
			for c in streamer.loaded:
				for b in streamer.loaded[c].find_children("*", "RigidBody3D", true, false):
					frozen = frozen and b.freeze
			result.far = {"pos": _v(own.cart_origin()), "chunk_here": streamer.loaded.has(cell),
				"chunks": streamer.loaded.size(), "chunk_bodies_frozen": frozen, "chunk_poses": net.stats.chunk_poses}
			_write()
		var path := current_scene.scene_file_path if current_scene else ""
		if path == seen or net.level == null or net.level != current_scene:
			continue
		var start: int = net.stats.snapshots_received
		var t0 := Time.get_ticks_msec()
		await _wait(2.0)
		print("      guest %s: %d snapshots in %.1f s, %d packets" % [path.get_file(), net.stats.snapshots_received - start, (Time.get_ticks_msec() - t0) / 1000.0, net.stats.packets_in])
		if net.level != current_scene:
			continue
		seen = path
		var frozen := net.level_bodies.all(func(b): return b.freeze)
		var bots_off := current_scene.find_children("*", "", true, false).filter(
			func(n): return n is CartBot and n.process_mode != Node.PROCESS_MODE_DISABLED).is_empty()
		var entry := {"bodies": net.level_bodies.size(), "expected": net._expected_bodies,
			"snapshots": net.stats.snapshots_received - start, "all_frozen": frozen, "bots_off": bots_off,
			"carts": net.carts.size()}
		if net.carts.has(net.my_id):
			entry.own = _v(net.carts[net.my_id].cart_origin())
		if net.carts.has(1):
			entry.host = _v(net.carts[1].cart_origin())
		result.levels[path] = entry
		_write()
