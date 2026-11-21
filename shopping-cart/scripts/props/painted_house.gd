@tool
extends StaticBody3D
## A San Francisco row house (house_victorian.glb or house_stucco.glb, built by tools/sf_hill_models.py) that
## can be painted per house: pick its Walls, Trim and Accent (doors, garage) from the shared paints in
## assets/sf_hill/materials/ in the inspector. Shared materials keep every house that wears the same paint on
## one material, so the browser version can merge them.

@export var walls: Material:
	set(value):
		walls = value
		_apply()
@export var trim: Material:
	set(value):
		trim = value
		_apply()
@export var accent: Material:
	set(value):
		accent = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	for part in [["Walls", walls], ["Trim", trim], ["Accent", accent]]:
		var mi := model.get_node_or_null(part[0]) as MeshInstance3D
		if mi:
			mi.material_override = part[1]
