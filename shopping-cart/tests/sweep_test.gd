extends SceneTree
## Headless check of the supermarket sweep. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/sweep_test.gd
## From the sandbox, the console's `sweep 45` loads the supermarket and lines the player and the three bot carts up
## at the entrance with empty baskets; nobody moves during 3, 2, 1. After GO: the player's cart parked by the coffee
## display gets coffee dropped into its basket up to the limit of 5 (and no more), and the score is their price;
## rolling the cart over spills them and the score drops; bumping the giant soup claims its bonus; standing still in
## the deli counter's box earns its bonus. The bots shop on their own. When time's up the results list everyone;
## `sweep nobots` restocks the store and starts over.

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


func _hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await _wait(seconds)
	for a in actions:
		Input.action_release(a)


func _display(sweep: Sweep, name: String) -> ProductDisplay:
	return sweep.displays.get_node(name) as ProductDisplay


func _run() -> void:
	console = root.get_node("Console")
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	console.open()
	_check(console.run_command("sweep 45"), "sweep is a console command")
	await _frames(10)
	var level := current_scene
	_check(level != null and level.scene_file_path == "res://scenes/levels/supermarket.tscn",
		"sweep fast-travels to the supermarket (%s)" % (level.scene_file_path if level else "nothing"))
	var sweep := get_first_node_in_group("sweep") as Sweep
	_check(sweep != null, "the supermarket has a Sweep")
	if sweep == null:
		quit(1)
		return
	await _frames(2)
	_check(sweep.phase == Sweep.Phase.COUNTDOWN, "counting down (phase %d)" % sweep.phase)
	_check(sweep.round_time == 45.0, "sweep 45 sets a 45 s round (%.0f)" % sweep.round_time)
	_check(sweep.shoppers.size() == 4, "4 shoppers: you and 3 bots (%s)" % ", ".join(sweep.shoppers.map(func(s): return s.name)))
	_check(sweep.display_list().size() == 12 and sweep.products().size() == 104, "12 displays, 104 products (%d, %d)" % [
		sweep.display_list().size(), sweep.products().size()])
	var marks := sweep.slots()
	var lined := true
	for i in sweep.shoppers.size():
		var c := sweep.cart_of(sweep.shoppers[i])
		if c == null or c.cart_origin().distance_to(marks[i].global_position) > 0.15:
			lined = false
	_check(lined, "everyone lined up at the entrance")
	_check(level.cart.groceries_in_basket() == 0, "carts start with an empty basket (%d groceries shown)" % level.cart.groceries_in_basket())
	var start: Vector3 = level.cart.cart_origin()
	await _hold(["push_left", "push_right"], 3.2)
	_check(sweep.phase == Sweep.Phase.SWEEPING, "GO: sweeping")
	_check(level.cart.cart_origin().distance_to(start) < 0.3, "nobody moves during the count (%.2f m)" % level.cart.cart_origin().distance_to(start))

	# Park by the coffee: the coffee drops in, up to the limit.
	var coffee := _display(sweep, "Coffee")
	var stop := coffee.stop.global_position
	level.spawn_cart(stop - Vector3(0.55, 0, 0), 0.0)
	level.cart.show_groceries(false)
	await _wait(4.0)
	var me: Dictionary = sweep.shoppers[0]
	var n := sweep._count_of(level.cart, "Coffee")
	_check(n == 5, "parked by the coffee, 5 cans drop into the basket (%d)" % n)
	_check(coffee.left() == 5, "and the display has 5 left (%d)" % coffee.left())
	_check(me.cents == 5 * 899 and me.items == 5, "score is 5 x $8.99 = $44.95 (%s, %d items)" % [SweepHUD.money(me.cents), me.items])
	await _wait(2.0)
	_check(coffee.left() == 5, "no more than the limit: still 5 left after waiting (%d)" % coffee.left())

	# Roll the cart over: the coffee spills out and stops counting.
	var before: int = me.cents
	var nose: Vector3 = level.cart.frame.global_transform.basis.x
	level.cart._wake()   # a cart standing still is pinned until something moves it
	level.cart.frame.angular_velocity = nose * -7.0   # top away from the display, into the aisle
	level.cart.frame.linear_velocity = Vector3(0, 2.0, 0)
	await _wait(3.0)
	print("      cart up %.2f fallen %s" % [level.cart.frame.global_transform.basis.y.y, level.cart.fallen])
	_check(me.cents < before, "rolling the cart over spills the coffee (%s -> %s)" % [SweepHUD.money(before), SweepHUD.money(me.cents)])

	# Bump the giant soup can.
	var soup := sweep.bonuses.get_node("GiantSoup") as Inflatable
	var at := soup.global_position
	level.spawn_cart(at + Vector3(-2.2, 0, 0), 0.0)
	await _hold(["push_left", "push_right"], 2.5)
	_check(soup.claimed and me.bonus_cents == 10000, "bumping the giant soup claims $100 (claimed %s, bonus %s)" % [
		soup.claimed, SweepHUD.money(me.bonus_cents)])

	# Stand still in the deli counter's box.
	var deli := sweep.stations.get_node("DeliCounter") as BonusStation
	level.spawn_cart(deli.global_position - Vector3(0.5, 0, 0), 0.0)
	await _wait(4.0)
	_check(me.bonus_cents == 15000, "holding still at the deli counter adds $50 (bonus %s)" % SweepHUD.money(me.bonus_cents))
	await _wait(3.0)
	_check(me.bonus_cents == 15000, "and only once (bonus %s)" % SweepHUD.money(me.bonus_cents))

	# The bots shop until time's up.
	while sweep.phase == Sweep.Phase.SWEEPING:
		await _wait(0.5)
	var bot_items := 0
	for s in sweep.shoppers.slice(1):
		bot_items += s.items
		var b: CartBot = s.bot
		print("      %s: %s, %d items (%s)" % [s.name, SweepHUD.money(s.cents), s.items, str(b.stats)])
	_check(bot_items >= 3, "the bots shop too (%d items between them)" % bot_items)
	_check(sweep.phase == Sweep.Phase.DONE, "time's up")
	_check(sweep.hud.get_node("%Results").visible and sweep.results().size() == 4, "the results show all 4 shoppers")
	print("      " + sweep.hud.get_node("%Table").text.replace("\n", "\n      "))

	# sweep again from inside the store: restocked, everyone back at the entrance.
	console.open()
	console.run_command("sweep nobots")
	await _frames(3)
	_check(current_scene == level, "sweep from inside the store stays there")
	_check(sweep.phase == Sweep.Phase.COUNTDOWN and sweep.shoppers.size() == 1 and not sweep.hud.get_node("%Results").visible,
		"sweep nobots starts over with just you (%d shoppers)" % sweep.shoppers.size())
	_check(coffee.left() == 10 and not soup.claimed, "the store is restocked (coffee %d left)" % coffee.left())
	_check(sweep.round_time == sweep.duration, "a plain sweep is %.0f s" % sweep.round_time)

	print("SWEEP TEST: %s" % ("ALL PASS" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
