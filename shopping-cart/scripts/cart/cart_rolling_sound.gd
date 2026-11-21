class_name CartRollingSound
extends Node3D
## The cart's rolling sound. Lives on the cart's Frame (scenes/cart/cart.tscn) with:
##  - FloorProbe: a RayCast3D down through the middle of the wheelbase. What it hits is the ground the cart rolls
##    on; nothing within reach means the cart is in the air or lying on its side, and the wheels go quiet.
##  - one RollingSurfaceSound per kind of ground (asphalt, tile, concrete), each with the physics materials of
##    the floors it is for. The one whose floors hold the ground's material plays; any other ground (kerbs,
##    props, a material no sound lists) plays `fallback`.
## Volume and pitch follow the frame's speed along the ground: silent at rest, full volume from
## full_volume_speed, and pitched up and down around the recordings' own pace (recorded_speed). Changing ground
## crossfades over fade_time.

@export var probe: RayCast3D
@export var fallback: RollingSurfaceSound
@export var silent_speed := 0.05      ## m/s: slower than this the wheels make no sound
@export var full_volume_speed := 1.5  ## m/s: full volume from here up (a brisk walk)
@export var volume_curve := 0.7       ## gain = (speed / full_volume_speed) ^ this: under 1 the sound comes in quickly
@export var recorded_speed := 1.3     ## m/s: the pace the recordings were made at; pitch 1 here
@export var min_pitch := 0.7          ## pitch at a crawl
@export var max_pitch := 1.5          ## pitch at a run
@export var pitch_per_speed := 0.2    ## pitch change per m/s away from recorded_speed
@export var fade_time := 0.15         ## s to fade a sound fully in or out (ground changes, lift-off, landing)

var speed := 0.0                         ## m/s along the ground right now
var surface: RollingSurfaceSound = null  ## the sound for the ground under the cart (null in the air)
@onready var _frame := get_parent() as RigidBody3D
var _sounds: Array[RollingSurfaceSound] = []


func _ready() -> void:
	for c in get_children():
		if c is RollingSurfaceSound:
			_sounds.append(c)
			c.set_gain(0.0)


func _physics_process(delta: float) -> void:
	surface = null
	speed = 0.0
	if probe.is_colliding():
		var ground := probe.get_collider()
		var mat: PhysicsMaterial = ground.get("physics_material_override") if ground else null
		surface = fallback
		for s in _sounds:
			if mat and s.floors.has(mat):
				surface = s
				break
		var up := probe.get_collision_normal()
		var v := Vector3.ZERO if _frame.freeze else _frame.linear_velocity
		speed = (v - up * v.dot(up)).length()
	var target := 0.0
	if speed > silent_speed:
		target = pow(clampf(speed / full_volume_speed, 0.0, 1.0), volume_curve)
	var pitch := clampf(1.0 + (speed - recorded_speed) * pitch_per_speed, min_pitch, max_pitch)
	var step := delta / fade_time
	for s in _sounds:
		var g := move_toward(s.gain, target if s == surface else 0.0, step)
		if g != s.gain:
			s.set_gain(g)
		s.pitch_scale = pitch
