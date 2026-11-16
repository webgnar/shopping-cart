extends Node3D
## Prototype sandbox: slippery store floor with shelves on +X, grippy parking lot with ramp, curb and
## speed bumps on -X. Q/A = left hand push/pull, E/D = right hand push/pull, W lift, S press, R reset.
## The mouse only moves the camera (click to capture, Esc to release, wheel to zoom).
##
## The level, lights, camera, HUD and the CartSpawn marker are all nodes in the scene (scenes/main.tscn).
## A scene that uses this script but leaves out the environment, camera or HUD gets the shared default
## scene for each.

const CART_SCENE := preload("res://scenes/cart/cart.tscn")
const ENVIRONMENT_SCENE := preload("res://scenes/environment/default_environment.tscn")
const CAMERA_SCENE := preload("res://scenes/cart_camera.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

const KEYS := {
	"push_left": KEY_Q, "pull_left": KEY_A,
	"push_right": KEY_E, "pull_right": KEY_D,
	"lift": KEY_W, "press": KEY_S, "reset": KEY_R,
	"gear_1": KEY_1, "gear_2": KEY_2, "gear_3": KEY_3, "gear_4": KEY_4, "gear_5": KEY_5,
	"fullscreen": KEY_F11,
}

var cart: ShoppingCart
var gear := 3   ## push gear, kept across resets
var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.38
var cam_dist := 3.2
var cam_heading := 0.0
var cam_target := Vector3.ZERO

## Shared floor materials (their friction is set in the .tres files).
var tile_mat: PhysicsMaterial = preload("res://assets/physics/tile.tres")
var asphalt_mat: PhysicsMaterial = preload("res://assets/physics/asphalt.tres")
var solid_mat: PhysicsMaterial = preload("res://assets/physics/solid.tres")

var hud: CartHUD


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_level()
	var spawn := get_node_or_null("CartSpawn") as Node3D
	if spawn:
		spawn_cart(spawn.global_position, spawn.global_rotation.y)
	else:
		spawn_cart(Vector3(2, 0, 0), 0.0)
	camera = get_node_or_null("Camera") as Camera3D
	if camera == null:
		camera = CAMERA_SCENE.instantiate()
		add_child(camera)
	camera.current = true
	_build_hud()


func _setup_input() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)


## Removes the current cart (and its groceries) and builds a fresh one at `at`, facing `yaw`.
func spawn_cart(at: Vector3, yaw: float) -> void:
	if cart:
		remove_child(cart)
		cart.free()
	cart = CART_SCENE.instantiate()
	cart.name = "Cart"
	cart.gear = gear
	cart.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.005, 0))
	add_child(cart)
	cam_heading = yaw
	cam_target = at + Vector3(0, 0.67, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
			if event.ctrl_pressed:   # Ctrl + scroll zooms the camera
				cam_dist = maxf(1.4, cam_dist * 0.9) if up else minf(9.0, cam_dist * 1.1)
			else:                    # scroll shifts the push gear
				gear = cart.set_gear(gear + (1 if up else -1))
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.004
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.003, 0.05, 1.3)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
		gear = cart.set_gear(event.physical_keycode - KEY_0)
	elif event.is_action_pressed("reset"):
		var p := cart.cart_origin()
		spawn_cart(Vector3(p.x, 0.05, p.z), cart.heading())


func _process(delta: float) -> void:
	# Camera trails behind the handle; the mouse orbits on top of that.
	var dh := wrapf(cart.heading() - cam_heading, -PI, PI)
	cam_heading += dh * minf(1.0, 3.0 * delta)
	var com := cart.frame.global_transform * cart.frame.center_of_mass
	cam_target = cam_target.lerp(com + Vector3(0, 0.25, 0), minf(1.0, 9.0 * delta))
	var yaw := cam_heading + PI + cam_yaw
	camera.global_position = cam_target + Vector3(cos(yaw) * cos(cam_pitch), sin(cam_pitch), -sin(yaw) * cos(cam_pitch)) * cam_dist
	camera.look_at(cam_target)
	hud.show_cart(cart)


# ---------------------------------------------------------------- world

## The scene's own WorldEnvironment and lights are used; without one, the shared default is added.
func _build_environment() -> void:
	if find_children("*", "WorldEnvironment", true, false).is_empty():
		add_child(ENVIRONMENT_SCENE.instantiate())


## Hook for level scripts. The level itself is built in the scene, not here.
func _build_level() -> void:
	pass


## The scene's HUD node is used; without one, the shared HUD scene is added.
func _build_hud() -> void:
	hud = get_node_or_null("HUD") as CartHUD
	if hud == null:
		hud = HUD_SCENE.instantiate()
		add_child(hud)
