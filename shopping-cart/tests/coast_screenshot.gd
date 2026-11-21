extends SceneTree
## Renders the coast highway level from a few viewpoints. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/coast_screenshot.gd -- <output_prefix>

var main: Node3D
var lane: PackedVector3Array   # the downhill lane, a point every 4 m from 2 m


func _initialize() -> void:
	main = load("res://scenes/levels/coast_highway.tscn").instantiate()
	root.add_child(main)
	lane = (main.get_node("Traffic/Downhill") as Path3D).curve.get_baked_points()
	_run.call_deferred()


## A point on the road `s` m from the top, `t` m right of the downhill lane, `h` m up.
func road(s: float, t := 0.0, h := 0.0) -> Vector3:
	var c := (main.get_node("Traffic/Downhill") as Path3D).curve
	var p := c.sample_baked(s)
	var dir := (c.sample_baked(s + 2.0) - c.sample_baked(maxf(0.0, s - 2.0))).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	return p + right * t + Vector3.UP * h


func _shot(name: String) -> void:
	for i in 30:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://coast"
	var out := "%s_%s.png" % [prefix, name]
	root.get_texture().get_image().save_png(out)
	print("SCREENSHOT ", out)


func _look(from: Vector3, at: Vector3) -> void:
	main.camera.global_position = from
	main.camera.look_at(at)


func _run() -> void:
	for i in 60:
		await process_frame
	await _shot("spawn")   # the game camera behind the cart at the top
	main.set_process(false)   # take over the camera
	_look(road(260, 2.5, 1.6), road(330, 0, 0))
	await _shot("road")             # on the shoulder, looking down the road
	_look(road(470, 6.0, 1.4), road(400, -2, 4))
	await _shot("guardrail")        # looking back up along the guardrail
	_look(road(560, 70, 30), road(560, -20, 5))
	await _shot("from_the_sea")     # the road on the cliff seen from over the water
	_look(road(70, 3, 2.5), road(0, 0, 4))
	await _shot("top_tunnel")       # looking back up at the top tunnel
	_look(road(1380, 2, 2.0), road(1460, 0, 4))
	await _shot("bottom_tunnel")
	_look(road(700, 260, 160), road(750, -60, -20))
	await _shot("overview")
	quit()
