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
## Every setting lives in the scene: the exports on this node and the masses on the bodies. The mobile web game
## gets a copy of them through tools/export_cart_tuning.gd.


@export_group("Hands")
## Hand power: holding a hand's key (Q/A left, E/D right) ramps that hand's push or pull from power_base, with no
## cap. The HUD shows it as that hand's bar. Pushing and pulling share the same base and ramp. As the arms strain,
## the wrists lever the bar (wrist_lever): pushing hard presses it down and the front wheels come up (a wheelie);
## pulling hard lifts it and the rear wheels come up onto the front casters, which breaks the back loose for a
## drift. W/S lean the cart on purpose (see "Lean keys"). Once the cart has fallen over and come to rest, any hand
## key hauls it back onto its wheels (see "Getting back up").
@export var power_base := 25.0      ## N per hand the moment a key goes down
@export var power_ramp := 120.0     ## N per second the hand's power grows while its key stays held
@export var power_relax := 400.0    ## N per second the bar falls back to zero once the key is let go
@export var sprint_speed := 5.0     ## m/s: a running player can't push (or pull) the cart faster than this
## m: the wrists' lever on the bar. Each hand twists the cart about its axle line by its power times this, whether
## or not the cart can speed up (a strained arm levers just as hard at a run). Push: nose up. Pull: nose down.
## The bigger it is, the less power it takes to lift an end. The push and pull themselves act at the height of
## the centre of mass, so they don't tilt the cart on their own.
@export var wrist_lever := 0.3
## true: the keyboard holds the bar. false: a spare cart nobody is holding, unless a driver (a bot, later a networked
## player) holds it through `controls`, pressing the same six keys a player does.
@export var player_controlled := true
## true: the groceries are taken out (spare carts in a level start empty).
@export var empty_basket := false
## Who holds the bar of a cart that isn't player_controlled: a CartBot (scripts/cart_bot.gd) today, a networked
## player later. null: a spare cart nobody holds.
var driver: Node = null
## The keys the driver is holding (action name -> true), set by the driver every physics step.
var controls := {}
## true: this cart only shows a cart simulated on another machine (a multiplayer guest's view, see
## scripts/net/net_session.gd). Its bodies stay frozen and the network moves them; nothing here pushes it.
var puppet := false
## true: nobody's hands are on the bar (a race countdown, scripts/race/race.gd). Every key reads as let go, the
## keyboard's and a driver's alike.
var locked := false
var puppet_velocity := Vector3.ZERO   ## a puppet's frame velocity on the host (for the HUD and the rolling sound)
var puppet_spin := 0.0                ## a puppet's turn rate on the host, rad/s
var hand_power := {"L": 0.0, "R": 0.0}   ## N each hand is putting into the bar: + push, - pull
@export_group("Lean keys")
## W tips the back up, S tips the front up, at any speed, toward a lean held by the wrists (capped torque). Keep
## holding past tip_delay and the lean keeps growing until the cart passes its balance point; then the hands slip
## off (let_go_pitch) and it falls over on its own, onto its nose for W, back onto the handle for S. With one hand
## key held as well, only that side leans (W lifts it, S drops it). A fallen cart: W or S hauls it back up.
@export var lift_pitch := -0.2      ## rad, W: nose down, rear wheels up
@export var press_pitch := 0.3      ## rad, S: nose up, front wheels up
@export var side_roll := 0.22       ## rad, W/S with one hand held
@export var tilt_kp := 1400.0       ## N*m per rad toward the lean
@export var tilt_kd := 80.0         ## N*m per rad/s
@export var tilt_max := 200.0       ## N*m the wrists can apply for a lean
@export var tip_delay := 0.6        ## s W/S is held at the normal lean before the lean starts growing
@export var tip_rate := 0.7         ## rad/s the lean grows by after that, for as long as W/S stays held
@export var let_go_pitch := 0.95    ## rad: past this the hands slip off the bar and the cart falls on its own
@export_group("Getting back up")
## The cart counts as fallen over once it lies past this tilt (cosine of the angle from upright) and has nearly
## stopped moving. Then, after every key has been let go once, a held hand key hauls it upright (a twist toward
## upright of the hand's power times wrist_lever), and so does W or S (tilt_max). The hands' push and pull fade out as the cart tips, so a fallen
## cart is levered up rather than shoved along the floor.
@export var fallen_upright := 0.3   ## cos of tilt: 0.3 is about 73 degrees over
@export var fallen_still := 1.0     ## rad/s: slower than this it has come to rest
@export var stood_upright := 0.95   ## cos of tilt: back up once it's within about 18 degrees of upright
@export_group("Hands")
@export var rolling_resistance := 0.015  ## fraction of each wheel's load that resists rolling (real casters: 0.01 to 0.02)
@export var settle_speed := 0.15    ## m/s: below this, with no hands on, the cart brakes to a stop
@export var settle_spin := 0.25     ## rad/s: same, for turning
@export var stop_speed := 0.05      ## m/s: below this for stop_delay s with nothing pressed, the cart stops dead
@export var stop_spin := 0.05       ## rad/s: same, for turning
var _rest_time := 0.0
@export var grip_yaw_damping := 30.0  ## N*m per rad/s: two hands on the bar resist the cart twisting
@export var spin_grip := 150.0      ## N per m/s: a hand working against the spin grabs the bar and holds it (up to brake_max)
@export var spin_grip_min := 0.1    ## rad/s: below this the cart isn't really spinning and nothing grabs
@export_group("Pulling and braking")
@export var arm_reach := 0.3        ## m each arm can straighten while the body is planted
@export var brake_spring := 350.0   ## N per m of arm extension, per hand: arms stiffen as they straighten
@export var brake_damping := 25.0   ## N per m/s, per hand
@export var brake_max := 120.0      ## N per hand: leaning back with full body weight
var arm_extension := {"L": 0.0, "R": 0.0}   ## m each arm is currently stretched past its relaxed bend
@export_group("Hands")
@export var hand_position := Vector3(0.0, 1.0, 0.2)   ## where the right hand grips the bar (cart local); the left is mirrored
@export var arm_relax_rate := 1.0   ## m/s an arm bends back in once the player stops braking
@export_group("Coming to rest")
@export var settle_brake := 40.0    ## how hard the cart brakes itself below settle_speed (per kg, and N*m per rad/s)
@export var stop_delay := 0.25      ## s of creeping below stop_speed before the cart stops dead
@export var settle_max_slope := 0.04   ## rise per run: on anything steeper the cart never settles, it rolls away
@export_group("")

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
## Read from the scene: the radius of the wheels' collision spheres.
@onready var wheel_radius: float = (($Wheel_FL/Shape as CollisionShape3D).shape as SphereShape3D).radius
var groceries: Array[RigidBody3D] = []
var hand_state := {"L": "", "R": ""}
var fallen := false                 ## lying over; the hands haul it back up
var _wait_release := false          ## fell over or got back up with keys held: the hands rest until they are let go
var _tilt_time := 0.0               ## s the current W/S has been held
var _tilt_dir := 0                  ## +1 S, -1 W, 0 neither
var _let_go := false                ## the hands slipped off on this W/S hold; it does nothing more until let go

var _links := []           ## [visual node, body, offset] kept in step every frame
var _frame_rest := Transform3D.IDENTITY   ## the frame's place relative to the cart's origin, as built
var _own_rids: Array[RID] = []   ## this cart's bodies, which its wheel-on-the-ground rays look past


func _ready() -> void:
	_frame_rest = global_transform.affine_inverse() * frame.global_transform
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
	for b in parts + groceries:
		_own_rids.append(b.get_rid())
	# Each rig pivot of the visual model follows its physics body.
	_link(_model, frame)
	_link(_model.find_child("Gate_Hinge"), gate)
	_link(_model.find_child("ChildSeat_Hinge"), child_seat)
	_link(_model.find_child("SeatFlap_Hinge"), seat_flap)
	for side in ["L", "R"]:
		_link(_model.find_child("Caster_F%s_Swivel" % side), forks["F" + side])
		_link(_model.find_child("Wheel_F%s_Axle" % side), wheels["F" + side])
		_link(_model.find_child("Wheel_R%s_Axle" % side), wheels["R" + side])


## Cart feel as the shared tuning dictionary (same keys as tuning/cart_tuning.json). The values come from this
## scene: the exports above and the bodies' masses. tools/export_cart_tuning.gd writes them out for the mobile game.
const TUNING_KEYS := ["power_base", "power_ramp", "power_relax", "sprint_speed", "wrist_lever",
	"lift_pitch", "press_pitch", "side_roll", "tilt_kp", "tilt_kd", "tilt_max", "tip_delay", "tip_rate", "let_go_pitch",
	"fallen_upright", "fallen_still", "stood_upright",
	"rolling_resistance", "grip_yaw_damping", "spin_grip", "spin_grip_min",
	"settle_speed", "settle_spin", "stop_speed", "stop_spin",
	"arm_reach", "brake_spring", "brake_damping", "brake_max", "arm_relax_rate", "settle_brake", "stop_delay",
	"settle_max_slope"]


func tuning() -> Dictionary:
	var t := {
		"frame_mass": ($Frame as RigidBody3D).mass,
		"wheel_mass": ($Wheel_FL as RigidBody3D).mass,
		"fork_mass": ($Fork_FL as RigidBody3D).mass,
		"gate_mass": ($Gate as RigidBody3D).mass,
	}
	for key in TUNING_KEYS:
		t[key] = get(key)
	return t


func _process(_delta: float) -> void:
	for l in _links:
		l[0].global_transform = l[1].global_transform * l[2]


const ACTIONS := ["push_left", "pull_left", "push_right", "pull_right", "lift", "press"]


## Whether a key is held: the player's keyboard (not while typing in a text box), or the driver's `controls` for
## any other cart.
func held(action: String) -> bool:
	if locked:
		return false
	if not player_controlled:
		return controls.get(action, false)
	var focus := get_viewport().gui_get_focus_owner()
	return Input.is_action_pressed(action) and not (focus is LineEdit or focus is TextEdit)


func _physics_process(delta: float) -> void:
	if puppet:
		return
	var any_input := false
	for a in ACTIONS:
		if held(a):
			any_input = true
			break
	if any_input and frame.freeze:
		_wake()
	if player_controlled or driver != null:
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
	# On a hill a cart left alone on its wheels rolls away, as a real one does: no braking, no pinning.
	if ground_slope() > settle_max_slope:
		_rest_time = 0.0
		return
	var v := frame.linear_velocity
	var w := frame.angular_velocity
	if v.length() < settle_speed and w.length() < settle_spin:
		frame.apply_central_force(-v * frame.mass * settle_brake)
		frame.apply_torque(-w * settle_brake)
	# Creeping this slowly for a moment with nothing pressed: stop dead and sleep, so it can't drift at all.
	if v.length() < stop_speed and w.length() < stop_spin and gate.angular_velocity.length() < 0.1:
		_rest_time += delta
		if _rest_time >= stop_delay:
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
	var mover := (body is RigidBody3D and not groceries.has(body)) or body is AnimatableBody3D   # props, carts, traffic
	if frame.freeze and mover and body.get_parent() != self:
		_wake()


func _wake() -> void:
	if puppet:
		return
	frame.freeze = false
	_rest_time = 0.0
	for b in [frame, gate, child_seat, seat_flap] + wheels.values() + forks.values():
		b.sleeping = false


## Each wheel resists rolling with a small torque, as real casters do. Also keeps the cart still on flat ground.
func _apply_rolling_resistance(delta: float) -> void:
	var total_mass := frame.mass + gate.mass + child_seat.mass + seat_flap.mass
	for b in wheels.values() + forks.values():
		total_mass += b.mass
	var max_torque := rolling_resistance * total_mass * 9.81 / 4.0 * wheel_radius
	for k in wheels:
		var w: RigidBody3D = wheels[k]
		if not wheel_on_ground(w):
			continue   # off the ground
		var axle := w.global_transform.basis.z.normalized()
		var spin := w.angular_velocity.dot(axle)
		var inertia := 0.5 * w.mass * wheel_radius * wheel_radius
		var t := minf(max_torque, absf(spin) * inertia / delta)   # never reverse the spin within one step
		w.apply_torque(-axle * signf(spin) * t)


func _apply_hands(delta: float) -> void:
	var xf := frame.global_transform
	var nose := xf.basis.x.normalized()
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	var com_g := xf * frame.center_of_mass
	var upright := xf.basis.y.normalized().y
	var any_key := false
	for a in ACTIONS:
		any_key = any_key or held(a)
	if not fallen and upright < fallen_upright and frame.angular_velocity.length() < fallen_still:
		fallen = true
		_wait_release = any_key
	elif fallen and upright > stood_upright:
		# Back on its wheels: the hands let go of the haul and rest until the keys are let go, so the power built
		# up hauling doesn't throw it straight over again.
		fallen = false
		_wait_release = any_key
		hand_power = {"L": 0.0, "R": 0.0}
	if not any_key:
		_wait_release = false
	# The push and pull drive the cart along the floor only while it stands: they fade out as it tips past 45
	# degrees and are gone by fallen_upright, so the nose pointing straight up can't send it skating. While it's
	# fallen over they stay off until it's back on its wheels.
	var drive_scale := 0.0 if fallen else clampf((upright - fallen_upright) / (0.7 - fallen_upright), 0.0, 1.0)
	# Stopping is when you pull back with no hand pushing while the cart is still rolling forward.
	# Push one hand and pull the other and it's a spin, not a stop.
	var pushing_any := held("push_left") or held("push_right")
	var cart_along := frame.linear_velocity.dot(fwd)
	# Which way the hands are trying to turn the cart: + = to the left (counter-clockwise from above).
	# A hand at lateral offset s (left -1, right +1) driving the bar along the nose by dir turns it by s * dir.
	var yaw_rate := frame.angular_velocity.dot(Vector3.UP)
	var dirs := {}
	var hand_yaw := {}
	for side in ["L", "R"]:
		var suffix := "left" if side == "L" else "right"
		dirs[side] = 0 if _wait_release else \
			int(held("push_" + suffix)) - int(held("pull_" + suffix))
		hand_yaw[side] = (-1.0 if side == "L" else 1.0) * dirs[side]
	var yaw_cmd: float = hand_yaw.L + hand_yaw.R

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var dir: int = dirs[side]
		# The hand's power: from power_base the moment its key goes down, growing for as long as it's held.
		# Switching from push to pull starts again from the base; letting go relaxes the bar back to zero.
		var p: float = hand_power[side]
		if dir == 0:
			p = move_toward(p, 0.0, power_relax * delta)
		else:
			p = maxf(p * dir, power_base) * dir + dir * power_ramp * delta
		hand_power[side] = p
		var strength := absf(p)
		var hand_g := xf * Vector3(hand_position.x, hand_position.y, s * hand_position.z)
		var drive_g := xf * Vector3(hand_position.x, frame.center_of_mass.y, s * hand_position.z)   # where the push acts
		var r := hand_g - com_g
		var v_hand := frame.linear_velocity + frame.angular_velocity.cross(r)
		var along := v_hand.dot(fwd)
		var st := ""
		if dir < 0 and not pushing_any and cart_along > 0.05 and along > 0.0:
			# Stopping a rolling cart: the body plants its feet and the arms straighten as the cart carries on.
			# Bent arms give a little; the further they straighten the harder they hold, up to leaning back
			# with full body weight. Out of reach, the player is dragged at that full force. A hand pulling
			# harder than that (its power) wins out, and a hard enough yank lifts the rear wheels.
			arm_extension[side] = minf(arm_reach, arm_extension[side] + along * delta)
			var f := minf(brake_max, brake_spring * arm_extension[side] + brake_damping * along)
			if arm_extension[side] >= arm_reach:
				f = brake_max
			frame.apply_force(-fwd * maxf(f, strength) * drive_scale, drive_g - frame.global_position)
			st = "braking %d N (arm %d%%)" % [roundi(maxf(f, strength)), roundi(100.0 * arm_extension[side] / arm_reach)]
		else:
			# Not braking: the body steps back in to its relaxed distance from the handle.
			arm_extension[side] = maxf(0.0, arm_extension[side] - arm_relax_rate * delta)
			if dir != 0:
				# A running person can only add force up to their running speed.
				var k := clampf(1.0 - dir * along / sprint_speed, 0.0, 1.0)
				frame.apply_force(fwd * dir * strength * k * drive_scale, drive_g - frame.global_position)
				st = ("pushing %d N" if dir > 0 else "pulling %d N") % roundi(strength)
		# Countering a spin: when the hands as a whole work against the way the cart is spinning, a hand doing so
		# grabs the bar and braces it, like a planted arm. The bar is a lever about half a metre behind the basket's
		# centre, so a hand holding up to brake_max there stops a spin within a fraction of a second. It acts as a
		# twist about the vertical only: the arm resists the yaw, it doesn't shove the cart over sideways.
		if hand_yaw[side] * yaw_rate < 0.0 and yaw_cmd * yaw_rate < 0.0 and absf(yaw_rate) > spin_grip_min:
			var lever := Vector2(r.x, r.z).length()
			var t := minf(brake_max * lever, spin_grip * lever * lever * absf(yaw_rate))
			frame.apply_torque(Vector3.UP * -signf(yaw_rate) * t)
			st = (st + " + " if st else "") + "holding the spin"
		if fallen:
			# Lying over: a held hand grabs the bar and hauls the cart back toward upright, whichever way it fell.
			# The wrists damp the swing (tilt_kd) so the cart settles onto its wheels instead of going over the other way.
			if dir != 0:
				var axis := xf.basis.y.normalized().cross(Vector3.UP)
				if axis.length() < 0.05:   # upside down: any horizontal axis will do
					axis = xf.basis.z
				axis = axis.normalized()
				var spin := frame.angular_velocity.dot(axis)
				frame.apply_torque(axis * (strength * wrist_lever - tilt_kd * spin))
				st = "hauling it upright"
			elif _wait_release:
				st = "let go, then hold to haul it up"
		elif dir != 0:
			# The wrists lever the bar by the hand's full power: a push raises the nose, a pull drops it. Each wrist
			# also damps the cart's pitching (tilt_kd, split between the hands), so a wheelie grows steadily
			# instead of flipping the cart the moment an end lifts.
			var pitch_axis := xf.basis.z.normalized()
			var pitch_rate := frame.angular_velocity.dot(pitch_axis)
			frame.apply_torque(pitch_axis * (dir * strength * wrist_lever - 0.5 * tilt_kd * pitch_rate))
		hand_state[side] = st

	# Grip: with both hands moving the same way the player resists the cart twisting (keeps it tracking when
	# pulled back). Opposite hands (spin) or one hand (turn) twist it freely.
	if dirs.L != 0 and dirs.L == dirs.R:
		frame.apply_torque(Vector3.UP * -grip_yaw_damping * yaw_rate)

	# Lean keys: W tips the back up, S the front, toward a lean with capped torque. Held on, the lean grows
	# (tip_rate) until the cart passes its balance point and the hands slip off (let_go_pitch). One hand key held
	# as well: only that side (W lifts it, S drops it). On a fallen cart, W or S hauls it back up instead.
	var lift := held("lift")
	var press := held("press")
	var tilt_dir := 0 if lift == press else (1 if press else -1)
	if tilt_dir != _tilt_dir:
		_tilt_dir = tilt_dir
		_tilt_time = 0.0
		_let_go = false
	if tilt_dir != 0:
		_tilt_time += delta
		if absf(asin(clampf(nose.y, -1, 1))) > let_go_pitch or upright < 0.0:
			_let_go = true
	if tilt_dir != 0 and fallen and not _wait_release:
		var axis := xf.basis.y.normalized().cross(Vector3.UP)
		if axis.length() < 0.05:
			axis = xf.basis.z
		axis = axis.normalized()
		frame.apply_torque(axis * (tilt_max - tilt_kd * frame.angular_velocity.dot(axis)))
		for side in ["L", "R"]:
			hand_state[side] = "hauling it upright"
	elif tilt_dir != 0 and not fallen and not _wait_release and not _let_go:
		var side_axis := xf.basis.z.normalized()
		var pitch := asin(clampf(nose.y, -1, 1))        # + = nose up
		var roll := asin(clampf(side_axis.y, -1, 1))    # + = right side up
		var sides := 0.0
		if (dirs.L != 0) != (dirs.R != 0):
			sides = 1.0 if dirs.R != 0 else -1.0
		var pitch_t := (lift_pitch if lift else press_pitch) * (0.6 if sides != 0.0 else 1.0)
		pitch_t += tilt_dir * tip_rate * maxf(0.0, _tilt_time - tip_delay)
		var roll_t := sides * (1.0 if lift else -1.0) * side_roll
		var w := frame.angular_velocity
		var tp := clampf(tilt_kp * (pitch_t - pitch) - tilt_kd * w.dot(side_axis), -tilt_max, tilt_max)
		var tr := clampf(tilt_kp * (roll_t - roll) + tilt_kd * w.dot(nose), -tilt_max, tilt_max)
		frame.apply_torque(side_axis * tp - nose * tr)   # rotating about -nose raises the right side
		for side in ["L", "R"]:
			var st: String = hand_state[side]
			hand_state[side] = (st + " + " if st else "") + ("leaning back up" if lift else "leaning front up")


## Cart origin (on the ground under the handle) in world space.
func cart_origin() -> Vector3:
	return frame.global_position


func heading() -> float:
	var n := frame.global_transform.basis.x
	return atan2(-n.z, n.x)


## The frame's velocity: from physics, or for a puppet the host's.
func frame_velocity() -> Vector3:
	return puppet_velocity if puppet else frame.linear_velocity


## The frame's turn rate (rad/s about up): from physics, or for a puppet the host's.
func frame_spin() -> float:
	return puppet_spin if puppet else frame.angular_velocity.y


## Every body of the rig, groceries last, in the order the network sends them.
func net_bodies() -> Array[RigidBody3D]:
	var list: Array[RigidBody3D] = [frame, gate, child_seat, seat_flap, forks.FL, forks.FR,
		wheels.FL, wheels.FR, wheels.RL, wheels.RR]
	list.append_array(groceries)
	return list


## Moves the whole rig (and whatever is in its basket) so the handle stands at `at`, upright and facing `yaw`, at
## rest. A bot cart or a spare one can be put somewhere else this way without being rebuilt.
func place(at: Vector3, yaw: float) -> void:
	var to := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.005, 0)) * _frame_rest
	var move := to * frame.global_transform.affine_inverse()
	for b in net_bodies():
		b.global_transform = move * b.global_transform
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	fallen = false
	_wait_release = false
	hand_power = {"L": 0.0, "R": 0.0}
	_wake()


## Turns this cart into a puppet: frozen, moved only by the network.
func make_puppet() -> void:
	puppet = true
	driver = null
	player_controlled = false
	for b in net_bodies():
		b.freeze = true


func wheels_down() -> int:
	var n := 0
	for k in wheels:
		if wheel_on_ground(wheels[k]):
			n += 1
	return n


## A wheel is on the ground when something solid is right under it (2 cm of air at most), on any floor or slope.
func wheel_on_ground(w: RigidBody3D) -> bool:
	return not _ground_hit(w).is_empty()


func _ground_hit(w: RigidBody3D) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(w.global_position,
		w.global_position + Vector3.DOWN * (wheel_radius + 0.02), 0x000f, _own_rids)
	return w.get_world_3d().direct_space_state.intersect_ray(q)


## Rise per run of the ground the cart stands on, from under its wheels (0 unless at least three are down).
func ground_slope() -> float:
	var n := Vector3.ZERO
	var down := 0
	for k in wheels:
		var hit := _ground_hit(wheels[k])
		if not hit.is_empty():
			n += hit.normal
			down += 1
	if down < 3:
		return 0.0
	n = n.normalized()
	return sqrt(maxf(0.0, 1.0 - n.y * n.y)) / maxf(n.y, 0.01)


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
