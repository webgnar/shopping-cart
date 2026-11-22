class_name CartHUD
extends CanvasLayer
## Driving HUD, styled after US road signs (MUTCD 11th edition, see Reference Images/UI): a guide-sign title, a
## speed plaque and a guide sign of readouts top right, and bottom left the keys (green push, red pull, yellow
## lean; lit while held) between the hands' power meters, over a changeable message sign saying what each hand does.
## Layout and colours live in scenes/ui/hud.tscn; the keycaps light themselves (see key_cap.gd).
## Each hand's meter fills up (green) while it pushes and down (red) while it pulls. Power has no cap: the meters'
## range is their max_value in the scene, and past it the meter stays full while the number keeps climbing.

@onready var _speed: Label = %Speed
@onready var _turn: Label = %Turn
@onready var _wheels: Label = %Wheels
@onready var _groceries: Label = %Groceries
@onready var _hands: Label = %Hands
@onready var _bars := {
	"L": [%LeftPush, %LeftPull, %LeftNewtons],
	"R": [%RightPush, %RightPull, %RightNewtons],
}


func show_cart(cart: ShoppingCart) -> void:
	var v := cart.frame_velocity()
	_speed.text = "%d" % roundi(Vector2(v.x, v.z).length() * 3.6)
	_turn.text = "%d°/s" % roundi(rad_to_deg(cart.frame_spin()))
	_wheels.text = "%d / 4" % cart.wheels_down()
	_groceries.text = "%d / %d" % [cart.groceries_in_basket(), cart.groceries.size()]
	for side in _bars:
		var p: float = cart.hand_power[side]
		var bar: Array = _bars[side]
		(bar[0] as Range).value = maxf(p, 0.0)
		(bar[1] as Range).value = maxf(-p, 0.0)
		(bar[2] as Label).text = "%d N" % roundi(absf(p))
	var hs := cart.hand_state
	_hands.text = "LEFT HAND   %s\nRIGHT HAND  %s" % [hs.L.to_upper() if hs.L else "—", hs.R.to_upper() if hs.R else "—"]
