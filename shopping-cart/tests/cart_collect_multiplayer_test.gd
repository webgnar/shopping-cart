extends SceneTree
## Cart collection with two players on one machine: this process hosts the lot and starts a second Godot as the
## guest (tests/cart_collect_multiplayer_guest.gd), which joins over 127.0.0.1. Real time (no --fixed-fps), about a
## minute:
##   godot --headless -s res://tests/cart_collect_multiplayer_test.gd
## Checks: the round waits for the guest to load the lot; the guest gets a starting slot and is held through the
## count; at GO the guest (pressing its own keys) rams two loose carts lined up in front of it, pushes the chain into
## the door and scores 10 + 15 on the host; the guest sees the count, the round, its points, its pop-ups and the
## results with the right score.

var failures := 0
var net: NetSession
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-48s %s" % ["PASS" if ok else "FAIL", name, detail])


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await physics_frame


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while not cond.call() and Time.get_ticks_msec() < end:
		await physics_frame


func _run() -> void:
	net = root.get_node("Net")
	out = ProjectSettings.globalize_path("user://cart_collect_guest_result.json")
	DirAccess.remove_absolute(out)
	var port := 25100 + randi() % 200
	change_scene_to_file("res://scenes/levels/cart_collect_lot.tscn")
	await _wait(0.5)
	_check("hosts", net.host(port), "port %d" % port)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/cart_collect_multiplayer_guest.gd", "--", str(port), out])
	await _until(func(): return not net._guests.is_empty(), 40.0)
	_check("guest joins", not net._guests.is_empty(), "")
	if net._guests.is_empty():
		OS.kill(pid)
		_finish()
		return
	var gid: int = net._guests.keys()[0]

	# A new round with the guest in it: it waits until the guest has the lot loaded.
	var game := get_first_node_in_group("cart_collect") as CartCollect
	game.start()
	_check("waits for the guest to load", game.phase == CartCollect.Phase.WAITING or net.guests_loaded(), "phase %d" % game.phase)
	await _until(func(): return game.phase == CartCollect.Phase.COUNTDOWN, 30.0)
	_check("guest loaded: the count starts", game.phase == CartCollect.Phase.COUNTDOWN and net.guests_loaded(), "")
	_check("both players in the round", game.shoppers.map(func(s): return s.id) == [1, gid], str(game.shoppers.map(func(s): return s.id)))
	var guest_cart: ShoppingCart = net.carts[gid]
	var slot := (game.slots()[1] as Node3D).global_position
	_check("guest's cart on its starting slot", guest_cart.cart_origin().distance_to(slot) < 0.2,
		"%.2f m off" % guest_cart.cart_origin().distance_to(slot))
	_check("guest's cart held through the count", guest_cart.locked, "")
	await _until(func(): return game.phase == CartCollect.Phase.COLLECTING, 6.0)
	_check("GO: the guest's cart is free", not guest_cart.locked, "")

	# Line two loose carts up in front of the guest's cart, all facing the door; the guest pushes.
	var a: ShoppingCart = game.loose_carts()[0]
	var b: ShoppingCart = game.loose_carts()[1]
	a.place(Vector3(2.0, 0, 0), PI)
	b.place(Vector3(4.5, 0, 0), PI)
	net.place_guest_cart(gid, Vector3(6.8, 0, 0), PI)
	var g: Dictionary = game._shopper_by_id(gid)
	await _until(func(): return g.carrying >= 2, 30.0)
	_check("guest's cart rams both carts on", g.carrying == 2, "pushing %d" % g.carrying)
	await _until(func(): return g.returned >= 2, 30.0)
	_check("guest returns both: 10 + 15", g.returned == 2 and g.points == 25, "%d carts, %d points" % [g.returned, g.points])
	await _wait(1.5)
	game.clock = 0.5
	await _until(func(): return game.phase == CartCollect.Phase.DONE, 5.0)
	_check("time's up", game.phase == CartCollect.Phase.DONE, "")

	var r := {}
	var deadline := Time.get_ticks_msec() + 20000
	while not r.has("final") and Time.get_ticks_msec() < deadline:
		await _wait(0.25)
		if FileAccess.file_exists(out):
			var data = JSON.parse_string(FileAccess.get_file_as_string(out))
			r = data if data is Dictionary else {}
	_check("guest reports", r.has("final"), str(r))
	if r.has("final"):
		var seen: Array = r.phases.map(func(x): return int(x))
		_check("guest sees the count, the round and time's up", [2, 3, 4].all(func(x): return x in seen), str(seen))
		_check("guest's own cart held in the count", r.locked_in_count, "")
		_check("guest sees its own points", int(r.final.points) == 25 and int(r.final.returned) == 2, str(r.final))
		_check("guest gets its pop-ups", r.toasts.any(func(t): return "+15" in t), str(r.toasts))
		_check("guest sees the results", r.results_panel and "25 pts" in r.table, r.table)
	_finish()


func _finish() -> void:
	net.leave()
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
