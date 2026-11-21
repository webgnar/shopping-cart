extends SceneTree
## Two players on one machine: this process hosts, and starts a second Godot as the guest
## (tests/multiplayer_guest.gd) that joins over 127.0.0.1. Runs in real time (no --fixed-fps), about a minute:
##   godot --headless -s res://tests/multiplayer_test.gd
## Checks: the guest joins and gets a cart; both carts are pushed and both move on the host; once everything
## stops the guest sees both carts where the host has them; then the host travels through every level and the
## guest follows, with matching loose bodies, everything frozen on its side, its bots off and its cart upright.

const LEVELS := ["res://scenes/main.tscn", "res://scenes/levels/supermarket.tscn",
	"res://scenes/levels/parking_lot.tscn", "res://scenes/levels/parking_garage.tscn"]

var failures := 0
var net: NetSession
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-40s %s" % ["PASS" if ok else "FAIL", name, detail])


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await physics_frame


func _guest_result() -> Dictionary:
	if not FileAccess.file_exists(out):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(out))
	return data if data is Dictionary else {}


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _stopped(c: ShoppingCart) -> bool:
	return c.frame.freeze or (c.frame.linear_velocity.length() < 0.02 and c.frame.angular_velocity.length() < 0.05)


func _run() -> void:
	net = root.get_node("Net")
	out = ProjectSettings.globalize_path("user://multiplayer_guest_result.json")
	DirAccess.remove_absolute(out)
	var port := 24700 + randi() % 200
	change_scene_to_file(LEVELS[0])
	await _wait(0.3)
	_check("hosts", net.host(port), "port %d" % port)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/multiplayer_guest.gd", "--", str(port), out])
	_check("guest process starts", pid > 0, "pid %d" % pid)
	var deadline := Time.get_ticks_msec() + 40000
	while net._guests.is_empty() and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check("guest joins", not net._guests.is_empty(), "%d guests" % net._guests.size())
	if net._guests.is_empty():
		OS.kill(pid)
		_finish()
		return
	var gid: int = net._guests.keys()[0]
	await _wait(0.5)
	var host_cart: ShoppingCart = current_scene.cart
	var guest_cart: ShoppingCart = net.carts[gid]
	_check("guest cart is a remote-held cart", not guest_cart.player_controlled and guest_cart.driver == net, guest_cart.name)
	var host_start := host_cart.cart_origin()
	var guest_start := guest_cart.cart_origin()
	# The guest starts pushing once it sees snapshots; push the host's cart too.
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(2.5)
	Input.action_release("push_left")
	Input.action_release("push_right")
	var guest_keys := {}
	deadline = Time.get_ticks_msec() + 40000
	while not (_stopped(host_cart) and _stopped(guest_cart)) and Time.get_ticks_msec() < deadline:
		for k in guest_cart.controls:
			if guest_cart.controls[k]:
				guest_keys[k] = true
		await physics_frame
	var host_end := host_cart.cart_origin()
	var guest_end := guest_cart.cart_origin()
	_check("host's cart moves", host_end.distance_to(host_start) > 1.0, "%.1f m" % host_end.distance_to(host_start))
	_check("guest's cart moves on the host", guest_end.distance_to(guest_start) > 1.0,
		"%.1f m, keys %s, %d input packets" % [guest_end.distance_to(guest_start), guest_keys.keys(), net.stats.inputs_received])
	# Wait for the guest to report what it saw once everything stopped.
	var r := {}
	deadline = Time.get_ticks_msec() + 45000
	while not r.has("phase1") or not r.phase1.has("own_end"):
		if Time.get_ticks_msec() > deadline:
			break
		await _wait(0.25)
		r = _guest_result()
	_check("guest reports", r.has("phase1") and r.phase1.has("own_end"), str(r.get("error", "")))
	if r.has("phase1") and r.phase1.has("own_end"):
		var p: Dictionary = r.phase1
		var own_err := _vec(p.own_end).distance_to(guest_cart.cart_origin())
		var host_err := _vec(p.host_end).distance_to(host_cart.cart_origin())
		_check("guest sees its cart where the host has it", own_err < 0.05, "%.3f m off" % own_err)
		_check("guest sees the host's cart where it is", host_err < 0.05, "%.3f m off" % host_err)
		_check("guest saw the host's cart move", _vec(p.host_end).distance_to(_vec(p.host_start)) > 1.0,
			"%.1f m, %d snapshots" % [_vec(p.host_end).distance_to(_vec(p.host_start)), p.snapshots])
		_check("guest's own cart stays frozen there", p.own_frozen, "")
	# Fast travel: the guest follows.
	for path in LEVELS.slice(1):
		var name: String = path.get_file().get_basename()
		change_scene_to_file(path)
		var sent0: int = net.stats.snapshots_sent
		var t0 := Time.get_ticks_msec()
		await _wait(3.0)
		print("      %s: host sent %d snapshots in %.1f s" % [name, net.stats.snapshots_sent - sent0, (Time.get_ticks_msec() - t0) / 1000.0])
		guest_cart = net.carts.get(gid)
		_check(name + ": guest has a cart", guest_cart != null and is_instance_valid(guest_cart), "")
		if guest_cart == null:
			continue
		var up := guest_cart.frame.global_transform.basis.y.y
		_check(name + ": guest's cart spawns upright", up > 0.95 and not guest_cart.fallen, "up %.2f" % up)
		deadline = Time.get_ticks_msec() + 30000
		r = _guest_result()
		while not r.get("levels", {}).has(path) and Time.get_ticks_msec() < deadline:
			await _wait(0.25)
			r = _guest_result()
		var e: Dictionary = r.get("levels", {}).get(path, {})
		_check(name + ": guest follows", not e.is_empty(), "")
		if e.is_empty():
			continue
		_check(name + ": same loose bodies", e.bodies == e.expected and e.bodies == net.level_bodies.size(),
			"guest %d, host %d" % [e.bodies, net.level_bodies.size()])
		_check(name + ": guest gets snapshots", e.snapshots > 20, "%d in 2 s" % e.snapshots)
		_check(name + ": guest's level is frozen, bots off", e.all_frozen and e.bots_off, "")
		_check(name + ": guest sees both carts", e.carts == 2 and e.has("own") and e.has("host"), "%d carts" % e.carts)
		if e.has("own"):
			var err := _vec(e.own).distance_to(guest_cart.cart_origin())
			_check(name + ": guest's cart where the host has it", err < 0.05, "%.3f m off" % err)
	OS.kill(pid)
	_finish()


func _finish() -> void:
	net.leave()
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
