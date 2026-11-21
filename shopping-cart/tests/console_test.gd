extends SceneTree
## Headless checks for the debug console autoload. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/console_test.gd

var console: DebugConsole
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-26s %s" % ["PASS" if ok else "FAIL", name, detail])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await _frames(2)


func _scene() -> String:
	return current_scene.scene_file_path if current_scene else ""


func _run() -> void:
	console = root.get_node_or_null("Console")
	_check("autoload present", console != null, str(console))
	if console == null:
		quit(1)
		return
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)

	await _press(KEY_QUOTELEFT)
	_check("tilde opens", console.is_open() and paused, "open=%s paused=%s" % [console.is_open(), paused])
	await _press(KEY_QUOTELEFT)
	_check("tilde closes", not console.is_open() and not paused, "open=%s paused=%s" % [console.is_open(), paused])

	console.open()
	console.run_command("help")
	var text: String = console.get_node("%Output").get_parsed_text()
	_check("help lists travel", text.contains("plot") and text.contains("garage") and text.contains("market") and text.contains("hill") and text.contains("coast"), "")
	_check("unknown command", not console.run_command("fly"), "")

	for place in [["plot", "res://scenes/levels/parking_lot.tscn"], ["garage", "res://scenes/levels/parking_garage.tscn"], ["hill", "res://scenes/levels/sf_hill.tscn"], ["coast", "res://scenes/levels/coast_highway.tscn"], ["sandbox", "res://scenes/main.tscn"]]:
		console.open()
		console.run_command(place[0])
		await _frames(10)
		var cart: Node = current_scene.get_node_or_null("Cart") if current_scene else null
		_check("travel " + place[0], _scene() == place[1] and cart != null and not paused and not console.is_open(),
			"%s, cart=%s" % [_scene(), cart != null])

	var before := _scene()
	console.run_command("market")
	await _frames(5)
	var market_built := ResourceLoader.exists(console.destinations.market)
	_check("market", _scene() == ("res://scenes/levels/supermarket.tscn" if market_built else before),
		"%s (level %s)" % [_scene(), "built" if market_built else "not built yet, stayed put"])

	print("ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
