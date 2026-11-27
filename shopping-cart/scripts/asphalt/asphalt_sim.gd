class_name AsphaltSim
extends AsphaltSimHeight
## A 2D (top-down) simulation of an asphalt road section ageing and being repaired, year by year.
##
## The section runs along +Y (direction of travel) and across X, in metres: a gravel shoulder each side, two
## lanes meeting at a longitudinal construction joint, and two wheel paths per lane where the traffic load goes.
## It follows the Austroads crack types in the project's "Asphalt Cracking Quick Guide":
##   - oxidation and UV harden and grey the surface, then the aggregate starts to ravel out
##   - transverse (thermal) cracks run across the road, spaced closer as the binder hardens
##   - the lane joint opens into a longitudinal crack early on
##   - traffic fatigue builds in the wheel paths (faster on thin or poorly built pavement, and on wet,
##     weak subgrade); it starts as longitudinal wheel-path cracks that branch into fatigue ("alligator") cells
##   - old, hard binder shrinks into block cracking off the long cracks
##   - edge cracking and fretting where the pavement meets an unsealed shoulder
##   - slippage crescents where the wearing course is poorly bonded
##   - water through open cracks (freeze-thaw) wears the base until potholes break out and grow
##   - after a surface seal or an overlay the old cracks and patch edges come back as reflection cracks
## Repairs: crack filling (overbanded sealant), throw-and-roll pothole fill (which tends to fail again), saw-cut
## heavy patches (whose seams crack later), a surface seal, and cold planing plus an asphalt overlay.
##
## The state is vector data (crack polylines, patch rectangles) plus a 10 cm cell grid; AsphaltCanvas draws it.
## The simulation is deterministic for a seed and the list of repairs, so scrubbing back in time just replays it.
##
## The class is split by concern, each file extending the one before: asphalt_sim_state.gd (settings, state,
## queries), asphalt_sim_cracks.gd (crack geometry), asphalt_sim_networks.gd (crack networks), asphalt_sim_rules.gd
## (the placeholder damage rules), asphalt_sim_repairs.gd, asphalt_sim_height.gd (bake_height), and this file: the
## timeline (reset, step, seek, repairs as events).


func _ready() -> void:
	reset()


## Rebuild the road as new at year 0 (repairs in `events` are replayed as time passes).
func reset() -> void:
	_rng.seed = seed
	time = 0.0
	surface_born = 0.0
	paint_born = 0.0
	rut_born = 0.0
	cracks.clear()
	patches.clear()
	seal_spots.clear()
	log_lines.clear()
	_latent.clear()
	_transverse_y.clear()
	_last = { }
	_next_event = 0
	_seal_check = INF
	nx = int(round(size.x / CELL))
	ny = int(round(size.y / CELL))
	var n := nx * ny
	for a in [weak, pond, load, fatigue, damage, hole, crack_len, open_len, fill_depth]:
		a.resize(n)
		a.fill(0.0)
	fill_born.resize(n)
	fill_born.fill(-1.0)
	patch_of.resize(n)
	patch_of.fill(-1)
	edge_l.resize(ny)
	edge_l.fill(0.0)
	edge_r.resize(ny)
	edge_r.fill(0.0)
	gx = int(round(size.x / GRID))
	gy = int(round(size.y / GRID))
	occ.resize(gx * gy)
	occ.fill(0)
	occ_pt.resize(gx * gy)
	occ_pt.fill(0)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.35
	noise.fractal_octaves = 3
	var grade := FastNoiseLite.new()
	grade.seed = seed + 101
	grade.frequency = 0.25
	_mix_low.seed = seed + 202
	_mix_low.frequency = 1.0
	_mix_low.fractal_octaves = 2
	_mix_fine.seed = seed + 303
	_mix_fine.frequency = 1.0 / maxf(aggregate_size, 0.002)
	_mix_fine.fractal_octaves = 1
	for cy in ny:
		for cx in nx:
			var i := cy * nx + cx
			var p := Vector2(cx + 0.5, cy + 0.5) * CELL
			weak[i] = clampf(0.5 + 0.9 * noise.get_noise_2d(p.x * 10.0, p.y * 10.0), 0.0, 1.0)
			pond[i] = clampf((grade.get_noise_2d(p.x, p.y) - 0.15) * 2.5, 0.0, 1.0)
			var l := 0.06
			for w in wheel_paths:
				l += exp(-pow((p.x - w) / wheel_path_width, 2.0))
			load[i] = l if paved(p) else 0.0
	_wheel_cells.clear()
	for i in nx * ny:
		if load[i] >= 0.25:
			_wheel_cells.append(i)
	_build_networks()
	changed.emit()


## Run the simulation forward to year t (repairs made at t included).
func advance_to(t: float) -> void:
	var stepped := false
	while time + DT * 0.5 <= t:
		_step()
		stepped = true
	if _apply_due() or stepped:
		changed.emit()


## Do the repairs that are due now; true if there were any.
func _apply_due() -> bool:
	var any := false
	while _next_event < events.size() and events[_next_event].t <= time + DT * 0.25:
		_apply(events[_next_event].action)
		_next_event += 1
		any = true
	return any


## Show the road at year t (replays from year 0 when going back).
func seek(t: float) -> void:
	if t < time - DT * 0.5:
		reset()
	advance_to(t)


## Do a repair now and remember it, so it is replayed when scrubbing. Later repairs are dropped (a new timeline).
func do_action(action: int) -> void:
	_apply_due()
	while events.size() > _next_event:
		events.pop_back()
	events.append({ t = time, action = action })
	_next_event = events.size()
	_apply(action)
	changed.emit()


## Turn one kind of repair on (done at year t) or off, and replay to the current year. Each kind is done at most once.
func set_repair(action: int, on: bool, t: float) -> void:
	for k in range(events.size() - 1, -1, -1):
		if events[k].action == action:
			events.remove_at(k)
	if on:
		events.append({ t = t, action = action })
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	var now := time
	reset()
	advance_to(now)


## The year the repair kind is done at, or -1 if it is off.
func repair_year(action: int) -> float:
	for e in events:
		if e.action == action:
			return e.t
	return -1.0


func _step() -> void:
	_apply_due()
	if auto_maintain:
		_auto_maintain()
	var age := surface_age()
	var ox := 1.0 - exp(-age * climate / oxidation_years)
	_fatigue_and_water(ox)
	_initiate(age, ox)
	for i in cracks.size():
		var c := cracks[i]
		if c.alive and c.growing and not c.sealed(time):
			_grow(i, c.speed * DT * (0.6 + 0.4 * climate))
	_reflect()
	_edges(age)
	time += DT
	if time >= _seal_check:
		_seal_check = INF
		_rebuild_lengths()
