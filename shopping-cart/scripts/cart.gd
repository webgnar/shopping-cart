class_name ShoppingCart
extends Node3D
## The shopping cart as a real multi-body rig, driven only by the two hands on the handlebar.
##
## The rig is built in the editor in scenes/cart/cart.tscn (this script only drives it):
##  - Frame: 18 kg body with a hollow basket (floor, walls, lower tray, handlebar) and a Guard zone.
##  - Front casters: a fork that swivels 360 degrees on a vertical hinge, wheel trailing 3.8 cm behind.
##  - Rear wheels: fixed, spin on their axles.
##  - Gate: hinged at the top rail, swings into the basket 0 to 70 degrees.
##  - ChildSeat (the wire backrest): hinged on the gate at its bottom bar. It rests folded back against the gate and
##    the folded seat flap (its 0 stop), so when the gate swings up it carries it up; it opens 30 degrees into the basket.
##  - SeatFlap (the wire seat): its loops hook round a gate wire and are its hinge. Folded it stands up against the
##    gate's front (its 0 stop); pulled down it lies level as a seat at 98 degrees.
##  - SeatPlastic (the plastic plate on the seat): hinged on the seat by its loops. It lies on the seat (its 0 stop)
##    and lifts off it until it meets the gate.
##    All three seat hinges swing freely (no friction or damping).
##  - Groceries: loose bodies in the basket; add or move them under the Groceries node.
##  - Model: the rigged model (assets/models/shopping_cart.glb); its pivots follow the physics bodies.
## Cart local axes: nose = +X, up = +Y, left = -Z. Units: metres, kg, newtons.
## Every setting lives in the scene: the exports on this node and the masses on the bodies.


@export_group("Hands")
## Each hand has two things the player controls with one key (Q/A left push/pull, E/D right):
##  - How hard: holding the key ramps the hand's power from power_base, with no cap (hand_power, the HUD's meter).
##    The push it puts into the bar levels off toward drive_max. It acts where the hands are, at handle height,
##    along the arm from the body (body_point) to the hand: level when slow, a push angling up and a pull down
##    only as the body leans with speed. It acts at handle height, above the cart's centre of mass, so the
##    physics tips the cart only when pushing (or braking) hard at high speed; S and W on top add to or fight that.
##  - Where: tapping the key moves the hand out along the bar (hand_grip, 0 = hand_rest near the middle, 1 = the
##    end). Each press moves it out by tap_step, a quick press (tap_fast after the last) by up to tap_boost times
##    that, and it slides back in at grip_drain. Each press after the first is also a shove (tap_power on top of
##    the power), and between taps the hand stays on the bar, its power leaking away (tap_hold_leak). A hand
##    already at the end and going flat out (carry_power) slides the other hand toward it with each further tap
##    (carry_step, back at carry_drain), up to a hand's width away (hand_gap), so the turn keeps building.
## Each hand's push turns the cart by its force times its distance from the middle of the bar (right minus left),
## at any speed, and the push isn't capped by speed. A hand out at the end turns the cart harder; a push with one hand
## and a pull with the other turns it hardest. Held hands tire (fatigue): the arm's force wanders (wobble) and its
## grip on the cart's twist weakens, so a cart left on held keys drifts off line; a press freshens the arm.
## W/S lean the cart on purpose (see "Lean keys"). Once the cart has fallen over and come to rest, any hand key
## hauls it back onto its wheels (see "Getting back up").
@export var power_base := 25.0      ## N per hand the moment a key goes down
@export var power_ramp := 120.0     ## N per second the hand's power grows while its key stays held
@export var power_relax := 400.0    ## N per second the bar falls back to zero once the key is let go
@export var drive_max := 60.0       ## N per hand: the push (or pull) levels off toward this however hard the hand strains. A push at handle height (1 m) against a cart that isn't speeding up freely would tip it over the front wheels at its weight times 0.4 m (about 114 N for both hands, empty) if the hands didn't hold the handle down (hold_max)
@export var hand_rest := 0.14       ## m from the middle of the bar a hand slides back to
@export var hand_end := 0.25        ## m from the middle at the end of the bar (it is 0.52 m wide)
@export var tap_step := 0.15        ## how far out (of hand_rest to hand_end) one press moves the hand
@export var tap_boost := 2.5        ## a press tap_fast after the last moves it this many times further
@export var tap_fast := 0.12        ## s between presses for the full boost
@export var tap_slow := 0.6         ## s between presses for no boost
@export var tap_min_gap := 0.05     ## s a key must be up before the next press counts as a tap (no faster than a finger)
@export var grip_drain := 0.6       ## per second: how fast a hand slides back in toward hand_rest
@export var carry_power := 100.0    ## N: a hand at the end of the bar this hard at it, tapped again, slides the other hand toward it
@export var carry_step := 0.04      ## m the other hand slides per such tap (times the same boost as tap_step)
@export var carry_drain := 0.05     ## m per second a slid hand works its way back
@export var hand_gap := 0.1         ## m the hands stay apart (a hand's width)
@export var tap_power := 15.0      ## N a press within tap_slow of the last adds to the hand's power (a shove), times the same boost as tap_step
@export var tap_hold_leak := 1.2    ## per second: between taps, while the rhythm keeps going, the hand stays on the bar and its power leaks away by this fraction of itself, so a steady rhythm settles at a power set by how fast you tap
@export var fatigue_rate := 0.25    ## per second a held hand tires (1 = spent)
@export var fatigue_recover := 0.5  ## per second a released hand recovers
@export var tap_refresh := 0.12     ## fatigue a press takes off
@export var wobble := 0.15          ## a spent hand's force wanders by up to this fraction
@export var grip_fatigue_loss := 0.5   ## fraction of grip_yaw_damping a spent pair of arms loses
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
var hand_grip := {"L": 0.0, "R": 0.0}    ## where each hand holds the bar: 0 at hand_rest, 1 at hand_end
var hand_carry := {"L": 0.0, "R": 0.0}   ## m each hand has been slid toward the other's end (carry_step)
var hand_fatigue := {"L": 0.0, "R": 0.0} ## how tired each arm is, 0 fresh to 1 spent
var _hand_dir := {"L": 0, "R": 0}        ## each hand's key last step (+1 push, -1 pull, 0 up)
var _hand_last := {"L": 0, "R": 0}       ## each hand's last push (+1) or pull (-1)
var _hand_up := {"L": 1.0, "R": 1.0}     ## s each hand's key has been up
var _hand_since := {"L": 9.0, "R": 9.0}  ## s since each hand's last counted press
var _wobble_t := 0.0                     ## s of hand time, for the arms' wobble
var _idle_time := 0.0                    ## s since the last key on this cart's stack
var lean_power := 0.0                    ## N per hand on the handle from W (+, lifting) or S (-, pressing)
var _lean_prev := 0                      ## W/S last step: +1 W, -1 S, 0 neither
var _lean_last := 0                      ## the last one pressed
var _lean_up := 1.0                      ## s W and S have both been up
var _lean_since := 9.0                   ## s since the last counted W/S tap
var _last_velocity := Vector3.ZERO       ## the frame's velocity last step, for the cart's acceleration
var _body_lean := 0.0                    ## how far the player's body leans with the speed, -1 to 1 (body_lean())
## What each hand put on the handle in the last physics step, for the HUD's force diagram (world space):
## point (where it acts), arm (push or pull along the arm, N), lift (W/S, N, + up), damp (arms damping the handle,
## N, + up), twist (yaw it gives the cart, N*m, + turns left). grip_twist: both hands resisting the cart's twist.
var handle_forces := {}
var grip_twist := 0.0
var wheel_load := {"FL": 0.0, "FR": 0.0, "RL": 0.0, "RR": 0.0}   ## N the ground pushes up on each wheel
@export_group("Lean keys")
## W lifts the handle, S presses it down: a vertical force where the hands hold the bar, building while the key is
## held (lean_base, lean_ramp) up to what arms can do (lean_max). The physics does the rest: the cart tips about
## whichever wheels are on the ground. Lifting the handle pivots it on the front casters and raises the rear (about
## 140 N does it). Pressing (mostly down, press_angle back) pins the rear wheels and pivots the cart on them: a light
## press loads the rear and slows the cart, a hard one (about 200 N per hand, empty) lifts the front, as far as
## the arms can hold it (see below). W and S counter each other.
## With one hand key held as well, only that hand lifts or presses, so the cart rolls toward that side. The arms
## reach only so far: the force fades from full with the handle at rest to nothing at handle_low or handle_high,
## measured from the floor the player stands on (floor_height), so a lift or press tips the cart only as far as the
## arms can hold it and a cart off the floor is out of reach. A fallen cart: W or S hauls it
## back up (tilt_max).
@export var lean_base := 20.0       ## N per hand the moment W or S goes down
@export var lean_ramp := 120.0      ## N per second per hand it grows while held
@export var lean_max := 300.0       ## N per hand: the most the player can press (about their body weight leant on the bar)
@export var lift_max := 150.0       ## N per hand: the most the arms can lift
@export var lean_relax := 400.0     ## N per second it falls back once W/S is let go and the tapping has stopped
@export var lean_tap := 30.0        ## N a W/S press within tap_slow of the last adds (times the same boost as the hands' taps)
@export var lean_hold_leak := 1.0   ## per second: between W/S taps the hands keep pressing (or lifting) and the force only leaks away by this fraction of itself
@export var handle_low := 0.55      ## m above the ground: the arms can't press the handle lower than this
@export var handle_high := 1.5      ## m above the ground: nor lift it higher than this
@export var arm_damping := 80.0     ## N per m/s per hand: arms on the bar resist the handle moving up or down, so any tip comes on gradually
@export var hold_stiffness := 1500.0   ## N per m per hand: a hand pushing or pulling holds the handle at its resting height (hand_position.y above the floor), pressing it back as it rises or lifting it as it drops
@export var hold_max := 100.0       ## N per hand: the most the grip holds with. Both hands at the handle, 0.85 m behind the front wheels, add about 170 N*m against tipping forward, so a push has to pass roughly 280 N before the rear comes up
@export var press_angle := 10.0     ## degrees back from straight down that S presses at: mostly down, pinning the rear wheels so the cart pivots on them; the small back part slows the cart and, acting at handle height, adds to the lift
@export var shoulder_half := 0.2    ## m from the body's middle to each shoulder
@export var body_distance := 0.45   ## m the body is behind the bar with the cart standing still. Each arm pushes along the line from the body (body_point) to its hand, so a hand inside shoulder width pushes a little inward, one at the end a little outward
@export var lean_speed := 15.0     ## m/s the cart rolls at for the body's full lean (in toward the bar rolling forward, back from it rolling backward); standing still it is upright at body_distance, level with the bar. The lean grows with the square of the speed, so slow and medium speeds barely move it
@export var lean_rate := 0.05       ## per second: the most the lean changes, so the body closes in on the bar over many seconds (20 s for the full lean), never at once
@export var body_close := 0.3       ## m: how close to the bar the body is at full lean forward
@export var body_far := 0.6         ## m: how far back it stands at full lean backward
@export var body_drop := 0.04      ## m the body has dropped below the bar at full lean: from 0 at rest, so pushes and pulls start level and only angle (a push up, a pull down) as the speed builds
@export var tilt_kd := 80.0         ## N*m per rad/s: damping while W/S haul a fallen cart upright
@export var tilt_max := 200.0       ## N*m W/S apply hauling a fallen cart upright
@export_group("Getting back up")
## The cart counts as fallen over once it lies past this tilt (cosine of the angle from upright) and has nearly
## stopped moving. Then, after every key has been let go once, a held hand key hauls it upright (a twist toward
## upright of the hand's power times haul_lever), and so does W or S (tilt_max). The hands' push and pull fade out as the cart tips, so a fallen
## cart is levered up rather than shoved along the floor.
@export var fallen_upright := 0.3   ## cos of tilt: 0.3 is about 73 degrees over
@export var fallen_still := 1.0     ## rad/s: slower than this it has come to rest
@export var stood_upright := 0.95   ## cos of tilt: back up once it's within about 18 degrees of upright
@export var haul_lever := 0.3       ## m: a hand hauling a fallen cart upright twists it by its power times this
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
@export var brake_max := 40.0       ## N per hand: leaning back with full body weight (kept well under the roughly 108 N for both hands that lifts the front of the empty cart once it has stopped: its weight times 0.38 m, rear axle to centre of mass, over the 1 m handle height)
var arm_extension := {"L": 0.0, "R": 0.0}   ## m each arm is currently stretched past its relaxed bend
@export_group("Hands")
@export var hand_position := Vector3(0.0, 1.0, 0.2)   ## where the right hand grips the bar (cart local); the left is mirrored
@export var arm_relax_rate := 1.0   ## m/s an arm bends back in once the player stops braking
@export_group("Coming to rest")
@export var settle_delay := 0.4     ## s every key must be up before the cart starts settling (a rolling wheel has no static friction; only a cart left alone stops)
@export var settle_brake := 40.0    ## how hard the cart brakes itself below settle_speed (per kg, and N*m per rad/s)
@export var stop_delay := 0.25      ## s of creeping below stop_speed before the cart stops dead
@export var settle_max_slope := 0.04   ## rise per run: on anything steeper the cart never settles, it rolls away
@export_group("Stacks")
## m, seen from above: two carts that came apart collide again once their basket centres are this far apart
## (a cart is about a metre long, so they are clear of each other by then).
@export var ghost_clearance := 1.2
@export_group("")

const LAYER_WORLD := 1
const LAYER_CART := 2
const LAYER_CARGO := 4

@onready var frame: RigidBody3D = $Frame
@onready var gate: RigidBody3D = $Gate
@onready var child_seat: RigidBody3D = $ChildSeat
@onready var seat_flap: RigidBody3D = $SeatFlap
@onready var seat_plastic: RigidBody3D = $SeatPlastic
@onready var forks := {"FL": $Fork_FL, "FR": $Fork_FR}   ## RigidBody3D each
@onready var wheels := {"FL": $Wheel_FL, "FR": $Wheel_FR, "RL": $Wheel_RL, "RR": $Wheel_RR}   ## RigidBody3D each
@onready var _model: Node3D = $Model
## Read from the scene: the radius of the wheels' collision spheres.
@onready var wheel_radius: float = (($Wheel_FL/Shape as CollisionShape3D).shape as SphereShape3D).radius
var groceries: Array[RigidBody3D] = []
var hand_state := {"L": "", "R": ""}
var fallen := false                 ## lying over; the hands haul it back up
var _wait_release := false          ## fell over or got back up with keys held: the hands rest until they are let go

var _links := []           ## [visual node, body, offset] kept in step every frame
var _frame_rest := Transform3D.IDENTITY   ## the frame's place relative to the cart's origin, as built
var _own_rids: Array[RID] = []   ## this cart's bodies, which its wheel-on-the-ground rays look past

## Nesting (a stack of carts, see scripts/cart/cart_nest.gd): the cart this one's nose is tucked into, the cart
## tucked into this one's back, and the joint holding this cart in the one ahead. A stack is the chain of carts
## linked this way, front to back; it wakes, settles and stops as one.
var nested_in: ShoppingCart = null
var nested_behind: ShoppingCart = null
var nest: CartNest = null
## Carts this one passes through (their bodies don't collide with this cart's): every cart of its stack, and a
## cart that has just come apart from it until the two are clear of each other.
var ghosts := {}


func _ready() -> void:
	_frame_rest = global_transform.affine_inverse() * frame.global_transform
	for g in $Groceries.get_children():
		if empty_basket:
			g.queue_free()
		elif g is RigidBody3D:
			groceries.append(g)
	# Carts collide with other carts (their bodies' masks include LAYER_CART), but not with their own parts.
	var parts: Array = [frame, gate, child_seat, seat_flap, seat_plastic] + wheels.values() + forks.values()
	for a in parts:
		for b in parts:
			if a != b and not _touching(a, b):
				a.add_collision_exception_with(b)
	for b in parts + groceries:
		_own_rids.append(b.get_rid())
	add_to_group("carts")
	# Each rig pivot of the visual model follows its physics body.
	_link(_model, frame)
	_link(_model.find_child("Gate_Hinge"), gate)
	_link(_model.find_child("ChildSeat_Hinge"), child_seat)
	_link(_model.find_child("SeatFlap_Hinge"), seat_flap)
	_link(_model.find_child("SeatPlastic_Hinge"), seat_plastic)
	for side in ["L", "R"]:
		_link(_model.find_child("Caster_F%s_Swivel" % side), forks["F" + side])
		_link(_model.find_child("Wheel_F%s_Axle" % side), wheels["F" + side])
		_link(_model.find_child("Wheel_R%s_Axle" % side), wheels["R" + side])


## The cart's own bodies never collide with each other (the hinges hold them together), except these pairs: the
## backrest lies over the folded seat flap and holds it against the gate, and the seat plastic lifts until it meets
## the gate.
const TOUCHING_PARTS := [["ChildSeat", "SeatFlap"], ["Gate", "SeatPlastic"]]

func _process(_delta: float) -> void:
	for l in _links:
		l[0].global_transform = l[1].global_transform * l[2]


const ACTIONS := ["push_left", "pull_left", "push_right", "pull_right", "lift", "press"]


## Whether any of the six keys is held on this cart.
func keys_held() -> bool:
	if not player_controlled and driver == null:
		return false
	for a in ACTIONS:
		if held(a):
			return true
	return false


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
	_drop_clear_ghosts()
	# A stack is one herd: a key held on any of its carts keeps them all awake and rolling.
	var any_input := false
	for c in stack():
		if c.keys_held():
			any_input = true
			break
	if any_input and frame.freeze:
		_wake()
	if player_controlled or driver != null:
		_apply_hands(delta)
	_apply_rolling_resistance(delta)
	_idle_time = 0.0 if any_input else _idle_time + delta
	if _idle_time >= settle_delay:
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
		# In a stack, only once every cart of it has come to rest.
		if _rest_time >= stop_delay and stack().all(func(c): return c == self or c._rest_time >= c.stop_delay or c.frame.freeze):
			for c in stack():
				c._stop()
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
	for c in stack():
		c.frame.freeze = false
		c._rest_time = 0.0
		for b in [c.frame, c.gate, c.child_seat, c.seat_flap, c.seat_plastic] + c.wheels.values() + c.forks.values():
			b.sleeping = false


# ---------------------------------------------------------------- stacks

## The carts of this cart's stack, front to back (just this cart when it stands alone).
func stack() -> Array[ShoppingCart]:
	var front := self
	while front.nested_in != null:
		front = front.nested_in
	var list: Array[ShoppingCart] = []
	var c := front
	while c != null:
		list.append(c)
		c = c.nested_behind
	return list


## Every physics body of the rig, groceries included.
func bodies() -> Array[RigidBody3D]:
	var list: Array[RigidBody3D] = [frame, gate, child_seat, seat_flap, seat_plastic]
	list.append_array(wheels.values())
	list.append_array(forks.values())
	list.append_array(groceries)
	return list


## Mass of the whole rig (groceries left out).
func rig_mass() -> float:
	var m := frame.mass + gate.mass + child_seat.mass + seat_flap.mass + seat_plastic.mass
	for b in wheels.values() + forks.values():
		m += b.mass
	return m


## Lets this cart and `other` pass through each other (one is tucked inside the other): their bodies stop
## colliding, and neither's ground rays (wheels on the ground, wheel sounds) see the other.
func ghost(other: ShoppingCart) -> void:
	if other == self or ghosts.has(other):
		return
	ghosts[other] = true
	other.ghosts[self] = true
	for a in bodies():
		for b in other.bodies():
			a.add_collision_exception_with(b)
	for b in other.bodies():
		_own_rids.append(b.get_rid())
	for b in bodies():
		other._own_rids.append(b.get_rid())


## Undoes ghost(): the two carts collide again.
func unghost(other: ShoppingCart) -> void:
	if not ghosts.has(other):
		return
	ghosts.erase(other)
	other.ghosts.erase(self)
	if not is_instance_valid(other) or other.is_queued_for_deletion():
		return
	for a in bodies():
		for b in other.bodies():
			a.remove_collision_exception_with(b)
	for b in other.bodies():
		_own_rids.erase(b.get_rid())
	for b in bodies():
		other._own_rids.erase(b.get_rid())


## Carts that came apart from this one collide again once their baskets are clear of each other: the basket
## centres more than ghost_clearance apart, seen from above.
func _drop_clear_ghosts() -> void:
	if ghosts.is_empty():
		return
	var mine := stack()
	for other in ghosts.keys():
		if not is_instance_valid(other) or other.is_queued_for_deletion():
			ghosts.erase(other)
		elif not mine.has(other):
			var d: Vector3 = other.basket_centre() - basket_centre()
			if Vector2(d.x, d.z).length() > ghost_clearance:
				unghost(other)


## The middle of the basket, in world space.
func basket_centre() -> Vector3:
	return frame.global_transform * Vector3(0.47, 0.5, 0.0)


func _exit_tree() -> void:
	# Leaving the level (a reset, a level change): let go of the carts on either side.
	if nest:
		nest.come_apart()
	if nested_behind and nested_behind.nest:
		nested_behind.nest.come_apart()
	for other in ghosts.keys():
		if is_instance_valid(other):
			other.ghosts.erase(self)
	ghosts.clear()


## Each wheel resists rolling with a torque of rolling_resistance times the load on it (wheel_load, from
## _update_wheel_loads), as real wheels do: press down on the handle and the rear wheels drag harder. Also keeps
## the cart still on flat ground.
func _apply_rolling_resistance(delta: float) -> void:
	_update_wheel_loads(delta)
	for k in wheels:
		var w: RigidBody3D = wheels[k]
		if wheel_load[k] <= 0.0 or not wheel_on_ground(w):
			continue   # off the ground
		var max_torque: float = rolling_resistance * wheel_load[k] * wheel_radius
		var axle := w.global_transform.basis.z.normalized()
		var spin := w.angular_velocity.dot(axle)
		var inertia := 0.5 * w.mass * wheel_radius * wheel_radius
		var t := minf(max_torque, absf(spin) * inertia / delta)   # never reverse the spin within one step
		w.apply_torque(-axle * signf(spin) * t)


## How hard the ground pushes up on each wheel (wheel_load, N). Jolt's contact report only estimates a contact from
## the touching body itself (a wheel's own half kilo), not the frame resting on it through the axle, so the loads
## come from a moment balance on the cart's own geometry, seen from the side: the weight of the rig and the
## groceries at their combined centre of mass, every force the hands put on the handle where it acts, and the cart's
## own acceleration (braking shifts load forward). Whatever the ground must push back with is shared between the rear
## and front wheel pairs by their distance from each other; a pair that would have to pull down has lifted off.
## Each pair splits its share evenly, or puts it all on one wheel when the other is off the ground.
func _update_wheel_loads(delta: float) -> void:
	var nose := frame.global_transform.basis.x
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	var rear: Vector3 = (wheels.RL.global_position + wheels.RR.global_position) / 2.0 - Vector3(0, wheel_radius, 0)
	var front: Vector3 = (wheels.FL.global_position + wheels.FR.global_position) / 2.0 - Vector3(0, wheel_radius, 0)
	var span: float = (front - rear).dot(fwd)
	# Seen from the side: x forward from the rear contact, y up. moment = x * Fy - y * Fx (+ = nose up).
	var mass := 0.0
	var com := Vector3.ZERO
	for b in bodies():
		if b.freeze and b != frame:
			continue
		if b in groceries and not (b.visible and in_basket(b.global_position)):
			continue   # out of play, or fallen out onto the floor: its weight isn't on the wheels
		mass += b.mass
		com += b.mass * (b.global_transform * b.center_of_mass)
	com /= mass
	var accel := (frame.linear_velocity - _last_velocity) / delta
	_last_velocity = frame.linear_velocity
	var forces := [[com, Vector3.DOWN * mass * 9.81 - accel * mass]]   # weight, and the cart's inertia
	for side in handle_forces:
		var h: Dictionary = handle_forces[side]
		forces.append([h.point, h.arm + h.lean + Vector3.UP * h.damp])
	var moment := 0.0
	var up := 0.0
	for f in forces:
		var d: Vector3 = f[0] - rear
		var v: Vector3 = f[1]
		moment += d.dot(fwd) * v.y - d.y * v.dot(fwd)
		up += v.y
	var n_front := maxf(0.0, -moment / span) if span > 0.05 else 0.0
	var n_rear := maxf(0.0, -up - n_front)
	# Tipped onto one pair (the other in the air) the balance no longer holds: that pair carries it all.
	var rear_down := wheel_on_ground(wheels.RL) or wheel_on_ground(wheels.RR)
	var front_down := wheel_on_ground(wheels.FL) or wheel_on_ground(wheels.FR)
	if rear_down != front_down:
		n_rear = maxf(0.0, -up) if rear_down else 0.0
		n_front = maxf(0.0, -up) if front_down else 0.0
	for pair in [["RL", "RR", n_rear], ["FL", "FR", n_front]]:
		var a_on := wheel_on_ground(wheels[pair[0]])
		var b_on := wheel_on_ground(wheels[pair[1]])
		var share: float = pair[2]
		wheel_load[pair[0]] = 0.0 if not a_on else (share if not b_on else share / 2.0)
		wheel_load[pair[1]] = 0.0 if not b_on else (share if not a_on else share / 2.0)


func _apply_hands(delta: float) -> void:
	var xf := frame.global_transform
	for side in ["L", "R"]:
		handle_forces[side] = {"point": xf * Vector3(hand_position.x, hand_position.y, (-1.0 if side == "L" else 1.0) * hand_reach(side)),
			"arm": Vector3.ZERO, "lean": Vector3.ZERO, "damp": 0.0, "twist": 0.0}
	grip_twist = 0.0
	# The body leans with the speed only gradually: toward (speed / lean_speed) squared, at most lean_rate a second.
	var nose_flat := Vector3(xf.basis.x.x, 0, xf.basis.x.z).normalized()
	var speed_ahead := frame.linear_velocity.dot(nose_flat)
	var lean_target := signf(speed_ahead) * minf(1.0, pow(absf(speed_ahead) / lean_speed, 2.0))
	_body_lean = move_toward(_body_lean, lean_target, lean_rate * delta)
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
		hand_grip = {"L": 0.0, "R": 0.0}
		hand_carry = {"L": 0.0, "R": 0.0}
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

	_wobble_t += delta
	var drives := {}
	for side in ["L", "R"]:
		var dir: int = dirs[side]
		# A press: the key goes down (or switches between push and pull). It counts as a tap only after the key
		# was up for tap_min_gap, as fast as a finger can go: a tap moves the hand out along the bar (more the
		# sooner it follows the last tap), shoves the bar (tap_power) and freshens the arm.
		var p: float = hand_power[side]
		var tapped := false
		if dir != 0 and dir != _hand_dir[side]:
			tapped = _hand_up[side] >= tap_min_gap or _hand_dir[side] != 0
		_hand_up[side] = _hand_up[side] + delta if dir == 0 else 0.0
		_hand_dir[side] = dir
		_hand_since[side] += delta
		var boost := 1.0
		var shove := 0.0
		if tapped:
			# Only a press that follows another within tap_slow shoves the bar; the first press just grabs it.
			shove = tap_power if _hand_since[side] < tap_slow else 0.0
			var quick := clampf((tap_slow - _hand_since[side]) / (tap_slow - tap_fast), 0.0, 1.0)
			boost = lerpf(1.0, tap_boost, quick)
			# A hand already at the end, going as hard as it can (carry_power), has nowhere further to go: the tap
			# slides the other hand along toward it instead, so the turn keeps building. A tap of a hand that was slid
			# over first works it back out.
			var other := "R" if side == "L" else "L"
			var span := hand_end - hand_rest
			var back := minf(hand_carry[side], tap_step * boost * span)
			hand_carry[side] -= back
			var out: float = hand_grip[side] + tap_step * boost - back / span
			if out > 1.0 and signf(p) == dir and absf(p) >= carry_power:
				hand_carry[other] += carry_step * boost   # this tap would take the hand past the end
			hand_grip[side] = minf(1.0, out)
			hand_fatigue[side] = maxf(0.0, hand_fatigue[side] - tap_refresh)
			_hand_since[side] = 0.0
		hand_grip[side] = maxf(0.0, hand_grip[side] - grip_drain * delta)
		hand_carry[side] = maxf(0.0, hand_carry[side] - carry_drain * delta)
		hand_fatigue[side] = clampf(hand_fatigue[side] + (fatigue_rate if dir != 0 else -fatigue_recover) * delta, 0.0, 1.0)
		if dir != 0:
			_hand_last[side] = dir
		# Between taps, while the rhythm keeps going (the last tap under tap_slow ago), the hand stays on the bar and
		# keeps pushing (or pulling) the way it last did; its power only leaks away (tap_hold_leak).
		var in_rhythm: bool = dir == 0 and _hand_since[side] < tap_slow and _hand_last[side] != 0 and not _wait_release
		if in_rhythm:
			dirs[side] = _hand_last[side]
		# The hand's power: from power_base the moment its key goes down (plus the tap's shove), growing for as long
		# as it's held. Switching from push to pull starts again from the base; letting go relaxes it back to zero.
		if in_rhythm:
			p = move_toward(p, 0.0, absf(p) * tap_hold_leak * delta)
		elif dir == 0:
			p = move_toward(p, 0.0, power_relax * delta)
		else:
			p = maxf(p * dir, power_base) * dir + dir * (shove * boost + power_ramp * delta)
		hand_power[side] = p
		var strength := absf(p)
		# What the arm actually puts into the bar: it levels off toward drive_max, and a tired arm wanders (two
		# slow swells per hand, out of step with the other hand's, so the cart drifts off line over a few seconds).
		var phase := 0.0 if side == "L" else 2.1
		var wander := 0.6 * sin(TAU * 0.23 * _wobble_t + phase) + 0.4 * sin(TAU * 0.61 * _wobble_t + 2.0 * phase)
		drives[side] = drive_max * tanh(strength / drive_max) * (1.0 + wobble * hand_fatigue[side] * wander)

	# A slid hand stops a hand's width short of the other one.
	for side in ["L", "R"]:
		var other := "R" if side == "L" else "L"
		var own := lerpf(hand_rest, hand_end, hand_grip[side])
		hand_carry[side] = clampf(hand_carry[side], 0.0, maxf(0.0, own + hand_reach(other) - hand_gap))

	pushing_any = dirs.L > 0 or dirs.R > 0
	for side in ["L", "R"]:
		hand_yaw[side] = (-1.0 if side == "L" else 1.0) * dirs[side]
	yaw_cmd = hand_yaw.L + hand_yaw.R

	# Each hand's push acts where the hand holds the bar, at any speed. It moves the cart, and twists it by its force
	# times how far from the middle the hand holds it. So turning is each hand's force times its place on the bar: a hand out at
	# the end turns harder, a push and a pull turn hardest, and equal hands at equal places run straight.
	# The floor the player stands on, for how high the handle is above it.
	var ground_y := floor_height()
	# A handle up out of reach (past handle_high above the floor, or with no floor under it: the cart in the air or off
	# a ledge) can't be pushed, pulled or held.
	var can_hold := (xf * Vector3(hand_position.x, hand_position.y, 0.0)).y - ground_y <= handle_high

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var dir: int = dirs[side]
		var strength := absf(hand_power[side])
		var drive: float = drives[side]
		# Where the hand holds the bar: the push acts there, so a hand out at the end turns the cart harder.
		var reach := hand_reach(side)
		var hand_g := xf * Vector3(hand_position.x, hand_position.y, s * reach)
		var r := hand_g - com_g
		var v_hand := frame.linear_velocity + frame.angular_velocity.cross(r)
		var along := v_hand.dot(fwd)
		# The arm pushes along the line from its shoulder to its hand: seen from above, angled in or out by where the
		# hand is against shoulder width; seen from the side, from the body a little below the bar. Times dir: + pushes.
		var arm_dir := (hand_g - body_point(side)).normalized()
		if not can_hold and not fallen:
			arm_extension[side] = 0.0
			hand_state[side] = "out of reach" if dir != 0 else ""
			continue
		var st := ""
		if dir < 0 and not pushing_any and cart_along > 0.05 and along > 0.0:
			# Stopping a rolling cart: the body plants its feet and the arms straighten as the cart carries on.
			# Bent arms give a little; the further they straighten the harder they hold, up to leaning back
			# with full body weight. Out of reach, the player is dragged at that full force. A hand pulling
			# harder than that wins out, and a hard enough yank, back at handle height, lifts the front wheels.
			arm_extension[side] = minf(arm_reach, arm_extension[side] + along * delta)
			var f := minf(brake_max, brake_spring * arm_extension[side] + brake_damping * along)
			if arm_extension[side] >= arm_reach:
				f = brake_max
			frame.apply_force(-arm_dir * maxf(f, drive) * drive_scale, hand_g - frame.global_position)
			handle_forces[side].arm = -arm_dir * maxf(f, drive) * drive_scale
			st = "braking %d N (arm %d%%)" % [roundi(maxf(f, drive)), roundi(100.0 * arm_extension[side] / arm_reach)]
		else:
			# Not braking: the body steps back in to its relaxed distance from the handle.
			arm_extension[side] = maxf(0.0, arm_extension[side] - arm_relax_rate * delta)
			if dir != 0:
				# The whole arm force acts where the hand holds the bar, at any speed: the physics turns the cart by
				# its forward part times the hand's distance from the middle, and tips it by where it acts.
				var force := arm_dir * dir * drive * drive_scale
				frame.apply_force(force, hand_g - frame.global_position)
				handle_forces[side].arm = force
				handle_forces[side].twist += s * reach * force.dot(fwd)
				st = ("pushing %d N" if dir > 0 else "pulling %d N") % roundi(drive)
		if dir != 0 or hand_grip[side] > 0.05:
			st = (st + " " if st else "") + "at %d cm" % roundi(100.0 * reach)
		# Countering a spin: when the hands as a whole work against the way the cart is spinning, a hand doing so
		# grabs the bar and braces it, like a planted arm. The bar is a lever about half a metre behind the basket's
		# centre, so a hand holding up to brake_max there stops a spin within a fraction of a second. It acts as a
		# twist about the vertical only: the arm resists the yaw, it doesn't shove the cart over sideways.
		if hand_yaw[side] * yaw_rate < 0.0 and yaw_cmd * yaw_rate < 0.0 and absf(yaw_rate) > spin_grip_min:
			var lever := Vector2(r.x, r.z).length()
			var t := minf(brake_max * lever, spin_grip * lever * lever * absf(yaw_rate))
			frame.apply_torque(Vector3.UP * -signf(yaw_rate) * t)
			handle_forces[side].twist += -signf(yaw_rate) * t
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
				frame.apply_torque(axis * (strength * haul_lever - tilt_kd * spin))
				st = "hauling it upright"
			elif _wait_release:
				st = "let go, then hold to haul it up"
		hand_state[side] = st

	# Grip: with both hands moving the same way the player resists the cart twisting (keeps it tracking when
	# pulled back); a difference between the hands' pushes, or where they hold the bar, still turns it. Tired
	# arms hold the twist less (grip_fatigue_loss). Opposite hands (spin) or one hand (turn) twist it freely.
	if can_hold and dirs.L != 0 and dirs.L == dirs.R:
		var tired: float = 0.5 * (hand_fatigue.L + hand_fatigue.R)
		grip_twist = -grip_yaw_damping * (1.0 - grip_fatigue_loss * tired) * yaw_rate
		frame.apply_torque(Vector3.UP * grip_twist)

	# Lean keys: W lifts the handle, S presses it down, where the hands hold the bar. Like the hand keys: holding
	# builds the force (lean_ramp), and each press after the first, within tap_slow of the last, adds lean_tap (more
	# the quicker it follows, tap_boost). Between taps the hands keep at it and the force only leaks away
	# (lean_hold_leak); once the tapping stops it falls back (lean_relax). W and S together cancel. On a fallen
	# cart, W or S hauls it back up.
	var lift := held("lift")
	var press := held("press")
	var lean_dir := 0 if lift == press or _wait_release else (1 if lift else -1)
	var lean_tapped := lean_dir != 0 and lean_dir != _lean_prev and (_lean_up >= tap_min_gap or _lean_prev != 0)
	_lean_up = _lean_up + delta if lean_dir == 0 else 0.0
	_lean_prev = lean_dir
	_lean_since += delta
	var lean_shove := 0.0
	if lean_tapped:
		var quick := clampf((tap_slow - _lean_since) / (tap_slow - tap_fast), 0.0, 1.0)
		if _lean_since < tap_slow and lean_dir == _lean_last:
			lean_shove = lean_tap * lerpf(1.0, tap_boost, quick)
		_lean_since = 0.0
	if lean_dir != 0:
		_lean_last = lean_dir
	var lean_rhythm := lean_dir == 0 and _lean_since < tap_slow and _lean_last != 0 and not _wait_release
	if lean_rhythm:
		lean_power = move_toward(lean_power, 0.0, absf(lean_power) * lean_hold_leak * delta)
	elif lean_dir == 0:
		lean_power = move_toward(lean_power, 0.0, lean_relax * delta)
	else:
		var kept := absf(lean_power) if signf(lean_power) == lean_dir else 0.0
		lean_power = lean_dir * minf(lift_max if lean_dir > 0 else lean_max, maxf(kept, lean_base) + lean_shove + lean_ramp * delta)
	if lean_dir != 0 and fallen:
		var axis := xf.basis.y.normalized().cross(Vector3.UP)
		if axis.length() < 0.05:
			axis = xf.basis.z
		axis = axis.normalized()
		frame.apply_torque(axis * (tilt_max - tilt_kd * frame.angular_velocity.dot(axis)))
		for side in ["L", "R"]:
			hand_state[side] = "hauling it upright"
	elif not fallen:
		# With exactly one hand key held, only that hand lifts or presses; otherwise both do.
		var only := ""
		if (dirs.L != 0) != (dirs.R != 0):
			only = "R" if dirs.R != 0 else "L"
		var holding: bool = lean_power != 0.0 or dirs.L != 0 or dirs.R != 0
		for side in ["L", "R"]:
			var s := -1.0 if side == "L" else 1.0
			var hand_g := xf * Vector3(hand_position.x, hand_position.y, s * hand_reach(side))
			var v_hand := frame.linear_velocity + frame.angular_velocity.cross(hand_g - com_g)
			var lean := Vector3.ZERO
			var in_reach := hand_g.y - ground_y <= handle_high   # a handle up out of reach (or no floor under it) can't be held
			if lean_power != 0.0 and (only == "" or only == side) and in_reach:
				# Arms are strongest with the handle where it rests and weaken as they reach: lifting fades out
				# toward handle_high, pressing toward handle_low. So a lift or press tips the cart to where the arms
				# balance its weight, further the harder they work, and a cart off the floor is out of reach.
				var height := hand_g.y - ground_y
				var rest_h := hand_position.y
				var room := (handle_high - height) / (handle_high - rest_h) if lean_power > 0.0 \
					else (height - handle_low) / (rest_h - handle_low)
				var f := absf(lean_power) * clampf(room, 0.0, 1.0)
				if lean_power > 0.0:
					lean = Vector3.UP * f   # W lifts straight up
				else:   # S presses down and back toward the body (press_angle back from straight down)
					var a := deg_to_rad(press_angle)
					lean = (Vector3.DOWN * cos(a) - fwd * sin(a)) * f
			handle_forces[side].lean = lean
			var damp := 0.0
			if holding and in_reach:
				damp = -arm_damping * v_hand.y   # arms on the bar damp the handle bobbing
				# A hand pushing or pulling (and not lifting or pressing) holds the handle at its height: the rear
				# can't rise, nor one side, without lifting the handle against the grip. Up to hold_max per hand.
				if (dirs[side] != 0) and lean == Vector3.ZERO:
					var off := hand_g.y - ground_y - hand_position.y
					damp += clampf(-hold_stiffness * off, -hold_max, hold_max)
				handle_forces[side].damp = damp
			if lean != Vector3.ZERO or damp != 0.0:
				frame.apply_force(lean + Vector3.UP * damp, hand_g - frame.global_position)
			if lean_power != 0.0 and (only == "" or only == side):
				var st: String = hand_state[side]
				hand_state[side] = (st + " + " if st else "") + ("lifting %d N" if lean_power > 0.0 else "pressing %d N") % roundi(absf(lean_power))


## m from the middle of the bar where a hand holds it (side "L" or "R").
## How far the player's body leans with the cart's speed: 0 standing still, toward +1 at lean_speed forward (leaning
## in to keep up), toward -1 at lean_speed backward (leaning back). It follows the speed slowly (lean_rate).
func body_lean() -> float:
	return _body_lean


## How far behind the bar the player's body is (m): body_distance standing still, closing in toward body_close the
## faster the cart rolls forward, standing back toward body_far as it rolls backward.
func body_gap() -> float:
	var lean := body_lean()
	return lerpf(body_distance, body_close, lean) if lean >= 0.0 else lerpf(body_distance, body_far, -lean)


## Where the player drives the arm on `side` from (world space): body_gap behind the middle of the bar, shoulder_half
## to that side, and level with the bar at rest, dropping below it (up to body_drop) as the body leans with speed.
## The arms push from there to the hands: level when slow, a push angling up and a pull down only as the speed
## builds; how the cart then tips is the physics'.
func body_point(side: String) -> Vector3:
	var xf := frame.global_transform
	var nose := xf.basis.x
	var fwd := Vector3(nose.x, 0, nose.z).normalized()
	var lateral := Vector3(xf.basis.z.x, 0, xf.basis.z.z).normalized()
	var mid := xf * Vector3(hand_position.x, hand_position.y, 0.0)
	var s := -1.0 if side == "L" else 1.0
	return mid - Vector3(0, body_drop * absf(body_lean()), 0) - fwd * body_gap() + lateral * s * shoulder_half


func hand_reach(side: String) -> float:
	return lerpf(hand_rest, hand_end, hand_grip[side]) - hand_carry[side]


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
	var list: Array[RigidBody3D] = [frame, gate, child_seat, seat_flap, seat_plastic, forks.FL, forks.FR,
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


## What's right under a wheel (`gap` m of air at most): the ray hit (collider, position, normal), or empty.
func ground_hit(w: RigidBody3D, gap := 0.02) -> Dictionary:
	return _ground_hit(w, gap)


## Height of the floor the player stands on, under the middle of the handle (a ray down past the cart). The player's
## arms reach from there, so a cart in the air is out of reach. -INF: no floor within 3 m.
func floor_height() -> float:
	var mid := frame.global_transform * Vector3(hand_position.x, hand_position.y, 0.0)
	var q := PhysicsRayQueryParameters3D.create(mid, mid + Vector3.DOWN * 3.0, 0x000f, _own_rids)
	var hit := frame.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -INF


func _ground_hit(w: RigidBody3D, gap := 0.02) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(w.global_position,
		w.global_position + Vector3.DOWN * (wheel_radius + gap), 0x000f, _own_rids)
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
		if g.visible and in_basket(g.global_position):
			n += 1
	return n


## Whether two of the cart's own bodies touch each other (TOUCHING_PARTS) instead of passing through.
static func _touching(a: Node, b: Node) -> bool:
	for pair in TOUCHING_PARTS:
		if (a.name == pair[0] and b.name == pair[1]) or (a.name == pair[1] and b.name == pair[0]):
			return true
	return false


## Whether a point (world space) is inside the basket, or heaped on top of it up to 1.2 m off the floor.
func in_basket(p: Vector3) -> bool:
	var q := frame.global_transform.affine_inverse() * p
	return q.x > 0.05 and q.x < 1.0 and absf(q.z) < 0.33 and q.y > 0.4 and q.y < 1.2


## Where something dropped into the basket starts (cart-local): over the middle of the basket, a little above the
## rim, spread a bit by `spread` (-1 to 1 in each of x and z) so a run of drops doesn't land on one spot.
func basket_drop(spread: Vector2) -> Vector3:
	return Vector3(0.55 + 0.2 * spread.x, 1.08, 0.15 * spread.y)


## The cart's own groceries (the five under Groceries): shown and loose in the basket, or taken out of play
## (hidden, frozen, touching nothing), as for a supermarket sweep, where every cart starts empty.
func show_groceries(on: bool) -> void:
	for g in groceries:
		if g.visible == on:
			continue
		g.visible = on
		g.collision_layer = LAYER_CARGO if on else 0
		g.collision_mask = LAYER_WORLD | LAYER_CART | LAYER_CARGO if on else 0
		if not puppet:
			g.freeze = not on


func _link(node: Node3D, body: RigidBody3D) -> void:
	if node == null:
		push_warning("Cart model is missing a rig node for %s" % body.name)
		return
	_links.append([node, body, body.global_transform.affine_inverse() * node.global_transform])
