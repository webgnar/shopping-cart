class_name CartHUD
extends CanvasLayer
## Driving HUD: speed and grocery stats, a power bar per hand and the hands' state.
## Layout lives in scenes/ui/hud.tscn; the keycaps light themselves (see key_cap.gd).
## Each hand's bar fills up (green) while it pushes and down (red) while it pulls. Power has no cap: the bars'
## range is their max_value in the scene, and past it the bar stays full while the number keeps climbing.

@onready var _stats: Label = %Stats
@onready var _hands: Label = %Hands
@onready var _bars := {
	"L": [%LeftPush, %LeftPull, %LeftNewtons],
	"R": [%RightPush, %RightPull, %RightNewtons],
}


func show_cart(cart: ShoppingCart) -> void:
	var v := cart.frame_velocity()
	_stats.text = "Speed  %.1f km/h\nTurn rate  %d°/s\nWheels down  %d / 4\nGroceries  %d / %d" % [
		Vector2(v.x, v.z).length() * 3.6, roundi(rad_to_deg(cart.frame_spin())),
		cart.wheels_down(), cart.groceries_in_basket(), cart.groceries.size()]
	for side in _bars:
		var p: float = cart.hand_power[side]
		var bar: Array = _bars[side]
		(bar[0] as Range).value = maxf(p, 0.0)
		(bar[1] as Range).value = maxf(-p, 0.0)
		(bar[2] as Label).text = "%d N" % roundi(absf(p))
	var hs := cart.hand_state
	_hands.text = "Left hand: %s\nRight hand: %s" % [hs.L if hs.L else "—", hs.R if hs.R else "—"]
