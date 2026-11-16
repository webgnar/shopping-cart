extends "res://scripts/main.gd"
## Parking garage level: start on the roof and roll the cart down ten gently sloped floors. Floors 10 to 6
## turn right at each flat landing; at the halfway landing the garage carries on into a second wing where
## floors 5 to 1 turn left, and you leave at street level.
##
## Everything (decks, walls, parked cars, lights, sky) is built as nodes in scenes/levels/parking_garage.tscn.
## This script only skips main.gd's sandbox and starts the cart at the CartSpawn marker.


func _build_environment() -> void:
	pass   # WorldEnvironment and Sun are nodes in the scene


func _build_level() -> void:
	pass   # the garage is nodes in the scene


func _ready() -> void:
	super()
	var spawn: Marker3D = $CartSpawn
	spawn_cart(spawn.global_position, spawn.global_rotation.y)
