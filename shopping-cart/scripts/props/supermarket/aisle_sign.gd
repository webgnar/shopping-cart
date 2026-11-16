@tool
extends Node3D
## Hanging aisle sign: big aisle number on the yellow header, what's in the aisle underneath.
## Both faces show the same text. Set them in the inspector.

@export var number := 1:
	set(value):
		number = value
		if is_node_ready():
			_apply_text()
@export var items := PackedStringArray(["Cereal", "Coffee", "Snacks"]):
	set(value):
		items = value
		if is_node_ready():
			_apply_text()


func _ready() -> void:
	_apply_text()


func _apply_text() -> void:
	for side in ["Front", "Back"]:
		get_node("%s/Number" % side).text = str(number)
		get_node("%s/Items" % side).text = "\n".join(items)
