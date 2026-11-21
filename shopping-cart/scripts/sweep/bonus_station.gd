class_name BonusStation
extends Area3D
## A spot in the store worth a bonus in a supermarket sweep (scenes/sweep/bonus_station.tscn): stop your cart in its
## taped box and hold still for hold_time seconds, and the bonus is yours. Each cart gets it once per sweep.

@export var title := "DELI COUNTER"
@export var bonus := 50.0        ## dollars
@export var hold_time := 3.0     ## s the cart must stand in the box
@export var still_speed := 0.25  ## m/s: slower than this counts as holding still
@export var sign_label: Label3D
@export var floor_label: Label3D  ## painted in the box: "+$50"


func cents() -> int:
	return roundi(bonus * 100.0)


func _ready() -> void:
	sign_label.text = "%s\nStop here %d s: +$%d" % [title, roundi(hold_time), roundi(bonus)]
	floor_label.text = "+$%d" % roundi(bonus)
