class_name KeyCap
extends PanelContainer
## An on-screen keycap that lights up while its input action is held.

@export var action: StringName
@export var idle_style: StyleBox
@export var pressed_style: StyleBox
@export var idle_text_color := Color("eceef2")
@export var pressed_text_color := Color("12151b")

var _on := false


func _ready() -> void:
	_show(false)


func _process(_delta: float) -> void:
	var on := InputMap.has_action(action) and Input.is_action_pressed(action)
	if on != _on:
		_show(on)


func _show(on: bool) -> void:
	_on = on
	add_theme_stylebox_override("panel", pressed_style if on else idle_style)
	for l in find_children("*", "Label", true, false):
		l.add_theme_color_override("font_color", pressed_text_color if on else idle_text_color)
