extends Node3D
## Cart sound bench (scenes/sound_bench.tscn): the real cart on a plain floor, with a cinder block and two boxes to
## pick up and drop into it, so you can hear the sounds the cart's physics makes (its ContactSounds, WheelSounds
## and ImpactSynth do all of it; this script only holds things and turns the cart).
##  - Left mouse: grab whatever body is under the cursor (a prop, or any part of the cart, seen through its wire parts) and hold it at the hand,
##    a point that follows the cursor at the distance you grabbed it. The hand pulls on the spot you grabbed, like
##    a spring with a person's strength, so a heavy block lags, swings and lands with its real weight. Let go to drop.
##  - Mouse wheel: while holding, moves the hand nearer or further; otherwise zooms the camera.
##  - Right mouse drag: orbits the camera round the cart.
##  - Left/Right arrows: turn the cart on the spot.
## Everything is placed in the scene; this script is behaviour only.

@export var cart: ShoppingCart
@export var camera: Camera3D

@export_group("Grab")
@export var grab_stiffness := 120.0   ## 1/s^2: the hand's pull on the held spot per metre it trails, as acceleration
@export var grab_damping := 16.0      ## 1/s: how much the hand resists the held spot's speed, as acceleration
@export var grab_min_mass := 2.0     ## kg: the spring pulls a lighter body as hard as one this heavy
@export var grab_max_force := 450.0   ## N: a person's lifting strength; a heavier pull than this lags behind
@export var grab_angular_damp := 4.0  ## extra angular damping on the held body, so it doesn't spin off the hand
@export var hold_min := 0.6           ## m from the camera
@export var hold_max := 8.0
@export var reach := 30.0             ## m: furthest the cursor can grab
@export var pick_depth := 0.06        ## m behind the first thing the cursor hits that it can still pick (see pick())
@export var falling_speed := 0.05     ## m/s (and rad/s): a dropped body moving faster keeps the cart awake to hear it

@export_group("Turn")
@export var turn_rate := 1.2          ## rad/s the arrows turn the cart at
@export var turn_gain := 120.0        ## N*m per rad/s the cart is short of turn_rate
@export var turn_max := 90.0          ## N*m

@export_group("Camera")
@export var orbit_speed := 0.005      ## rad per pixel dragged
@export var cam_yaw := 2.4            ## rad round the cart (0 looks along -X)
@export var cam_pitch := 0.5          ## rad above level
@export var cam_dist := 3.2           ## m
@export var cam_min := 1.2
@export var cam_max := 10.0

var held: RigidBody3D = null   ## the body in the hand
var hand := Vector3.ZERO       ## where the hand is (world)
var hold_dist := 2.0           ## m from the camera to the hand
var turn := 0.0                ## -1 turn right, +1 turn left (the arrows)
var _held_point := Vector3.ZERO   ## the grabbed spot, in the held body's space
var _held_damp := 0.0             ## its angular_damp before it was grabbed
var _mouse := Vector2.ZERO
var _mouse_seen := false
var _orbiting := false
var _falling: RigidBody3D = null  ## the body last let go of, until it stops moving


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_mouse_seen = true
		if _orbiting:
			cam_yaw -= event.relative.x * orbit_speed
			cam_pitch = clampf(cam_pitch + event.relative.y * orbit_speed, -0.1, 1.45)
	elif event is InputEventMouseButton:
		_mouse = event.position
		_mouse_seen = true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_grab_at_cursor()
			else:
				release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var nearer: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
			if held:
				hold_dist = clampf(hold_dist * (0.92 if nearer else 1.08), hold_min, hold_max)
			else:
				cam_dist = clampf(cam_dist * (0.9 if nearer else 1.1), cam_min, cam_max)
	elif event is InputEventKey and event.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
		var left := Input.is_physical_key_pressed(KEY_LEFT)
		var right := Input.is_physical_key_pressed(KEY_RIGHT)
		turn = float(left) - float(right)


func _process(_delta: float) -> void:
	var target := cart.frame.global_transform * cart.frame.center_of_mass
	var offset := Vector3(-cos(cam_yaw) * cos(cam_pitch), sin(cam_pitch), sin(cam_yaw) * cos(cam_pitch))
	camera.look_at_from_position(target + offset * cam_dist, target)
	if _mouse_seen:
		hand = _cursor_point(hold_dist)


func _physics_process(delta: float) -> void:
	if held:
		_wake(held)
		var p := held.global_transform * _held_point
		var r := p - held.global_position
		var v := held.linear_velocity + held.angular_velocity.cross(r)
		# The spring pulls as if on at least grab_min_mass, so a light part hinged to heavier ones still follows.
		var spring := ((hand - p) * grab_stiffness - v * grab_damping) * maxf(held.mass, grab_min_mass)
		held.apply_force((spring - held.get_gravity() * held.mass).limit_length(grab_max_force), r)
	# A cart at rest is pinned (frozen) and hears nothing that lands on it, so it is kept live while what was just
	# dropped is still moving.
	if _falling:
		if _falling.linear_velocity.length() > falling_speed or _falling.angular_velocity.length() > falling_speed:
			_wake(cart.frame)
		else:
			_falling = null
	if turn != 0.0:
		_wake(cart.frame)
		var short := turn * turn_rate - cart.frame.angular_velocity.y
		cart.frame.apply_torque(Vector3.UP * clampf(short * turn_gain, -turn_max, turn_max))


## Picks up `body` by the spot `at` (world): the hand starts there.
func grab(body: RigidBody3D, at: Vector3) -> void:
	release()
	held = body
	_held_point = body.global_transform.affine_inverse() * at
	_held_damp = body.angular_damp
	body.angular_damp = _held_damp + grab_angular_damp
	hold_dist = clampf(camera.global_position.distance_to(at), hold_min, hold_max)
	hand = at
	_wake(body)


## Lets go of whatever is held.
func release() -> void:
	if held:
		held.angular_damp = _held_damp
		_falling = held
	held = null


func _grab_at_cursor() -> void:
	var from := camera.project_ray_origin(_mouse)
	var hit := pick(from, camera.project_ray_normal(_mouse))
	if hit:
		grab(hit.collider, hit.position)


## What the cursor ray from `from` along `dir` picks up: the lightest body it meets within pick_depth of the first
## thing it hits. The cart's wire parts (gate, seat, backrest) have solid collision boxes, but you see through them
## to what sits on or behind them, like the plastic plate on the child seat, and that is what you meant to grab.
func pick(from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach,
		ShoppingCart.LAYER_WORLD | ShoppingCart.LAYER_CART | ShoppingCart.LAYER_CARGO)
	var space := get_world_3d().direct_space_state
	var best := {}
	var first := -1.0
	var skip: Array[RID] = []
	for i in 6:
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var d := from.distance_to(hit.position)
		if first < 0.0:
			first = d
		elif d - first > pick_depth:
			break
		if hit.collider is RigidBody3D and (best.is_empty() or hit.collider.mass < best.collider.mass):
			best = hit
		skip.append(hit.rid)
	return best


func _cursor_point(dist: float) -> Vector3:
	return camera.project_ray_origin(_mouse) + camera.project_ray_normal(_mouse) * dist


## A cart that has come to rest is pinned (its frame frozen); a hand on it, turning it, or something just dropped
## lets it move again.
func _wake(body: RigidBody3D) -> void:
	body.sleeping = false
	var c := body.get_parent() as ShoppingCart
	if c and c.frame.freeze:
		c._wake()
