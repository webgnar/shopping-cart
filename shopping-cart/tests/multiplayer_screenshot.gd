extends SceneTree
## A guest's view of a hosted game, saved as a screenshot. Start a host first, then (needs a display, e.g. xvfb-run):
##   godot --headless --path . res://scenes/levels/supermarket.tscn -- --host=24650 &
##   xvfb-run godot -s res://tests/multiplayer_screenshot.gd -- <output.png> [port] [seconds of pushing]

func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://multiplayer.png"
	var port := int(args[1]) if args.size() > 1 else 24650
	var push := float(args[2]) if args.size() > 2 else 0.0
	var net: NetSession = root.get_node("Net")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.5)
	net.join("127.0.0.1", port)
	await _wait(4.0)
	if push > 0.0:
		Input.action_press("push_left")
		Input.action_press("push_right")
		await _wait(push)
		Input.action_release("push_left")
		Input.action_release("push_right")
		await _wait(0.6)
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out, " ", net.status_text())
	net.leave()
	quit()
