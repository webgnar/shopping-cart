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
	cf.advance_to(10.0)
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
	var cs := _sim()
	cs.advance_to(16.0)
	cs.do_action(A.SURFACE_SEAL)
	_check("chip seal is the new surface", cs.surface_kind == AsphaltSim.Surface.CHIP_SEAL and cs.stats().crack_m == 0.0, "")

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
	(lab.get_node("Panel/Scroll/Box/Repair0") as Button).pressed.emit()
	_check("repair button records a repair", lsim.events.size() == 1 and lsim.events[0].action == A.CRACK_FILL, str(lsim.events))
	(lab.get_node("Panel/Scroll/Box/Timeline") as HSlider).value = 5.0
	await process_frame
	(lab.get_node("Panel/Scroll/Box/Timeline") as HSlider).value = 14.0
	await process_frame
	_check("scrubbing keeps the repair", lsim.log_lines.size() == 1, str(lsim.log_lines))

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
	var relief: TextureRect = lab.get_node("Views/ReliefView")
	_check("relief view shows the height map", relief.visible and relief.texture != null and relief.texture.get_width() == 501,
		"%s" % [relief.texture.get_size() if relief.texture else "no texture"])

	print("\n%s: %d failure(s)" % ["FAIL" if failures else "PASS", failures])
	quit(1 if failures else 0)


func _sim_at(t: float) -> AsphaltSim:
	var s := _sim()
	s.advance_to(t)
	return s
