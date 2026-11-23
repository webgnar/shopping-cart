extends SceneTree
## Headless checks for the parking lot level. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/parking_lot_test.gd

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/parking_lot.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-26s %s" % ["PASS" if ok else "FAIL", name, detail])


## Pushes with both hands at a steady force (the old middle gear's), so a long push doesn't keep ramping up.
func _push(seconds: float) -> void:
	main.cart.power_base = 45.0
	main.cart.power_ramp = 0.0
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(seconds)
	Input.action_release("push_left")
	Input.action_release("push_right")


func _run() -> void:
	# The level's bot carts roam the lot. Their routes come from the navigation server, which runs on its own
	# timing, so on a busy machine a bot can reach corral 1A just as the push check rolls a cart into it. Take them
	# out so the checks below see only the player's cart (tests/bot_test.gd covers the bots).
	main.get_node("BotCarts").free()
	await _wait(1.0)
	var blocks := get_nodes_in_group("parking_block").size()
	var corrals := get_nodes_in_group("cart_corral").size()
	var lights := get_nodes_in_group("streetlight").size()
	_check("props present", blocks == 64 and corrals == 5 and lights == 10,
		"%d parking blocks, %d cart corrals, %d streetlights" % [blocks, corrals, lights])

	# Cart starts on the CartSpawn marker, settled on four wheels.
	var spawn: Vector3 = main.get_node("CartSpawn").global_position
	var cart: ShoppingCart = main.cart
	var at := cart.cart_origin()
	_check("spawns on marker", Vector2(at.x - spawn.x, at.z - spawn.z).length() < 0.1 and cart.wheels_down() == 4,
		"at (%.2f, %.2f, %.2f), wheels down %d" % [at.x, at.y, at.z, cart.wheels_down()])

	# Pushing down the fire lane works on this asphalt.
	var p0 := cart.cart_origin()
	await _push(3.0)
	var nose := cart.frame.global_transform.basis.x
	var along := cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())
	var moved := Vector2(cart.cart_origin().x - p0.x, cart.cart_origin().z - p0.z).length()
	_check("drives on asphalt", along > 1.0 and moved > 2.0, "moved %.2f m, %.2f m/s along the nose" % [moved, along])

	# A parking block stops a cart pushed into an empty stall (row 1 west, stall 4; block at z = -1.15).
	main.spawn_cart(Vector3(-14.85, 0, -4.2), -PI / 2)   # nose toward +Z, into the stall
	await _wait(1.0)
	cart = main.cart
	await _push(4.0)
	await _wait(1.0)
	var front := maxf(cart.wheels.FL.global_position.z, cart.wheels.FR.global_position.z)
	_check("parking block stops cart", front < -1.15 - 0.097 + 0.03 and front > -2.0,
		"front wheels stopped at z = %.2f (block face at -1.25)" % front)

	# A cart pushed into a corral's open end ends up inside it (corral 1A opens at z = -5.44, x = -1.3).
	main.spawn_cart(Vector3(-1.3, 0, -9.5), -PI / 2)
	await _wait(1.0)
	cart = main.cart
	await _push(5.0)
	await _wait(1.0)
	var c := cart.cart_origin()
	_check("cart rolls into corral", c.z > -5.0 and absf(c.x + 1.3) < 0.5,
		"cart origin at (%.2f, %.2f); corral runs z -5.44 to -1.27" % [c.x, c.z])

	# Background loop: plays on the Music bus, loops, keeps going with the console open, under the cart's roll.
	var music := main.get_node("BackgroundMusic") as AudioStreamPlayer
	var ogg := music.stream as AudioStreamOggVorbis
	var bus := AudioServer.get_bus_index(&"Music")
	_check("background music", music.playing and music.bus == &"Music" and bus > 0 and ogg != null and ogg.loop
		and music.process_mode == Node.PROCESS_MODE_ALWAYS and music.volume_db < -6.0,
		"playing %s on %s (bus %d), loop %s, %.0f s, %.1f dB" % [music.playing, music.bus, bus,
		ogg.loop if ogg else false, ogg.get_length() if ogg else 0.0, music.volume_db])

	# Fast travel (console) leaves the level, and its music with it.
	current_scene = main
	root.get_node("Console").run_command("garage")
	await _wait(0.5)
	var still := (root.find_children("*", "AudioStreamPlayer", true, false) as Array).filter(
		func(p): return p.playing and p.bus == &"Music")
	_check("music stops on travel", not is_instance_valid(main) and still.is_empty(),
		"parking lot freed %s, %d Music players still playing" % [not is_instance_valid(main), still.size()])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
