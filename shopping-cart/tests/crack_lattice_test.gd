extends SceneTree
## Checks the crack lattice experiment (scripts/asphalt/crack_lattice.gd) on a 1 x 1 m patch. Run from the Godot
## project folder: godot --headless -s res://tests/crack_lattice_test.gd

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sim := CrackLattice.new()
	sim.size = Vector2(1.0, 1.0)
	sim.wheel_path_x = 0.5
	root.add_child(sim)
	_check(sim.broken.is_empty(), "new asphalt has no cracks")
	var face := 0
	for kd in sim.kind:
		if kd != CrackLattice.Kind.MASTIC:
			face += 1
	_check(face > sim.kind.size() / 5, "the stones weaken a good share of the springs (%d)" % face)
	sim.advance_to(1.0)
	var year1: float = sim.stats().crack_m
	_check(year1 < 0.5, "hardly any cracking in year 1 (%.2f m)" % year1)
	sim.advance_to(10.0)
	var year10: float = sim.stats().crack_m
	_check(year10 > 2.0, "cracks by year 10 (%.1f m)" % year10)
	sim.advance_to(30.0)
	var st := sim.stats()
	_check(st.crack_m > year10, "cracking keeps growing (%.1f m at 30)" % st.crack_m)
	for s in sim.broken:
		if sim.kind[s] == CrackLattice.Kind.STONE:
			_check(false, "a stone broke")
			break
	# crack per metre of width: the middle 0.4 m (wheel path) against the 0.4 m either side of the wrap
	var inside := 0
	var outside := 0
	for s in sim.broken:
		var dx := absf(sim.mid[s].x - 0.5)
		if dx < 0.2:
			inside += 1
		elif dx > 0.3:
			outside += 1
	_check(inside > outside * 1.3, "the wheel path cracks more (%d against %d springs)" % [inside, outside])
	print("crack_lattice_test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1
