extends SceneTree
## Renders the parking lot lab (scenes/lot_gen/lot_lab.tscn) at a few settings. From the Godot project:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/lot_lab_screenshot.gd -- <out dir>

const LAB := preload("res://scenes/lot_gen/lot_lab.tscn")

## shot name, angle index (90, 60, 45, 30), two-way, top view
const SHOTS := [
	["lab_90_top", 0, true, true],
	["lab_60_oneway_top", 1, false, true],
	["lab_45_top", 2, true, true],
	["lab_30_oneway_top", 3, false, true],
	["lab_90_3d", 0, true, false],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://lot_lab"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var lab: Node3D = LAB.instantiate()
	root.add_child(lab)
	for i in 10:
		await process_frame
	for s: Array in SHOTS:
		var angle: OptionButton = lab.get_node("%Angle")
		angle.select(s[1])
		angle.item_selected.emit(s[1])
		lab.get_node("%TwoWay").button_pressed = s[2]
		lab.get_node("%TopView").button_pressed = s[3]
		for i in 10:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
	quit()
