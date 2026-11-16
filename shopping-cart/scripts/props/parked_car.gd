@tool
extends StaticBody3D
## A parked car to bump into (model: assets/models/garage/parked_car, built by tools/blender/garage_models.py).
## Everything is in scenes/props/garage/parked_car.tscn; this only paints the body, so each
## car in a level can have its own colour: pick Paint Color in the inspector.

@export var paint_color := Color("a8322d"):
	set(value):
		paint_color = value
		if is_node_ready():
			_apply_paint()


func _ready() -> void:
	_apply_paint()


func _apply_paint() -> void:
	var body := get_node_or_null("Model/Body") as MeshInstance3D   # car_paint object of parked_car.glb
	if body == null:
		return
	var mat := body.get_active_material(0).duplicate() as StandardMaterial3D
	mat.albedo_color = paint_color
	body.material_override = mat
