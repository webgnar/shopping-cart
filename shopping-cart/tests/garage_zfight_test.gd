extends SceneTree
## Scans the parking garage's box-shaped level pieces (decks, rails, walls, beams, paint) for z-fighting: two
## faces on the same plane, facing the same way and overlapping. Prop models are scanned when they're built
## (tools/blender/garage_models.py). Run from the Godot project folder:
##   godot --headless -s res://tests/garage_zfight_test.gd

func _initialize() -> void:
	var level: Node3D = load("res://scenes/levels/parking_garage.tscn").instantiate()
	root.add_child(level)
	_run.call_deferred(level)


func _faces(mi: MeshInstance3D) -> Array:
	var size: Vector3 = (mi.mesh as BoxMesh).size
	var xf := mi.global_transform
	var out := []
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = xf.basis[axis].normalized() * sgn
			var c: Vector3 = xf.origin + xf.basis[axis] * size[axis] / 2.0 * sgn
			var u_ax := (axis + 1) % 3
			var v_ax := (axis + 2) % 3
			var u := xf.basis[u_ax].normalized()
			var v := xf.basis[v_ax].normalized()
			out.append({"n": n, "c": c, "u": u, "v": v, "hu": size[u_ax] / 2.0, "hv": size[v_ax] / 2.0})
	return out


## Centre of the overlap of b over a, or null if they overlap less than 1 cm either way.
func _overlap(a: Dictionary, b: Dictionary) -> Variant:
	# b's centre and extents measured along a's in-plane axes (rotation about the normal is handled loosely).
	var d: Vector3 = b.c - a.c
	var bu: float = absf(b.u.dot(a.u)) * b.hu + absf(b.v.dot(a.u)) * b.hv
	var bv: float = absf(b.u.dot(a.v)) * b.hu + absf(b.v.dot(a.v)) * b.hv
	var du := d.dot(a.u)
	var dv := d.dot(a.v)
	var u0 := maxf(-a.hu, du - bu)
	var u1 := minf(a.hu, du + bu)
	var v0 := maxf(-a.hv, dv - bv)
	var v1 := minf(a.hv, dv + bv)
	if u1 - u0 < 0.01 or v1 - v0 < 0.01:
		return null
	return a.c + a.u * (u0 + u1) / 2.0 + a.v * (v0 + v1) / 2.0


## True if p is inside some other box, i.e. the flush faces there are buried and never seen.
func _buried(p: Vector3, items: Array, skip: Array) -> bool:
	for it in items:
		if it[0] in skip:
			continue
		var mi: MeshInstance3D = it[0]
		var local := mi.global_transform.affine_inverse() * p
		var h: Vector3 = (mi.mesh as BoxMesh).size / 2.0
		if absf(local.x) < h.x and absf(local.y) < h.y and absf(local.z) < h.z:
			return true
	return false


func _run(level: Node3D) -> void:
	var items := []
	for mi in level.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is BoxMesh:
			items.append([mi, _faces(mi)])
	var hits := 0
	for i in items.size():
		for j in range(i + 1, items.size()):
			for fa in items[i][1]:
				for fb in items[j][1]:
					if fa.n.dot(fb.n) < 0.9999 or absf((fb.c - fa.c).dot(fa.n)) > 0.0005:
						continue
					if fa.n.y < -0.99 and absf(fa.c.y) < 0.001:
						continue   # both stand on the street: those faces are pressed into the ground, never seen
					var at: Variant = _overlap(fa, fb)
					if at != null and not _buried(at + fa.n * 0.005, items, [items[i][0], items[j][0]]):
						hits += 1
						if hits <= 60:
							print("FLUSH  %s  <->  %s   normal %s at %s / %s" % [level.get_path_to(items[i][0]), level.get_path_to(items[j][0]), fa.n.snapped(Vector3.ONE * 0.01), fa.c.snapped(Vector3.ONE * 0.01), fb.c.snapped(Vector3.ONE * 0.01)])
	print("%d box pieces scanned" % items.size())
	print("RESULT: %s (%d flush overlapping faces)" % ["ALL PASS" if hits == 0 else "FAILURES", hits])
	quit(1 if hits else 0)
