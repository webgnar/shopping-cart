class_name AsphaltSimRepairs
extends AsphaltSimRules
## AsphaltSim, part 5 of 7: the repairs (crack filling, cold patch, heavy patch, spot sealcoat, mill and overlay,
## repaint) and the road crew that does them on its own. Their lives and effects are placeholders.


func _apply(action: int) -> void:
	_last[action] = time
	var note := ""
	match action:
		Action.CRACK_FILL:
			note = _crack_fill()
		Action.POTHOLE_FILL:
			note = _pothole_fill()
		Action.HEAVY_PATCH:
			note = _heavy_patch()
		Action.SURFACE_SEAL:
			note = _spot_seal()
		Action.OVERLAY:
			note = _resurface()
		Action.REPAINT:
			paint_born = time
			note = "%d lines" % (paint_lines.size() / 2)
	log_lines.append("Year %.1f  %s: %s" % [time, ACTION_NAMES[action], note])
	_rebuild_lengths()


## Crack filling: hot rubberised sealant poured into every crack wider than a hairline, overbanded on top.
## The sealant stops water and stops the crack opening, until it debonds after SEAL_LIFE years.
func _crack_fill() -> String:
	var n := 0
	var m := 0.0
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or c.sealed(time):
			continue
		if c.width(0, time) < 0.0015 and c.kind != Kind.TRANSVERSE:
			continue
		if c.seal_from >= 0.0:
			c.sealed_before += c._g(c.seal_from, minf(time, c.seal_to()))
		c.seal_from = time
		n += 1
		m += c.length
		_seal_check = minf(_seal_check, time + SEAL_LIFE)
	return "%d cracks, %.0f m" % [n, m]


## Throw-and-roll: cold mix shovelled into each pothole and rolled with the truck tyre. Cheap and quick, and
## water gets in round its edges, so it tends to ravel out again in a year or three.
func _pothole_fill() -> String:
	var n := _count_clusters()
	var filled := PackedInt32Array()
	for i in nx * ny:
		if hole[i] > 0.0:
			filled.append(i)
	for i in filled:
		if _cell_seed[i] >= 0:
			plucked[_cell_seed[i]] = 0.0
		fill_depth[i] = hole[i]
		hole[i] = 0.0
		fill_born[i] = time
		damage[i] = 0.35
		# The crew shovels the mix a little past the broken edge.
		for o in [1, -1, nx, -nx]:
			var j: int = i + o
			if j >= 0 and j < nx * ny and hole[j] <= 0.0:
				damage[j] = minf(damage[j], 0.6)
	# The cold joint round each patch, where the mix meets the old edge: it opens into a crack a year or two on.
	var outlined := { }
	for i in filled:
		var k := _cell_seed[i]
		if outlined.has(k if k >= 0 else -1 - i):
			continue
		outlined[k if k >= 0 else -1 - i] = true
		var ring := PackedVector2Array()
		if k >= 0 and not net_cells[k].is_empty():
			for q in net_cells[k]:
				ring.append(net_seeds[k] + (q - net_seeds[k]) * 1.12)
		else:
			for a in 12:
				ring.append(cell_center(i) + Vector2.from_angle(TAU * a / 12.0) * 0.12)
		ring.append(ring[0])
		# Only the outer edge of the patch is a joint: skip stretches that run inside the next filled cell.
		var at := time + _rng.randf_range(0.8, 2.5)
		var path := PackedVector2Array()
		for e in ring.size() - 1:
			var m := maxi(1, int(ring[e].distance_to(ring[e + 1]) / STEP))
			for s in m + (1 if e == ring.size() - 2 else 0):
				var q := ring[e].lerp(ring[e + 1], float(s) / m)
				var j := cell_index(q)
				var inner := fill_born[j] >= 0.0 and j != i and (k < 0 or _cell_seed[j] != k)
				if not inner and paved(q):
					path.append(q)
				elif path.size() > 0:
					if path.size() >= 3:
						_latent.append({ path = path, at = at, kind = Kind.SEAM, speed = 1.0, widen = 1.3 })
					path = PackedVector2Array()
		if path.size() >= 3:
			_latent.append({ path = path, at = at, kind = Kind.SEAM, speed = 1.0, widen = 1.3 })
	return "%d potholes" % n


## Heavy patching: saw-cut a tight rectangle round each pothole or failed fill, dig out the failed asphalt
## and base, and replace it full depth. Cracks inside are gone; the cut edges are joints that crack open later.
func _heavy_patch() -> String:
	# The crew cuts a tight rectangle round each pothole or failed fill, not round whole cracked areas.
	var bad := PackedByteArray()
	bad.resize(nx * ny)
	for i in nx * ny:
		if load[i] > 0.0 and (hole[i] > 0.0 or fill_born[i] >= 0.0):
			bad[i] = 1
	var rects: Array[Rect2] = []
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	for i in nx * ny:
		if bad[i] == 0 or seen[i] == 1:
			continue
		var r := Rect2(cell_center(i), Vector2.ZERO)
		var stack := [i]
		seen[i] = 1
		var count := 0
		while not stack.is_empty():
			var j: int = stack.pop_back()
			count += 1
			r = r.expand(cell_center(j) - Vector2.ONE * CELL * 0.5).expand(cell_center(j) + Vector2.ONE * CELL * 0.5)
			var cx := j % nx
			var cy := j / nx
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var y := cy + dy
					if x >= 0 and y >= 0 and x < nx and y < ny and bad[y * nx + x] == 1 and seen[y * nx + x] == 0:
						seen[y * nx + x] = 1
						stack.append(y * nx + x)
		rects.append(r.grow(0.12))
	# Merge overlapping cuts into one, square to the road and on a 5 cm grid, inside the pavement.
	var merged := true
	while merged:
		merged = false
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				if rects[a].grow(0.05).intersects(rects[b]):
					rects[a] = rects[a].merge(rects[b])
					rects.remove_at(b)
					merged = true
					break
			if merged:
				break
	var made := 0
	for r in rects:
		var p0 := (r.position / 0.05).floor() * 0.05
		var p1 := (r.end / 0.05).ceil() * 0.05
		p0.x = maxf(p0.x, shoulder + 0.05)
		p1.x = minf(p1.x, size.x - shoulder - 0.05)
		p0.y = maxf(p0.y, 0.0)
		p1.y = minf(p1.y, size.y)
		var rect := Rect2(p0, p1 - p0)
		if rect.size.x < 0.3 or rect.size.y < 0.3:
			continue
		var id := patches.size()
		var seams := PackedFloat32Array()
		for s in 4:
			seams.append(time + _rng.randf_range(2.0, 6.0) * structure)
		patches.append({ rect = rect, born = time, seams_at = seams })
		made += 1
		for i in nx * ny:
			var c := cell_center(i)
			if rect.has_point(c):
				patch_of[i] = id
				fatigue[i] = 0.0
				damage[i] = 0.0
				hole[i] = 0.0
				fill_born[i] = -1.0
				fill_depth[i] = 0.0
				weak[i] *= 0.4
				if _cell_seed[i] >= 0:
					plucked[_cell_seed[i]] = 0.0
		_cut_cracks(rect)
		for k in range(_latent.size() - 1, -1, -1):   # joints of fills dug out with it
			var lp: PackedVector2Array = _latent[k].path
			if not lp.is_empty() and rect.has_point(lp[0]):
				_latent.remove_at(k)
		# Seams: each cut edge opens into a crack along it a few years on.
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for s in 4:
			var a: Vector2 = corners[s]
			var b: Vector2 = corners[(s + 1) % 4]
			var path := PackedVector2Array()
			var n := maxi(2, int(a.distance_to(b) / STEP))
			var out := (b - a).orthogonal().normalized() * 0.006
			for k in n + 1:
				path.append(a.lerp(b, float(k) / n) - out)
			var keep := PackedVector2Array()
			for q in path:
				if paved(q):
					keep.append(q)
			_latent.append({ path = keep, at = seams[s], kind = Kind.SEAM, speed = 1.2, widen = 1.6 })
	return "%d patches" % made


## Cut every crack where it crosses into the rectangle: the part inside is dug out.
func _cut_cracks(rect: Rect2) -> void:
	var count := cracks.size()
	for ci in count:
		var c := cracks[ci]
		if not c.alive:
			continue
		var inside := false
		for q in c.pts:
			if rect.has_point(q):
				inside = true
				break
		if not inside:
			continue
		var runs: Array[Array] = []
		var cur: Array = []
		for k in c.pts.size():
			if rect.has_point(c.pts[k]):
				if cur.size() > 0:
					runs.append(cur)
					cur = []
			else:
				cur.append(k)
		if cur.size() > 0:
			runs.append(cur)
		c.alive = false
		for run in runs:
			if run.size() < 2:
				continue
			var n := Crack.new()
			n.kind = c.kind
			n.widen = c.widen
			n.local = c.local
			n.surf0 = c.surf0
			n.ox_k = c.ox_k
			n.seal_from = c.seal_from
			n.sealed_before = c.sealed_before
			n.growing = false
			for k: int in run:
				n.pts.append(c.pts[k])
				n.born.append(c.born[k])
			# Run the cut end right up to the saw cut.
			var first: int = run[0]
			var last: int = run[run.size() - 1]
			if last < c.pts.size() - 1:
				n.pts.append(_edge_point(c.pts[last], c.pts[last + 1], rect))
				n.born.append(c.born[last])
			if first > 0:
				n.pts.insert(0, _edge_point(c.pts[first], c.pts[first - 1], rect))
				n.born.insert(0, c.born[first])
			for k in n.pts.size() - 1:
				n.length += n.pts[k].distance_to(n.pts[k + 1])
			cracks.append(n)
	_rebuild_grid()


func _edge_point(outside: Vector2, inside: Vector2, rect: Rect2) -> Vector2:
	var a := outside
	var b := inside
	for _k in 8:
		var m := (a + b) * 0.5
		if rect.has_point(m):
			b = m
		else:
			a = m
	return a


## Spot sealcoat: the crew squeegees black sealer over a few of the roughest areas (most cracking, no potholes),
## a blob a couple of metres across each. It is only a coat: the cracks stay, it greys, and traffic wears it off
## the wheel paths first (see sealcoat_left). Cracks that open later show through it.
func _spot_seal() -> String:
	var score := PackedFloat32Array()
	score.resize(nx * ny)
	for i in nx * ny:
		var p := cell_center(i)
		score[i] = crack_len[i] + 0.3 * open_len[i] if paved(p) and hole[i] <= 0.0 else -1.0
	var made := 0
	for n in sealcoat_spots:
		# The roughest 10 cm cell, smoothed over its 1 m neighbourhood, not already under a spot from this pass.
		var best := -1
		var best_v := 0.0
		for tries in 400:
			var i := _rng.randi_range(0, nx * ny - 1)
			if score[i] < 0.0:
				continue
			var c := cell_center(i)
			var taken := false
			for sp in seal_spots:
				if sp.born == time and Geometry2D.is_point_in_polygon(c, sp.poly):
					taken = true
					break
			if taken:
				continue
			var v := 0.0
			for dy in range(-5, 6, 2):
				for dx in range(-5, 6, 2):
					var j := cell_index(c + Vector2(dx, dy) * CELL)
					v += maxf(score[j], 0.0)
			if v > best_v:
				best_v = v
				best = i
		if best < 0:
			break
		var centre := cell_center(best)
		var r := _rng.randf_range(sealcoat_size.x, sealcoat_size.y)
		var stretch := _rng.randf_range(0.7, 1.3)
		var poly := PackedVector2Array()
		var wob := _rng.randf() * TAU
		for k in 72:
			var a := TAU * k / 72.0
			var rr := r * (1.0 + 0.18 * sin(a * 3.0 + wob) + 0.1 * sin(a * 7.0 + wob * 2.0) + 0.04 * sin(a * 19.0 + wob * 3.0)
				+ _rng.randf_range(-0.03, 0.03))
			var q := centre + Vector2(cos(a) * rr * stretch, sin(a) * rr / stretch)
			q.x = clampf(q.x, shoulder + 0.05, size.x - shoulder - 0.05)
			q.y = clampf(q.y, 0.0, size.y)
			poly.append(q)
		seal_spots.append({ poly = poly, born = time })
		made += 1
	return "%d spots" % made


## Cold plane and overlay: a new wearing surface over everything. Potholes are filled first.
## The old cracks and the patch edges stay in the layer below and come back through it as reflection cracks.
func _resurface() -> String:
	var buried := 0
	for c in cracks:
		if not c.alive or c.pts.size() < 3:
			c.alive = false
			continue
		var w := c.width(0, time)
		# Hairlines mostly stay buried; wide, working cracks come back first.
		var chance := clampf(w / 0.006, 0.15, 1.0) * 0.75
		if _rng.randf() < chance:
			var delay := _rng.randf_range(1.5, 5.0) * structure \
				* lerpf(1.6, 0.6, clampf(w / 0.015, 0.0, 1.0))
			_latent.append({ path = c.pts.duplicate(), at = time + delay })
			buried += 1
		c.alive = false
	for p in patches:
		var r: Rect2 = p.rect
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for s in 4:
			if _rng.randf() < 0.6:
				var a: Vector2 = corners[s]
				var b: Vector2 = corners[(s + 1) % 4]
				var path := PackedVector2Array()
				var n := maxi(2, int(a.distance_to(b) / STEP))
				for k in n + 1:
					path.append(a.lerp(b, float(k) / n))
				_latent.append({ path = path, at = time + _rng.randf_range(2.0, 6.0) * structure })
	cracks = cracks.filter(func(c: Crack) -> bool: return c.alive)
	patches.clear()
	_transverse_y.clear()
	plucked.fill(0.0)
	for e in _net_edges:
		e.on = false
	for i in nx * ny:
		hole[i] = 0.0
		fill_born[i] = -1.0
		fill_depth[i] = 0.0
		patch_of[i] = -1
		damage[i] *= 0.3
		fatigue[i] *= 0.45
	edge_l.fill(0.0)
	edge_r.fill(0.0)
	rut_born = time
	surface_born = time
	paint_born = time
	seal_spots.clear()
	_rebuild_grid()
	return "%d cracks will reflect through" % buried


## What a road crew does left to itself: fill cracks once they open up, fill potholes straight away, patch the
## worst fatigue areas, and overlay the road when it is beyond patching.
func _auto_maintain() -> void:
	var since := func(a: int) -> float: return time - float(_last.get(a, -100.0))
	if surface_age() < 1.0:
		return
	var s := stats()
	if s.pci < 30.0 and since.call(Action.OVERLAY) > 6.0:
		_apply(Action.OVERLAY)
		return
	if s.pothole_pct > 0.0 and since.call(Action.POTHOLE_FILL) > 0.5:
		_apply(Action.POTHOLE_FILL)
	if s.alligator_pct > 3.0 and since.call(Action.HEAVY_PATCH) > 4.0:
		_apply(Action.HEAVY_PATCH)
	if s.wide_crack_m > 6.0 and since.call(Action.CRACK_FILL) > 3.0:
		_apply(Action.CRACK_FILL)
