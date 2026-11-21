@tool
class_name CartFlag
extends Node3D
## The pennant flag on a pole clipped to the back of the basket (scenes/cart/flag.tscn), so players can tell
## whose cart is whose in multiplayer. Only for looks: it is no body and has no collision shape, so the cart's
## mass, centre of mass and tipping are the same with it as without. Every cart carries one, hidden; NetSession
## shows it on each player's cart and sets `color` to the player's slot (host 0, guests 1-7).

## The pennant's colours, one per player slot (wraps around past the end).
@export var colors: Array[Material] = []
@export var color := 0:
	set(v):
		color = v
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var pennant := get_node_or_null("Model/Pennant") as MeshInstance3D
	if pennant and not colors.is_empty():
		pennant.material_override = colors[posmod(color, colors.size())]
