class_name ShoppingCart
extends Node3D
## The shopping cart as a real multi-body rig, driven only by the two hands on the handlebar.
##
## The rig is built in the editor in scenes/cart/cart.tscn (this script only drives it):
##  - Frame: 18 kg body with a hollow basket (floor, walls, lower tray, handlebar) and a Guard zone.
##  - Front casters: a fork that swivels 360 degrees on a vertical hinge, wheel trailing 3.8 cm behind.
##  - Rear wheels: fixed, spin on their axles.
##  - Gate: hinged at the top rail, swings into the basket 0 to 70 degrees.
##  - ChildSeat (backrest) and SeatFlap: hinged on the gate; the backrest folds back 0 to 30 degrees and
##    the flap folds up 0 to 105 degrees, both resting on their stops under gravity.
##  - Groceries: loose bodies in the basket; add or move them under the Groceries node.
##  - Model: the rigged model (assets/models/shopping_cart.glb); its pivots follow the physics bodies.
## Cart local axes: nose = +X, up = +Y, left = -Z. Units: metres, kg, newtons.
## Masses live on the bodies in the scene; tuning/cart_tuning.json overrides them at start.

const TUNING_PATH := "res://tuning/cart_tuning.json"   ## shared with the mobile web game

@export_group("Hands")
## Push gears: [N per hand, top walking speed m/s]. Scroll wheel or 1-5 picks one.
@export var gears: Array[Vector2] = [Vector2(25, 1.2), Vector2(35, 1.8), Vector2(45, 2.2), Vector2(65, 3.0), Vector2(90, 4.0)]
@export var gear := 3               ## 1-based, into `gears`
## false: a spare cart nobody is holding. It ignores the keys and only moves when something hits it.
@export var player_controlled := true
## true: the groceries are taken out (spare carts in a level start empty).
@export var empty_basket := false
var push_force := 45.0              ## N per hand (from the current gear)
var walk_max := 2.2                 ## m/s at which a walking hand stops adding force (from the current gear)
@export var rolling_resistance := 0.015  ## fraction of each wheel's load that resists rolling (real casters: 0.01 to 0.02)
@export var settle_speed := 0.15    ## m/s: below this, with no hands on, the cart brakes to a stop
@export var settle_spin := 0.25     ## rad/s: same, for turning
@export var stop_speed := 0.05      ## m/s: below this for 0.25 s with nothing pressed, the cart stops dead
@export var stop_spin := 0.05       ## rad/s: same, for turning
var _rest_time := 0.0
@export var grip_yaw_damping := 30.0  ## N*m per rad/s: two hands on the bar resist the cart twisting
@export var spin_grip := 150.0      ## N per m/s: a hand working against the spin grabs the bar and holds it (up to brake_max)
@export var spin_grip_min := 0.1    ## rad/s: below this the cart isn't really spinning and nothing grabs
@export_group("Pulling and braking")
@export var pull_ratio := 1.5       ## pulling (leaning back on your heels) is this much stronger than pushing
@export var arm_reach := 0.3        ## m each arm can straighten while the body is planted
@export var brake_spring := 350.0   ## N per m of arm extension, per hand: arms stiffen as they straighten
@export var brake_damping := 25.0   ## N per m/s, per hand
@export var brake_max := 110.0      ## N per hand: leaning back with full body weight
var arm_extension := {"L": 0.0, "R": 0.0}   ## m each arm is currently stretched past its relaxed bend
@export_group("Lift and press")
@export var lift_pitch := -0.2      ## rad, W: rear wheels up
@export var press_pitch := 0.3      ## rad, S: wheelie
@export var side_roll := 0.22       ## rad, W/S with one hand
@export var tilt_kp := 1400.0
@export var tilt_kd := 80.0
@export var tilt_max := 200.0       ## N*m the wrists can apply
@export var tip_delay := 0.6        ## s W/S is held at the normal lean before the player starts tipping further
@export var tip_rate := 0.7         ## rad/s the lean grows by after that, for as long as W/S stays held
@export var let_go_pitch := 0.95    ## rad: past this the hands slip off the bar and the cart falls on its own
var _tilt_time := 0.0               ## s the current W/S has been held
var _tilt_dir := 0                  ## +1 S (press), -1 W (lift), 0 none
var _let_go := false                ## the hands slipped off this hold; W/S does nothing until released

const COM := Vector3(0.45, 0.42, 0.0)    ## matches Frame's center_of_mass in the scene
const WHEEL_R := 0.0635                    ## matches the wheels' sphere radius in the scene
const HAND := Vector3(0.0, 1.0, 0.2)

const LAYER_WORLD := 1
const LAYER_CART := 2
const LAYER_CARGO := 4

@onready var frame: RigidBody3D = $Frame
@onready var gate: RigidBody3D = $Gate
@onready var child_seat: RigidBody3D = $ChildSeat
@onready var seat_flap: RigidBody3D = $SeatFlap
@onready var forks := {"FL": $Fork_FL, "FR": $Fork_FR}   ## RigidBody3D each
@onready var wheels := {"FL": $Wheel_FL, "FR": $Wheel_FR, "RL": $Wheel_RL, "RR": $Wheel_RR}   ## RigidBody3D each
@onready var _model: Node3D = $Model
var groceries: Array[RigidBody3D] = []
var hand_state := {"L": "", "R": ""}

var _links := []           ## [visual node, body, offset] kept in step every frame


func _ready() -> void:
	load_tuning()
	set_gear(gear)
	for g in $Groceries.get_children():
		if empty_basket:
			g.queue_free()
		elif g is RigidBody3D:
			groceries.append(g)
	# Carts collide with other carts (their bodies' masks include LAYER_CART), but not with their own parts.
	var parts: Array = [frame, gate, child_seat, seat_flap] + wheels.values() + forks.values()
	for a in parts:
		for b in parts:
			if a != b:
				a.add_collision_exception_with(b)
	# Each rig pivot of the visual model follows its physics body.
	_link(_model, frame)
	_link(_model.find_child("Gate_Hinge"), gate)
	_link(_model.find_child("ChildSeat_Hinge"), child_seat)
	_link(_model.find_child("SeatFlap_Hinge"), seat_flap)
	for side in ["L", "R"]:
		_link(_model.find_child("Caster_F%s_Swivel" % side), forks["F" + side])
		_link(_model.find_child("Wheel_F%s_Axle" % side), wheels["F" + side])
		_link(_model.find_child("Wheel_R%s_Axle" % side), wheels["R" + side])


## Reads the shared tuning file (also used by the mobile web game) over the values set in the scene.
func load_tuning() -> void:
	var t: Variant = load_tuning_file()
	if t == null:
		return
	for key in ["rolling_resistance", "grip_yaw_damping", "spin_grip", "spin_grip_min",
			"lift_pitch", "press_pitch", "side_roll", "tilt_kp", "tilt_kd", "tilt_max",
			"tip_delay", "tip_rate", "let_go_pitch",
			"settle_speed", "settle_spin", "stop_speed", "stop_spin",
			"pull_ratio", "arm_reach", "brake_spring", "brake_damping", "brake_max"]:
		if t.has(key):
			set(key, float(t[key]))
	if t.has("frame_mass"):
		frame.mass = float(t.frame_mass)
	if t.has("gate_mass"):
		gate.mass = float(t.gate_mass)
	for b in wheels.values():
		b.mass = float(t.get("wheel_mass", b.mass))
	for b in forks.values():
		b.mass = float(t.get("fork_mass", b.mass))
	if t.has("gears"):
		var g: Array[Vector2] = []
		for pair in t.gears:
			g.append(Vector2(pair[0], pair[1]))
		gears = g


static func load_tuning_file() -> Variant:
	if not FileAccess.file_exists(TUNING_PATH):
		push_warning("No tuning file at %s; using built-in defaults" % TUNING_PATH)
		return null
	var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))
	if typeof(t) != TYPE_DICTIONARY:
		push_warning("Could not read %s; using built-in defaults" % TUNING_PATH)
		return null
	return t


## Picks a push gear (1 = stroll ... 5 = run) and returns the gear actually set.
func set_gear(g: int) -> int:
	gear = clampi(g, 1, gears.size())
	push_force = gears[gear - 1].x
	walk_max = gears[gear - 1].y
	return gear


func _process(_delta: float) -> void:
	for l in _links:
		l[0].global_transform = l[1].global_transform * l[2]


const ACTIONS := ["push_left", "pull_left", "push_right", "pull_right", "lift", "press"]


func _physics_process(delta: float) -> void:
	var any_input := false
	if player_controlled:
		for a in ACTIONS:
			if Input.is_action_pressed(a):
				any_input = true
				break
	if any_input and frame.freeze:
		_wake()
	if player_controlled:
		_apply_hands(delta)
	_apply_rolling_resistance(delta)
	if not any_input:
		_settle(delta)
	else:
		_rest_time = 0.0


## Real carts have static friction: once nearly stopped with no hands pushing, they stay put. Jolt's contact
## friction lets the wheels creep (about 1 degree a second of slow spin), so near rest we brake the frame
## gently and let the bodies fall asleep. Any key wakes them.
func _settle(delta: float) -> void:
	if frame.freeze:
		return
	var v := frame.linear_velocity
	var w := frame.angular_velocity
	if v.length() < settle_speed and w.length() < settle_spin:
		frame.apply_central_force(-v * frame.mass * 40.0)
		frame.apply_torque(-w * 40.0)
	# Creeping this slowly for a moment with nothing pressed: stop dead and sleep, so it can't drift at all.
	if v.length() < stop_speed and w.length() < stop_spin and gate.angular_velocity.length() < 0.1:
		_rest_time += delta
		if _rest_time >= 0.25:
			_stop()
	else:
		_rest_time = 0.0


## Pins the frame exactly where it is (the wheels, casters, gate and seat stay live). Any key, or a loose object
## knocking into the cart, releases it.
func _stop() -> void:
	for b in [frame] + wheels.values() + forks.values():
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	frame.freeze = true


## A loose object or another cart (not this cart's own parts or groceries) is about to hit the pinned cart:
## let physics take it again.
func _on_frame_hit(body: Node) -> void:
	if frame.freeze and body is RigidBody3D and not groceries.has(body) and body.get_parent() != self:
		_wake()


func _wake() -> void:
	frame.freeze = false
	_rest_time = 0.0
	for b in [frame, gate, child_seat, seat_flap] + wheels.values() + forks.values():
		b.sleeping = false


## Each wheel resists rolling with a small torque, as real casters do. Also keeps the cart still on flat ground.
func _apply_rolling_resistance(delta: float) -> void:
	var total_mass := frame.mass + gate.mass + child_seat.mass + seat_flap.mass
	for b in wheels.values() + forks.values():
		total_mass += b.mass
	var max_torque := rolling_resistance * total_mass * 9.81 / 4.0 * WHEEL_R
	for k in wheels:
		var w: RigidBody3D = wheels[k]
		if w.global_position.y > WHEEL_R + 0.02:
			continue   # off the ground
		var axle := w.global_transform.basis.z.normalized()
		var spin := w.angular_velocity.dot(axle)
		var inertia := 0.5 * w.mass * WHEEL_R * WHEEL_R
		var t := minf(max_torque, absf(spin) * inertia / delta)   # never reverse the spin within one step
		w.apply_torque(-axle * signf(spin) * t)


func _apply_hands(delta: float) -> void:
	var xf := frame.global_transform
	var nose := xf.basis.x.normalized()
	var side_axis := xf.basis.z.normalized()
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	var com_g := xf * COM
	var lift := Input.is_action_pressed("lift")
	var press := Input.is_action_pressed("press")
	var held := {
		"L": Input.is_action_pressed("push_left") or Input.is_action_pressed("pull_left"),
		"R": Input.is_action_pressed("push_right") or Input.is_action_pressed("pull_right"),
	}
	var none_held: bool = not held.L and not held.R
	# Stopping is when you pull back with no hand pushing while the cart is still rolling forward.
	# Push one hand and pull the other and it's a spin, not a stop.
	var pushing_any := Input.is_action_pressed("push_left") or Input.is_action_pressed("push_right")
	var cart_along := frame.linear_velocity.dot(fwd)
	# Which way the hands are trying to turn the cart: + = to the left (counter-clockwise from above).
	# A hand at lateral offset s (left -1, right +1) driving the bar along the nose by dir turns it by s * dir.
	var yaw_rate := frame.angular_velocity.dot(Vector3.UP)
	var hand_yaw := {}
	for side in ["L", "R"]:
		var suffix := "left" if side == "L" else "right"
		var dir := int(Input.is_action_pressed("push_" + suffix)) - int(Input.is_action_pressed("pull_" + suffix))
		hand_yaw[side] = (-1.0 if side == "L" else 1.0) * dir
	var yaw_cmd: float = hand_yaw.L + hand_yaw.R

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var suffix := "left" if side == "L" else "right"
		var hand_g := xf * Vector3(HAND.x, HAND.y, s * HAND.z)
		var r := hand_g - com_g
		var v_hand := frame.linear_velocity + frame.angular_velocity.cross(r)
		var dir := int(Input.is_action_pressed("push_" + suffix)) - int(Input.is_action_pressed("pull_" + suffix))
		var along := v_hand.dot(fwd)
		var st := ""
		if dir < 0 and not pushing_any and cart_along > 0.05 and along > 0.0:
			# Stopping a rolling cart: the body plants its feet and the arms straighten as the cart carries on.
			# Bent arms give a little; the further they straighten the harder they hold, up to leaning back
			# with full body weight. Out of reach, the player is dragged at that full force.
			arm_extension[side] = minf(arm_reach, arm_extension[side] + along * delta)
			var f := minf(brake_max, brake_spring * arm_extension[side] + brake_damping * along)
			if arm_extension[side] >= arm_reach:
				f = brake_max
			frame.apply_force(-fwd * f, hand_g - frame.global_position)
			st = "braking (arm %d%%)" % roundi(100.0 * arm_extension[side] / arm_reach)
		else:
			# Not braking: the body steps back in to its relaxed distance from the handle.
			arm_extension[side] = maxf(0.0, arm_extension[side] - 1.0 * delta)
			if dir != 0:
				# A walking person can only add force up to their walking speed. Pulling back with both hands (leaning
				# back on your heels) is stronger; with one hand pushing, your weight is forward, so the pull matches the push.
				var k := clampf(1.0 - dir * along / walk_max, 0.0, 1.0)
				var strength := push_force * (pull_ratio if dir < 0 and not pushing_any else 1.0)
				frame.apply_force(fwd * dir * strength * k, hand_g - frame.global_position)
				st = "pushing" if dir > 0 else "pulling"
		# Countering a spin: when the hands as a whole work against the way the cart is spinning, a hand doing so
		# grabs the bar and braces it, like a planted arm. The bar is a lever about half a metre behind the basket's
		# centre, so a hand holding up to brake_max there stops a spin within a fraction of a second. It acts as a
		# twist about the vertical only: the arm resists the yaw, it doesn't shove the cart over sideways.
		if hand_yaw[side] * yaw_rate < 0.0 and yaw_cmd * yaw_rate < 0.0 and absf(yaw_rate) > spin_grip_min:
			var lever := Vector2(r.x, r.z).length()
			var t := minf(brake_max * lever, spin_grip * lever * lever * absf(yaw_rate))
			frame.apply_torque(Vector3.UP * -signf(yaw_rate) * t)
			st = (st + " + " if st else "") + "holding the spin"
		if (lift or press) and (held[side] or none_held):
			st = (st + " + " if st else "") + ("lost grip" if _let_go else ("lifting" if lift else "pressing"))
		hand_state[side] = st

	# Grip: with both hands moving the same way the player resists the cart twisting (keeps it tracking when
	# pulled back). Opposite hands (spin) or one hand (turn) twist it freely.
	var same_way := (Input.is_action_pressed("push_left") and Input.is_action_pressed("push_right")) \
		or (Input.is_action_pressed("pull_left") and Input.is_action_pressed("pull_right"))
	if same_way:
		frame.apply_torque(Vector3.UP * -grip_yaw_damping * yaw_rate)

	# Tilt: the wrists roll the bar toward a target angle with capped torque.
	# W lifts the bar (rear wheels up), S presses it down (wheelie). One hand held = that side only.
	# Keep holding and the lean keeps growing (tip_rate) until the cart passes its balance point; then the
	# hands slip off (let_go_pitch) and it falls over on its own, nose first for W, onto the handle for S.
	var tilt_dir := 0 if lift == press else (1 if press else -1)
	if tilt_dir != _tilt_dir:
		_tilt_dir = tilt_dir
		_tilt_time = 0.0
		_let_go = false
	if tilt_dir != 0:
		_tilt_time += delta
		var pitch := asin(clampf(nose.y, -1, 1))        # + = nose up
		if pitch * tilt_dir > let_go_pitch or xf.basis.y.y < 0.0:
			_let_go = true
	if tilt_dir != 0 and not _let_go:
		var pitch := asin(clampf(nose.y, -1, 1))        # + = nose up
		var roll := asin(clampf(side_axis.y, -1, 1))    # + = right side up
		var sides := 0.0
		if not none_held and not (held.L and held.R):
			sides = 1.0 if held.R else -1.0
		var pitch_t := (lift_pitch if lift else press_pitch) * (0.6 if sides != 0.0 else 1.0)
		pitch_t += tilt_dir * tip_rate * maxf(0.0, _tilt_time - tip_delay)
		var roll_t := sides * (1.0 if lift else -1.0) * side_roll
		var w := frame.angular_velocity
		var tp := clampf(tilt_kp * (pitch_t - pitch) - tilt_kd * w.dot(side_axis), -tilt_max, tilt_max)
		var tr := clampf(tilt_kp * (roll_t - roll) + tilt_kd * w.dot(nose), -tilt_max, tilt_max)
		frame.apply_torque(side_axis * tp - nose * tr)   # rotating about -nose raises the right side


## Cart origin (on the ground under the handle) in world space.
func cart_origin() -> Vector3:
	return frame.global_position


func heading() -> float:
	var n := frame.global_transform.basis.x
	return atan2(-n.z, n.x)


func wheels_down() -> int:
	var n := 0
	for k in wheels:
		if wheels[k].global_position.y < WHEEL_R + 0.02:
			n += 1
	return n


func groceries_in_basket() -> int:
	var n := 0
	for g in groceries:
		var p := frame.global_transform.affine_inverse() * g.global_position
		if p.x > 0.05 and p.x < 1.0 and absf(p.z) < 0.33 and p.y > 0.4 and p.y < 1.2:
			n += 1
	return n


func _link(node: Node3D, body: RigidBody3D) -> void:
	if node == null:
		push_warning("Cart model is missing a rig node for %s" % body.name)
		return
	_links.append([node, body, body.global_transform.affine_inverse() * node.global_transform])
