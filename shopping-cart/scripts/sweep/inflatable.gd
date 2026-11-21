class_name Inflatable
extends RigidBody3D
## A giant inflatable product hidden in the store (scenes/sweep/inflatable_*.tscn). In a supermarket sweep the first
## cart to bump into it claims its bonus, and it's taken away (moved out of the store) until the next sweep.
## Outside a sweep it's just a big light prop to knock about.

@export var bonus_name := "Giant soda"
@export var bonus := 100.0   ## dollars
## Where a claimed one is put, relative to where it started (out of sight under the floor, frozen).
@export var stash_offset := Vector3(0, -20, 0)

var rest := Transform3D.IDENTITY
var claimed := false


func _ready() -> void:
	rest = global_transform


func cents() -> int:
	return roundi(bonus * 100.0)


func restock() -> void:
	claimed = false
	freeze = true   # still until the sweep starts; then it's knocked about like any prop
	global_transform = rest
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false


func claim() -> void:
	claimed = true
	freeze = true
	global_transform = Transform3D(rest.basis, rest.origin + stash_offset)
