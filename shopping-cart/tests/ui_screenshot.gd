extends SceneTree
## Screenshots of every screen of UI (the driving HUD, pause menu, console, multiplayer menu and the race, sweep,
## cart collection and cart ball screens with their results), over the sandbox. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility --resolution 1920x1080 -s res://tests/ui_screenshot.gd -- <out dir>

var out_dir := "user://ui_shots"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _add(path: String) -> CanvasLayer:
	var ui := (load(path) as PackedScene).instantiate() as CanvasLayer
	root.add_child(ui)
	ui.visible = true
	return ui


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(30)
	await _shot("hud")

	var pause: PauseScreen = root.get_node("Pause")
	pause.open()
	await _shot("pause_menu")
	pause.close()

	var console: DebugConsole = root.get_node("Console")
	console.open()
	console.run_command("help")
	console.run_command("nope")
	await _shot("console")
	console.close()

	var menu := root.get_node("Net/Menu") as MultiplayerMenu
	menu.open()
	await _shot("multiplayer_menu")
	menu.close()

	var race := _add("res://scenes/ui/race_hud.tscn") as RaceHUD
	race.show_clock(62.48, "LAP 1 · 2ND PLACE")
	race.show_countdown("2", 0.5)
	race.show_results([{name = "You", time = 62.48, me = true}, {name = "Bot 1", time = 64.1},
		{name = "Bot 2", time = -1.0}])
	await _shot("race")
	race.queue_free()

	var sweep := _add("res://scenes/ui/sweep_hud.tscn") as SweepHUD
	sweep.show_clock(48.0, "Grab what you can")
	sweep.show_basket(12345, 14, 500)
	sweep.toast("+ Cereal $4.99")
	sweep.show_standings([{name = "You", cents = 12345, me = true}, {name = "Bot 1", cents = 9800, me = false}])
	sweep.show_results([{name = "You", cents = 12345, items = 14, bonus_cents = 500, me = true},
		{name = "Bot 1", cents = 9800, items = 11, bonus_cents = 0}])
	await _shot("sweep")
	sweep.queue_free()

	var collect := _add("res://scenes/ui/collect_hud.tscn") as CollectHUD
	collect.show_clock(212.0, "Push the carts into the store")
	collect.show_score(120, 9, 3)
	collect.show_board([{name = "You", points = 120, me = true}, {name = "Bot 1", points = 80, me = false}])
	collect.show_final([{name = "You", points = 120, returned = 9, best_chain = 4, me = true},
		{name = "Bot 1", points = 80, returned = 6, best_chain = 3}])
	await _shot("collect")
	collect.queue_free()

	var ball := _add("res://scenes/ui/cart_ball_hud.tscn") as CartBallHUD
	ball.show_score(2, 1, 95.0, "Kick off")
	ball.show_banner("GOAL!", Color(1, 0.86, 0.35), 1.0)
	ball.show_replay(true)
	ball.show_full_time(2, 1, "Green wins!")
	await _shot("cart_ball")
	ball.queue_free()
	quit()
