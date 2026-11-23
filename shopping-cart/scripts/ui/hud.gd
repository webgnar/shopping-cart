class_name CartHUD
extends CanvasLayer
## Driving HUD, styled after US road signs (MUTCD 11th edition, see Reference Images/UI): a guide-sign title, a
## speed plaque and a guide sign of readouts top right, and bottom left the keys (green push, red pull, yellow
## lean; lit while held) between the hands' power meters, the handlebar seen from above with a marker where each
## hand holds it (tapping moves a hand out to the end), and a changeable message sign saying what each hand does.
## Layout and colours live in scenes/ui/hud.tscn; the keycaps light themselves (see key_cap.gd).
## Each hand's meter fills up (green) while it pushes and down (red) while it pulls. Power has no cap: the meters'
## range is their max_value in the scene, and past it the meter stays full while the number keeps climbing.

@onready var _speed: Label = %Speed
@onready var _turn: Label = %Turn
@onready var _wheels: Label = %Wheels
@onready var _groceries: Label = %Groceries
@onready var _hands: Label = %Hands
@onready var _track: Control = %Track
@onready var _force_sign: Control = %ForceSign
@onready var _force_view: ForceDiagram = %ForceView
@onready var _markers := {"L": %LeftHand, "R": %RightHand}

const BAR_HALF := 0.26   ## m: half the handlebar's width, the track's half length
@onready var _bars := {
	"L": [%LeftPush, %LeftPull, %LeftNewtons],
	"R": [%RightPush, %RightPull, %RightNewtons],
}


## F cycles the handle-forces sign: both views, side, top, hidden.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("forces"):
		if not _force_sign.visible:
			_force_sign.visible = true
			_force_view.view = ForceDiagram.View.BOTH
		elif _force_view.view == ForceDiagram.View.BOTH:
			_force_view.view = ForceDiagram.View.SIDE
		elif _force_view.view == ForceDiagram.View.SIDE:
			_force_view.view = ForceDiagram.View.TOP
		else:
			_force_sign.visible = false
		get_viewport().set_input_as_handled()


func show_cart(cart: ShoppingCart) -> void:
	if _force_sign.visible:
		_force_view.show_cart(cart)
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
	# Hand markers: where each hand holds the bar (left of the middle for the left hand), green pushing, red
	# pulling, white resting; a tired arm fades.
	var mid := _track.size.x / 2.0
	for side in _markers:
		var m: ColorRect = _markers[side]
		var s := -1.0 if side == "L" else 1.0
		m.position.x = mid + s * cart.hand_reach(side) / BAR_HALF * (mid - m.size.x / 2.0) - m.size.x / 2.0
		var p: float = cart.hand_power[side]
		var col := Color(0.0, 0.75, 0.5) if p > 1.0 else (Color(0.95, 0.3, 0.15) if p < -1.0 else Color(1, 1, 1))
		col.a = 1.0 - 0.6 * cart.hand_fatigue[side]
		m.color = col
	var hs := cart.hand_state
	_hands.text = "L  %s\nR  %s" % [hs.L.to_upper() if hs.L else "—", hs.R.to_upper() if hs.R else "—"]
