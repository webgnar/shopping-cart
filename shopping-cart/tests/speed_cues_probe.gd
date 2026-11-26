extends SceneTree
## Measures what the sandbox gives the eye about speed (for docs/SPEED_PERCEPTION.md). Prints, does not pass/fail.
## Needs a display for the image part:
##   xvfb-run godot --rendering-method gl_compatibility --fixed-fps 60 -s res://tests/speed_cues_probe.gd
##  1. A real launch (Q+E held 2.5 s, then coasting) on the coast-down lane with the game's camera: speed, the
##     camera's distance behind and above the handle, how far its look target trails the cart, and the ground's
##     flow across the screen: an even grid of screen pixels is cast onto the ground and moved by the camera's own
##     motion; mean, 90th percentile and the mean over the outer fifths, in screen heights per second.
##  2. The same ground flow at 22 km/h for other camera settings (fov, distance, pitch), placed the way main.gd
##     places the camera, with how tall the cart stands on screen.
##  3. Ground detail: the mean brightness gradient of the ground in a frame, in the spawn aisle and on the lane.

const LAUNCH := 2.5
const COAST := 2.0
const V_REF := 22.0 / 3.6

var main: Node3D
var _last_cam := Vector3.ZERO


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Where an even 32 x 18 grid of screen pixels lands on the ground (y = 0) within 150 m; misses are left out.
func _ground_under_screen(cam: Camera3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for j in 18:
		for i in 32:
			var px := Vector2((i + 0.5) / 32.0, (j + 0.5) / 18.0) * Vector2(root.size)
			var o := cam.project_ray_origin(px)
			var d := cam.project_ray_normal(px)
			if d.y < -0.001:
				var p := o + d * (-o.y / d.y)
				if p.distance_to(o) < 150.0:
					pts.append(p)
	return pts


## How fast the ground under the screen moves across it when the camera moves by `move` in `dt`: [mean, 90th
## percentile, mean over the outer fifths left and right] in screen heights per second.
func _flow(cam: Camera3D, move: Vector3, dt: float) -> Vector3:
	var pts := _ground_under_screen(cam)
	var before := PackedVector2Array()
	for p in pts:
		before.append(cam.unproject_position(p))
	var xf := cam.global_transform
	cam.global_transform = Transform3D(xf.basis, xf.origin + move)
	var d: Array[float] = []
	var side := 0.0
	var side_n := 0
	for k in pts.size():
		if cam.is_position_behind(pts[k]):
			continue
		var v := cam.unproject_position(pts[k]).distance_to(before[k]) / root.size.y / dt
		d.append(v)
		if absf(before[k].x / root.size.x - 0.5) > 0.3:
			side += v
			side_n += 1
	cam.global_transform = xf
	if d.is_empty():
		return Vector3.ZERO
	var mean := 0.0
	for v in d:
		mean += v
	mean /= d.size()
	d.sort()
	return Vector3(mean, d[int(d.size() * 0.9)], side / maxf(side_n, 1))


func _run() -> void:
	await _frames(5)
	main.hud._force_sign.visible = false
	# ---------------------------------------------------------------- 1. launch
	main._next_lane()   # coast-down lane
	await _frames(30)
	var cart: ShoppingCart = main.cart
	var cam: Camera3D = main.camera
	print("\n1. LAUNCH  (Q+E %.1f s then coast; camera fov %d, dist %.1f, pitch %.2f)" % [LAUNCH, cam.fov, main.cam_dist, main.cam_pitch])
	print("   t s   km/h  cam back m  cam up m  target lag m  flow mean  flow p90  flow sides  (screen heights/s)")
	Input.action_press("push_left")
	Input.action_press("push_right")
	var t := 0.0
	var next_print := 0.0
	var released := false
	_last_cam = cam.global_position
	while t < LAUNCH + COAST:
		await process_frame
		var dt := 1.0 / 60.0
		t += dt
		if not released and t >= LAUNCH:
			Input.action_release("push_left")
			Input.action_release("push_right")
			released = true
		if t >= next_print - 0.001:
			next_print += 0.25
			# The camera's own motion over the last frame, applied to the ground it sees now.
			var f := _flow(cam, -(cam.global_position - _last_cam), dt)
			var h := cart.cart_origin()
			var fwd := Vector3(cos(cart.heading()), 0, -sin(cart.heading()))
			var back := -(cam.global_position - h).dot(fwd)
			var com := cart.frame.global_transform * cart.frame.center_of_mass + Vector3(0, 0.25, 0)
			print("   %4.2f  %5.1f  %10.2f  %8.2f  %12.2f  %9.2f  %8.2f  %10.2f" % [t, cart.frame_velocity().length() * 3.6,
				back, cam.global_position.y, main.cam_target.distance_to(com), f.x, f.y, f.z])
		_last_cam = cam.global_position
	# ---------------------------------------------------------------- 2. camera settings at 22 km/h
	print("\n2. GROUND FLOW AT 22 km/h BY CAMERA SETTING  (camera placed as main.gd does, cart at rest on the lane)")
	print("   fov  dist  pitch  cam up m  flow mean  flow p90  flow sides  cart on screen (screen heights)")
	main.set_process(false)
	await _frames(60)
	var target := cart.frame.global_transform * cart.frame.center_of_mass + Vector3(0, 0.25, 0)
	var yaw := cart.heading() + PI
	for s in [[55, 3.2, 0.38], [65, 3.2, 0.38], [75, 3.2, 0.38], [55, 2.4, 0.38], [55, 3.2, 0.25],
			[55, 2.4, 0.25], [65, 2.6, 0.30], [70, 2.4, 0.25]]:
		cam.fov = s[0]
		var dir := Vector3(cos(yaw) * cos(s[2]), sin(s[2]), -sin(yaw) * cos(s[2]))
		var at: Vector3 = target + dir * s[1]
		cam.global_position = at
		cam.look_at(target)
		var fwd := Vector3(cos(cart.heading()), 0, -sin(cart.heading()))
		var f := _flow(cam, fwd * V_REF / 60.0, 1.0 / 60.0)
		# The cart's height on screen: the handle top to the wheels' contact.
		var top := cam.unproject_position(cart.cart_origin() + Vector3(0, 1.05, 0))
		var bottom := cam.unproject_position(cart.cart_origin() + fwd * 0.5)
		print("   %3d  %4.1f  %5.2f  %8.2f  %9.2f  %8.2f  %10.2f  %6.2f" % [s[0], s[1], s[2], at.y, f.x, f.y, f.z,
			absf(bottom.y - top.y) / root.size.y])
	cam.fov = 55.0
	main.set_process(true)
	# ---------------------------------------------------------------- 3. ground detail
	print("\n3. GROUND DETAIL  (mean brightness gradient of the ground half of the frame, 0-1 per pixel)")
	main.hud.visible = false
	for spot in [["spawn aisle", Vector3(-30, 0, 0)], ["coast lane", Vector3(-20, 0, 17.5)], ["stall rows", Vector3(-30, 0, 20)]]:
		main.spawn_cart(spot[1], 0.0)
		await _frames(45)
		var img := root.get_texture().get_image()
		print("   %-12s  %.4f" % [spot[0], _gradient(img)])
	quit()


## Mean |gradient| of luma over the lower half of the image, skipping the middle where the cart is.
func _gradient(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(h / 2 + 4, h - 4, 3):
		for x in range(4, w - 4, 3):
			if absf(x - w / 2.0) < w * 0.12:
				continue
			var l := img.get_pixel(x, y).get_luminance()
			sum += absf(img.get_pixel(x + 1, y).get_luminance() - l) + absf(img.get_pixel(x, y + 1).get_luminance() - l)
			n += 1
	return sum / maxf(n, 1)
