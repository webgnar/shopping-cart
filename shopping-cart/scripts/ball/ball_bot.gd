class_name BallBot
extends Node
## A Cart Ball bot: drives its cart only through the same six keys a player has (the cart's `controls`, like
## scripts/cart_bot.gd), so it pushes, steers, tips and gets back up exactly as you do. Lives in
## scenes/ball/ball_bot_cart.tscn; where the cart stands in the arena scene is its kickoff spot.
##
## A STRIKER gets round behind the ball (on the far side from the goal it attacks), then drives through it at
## the goal. A KEEPER waits a few metres out from its own goal, level with the ball, and only goes for the ball
## (to clear it upfield, the striker's way) when it comes within keeper_reach of its goal.
##
## Driving: each hand gets a wanted force made of a forward part (speed toward the wanted speed) and a steering
## part (the outside hand pushes harder); a key is held while that hand's power is short of it. Pushing without
## getting anywhere for stuck_time, it pulls back for back_off_time and tries again.

enum Role { STRIKER, KEEPER }

@export var cart: ShoppingCart             ## default: the parent
@export var team := CartBall.Team.RED
@export var role := Role.STRIKER
@export_group("Driving")
@export var top_speed := 2.8               ## m/s with a clear run
@export var line_up_speed := 1.8           ## m/s while getting round behind the ball
@export var speed_gain := 60.0             ## N per m/s short of the wanted speed, per hand
@export var max_power := 85.0              ## N a hand pushes or pulls at most
@export var steer_gain := 45.0             ## N per rad off the heading it wants
@export var steer_damping := 25.0          ## N per rad/s of turning
@export var spin_angle := 1.4              ## rad: further off than this it turns on the spot first
@export var stuck_time := 1.2              ## s pushing without moving before it backs off
@export var back_off_time := 1.0           ## s it pulls back for
@export_group("Play")
@export var line_up_distance := 1.9        ## m behind the ball's centre it lines up, on the far side from the goal
@export var shoot_lane := 0.8              ## m: this close to the line from the ball to the goal, it goes for it
@export var keeper_depth := 3.0            ## m out from its goal line the keeper waits
@export var keeper_reach := 10.0           ## m: the ball this close to its goal, the keeper goes for it
@export_group("")

var _stuck := 0.0
var _backing := 0.0
var _get_up := -1.0


func _ready() -> void:
	if cart == null:
		cart = get_parent() as ShoppingCart
	cart.driver = self


func game() -> CartBall:
	return get_tree().get_first_node_in_group("cart_ball") as CartBall


func _physics_process(delta: float) -> void:
	var g := game()
	if cart == null or cart.frame == null or g == null or g.phase != CartBall.Phase.PLAYING:
		_press({})
		return
	if cart.fallen:
		# Lying over: let go once, then hold both pushes to haul it back up (the cart's own rule).
		if _get_up < 0.0:
			_get_up = 0.3
		_get_up -= delta
		_press({"push_left": true, "push_right": true} if _get_up <= 0.0 else {})
		return
	_get_up = -1.0
	if _backing > 0.0:
		_backing -= delta
		_press(_hands(-max_power * 0.6, 0.0))
		return
	var target: Array = _keeper_target(g) if role == Role.KEEPER else []
	if target.is_empty():
		target = _striker_target(g)
	_press(_drive_to(target[0], target[1], delta))


## [point, speed] that gets the ball to the goal it attacks: round behind it first, then through it.
func _striker_target(g: CartBall) -> Array:
	var b := _flat(g.ball.global_position)
	var to_goal := (_flat(g.goal_of(_other(team)).global_position) - b).normalized()
	var p := _flat(_centre())
	var behind := b - to_goal * line_up_distance
	var along := (b - p).dot(to_goal)                     # + : the cart is on the right side of the ball
	var off_line := absf((p - b).cross(to_goal).y)
	if along > 0.4 and off_line < shoot_lane + along * 0.3:
		return [b + to_goal * 3.0, top_speed]          # lined up: through the ball at the goal
	if along < 0.6 and p.distance_to(b) < line_up_distance + 0.8:
		# Wrong side of the ball and close to it: go round it, not through it.
		var side := signf((p - b).cross(to_goal).y)
		if side == 0.0:
			side = 1.0
		var round_point := b + Vector3(-to_goal.z, 0, to_goal.x) * side * 2.2 - to_goal * 0.8
		return [round_point, line_up_speed]
	return [behind, line_up_speed if p.distance_to(behind) < 4.0 else top_speed]


## [point, speed] for the keeper's waiting spot, or [] when the ball is near enough its goal to go for it.
func _keeper_target(g: CartBall) -> Array:
	var goal := g.goal_of(team)
	var mouth := _flat(goal.global_position)
	var b := _flat(g.ball.global_position)
	if b.distance_to(mouth) < keeper_reach:
		return []
	var out := -_flat(goal.global_basis.x).normalized()   # the goal's net is along its +X
	var across := Vector3(-out.z, 0, out.x)
	var shift := clampf((b - mouth).dot(across), -1.8, 1.8)
	var spot := mouth + out * keeper_depth + across * shift
	return [spot, minf(line_up_speed, maxf(0.0, _flat(_centre()).distance_to(spot) - 0.4))]


func _drive_to(point: Vector3, want: float, delta: float) -> Dictionary:
	var p := _centre()
	var to := point - p
	var speed := _speed()
	var yaw_rate := cart.frame.angular_velocity.y
	if Vector2(to.x, to.z).length() < 0.5 or want <= 0.0:
		return _hands(-speed_gain * speed, -steer_damping * yaw_rate)   # there: hold still
	var err := wrapf(atan2(-to.z, to.x) - cart.heading(), -PI, PI)
	want = lerpf(want, 0.6, clampf(absf(err) / spin_angle, 0.0, 1.0))
	var forward := 0.0 if absf(err) > spin_angle else clampf(speed_gain * (want - speed), -max_power, max_power)
	var steer := steer_gain * err - steer_damping * yaw_rate
	if (forward > 0.0 or absf(err) > spin_angle) and absf(speed) < 0.15 and absf(yaw_rate) < 0.3:
		_stuck += delta
		if _stuck > stuck_time:
			_stuck = 0.0
			_backing = back_off_time
	else:
		_stuck = maxf(0.0, _stuck - delta)
	return _hands(forward, steer)


## The keys for a forward force and a steering force (+ = turn left: the right hand pushes harder).
func _hands(forward: float, steer: float) -> Dictionary:
	var c := {}
	var want := {"L": clampf(forward - steer, -max_power, max_power), "R": clampf(forward + steer, -max_power, max_power)}
	for side in ["L", "R"]:
		var suffix := "left" if side == "L" else "right"
		var w: float = want[side]
		var power: float = cart.hand_power[side]
		if w > 3.0 and power < w:
			c["push_" + suffix] = true
		elif w < -3.0 and power > w:
			c["pull_" + suffix] = true
	return c


func _press(c: Dictionary) -> void:
	cart.controls = c


## The middle of the cart (its frame's centre of mass).
func _centre() -> Vector3:
	return cart.frame.global_transform * cart.frame.center_of_mass


## m/s the cart is rolling along its nose (- = backwards).
func _speed() -> float:
	var nose := cart.frame.global_transform.basis.x
	return cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


static func _other(t: CartBall.Team) -> CartBall.Team:
	return CartBall.Team.GREEN if t == CartBall.Team.RED else CartBall.Team.RED
