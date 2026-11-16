@tool
extends Node3D
## A pallet stacked with loose product cases. One band material for the whole stack, set in the inspector.

@export var label_material: Material:
	set(value):
		label_material = value
		if is_node_ready():
			_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	for c in $Cases.get_children():
		c.label_material = label_material
