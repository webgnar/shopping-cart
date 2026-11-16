@tool
extends StaticBody3D
## A parked car to bump into. Everything is in scenes/props/garage/parked_car.tscn; this only paints it, so each
## car in a level can have its own colour: pick Paint Color in the inspector.

@export var paint_color := Color("a8322d"):
	set(value):
		paint_color = value
		if is_node_ready():
			_apply_paint()


func _ready() -> void:
	_apply_paint()


func _apply_paint() -> void:
	var mat := ($Body as MeshInstance3D).mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	mat.albedo_color = paint_color
	for n in [$Body, $Roof]:
		(n as MeshInstance3D).material_override = mat
