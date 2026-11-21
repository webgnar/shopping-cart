extends SceneTree
## Headless checks for the San Francisco hill level. Run from the Godot project folder:
##   godot --headless --fixed-fps 120 -s res://tests/sf_hill_test.gd

var main: Node3D
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/levels/sf_hill.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-28s %s" % ["PASS" if ok else "FAIL", name, detail])


## World-space box of a node's first CollisionShape3D child that is a box (the props are only turned in
## quarter turns, so an axis-aligned box is exact enough).
func _box(n: Node3D, shape_name: String) -> AABB:
	var s := n.get_node(shape_name) as CollisionShape3D
	var half: Vector3 = (s.shape as BoxShape3D).size * 0.5
	var xf := s.global_transform
	var box := AABB(xf.origin, Vector3.ZERO)
	for c in 8:
		box = box.expand(xf * Vector3(half.x * (1 if c & 1 else -1), half.y * (1 if c & 2 else -1), half.z * (1 if c & 4 else -1)))
	return box


func _run() -> void:
	await _wait(1.0)
	var lanes: Array = main.get_node("CrossTraffic").get_children()
	var cars := get_nodes_in_group("traffic_car")
	var houses := get_nodes_in_group("sf_house")
	_check("props present", houses.size() == 203 and get_nodes_in_group("sf_lamp").size() == 12
		and get_nodes_in_group("sf_tree").size() == 48 and get_nodes_in_group("sf_stop_sign").size() == 10
		and get_nodes_in_group("sf_hydrant").size() == 6 and lanes.size() == 10 and cars.size() == 38,
		"%d houses, %d lamps, %d trees, %d stop signs, %d hydrants, %d traffic lanes, %d cars" % [houses.size(),
		get_nodes_in_group("sf_lamp").size(), get_nodes_in_group("sf_tree").size(),
		get_nodes_in_group("sf_stop_sign").size(), get_nodes_in_group("sf_hydrant").size(), lanes.size(), cars.size()])

	# No two houses stand inside each other (1 cm of touching allowed), and none stands in the street.
	var overlaps := 0
	var in_street := 0
	var boxes: Array[AABB] = []
	for h in houses:
		boxes.append(_box(h, "HouseShape"))
	for i in boxes.size():
		var b := boxes[i]
		if b.position.z < 9.0 - 0.01 and b.end.z > -9.0 + 0.01 and b.position.x > 0.0:
			in_street += 1
		for j in range(i + 1, boxes.size()):
			var o := b.intersection(boxes[j])
			if o.size.x > 0.01 and o.size.z > 0.01 and o.size.y > 0.01:
				overlaps += 1
	_check("houses clear of each other", overlaps == 0 and in_street == 0,
		"%d overlapping pairs, %d in the street" % [overlaps, in_street])

	# The cart starts on the CartSpawn marker on the flat top block, settled on four wheels and pinned.
	var spawn: Vector3 = main.get_node("CartSpawn").global_position
	var cart: ShoppingCart = main.cart
	var at := cart.cart_origin()
	_check("spawns on marker", at.distance_to(spawn) < 0.1 and cart.wheels_down() == 4 and cart.frame.freeze,
		"at (%.2f, %.2f, %.2f), wheels down %d, pinned %s" % [at.x, at.y, at.z, cart.wheels_down(), cart.frame.freeze])

	# Left alone at the top of each hill the cart rolls away downhill on its four wheels.
	for hill in [["FirstHill", 0.10], ["FourthHill", 0.31]]:
		var block: Node3D = main.get_node("Street/" + hill[0])
		main.spawn_cart(main.floor_under(block.global_transform * Vector3(3, 0, 1.9)), 0.0)
		cart = main.cart
		var p0 := cart.cart_origin()
		await _wait(3.0)
		var p1 := cart.cart_origin()
		var v := cart.frame.linear_velocity
		_check("rolls down " + hill[0], v.x > 1.0 and p1.y < p0.y - 0.5 and cart.wheels_down() >= 3 and not cart.frame.freeze,
			"%.0f%% grade: after 3 s %.2f m/s downhill, %.1f m lower, wheels down %d" % [hill[1] * 100, v.x, p0.y - p1.y,
			cart.wheels_down()])

	# R on a slope: a fresh cart on the hill under you, not inside it.
	var steep: Node3D = main.get_node("Street/ThirdHill")
	var p := steep.global_transform * Vector3(30, 0, -1.9)
	main.spawn_cart(main.floor_under(p), PI)   # facing uphill, the worst case for the front wheels
	cart = main.cart
	await _wait(0.5)
	var up := cart.frame.global_basis.y.y
	_check("R respawns on a slope", cart.wheels_down() >= 3 and up > 0.9 and absf(cart.cart_origin().y - p.y) < 0.5,
		"wheels down %d, upright %.2f, %.2f m off the road" % [cart.wheels_down(), up, cart.cart_origin().y - p.y])

	# Cross traffic drives along its lane at the lane's speed and comes back round at the end.
	var lane: Node3D = lanes[0]
	var car: Node3D = lane.get_child(0)
	var z0 := car.global_position.z
	await _wait(1.0)
	var moved := absf(car.global_position.z - z0)
	_check("cross traffic drives", absf(moved - lane.speed) < 0.3 or moved > lane.length - 20.0,
		"%s moved %.2f m in 1 s (speed %.1f m/s)" % [car.name, moved, lane.speed])
	var looped := 0
	for i in lane.get_child_count():
		var d: float = lane.distance(i, lane.clock)
		if d >= 0.0 and d < lane.length:
			looped += 1
	_check("traffic stays on its lane", looped == lane.get_child_count(), "%d of %d cars within the lane" % [
		looped, lane.get_child_count()])

	# A car crossing knocks a cart standing in its lane (even a pinned one).
	var cross: Node3D = main.get_node("Street/Crossing1")
	var lane_x: float = lane.global_position.x
	var ahead := INF
	for i in lane.get_child_count():   # the next car to reach z = 0, and when
		var c: Node3D = lane.get_child(i)
		var dist: float = c.global_position.z * (-1.0 if lane.global_basis.z.z > 0 else 1.0)
		ahead = minf(ahead, -dist if -dist > 6.0 else INF)
	main.spawn_cart(Vector3(lane_x - 0.5, cross.global_position.y + 0.02, 0), PI / 2)
	cart = main.cart
	var start := cart.cart_origin()
	var hit := false
	for t in 30:
		await _wait(0.5)
		if cart.cart_origin().distance_to(start) > 1.0:
			hit = true
			break
	_check("traffic knocks the cart", hit, "cart moved %.1f m (next car was %.0f m off at %.1f m/s)" % [
		cart.cart_origin().distance_to(start), ahead, lane.speed])
	print("RESULT: %s (%d failing)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	quit(1 if failures else 0)
