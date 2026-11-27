class_name AsphaltSimCracks
extends AsphaltSimState
## AsphaltSim, part 2 of 7: the crack-geometry engine. Cracks are polylines grown a STEP at a time on the GRID occupancy
## grid: they steer, take the weaker mix, turn to meet other cracks square on and join them (Bohn 2005, Shorlin
## 1999), branch, and follow guide paths (reflection and seam cracks). What starts a crack lives in the rules.


## A new crack's opening rate from where it starts, and the surface's age.
func _new_crack(kind: int, p: Vector2) -> Crack:
	var c := Crack.new()
	c.kind = kind
	c.surf0 = surface_born
	c.ox_k = maxf(climate, 0.05) / oxidation_years
	var i := cell_index(p)
	c.local = (0.5 + 0.5 * climate) * (0.45 + 0.45 * minf(load[i], 1.5) * traffic + 0.3 * weak[i]
		+ 0.4 * pond[i] * ponding * drainage)
	return c


## Two cracks growing opposite ways from one start; returns the second's index.
func _twin(kind: int, p: Vector2, heading: float, wander: float, steer: float, speed: float, widen: float) -> int:
	var a := _crack(kind, p, heading, heading, wander, steer, speed, 1e9, widen)
	var b := _crack(kind, p, heading + PI, heading + PI, wander, steer, speed, 1e9, widen)
	cracks[a].twin = b
	cracks[b].twin = a
	return b


func _crack(kind: int, p: Vector2, heading: float, pref: float, wander: float, steer: float, speed: float,
		max_len: float, widen: float) -> int:
	var c := _new_crack(kind, p)
	c.dir = heading
	c.pref = pref
	c.wander = wander
	c.steer = steer
	c.speed = speed
	c.max_len = max_len
	c.widen = widen * _rng.randf_range(0.7, 1.3)
	c.pts.append(p)
	c.born.append(time)
	cracks.append(c)
	return cracks.size() - 1


func _grow(ci: int, dist: float) -> void:
	var c := cracks[ci]
	c.carry += dist
	while c.carry >= STEP and c.growing:
		c.carry -= STEP
		var p := c.pts[c.pts.size() - 1]
		var q: Vector2
		if c.guide.size() > 0:
			if c.guide_i >= c.guide.size():
				c.growing = false
				break
			q = c.guide[c.guide_i] + Vector2(_rng.randf_range(-0.004, 0.004), _rng.randf_range(-0.004, 0.004))
			c.guide_i += 1
		else:
			var d := c.dir + _rng.randfn(0.0, c.wander) + angle_difference(c.dir, c.pref) * c.steer
			# The tip takes the weakest way of three: around the stones, through the poorly compacted mix.
			if crack_bias > 0.0:
				var best := -INF
				var pick := d
				for o in [-0.45, 0.0, 0.45]:
					var score := mix_weakness(p + Vector2.from_angle(d + o) * STEP) * crack_bias * 3.0 - absf(o) * 0.8 \
						+ _rng.randf() * 0.3
					if score > best:
						best = score
						pick = d + o
				d = pick
			# Another crack's free face takes the stress across it off, over a distance of about the layer
			# thickness (Bohn et al. 2005), so the stress left near it runs along it. The tip follows the local
			# stress (principle of local symmetry): the closer it gets, the more it turns to meet the crack square
			# on (shrinkage cracks meet at 90 +- 15 degrees: Shorlin et al. 1999).
			if c.kind != Kind.SLIPPAGE:
				var zone := thickness()
				var s_ahead := STEP
				while s_ahead <= zone:
					var ahead := _hit(p + Vector2.from_angle(d) * s_ahead, ci, c)
					if ahead.x >= 0 and cracks[ahead.x].pts.size() >= 2:
						var o := cracks[ahead.x]
						var k := clampi(ahead.y, 1, o.pts.size() - 1)
						var along := (o.pts[k] - o.pts[k - 1]).angle()
						var square := along + PI * 0.5
						if absf(angle_difference(d, square)) > PI * 0.5:
							square += PI
						d = lerp_angle(d, square, 1.0 - (s_ahead - STEP) / zone)
						break
					s_ahead += STEP
			c.dir = d
			q = p + Vector2.from_angle(c.dir) * STEP
		if not paved(q) or patch_of[cell_index(q)] != patch_of[cell_index(p)] and c.kind != Kind.SEAM:
			c.growing = false
			break
		if c.guide.is_empty():
			var hit := _hit(q, ci, c)
			if hit.x >= 0:
				var other := cracks[hit.x]
				if _rng.randf() >= stop_short or other.pts.size() < 2:
					# Runs into it and stops at a T: the other crack's free edge takes the stress off. It joins at the
					# nearest point of the other crack, so the last step meets it square on.
					var hk := mini(hit.y, other.pts.size() - 1)
					q = other.pts[hk]
					for j in [hk - 1, hk]:
						if j >= 0 and j + 1 < other.pts.size():
							var f := Geometry2D.get_closest_point_to_segment(p, other.pts[j], other.pts[j + 1])
							if f.distance_squared_to(p) < q.distance_squared_to(p):
								q = f
					_append(c, ci, q)
					c.growing = false
					break
				# Dies out just short of it, in the other crack's stress shadow.
				c.growing = false
				break
		_append(c, ci, q)
		# Now and then a side branch splits off (more as the binder gets brittle).
		if c.guide.is_empty() and branching > 0.0 and c.kind != Kind.SLIPPAGE \
				and _rng.randf() < branching * STEP * (0.5 + c.local * 0.5):
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var heading := c.dir + side * _rng.randf_range(0.5, 1.0)
			var pref := c.pref + side * 0.6
			if _shrinkage(c.kind):
				# A shrinkage crack starting from the side of another leaves it at right angles (Shorlin et al. 1999:
				# junctions 90 +- 15 degrees), where the stress left runs along the parent.
				heading = c.dir + side * (PI * 0.5 + _rng.randfn(0.0, BRANCH_SCATTER))
				pref = heading
			var b := _crack(c.kind, q, heading, pref, c.wander * 1.5, c.steer * 0.5, c.speed * 0.8,
				_rng.randf_range(0.15, 0.9), c.widen * 0.7)
			cracks[b].parent = ci
			c = cracks[ci]
		if c.length >= c.max_len:
			c.growing = false


## Cracks the cold opens (shrinkage of the layer), as opposed to wheel fatigue and slippage.
func _shrinkage(kind: int) -> bool:
	return kind == Kind.TRANSVERSE or kind == Kind.JOINT or kind == Kind.BLOCK or kind == Kind.REFLECTION \
		or kind == Kind.SEAM


func _append(c: Crack, ci: int, q: Vector2) -> void:
	var p := c.pts[c.pts.size() - 1]
	c.length += p.distance_to(q)
	c.pts.append(q)
	c.born.append(time)
	_add_points(c, ci, c.pts.size() - 1)


## Mark points from index `from` on in the grids.
func _add_points(c: Crack, ci: int, from: int) -> void:
	for k in range(from, c.pts.size()):
		var q := c.pts[k]
		var seg := q.distance_to(c.pts[k - 1]) if k > 0 else 0.0
		if k > 0:
			_mark((q + c.pts[k - 1]) * 0.5, ci, k)
		_mark(q, ci, k)
		var i := cell_index(q)
		crack_len[i] += seg
		if not c.sealed(time):
			open_len[i] += seg


func _mark(q: Vector2, ci: int, k: int) -> void:
	var g := _grid(q)
	if g >= 0:
		occ[g] = ci + 1
		occ_pt[g] = k


func _grid(q: Vector2) -> int:
	var x := int(q.x / GRID)
	var y := int(q.y / GRID)
	if x < 0 or y < 0 or x >= gx or y >= gy:
		return -1
	return y * gx + x


## Another crack within a grid cell of q: Vector2i(crack, point), or x = -1.
func _hit(q: Vector2, ci: int, c: Crack) -> Vector2i:
	var x := int(q.x / GRID)
	var y := int(q.y / GRID)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= gx or yy >= gy:
				continue
			var g := yy * gx + xx
			var o := occ[g] - 1
			if o < 0 or o == ci or o == c.twin:
				continue
			if o == c.parent and c.pts.size() < 5:
				continue
			if not cracks[o].alive:
				continue
			return Vector2i(o, occ_pt[g])
	return Vector2i(-1, -1)


func _free(p: Vector2, r: float) -> bool:
	var n := int(ceil(r / GRID))
	var x := int(p.x / GRID)
	var y := int(p.y / GRID)
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and yy >= 0 and xx < gx and yy < gy and occ[yy * gx + xx] != 0:
				return false
	return true


func _reflect() -> void:
	for k in range(_latent.size() - 1, -1, -1):
		var l: Dictionary = _latent[k]
		if time < l.at:
			continue
		_latent.remove_at(k)
		var path: PackedVector2Array = l.path
		if path.size() < 3:
			continue
		var c := _new_crack(l.get("kind", Kind.REFLECTION), path[0])
		c.speed = l.get("speed", 1.5)
		c.widen = l.get("widen", 1.1)
		c.guide = path
		c.guide_i = 1
		c.pts.append(path[0])
		c.born.append(time)
		cracks.append(c)


## A path from a to b, STEP apart, wandering up to `amp` m either side (ends fixed).
func _wobble(a: Vector2, b: Vector2, amp: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	var n := maxi(2, int(a.distance_to(b) / STEP))
	var side := (b - a).orthogonal().normalized()
	var p1 := _rng.randf() * TAU
	var p2 := _rng.randf() * TAU
	var k1 := _rng.randf_range(1.0, 2.0)
	var k2 := _rng.randf_range(2.5, 4.5)
	for k in n + 1:
		var t := float(k) / n
		var off := amp * sin(PI * t) * (0.7 * sin(TAU * k1 * t + p1) + 0.3 * sin(TAU * k2 * t + p2))
		off += _rng.randf_range(-0.002, 0.002) if k > 0 and k < n else 0.0
		path.append(a.lerp(b, t) + side * off)
	return path


func _rebuild_grid() -> void:
	occ.fill(0)
	for ci in cracks.size():
		var c := cracks[ci]
		if not c.alive:
			continue
		for k in c.pts.size():
			_mark(c.pts[k], ci, k)
			if k > 0:
				_mark((c.pts[k] + c.pts[k - 1]) * 0.5, ci, k)
	_rebuild_lengths()


func _rebuild_lengths() -> void:
	crack_len.fill(0.0)
	open_len.fill(0.0)
	for c in cracks:
		if not c.alive:
			continue
		var sealed := c.sealed(time + 0.001)
		if sealed:
			_seal_check = minf(_seal_check, c.seal_to())
		for k in range(1, c.pts.size()):
			var seg := c.pts[k].distance_to(c.pts[k - 1])
			var i := cell_index(c.pts[k])
			crack_len[i] += seg
			if not sealed:
				open_len[i] += seg
