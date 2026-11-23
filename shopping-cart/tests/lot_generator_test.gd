extends SceneTree
## Checks the parking lot generator (scenes/lot_gen/lot_generator.tscn) against the sizes it is built to: stall
## counts and spacing at each angle, stripes inside the lot, wheel stops in every stall but the corral ones,
## curbed islands only at double-row ends, and the heights of a wheel stop, an island curb and its fill.
##   godot --headless -s res://tests/lot_generator_test.gd

const GEN := preload("res://scenes/lot_gen/lot_generator.tscn")
const FT := 0.3048

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for angle in [90, 60, 45, 30]:
		for two_way in [true, false]:
			await _check_layout(angle, two_way)
	await _check_collision()
	_check_paved()
	print("lot_generator_test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _make(opts: Dictionary) -> LotGenerator:
	var g: LotGenerator = GEN.instantiate()
	for k: String in opts:
		g.set(k, opts[k])
	root.add_child(g)
	return g


func _check_layout(angle: int, two_way: bool) -> void:
	var tag := "%d%s" % [angle, "" if two_way else " one-way"]
	var g := _make({ stall_angle = angle, two_way = two_way, corrals = 2, seed = 3 })
	await process_frame
	var a := deg_to_rad(angle)
	_near(tag + " stall depth (Table 1 D)", g.stall_depth() / FT,
			{ 90: 18.0, 60: 19.8, 45: 18.7, 30: 16.4 }[angle], 0.06)
	_near(tag + " aisle (Table 1 E)", g.aisle_width() / FT,
			24.0 if two_way else { 90: 22.0, 60: 16.0, 45: 14.0, 30: 12.0 }[angle], 0.01)
	var stripes := g.stripes.get_children()
	var stops := g.stops.get_children()
	_check(tag + " has stalls", g.stall_count > 20, str(g.stall_count))
	_check(tag + " wheel stops = stalls - corrals", stops.size() == g.stall_count - 2,
			"%d stops, %d stalls" % [stops.size(), g.stall_count])
	_check(tag + " 2 corrals", g.corral_group.get_child_count() == 2, str(g.corral_group.get_child_count()))
	# Every stripe lies inside the lot, is 4" wide and Table 1's G long.
	var inside := true
	var widths := true
	var lengths := true
	for s: Node3D in stripes:
		var half := s.transform.basis.x * 0.5
		for p in [s.position + half, s.position - half]:
			if p.x < -0.01 or p.x > g.size.x + 0.01 or absf(p.z) > g.size.y * 0.5 + 0.01:
				inside = false
		widths = widths and absf(s.transform.basis.z.length() - 4.0 * 0.0254) < 0.001
		lengths = lengths and absf(s.transform.basis.x.length() - g.stall_depth() / sin(a)) < 0.01
	_check(tag + " stripes inside the lot", inside)
	_check(tag + " stripes 4 in wide", widths)
	_check(tag + " stripes Table 1 G long", lengths)
	# Neighbouring stripes on the same aisle edge are Table 1's C apart.
	var by_edge := {}
	for s: Node3D in stripes:
		var key := snappedf(s.position.z, 0.01)
		by_edge.get_or_add(key, []).append(s.position.x)
	var pitch_ok := true
	for key in by_edge:
		var xs: Array = by_edge[key]
		xs.sort()
		for i in range(1, xs.size()):
			pitch_ok = pitch_ok and absf(xs[i] - xs[i - 1] - g.stall_width / sin(a)) < 0.01
	_check(tag + " stall pitch (Table 1 C)", pitch_ok)
	# Across a double row the stripes run straight on: every stripe end on a double row's head line meets another.
	var ends := []
	for s: Node3D in stripes:
		for e in [s.position + s.transform.basis.x * 0.5, s.position - s.transform.basis.x * 0.5]:
			ends.append(e)
	var bay := 2.0 * g.stall_depth() + g.aisle_width()
	var aisle_count := int(g.size.y / bay)
	var margin := (g.size.y - aisle_count * bay) * 0.5
	var heads := 0
	var met := 0
	for i in ends.size():
		var e: Vector3 = ends[i]
		for k in range(1, aisle_count):
			if absf(e.z - (-g.size.y * 0.5 + margin + k * bay)) < 0.01:
				heads += 1
				for j in ends.size():
					if j != i and ends[j].distance_to(e) < 0.01:
						met += 1
						break
	_check(tag + " double-row stripes meet across the head line", heads > 0 and met == heads, "%d of %d" % [met, heads])
	# Islands: two per double row, one curb each plus the perimeter.
	var doubles := int(g.size.y / (2.0 * g.stall_depth() + g.aisle_width())) - 1
	_check(tag + " islands", g.islands.get_child_count() == doubles * 2,
			"%d islands for %d double rows" % [g.islands.get_child_count(), doubles])
	_check(tag + " curbs", g.curbs.get_child_count() == doubles * 2 + 1, str(g.curbs.get_child_count()))
	# Wheel stops sit OVERHANG + front offset in from the head line, square to the stall.
	var w: Node3D = stops[0]
	_check(tag + " stop square to stall", absf(absf(w.transform.basis.z.x) - cos(a)) < 0.001)
	g.free()


## A cart-sized ball rolled at a wheel stop and an island curb stops against them.
func _check_collision() -> void:
	var g := _make({ stall_angle = 90, corrals = 0 })
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	await physics_frame
	await physics_frame
	var space := g.get_world_3d().direct_space_state
	var w: Node3D = g.stops.get_child(0)
	var top := _down(space, w.global_position + Vector3(0, 1, 0))
	_near("wheel stop top 5 in", top, 0.127, 0.003)
	var island: IslandFill = g.islands.get_child(0)
	var curb_top := _down(space, island.global_position + Vector3(island.size.x * 0.5 + 0.07, 1, 0))
	_check("island curb about 6 in", curb_top > 0.14 and curb_top < 0.17, "%.3f" % curb_top)
	var fill_top := _down(space, island.global_position + Vector3(0, 1, 0))
	_near("island fill top", fill_top, 0.13, 0.002)
	g.free()
	ground.free()


## Paved with asphalt sections: 10 m tiles over the lot, each given the stall lines over it in its sim's space.
func _check_paved() -> void:
	var g: LotGenerator = GEN.instantiate()
	g.size = Vector2(60, 40)
	g.section_scene = load("res://scenes/asphalt/asphalt_section.tscn")
	g.generate()   # out of the tree, so the sections don't simulate
	_check("paved: 24 sections", g.sections.get_child_count() == 24, str(g.sections.get_child_count()))
	_check("paved: no stripe meshes", g.stripes.get_child_count() == 0)
	var inside := true
	var total := 0.0
	for s: AsphaltSection in g.sections.get_children():
		var lines := s.sim.paint_lines
		for k in range(0, lines.size(), 2):
			total += lines[k].distance_to(lines[k + 1])
			for p in [lines[k], lines[k + 1]]:
				inside = inside and p.x > -0.001 and p.x < 10.001 and p.y > -0.001 and p.y < 10.001
			# Back in lot space, a 90 degree stall line runs along Z.
			var a := s.transform * Vector3(lines[k].x - 5.0, 0, lines[k].y - 5.0)
			var b := s.transform * Vector3(lines[k + 1].x - 5.0, 0, lines[k + 1].y - 5.0)
			inside = inside and absf(a.x - b.x) < 0.001
	_check("paved: lines inside their sections, along Z in the lot", inside)
	# (stalls + one more stripe per row) stripes, each a stall depth long.
	var want := (g.stall_count + 4) * g.stall_depth()
	_near("paved: total line length", total, want, 0.05)
	g.free()


func _down(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -2, 0)))
	return hit.position.y if hit else -1.0


func _near(what: String, got: float, want: float, tol := 0.001) -> void:
	_check(what, absf(got - want) <= tol, "got %.4f, want %.4f" % [got, want])


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fails += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", what, detail])
