class_name ShoppingCart
extends Node3D
## The shopping cart as a real multi-body rig, driven only by the two hands on the handlebar.
##
## Built in code from the rigged model (assets/models/shopping_cart.glb):
##  - Frame: 18 kg body with a hollow basket (floor, walls, lower tray, handlebar).
##  - Front casters: a fork that swivels 360 degrees on a vertical hinge, wheel trailing 3.8 cm behind.
##  - Rear wheels: fixed, spin on their axles.
##  - Gate: hinged at the top rail, swings into the basket 0 to 70 degrees (child seat and flap ride on it).
## Cart local axes: nose = +X, up = +Y, left = -Z. Units: metres, kg, newtons.

const MODEL := preload("res://assets/models/shopping_cart.glb")

@export_group("Masses")
@export var frame_mass := 18.0
@export var wheel_mass := 0.5
@export var fork_mass := 0.6
@export var gate_mass := 1.5
@export_group("Hands")
@export var push_force := 45.0      ## N per hand
@export var walk_max := 2.2         ## m/s at which a walking hand stops adding force
@export var rolling_resistance := 0.015  ## fraction of each wheel's load that resists rolling (real casters: 0.01 to 0.02)
@export var grip_yaw_damping := 30.0  ## N*m per rad/s: two hands on the bar resist the cart twisting
@export_group("Lift and press")
@export var lift_pitch := -0.2      ## rad, W: rear wheels up
@export var press_pitch := 0.3      ## rad, S: wheelie
@export var side_roll := 0.22       ## rad, W/S with one hand
@export var tilt_kp := 1400.0
@export var tilt_kd := 80.0
@export var tilt_max := 200.0       ## N*m the wrists can apply

const COM := Vector3(0.45, 0.42, 0.0)
const WHEEL_R := 0.0635
const WHEEL_W := 0.04
const REAR_AXLE := Vector3(0.0685, 0.062, 0.3045)
const KINGPIN := Vector3(0.887, 0.16, 0.1545)
const FRONT_AXLE := Vector3(0.849, 0.063, 0.1545)
const HAND := Vector3(0.0, 1.0, 0.2)
const GATE_HINGE := Vector3(0.068, 0.985, 0.0)
const GATE_OPEN_DEG := 70.0

const LAYER_WORLD := 1
const LAYER_CART := 2
const LAYER_CARGO := 4

const GROCERIES := [
	# size, mass kg, colour, spot in the basket (cart local)
	[Vector3(0.18, 0.26, 0.07), 0.6, Color("e94f37"), Vector3(0.75, 0.62, -0.12)],
	[Vector3(0.12, 0.12, 0.12), 1.2, Color("3e92cc"), Vector3(0.40, 0.55, 0.15)],
	[Vector3(0.22, 0.10, 0.15), 1.5, Color("f6c445"), Vector3(0.62, 0.56, 0.12)],
	[Vector3(0.10, 0.20, 0.10), 1.0, Color("6dbf67"), Vector3(0.85, 0.58, 0.16)],
	[Vector3(0.16, 0.08, 0.16), 0.8, Color("ffffff"), Vector3(0.42, 0.52, -0.15)],
]

var frame: RigidBody3D
var gate: RigidBody3D
var forks := {}            ## "FL", "FR" -> RigidBody3D
var wheels := {}           ## "FL", "FR", "RL", "RR" -> RigidBody3D
var groceries: Array[RigidBody3D] = []
var hand_state := {"L": "", "R": ""}

var _model: Node3D
var _links := []           ## [visual node, body, offset] kept in step every frame


func _ready() -> void:
	_build()


func _build() -> void:
	var wheel_mat := PhysicsMaterial.new()
	wheel_mat.friction = 1.0   # Godot uses the lower friction of the pair, so the floor decides grip
	var cart_mat := PhysicsMaterial.new()
	cart_mat.friction = 0.5

	# Frame
	frame = _body("Frame", frame_mass, Vector3.ZERO, LAYER_CART, LAYER_WORLD | LAYER_CARGO)
	frame.physics_material_override = cart_mat
	frame.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	frame.center_of_mass = COM
	_box(frame, Vector3(0.72, 0.024, 0.58), Vector3(0.57, 0.46, 0))     # basket floor
	_box(frame, Vector3(0.03, 0.50, 0.60), Vector3(0.95, 0.71, 0))      # front wall
	_box(frame, Vector3(0.84, 0.50, 0.03), Vector3(0.53, 0.71, -0.30))  # left wall
	_box(frame, Vector3(0.84, 0.50, 0.03), Vector3(0.53, 0.71, 0.30))   # right wall
	_box(frame, Vector3(0.70, 0.06, 0.56), Vector3(0.57, 0.22, 0))      # lower tray
	_box(frame, Vector3(0.06, 0.06, 0.52), Vector3(0.0, 1.0, 0))        # handlebar

	# Gate: hangs from the top rail, leans back about 18 degrees, swings forward into the basket.
	gate = _body("Gate", gate_mass, GATE_HINGE, LAYER_CART, LAYER_WORLD | LAYER_CARGO)
	gate.physics_material_override = cart_mat
	_box(gate, Vector3(0.03, 0.54, 0.56), Vector3(0.087, -0.265, 0), -0.32)
	var gj := _hinge(frame, gate, GATE_HINGE, Basis.IDENTITY)
	gj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	# Godot's hinge angle runs opposite to Blender's: negative = swung forward into the basket.
	gj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -deg_to_rad(GATE_OPEN_DEG))
	gj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 0.0)

	var swivel_axis := Basis(Vector3.RIGHT, -PI / 2)   # hinge axis is the joint's local Z; this turns it to +Y
	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		# Rear: fixed wheel on an axle.
		var rp := Vector3(REAR_AXLE.x, REAR_AXLE.y, s * REAR_AXLE.z)
		var rw := _wheel("Wheel_R" + side, rp, wheel_mat)
		_hinge(frame, rw, rp, Basis.IDENTITY)
		wheels["R" + side] = rw
		# Front: fork swivels freely about the kingpin; the wheel trails behind it.
		var kp := Vector3(KINGPIN.x, KINGPIN.y, s * KINGPIN.z)
		var fork := _body("Fork_F" + side, fork_mass, kp, 0, 0)
		fork.angular_damp = 2.0   # a little swivel friction so the casters settle instead of fluttering forever
		_box(fork, Vector3(0.05, 0.10, 0.04), Vector3(-0.02, -0.05, 0))
		_hinge(frame, fork, kp, swivel_axis)
		var fp := Vector3(FRONT_AXLE.x, FRONT_AXLE.y, s * FRONT_AXLE.z)
		var fw := _wheel("Wheel_F" + side, fp, wheel_mat)
		_hinge(fork, fw, fp, Basis.IDENTITY)
		forks["F" + side] = fork
		wheels["F" + side] = fw

	# Groceries, loose in the basket.
	for g in GROCERIES:
		var b := _body("Grocery", g[1], g[3], LAYER_CARGO, LAYER_WORLD | LAYER_CART | LAYER_CARGO)
		_box(b, g[0], Vector3.ZERO, 0.0, g[2])
		groceries.append(b)

	# Visual model, with each rig pivot following its physics body.
	_model = MODEL.instantiate()
	add_child(_model)
	_model.transform = Transform3D.IDENTITY
	_link(_model, frame)
	_link(_model.find_child("Gate_Hinge"), gate)
	for side in ["L", "R"]:
		_link(_model.find_child("Caster_F%s_Swivel" % side), forks["F" + side])
		_link(_model.find_child("Wheel_F%s_Axle" % side), wheels["F" + side])
		_link(_model.find_child("Wheel_R%s_Axle" % side), wheels["R" + side])


func _process(_delta: float) -> void:
	for l in _links:
		l[0].global_transform = l[1].global_transform * l[2]


func _physics_process(delta: float) -> void:
	_apply_hands()
	_apply_rolling_resistance(delta)


## Each wheel resists rolling with a small torque, as real casters do. Also keeps the cart still on flat ground.
func _apply_rolling_resistance(delta: float) -> void:
	var total_mass := frame_mass + gate_mass + 4.0 * wheel_mass + 2.0 * fork_mass
	var max_torque := rolling_resistance * total_mass * 9.81 / 4.0 * WHEEL_R
	for k in wheels:
		var w: RigidBody3D = wheels[k]
		if w.global_position.y > WHEEL_R + 0.02:
			continue   # off the ground
		var axle := w.global_transform.basis.z.normalized()
		var spin := w.angular_velocity.dot(axle)
		var inertia := 0.5 * wheel_mass * WHEEL_R * WHEEL_R
		var t := minf(max_torque, absf(spin) * inertia / delta)   # never reverse the spin within one step
		w.apply_torque(-axle * signf(spin) * t)


func _apply_hands() -> void:
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

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var suffix := "left" if side == "L" else "right"
		var hand_g := xf * Vector3(HAND.x, HAND.y, s * HAND.z)
		var r := hand_g - com_g
		var v_hand := frame.linear_velocity + frame.angular_velocity.cross(r)
		var dir := int(Input.is_action_pressed("push_" + suffix)) - int(Input.is_action_pressed("pull_" + suffix))
		var st := ""
		if dir != 0:
			# A walking person can only add force up to their walking speed.
			var k := clampf(1.0 - dir * v_hand.dot(fwd) / walk_max, 0.0, 1.0)
			frame.apply_force(fwd * dir * push_force * k, hand_g - frame.global_position)
			st = "pushing" if dir > 0 else "pulling"
		if (lift or press) and (held[side] or none_held):
			st = (st + " + " if st else "") + ("lifting" if lift else "pressing")
		hand_state[side] = st

	# Grip: with both hands moving the same way the player resists the cart twisting (keeps it tracking when
	# pulled back). Opposite hands (spin) or one hand (turn) twist it freely.
	var same_way := (Input.is_action_pressed("push_left") and Input.is_action_pressed("push_right")) \
		or (Input.is_action_pressed("pull_left") and Input.is_action_pressed("pull_right"))
	if same_way:
		var yaw_rate := frame.angular_velocity.dot(Vector3.UP)
		frame.apply_torque(Vector3.UP * -grip_yaw_damping * yaw_rate)

	# Tilt: the wrists roll the bar toward a target angle with capped torque.
	# W lifts the bar (rear wheels up), S presses it down (wheelie). One hand held = that side only.
	if lift != press:
		var pitch := asin(clampf(nose.y, -1, 1))        # + = nose up
		var roll := asin(clampf(side_axis.y, -1, 1))    # + = right side up
		var sides := 0.0
		if not none_held and not (held.L and held.R):
			sides = 1.0 if held.R else -1.0
		var pitch_t := (lift_pitch if lift else press_pitch) * (0.6 if sides != 0.0 else 1.0)
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


# ---------------------------------------------------------------- builders

func _body(n: String, mass: float, pos: Vector3, layer: int, mask: int) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = n
	b.mass = mass
	b.collision_layer = layer
	b.collision_mask = mask
	b.position = pos
	b.can_sleep = false
	add_child(b)
	return b


func _box(b: RigidBody3D, size: Vector3, pos: Vector3, rot_z := 0.0, color = null) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	cs.rotation.z = rot_z
	b.add_child(cs)
	if color != null:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.7
		mesh.material = mat
		mi.mesh = mesh
		mi.position = pos
		b.add_child(mi)


func _wheel(n: String, pos: Vector3, mat: PhysicsMaterial) -> RigidBody3D:
	var b := _body(n, wheel_mass, pos, LAYER_CART, LAYER_WORLD | LAYER_CARGO)
	b.physics_material_override = mat
	b.angular_damp = 0.05   # rolling resistance
	# A sphere rolls cleanly in Jolt; cylinders on flat ground jitter at speed and drag the axle joints.
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = WHEEL_R
	cs.shape = shape
	b.add_child(cs)
	return b


func _hinge(a: RigidBody3D, b: RigidBody3D, pos: Vector3, basis: Basis) -> HingeJoint3D:
	var j := HingeJoint3D.new()
	j.transform = Transform3D(basis, pos)
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	return j


func _link(node: Node3D, body: RigidBody3D) -> void:
	if node == null:
		push_warning("Cart model is missing a rig node for %s" % body.name)
		return
	_links.append([node, body, body.global_transform.affine_inverse() * node.global_transform])
