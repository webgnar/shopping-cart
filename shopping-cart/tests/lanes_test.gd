extends SceneTree
## The sandbox's measurement lanes (scenes/sandbox/measurement_lanes.tscn, in scenes/main.tscn) measure what their
## labels say:
##  - each slope rises at its angle, holds a level top and comes back down,
##  - each curb and bump stands at its height,
##  - the coast and braking lanes are flat from start to end,
##  - every Start marker faces +X on clear ground, and L (main._next_lane) puts a cart there that stands on 4 wheels.
##   godot --headless --fixed-fps 120 -s res://tests/lanes_test.gd

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


## Height of whatever is under (x, z), ignoring the cart.
func _floor(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 5, z), Vector3(x, -1, z), 1)
	q.exclude = main.cart._own_rids
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -INF


func _run() -> void:
	for i in 4:
		await physics_frame
	var lanes: Node3D = main.get_node("MeasurementLanes")
	# Slopes: the grade halfway up and down, and the top's height.
	for deg in [2, 5, 10]:
		var s: Node3D = lanes.get_node("Slopes/Slope%d" % deg)
		var x0 := s.global_position.x
		var z := s.global_position.z
		var grade := tan(deg_to_rad(deg))
		var up := (_floor(x0 + 3.5, z) - _floor(x0 + 2.5, z))
		var down := (_floor(x0 + 11.5, z) - _floor(x0 + 12.5, z))
		var top := _floor(x0 + 7.5, z)
		_check(absf(up - grade) < 0.002 and absf(down - grade) < 0.002,
			"%d° slope: rises %.4f and falls %.4f per metre (tan = %.4f)" % [deg, up, down, grade])
		_check(absf(top - 6.0 * grade) < 0.003, "%d° slope: top %.3f m (6 m run)" % [deg, top])
	for c in lanes.get_node("Steps").get_children():
		if c is StaticBody3D:
			var cm := float(c.name.trim_prefix("Curb").trim_suffix("cm").replace("_", "."))
			var h := _floor(c.global_position.x, c.global_position.z)
			_check(absf(h - cm / 100.0) < 0.001, "curb %s: %.1f cm high" % [c.name, h * 100.0])
	for c in lanes.get_node("Bumps").get_children():
		if c is StaticBody3D:
			var cm := float(c.name.trim_prefix("Bump").trim_suffix("cm"))
			var h := _floor(c.global_position.x, c.global_position.z)
			_check(absf(h - cm / 100.0) < 0.001, "bump %s: %.1f cm high" % [c.name, h * 100.0])
	for lane in ["CoastLane", "BrakeLane"]:
		var n: Node3D = lanes.get_node(lane)
		var worst := 0.0
		for d in range(0, 81):
			worst = maxf(worst, absf(_floor(-20.0 + d, n.global_position.z)))
		_check(worst < 0.001, "%s: flat over 80 m (worst %.4f m)" % [lane, worst])
	var starts: Array[Node] = lanes.find_children("Start", "Marker3D", true, false)
	_check(starts.size() == 8, "8 Start markers (%d)" % starts.size())
	for m in starts:
		var p: Vector3 = (m as Node3D).global_position
		var flat := true
		for dx in [0.0, 0.5, 1.0, 1.5]:
			for dz in [-0.4, 0.0, 0.4]:
				flat = flat and absf(_floor(p.x + dx, p.z + dz)) < 0.001
		_check(flat and absf((m as Node3D).global_rotation.y) < 0.001,
			"%s start at (%.1f, %.1f): faces +X on clear flat ground" % [m.get_parent().name, p.x, p.z])
	for m in starts:
		main._next_lane()
		for i in 120:
			await physics_frame
		var at: Vector3 = main.cart.cart_origin()
		var want: Vector3 = (m as Node3D).global_position
		_check(main.cart.wheels_down() == 4 and Vector2(at.x - want.x, at.z - want.z).length() < 0.1,
			"L puts the cart at %s and it stands (%d wheels down, %.2f m off)" % [m.get_parent().name,
				main.cart.wheels_down(), Vector2(at.x - want.x, at.z - want.z).length()])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
