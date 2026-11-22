extends SceneTree
## Close-ups of the cart's back end: gate, child seat and seat flap, at rest, with the seat opened and with the gate
## swung up.
## Needs a display:  xvfb-run godot -s res://tests/cart_rig_screenshot.gd -- <output_prefix> [tint]
## With "tint" the gate is drawn red, the child seat green and the seat flap blue.

var main: Node3D
var prefix := "user://cart_rig"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(args.size() > 1 and args[1] == "tint")


func _tint(node: Node, color: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var hinge := mi.get_parent()
		while hinge and not hinge.name.ends_with("_Hinge"):
			hinge = hinge.get_parent()
		if hinge == node:
			(mi as MeshInstance3D).material_override = m


func _shot(name: String) -> void:
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("SCREENSHOT %s_%s.png" % [prefix, name])


func _views(cart: ShoppingCart, tag: String) -> void:
	var cam: Camera3D = main.camera
	var p := cart.frame.global_transform * Vector3(0.2, 0.75, 0)
	var x := cart.frame.global_basis.x
	var z := cart.frame.global_basis.z
	cam.fov = 40
	cam.global_position = p + z * 1.6 + x * 0.1
	cam.look_at(p)
	await _shot(tag + "_side")
	cam.global_position = p - x * 1.1 + z * 0.9 + Vector3(0, 0.6, 0)
	cam.look_at(p)
	await _shot(tag + "_back")
	cam.global_position = p + x * 1.3 + z * 0.7 + Vector3(0, 0.7, 0)
	cam.look_at(p)
	await _shot(tag + "_front")
	# The front casters and wheels, low from the front.
	var f := cart.frame.global_transform * Vector3(0.87, 0.1, 0)
	cam.global_position = f + x * 0.9 + z * 0.35 + Vector3(0, 0.15, 0)
	cam.look_at(f)
	await _shot(tag + "_casters")


func _run(tint: bool) -> void:
	for i in 120:
		await physics_frame
	main.set_process(false)
	var cart: ShoppingCart = main.cart
	if tint:
		var model := cart.get_node("Model")
		_tint(model.find_child("Gate_Hinge"), Color(0.9, 0.15, 0.1))
		_tint(model.find_child("ChildSeat_Hinge"), Color(0.1, 0.8, 0.2))
		_tint(model.find_child("SeatFlap_Hinge"), Color(0.15, 0.3, 0.95))
	await _views(cart, "rest")
	# Open the child seat: pull the backrest into the basket.
	for i in 40:
		cart.child_seat.apply_force(cart.frame.global_basis.x * 10.0, cart.child_seat.global_basis * Vector3(-0.15, 0.45, 0))
		await physics_frame
	for i in 120:
		await physics_frame
	# Then pull the seat flap down about its loops until it lies level.
	var tip := Vector3(-0.017, 0.119, 0)
	for i in 40:
		cart.seat_flap.apply_force(cart.frame.global_basis.x * 8.0, cart.seat_flap.global_basis * tip)
		await physics_frame
	for i in 240:
		await physics_frame
	await _views(cart, "seat_open")
	# Fold it again: lift the flap back against the gate, push the backrest back.
	for i in 60:
		cart.seat_flap.apply_force((cart.frame.global_basis.y - cart.frame.global_basis.x) * 8.0, cart.seat_flap.global_basis * tip)
		await physics_frame
	for i in 40:
		cart.child_seat.apply_force(-cart.frame.global_basis.x * 10.0, cart.child_seat.global_basis * Vector3(-0.15, 0.45, 0))
		await physics_frame
	for i in 240:
		await physics_frame
	# Swing the gate up from behind (what a cart nesting into this one does) and let the seat and flap follow.
	var lever := cart.frame.global_transform * Vector3(0.2, 0.55, 0)
	for i in 240:
		cart.gate.apply_force(cart.frame.global_basis.x * 40.0, lever - cart.gate.global_position)
		await physics_frame
	PhysicsServer3D.set_active(false)
	await _views(cart, "gate_up")
	quit()
