class_name AsphaltSimHeight
extends AsphaltSimRepairs
## AsphaltSim, part 6 of 7: the road surface as heights in metres (bake_height), for the displacement, the collision
## and the cross-section.


## The road surface as heights in metres (0 = as built, down is negative) on a grid `res` metres apart, for the
## ground's displacement and collision: (size / res + 1) points across X, rows along Y, row-major. Cracks are cut
## at their real width and depth (one narrower than the grid makes a shallower dip), with broken shoulders on wide
## ones; potholes go down to their depth; wheel paths rut; the fretted edge drops to the base course and the
## shoulders sit lower. The outer `edge_feather` metres ease back to 0 so the section meets flat ground.
func bake_height(res := 0.01) -> PackedFloat32Array:
	var w := int(round(size.x / res)) + 1
	var h := int(round(size.y / res)) + 1
	var out := PackedFloat32Array()
	out.resize(w * h)
	# Ruts depend only on X; the shoulders and fretted edge on X and the 10 cm row.
	var rut := PackedFloat32Array()
	rut.resize(w)
	var rd := rut_depth()
	for ix in w:
		var x := ix * res
		var r := 0.0
		for wp in wheel_paths:
			r += exp(-pow((x - wp) / 0.35, 2.0))
		rut[ix] = -rd * r
	var row := PackedFloat32Array()
	row.resize(w)
	for iy in h:
		var y := iy * res
		var cr := clampi(int(y / CELL), 0, ny - 1)
		var l := shoulder + edge_l[cr]
		var r := size.x - shoulder - edge_r[cr]
		for ix in w:
			var x := ix * res
			var v := rut[ix]
			if x < shoulder or x > size.x - shoulder:
				v = shoulder_drop
			elif x < l or x > r:
				v = fret_drop
			row[ix] = v
		for ix in w:
			out[iy * w + ix] = row[ix]
	# Patches and fills sit a few millimetres proud (fresh mix, rolled). They bury every crack that was there
	# before them: `covered` holds the year each pixel was last repaired, and only cracks newer than that cut it.
	var covered := PackedFloat32Array()
	covered.resize(w * h)
	covered.fill(-1.0)
	for p in patches:
		var rect: Rect2 = p.rect
		for iy in range(int(ceil(rect.position.y / res)), int(rect.end.y / res) + 1):
			for ix in range(int(ceil(rect.position.x / res)), int(rect.end.x / res) + 1):
				if iy >= 0 and iy < h and ix >= 0 and ix < w:
					out[iy * w + ix] = 0.003
					covered[iy * w + ix] = maxf(covered[iy * w + ix], p.born)
	# The tar band over a patch's seam stands a hair proud until it debonds.
	for p in patches:
		if time - p.born >= SEAL_LIFE * 1.5:
			continue
		var rect: Rect2 = p.rect
		var outer := rect.grow(0.035)
		var inner := rect.grow(-0.035)
		for iy in range(maxi(0, int(outer.position.y / res)), mini(h - 1, int(ceil(outer.end.y / res))) + 1):
			for ix in range(maxi(0, int(outer.position.x / res)), mini(w - 1, int(ceil(outer.end.x / res))) + 1):
				var q := Vector2(ix * res, iy * res)
				if outer.has_point(q) and not inner.has_point(q):
					out[iy * w + ix] += SEAL_PROUD
	# Cold patch, tamped flat in the shape of its hole: the plucked crocodile cell, or a disk.
	var filled_cells := { }
	for i in nx * ny:
		if fill_born[i] < 0.0:
			continue
		var k := _cell_seed[i]
		if k >= 0 and not net_cells[k].is_empty():
			# The 10 cm cells of the hole can reach past the crocodile cell's outline: fill those too.
			_stamp_disk(out, w, h, res, cell_center(i), 0.075, fill_proud(time - fill_born[i]), false)
			_stamp_disk(covered, w, h, res, cell_center(i), 0.075, fill_born[i], false)
			if filled_cells.has(k):
				continue
			filled_cells[k] = true
			var poly := PackedVector2Array()
			for q in net_cells[k]:
				poly.append(net_seeds[k] + (q - net_seeds[k]) * 1.12)
			var bb := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				bb = bb.expand(q)
			var up := fill_proud(time - fill_born[i])
			for iy in range(maxi(0, int(bb.position.y / res)), mini(h - 1, int(ceil(bb.end.y / res))) + 1):
				for ix in range(maxi(0, int(bb.position.x / res)), mini(w - 1, int(ceil(bb.end.x / res))) + 1):
					if Geometry2D.is_point_in_polygon(Vector2(ix * res, iy * res), poly):
						var j := iy * w + ix
						out[j] = up
						covered[j] = maxf(covered[j], fill_born[i])
		else:
			_stamp_disk(out, w, h, res, cell_center(i), 0.12, fill_proud(time - fill_born[i]), false)
			_stamp_disk(covered, w, h, res, cell_center(i), 0.1, fill_born[i], false)
	# Paint stands a hair proud where it is left (not under a patch or fill); cracks still cut through it.
	var half_w := paint_width * 0.5
	var painted := PackedByteArray()
	if not paint_lines.is_empty():
		painted.resize(w * h)
	for k in range(0, paint_lines.size() - 1, 2):
		var a := paint_lines[k]
		var b := paint_lines[k + 1]
		var x0 := maxi(0, int((minf(a.x, b.x) - half_w) / res))
		var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + half_w) / res)))
		var y0 := maxi(0, int((minf(a.y, b.y) - half_w) / res))
		var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + half_w) / res)))
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1e-10)
		for iy in range(y0, y1 + 1):
			for ix in range(x0, x1 + 1):
				var q := Vector2(ix * res, iy * res)
				var j := iy * w + ix
				if painted[j] == 0 and covered[j] <= paint_born and q.distance_to(a + ab * clampf((q - a).dot(ab) / len2, 0.0, 1.0)) <= half_w:
					out[j] += paint_thickness * paint_left(q)
					painted[j] = 1
	# Filled cracks: the sealant fills the crack flush and the overband stands a little proud, until it debonds.
	var surface := PackedFloat32Array(out)
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or not c.sealed(time):
			continue
		for k in c.pts.size() - 1:
			var half := 0.03 + c.width(k, c.seal_from)
			var a := c.pts[k]
			var b := c.pts[k + 1]
			var x0 := maxi(0, int((minf(a.x, b.x) - half) / res))
			var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + half) / res)))
			var y0 := maxi(0, int((minf(a.y, b.y) - half) / res))
			var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + half) / res)))
			var ab := b - a
			var len2 := maxf(ab.length_squared(), 1e-10)
			for iy in range(y0, y1 + 1):
				for ix in range(x0, x1 + 1):
					var q := Vector2(ix * res, iy * res)
					var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
					if q.distance_to(a + ab * t) <= half:
						var j := iy * w + ix
						out[j] = maxf(out[j], surface[j] + SEAL_PROUD)
	# Open cracks.
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or c.sealed(time):
			continue
		for k in c.pts.size() - 1:
			var cw := c.width(k, time)
			var depth := crack_depth(cw)
			var half := cw * 0.5
			var spall := (minf(cw * 2.2 + 0.008, 0.06) * 0.5) if cw > 0.005 else 0.0
			var reach := maxf(maxf(half, spall), res * 0.75)
			var a := c.pts[k]
			var b := c.pts[k + 1]
			var x0 := maxi(0, int((minf(a.x, b.x) - reach) / res))
			var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + reach) / res)))
			var y0 := maxi(0, int((minf(a.y, b.y) - reach) / res))
			var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + reach) / res)))
			var ab := b - a
			var len2 := maxf(ab.length_squared(), 1e-10)
			for iy in range(y0, y1 + 1):
				for ix in range(x0, x1 + 1):
					var q := Vector2(ix * res, iy * res)
					var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
					var d := q.distance_to(a + ab * t)
					var v := 0.0
					if d <= maxf(half, res * 0.5):
						v = -depth * minf(1.0, cw / res)   # narrower than a grid step: a shallower dip
					elif d <= spall:
						v = -spall_depth * (1.0 - (d - half) / maxf(spall - half, 1e-4))
					var j := iy * w + ix
					if v < out[j] and c.born[k + 1] > covered[j]:
						out[j] = v
	# Potholes: whole crocodile cells plucked out, steep-sided, down to the hole's depth; a disk where no cell is.
	for k in plucked.size():
		if plucked[k] <= 0.0 or net_cells[k].is_empty():
			continue
		var poly := net_cells[k]
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		for iy in range(maxi(0, int(bb.position.y / res)), mini(h - 1, int(ceil(bb.end.y / res))) + 1):
			for ix in range(maxi(0, int(bb.position.x / res)), mini(w - 1, int(ceil(bb.end.x / res))) + 1):
				var q := Vector2(ix * res, iy * res)
				if Geometry2D.is_point_in_polygon(q, poly):
					var j := iy * w + ix
					out[j] = minf(out[j], -plucked[k])
	for i in nx * ny:
		if hole[i] > 0.0 and (_cell_seed[i] < 0):
			_stamp_disk(out, w, h, res, cell_center(i), 0.1, -hole[i], true)
	# Ease the outer edge back to 0.
	var n := int(edge_feather / res)
	if n > 0:
		for iy in h:
			for ix in w:
				var e := mini(mini(ix, w - 1 - ix), mini(iy, h - 1 - iy))
				if e < n:
					out[iy * w + ix] *= smoothstep(0.0, 1.0, float(e) / n)
	return out


func _stamp_disk(out: PackedFloat32Array, w: int, h: int, res: float, c: Vector2, r: float, v: float, down: bool) -> void:
	var x0 := maxi(0, int((c.x - r) / res))
	var x1 := mini(w - 1, int(ceil((c.x + r) / res)))
	var y0 := maxi(0, int((c.y - r) / res))
	var y1 := mini(h - 1, int(ceil((c.y + r) / res)))
	for iy in range(y0, y1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(ix * res, iy * res).distance_to(c)
			if d > r:
				continue
			# Steep broken walls: full depth inside 70 % of the radius.
			var hv := v * smoothstep(r, r * 0.7, d)
			var j := iy * w + ix
			if down:
				out[j] = minf(out[j], hv)
			else:
				out[j] = maxf(out[j], hv)
