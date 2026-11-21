extends SceneTree
## Renders the supermarket sweep: the count at the entrance, a cart filling up at a display, a giant inflatable,
## a bonus station, the results, and an overhead plan of where everything is. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/sweep_screenshot.gd -- <out dir>

var main: Node3D


func _initialize() -> void:
	Sweep.start_on_load = true
	main = load("res://scenes/levels/supermarket.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _shot(name: String) -> void:
	await _frames(3)
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var path := dir.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _look(at: Vector3, yaw: float, dist: float, pitch: float) -> void:
	main.cam_dist = dist
	main.cam_pitch = pitch
	main.spawn_cart(at, yaw)
	main.cart.show_groceries(false)
	await _frames(40)


func _run() -> void:
	var sweep := get_first_node_in_group("sweep") as Sweep
	await _frames(5)
	main.cam_dist = 7.0
	main.cam_pitch = 0.4
	while sweep.clock > 1.6:
		await physics_frame
	await _shot("sweep_countdown.png")
	while sweep.phase != Sweep.Phase.SWEEPING:
		await physics_frame
	# Filling up at the coffee: parked alongside, the cans drop in.
	var coffee := sweep.displays.get_node("Coffee") as ProductDisplay
	main.spawn_cart(coffee.stop.global_position - Vector3(0.55, 0, 0), 0.0)
	main.cart.show_groceries(false)
	main.cam_dist = 2.6
	main.cam_pitch = 0.5
	main.cam_yaw = -0.5
	await _wait(1.2)
	await _shot("sweep_grab.png")
	await _wait(2.5)
	await _shot("sweep_coffee_limit.png")
	# A display up close.
	var steak := sweep.displays.get_node("Steak") as ProductDisplay
	main.cam_yaw = 0.0
	await _look(steak.stop.global_position + Vector3(-1.6, 0, 0), 0.0, 2.2, 0.3)
	await _shot("sweep_display.png")
	# The giant inflatables and a station.
	var soda := sweep.bonuses.get_node("GiantSoda") as Node3D
	await _look(soda.global_position + Vector3(3.0, 0, 2.0), PI * 0.8, 3.0, 0.3)
	await _shot("sweep_inflatable.png")
	var deli := sweep.stations.get_node("DeliCounter") as Node3D
	main.cam_yaw = 0.35
	await _look(deli.global_position + Vector3(-1.2, 0, 0), 0.0, 4.5, 0.35)
	await _shot("sweep_station.png")
	# Overhead plan.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 32.0
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 30, 0))
	cam.far = 60.0
	cam.current = true
	var ceiling := main.get_node("Building/Model")
	ceiling.visible = false
	for l in main.get_node("Lights").get_children():
		l.visible = false
	var layers := root.find_children("*", "CanvasLayer", true, false)
	for l in layers:
		l.visible = false
	await _frames(10)
	await _shot("sweep_plan.png")
	for l in layers:
		l.visible = true
	ceiling.visible = true
	cam.queue_free()
	main.camera.current = true
	# The results.
	main.cam_yaw = 0.0
	sweep.shoppers[0].bonus_cents = 15000
	sweep._end()
	sweep.shoppers[1].cents += 3127
	sweep._show_results()
	await _frames(10)
	await _shot("sweep_results.png")
	quit()
