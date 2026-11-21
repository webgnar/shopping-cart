extends SceneTree
## Headless check that the follow camera never ends up inside level geometry. In every level the cart
## is parked at spots next to walls, shelves, cars, pillars and under the garage's low ceilings, and the
## camera is orbited all the way round at several zooms and pitches. Each frame a small sphere at the
## camera must touch nothing. The same sweep is run with collision avoidance off to show what it fixes,
## and the time the camera's collision checks take is reported. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/camera_test.gd

## [level scene, [[cart position, heading], ...]]
const LEVELS := [
	["res://scenes/main.tscn", [[Vector3(0, 0, 0), 0.0], [Vector3(0, 0, 6.28), 0.0], [Vector3(0, 0, 7.55), 0.0], [Vector3(27, 0, 0), 0.0], [Vector3(32.2, 0, 6.5), -PI / 2]]],
	["res://scenes/levels/parking_lot.tscn", [[Vector3(-12, 0, -9.5), 0.0], [Vector3(-14.85, 0, -4.2), -PI / 2], [Vector3(-1.3, 0, -9.5), -PI / 2]]],
	["res://scenes/levels/supermarket.tscn", [[Vector3(-14, 0, 0), 0.0], [Vector3(-1.5, 0, 0), 0.0], [Vector3(9.5, 0, -11.2), PI], [Vector3(-9.0, 0, 0.0), PI]]],
	["res://scenes/levels/sf_hill.tscn", [[Vector3(48, 47.8, 1.9), 0.0], [Vector3(4, 47.8, -4), PI], [Vector3(420, 0, 1.5), 0.0], [Vector3(442, 0, -1.5), 0.0]]],
	["res://scenes/levels/parking_garage.tscn", [[Vector3(5, 16, -3), 0.0], [Vector3(13, 12.75, -3), 0.0], [Vector3(55, 4.75, -3), 0.0], [Vector3(83, 3.15, -14.4), PI], [Vector3(55, 1.55, -3), 0.0]]],
]
## [cam_dist, cam_pitch] pairs swept at every spot.
const VIEWS := [[3.2, 0.38], [9.0, 0.38], [9.0, 0.05], [5.0, 1.2], [1.4, 0.2]]
const YAWS := 16
const FRAMES_PER_YAW := 8
## Smaller than the camera's probe sphere, so it only fails when the camera is really inside something.
const CLIP_RADIUS := 0.12

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var all_costs: Array[int] = []
	for level in LEVELS:
		var off := await _sweep(level[0], level[1], false, [])
		var costs: Array[int] = []
		var on := await _sweep(level[0], level[1], true, costs)
		all_costs.append_array(costs)
		costs.sort()
		var avg := 0.0
		for c in costs:
			avg += c
		avg /= maxf(1, costs.size())
		print("%s: clipping frames %d -> %d of %d, lifted on %d frames, camera checks avg %.1f us, p99 %d us, max %d us, max casts %d" % [
			level[0].get_file(), off.clipped, on.clipped, on.frames, on.lifted, avg,
			costs[int(costs.size() * 0.99)], costs[-1], on.max_casts])
		_check(on.clipped == 0, "%s: camera never inside geometry (%d frames clipped)" % [level[0].get_file(), on.clipped])
		_check(off.clipped > 0, "%s: the sweep reaches geometry with avoidance off (%d frames)" % [level[0].get_file(), off.clipped])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)


func _sweep(path: String, spots: Array, avoid: bool, costs: Array[int]) -> Dictionary:
	var main: Node3D = load(path).instantiate()
	root.add_child(main)
	await process_frame
	var cam: CartCamera = main.camera
	cam.avoid_collisions = avoid
	var space := cam.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = CLIP_RADIUS
	probe.shape = ball
	probe.collision_mask = 1
	var r := {"frames": 0, "clipped": 0, "lifted": 0, "max_casts": 0}
	for spot in spots:
		main.spawn_cart(spot[0], spot[1])
		for i in 30:
			await process_frame
		for view in VIEWS:
			main.cam_dist = view[0]
			main.cam_pitch = view[1]
			for y in YAWS:
				main.cam_yaw = TAU * y / YAWS
				for f in FRAMES_PER_YAW:
					await process_frame
					r.frames += 1
					probe.transform = Transform3D(Basis.IDENTITY, cam.global_position)
					if not space.intersect_shape(probe, 1).is_empty():
						r.clipped += 1
					if avoid:
						costs.append(cam.last_cost_usec)
						r.max_casts = maxi(r.max_casts, cam.last_casts)
						if cam._lift > 0.05:
							r.lifted += 1
	main.queue_free()
	await process_frame
	return r


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1
