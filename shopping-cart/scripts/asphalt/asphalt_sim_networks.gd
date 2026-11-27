class_name AsphaltSimNetworks
extends AsphaltSimCracks
## AsphaltSim, part 3 of 7: the crack networks laid out at year 0, the Voronoi cells of jittered points: crocodile
## cells over the wheel paths (Westergaard radius) and blocks over the road (slip length). Edges open when the
## rules say the stress under them has passed their threshold.


func _build_networks() -> void:
	_net_edges.clear()
	net_cells.clear()
	var fc := fatigue_cell()
	var bc := block_cell()
	# Fatigue cells: about 15 x 21 cm on a 3 in lot (crocodile skin has a longitudinal grain), over each wheel path.
	var seeds := PackedVector2Array()
	for wp in wheel_paths:
		var x0 := wp - wheel_path_width * 1.3
		var cols := int(round(wheel_path_width * 2.6 / fc.x))
		var rows := int(ceil(size.y / fc.y)) + 1
		for r in rows:
			for c in cols + 1:
				var p := Vector2(x0 + c * fc.x, (r - 0.5) * fc.y) \
					+ Vector2(_rng.randf_range(-0.4, 0.4) * fc.x, _rng.randf_range(-0.4, 0.4) * fc.y)
				if paved(p):
					seeds.append(p)
	net_seeds = seeds
	plucked.resize(seeds.size())
	plucked.fill(0.0)
	_add_network(seeds, Kind.FATIGUE, fc.y * 2.2, true)
	# Block cells: about 1.6 x 2.3 m on a 3 in lot, little jitter so they come out nearly rectangular.
	var bs := PackedVector2Array()
	var bcols := int(ceil((size.x - 2.0 * shoulder) / bc.x)) + 1
	var brows := int(ceil(size.y / bc.y)) + 2
	for r in brows:
		for c in bcols:
			bs.append(Vector2(shoulder + (c + _rng.randf_range(-0.12, 0.12)) * bc.x,
				(r - 1 + _rng.randf_range(-0.12, 0.12)) * bc.y))
	_add_network(bs, Kind.BLOCK, bc.y * 2.5, false)
	# Which fatigue cell is over each 10 cm cell (potholes pluck whole cells out).
	_cell_seed.resize(nx * ny)
	_cell_seed.fill(-1)
	for k in seeds.size():
		var q := seeds[k]
		var r := int(ceil(maxf(fc.x, fc.y) / CELL))
		var cx := int(q.x / CELL)
		var cy := int(q.y / CELL)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= nx or y >= ny:
					continue
				var i := y * nx + x
				var cur := _cell_seed[i]
				if cur < 0 or cell_center(i).distance_squared_to(seeds[cur]) > cell_center(i).distance_squared_to(q):
					_cell_seed[i] = k
	for i in nx * ny:
		var k := _cell_seed[i]
		if k >= 0 and (cell_center(i).distance_to(seeds[k]) > maxf(fc.x, fc.y) or net_cells[k].is_empty()):
			_cell_seed[i] = -1


## Voronoi edges of `pts` (from their Delaunay triangles) as closed-off crack paths; edges longer than `max_len`
## (the open rim) are dropped. With `cells`, also each point's cell outline.
func _add_network(pts: PackedVector2Array, kind: int, max_len: float, cells: bool) -> void:
	var tri := Geometry2D.triangulate_delaunay(pts)
	var centers := PackedVector2Array()
	var n := tri.size() / 3
	var by_edge := { }
	var around: Array[PackedInt32Array] = []
	if cells:
		around.resize(pts.size())
	for t in n:
		var a := pts[tri[t * 3]]
		var b := pts[tri[t * 3 + 1]]
		var c := pts[tri[t * 3 + 2]]
		centers.append(_circumcenter(a, b, c))
		for e in 3:
			var i := tri[t * 3 + e]
			var j := tri[t * 3 + (e + 1) % 3]
			var key := mini(i, j) * pts.size() + maxi(i, j)
			if by_edge.has(key):
				by_edge[key].append(t)
			else:
				by_edge[key] = [t]
			if cells:
				around[i].append(t)
	for key in by_edge:
		var ts: Array = by_edge[key]
		if ts.size() != 2:
			continue
		var a: Vector2 = centers[ts[0]]
		var b: Vector2 = centers[ts[1]]
		if a.distance_to(b) > max_len or a.distance_to(b) < 0.02:
			continue
		_net_edges.append({ a = a, b = b, kind = kind, thr = _rng.randf(), on = false, ci = cell_index((a + b) * 0.5) })
	if cells:
		for i in pts.size():
			var ring := PackedVector2Array()
			var ok := around[i].size() >= 3
			var angs := []
			for t in around[i]:
				var c := centers[t]
				if c.distance_to(pts[i]) > max_len:
					ok = false
				angs.append([(c - pts[i]).angle(), c])
			if ok:
				angs.sort_custom(func(u: Array, v: Array) -> bool: return u[0] < v[0])
				for av in angs:
					ring.append(av[1])
				# A cell on the rim of the network is open on one side: its ring of corners has a gap.
				var gap := false
				for k in ring.size():
					if ring[k].distance_to(ring[(k + 1) % ring.size()]) > max_len:
						gap = true
				if gap:
					ring = PackedVector2Array()
			net_cells.append(ring)


func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-9:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


## Open the network edges whose stress has passed their threshold. Fatigue edges go when the fatigue at their
## middle passes FATIGUE_CELLS (plus up to 0.35 more, per edge); block edges when the binder's oxidation passes
## block_onset (plus up to 0.45). An edge opens from an end that touches a crack, so the cracking spreads out
## from the wheel-path cracks and the long cracks; now and then one starts on its own.
func _open_edges(age: float, ox: float) -> void:
	# Block cracking is the same everywhere, so its threshold is worked out once a step.
	var block_level := ox * climate * (1.25 - 0.25 * structure) if age > 5.0 else -1.0
	for e in _net_edges:
		if e.on:
			continue
		if e.kind == Kind.FATIGUE:
			if fatigue[e.ci] <= FATIGUE_CELLS + 0.35 * e.thr:
				continue
		elif block_level <= block_onset + 0.45 * e.thr:
			continue
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		if not paved((a + b) * 0.5):
			continue
		var touch_a := not _free(a, 0.03)
		var touch_b := not _free(b, 0.03)
		# Crocodile cells grow out of the wheel-path cracks: an edge touching no crack rarely opens on its own.
		if not touch_a and not touch_b and _rng.randf() > DT * (0.12 if e.kind == Kind.FATIGUE else 0.3):
			continue
		e.on = true
		var from := b if touch_b and not touch_a else a
		var to := a if from == b else b
		var c := _new_crack(e.kind, from)
		c.speed = 1.2 if e.kind == Kind.FATIGUE else 2.0
		c.widen = 1.3 if e.kind == Kind.FATIGUE else 1.0   # crocodile cells rock under every wheel and open fast
		c.guide = _wobble(from, to, 0.012 if e.kind == Kind.FATIGUE else 0.07)
		c.guide_i = 1
		c.pts.append(from)
		c.born.append(time)
		cracks.append(c)
		_mark(from, cracks.size() - 1, 0)


## A pothole in this 10 cm cell plucks out the fatigue cell over it.
func _pluck(i: int) -> void:
	var k := _cell_seed[i] if _cell_seed.size() > i else -1
	if k >= 0:
		plucked[k] = maxf(plucked[k], hole[i])
