class_name TrafficRoute
extends Path3D
## A lane of traffic that follows a winding road: the cars are this node's children (traffic_car.tscn instances),
## placed on the curve in the scene. Each keeps its place in the queue and drives along the curve at `speed`,
## facing along it (so cars pitch with the grade), and when it reaches the end it comes back round to the start.
## Put the ends somewhere out of sight (the coast highway's are inside its tunnels). Cars don't stop for anything,
## carts included. TrafficLane is the same thing for a straight lane.

@export var speed := 11.0   ## m/s (11 m/s is about 25 mph)

var clock := 0.0
var length := 0.0
var _cars: Array[Node3D] = []
var _offsets: Array[float] = []


func _ready() -> void:
	length = curve.get_baked_length()
	for c in get_children():
		if c is AnimatableBody3D:
			_cars.append(c)
			_offsets.append(curve.get_closest_offset(c.position))


## Distance along the route of car `i` at route time `t`.
func distance(i: int, t: float) -> float:
	return fposmod(_offsets[i] + speed * t, length)


## Where a car is `d` m along the route, facing along it (in this node's space).
func transform_at(d: float) -> Transform3D:
	var p := curve.sample_baked(d)
	var ahead := curve.sample_baked(minf(d + 2.0, length)) - curve.sample_baked(maxf(d - 2.0, 0.0))
	return Transform3D(Basis.looking_at(ahead.normalized(), Vector3.UP), p)


func _physics_process(delta: float) -> void:
	clock += delta
	for i in _cars.size():
		var d := distance(i, clock)
		var xf := transform_at(d)
		var car := _cars[i]
		if car.position.distance_to(xf.origin) > speed * 0.5 + 5.0:
			# Came back round to the start: jump there instead of sweeping through everything on the way.
			car.sync_to_physics = false
			car.transform = xf
			car.set_deferred("sync_to_physics", true)
		else:
			car.transform = xf
