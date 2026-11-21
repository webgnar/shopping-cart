class_name CartNestMouth
extends Area3D
## The open back of a cart's basket (Frame/NestMouth in scenes/cart/cart.tscn): push another cart's nose into it,
## lined up, and the cart tucks in behind this one as carts do in a stack (scripts/cart/cart_nest.gd).
## The area's shape is where a nose is looked for; the checks below say when it is caught.
## Bot carts never nest (they would push a stack around forever), and only the last cart of a stack takes another.

## The joint that holds a caught cart (scenes/cart/nest_joint.tscn).
@export var nest_scene: PackedScene
## m: how far past this cart's handle the other cart's nose has to come before it is caught.
@export var capture_depth := -0.06
## m: how far off this cart's centre line the nose may be.
@export var capture_offset := 0.09
## rad: how far off straight the other cart may point.
@export var capture_angle := 0.2
## rad: how far it may be pitched or rolled against this cart (one on a kerb, one not).
@export var capture_tilt := 0.12
## m/s: it has to be coming in at least this fast.
@export var capture_speed := 0.05
## Where a cart's nose is, in its own space (the front of the basket at mid height).
@export var nose := Vector3(0.965, 0.7, 0.0)

@onready var cart := get_parent().get_parent() as ShoppingCart


func _physics_process(_delta: float) -> void:
	if cart == null or cart.puppet or cart.nested_behind != null or cart.driver is CartBot or nest_scene == null:
		return
	if not has_overlapping_bodies():
		return
	for body in get_overlapping_bodies():
		var other := body.get_parent() as ShoppingCart
		if other == null or other == cart or body != other.frame:
			continue
		if _catches(other):
			_take(other)
			return


func _catches(other: ShoppingCart) -> bool:
	if other.nested_in != null or other.driver is CartBot or other.puppet or other.fallen or cart.fallen:
		return false
	if other.stack().has(cart):
		return false
	var mine := cart.frame.global_transform
	var theirs := other.frame.global_transform
	var tip := mine.affine_inverse() * (theirs * nose)
	if tip.x < capture_depth or tip.x > capture_depth + 0.3 or absf(tip.z) > capture_offset:
		return false
	var rel := mine.basis.orthonormalized().inverse() * theirs.basis.orthonormalized()
	var e := rel.get_euler()
	if absf(e.y) > capture_angle or absf(e.x) > capture_tilt or absf(e.z) > capture_tilt:
		return false
	var closing := (other.frame.linear_velocity - cart.frame.linear_velocity).dot(mine.basis.x.normalized())
	return closing > capture_speed


## Lines the other cart (and any carts nested behind it) up straight behind this one, then joins it on.
func _take(other: ShoppingCart) -> void:
	var nest: CartNest = nest_scene.instantiate()
	var mine := cart.frame.global_transform.orthonormalized()
	var theirs := other.frame.global_transform
	# Turn it about the vertical to this cart's heading, then slide it sideways onto the centre line: a small
	# correction (capture_angle, capture_offset) applied to every body of it at once, so nothing inside it moves.
	var fwd_mine := Vector3(mine.basis.x.x, 0, mine.basis.x.z).normalized()
	var fwd_theirs := Vector3(theirs.basis.x.x, 0, theirs.basis.x.z).normalized()
	var turn := atan2(fwd_theirs.cross(fwd_mine).y, fwd_theirs.dot(fwd_mine))
	var o := theirs.origin
	var shift := Transform3D(Basis(Vector3.UP, turn), o) * Transform3D(Basis(), -o)
	var local := mine.affine_inverse() * (shift * o)
	shift = Transform3D(Basis(), -mine.basis.z * local.z) * shift
	for c in other.stack():
		for b in c.bodies():
			b.global_transform = shift * b.global_transform
			b.linear_velocity = shift.basis * b.linear_velocity
	theirs = other.frame.global_transform
	# Caught partway in: the slide runs from here (0) to fully in (still_to_go) and back out by the same reach as
	# a stack scene's nest.
	var x := (mine.affine_inverse() * theirs.origin).x
	var still_to_go := -nest.spacing - x
	var reach := -float(nest.get("linear_limit_x/lower_distance"))
	nest.set("linear_limit_x/upper_distance", still_to_go)
	nest.set("linear_limit_x/lower_distance", still_to_go - reach)
	nest.transform = other.global_transform.affine_inverse() * Transform3D(mine.basis, theirs * nest.pivot)
	nest.node_a = cart.frame.get_path()
	nest.node_b = other.frame.get_path()
	nest.name = "Nest"
	other.add_child(nest)
