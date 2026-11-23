extends SceneTree
## Renders Cart Ball: the kickoff count from behind your cart, the arena from above, a goal, and full time.
## Needs a display:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/cart_ball_screenshot.gd -- <out dir>

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/levels/cart_ball_arena.tscn").instantiate()
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


## A fixed camera looking from `from` at `at` (the follow camera is parked meanwhile).
func _look(from: Vector3, at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.look_at_from_position(from, at)
	cam.current = true
	main.set_process(false)
	return cam


func _run() -> void:
	var game := get_first_node_in_group("cart_ball") as CartBall
	await _frames(5)
	main.cam_dist = 5.0
	main.cam_pitch = 0.3
	await _frames(15)
	await _shot("cart_ball_kickoff.png")
	var cam := _look(Vector3(-24, 17, 17), Vector3(0, 0, 0))
	await _shot("cart_ball_arena.png")
	cam.look_at_from_position(Vector3(7, 3.2, 4.5), Vector3(15, 1, 0))
	while game.phase != CartBall.Phase.PLAYING:
		await physics_frame
	game.ball.global_position = Vector3(13.2, 0.66, 0.6)
	game.ball.linear_velocity = Vector3(4, 0, 0)
	while game.phase == CartBall.Phase.PLAYING:
		await physics_frame
	await _frames(20)
	await _shot("cart_ball_goal.png")
	game.clock = 0.0
	while game.phase != CartBall.Phase.PLAYING:
		await physics_frame
	await _frames(5)
	cam.queue_free()
	main.set_process(true)
	await _frames(30)
	await _shot("cart_ball_full_time.png")
	quit()
