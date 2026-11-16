class_name CartCamera
extends Camera3D
## Follow camera that never clips into the level. main.gd works out where the camera wants to be
## (behind the cart, orbited by the mouse, zoomed by the wheel) and calls `follow()`.
##
## Each frame one sphere cast (the `Probe` ShapeCast3D child, sized in the scene) runs from the look
## target to the wanted position. If it is clear, that is the whole cost. If something is in the way
## (a wall, shelf, car, pillar), the camera tries raised positions, `lift_step` apart up to `max_lift`,
## and rises to the lowest one with a clear view. Under a low ceiling where no raised position is clear
## it takes whichever gets furthest from the cart, and then slides in along that line until the
## probe sphere fits. Moving in is instant (so it never clips); rising, settling and moving back out
## are eased.

## Turn off to see the raw orbit camera (clips through walls).
@export var avoid_collisions := true
## Highest the camera rises above where it wants to be, in metres.
@export_range(0.0, 6.0, 0.05) var max_lift := 2.0
## Gap between the raised positions it tries. max_lift / lift_step extra casts at most per frame.
@export_range(0.1, 2.0, 0.05) var lift_step := 0.5
## How fast the camera rises to clear something, per second (higher is snappier).
@export var rise_speed := 8.0
## How fast it settles back down once clear, per second.
@export var settle_speed := 2.5
## How fast it moves back out after being pulled in, per second.
@export var out_speed := 3.0

@onready var probe: ShapeCast3D = $Probe

var _lift := 0.0
var _reach := 1.0
## Microseconds the last follow() call spent on collision checks, and how many casts it ran.
var last_cost_usec := 0
var last_casts := 0


## Places the camera looking at `target`, as close to `wanted` as the level allows.
func follow(target: Vector3, wanted: Vector3, delta: float) -> void:
	if not avoid_collisions:
		_place(wanted, target)
		return
	var t0 := Time.get_ticks_usec()
	last_casts = 0
	# Pick the lowest lift with a clear view; failing that, the one that gets furthest out.
	var goal_lift := 0.0
	var best_reach := -1.0
	var first_fit := 1.0
	var steps := ceili(max_lift / lift_step - 0.001) if max_lift > 0.0 else 0
	for i in steps + 1:
		var lift := minf(i * lift_step, max_lift)
		var line := wanted + Vector3.UP * lift - target
		var fraction := _cast(target, line)
		if i == 0:
			first_fit = fraction
		if fraction >= 1.0:
			goal_lift = lift
			break
		if fraction * line.length() > best_reach + 0.05:
			best_reach = fraction * line.length()
			goal_lift = lift
	# Ease the lift, then slide in along the eased line until the probe fits. When the camera is
	# not lifted at all, the first cast already covers that line.
	var speed := rise_speed if goal_lift > _lift else settle_speed
	_lift = lerpf(_lift, goal_lift, minf(1.0, speed * delta))
	if _lift < 0.005:
		_lift = 0.0
	var offset := wanted + Vector3.UP * _lift - target
	var fit := first_fit if _lift == 0.0 else _cast(target, offset)
	_reach = minf(fit, move_toward(_reach, 1.0, out_speed * delta / maxf(offset.length(), 0.1)))
	last_cost_usec = Time.get_ticks_usec() - t0
	_place(target + offset * _reach, target)


## Jumps straight to the wanted spot, e.g. after the cart respawns.
func reset() -> void:
	_lift = 0.0
	_reach = 1.0


## Sweeps the probe sphere from `from` along `offset`; returns the clear fraction (1 = nothing hit).
func _cast(from: Vector3, offset: Vector3) -> float:
	last_casts += 1
	probe.global_transform = Transform3D(Basis.IDENTITY, from)
	probe.target_position = offset
	probe.force_shapecast_update()
	return probe.get_closest_collision_safe_fraction()


func _place(at: Vector3, target: Vector3) -> void:
	global_position = at
	if not at.is_equal_approx(target):
		look_at(target)
