extends SceneTree
## The HUD's curve editor (C; scripts/ui/curve_panel.gd, curve_view.gd) in the sandbox:
##  - each view names its cart export, and says so while cart.gd doesn't have it,
##  - the operating points it works out meanwhile make sense (hands at handle height, fresh, moving with the cart),
##  - with a Curve in a view (here a test .tres in user://): dragging a point edits the curve the view holds,
##    double-click adds a point and right-click removes one, Save writes it to its .tres, and Revert reloads the
##    .tres into the same Curve instance (so whatever else holds it, like the cart, gets the old curve back).
##   godot --headless --fixed-fps 120 -s res://tests/curve_panel_test.gd

const TEST_PATH := "user://curve_panel_test.tres"

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame


func _click(v: CurveView, at: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.double_click = double
	e.position = at
	v._gui_input(e)


func _move(v: CurveView, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	v._gui_input(e)


func _run() -> void:
	await _wait(0.5)
	var panel: CurvePanel = main.hud._curve_sign
	_check(not panel.visible, "the curve sign starts hidden")
	await _press("curves")
	_check(panel.visible, "C opens the curve sign")
	_check(panel.views().size() == 3, "three curve views (%d)" % panel.views().size())
	await process_frame
	for v in panel.views():
		var has: bool = v.cart_property in main.cart
		_check(has or v.missing_text.contains(v.cart_property),
			"%s: %s" % [v.title, ("bound to cart." + v.cart_property) if has else ("says '%s'" % v.missing_text)])
	var by_key := {}
	for v in panel.views():
		by_key[v.input_key] = v
	var hh: Dictionary = by_key.handle_height.operating
	_check(absf(hh.L - 1.0) < 0.1 and absf(hh.R - 1.0) < 0.1, "hands at handle height: L %.2f m, R %.2f m" % [hh.L, hh.R])
	_check(by_key.fatigue.operating.L < 0.05, "fresh arms at rest (%.2f)" % by_key.fatigue.operating.L)
	Input.action_press("push_left")
	Input.action_press("push_right")
	await _wait(1.5)
	await process_frame
	var hs: Dictionary = by_key.hand_speed.operating
	var speed: float = main.cart.frame_velocity().length()
	Input.action_release("push_left")
	Input.action_release("push_right")
	_check(absf(hs.L - speed) < 0.3 and absf(hs.R - speed) < 0.3, "hand speed follows the cart: L %.2f, R %.2f, cart %.2f m/s" % [hs.L, hs.R, speed])
	_check(by_key.fatigue.operating.L > 0.2, "held arms tire (%.2f)" % by_key.fatigue.operating.L)

	# Editing, saving and reverting, on a test curve.
	var c := Curve.new()
	c.min_domain = 0.0
	c.max_domain = 2.0
	c.add_point(Vector2(0, 1), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	c.add_point(Vector2(1, 0.8), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	c.add_point(Vector2(2, 0.3), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	ResourceSaver.save(c, TEST_PATH)
	var curve: Curve = load(TEST_PATH)
	var v: CurveView = by_key.hand_speed
	if not (v.cart_property in main.cart):
		v.curve = curve
	else:
		curve = v.curve   # the cart has it: edit its own (and don't save over it below)
	await process_frame
	var mid := v.to_screen(curve.get_point_position(1))
	_click(v, mid)
	_move(v, v.to_screen(Vector2(1.2, 0.5)))
	_click(v, v.to_screen(Vector2(1.2, 0.5)), MOUSE_BUTTON_LEFT, false)
	var p := curve.get_point_position(1)
	_check(absf(p.x - 1.2) < 0.02 and absf(p.y - 0.5) < 0.02, "dragging moves the point to (%.2f, %.2f)" % [p.x, p.y])
	_check(main.hud._curve_sign.get_node("Lines/Status").text.contains("UNSAVED"), "the sign shows unsaved edits")
	_click(v, v.to_screen(Vector2(0.5, 0.2)), MOUSE_BUTTON_LEFT, true, true)
	_click(v, v.to_screen(Vector2(0.5, 0.2)), MOUSE_BUTTON_LEFT, false)
	_check(curve.point_count == 4, "double-click adds a point (%d)" % curve.point_count)
	_click(v, v.to_screen(curve.get_point_position(1)), MOUSE_BUTTON_RIGHT)
	_check(curve.point_count == 3, "right-click removes it (%d)" % curve.point_count)
	if curve.resource_path == TEST_PATH:
		_check(panel.save() == 1, "Save writes the edited curve")
		var on_disk: Curve = ResourceLoader.load(TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(on_disk.get_point_position(1).distance_to(Vector2(1.2, 0.5)) < 0.02, "the .tres holds the edit (%s)" % on_disk.get_point_position(1))
		curve.set_point_value(1, 0.9)
		v.edited.emit()
		panel.revert()
		_check(absf(curve.get_point_position(1).y - 0.5) < 0.02, "Revert puts the saved value back in the same Curve (%.2f)" % curve.get_point_position(1).y)
	await _press("curves")
	_check(not panel.visible, "C closes it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
