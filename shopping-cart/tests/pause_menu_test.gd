extends SceneTree
## Checks for the Esc pause menu autoload (scenes/ui/pause_menu.tscn). Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/pause_menu_test.gd
## With an out dir it also saves pause_menu.png of the open menu (needs a real renderer):
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/pause_menu_test.gd -- <out dir>

var menu: PauseMenu
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


func _button(text: String) -> Button:
	for grid in [menu.get_node("%Places"), menu.get_node("%Commands")]:
		for b: Button in grid.get_children():
			if b.text == text:
				return b
	return null


func _run() -> void:
	menu = root.get_node_or_null("Pause")
	console = root.get_node_or_null("Console")
	_check("autoload present", menu != null and console != null, str(menu))
	if menu == null or console == null:
		quit(1)
		return
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	if out != "":
		root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)

	await _press(KEY_ESCAPE)
	_check("esc opens", menu.is_open() and paused, "open=%s paused=%s" % [menu.is_open(), paused])
	var missing := []
	for place in console.destinations:
		if _button(place) == null:
			missing.append(place)
	for cmd in ["race", "sweep", "race downhill"]:
		if _button(cmd) == null:
			missing.append(cmd)
	_check("a button per place", missing.is_empty(), "missing %s" % [missing])
	_check("console-only hidden", _button("help") == null and _button("clear") == null, "")
	_check("quit button", menu.get_node_or_null("Center/Panel/Rows/BottomRow/QuitButton") != null, "")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
		await _frames(4)
		root.get_texture().get_image().save_png(out.path_join("pause_menu.png"))
		print("saved ", out.path_join("pause_menu.png"))
	await _press(KEY_ESCAPE)
	_check("esc closes", not menu.is_open() and not paused, "open=%s paused=%s" % [menu.is_open(), paused])

	# With the console open, Esc closes the console and leaves the pause menu shut.
	console.open()
	await _press(KEY_ESCAPE)
	_check("esc closes console first", not console.is_open() and not menu.is_open() and not paused,
		"console=%s menu=%s paused=%s" % [console.is_open(), menu.is_open(), paused])

	# Clicking a place travels there and unpauses.
	menu.open()
	_button("chain").pressed.emit()
	await _frames(10)
	_check("button travels", current_scene and current_scene.scene_file_path == console.destinations.chain
		and not paused and not menu.is_open(), current_scene.scene_file_path if current_scene else "none")

	# Hosting a game: the menu opens without pausing the world.
	var net := root.get_node("Net") as NetSession
	net.role = NetSession.Role.HOST
	menu.open()
	_check("online doesn't pause", menu.is_open() and not paused, "paused=%s" % paused)
	menu.close()
	net.role = NetSession.Role.OFFLINE

	print("ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
