class_name TrafficLane
extends Node3D
## A lane of cross traffic. The cars are this node's children (traffic_car.tscn instances), placed along the
## lane's -Z axis in the scene: each keeps its place in the queue and drives along -Z at `speed`, and when it
## passes `length` it comes round to the start again. Cars don't stop for anything, carts included.

@export var speed := 10.0       ## m/s (10 m/s is 22 mph)
@export var length := 200.0     ## m along -Z before a car comes back round to the start

var clock := 0.0
var _cars: Array[Node3D] = []
var _offsets: Array[float] = []


func _ready() -> void:
	for c in get_children():
		if c is AnimatableBody3D:
			_cars.append(c)
			_offsets.append(-c.position.z)


## Distance along the lane of car `i` at lane time `t`.
func distance(i: int, t: float) -> float:
	return fposmod(_offsets[i] + speed * t, length)


func _physics_process(delta: float) -> void:
	clock += delta
	for i in _cars.size():
		var d := distance(i, clock)
		var p := Vector3(0, 0, -d)
		if absf(_cars[i].position.z + d) > length * 0.5:
			# Coming back round to the start: jump there instead of sweeping through everything on the way.
			_cars[i].sync_to_physics = false
			_cars[i].position = p
			_cars[i].set_deferred("sync_to_physics", true)
		else:
			_cars[i].position = p
