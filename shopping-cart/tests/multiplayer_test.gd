extends SceneTree
## Two players on one machine: this process hosts, and starts a second Godot as the guest
## (tests/multiplayer_guest.gd) that joins over 127.0.0.1. Runs in real time (no --fixed-fps), about a minute:
##   godot --headless -s res://tests/multiplayer_test.gd
## Online (WebRTC, join code) against a rendezvous service, e.g. `npm run dev` in services/rendezvous:
##   godot --headless -s res://tests/multiplayer_test.gd -- --online --rendezvous=http://127.0.0.1:8787
## (services/rendezvous/test/godot_online_test.mjs starts the service and runs this for you.)
## Checks: the guest joins and gets a cart; both carts are pushed and both move on the host; once everything
## stops the guest sees both carts where the host has them; then the host travels through every level and the
## guest follows, with matching loose bodies, everything frozen on its side, its bots off and its cart upright. Last,
## the host starts a race in the garage: the guest lines up, sees the count, is held until GO and gets the results.
## Then a supermarket sweep: the guest lines up, its cart is parked by the coffee and five cans drop into it on the
## host; the guest sees them in its basket, its score and pop-ups, and the results.

const LEVELS := ["res://scenes/main.tscn", "res://scenes/levels/supermarket.tscn",
	"res://scenes/levels/parking_lot.tscn", "res://scenes/levels/parking_garage.tscn"]

## s added to everything the guest sends (a slow connection): its own cart must still answer its keys at once.
const GUEST_LAG := 0.15

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
	var online := "--online" in OS.get_cmdline_user_args()
	var port := 24700 + randi() % 200
	change_scene_to_file(LEVELS[0])
	await _wait(0.3)
	var where := str(port)
	if online:
		net.game_name = "multiplayer test"
		where = await net.host_online()
		_check("hosts online", where != "", "code %s via %s" % [where, net.rendezvous_url])
		var t0 := Time.get_ticks_msec()
		while net.peer and net.peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() - t0 < 10000:
			await physics_frame
		_check("host connected to the service", net.peer != null and net.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, net.status_text())
		var games := await net.list_games()
		_check("listed in the game list", games.any(func(g): return g.code == where), "%d games" % games.size())
		if where == "":
			_finish()
			return
	else:
		_check("hosts", net.host(port), "port %d" % port)
	var guest_args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/multiplayer_guest.gd", "--", where, out, "--lag=%.2f" % GUEST_LAG]
	if online:
		guest_args.append("--rendezvous=" + net.rendezvous_url)
	var pid := OS.create_process(OS.get_executable_path(), guest_args)
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
	var host_flag := host_cart.get_node("Frame/Flag") as CartFlag
	var guest_flag := guest_cart.get_node("Frame/Flag") as CartFlag
	_check("both carts fly flags in different colours", host_flag.visible and guest_flag.visible
		and host_flag.color == 0 and guest_flag.color == net._guests[gid].slot and guest_flag.color != 0,
		"host %s %d, guest %s %d" % [host_flag.visible, host_flag.color, guest_flag.visible, guest_flag.color])
	_check("flags are only for looks", host_flag.find_children("*", "CollisionObject3D", true, false).is_empty()
		and host_flag.find_children("*", "CollisionShape3D", true, false).is_empty()
		and host_cart.frame.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM, "")
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
		_check("guest's own cart comes to rest there", p.own_frozen, "")
		_check("guest's cart answers its keys at once, %d ms lag" % roundi(GUEST_LAG * 1000.0),
			p.response <= r.offline_response + 0.05, "%.2f s, %.2f s offline" % [p.response, r.offline_response])
		_check("guest's prediction stays close to the host", p.own_error < 0.3, "largest error %.3f m" % p.own_error)
		_check("guest sees both flags, in the host's colours", p.flags[0][0] and int(p.flags[0][1]) == guest_flag.color
			and p.flags[1][0] and int(p.flags[1][1]) == 0, str(p.flags))
	# Endless sandbox: the guest drives off on its own (its cart is moved 320 m out, onto a flat chunk seam). The
	# host must stream ground around it too, and the guest must see the chunks and their loose bodies there.
	var streamer: ChunkStreamer = current_scene.get_node("Chunks")
	var far := streamer.global_position + Vector3(8 * streamer.chunk_size + 2.0, 0.02, 7 * streamer.chunk_size)
	net._spawn_guest_cart(gid, far, 0.0)
	await _wait(3.0)
	guest_cart = net.carts[gid]
	var gp := guest_cart.cart_origin()
	var up_far := guest_cart.frame.global_transform.basis.y.y
	_check("far away: host streams ground under the guest", absf(gp.y) < 0.3 and up_far > 0.95 and gp.distance_to(far) < 1.0,
		"at %s, up %.2f, %d chunks loaded" % [gp, up_far, streamer.loaded.size()])
	r = _guest_result()
	deadline = Time.get_ticks_msec() + 20000
	while not r.has("far") and Time.get_ticks_msec() < deadline:
		await _wait(0.25)
		r = _guest_result()
	_check("far away: guest reports", r.has("far"), "")
	if r.has("far"):
		var f: Dictionary = r.far
		var err := _vec(f.pos).distance_to(guest_cart.cart_origin())
		_check("far away: guest sees its cart there", err < 0.05, "%.3f m off" % err)
		_check("far away: guest has ground there", f.chunk_here and f.chunks > 4, "%d chunks" % f.chunks)
		var loose := streamer.find_children("*", "RigidBody3D", true, false).size()   # the sandbox's open lot has none
		_check("far away: guest's chunk bodies frozen, poses from the host", f.chunk_bodies_frozen and (f.chunk_poses > 0 or loose == 0),
			"%d chunk body poses (%d loose bodies in the host's chunks)" % [f.chunk_poses, loose])
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
		var mark := net.level.get_node_or_null("PlayerSpawns/Spawn1") as Node3D
		if mark:
			var off := (guest_cart.global_position - mark.global_position) * Vector3(1, 0, 1)
			_check(name + ": guest starts at its spawn marker", off.length() < 0.5, "%.2f m off" % off.length())
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
	await _race(gid)
	await _sweep(gid)
	OS.kill(pid)
	_finish()


## The host starts a race in the garage (the last level): the guest lines up on the grid, is held still through
## the count it sees too, and its finish shows up in the results on both sides.
func _race(gid: int) -> void:
	var race := get_first_node_in_group("race") as Race
	_check("race: the garage has a race", race != null, "")
	if race == null:
		return
	race.start(true)
	var deadline := Time.get_ticks_msec() + 15000
	while race.phase == Race.Phase.WAITING and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check("race: counting down once the guest has loaded", race.phase == Race.Phase.COUNTDOWN,
		"phase %d, %d racers" % [race.phase, race.racers.size()])
	var guest_cart: ShoppingCart = net.carts.get(gid)
	var slot := race.slots()[1]
	_check("race: guest lined up in the second slot", guest_cart != null and guest_cart.cart_origin().distance_to(slot.global_position) < 0.15,
		"%s vs %s" % [guest_cart.cart_origin() if guest_cart else "?", slot.global_position])
	_check("race: guest's cart is held during the count", guest_cart != null and guest_cart.locked, "")
	while race.phase == Race.Phase.COUNTDOWN:
		await physics_frame
	guest_cart = net.carts.get(gid)
	_check("race: GO frees the guest's cart", race.phase == Race.Phase.RACING and not guest_cart.locked, "")
	# Put the guest's cart, then ours, over the line; the bots get two seconds more.
	var line: Vector3 = race.finish.global_position
	net.place_guest_cart(gid, Vector3(line.x + 0.6, 0.0, -3.0), 0.0)
	await _wait(1.0)
	current_scene.spawn_cart(Vector3(line.x + 0.6, 0.0, -6.0), 0.0)
	race.finish_grace = 2.0
	deadline = Time.get_ticks_msec() + 10000
	while race.phase != Race.Phase.DONE and Time.get_ticks_msec() < deadline:
		await physics_frame
	var res := race.results()
	_check("race: guest finishes first, host second", res.size() >= 2 and res[0].id == gid and res[1].id == 1,
		", ".join(res.map(func(x): return "%s %.2f" % [x.name, x.time])))
	var r := _guest_result()
	deadline = Time.get_ticks_msec() + 15000
	while not r.has("race") and Time.get_ticks_msec() < deadline:
		await _wait(0.25)
		r = _guest_result()
	_check("race: guest reports", r.has("race"), "")
	if r.has("race"):
		var g: Dictionary = r.race
		_check("race: guest saw 3, 2, 1", g.counts.has(3.0) and g.counts.has(2.0) and g.counts.has(1.0) and g.hud_shown,
			"counts %s" % str(g.counts))
		_check("race: guest's results list everyone with its time", g.results_shown and int(g.racers) == res.size()
			and absf(g.my_time - res[0].time) < 0.01, "%d racers, my time %.2f" % [g.racers, g.my_time])


## The host runs a short sweep in the supermarket (no bots): the guest's cart, parked by the coffee, gets five cans.
func _sweep(gid: int) -> void:
	change_scene_to_file("res://scenes/levels/supermarket.tscn")
	await _wait(3.0)
	var sweep := get_first_node_in_group("sweep") as Sweep
	_check("sweep: the supermarket has a sweep", sweep != null, "")
	if sweep == null:
		return
	sweep.start(false, 12.0)
	var deadline := Time.get_ticks_msec() + 15000
	while sweep.phase == Sweep.Phase.WAITING and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check("sweep: counting down once the guest has loaded", sweep.phase == Sweep.Phase.COUNTDOWN,
		"phase %d, %d shoppers" % [sweep.phase, sweep.shoppers.size()])
	var guest_cart: ShoppingCart = net.carts.get(gid)
	var slot := sweep.slots()[1]
	_check("sweep: guest lined up at the entrance", guest_cart != null and guest_cart.cart_origin().distance_to(slot.global_position) < 0.15,
		"%s vs %s" % [guest_cart.cart_origin() if guest_cart else "none", slot.global_position])
	while sweep.phase == Sweep.Phase.COUNTDOWN:
		await physics_frame
	var coffee := sweep.displays.get_node("Coffee") as ProductDisplay
	net.place_guest_cart(gid, coffee.stop.global_position - Vector3(0.55, 0, 0), 0.0)
	await _wait(3.5)
	var g: Dictionary = sweep.shoppers.filter(func(x): return x.id == gid)[0]
	_check("sweep: coffee drops into the guest's cart", g.items == 5 and g.cents == 5 * 899, "%d items, %s" % [g.items, SweepHUD.money(g.cents)])
	deadline = Time.get_ticks_msec() + 20000
	while sweep.phase != Sweep.Phase.DONE and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check("sweep: time's up, guest wins", sweep.phase == Sweep.Phase.DONE and sweep.results()[0].id == gid, "")
	var r := _guest_result()
	deadline = Time.get_ticks_msec() + 15000
	while not r.has("sweep") and Time.get_ticks_msec() < deadline:
		await _wait(0.25)
		r = _guest_result()
	_check("sweep: guest reports", r.has("sweep"), "")
	if r.has("sweep"):
		var e: Dictionary = r.sweep
		_check("sweep: guest saw 3, 2, 1", e.counts.has(3.0) and e.counts.has(2.0) and e.counts.has(1.0), "counts %s" % str(e.counts))
		_check("sweep: guest sees the 5 cans in its basket", int(e.in_basket) == 5, "%d" % e.in_basket)
		_check("sweep: guest's score and pop-ups", int(e.my_cents) == 5 * 899 and e.toast_seen, "%s, pop-up %s" % [
			SweepHUD.money(int(e.my_cents)), e.toast_seen])
		_check("sweep: guest's display sign counts down", int(e.coffee_left) == 5, "%d left" % e.coffee_left)
		_check("sweep: guest's results list everyone", e.results_shown and int(e.shoppers) == sweep.shoppers.size(), "")


func _finish() -> void:
	net.leave()
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
