@tool
extends RigidBody3D
## A loose case of groceries the cart can knock over. Pick the printed band's material in the inspector
## (assets/materials/supermarket/case_label_*.tres); empty keeps the model's own.

@export var label_material: Material:
	set(value):
		label_material = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	$Model/product_case/case_label.material_override = label_material
