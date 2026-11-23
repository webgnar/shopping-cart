extends SceneTree
## Renders the curb demo (scenes/curb/curb_demo.tscn) with a cart for scale. Run from the Godot project folder:
##   xvfb-run godot --rendering-method gl_compatibility -s res://tests/curb_screenshot.gd -- <out dir>
## Writes overview.png, corner.png, cart.png (a cart up against the face) and profile.png (end-on at the straight run's start).

const DEMO := preload("res://scenes/curb/curb_demo.tscn")
const CART := preload("res://scenes/cart/cart.tscn")

## name, camera position, look at
const SHOTS := [
	["overview", Vector3(1, 4.5, 8), Vector3(0, 0, -3)],
	["corner", Vector3(-6.5, 1.2, 3.2), Vector3(-9.2, 0.1, 0.2)],
	["cart", Vector3(0.9, 0.7, 0.4), Vector3(-0.9, 0.15, -1.9)],
	["profile", Vector3(-3.6, 0.09, -2.05), Vector3(-3, 0.07, -2.05)],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://curb"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var demo: Node3D = DEMO.instantiate()
	root.add_child(demo)
	var cart: Node3D = CART.instantiate()
	cart.position = Vector3(-1.2, 0, -0.9)
	cart.rotation.y = PI / 2   # nose (+X) toward the curb's face
	demo.add_child(cart)
	cart.set_physics_process(false)   # no input map here; it just stands
	var cam: Camera3D = demo.get_node("Camera3D")
	cam.current = true
	for i in 60:
		await process_frame
	for s: Array in SHOTS:
		cam.fov = 75.0 if s[0] != "profile" else 30.0
		cam.near = 0.01
		cam.look_at_from_position(s[1], s[2])
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
	quit()
