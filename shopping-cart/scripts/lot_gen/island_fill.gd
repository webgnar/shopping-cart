@tool
class_name IslandFill
extends StaticBody3D
## The planted middle of a curbed parking island (scenes/lot_gen/island_fill.tscn): a mulch box from the ground up
## to just under the curb top, with matching collision. Its origin is at ground level in the middle.

@export var mesh_instance: MeshInstance3D   ## a BoxMesh (local to scene)
@export var collision: CollisionShape3D     ## a BoxShape3D (local to scene)
@export var size := Vector3(2.0, 0.13, 5.0):
	set(v):
		size = v
		if is_node_ready():
			_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	(mesh_instance.mesh as BoxMesh).size = size
	(collision.shape as BoxShape3D).size = size
	mesh_instance.position.y = size.y * 0.5
	collision.position.y = size.y * 0.5
