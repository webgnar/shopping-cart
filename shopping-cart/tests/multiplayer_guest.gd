extends SceneTree
## The guest half of tests/multiplayer_test.gd, started by it as a second Godot process:
##   godot --headless --path . -s res://tests/multiplayer_guest.gd -- <port> <result file>
## Joins 127.0.0.1, pushes its cart for a moment, waits for every cart to stop, then follows the host through its
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
	var port := int(args[0])
	out = args[1]
	net = root.get_node("Net")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.5)
	net.join("127.0.0.1", port)
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
	# Follow the host from level to level until it ends the test.
	var seen := current_scene.scene_file_path if current_scene else ""
	while true:
		await physics_frame
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
