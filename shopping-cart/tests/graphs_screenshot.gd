extends SceneTree
## Drives the cart down the sandbox's coast-down lane (push 2 s, coast, a right-hand tap turn, pull to a stop) with
## the HUD's graphs up (G), and saves a screenshot after each part. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/graphs_screenshot.gd -- <out dir>

var main: Node3D
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	var path := out_dir.path_join("graphs_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await _wait(seconds)
	for a in actions:
		Input.action_release(a)


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame


func _run() -> void:
	await process_frame
	main.hud._force_sign.visible = false
	main._next_lane()           # the coast-down lane
	await _key("graphs")
	await _wait(0.5)
	await _hold(["push_left", "push_right"], 2.0)
	await _shot("push")
	await _wait(1.5)
	await _shot("coast")
	await _hold(["push_left"], 0.8)
	await _wait(0.5)
	await _shot("turn")
	await _hold(["pull_left", "pull_right"], 1.5)
	await _wait(0.5)
	await _shot("stop")
	quit()
