extends SceneTree
## Renders the crack lattice experiment next to the current AsphaltSim over the years. Run from the Godot project folder:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/crack_lattice_screenshot.gd -- <out dir>
## Writes lattice_yearNN.png (the 2 x 2 m patch) and current_yearNN.png: the same 2 x 2 m of the asphalt lab's
## section (x 0.95..2.95 m, y 4..6 m, round its first wheel path) at the same scale, 1024 px per metre (2048 px images).

const LATTICE := preload("res://scenes/asphalt/crack_lattice_lab.tscn")
const LAB := preload("res://scenes/asphalt/asphalt_lab.tscn")
const YEARS := [0, 5, 10, 15, 20, 25, 30]
const CROP := Vector2(0.95, 4.0)   ## m: corner of the lab section matching the patch (its wheel path at x 1.0)
const PX_PER_M := 1024.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://crack_lattice"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1400, 1100)
	var lab: Control = LAB.instantiate()
	root.add_child(lab)
	var vp: SubViewport = lab.get_node("ColorViewport")
	vp.size = Vector2i(2048, 2048)
	var base: Control = lab.get_node("ColorViewport/Base")
	var damage: Node2D = lab.get_node("ColorViewport/Damage")
	damage.px_per_m = PX_PER_M
	damage.position = -CROP * PX_PER_M
	base.position = -CROP * PX_PER_M
	var sim: AsphaltSim = lab.get_node("Sim")
	await _frames(30)
	for y: int in YEARS:
		sim.events.clear()
		sim.reset()
		sim.advance_to(y)
		await _frames(3)
		vp.get_texture().get_image().save_png("%s/current_year%02d.png" % [out, y])
	lab.queue_free()
	var lat: Control = LATTICE.instantiate()
	root.add_child(lat)
	await _frames(5)
	var cl: CrackLattice = lat.get_node("Sim")
	var lvp: SubViewport = lat.get_node("PatchViewport")
	lvp.size = Vector2i(2048, 2048)
	lat.get_node("PatchViewport/Patch").px_per_m = PX_PER_M
	for y: int in YEARS:
		var t0 := Time.get_ticks_msec()
		cl.advance_to(y)
		await _frames(3)
		lvp.get_texture().get_image().save_png("%s/lattice_year%02d.png" % [out, y])
		print("year %2d  %s  (%d s)" % [y, cl.stats(), (Time.get_ticks_msec() - t0) / 1000])
	root.get_texture().get_image().save_png("%s/lattice_lab.png" % out)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
