class_name CartHUD
extends CanvasLayer
## Driving HUD: speed and grocery stats, the push-gear meter and the hands' state.
## Layout lives in scenes/ui/hud.tscn; the keycaps light themselves (see key_cap.gd).

@export var segment_off: StyleBox        ## a push-meter segment above the current gear
@export var segment_on: Array[StyleBox]  ## one per gear, for segments at or below the current gear

@onready var _stats: Label = %Stats
@onready var _meter_label: Label = %MeterLabel
@onready var _segments: HBoxContainer = %Segments
@onready var _hands: Label = %Hands


func show_cart(cart: ShoppingCart) -> void:
	var v := cart.frame.linear_velocity
	_stats.text = "Speed  %.1f km/h\nTurn rate  %d°/s\nWheels down  %d / 4\nGroceries  %d / %d" % [
		Vector2(v.x, v.z).length() * 3.6, roundi(rad_to_deg(cart.frame.angular_velocity.y)),
		cart.wheels_down(), cart.groceries_in_basket(), cart.groceries.size()]
	_meter_label.text = "PUSH  gear %d / %d   ·   %d N per hand   ·   up to %.0f km/h" % [
		cart.gear, cart.gears.size(), roundi(cart.push_force), cart.walk_max * 3.6]
	var segs := _segments.get_children()
	for i in segs.size():
		var on: StyleBox = segment_on[mini(i, segment_on.size() - 1)] if segment_on.size() > 0 else null
		segs[i].add_theme_stylebox_override("panel", on if i < cart.gear else segment_off)
	var hs := cart.hand_state
	_hands.text = "Left hand: %s\nRight hand: %s" % [hs.L if hs.L else "—", hs.R if hs.R else "—"]
