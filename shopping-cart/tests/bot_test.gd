extends SceneTree
## Bot carts drive themselves around each level that has them. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/bot_test.gd [-- <seconds per level>]
## For every BotCart: it drives through the same keys a player presses (never the keyboard), covers ground, reaches
## spots on the navigation mesh (or gives up on one and moves on), stays on the level and ends up on its wheels.

const LEVELS := ["res://scenes/levels/supermarket.tscn", "res://scenes/levels/parking_lot.tscn",
	"res://scenes/levels/parking_garage.tscn"]

var failures := 0


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-34s %s" % ["PASS" if ok else "FAIL", name, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 60.0
	for path in LEVELS:
		var level: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(level)
		var bots: Array = level.find_children("*", "", true, false).filter(func(n): return n is CartBot)
		var level_name: String = path.get_file().get_basename()
		_check("%s has bot carts" % level_name, bots.size() >= 2, "%d bots" % bots.size())
		var player: ShoppingCart = level.cart
		var last := {}
		var travelled := {}
		var lowest := {}
		var keys_seen := {}
		for b: CartBot in bots:
			last[b] = b.cart.cart_origin()
			travelled[b] = 0.0
			lowest[b] = b.cart.cart_origin().y
			keys_seen[b] = {}
		var ticks := int(seconds * Engine.physics_ticks_per_second)
		for i in ticks:
			await physics_frame
			if i % 12 == 0:
				for b: CartBot in bots:
					var p: Vector3 = b.cart.cart_origin()
					travelled[b] += Vector2(p.x - last[b].x, p.z - last[b].z).length()
					last[b] = p
					lowest[b] = minf(lowest[b], p.y)
					for k in b.cart.controls:
						keys_seen[b][k] = true
		for b: CartBot in bots:
			var c: ShoppingCart = b.cart
			var n := "%s %s" % [level_name, c.name]
			_check(n + " drives", travelled[b] > seconds * 0.4 and b.stats.trips + b.stats.gave_up >= 1,
				"%.0f m in %.0f s, %s, keys used %s" % [travelled[b], seconds, b.stats, keys_seen[b].keys()])
			_check(n + " stays on the level", lowest[b] > -2.0, "lowest y %.2f" % lowest[b])
			_check(n + " on its wheels", not c.fallen, "fallen %s, wheels down %d" % [c.fallen, c.wheels_down()])
			_check(n + " not on the keyboard", not c.player_controlled and c.driver == b, "")
		_check("%s player's cart stays on the keyboard" % level_name, player.player_controlled and player.driver == null, "")
		level.queue_free()
		await process_frame
	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
