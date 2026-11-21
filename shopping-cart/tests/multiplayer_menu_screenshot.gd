extends SceneTree
## The Multiplayer menu while hosting online, saved as a screenshot. Uses the rendezvous service in
## rendezvous_url (or --rendezvous=<url>, e.g. a local `npm run dev`) and needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/multiplayer_menu_screenshot.gd -- <output.png> [--rendezvous=<url>]

func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else "user://multiplayer_menu.png"
	var net: NetSession = root.get_node("Net")
	change_scene_to_file("res://scenes/levels/supermarket.tscn")
	await _wait(1.0)
	net.game_name = "Zack's supermarket"
	await net.host_online()
	await _wait(1.5)
	var menu: MultiplayerMenu = net.get_node("Menu")
	menu.open()
	await net.games_listed
	await _wait(0.5)
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out, " ", net.status_text())
	net.leave()
	quit()
