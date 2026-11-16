extends SceneTree
## CPU cost of each level without rendering: wall time per frame (one 120 Hz physics step plus scripts)
## while the cart is pushed, and how many rigid bodies and lights the level has. For GPU-side numbers see
## tests/perf_render.gd.
##   godot --headless --fixed-fps 120 -s res://tests/perf_probe.gd [-- <scene> ...]

const LEVELS := ["res://scenes/main.tscn", "res://scenes/levels/parking_garage.tscn",
	"res://scenes/levels/parking_lot.tscn", "res://scenes/levels/supermarket.tscn"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var levels: Array = args if args.size() > 0 else LEVELS
	for path in levels:
		var main: Node3D = load(path).instantiate()
		root.add_child(main)
		for i in 240:
			await physics_frame
		Input.action_press("push_left")
		Input.action_press("push_right")
		var n := 360
		var t0 := Time.get_ticks_usec()
		for i in n:
			await process_frame
		var wall := (Time.get_ticks_usec() - t0) / 1000.0 / n
		Input.action_release("push_left")
		Input.action_release("push_right")
		var bodies := main.find_children("*", "RigidBody3D", true, false).size()
		var lights := main.find_children("*", "Light3D", true, false)
		var shadowed := lights.filter(func(l): return l.shadow_enabled).size()
		print("%-26s %5.2f ms per frame  rigid bodies %3d  lights %3d (%d with shadows)" % [
			path.get_file(), wall, bodies, lights.size(), shadowed])
		root.remove_child(main)
		main.free()
		await process_frame
	quit()
