extends SceneTree
## The endless sandbox (scenes/main.tscn, ChunkStreamer on its Chunks node):
##  - chunks load around the cart and never in the hand-built home squares,
##  - after the cart jumps far away, the squares around it are all there and the old ones are gone,
##  - no holes: the ground under a grid of points around the cart is always found,
##  - every chunk is flat at height 0 along its edges (so any two meet flush),
##  - each kind of chunk has the floor (and rolling sound) it should,
##  - the cart can be pushed over the hill street's crest and rolls back down the other side (when the sandbox
##    has a hill chunk).
##   godot --headless --fixed-fps 120 -s res://tests/sandbox_test.gd

var main: Node3D
var streamer: ChunkStreamer
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	streamer = main.get_node("Chunks")
	_run.call_deferred()


func _wait(seconds: float) -> void:
	for i in maxi(1, int(seconds * Engine.physics_ticks_per_second)):
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %s" % ["PASS" if ok else "FAIL", what])


## World transform of the chunk in `cell` (where it is or would be).
func _cell_xf(cell: Vector2i) -> Transform3D:
	return streamer.global_transform * streamer.cell_transform(cell, streamer.pick(cell)[1])


## The nearest square (to the origin, outside home) that gets chunk `idx`.
func _find_cell(idx: int, skip := 0) -> Vector2i:
	for r in range(1, 30):
		for i in range(-r, r + 1):
			for j in range(-r, r + 1):
				if maxi(absi(i), absi(j)) != r:
					continue
				var c := Vector2i(i, j)
				if not streamer.home_cells.has(c) and streamer.pick(c)[0] == idx:
					if skip == 0:
						return c
					skip -= 1
	return Vector2i(999, 999)


func _ray_down(p: Vector3, from_h := 20.0) -> Dictionary:
	var space := main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + from_h, p.z), Vector3(p.x, p.y - 5.0, p.z))
	q.collision_mask = 1
	q.exclude = main.cart.find_children("*", "CollisionObject3D", true, false).map(func(n): return n.get_rid()) + [main.cart.frame.get_rid()]
	return space.intersect_ray(q)


func _teleport(at: Vector3, yaw := 0.0) -> void:
	main.spawn_cart(at, yaw)
	await process_frame
	await process_frame
	await physics_frame


func _run() -> void:
	await _wait(0.3)
	var max_loaded := 0

	# Around the start.
	var home_hit := streamer.loaded.keys().filter(func(c): return streamer.home_cells.has(c))
	_check(streamer.loaded.size() >= 8 and home_hit.is_empty(),
		"start: %d chunks loaded around the cart, none in the home squares" % streamer.loaded.size())

	# Jumps: everything near is there, nothing far is kept, no holes under a 2 m grid within 40 m.
	var kinds := {}
	for at in [Vector3(300, 0, 260), Vector3(-1250, 0, 3400), Vector3(-90, 0, -80), Vector3(2, 0, 0)]:
		var cell := Vector2i(floori((at.x - streamer.global_position.x) / streamer.chunk_size),
			floori((at.z - streamer.global_position.z) / streamer.chunk_size))
		var ground: Vector3 = at
		if not streamer.home_cells.has(cell):
			# Land on the flat apron of the chunk, just inside its corner.
			ground = _cell_xf(cell) * Vector3(-18.5, 0, -18.5)
		await _teleport(ground + Vector3(0, 0.05, 0))
		max_loaded = maxi(max_loaded, streamer.loaded.size())
		var far := 0
		for c in streamer.loaded:
			kinds[streamer.pick(c)[0]] = true
			if streamer._distance(ground - streamer.global_position, c) > streamer.unload_distance:
				far += 1
		var holes := []
		for x in range(-40, 41, 2):
			for z in range(-40, 41, 2):
				var p: Vector3 = ground + Vector3(x + 0.13, 0, z + 0.13)
				var hit := _ray_down(p)
				if hit.is_empty() or hit.position.y < -0.05 or hit.position.y > 12.0:
					holes.append(Vector2(p.x, p.z))
		_check(far == 0 and holes.is_empty() and streamer.loaded.has(cell) == not streamer.home_cells.has(cell),
			"jump to (%d, %d): %d chunks loaded, %d too far, holes %s" % [ground.x, ground.z, streamer.loaded.size(), far,
			str(holes.slice(0, 4)) if holes else "none"])
	var orphans := streamer.get_children().filter(func(n): return n.name.begins_with("Chunk_")).size() - streamer.loaded.size()
	# The most squares that can be within unload_distance of the cart (a circle of that radius, plus a square's
	# half diagonal): 27 for 88 m, 44 for the sandbox's 120 m.
	var limit := ceili(PI * pow(streamer.unload_distance / streamer.chunk_size + 0.71, 2))
	_check(max_loaded <= limit and orphans >= 0 and kinds.size() == streamer.chunks.size(),
		"at most %d chunks at once (limit %d), every kind seen (%d of %d)" % [max_loaded, limit, kinds.size(), streamer.chunks.size()])

	# Edges: every chunk kind is flat at height 0 for the last 0.3 m along all four edges (at most 1 cm off).
	for idx in streamer.chunks.size():
		var cell := _find_cell(idx)
		var xf := _cell_xf(cell)
		await _teleport(xf * Vector3(0, 30, 0))   # cart up in the air, out of the way; chunks load around it
		var worst := 0.0
		var misses := 0
		var half := streamer.chunk_size / 2 - 0.3
		for t in range(-19, 20):
			for e in [Vector3(t, 0, -half), Vector3(t, 0, half), Vector3(-half, 0, t), Vector3(half, 0, t)]:
				var hit := _ray_down(xf * (e + Vector3(0.13, 0, 0.13)), 6.0)
				if hit.is_empty():
					misses += 1
				else:
					worst = maxf(worst, absf(hit.position.y))
		_check(misses == 0 and worst <= 0.01, "%s edges: flat at 0 (worst %.3f m off, %d misses)" % [
			streamer.chunks[idx].resource_path.get_file(), worst, misses])

	# Floors: a cart rolled across each kind of chunk's corner hears the right ground.
	var floors := {"open_lot.tscn": "Asphalt", "lot.tscn": "Asphalt", "street.tscn": "Concrete", "market.tscn": "Tile", "garage.tscn": "Concrete",
		"hill.tscn": "Asphalt"}
	for idx in streamer.chunks.size():
		var name: String = streamer.chunks[idx].resource_path.get_file()
		var xf := _cell_xf(_find_cell(idx, 1))
		await _teleport(xf * Vector3(-18.5, 0.05, -18.5), xf.basis.get_euler().y)
		await _wait(0.5)
		Input.action_press("push_left")
		Input.action_press("push_right")
		await _wait(1.0)
		var rs: CartRollingSound = main.cart.get_node("Frame/RollingSound")
		var heard: String = rs.surface.name if rs.surface else "nothing"
		Input.action_release("push_left")
		Input.action_release("push_right")
		_check(heard == floors.get(name, "?"), "%s: rolling on %s (want %s)" % [name, heard, floors.get(name, "?")])

	# The hill: start on the flat at the foot of the street, push up and over the crest.
	var hill_idx := -1
	for k in streamer.chunks.size():
		if streamer.chunks[k].resource_path.get_file() == "hill.tscn":
			hill_idx = k
	if hill_idx < 0:
		print("info  no hill chunk in this sandbox, hill check skipped")
		print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
		quit(1 if failures else 0)
		return
	var hxf := _cell_xf(_find_cell(hill_idx))
	var heading := (hxf.basis * Vector3.RIGHT)
	await _teleport(hxf * Vector3(-19, 0.05, -2), atan2(-heading.z, heading.x))
	await _wait(0.5)
	# Push like a player walking the cart up: both hands while it's slower than a walk, and one hand to keep it
	# pointing straight up the street (the casters let it swing round on the slope).
	var uphill := atan2(-heading.z, heading.x)
	var top := -1.0
	var crossed := false
	for i in int(30 * Engine.physics_ticks_per_second):
		var nose: Vector3 = main.cart.frame.global_basis.x
		var slow: bool = main.cart.frame.linear_velocity.dot(nose) < 1.3
		var off: float = wrapf(main.cart.heading() - uphill, -PI, PI)   # + = turned left of straight up
		var left := slow and off > -0.05 or off > 0.05    # the left hand pushing turns the cart right
		var right := slow and off < 0.05 or off < -0.05
		for k in [["push_left", left], ["push_right", right]]:
			if k[1]:
				Input.action_press(k[0])
			else:
				Input.action_release(k[0])
		await physics_frame
		var p: Vector3 = hxf.affine_inverse() * main.cart.cart_origin()
		top = maxf(top, p.y)
		if OS.has_environment("HILL_LOG") and i % 30 == 0:
			print("  t %.2f  x %.2f  y %.2f  dot %.2f  power %s" % [i / 120.0, p.x, p.y, main.cart.frame.linear_velocity.dot(main.cart.frame.global_basis.x), main.cart.hand_power])
		if p.x > 8:
			crossed = true
			break
	Input.action_release("push_left")
	Input.action_release("push_right")
	await _wait(3.0)
	var p_end: Vector3 = hxf.affine_inverse() * main.cart.cart_origin()
	var upright: bool = main.cart.frame.global_basis.y.y > 0.8
	_check(crossed and top > 2.3 and upright,
		"hill: pushed up to %.2f m (crest 2.6 m) and over (%s), rolled on to x = %.1f m, %s" % [
		top, "yes" if crossed else "no", p_end.x, "upright" if upright else "fallen over"])

	print("RESULT: %s" % ("ALL PASS" if failures == 0 else "FAILURES (%d)" % failures))
	quit(1 if failures else 0)
