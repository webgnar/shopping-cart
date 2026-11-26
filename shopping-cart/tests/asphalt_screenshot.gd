extends SceneTree
## Renders the asphalt lab at stages of its life, with and without repairs. Run from the Godot project folder:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/asphalt_screenshot.gd -- <out dir>
## Writes <stage>_color.png and <stage>_height.png (the whole 10 x 10 m section), <stage>_zoom.png (a 2.5 m
## close-up of a wheel path), lab.png (the lab window) and section_<stage>.png (the lab's plan + cross-section view) and map_<stage>.png (its LTPP distress map).

const LAB := preload("res://scenes/asphalt/asphalt_lab.tscn")

## name, year, repairs as [year, AsphaltSim.Action]
const STAGES := [
	["01_new", 0.0, []],
	["02_year05", 5.0, []],
	["03_year10", 10.0, []],
	["04_year14", 14.0, []],
	["05_year18", 18.0, []],
	["06_year22", 22.0, []],
	["07_year28", 28.0, []],
	["08_cracks_filled", 10.0, [[9.6, 0]]],
	["09_fill_ageing", 17.0, [[9.6, 0]]],
	["10_potholes", 18.0, [[9.6, 0]]],
	["11_potholes_filled", 18.2, [[9.6, 0], [18.0, 1]]],
	["12_fills_failing", 20.0, [[9.6, 0], [18.0, 1]]],
	["13_heavy_patched", 16.6, [[9.6, 0], [16.4, 2]]],
	["14_patch_seams", 23.0, [[9.6, 0], [16.4, 2]]],
	["15_spot_sealcoat", 16.2, [[16.0, 3]]],
	["16_sealcoat_worn", 19.0, [[16.0, 3]]],
	["16_sealcoat_repainted", 16.4, [[16.0, 3], [16.2, 5]]],
	["17_overlay", 20.6, [[9.6, 0], [18.0, 1], [20.0, 2], [20.4, 4]]],
	["18_overlay_reflecting", 27.0, [[9.6, 0], [18.0, 1], [20.0, 2], [20.4, 4]]],
]

## Plan + cross-section renders: name, year, repairs.
const SECTIONS := [
	["year08", 8.0, []],
	["year18_potholes", 18.0, []],
	["year18_filled", 18.2, [[9.6, 0], [18.0, 1]]],
	["year17_heavy_patched", 16.6, [[9.6, 0], [16.4, 2]]],
	["year27_overlay_reflecting", 27.0, [[9.6, 0], [18.0, 1], [20.0, 2], [20.4, 4]]],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://asphalt"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var lab: Control = LAB.instantiate()
	root.add_child(lab)
	# The grain NoiseTexture2D is generated on a thread; wait for it.
	await _frames(30)
	var sim: AsphaltSim = lab.get_node("Sim")
	var color_vp: SubViewport = lab.get_node("ColorViewport")
	var height_vp: SubViewport = lab.get_node("HeightViewport")
	for st: Array in STAGES:
		sim.events.clear()
		for e: Array in st[2]:
			sim.events.append({ t = e[0], action = e[1] })
		sim.reset()
		sim.advance_to(st[1])
		await _frames(3)
		var img := color_vp.get_texture().get_image()
		img.save_png("%s/%s_color.png" % [out, st[0]])
		img.get_region(Rect2i(300, 700, 560, 560)).save_png("%s/%s_zoom.png" % [out, st[0]])
		height_vp.get_texture().get_image().save_png("%s/%s_height.png" % [out, st[0]])
		var s := sim.stats()
		print("%-20s year %4.1f  pci %3.0f  cracks %5.0f m  fatigue %4.1f%%  potholes %d  log %s" % [st[0], s.year, s.pci,
			s.crack_m, s.alligator_pct, s.potholes, sim.log_lines])
	await _frames(3)
	root.get_texture().get_image().save_png("%s/lab.png" % out)
	# Plan + cross-section, cut through the 10 cm row with the most potholes, fills and patches (else the middle).
	var view := lab.get_node("Panel/Scroll/Box/PlayRow/View") as OptionButton
	view.select(5)
	view.item_selected.emit(5)
	var section: CrossSectionCanvas = lab.get_node("Stage/SectionView")
	for st: Array in SECTIONS:
		sim.events.clear()
		for e: Array in st[2]:
			sim.events.append({ t = e[0], action = e[1] })
		sim.reset()
		sim.advance_to(st[1])
		section.refresh()
		section.set_cut(_worst_row(sim))
		await _frames(3)
		root.get_texture().get_image().save_png("%s/section_%s.png" % [out, st[0]])
	# The LTPP distress map (appendix A symbols) at the same stages.
	view.select(6)
	view.item_selected.emit(6)
	var map: DistressMapCanvas = lab.get_node("Stage/MapView")
	for st: Array in SECTIONS:
		sim.events.clear()
		for e: Array in st[2]:
			sim.events.append({ t = e[0], action = e[1] })
		sim.reset()
		sim.advance_to(st[1])
		map.refresh()
		await _frames(3)
		root.get_texture().get_image().save_png("%s/map_%s.png" % [out, st[0]])
	quit()


## m along the road of the 10 cm row with the most potholes, fills and patches; the middle if there are none.
func _worst_row(sim: AsphaltSim) -> float:
	var best := -1
	var best_n := 0
	for cy in sim.ny:
		var n := 0
		for cx in sim.nx:
			var i := cy * sim.nx + cx
			if sim.hole[i] > 0.0 or sim.fill_born[i] >= 0.0 or sim.patch_of[i] >= 0:
				n += 1
		if n > best_n:
			best_n = n
			best = cy
	return (best + 0.5) * AsphaltSim.CELL if best >= 0 else sim.size.y * 0.5


func _frames(n: int) -> void:
	for i in n:
		await process_frame
