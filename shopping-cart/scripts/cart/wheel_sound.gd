class_name WheelSound
extends Node3D
## One cart wheel's sound, driven by that wheel's own physics. Instanced (scenes/cart/wheel_sound.tscn) under each
## wheel body of scenes/cart/cart.tscn, so all four share these settings.
##  - Roll: the loop for the floor under this wheel (its physics material picks a CartFloorSound). Volume and
##    pitch follow how fast the wheel itself spins (spin about its axle times its radius), so a wheel in the air
##    or a locked, sliding wheel doesn't roll, and in a wheelie only the wheels on the ground are heard.
##  - Scrub: the wheel sliding along its axle (sideways), or skidding (moving faster or slower over the ground
##    than it spins). Drifts, spins on the spot and casters whipping round.
##  - Land: the wheel hitting the ground after being off it (a wheelie set down, W/S, a drop, a bounce). How hard
##    is the wheel's speed into the ground at the moment it touches (along the floor's normal). A gentle touch
##    is silent, a soft one a light tap (the bounce of zack's drop recording), a hard one the full slam (its
##    main hit), louder the faster it came down.
##  - Knock: a sudden upward jolt of a wheel that stayed on the ground (a kerb, a joint, a bump): a slab clack.
## Landings and knocks are the same physics: the ground stopping the wheel, measured as how much the wheel's velocity
## along the floor's normal jumps while it touches (summed over the ticks the hit lasts, so one hit is one sound).
## Whether the wheel came out of the air picks landing or knock. There are no timers: a sound plays only when the
## physics says the wheel was hit that hard.
## A multiplayer guest's cart is frozen and moved by the network: its wheels' motion is read from how they moved
## between frames instead.

@export var roll_player: AudioStreamPlayer3D
@export var scrub_player: AudioStreamPlayer3D
@export var knock_player: AudioStreamPlayer3D
@export var land_player: AudioStreamPlayer3D
## Generated hits (the cart's ImpactSynth): when set, every hit also strikes it, layered under the recording (the
## recording gives the real cart's character, the synth how this hit differs: where, how hard, on what).
@export var synth: ImpactSynth
@export var struck_mass := 6.0        ## kg: the share of the cart a wheel stops when it hits (a quarter of it)
@export var contact_time := 0.0012    ## s a hard polyurethane caster wheel's contact lasts at 1 m/s
@export var floor_sounds: Array[CartFloorSound] = []
@export var fallback: CartFloorSound   ## for any floor no CartFloorSound lists (kerbs, props)
## m of air under the wheel that still counts as touching: a wheel lifted more than this is off the ground and
## makes no sound (the cart's own wheels-down check allows 2 cm; a lifted wheel spinning down is still 2 cm up)
@export var contact_gap := 0.005
@export_group("Rolling")
@export var wheel_db := -6.0          ## each wheel's share: four wheels together sound like one cart
@export var silent_speed := 0.05      ## m/s of roll under which the wheel makes no sound
@export var full_volume_speed := 1.5  ## m/s: full volume from here up (a brisk walk)
@export var volume_curve := 0.7       ## gain = (speed / full_volume_speed) ^ this: under 1 the sound comes in quickly
@export var recorded_speed := 1.3     ## m/s: the pace the recordings were made at; pitch 1 here
@export var min_pitch := 0.7          ## pitch at a crawl
@export var max_pitch := 1.5          ## pitch at a run
@export var pitch_per_speed := 0.2    ## pitch change per m/s away from recorded_speed
@export var fade_time := 0.03         ## s to ramp a loop in or out: just long enough not to click
@export_group("Scrub")
@export var scrub_start := 0.25       ## m/s of slide before the wheel starts to scrub
@export var scrub_full := 1.5         ## m/s of slide for full scrub volume
## Rolling wheels never match the ground exactly (the contact squashes a little, the physics spins a loaded wheel a
## few per cent fast): a skid smaller than this fraction of the speed is still rolling, as a tyre's slip ratio.
@export var skid_tolerance := 0.15
@export var scrub_pitch_low := 0.85   ## scrub pitch at scrub_start
@export var scrub_pitch_per_speed := 0.15   ## scrub pitch rise per m/s of slide
@export var scrub_max_pitch := 1.4
@export_group("Knock")
@export var knock_start := 0.6        ## m/s: an upward jolt of the wheel bigger than this knocks
@export var knock_full := 2.5         ## m/s: full knock volume
@export var knock_db := -4.0          ## knock volume at full
## m/s per tick: the ground pushing the wheel's velocity up by more than this in one tick is part of a hit (resting
## and rolling stay near 0; gravity alone is -0.08 at 120 ticks)
@export var hit_floor := 0.15
@export_group("Landing")
@export var land_tap: AudioStream      ## a soft landing: a light tap
@export var land_slam: AudioStream     ## a hard landing: the full slam
@export var land_start := 0.3         ## m/s into the ground: slower than this the wheel touches down silently
@export var land_slam_speed := 1.0    ## m/s into the ground from which it slams instead of tapping (a 5 cm drop)
@export var land_full := 3.0          ## m/s into the ground for full volume (a 45 cm drop)
@export var land_curve := 0.8         ## gain = ((impact - land_start) / (land_full - land_start)) ^ this
@export var land_db := -1.0           ## landing volume at full

var grounded := false
var floor_sound: CartFloorSound = null  ## the ground under this wheel (null in the air)
var roll_speed := 0.0                   ## m/s: spin about the axle times the radius
var slide := 0.0                        ## m/s: sideways slide and skid over the ground
var roll_gain := 0.0
var scrub_gain := 0.0
var knocks := 0                         ## knocks so far (for tests)
var landings := 0                       ## landings heard so far (for tests)
var slams := 0                          ## of those, hard ones
var last_impact := 0.0                  ## m/s the ground took out of the wheel at the last touchdown, heard or not

@onready var _wheel := get_parent() as RigidBody3D
@onready var _cart := _wheel.get_parent() as ShoppingCart
var _roll_sound: CartFloorSound = null   ## the floor whose loop the Roll player has now
var _scrub_sound: CartFloorSound = null
var _prev_xf := Transform3D()
var _prev_v := Vector3.ZERO
var _have_prev := false
var _hit := 0.0          ## m/s of velocity the ground has taken out of the wheel so far in the hit going on now
var _from_air := false   ## the wheel was off the ground since it last settled: its next hit is a landing


func _ready() -> void:
	_set_gain(roll_player, 0.0, 0.0)
	_set_gain(scrub_player, 0.0, 0.0)


func _physics_process(delta: float) -> void:
	var xf := _wheel.global_transform
	var v: Vector3
	var w: Vector3
	if _cart.puppet or _wheel.freeze:
		v = (xf.origin - _prev_xf.origin) / delta if _have_prev else Vector3.ZERO
		var q := Quaternion((xf.basis * _prev_xf.basis.inverse()).orthonormalized()) if _have_prev else Quaternion()
		w = q.get_axis() * q.get_angle() / delta if q.get_angle() > 1e-6 else Vector3.ZERO
	else:
		v = _wheel.linear_velocity
		w = _wheel.angular_velocity
	_prev_xf = xf
	_have_prev = true

	var hit := _cart.ground_hit(_wheel, contact_gap)
	grounded = not hit.is_empty()
	floor_sound = null
	roll_speed = 0.0
	slide = 0.0
	if grounded:
		var mat: PhysicsMaterial = hit.collider.get("physics_material_override") if hit.collider else null
		floor_sound = fallback
		for f in floor_sounds:
			if mat and f.floors.has(mat):
				floor_sound = f
				break
		var n: Vector3 = hit.normal
		var axle := xf.basis.z.normalized()
		var side := (axle - n * axle.dot(n))
		if side.length() > 0.1:   # a wheel lying flat has no axle along the ground
			side = side.normalized()
			var ahead := side.cross(n).normalized()
			var vg := v - n * v.dot(n)
			roll_speed = absf(w.dot(axle)) * _cart.wheel_radius
			var sideways := vg.dot(side)
			var over := absf(vg.dot(ahead))
			var skid := maxf(0.0, absf(over - roll_speed) - skid_tolerance * maxf(over, roll_speed))
			slide = sqrt(sideways * sideways + skid * skid)

	# Hits: the ground pushing the wheel's velocity up along its normal (off the ground: plain up).
	var up: Vector3 = hit.normal if grounded else Vector3.UP
	var dv := (v - _prev_v).dot(up) if _have_prev else 0.0
	_prev_v = v
	if not grounded:
		_from_air = true
	if grounded and dv > hit_floor:
		_hit += dv
	elif _hit > 0.0:
		_play_hit(_hit)
		_hit = 0.0
	elif grounded and absf(v.dot(up)) < hit_floor:
		_from_air = false   # settled on the ground: what comes next is a knock, not a landing

	var step := delta / fade_time
	var roll_t := 0.0
	if roll_speed > silent_speed:
		roll_t = pow(clampf(roll_speed / full_volume_speed, 0.0, 1.0), volume_curve)
	var scrub_t := clampf((slide - scrub_start) / (scrub_full - scrub_start), 0.0, 1.0)
	roll_gain = _drive(roll_player, floor_sound, roll_gain, roll_t, step, true)
	scrub_gain = _drive(scrub_player, floor_sound, scrub_gain, scrub_t, step, false)
	roll_player.pitch_scale = clampf(1.0 + (roll_speed - recorded_speed) * pitch_per_speed, min_pitch, max_pitch)
	scrub_player.pitch_scale = clampf(scrub_pitch_low + (slide - scrub_start) * scrub_pitch_per_speed, scrub_pitch_low,
		scrub_max_pitch)


## One hit, done: a landing if the wheel came out of the air (silent, tap or slam by how hard), else a knock.
func _play_hit(speed: float) -> void:
	if synth:
		var where := _cart.frame.global_transform.affine_inverse() * _wheel.global_position
		var scale := floor_sound.contact_time_scale if floor_sound else 1.0
		synth.strike(ImpactSynth.Source.WHEEL, speed, speed * struck_mass, contact_time * scale, where)
	if _from_air:
		_from_air = false
		last_impact = speed
		if speed <= land_start:
			return
		landings += 1
		var slam := speed >= land_slam_speed
		if slam:
			slams += 1
		land_player.stream = land_slam if slam else land_tap
		var g := pow(clampf((speed - land_start) / (land_full - land_start), 0.0, 1.0), land_curve)
		land_player.volume_db = land_db + linear_to_db(maxf(g, 0.02))
		land_player.play()
		if synth:
			synth.note_recording(land_player.stream, land_player.volume_db)
	elif speed > knock_start:
		knocks += 1
		knock_player.volume_db = knock_db + linear_to_db(clampf((speed - knock_start) / (knock_full - knock_start), 0.1, 1.0))
		knock_player.play()
		if synth:
			synth.note_recording(knock_player.stream, knock_player.volume_db)


## Fades one player toward target on this floor's loop. A new floor fades the old loop out first, then swaps.
func _drive(p: AudioStreamPlayer3D, f: CartFloorSound, gain: float, target: float, step: float, is_roll: bool) -> float:
	var current: CartFloorSound = _roll_sound if is_roll else _scrub_sound
	if f != current and f != null:
		if gain > 0.0:
			target = 0.0   # fade the old floor's loop out before swapping
		else:
			current = f
			p.stream = f.roll if is_roll else f.scrub
			if is_roll:
				_roll_sound = f
			else:
				_scrub_sound = f
	if current == null:
		return 0.0
	var g := move_toward(gain, target, step)
	_set_gain(p, g, (current.roll_db if is_roll else current.scrub_db) + wheel_db)
	return g


func _set_gain(p: AudioStreamPlayer3D, g: float, db: float) -> void:
	p.volume_db = db + linear_to_db(maxf(g, 0.0001))
	if g > 0.0 and not p.playing and p.stream:
		p.play(randf() * p.stream.get_length())   # each wheel starts somewhere else in the loop
	elif g <= 0.0 and p.playing:
		p.stop()
