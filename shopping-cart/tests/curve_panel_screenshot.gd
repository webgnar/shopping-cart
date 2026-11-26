extends SceneTree
## Screenshots of the HUD's curve editor (C) while the cart is pushed: as it is (each view saying whether cart.gd has
## its curve yet) and with sample curves in the views (made up here, only to show the drawing; they aren't the
## cart's). Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/curve_panel_screenshot.gd -- <out dir>

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
	var path := out_dir.path_join("curves_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _curve(lo: float, hi: float, pts: Array) -> Curve:
	var c := Curve.new()
	c.min_domain = lo
	c.max_domain = hi
	c.max_value = 1.2
	for p in pts:
		c.add_point(p, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


func _run() -> void:
	await process_frame
	main.hud._force_sign.visible = false
	main._next_lane()   # the coast-down lane
	var ev := InputEventAction.new()
	ev.action = "curves"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.3)
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(1.0)
	await _shot("as_is")
	var samples := {
		"hand_speed": _curve(-2, 8, [Vector2(-2, 1.0), Vector2(0, 1.0), Vector2(3, 0.75), Vector2(8, 0.15)]),
		"handle_height": _curve(0.5, 1.5, [Vector2(0.5, 0.6), Vector2(0.95, 1.0), Vector2(1.1, 1.0), Vector2(1.5, 0.5)]),
		"fatigue": _curve(0, 1, [Vector2(0, 1.0), Vector2(0.6, 0.85), Vector2(1, 0.4)]),
	}
	for v in main.hud._curve_sign.views():
		if not (v.cart_property in main.cart):
			v.curve = samples[v.input_key]
	await _wait(0.6)
	await _shot("samples")
	quit()
