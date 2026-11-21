extends SceneTree
## Renders the garage race: the count on the roof grid, the finish line at the exit, and the results. Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/race_screenshot.gd -- <out dir>

var main: Node3D


func _initialize() -> void:
	Race.start_on_load = true
	main = load("res://scenes/levels/parking_garage.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var path := dir.path_join(name)
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", path)


func _run() -> void:
	var race := get_first_node_in_group("race") as Race
	await _frames(5)
	# Looking over the grid from behind and above, partway through the count.
	main.cam_dist = 7.0
	main.cam_pitch = 0.45
	while race.clock > 1.6:
		await physics_frame
	await _shot("race_countdown.png")
	# The finish line at the street exit, seen from the bottom of floor 1.
	while race.phase != Race.Phase.RACING:
		await physics_frame
	main.spawn_cart(Vector3(race.finish.global_position.x - 7.0, 0.0, -3.0), 0.0)
	main.cam_dist = 4.5
	main.cam_pitch = 0.35
	await _frames(40)
	await _shot("race_finish_line.png")
	# The results.
	race.racers[0].time = 131.42
	race.racers[2].time = 178.9
	race.racers[1].time = 195.36
	race._end()
	await _frames(10)
	await _shot("race_results.png")
	quit()
