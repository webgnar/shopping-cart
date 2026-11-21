class_name CartNest
extends Generic6DOFJoint3D
## Holds one cart tucked into the back of the cart ahead, as carts nest in a stack (scenes/cart/nest_joint.tscn).
## node_a is the Frame of the cart ahead, node_b the Frame of the cart behind; the joint sits at the pivot of the
## cart behind (`pivot`, inside the basket ahead), lined up with the cart ahead (its X along the nose).
##
## The settings on the joint are the nest:
##  - linear X: the slide. The cart behind slides along the one ahead between fully in (upper limit) and just
##    out (lower limit). linear_motor_x with no target speed is the grip of the wire baskets on each other: it takes
##    that much force to slide a cart in or out.
##  - linear Y and Z: locked. The nose rides in the basket ahead.
##  - angular: the play of a nose in a basket, a little yaw (with a soft spring back to straight), less pitch and
##    roll. A stack wanders and fishtails within it.
## In a stack scene the carts stand fully nested and the limits run from -slide to 0. A cart pushed in from behind
## (scripts/cart/cart_nest_mouth.gd) is caught partway in, so its limits are shifted by how far it still has to go.
##
## While nested: the two carts pass through each other (ShoppingCart.ghost), the gate of the cart ahead is swung
## up into its basket by its hinge motor, and the stack wakes and settles as one (scripts/cart.gd).
## It comes apart when the cart behind slides all the way out (pulled off), or when the carts behind take a hard
## sideways knock (break_impulse): a side hit or a violent fishtail pops the nose out of the basket.

## m: how far behind the cart ahead this cart stands when fully in (handle to handle).
@export var spacing := 0.28
## Where the joint sits on the cart behind, in its own space (the pivot of the nest, inside the basket ahead).
@export var pivot := Vector3(0.45, 0.5, 0.0)
## rad/s the hinge motor swings the gate of the cart ahead up at, and the most it pushes with.
@export var gate_speed := 2.0
@export var gate_impulse := 0.1
## N*s: a sideways knock this big passed through the nest (the carts on either side of it both change their sideways
## momentum by at least this much within impulse_window) pops it apart.
@export var break_impulse := 70.0
@export var impulse_window := 0.06   ## s
## m: this close to the lower (out) limit counts as pulled out.
@export var release_margin := 0.01

var ahead: ShoppingCart
var behind: ShoppingCart
var _frame_a: Transform3D    ## the joint in the space of the frame ahead
var _frame_b: Transform3D    ## the joint in the space of the frame behind
var _momentum: Array[Vector2] = []   ## sideways momentum of the carts ahead (x) and behind (y), last few steps
var _hits: Array[Vector2] = []       ## whether anything solid touched the frames ahead (x) or behind (y), same steps
var _apart := false


func _ready() -> void:
	var fa := get_node_or_null(node_a) as RigidBody3D
	var fb := get_node_or_null(node_b) as RigidBody3D
	if fa == null or fb == null:
		push_warning("CartNest %s: node_a and node_b must be two carts frames (%s, %s)" % [name, node_a, node_b])
		return
	ahead = fa.get_parent() as ShoppingCart
	behind = fb.get_parent() as ShoppingCart
	_frame_a = fa.global_transform.affine_inverse() * global_transform
	_frame_b = fb.global_transform.affine_inverse() * global_transform
	ahead.nested_behind = behind
	behind.nested_in = ahead
	behind.nest = self
	# The cart behind and everything ahead of it in the stack (and the carts already behind it) pass through
	# each other: the noses sit inside the baskets ahead.
	var carts := behind.stack()
	for a in carts:
		for b in carts:
			a.ghost(b)
	_set_gate(true)
	_wake_all.call_deferred()


func _wake_all() -> void:
	if is_instance_valid(behind) and not behind.puppet:
		behind._wake()


## Swings the gate of the cart ahead up (its hinge motor) or lets it hang again.
func _set_gate(up: bool) -> void:
	var hinge := ahead.get_node_or_null("GateHinge") as HingeJoint3D
	if hinge == null:
		return
	hinge.set("motor/enable", up)
	hinge.set("motor/target_velocity", -gate_speed)
	hinge.set("motor/max_impulse", gate_impulse)


## m the cart behind has slid along the cart ahead since the joint was made (+ = further in).
func slide() -> float:
	var ja := ahead.frame.global_transform * _frame_a
	var jb := behind.frame.global_transform * _frame_b
	return (ja.affine_inverse() * jb.origin).x


func _physics_process(_delta: float) -> void:
	if _apart or ahead == null or behind == null or behind.puppet or ahead.puppet:
		return
	# Pulled off: slid all the way to the out limit.
	if slide() <= get("linear_limit_x/lower_distance") + release_margin:
		come_apart()
		return
	# A hard sideways knock on the carts behind (a side hit, a violent fishtail) pops the nose out of the basket.
	# What the joint passes on. A knock on one side of the nest (something solid hitting the frames there) changes
	# the sideways momentum of the carts on the other side only through this joint, so that side's change is the
	# joint's load. With nothing hitting either side, or both, the smaller of the two changes.
	var side := ahead.frame.global_transform.basis.z.normalized()
	var p := Vector2.ZERO   # sideways momentum: x the carts ahead of the nest, y the carts behind it
	var hit := Vector2.ZERO
	for c in behind.stack():
		var back := c == behind or _is_behind(c)
		var m := c.frame.linear_velocity.dot(side) * c.rig_mass()
		var touched := 1.0 if c.frame.get_colliding_bodies().any(func(b): return not (b is RigidBody3D and c.groceries.has(b))) else 0.0
		if back:
			p.y += m
			hit.y = maxf(hit.y, touched)
		else:
			p.x += m
			hit.x = maxf(hit.x, touched)
	_momentum.append(p)
	_hits.append(hit)
	var steps := maxi(2, roundi(impulse_window * Engine.physics_ticks_per_second))
	while _momentum.size() > steps:
		_momentum.pop_front()
		_hits.pop_front()
	var d: Vector2 = (_momentum.back() - _momentum.front()).abs()
	var h := Vector2.ZERO
	for x in _hits:
		h = h.max(x)
	var load := minf(d.x, d.y)
	if h.x > 0.0 and h.y == 0.0:
		load = d.y
	elif h.y > 0.0 and h.x == 0.0:
		load = d.x
	if load > break_impulse:
		come_apart()


func _is_behind(c: ShoppingCart) -> bool:
	var b := behind.nested_behind
	while b != null:
		if b == c:
			return true
		b = b.nested_behind
	return false


## The cart behind lets go of the cart ahead. The two keep passing through each other until they are clear
## (ShoppingCart._drop_clear_ghosts), so nothing is pushed out of anything.
func come_apart() -> void:
	if _apart:
		return
	_apart = true
	if is_instance_valid(ahead):
		ahead.nested_behind = null
		_set_gate(false)
	if is_instance_valid(behind):
		behind.nested_in = null
		if behind.nest == self:
			behind.nest = null
	node_a = NodePath()
	node_b = NodePath()
	queue_free()
