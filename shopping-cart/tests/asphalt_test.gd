extends SceneTree
## Headless checks for the 2D asphalt lab (AsphaltSim and the lab scene). Run from the Godot project folder:
##   godot --headless -s res://tests/asphalt_test.gd

const LAB := preload("res://scenes/asphalt/asphalt_lab.tscn")
const K := AsphaltSim.Kind
const A := AsphaltSim.Action

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("%-5s %-34s %s" % ["PASS" if ok else "FAIL", name, detail])


func _sim(events := [], seed := 1) -> AsphaltSim:
	var sim := AsphaltSim.new()
	sim.seed = seed
	for e: Array in events:
		sim.events.append({ t = e[0], action = e[1] })
	sim.reset()
	return sim


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		a += poly[k].cross(poly[(k + 1) % poly.size()])
	return a * 0.5


func _near(pts: PackedVector2Array, p: Vector2, r: float) -> bool:
	for q in pts:
		if q.distance_squared_to(p) < r * r:
			return true
	return false


## Whether p is within r of the polyline (a crack can join another between its points).
func _near_line(pts: PackedVector2Array, p: Vector2, r: float) -> bool:
	for i in range(1, pts.size()):
		if Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i]).distance_squared_to(p) < r * r:
			return true
	return false


func _holes(sim: AsphaltSim) -> int:
	var n := 0
	for i in sim.nx * sim.ny:
		if sim.hole[i] > 0.0:
			n += 1
	return n


func _run() -> void:
	# Ageing without repairs.
	var sim := _sim()
	var s5: Dictionary
	var s10: Dictionary
	var s15: Dictionary
	sim.advance_to(5.0)
	s5 = sim.stats()
	sim.advance_to(10.0)
	s10 = sim.stats()
	sim.advance_to(15.0)
	s15 = sim.stats()
	var t0 := Time.get_ticks_msec()
	sim.advance_to(24.0)
	var s24 := sim.stats()
	_check("cracks spread with age", s5.crack_m < s10.crack_m and s10.crack_m < s15.crack_m and s15.crack_m < s24.crack_m,
		"%.0f, %.0f, %.0f, %.0f m at 5, 10, 15, 24 years" % [s5.crack_m, s10.crack_m, s15.crack_m, s24.crack_m])
	_check("condition falls with age", s5.pci > s10.pci and s10.pci > s15.pci and s15.pci > s24.pci,
		"%.0f, %.0f, %.0f, %.0f" % [s5.pci, s10.pci, s15.pci, s24.pci])
	_check("no potholes in the first 10 years", s10.potholes == 0 and s5.potholes == 0, "%d" % s10.potholes)
	_check("potholes by year 24 unmaintained", s24.potholes > 0, "%d potholes" % s24.potholes)
	_check("fatigue cells in the wheel paths", s24.alligator_pct > 3.0, "%.1f %%" % s24.alligator_pct)

	# Every crack type from the guide turns up somewhere (poor bond for slippage).
	var weak := _sim([], 3)
	weak.bond = 0.3
	weak.reset()
	weak.advance_to(22.0)
	var kinds: PackedFloat32Array = weak.stats().by_kind
	for k in [K.TRANSVERSE, K.JOINT, K.WHEELPATH, K.FATIGUE, K.BLOCK, K.EDGE, K.SLIPPAGE]:
		_check("crack type: " + AsphaltSim.KIND_NAMES[k], kinds[k] > 0.0, "%.1f m" % kinds[k])
	var fretted := 0.0
	for e in weak.edge_l:
		fretted = maxf(fretted, e)
	_check("edge frets into the shoulder", fretted > 0.05, "%.2f m at worst" % fretted)

	# Thin pavement fails sooner than a strong one.
	var thin := _sim([], 1)
	thin.structure = 0.6
	thin.reset()
	thin.advance_to(12.0)
	var strong := _sim([], 1)
	strong.structure = 1.3
	strong.reset()
	strong.advance_to(12.0)
	_check("thin pavement fails sooner", thin.stats().pci < strong.stats().pci,
		"%.0f vs %.0f at year 12" % [thin.stats().pci, strong.stats().pci])

	# Deterministic, and scrubbing back replays the same road.
	var again := _sim()
	again.advance_to(15.0)
	_check("same seed, same road", again.cracks.size() == _sim_at(15.0).cracks.size() and is_equal_approx(again.stats().crack_m, s15.crack_m),
		"%d cracks" % again.cracks.size())
	sim.seek(15.0)
	_check("seek back replays", is_equal_approx(sim.stats().crack_m, s15.crack_m), "%.1f m" % sim.stats().crack_m)
	_check("30 years simulate quickly", Time.get_ticks_msec() - t0 < 4000, "years 15-24 in %d ms" % (Time.get_ticks_msec() - t0))
	# Lot sections butt onto more pavement: no shoulder, so no edge cracks or fretting.
	var lot := _sim([], 3)
	lot.shoulder = 0.0
	lot.unsealed_edges = false
	lot.reset()
	lot.advance_to(22.0)
	var lot_fret := 0.0
	for i in lot.ny:
		lot_fret = maxf(lot_fret, maxf(lot.edge_l[i], lot.edge_r[i]))
	_check("sealed edges don't crack or fret", lot.stats().by_kind[K.EDGE] == 0.0 and lot_fret == 0.0,
		"%.1f m edge cracks, %.2f m fretted" % [lot.stats().by_kind[K.EDGE], lot_fret])

	# Potholes pluck out whole crocodile cells, and the height map carries real depths.
	var h18 := _sim_at(18.0)
	var plucked := 0
	for d in h18.plucked:
		if d > 0.0:
			plucked += 1
	_check("potholes pluck crocodile cells", plucked > 0, "%d cells" % plucked)
	var hm := h18.bake_height(0.02)
	var hw := int(round(h18.size.x / 0.02)) + 1
	var deepest := 0.0
	for v in hm:
		deepest = minf(deepest, v)
	var joint := 0.0     # the lane joint crack, between the wheel paths where there is no rut
	for row in hw:
		for col in range(245, 256):
			joint = minf(joint, hm[row * hw + col])
	var mid_row := (hw / 2) * hw
	_check("height map: holes and cracks cut in", deepest < -0.02 and joint < -0.004,
		"deepest %.0f mm, lane joint %.1f mm" % [deepest * 1000.0, joint * 1000.0])
	_check("height map: shoulders low, edges flush", is_equal_approx(hm[mid_row + 20], h18.shoulder_drop) and hm[mid_row] == 0.0,
		"%.3f m at 0.4 m in, %.3f m at the edge" % [hm[mid_row + 20], hm[mid_row]])

	# Crack filling: no water in, no widening while the sealant holds.
	var cf := _sim([[10.0, A.CRACK_FILL]])
	cf.advance_to(9.8)   # a repair made at year 10 is already done at year 10
	var open_before: float = cf.stats().crack_m
	cf.advance_to(10.2)
	var sealed: AsphaltSim.Crack = null
	for c in cf.cracks:
		if c.seal_from >= 0.0:
			sealed = c
			break
	_check("crack fill seals the open cracks", cf.stats().crack_m < open_before * 0.5 and sealed != null,
		"open %.0f -> %.0f m" % [open_before, cf.stats().crack_m])
	if sealed:
		var w0 := sealed.width(0, 10.2)
		var w1 := sealed.width(0, 14.0)
		var w2 := sealed.width(0, 20.0)
		_check("sealed crack stops opening", is_equal_approx(w0, w1) and w2 > w1, "%.1f, %.1f, %.1f mm" % [w0 * 1000, w1 * 1000, w2 * 1000])

	# Pothole fill.
	var pf := _sim()
	pf.advance_to(20.0)
	var before := _holes(pf)
	pf.do_action(A.POTHOLE_FILL)
	var filled := 0
	for i in pf.nx * pf.ny:
		if pf.fill_born[i] >= 0.0:
			filled += 1
	_check("pothole fill fills every hole", before > 0 and _holes(pf) == 0 and filled == before, "%d cells filled" % filled)
	# Repairs bring the surface back up: nothing under a fill or a new patch sits below the road.
	var fh := pf.bake_height(0.02)
	var fill_low := 1.0
	for i in pf.nx * pf.ny:
		if pf.fill_born[i] >= 0.0:
			var fc := pf.cell_center(i)
			fill_low = minf(fill_low, fh[int(round(fc.y / 0.02)) * 501 + int(round(fc.x / 0.02))])
	_check("pothole fill comes back up", fill_low > 0.0, "lowest fill centre %.1f mm" % (fill_low * 1000.0))
	pf.advance_to(22.6)
	var joints := 0
	for c in pf.cracks:
		if c.alive and c.kind == AsphaltSim.Kind.SEAM:
			joints += 1
	_check("cold patch joints open into seams", joints > 0, "%d seam cracks 2.6 years on" % joints)
	pf.advance_to(24.0)
	_check("throw-and-roll fails again", _holes(pf) > 0, "%d hole cells 4 years on" % _holes(pf))

	# Heavy patch: cracks dug out inside, seams crack open later.
	var hp := _sim()
	hp.advance_to(16.4)
	hp.do_action(A.HEAVY_PATCH)
	var inside := 0
	for c in hp.cracks:
		if not c.alive:
			continue
		for q in c.pts:
			for p in hp.patches:
				if (p.rect as Rect2).grow(-0.01).has_point(q):
					inside += 1
	_check("heavy patch made", hp.patches.size() > 0, "%d patches" % hp.patches.size())
	_check("heavy patches stay small", hp.stats().patched_pct < 12.0, "%.1f %% of the road" % hp.stats().patched_pct)
	var ph := hp.bake_height(0.02)
	var patch_low := 1.0
	for p in hp.patches:
		var r: Rect2 = (p.rect as Rect2).grow(-0.02)   # the edge row can be a pothole just outside it
		for iy in range(int(ceil(r.position.y / 0.02)), int(r.end.y / 0.02) + 1):
			for ix in range(int(ceil(r.position.x / 0.02)), int(r.end.x / 0.02) + 1):
				patch_low = minf(patch_low, ph[iy * 501 + ix])
	_check("new patch is level", patch_low >= 0.0, "lowest %.1f mm" % (patch_low * 1000.0))
	_check("no cracks inside a new patch", inside == 0, "%d points inside" % inside)
	hp.advance_to(24.0)
	_check("patch seams crack", hp.stats().by_kind[K.SEAM] > 0.5, "%.1f m" % hp.stats().by_kind[K.SEAM])

	# Overlay: a clean surface, then the old cracks reflect through.
	var ov := _sim()
	ov.advance_to(16.0)
	ov.do_action(A.OVERLAY)
	_check("overlay buries the cracks", ov.stats().crack_m == 0.0 and ov.surface_age() == 0.0, "%.0f m" % ov.stats().crack_m)
	ov.advance_to(22.0)
	_check("reflection cracks come back", ov.stats().by_kind[K.REFLECTION] > 1.0, "%.1f m" % ov.stats().by_kind[K.REFLECTION])

	# Paint: stall lines stand a hair proud, wear fastest in the wheel paths, and are repainted with an overlay.
	var pt := _sim()
	pt.paint_lines = PackedVector2Array([Vector2(0.8, 5.03), Vector2(9.2, 5.03)])
	pt.reset()
	pt.advance_to(0.2)
	var ph0 := pt.bake_height(0.02)
	var fresh := ph0[int(round(5.03 / 0.02)) * 501 + int(round(5.0 / 0.02))]
	_check("fresh paint stands proud", fresh > 0.0006 and fresh < 0.001, "%.2f mm" % (fresh * 1000.0))
	pt.advance_to(8.0)
	var in_path := 0.0
	var off_path := 0.0
	for x in [1.95, 3.75, 6.25, 8.05]:
		in_path += pt.paint_left(Vector2(x, 5.03)) / 4.0
	for x in [1.0, 2.85, 7.15, 9.0]:
		off_path += pt.paint_left(Vector2(x, 5.03)) / 4.0
	_check("paint wears in the wheel paths", in_path < off_path - 0.2, "%.2f left in the wheel paths, %.2f between" % [in_path, off_path])
	pt.do_action(A.REPAINT)
	_check("repaint makes the lines fresh", pt.paint_left(Vector2(1.95, 5.03)) == 1.0, "%.2f" % pt.paint_left(Vector2(1.95, 5.03)))
	pt.advance_to(12.0)
	pt.do_action(A.OVERLAY)
	_check("overlay repaints the lines", pt.paint_left(Vector2(1.95, 5.03)) == 1.0, "%.2f" % pt.paint_left(Vector2(1.95, 5.03)))

	# Crack paths and junctions (from the material, not a fixed recipe).
	var mx := _sim()
	mx.advance_to(18.0)
	var on_crack := 0.0
	var n_on := 0
	var branches := 0
	for c in mx.cracks:
		if not c.alive or c.guide.size() > 0 or c.kind == K.SLIPPAGE:
			continue
		for q in c.pts:
			on_crack += mx.mix_weakness(q)
			n_on += 1
		if c.parent >= 0:
			branches += 1
	var anywhere := 0.0
	var rng := RandomNumberGenerator.new()
	for i in 4000:
		anywhere += mx.mix_weakness(Vector2(rng.randf_range(0.0, 10.0), rng.randf_range(0.0, 10.0)))
	on_crack /= maxf(n_on, 1)
	anywhere /= 4000.0
	_check("cracks follow the weaker mix", on_crack > anywhere + 0.03, "%.2f on cracks, %.2f anywhere" % [on_crack, anywhere])
	_check("cracks branch", branches > 5, "%d branches" % branches)
	# Junctions over four seeds. Shrinkage cracks (transverse, lane joint) meet at 90 +- 15 degrees (Shorlin et
	# al. 1999); fatigue pieces are "many-sided, sharp-angled" (LTPP DIM, ACP 1), with no measured angle to hold them to.
	var jn := _junctions(mx)
	for sd in [2, 3, 4]:
		var more := _sim([], sd)
		more.advance_to(24.0)
		var m2 := _junctions(more)
		for key in ["shrink", "fatigue", "other"]:
			jn[key].append_array(m2[key])
		jn.seam += m2.seam
		jn.ends += m2.ends
		more.free()
	var shrink_mean := _mean(jn.shrink)
	_check("shrinkage cracks meet about square on", jn.shrink.size() >= 20 and shrink_mean > 75.0,
		"mean %.0f degrees at %d junctions (fatigue cracks: %.0f at %d)" % [shrink_mean, jn.shrink.size(), _mean(jn.fatigue), jn.fatigue.size()])
	# The LTPP survey keeps the manual's rules (DIM, FHWA-HRT-13-092).
	var sv := AsphaltSurvey.take(mx)
	var rules_ok := true
	var why := ""
	for a in sv.areas:
		if a.type == 8 and a.counted:
			var rect: Rect2 = a.rect
			var band := "L" if a.depth < 0.025 else ("M" if a.depth <= 0.05 else "H")
			if minf(rect.size.x, rect.size.y) < 0.15 or a.area < 0.02 or a.severity != band:
				rules_ok = false
				why = "pothole %s %.2f x %.2f m, %.0f mm" % [a.code, rect.size.x, rect.size.y, a.depth * 1000.0]
	for l in sv.lines:
		if l.counted and l.type != 16 and l.length < 0.3 and l.type != 6:
			rules_ok = false
			why = "%s only %.2f m" % [l.code, l.length]
	var fatigue_m2 := 0.0
	for lane in 2:
		for v in sv.totals_for(lane)["1"]:
			fatigue_m2 += v
	_check("LTPP survey keeps the manual's rules", rules_ok and fatigue_m2 > 0.0,
		"%.1f m2 fatigue, %d areas, %d lines %s" % [fatigue_m2, sv.areas.size(), sv.lines.size(), why])
	var joined: int = jn.shrink.size() + jn.fatigue.size() + jn.other.size() + jn.seam
	var share := float(joined) / maxf(jn.ends, 1)
	_check("not every crack ends at a T", share > 0.3 and share < 0.9, "%d of %d ends join another crack" % [joined, jn.ends])
	var wide_far := _sim()
	# A slippery base (a quarter of the cohesion and friction): the cracks space out about 4x wider.
	wide_far.buildup = wide_far.pavement().duplicate(true)
	wide_far.buildup.base().cohesion *= 0.25
	wide_far.buildup.base().friction_tan *= 0.25
	wide_far.reset()
	wide_far.advance_to(18.0)
	_check("thermal spacing sets the cross cracks", wide_far.stats().by_kind[K.TRANSVERSE] < mx.stats().by_kind[K.TRANSVERSE],
		"%.1f m on a slippery base, %.1f m at the default" % [wide_far.stats().by_kind[K.TRANSVERSE], mx.stats().by_kind[K.TRANSVERSE]])
	# Standing water: more potholes where the lot holds water.
	var dry := _sim()
	dry.ponding = 0.0
	dry.reset()
	dry.advance_to(20.0)
	var wet := _sim()
	wet.ponding = 2.0
	wet.reset()
	wet.advance_to(20.0)
	_check("standing water makes more potholes", _holes(wet) > _holes(dry), "%d hole cells wet, %d dry" % [_holes(wet), _holes(dry)])
	# Spot sealcoat: a few black spots over the roughest areas; a coat only, so the cracks stay; wears off the
	# wheel paths first.
	var cs := _sim()
	cs.advance_to(16.0)
	var cracked: float = cs.stats().crack_m
	cs.do_action(A.SURFACE_SEAL)
	var spot_area := 0.0
	for sp in cs.seal_spots:
		spot_area += absf(_area(sp.poly))
	_check("spot sealcoat lays a few spots", cs.seal_spots.size() == cs.sealcoat_spots and spot_area > 3.0 and spot_area < 40.0,
		"%d spots, %.1f m2" % [cs.seal_spots.size(), spot_area])
	_check("sealcoat leaves the cracks", is_equal_approx(cs.stats().crack_m, cracked), "%.0f m" % cs.stats().crack_m)
	var spot0: Dictionary = cs.seal_spots[0]
	cs.advance_to(16.0 + cs.sealcoat_life)
	var wheel_left := cs.sealcoat_left(Vector2(cs.wheel_paths[0], 5.0), spot0.born)
	var mid_left := cs.sealcoat_left(Vector2(cs.lane_joint_x - 0.6, 5.0), spot0.born)
	_check("sealcoat wears off the wheel paths first", wheel_left < mid_left and wheel_left < 0.5, "%.2f in a wheel path, %.2f between" % [wheel_left, mid_left])

	# A road crew keeps the road usable.
	var crew := _sim()
	crew.auto_maintain = true
	crew.reset()
	var worst := 100.0
	for y in range(1, 41):
		crew.advance_to(y)
		worst = minf(worst, crew.stats().pci)
	_check("road crew keeps it above 20", worst > 20.0, "worst %.0f over 40 years, %d repairs" % [worst, crew.log_lines.size()])

	# The lab scene: repair buttons work, the slider scrubs.
	var lab: Control = LAB.instantiate()
	root.add_child(lab)
	await process_frame
	var lsim: AsphaltSim = lab.get_node("Sim")
	(lab.get_node("Panel/Scroll/Box/Timeline") as HSlider).value = 12.0
	await process_frame
	_check("timeline scrubs the lab", is_equal_approx(lsim.time, 12.0), "year %.1f" % lsim.time)
	var fill := lab.get_node("Panel/Scroll/Box/Repair0") as CheckBox
	fill.button_pressed = true
	_check("ticking a repair does it at this year", lsim.events.size() == 1 and lsim.events[0].action == A.CRACK_FILL
		and lsim.log_lines.size() == 1 and is_equal_approx(lsim.time, 12.0), "%s, %s" % [lsim.events, lsim.log_lines])
	var tl := lab.get_node("Panel/Scroll/Box/Timeline") as HSlider
	tl.value = 15.0
	await process_frame
	(lab.get_node("Panel/Scroll/Box/Repair2") as CheckBox).button_pressed = true
	tl.value = 17.0
	await process_frame
	_check("repairs of different kinds stack up", lsim.events.size() == 2 and lsim.log_lines.size() == 2,
		"year %.1f, %s" % [lsim.time, lsim.log_lines])
	fill.button_pressed = false
	_check("unticking one undoes only it", lsim.events.size() == 1 and lsim.events[0].action == A.HEAVY_PATCH
		and lsim.log_lines.size() == 1 and is_equal_approx(lsim.time, 17.0), "year %.1f, %s" % [lsim.time, lsim.log_lines])
	tl.value = 10.0
	await process_frame
	_check("scrubbing before a repair shows the road without it", lsim.log_lines.is_empty() and
		(lab.get_node("Panel/Scroll/Box/Repair2") as CheckBox).button_pressed, str(lsim.log_lines))
	tl.value = 17.0
	await process_frame
	var start := lab.get_node("Panel/Scroll/Box/StartHere") as Button
	start.button_pressed = true
	_check("timeline can start at this year", tl.value == 0.0 and is_equal_approx(lsim.time, 17.0), "slider %.1f, year %.1f" % [tl.value, lsim.time])
	tl.value = 30.0
	await process_frame
	_check("and run on from it", is_equal_approx(lsim.time, 47.0) and lsim.log_lines.size() == 1, "year %.1f, %s" % [lsim.time, lsim.log_lines])
	start.button_pressed = false
	tl.value = 10.0
	await process_frame
	var panel := lab.get_node("Panel") as Control
	_check("side panel keeps its width", panel.size.x <= 331.0, "%.0f px" % panel.size.x)

	(lab.get_node("Panel/Scroll/Box/Timeline") as HSlider).value = 0.0
	await process_frame
	(lab.get_node("Panel/Scroll/Box/PlayRow/PlayButton") as Button).button_pressed = true
	for i in 30:
		lab._process(1.0 / 60.0)
	_check("Play runs from year 0 at 60 fps", lsim.time >= 0.8, "year %.1f after half a second" % lsim.time)
	(lab.get_node("Panel/Scroll/Box/PlayRow/PlayButton") as Button).button_pressed = false
	(lab.get_node("Panel/Scroll/Box/PlayRow/View") as OptionButton).select(3)
	(lab.get_node("Panel/Scroll/Box/PlayRow/View") as OptionButton).item_selected.emit(3)
	lab.draw_relief()
	var relief: TextureRect = lab.get_node("Stage/Views/ReliefView")
	_check("relief view shows the height map", relief.visible and relief.texture != null and relief.texture.get_width() == 501,
		"%s" % [relief.texture.get_size() if relief.texture else "no texture"])
	# Plan + section: the cross-section slices the road at the cut, and clicking on the plan moves the cut.
	var view := lab.get_node("Panel/Scroll/Box/PlayRow/View") as OptionButton
	view.select(5)
	view.item_selected.emit(5)
	var section: CrossSectionCanvas = lab.get_node("Stage/SectionView")
	lsim.seek(16.0)
	section.refresh()
	var across := section.crossings()
	var depth_ok := not across.is_empty()
	for cr in across:   # on the road, and as deep as the height map cuts it
		depth_ok = depth_ok and cr.x >= 0.0 and cr.x <= lsim.size.x and (cr.sealed or is_equal_approx(cr.depth, lsim.crack_depth(cr.width)))
	_check("cross-section slices the road", section.visible and section.profile.size() == int(round(lsim.size.x / section.res)) + 1
		and depth_ok, "%d profile samples, %d cracks crossed at %.2f m" % [section.profile.size(), across.size(), section.cut_y])
	var plan := lab.get_node("Stage/Views/ColorView") as TextureRect
	var r := section.plan_rect()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = r.position + Vector2(r.size.x * 0.5, r.size.y * 0.25)
	lab._on_plan_input(click)
	_check("clicking the plan moves the cut", absf(section.cut_y - lsim.size.y * 0.25) < 0.05, "cut at %.2f m" % section.cut_y)
	# LTPP distress map: the survey drawn with the appendix A symbols, and the data sheet totals.
	view.select(6)
	view.item_selected.emit(6)
	var map: DistressMapCanvas = lab.get_node("Stage/MapView")
	map.refresh()
	_check("distress map view shows the survey", map.visible and not section.visible and not plan.get_parent().visible
		and map.survey != null and not map.survey.areas.is_empty(), "%d areas, %d crack lines" % [map.survey.areas.size(), map.survey.lines.size()])

	print("\n%s: %d failure(s)" % ["FAIL" if failures else "PASS", failures])
	quit(1 if failures else 0)



## Angles (degrees) at which freely growing cracks meet another crack: shrinkage cracks (transverse, lane joint),
## fatigue cracks and the rest (edge); lane joint pieces meeting end on (`seam`); and how many crack ends there are.
func _junctions(sim: AsphaltSim) -> Dictionary:
	var out := { shrink = [], fatigue = [], other = [], seam = 0, ends = 0 }
	for c in sim.cracks:
		if not c.alive or c.guide.size() > 0 or c.kind == K.SLIPPAGE:
			continue
		if c.growing or c.length >= c.max_len - 0.03 or c.pts.size() <= 2:
			continue
		out.ends += 1
		var tip := c.pts[c.pts.size() - 1]
		for o in sim.cracks:
			if o != c and o.alive and o.pts.size() > 1 and _near_line(o.pts, tip, 0.006):
				# the angle they meet at: the last 7.5 cm of this crack against the other one there
				var k := 1
				for j in range(1, o.pts.size()):
					if o.pts[j].distance_squared_to(tip) < o.pts[k].distance_squared_to(tip):
						k = j
				var a := (tip - c.pts[maxi(0, c.pts.size() - 4)]).angle()
				var b := (o.pts[k] - o.pts[k - 1]).angle()
				var ang := absf(angle_difference(a, b))
				var deg := rad_to_deg(minf(ang, PI - ang))
				if c.kind == K.JOINT and o.kind == K.JOINT:
					out.seam += 1        # two pieces of the paving seam meeting end on: one crack, not a junction
				elif c.kind == K.WHEELPATH or c.kind == K.FATIGUE:
					out.fatigue.append(deg)
				elif c.kind == K.TRANSVERSE or c.kind == K.JOINT:
					out.shrink.append(deg)
				else:
					out.other.append(deg)
				break
	return out


func _mean(v: Array) -> float:
	var m := 0.0
	for x in v:
		m += x
	return m / maxf(v.size(), 1)

func _sim_at(t: float) -> AsphaltSim:
	var s := _sim()
	s.advance_to(t)
	return s
