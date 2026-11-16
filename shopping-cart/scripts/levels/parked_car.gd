@tool
extends StaticBody3D
## A parked car (Blender model parked_car.glb) you can drop into any level. Pick its colour with Paint in the inspector.

const PAINT := preload("res://assets/parking_lot/materials/car_paint.tres")

@export var paint := Color("8a8f98"):
	set(value):
		paint = value
		_apply_paint()


func _ready() -> void:
	_apply_paint()


## Repaints the model's painted parts (Body, Cabin, Mirrors in parked_car.glb) with a copy of the shared paint.
func _apply_paint() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	var m: StandardMaterial3D = PAINT.duplicate()
	m.albedo_color = paint
	for n in ["Body", "Cabin", "Mirrors"]:
		var mi := model.get_node_or_null(n) as MeshInstance3D
		if mi:
			mi.material_override = m
