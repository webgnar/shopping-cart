class_name EndlessTiles
extends Node3D
## Makes a grid of tiles endless: the children (instanced block scenes laid out edge to edge, `span` across in
## all) follow the camera. Every physics step, a child that has fallen more than half a span behind the camera
## along X or Z jumps a whole span ahead, so the grid stays centred on the player and never runs out. The
## blocks always land on the same world grid, so anything placed outside this node (loose props, test ramps)
## stays where it is between the same stalls.
##
## The children must tile: unrotated, `span / count` apart, edges that match. Only X and Z wrap. Pick `span`
## so the far edge stays in the fog: the camera always sees at least half a span minus one block ahead.
## The browser game repeats one block the same way (tools/mobile_level_export.gd, mobile/game/level.js).

@export var span := Vector2(390.0, 259.0)   ## m: the whole grid along X and Z (block size times blocks across)


func _physics_process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		recenter(camera.global_position)


## Moves every child that is more than half a span from `focus` (along X or Z) by whole spans toward it.
func recenter(focus: Vector3) -> void:
	for child in get_children():
		var block := child as Node3D
		if block == null:
			continue
		var d := focus - block.global_position
		var shift := Vector3(roundf(d.x / span.x) * span.x, 0.0, roundf(d.z / span.y) * span.y)
		if shift != Vector3.ZERO:
			block.global_position += shift
