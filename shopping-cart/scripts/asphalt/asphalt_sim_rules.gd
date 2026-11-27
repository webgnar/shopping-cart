class_name AsphaltSimRules
extends AsphaltSimNetworks
## AsphaltSim, part 4 of 7: the damage rules. PLACEHOLDERS: fatigue, water damage and potholes, when each kind of
## crack starts, edge fretting and slippage are hand-tuned rules, not sourced models (docs/ASPHALT_SCIENCE.md). They
## are replaced one by one by sourced models; nothing new is added here.


func _fatigue_and_water(ox: float) -> void:
	# A wheel bends the layer harder the thinner it is (Westergaard: stress ~ load / thickness^2).
	var k_f := 0.085 * traffic / structure * pow(REF_THICKNESS / thickness(), 2.0)
	var k_d := 0.6 * drainage * climate
	for i in nx * ny:
		if load[i] <= 0.0:
			continue
		# Water in the base: through open cracks, and standing in low spots.
		var wet := (clampf(open_len[i] / 0.1, 0.0, 2.0) + pond[i] * ponding) * drainage
		# Traffic fatigue: wheel load on a weak, wet base, worse once the binder is brittle.
		var f_rate := k_f * load[i] * (0.55 + 0.9 * weak[i]) * (1.0 + 0.6 * wet) * (0.8 + 0.4 * ox)
		if patch_of[i] >= 0:
			f_rate *= 0.6     # new full-depth base
		fatigue[i] += DT * f_rate
		# Water damage: water through open cracks softens the base and freeze-thaw pumps it out.
		if open_len[i] > 0.0 or pond[i] > 0.0 or hole[i] > 0.0 or fill_born[i] >= 0.0:
			# Only broken-up (fatigue-cracked) asphalt lets the wheels pump the base out through it.
			var broken := clampf((fatigue[i] - 1.4) / 0.6, 0.0, 1.5)
			# Potholes need all three: water getting in (open cracks, standing water), a structure already broken up,
			# and wheels to pump it.
			var water := maxf(open_len[i] - 0.05, 0.0) + 0.06 * pond[i] * ponding
			var d_rate := k_d * water * (0.3 + load[i]) * (0.4 + weak[i]) * broken
			if fill_born[i] >= 0.0:
				d_rate += 0.12 * climate * drainage * (0.4 + load[i])   # cold mix ravels out of the hole
			damage[i] += DT * d_rate
	# Potholes break out where the water damage is done, then deepen and eat into their neighbours.
	for i in nx * ny:
		if load[i] <= 0.0:
			continue
		if hole[i] > 0.0:
			hole[i] = minf(HOLE_MAX, hole[i] + DT * 0.03 * (0.5 + load[i]) * climate)
			_pluck(i)
			var cx := i % nx
			var cy := i / nx
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x := cx + o.x
				var y := cy + o.y
				if x < 0 or y < 0 or x >= nx or y >= ny:
					continue
				var j := y * nx + x
				if load[j] > 0.0 and patch_of[j] == patch_of[i] and crack_len[j] > 0.02:
					damage[j] += DT * 0.18 * (0.3 + load[j]) * climate * drainage * (0.5 + weak[j])
		elif damage[i] >= 1.0:
			hole[i] = 0.012
			_pluck(i)


func _initiate(age: float, ox: float) -> void:
	var px0 := shoulder
	var px1 := size.x - shoulder
	# Transverse (thermal) cracks: once the binder hardens, cold snaps crack it across. Each crack relieves the
	# shrinkage stress for a stretch either side, so a new one opens in the middle of the longest uncracked stretch,
	# once that is long enough; the spacing shrinks as the binder hardens.
	if age > 1.5:
		var rate := 0.8 * climate * ox * (1.4 - 0.4 * structure)
		if _rng.randf() < rate * DT:
			# Colder climates and thinner pavement crack closer together.
			var ts := thermal_spacing()
			var spacing := lerpf(ts.x, ts.y, ox) * sqrt(structure) / sqrt(maxf(climate, 0.25))
			var ys := PackedFloat32Array(_transverse_y)
			ys.sort()
			# The section is part of a longer road: its ends count as half a spacing from the last crack.
			var prev := -spacing * 0.5
			var best_gap := 0.0
			var best_y := -1.0
			ys.append(size.y + spacing * 0.5)
			for y in ys:
				if y - prev > best_gap:
					best_gap = y - prev
					best_y = (prev + y) * 0.5 + _rng.randf_range(-0.2, 0.2) * (y - prev)
				prev = y
			if best_gap > 1.6 * spacing and best_y > 0.2 and best_y < size.y - 0.2:
				_transverse_y.append(best_y)
				var x := _rng.randf_range(px0 + 0.3, px1 - 0.3)
				_twin(Kind.TRANSVERSE, Vector2(x, best_y), 0.0, 0.12, 0.08, 3.5, 1.3)
	# The lane joint: the paving seam opens early.
	if age > 0.8 and _rng.randf() < 0.45 * climate * DT:
		var y := _rng.randf_range(0.2, size.y - 0.2)
		var p := Vector2(lane_joint_x + _rng.randf_range(-0.02, 0.02), y)
		if _free(p, 0.15):
			_twin(Kind.JOINT, p, PI * 0.5, 0.05, 0.35, 1.2, 1.0)
	# Wheel-path cracks where fatigue has built up, branching into alligator cells as it goes on.
	for i in _wheel_cells:
		var f := fatigue[i]
		if f < 1.0 or crack_len[i] >= 0.01:
			continue
		var p := cell_center(i) + Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * CELL
		if not paved(p):
			continue
		if _rng.randf() < DT * 0.2 * (f - 0.9) and _free(p, 0.08):
			var c := _twin(Kind.WHEELPATH, p, PI * 0.5, 0.2, 0.12, 0.5 + 0.3 * f, 0.9)
			for k in [c, c - 1]:
				cracks[k].max_len = _rng.randf_range(0.8, 2.5)
	# Fatigue (crocodile) cells in the wheel paths and block cracking across the road: edges of the networks open.
	_open_edges(age, ox)
	# Edge cracking near the unsealed shoulders.
	if unsealed_edges and age > 3.0:
		var rate := 0.5 * traffic * climate * drainage / structure * clampf((age - 3.0) / 6.0, 0.0, 1.0)
		if _rng.randf() < rate * DT:
			var left := _rng.randf() < 0.5
			var y := _rng.randf_range(0.2, size.y - 0.2)
			var row := clampi(int(y / CELL), 0, ny - 1)
			var x := shoulder + edge_l[row] + 0.03 if left else size.x - shoulder - edge_r[row] - 0.03
			var inward := 0.0 if left else PI
			var along := PI * 0.5 if _rng.randf() < 0.5 else -PI * 0.5
			var d := lerp_angle(inward, along, _rng.randf_range(0.3, 0.6))
			_crack(Kind.EDGE, Vector2(x, y), d, along, 0.25, 0.06, 0.7, _rng.randf_range(0.4, 1.6), 1.4)
	# Slippage: crescents in sets where the wearing course slides on a poor bond.
	if age > 1.0 and bond < 0.95:
		if _rng.randf() < 0.25 * (1.0 - bond) * (1.0 - bond) * traffic * DT * 4.0:
			_slippage()


func _slippage() -> void:
	var w := wheel_paths[_rng.randi_range(0, wheel_paths.size() - 1)]
	var y := _rng.randf_range(0.8, size.y - 0.8)
	# Lanes left of the joint travel -Y, right of it +Y; crescents point the way the wheels shove the mat.
	var fwd := -1.0 if w < lane_joint_x else 1.0
	var r := _rng.randf_range(0.35, 0.7)
	var span := _rng.randf_range(1.6, 2.3)
	var n := _rng.randi_range(2, 4)
	for k in n:
		var centre := Vector2(w, y - fwd * k * _rng.randf_range(0.08, 0.14))
		var c := _new_crack(Kind.SLIPPAGE, centre)
		c.growing = false
		c.widen = 0.6
		r *= _rng.randf_range(0.85, 1.15)
		var a0 := (PI * 0.5 if fwd > 0 else -PI * 0.5) - span * 0.5
		var steps := int(r * span / STEP)
		for s in steps + 1:
			var a := a0 + span * s / steps
			var q := centre - Vector2(0, fwd * r * 0.6) + Vector2(cos(a), sin(a)) * Vector2(r, r * 0.6) \
				+ Vector2(_rng.randf_range(-0.012, 0.012), _rng.randf_range(-0.012, 0.012))
			if not paved(q):
				continue
			c.pts.append(q)
			c.born.append(time)
		if c.pts.size() > 3:
			for j in c.pts.size() - 1:
				c.length += c.pts[j].distance_to(c.pts[j + 1])
			_add_points(c, cracks.size(), 0)
			cracks.append(c)


func _edges(age: float) -> void:
	if not unsealed_edges or age < 4.0:
		return
	# Fretting: traffic on the unsupported edge breaks it off into the shoulder, row by row.
	var k := 0.025 * traffic * climate * drainage / structure * clampf((age - 4.0) / 6.0, 0.0, 1.0)
	for row in ny:
		var y := (row + 0.5) * CELL
		for side in 2:
			var e: PackedFloat32Array = edge_l if side == 0 else edge_r
			var x := shoulder + e[row] + 0.05 if side == 0 else size.x - shoulder - e[row] - 0.05
			var i := cell_index(Vector2(x, y))
			var rate := k * (0.3 + 1.4 * weak[i]) * (1.0 + 2.0 * clampf(open_len[i] / 0.1, 0.0, 1.0))
			if _rng.randf() < 0.3:
				e[row] = minf(e[row] + rate * DT * _rng.randf_range(1.0, 4.0), 0.6)
	# Edge loss of neighbouring rows pulls each other a little (no single-row notches).
	for side in 2:
		var e: PackedFloat32Array = edge_l if side == 0 else edge_r
		for row in range(1, ny - 1):
			e[row] = maxf(e[row], (e[row - 1] + e[row + 1]) * 0.5 - 0.02)
