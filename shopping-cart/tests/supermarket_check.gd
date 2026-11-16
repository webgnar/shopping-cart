extends SceneTree
## Loads the supermarket level, checks the cart spawns on all four wheels, can be pushed through the store
## and knocks cases off a pallet display, that spare carts ignore the keys but get shoved when rammed, and saves screenshots from a few spots. Exits 1 on a failure.
## Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/supermarket_check.gd -- <output folder>

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/supermarket.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


## A steady push at a fixed force per hand, so the hands don't keep ramping up (and tip the cart) over a long push.
func _steady(cart: ShoppingCart, newtons: float) -> void:
	cart.power_base = newtons
	cart.power_ramp = 0.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(dir: String, name: String) -> void:
	var path := dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://"
	await _frames(60)
	var spare: ShoppingCart = main.get_node("SpareCarts/Entrance1")
	var spare_start: Vector3 = spare.frame.global_position
	var start: Vector3 = main.cart.cart_origin()
	_check(main.cart.wheels_down() == 4, "spawned at %s on %d / 4 wheels" % [start, main.cart.wheels_down()])
	await _shot(dir, "1_entrance")
	_steady(main.cart, 45.0)
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	await _frames(240)
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	var p: Vector3 = main.cart.cart_origin()
	_check((p - start).length() > 5.0 and main.cart.wheels_down() == 4,
		"pushed %.1f m from the entrance, %d / 4 wheels down" % [(p - start).length(), main.cart.wheels_down()])
	var drift: float = spare.frame.global_position.distance_to(spare_start)
	_check(drift < 0.05, "spare cart by the door stayed put while the keys were held (moved %.3f m)" % drift)
	await _shot(dir, "2_pushing")
	# Into an aisle, looking down it
	main.spawn_cart(Vector3(-1.5, 0, 0), 0.0)
	await _frames(60)
	await _shot(dir, "3_aisle")
	main.spawn_cart(Vector3(-8, 0, 2.5), 0.6)
	main.cam_dist = 6.0
	main.cam_pitch = 0.6
	await _frames(60)
	await _shot(dir, "4_produce")
	# Ram the pallet display by the entrance: its cases should go flying.
	var stack: Node3D = main.get_node("Displays/Stack1")
	var before: Array[Vector3] = []
	for c in stack.get_node("Cases").get_children():
		before.append(c.global_position)
	main.spawn_cart(Vector3(-13.6, 0, 1.6), 0.0)
	_steady(main.cart, 90.0)
	main.cam_dist = 3.2
	main.cam_pitch = 0.38
	await _frames(30)
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	await _ticks(360)
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	await _ticks(120)
	var knocked := 0
	var cases := stack.get_node("Cases").get_children()
	for i in cases.size():
		if cases[i].global_position.distance_to(before[i]) > 0.1:
			knocked += 1
	_check(knocked > 0, "rammed a pallet display: %d of %d cases knocked" % [knocked, cases.size()])
	await _shot(dir, "6_crash")
	# Ram a spare cart: it should roll away, gate and all, and nothing should fall through the floor.
	var other: ShoppingCart = main.get_node("SpareCarts/FrontAisle")
	var other_start: Vector3 = other.frame.global_position
	main.spawn_cart(Vector3(-9.2, 0, 1.4), 0.0)
	_steady(main.cart, 90.0)
	await _frames(30)
	for a in ["push_left", "push_right"]:
		Input.action_press(a)
	await _ticks(240)
	for a in ["push_left", "push_right"]:
		Input.action_release(a)
	await _ticks(120)
	var shoved: Vector3 = other.frame.global_position - other_start
	_check(Vector2(shoved.x, shoved.z).length() > 0.2 and other.frame.global_position.y > -0.1,
		"rammed a spare cart: it moved %.2f m, %d / 4 wheels down" % [Vector2(shoved.x, shoved.z).length(), other.wheels_down()])
	await _shot(dir, "6b_cart_crash")
	main.spawn_cart(Vector3(-5, 0, 0), 0.0)
	main.cam_dist = 3.0
	main.cam_pitch = 0.05
	await _frames(60)
	await _shot(dir, "7_signs")
	main.spawn_cart(Vector3(-9.0, 0, 0.0), PI)
	main.cam_dist = 4.0
	main.cam_pitch = 0.25
	await _frames(60)
	await _shot(dir, "8_store_front")
	main.spawn_cart(Vector3(9.5, 0, -11.2), PI)
	main.cam_dist = 4.0
	main.cam_pitch = 0.35
	await _frames(60)
	await _shot(dir, "5_dairy")
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
