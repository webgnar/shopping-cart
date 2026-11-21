extends SceneTree
## Headless checks for the coast highway level. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/coast_test.gd

var main: Node3D
var failures := 0
var lane: Curve3D   # the downhill lane's centre (Traffic/Downhill)


func _initialize() -> void:
	main = load("res://scenes/levels/coast_highway.tscn").instantiate()
	root.add_child(main)
	lane = (main.get_node("Traffic/Downhill") as Path3D).curve
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-30s %s" % ["PASS" if ok else "FAIL", name, detail])


## A point `t` m right of the downhill lane, `s` m along it, and the way down the road there.
func _road(s: float, t := 0.0) -> Array:
	var p := lane.sample_baked(s)
	var dir := (lane.sample_baked(s + 2.0) - lane.sample_baked(s - 2.0)).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	return [p + right * t, dir]


func _yaw(dir: Vector3) -> float:
	return atan2(-dir.z, dir.x)   # the cart's nose is +X


func _ray_down(p: Vector3, skip: Node = null) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0)
	var through: Array[RID] = []
	if main.cart:   # look through the cart and its groceries
		through.assign(main.cart.find_children("*", "CollisionObject3D", true, false).map(func(b): return b.get_rid()))
	if skip:
		through.append((skip as CollisionObject3D).get_rid())
	q.exclude = through
	return main.get_world_3d().direct_space_state.intersect_ray(q)


func _run() -> void:
	await _wait(1.0)
	var trees := 0
	var mmis := main.find_children("*", "MultiMeshInstance3D", true, false)
	for m in mmis:
		trees += (m as MultiMeshInstance3D).multimesh.instance_count
	var cars := get_nodes_in_group("traffic_car")
	_check("level built", main.get_node("Road").get_child_count() >= 13 and cars.size() == 24 and trees > 2000,
		"%d road nodes, %d cars, %d trees and shrubs in %d MultiMeshes" % [main.get_node("Road").get_child_count(),
		cars.size(), trees, mmis.size()])

	# The cart starts on the CartSpawn marker on the shoulder at the top, settled on four wheels.
	var spawn: Vector3 = main.get_node("CartSpawn").global_position
	var cart: ShoppingCart = main.cart
	var at := cart.cart_origin()
	_check("spawns on marker", at.distance_to(spawn) < 0.15 and cart.wheels_down() == 4,
		"at (%.1f, %.1f, %.1f), wheels down %d" % [at.x, at.y, at.z, cart.wheels_down()])

	# The road can be driven its whole length: the deck is under every lane point, and the shoulder.
	var holes := 0
	var s := 2.0
	while s < lane.get_baked_length() - 2.0:
		for t in [-3.6, 0.0, 3.0]:
			var hit := _ray_down(_road(s, t)[0])
			if not hit.is_empty() and hit.collider.is_in_group("traffic_car"):
				continue   # a car driving by
			if hit.is_empty() or absf(hit.position.y - _road(s, t)[0].y) > 0.1:
				if holes < 5:
					print("      no road at s %.0f, t %.1f: %s" % [s, t, hit.get("position", "nothing")])
				holes += 1
		s += 5.0
	_check("road surface everywhere", holes == 0, "%d points without road under them" % holes)

	# Left alone on the 10 % stretch the cart rolls away down the road, on its wheels and on the road.
	var r := _road(600.0, 2.8)
	main.spawn_cart(r[0], _yaw(r[1]))
	cart = main.cart
	var p0 := cart.cart_origin()
	await _wait(6.0)
	var v := cart.frame.linear_velocity
	var p1 := cart.cart_origin()
	var on_road := not _ray_down(p1).is_empty()
	_check("rolls down the 10% grade", v.length() > 3.0 and p0.y - p1.y > 1.0 and cart.wheels_down() >= 3 and on_road,
		"after 6 s %.1f m/s, %.1f m lower, wheels down %d, on the road %s" % [v.length(), p0.y - p1.y,
		cart.wheels_down(), on_road])

	# Rolling into the guardrail (aimed at it, across the shoulder) stops the cart going over the cliff.
	r = _road(800.0, 2.5)
	var into: Vector3 = (r[1] + r[1].cross(Vector3.UP).normalized() * 0.8).normalized()
	main.spawn_cart(r[0], _yaw(into))
	cart = main.cart
	await _wait(0.3)
	for b in cart.find_children("*", "RigidBody3D", true, false):
		(b as RigidBody3D).freeze = false
		(b as RigidBody3D).linear_velocity = into * 5.0
	await _wait(4.0)
	var lat: float = (cart.cart_origin() - _road(800.0)[0]).dot(r[1].cross(Vector3.UP).normalized())
	_check("guardrail holds", cart.cart_origin().y > r[0].y - 1.0 and lat < 4.5,
		"cart %.1f m right of the lane, %.1f m below the road" % [lat, r[0].y - cart.cart_origin().y])

	# Traffic drives along both lanes, on the road, at the route's speed.
	for name in ["Downhill", "Uphill"]:
		var route: TrafficRoute = main.get_node("Traffic/" + name)
		var car: Node3D = route.get_child(0)
		var d0 := route.distance(0, route.clock)
		await _wait(1.0)
		var d1 := route.distance(0, route.clock)
		var off := _ray_down(car.global_position, car)
		_check(name.to_lower() + " traffic drives", absf(fposmod(d1 - d0, route.length) - route.speed) < 0.2
			and not off.is_empty() and absf(off.position.y - car.global_position.y) < 0.2,
			"%s moved %.1f m in 1 s (%.0f m/s), %.2f m over the road" % [car.name, fposmod(d1 - d0, route.length),
			route.speed, car.global_position.y - (off.position.y if off else 0.0)])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
