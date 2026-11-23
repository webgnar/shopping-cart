extends SceneTree
## Checks the Type C curb (scenes/curb/curb.tscn) against its drawing: the profile's sizes, a straight run's
## mesh, and that the collision is where the drawing says on the top, the face and around a rounded island.
##   godot --headless -s res://tests/curb_test.gd

const CURB := preload("res://scenes/curb/curb.tscn")
const IN := 0.0254
const TOL := 0.0015

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_profile()
	var world := Node3D.new()
	root.add_child(world)

	# A straight 4 m run along +X: the street is on its right, +Z.
	var straight: Curb = CURB.instantiate()
	straight.curve = Curb.curve_through(PackedVector3Array([Vector3.ZERO, Vector3(4, 0, 0)]))
	world.add_child(straight)
	var box := straight.mesh_instance.get_aabb()
	_near("straight length", box.size.x, 4.0)
	_near("straight base width (6 3/4\")", box.size.z, 6.75 * IN)
	_near("straight back height (6 1/4\")", box.size.y, 6.25 * IN, 0.002)
	_near("back face at z = -6\"", box.position.z, -6.0 * IN)

	# A rounded island, 2 x 5 m, wound clockwise seen from above so the street (right side) faces out.
	var island: Curb = CURB.instantiate()
	island.position = Vector3(0, 0, 4)
	island.curve = Curb.curve_through(PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, -2),
			Vector3(0, 0, -2)]), 0.8, true)
	world.add_child(island)
	await physics_frame
	await physics_frame

	var space := world.get_world_3d().direct_space_state
	# Top: 3" behind the curb line it is half way up the 1/4" rise.
	_near("top 3\" back", _down(space, Vector3(2, 0, -3.0 * IN)), 6.125 * IN, 0.002)
	_near("top at back edge (1\" in)", _down(space, Vector3(2, 0, -5.0 * IN)), (6.0 + 0.25 * 5.0 / 6.0) * IN, 0.002)
	# Face: 3" up it has leant back 3/8" from the base.
	_near("face 3\" up", _side(space, Vector3(2, 3.0 * IN, 1.0), Vector3(0, 0, -1)), 0.375 * IN)
	_near("face 1\" up", _side(space, Vector3(2, 1.0 * IN, 1.0), Vector3(0, 0, -1)), 0.625 * IN)
	# The front fillet is lower than a sharp corner would be.
	var nose := _down(space, Vector3(2, 0, -0.1 * IN))
	_check("front corner rounded", nose < 5.9 * IN and nose > 5.0 * IN, "%.4f" % nose)
	# Open ends are capped.
	_near("start cap", _side(space, Vector3(-1, 3.0 * IN, -3.0 * IN), Vector3(1, 0, 0)), 0.0)

	# Island: the face is on the outside all round, including on a rounded corner.
	_near("island long side", _side(space, Vector3(2.5, 3.0 * IN, 5.5), Vector3(0, 0, -1)), 4.0 + 0.375 * IN)
	_near("island short side", _side(space, Vector3(6.5, 3.0 * IN, 3.0), Vector3(-1, 0, 0)), 5.0 + 0.375 * IN)
	var diag := Vector3(1, 0, 1).normalized()
	var corner := Vector3(5 - 0.8, 0, 4 - 0.8) + diag * 0.8   # where the arc crosses the diagonal
	var hit := _side_hit(space, corner + diag * 1.0 + Vector3(0, 3.0 * IN, 0), -diag)
	_near("island corner face", (Vector3(hit.x, 0, hit.z) - corner).dot(diag), 0.375 * IN, 0.004)
	_check("island back face and top", _side_hit(space, Vector3(2.5, 3.0 * IN, 3.0), Vector3(0, 0, 1)) != Vector3.INF
			and _down(space, Vector3(2.5, 0, 4.0 - 3.0 * IN)) > 6.0 * IN, "")

	print("curb_test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check_profile() -> void:
	var p := Curb.profile()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in p:
		lo = lo.min(q)
		hi = hi.max(q)
	_near("profile back", lo.x, -6.0 * IN)
	_near("profile toe", hi.x, 0.75 * IN)
	_near("profile base", lo.y, 0.0)
	_check("profile top under 6 1/4\"", hi.y <= 6.25 * IN + 0.0001 and hi.y > 6.2 * IN, "%.4f" % hi.y)
	_check("profile is counter-clockwise", not Geometry2D.is_polygon_clockwise(p), "")


func _down(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP, at - Vector3.UP * 0.01))
	return r.position.y if r else -1.0


func _side_hit(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> Vector3:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 2.0))
	return r.position if r else Vector3.INF


## How far along -dir from the ray's start, measured on the axis of dir, the hit is (its x or z coordinate).
func _side(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> float:
	var h := _side_hit(space, from, dir)
	return h.z if absf(dir.z) > 0.5 else h.x


func _near(what: String, got: float, want: float, tol := TOL) -> void:
	_check(what, absf(got - want) <= tol, "got %.4f want %.4f" % [got, want])


func _check(what: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", what, detail])
