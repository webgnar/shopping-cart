extends SceneTree
## The multiplayer pennant flags (scenes/cart/flag.tscn): four carts in the sandbox, each flag in another player's
## colour, seen from the side, from behind and close up. Needs a display (e.g. xvfb-run):
##   xvfb-run godot -s res://tests/flag_screenshot.gd -- <out prefix>

const CART_SCENE := preload("res://scenes/cart/cart.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://flag"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await process_frame
	var main := current_scene
	var carts: Array = [main.cart]
	for i in 3:
		var c: ShoppingCart = CART_SCENE.instantiate()
		c.player_controlled = false
		c.transform = Transform3D(Basis(Vector3.UP, 0.3 * i), main.cart.cart_origin() + Vector3(0.5 * i, 0.005, 1.4 * (i + 1)))
		main.add_child(c)
		carts.append(c)
	for i in carts.size():
		var f := carts[i].get_node("Frame/Flag") as CartFlag
		f.color = i
		f.visible = true
	for i in 120:
		await physics_frame
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 50
	var c0: Vector3 = carts[0].cart_origin()
	var views := {
		"side": [c0 + Vector3(1.0, 1.4, -4.6), c0 + Vector3(0.6, 1.1, 2.0)],
		"behind": [c0 + Vector3(-3.6, 1.9, 2.2), c0 + Vector3(0.6, 1.0, 2.0)],
		"close": [c0 + Vector3(-0.9, 1.3, -1.5), c0 + Vector3(0.2, 0.9, -0.3)],
		"top": [c0 + Vector3(-0.6, 2.6, -1.1), c0 + Vector3(0.14, 2.0, -0.33)],
	}
	for k in views:
		cam.look_at_from_position(views[k][0], views[k][1])
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, k])
		print("SCREENSHOT %s_%s.png" % [prefix, k])
	quit()
