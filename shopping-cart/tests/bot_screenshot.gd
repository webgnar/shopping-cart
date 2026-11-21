extends SceneTree
## Renders a level after its bot carts have been driving for a while, from above and behind the player's cart.
##   xvfb-run godot -s res://tests/bot_screenshot.gd -- <level.tscn> <seconds> <out.png>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var level: Node3D = (load(args[0]) as PackedScene).instantiate()
	root.add_child(level)
	for i in int(float(args[1]) * Engine.physics_ticks_per_second):
		await physics_frame
	level.cam_pitch = 0.6
	level.cam_dist = 7.0
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(args[2])
	print("SCREENSHOT ", args[2])
	quit()
