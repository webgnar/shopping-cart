extends "res://scripts/main.gd"
## Parking lot level. Everything you see is built as nodes in scenes/levels/parking_lot.tscn (open it in the
## editor to move things around); this script only plugs that scene into the cart sandbox in main.gd:
## it skips main.gd's procedural sandbox, uses the scene's own lighting if it has a WorldEnvironment,
## keeps asphalt friction in sync with tuning/cart_tuning.json, and puts the cart on the CartSpawn marker.

const ASPHALT_PHYSICS := "res://assets/parking_lot/physics/asphalt.tres"


func _ready() -> void:
	super()
	var asphalt: PhysicsMaterial = load(ASPHALT_PHYSICS)
	asphalt.friction = asphalt_mat.friction   # tuning/cart_tuning.json
	var spawn := get_node_or_null("CartSpawn") as Marker3D
	if spawn:
		spawn_cart(spawn.global_position, spawn.global_rotation.y)


func _build_environment() -> void:
	if not has_node("WorldEnvironment"):
		super()


func _build_level() -> void:
	pass   # the level lives in the scene
