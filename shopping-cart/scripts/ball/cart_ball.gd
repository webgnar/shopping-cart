class_name CartBall
extends Node
## Cart Ball: push the big ball into the other team's goal with your cart. You play for Green and attack the Red
## goal. Each kickoff puts the ball on its spot and your cart on yours, counts 3, 2, 1, GO! with your hands off the
## bar, then the match clock runs. When the whole ball is over a goal line it's a goal: GOAL! for a few seconds,
## then the next kickoff. At full time the score stands (a draw is a draw).
##
## Built as scenes/ball/cart_ball.tscn and placed in an arena level (scenes/levels/cart_ball_arena.tscn), which
## points its exports at the level's Ball, BallSpawn, CartSpawn and the two goals' Inside areas, and connects
## those areas' body_entered here. The console's `ball` loads the arena, and the match starts on load.
##
## Multiplayer: guests' carts are held at kickoff too, but the score and clock run on the host only for now.

signal goal_scored(team: Team)
signal match_over(green: int, red: int)

enum Team { GREEN, RED }
enum Phase { IDLE, KICKOFF, PLAYING, GOAL, FULL_TIME }

@export var match_time := 180.0            ## s on the match clock
@export var countdown := 3                 ## the kickoff count: 3, 2, 1, then GO!
@export var go_hold := 1.0                 ## s GO! stays on screen
@export var goal_pause := 3.0              ## s GOAL! shows before the next kickoff
@export var start_on_ready := true         ## start a match as soon as the arena loads
## The ball is put back on its spot (no goal) if it ever gets past these, e.g. squeezed out of the arena.
@export var bounds := AABB(Vector3(-20, -3, -14), Vector3(40, 15, 28))
@export var ball: RigidBody3D
@export var ball_spawn: Marker3D
@export var kickoff_spot: Marker3D         ## where your cart starts each kickoff, facing the Red goal
@export var hud: CartBallHUD

const TEAM_NAMES := ["Green", "Red"]
const TEAM_COLORS := [Color(0.42, 0.9, 0.5), Color(1.0, 0.42, 0.36)]

var phase := Phase.IDLE
var score := [0, 0]
var clock := 0.0          ## match time left
var _phase_time := 0.0    ## s since the current phase began
var _last_scorer := Team.GREEN


func _ready() -> void:
	add_to_group("cart_ball")
	if start_on_ready:
		start.call_deferred()   # after the level's own _ready has spawned the cart


func level() -> Node:
	return get_parent()


func _is_guest() -> bool:
	var net := get_node_or_null("/root/Net") as NetSession
	return net != null and net.is_guest()


## A fresh match: 0-0, full clock, kickoff. Returns false on a multiplayer guest (the host runs the match).
func start() -> bool:
	if _is_guest():
		return false
	score = [0, 0]
	clock = match_time
	hud.hide_full_time()
	_kickoff()
	return true


func _kickoff() -> void:
	phase = Phase.KICKOFF
	_phase_time = 0.0
	_place_ball()
	ball.freeze = true
	level().spawn_cart(kickoff_spot.global_position, kickoff_spot.global_rotation.y)
	_lock_carts(true)


func _place_ball() -> void:
	ball.global_transform = ball_spawn.global_transform
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO


func _lock_carts(on: bool) -> void:
	for c in level().find_children("*", "", true, false):
		if c is ShoppingCart:
			c.locked = on


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE or _is_guest():
		return
	_phase_time += delta
	match phase:
		Phase.KICKOFF:
			_lock_carts(true)   # every tick: a cart reset during the count is a new cart
			if _phase_time >= float(countdown):
				phase = Phase.PLAYING
				_phase_time = 0.0
				ball.freeze = false
				_place_ball()
				_lock_carts(false)
		Phase.PLAYING:
			clock = maxf(clock - delta, 0.0)
			if not bounds.has_point(ball.global_position):
				_place_ball()
			if clock <= 0.0:
				_full_time()
		Phase.GOAL:
			if _phase_time >= goal_pause:
				_kickoff()


func _full_time() -> void:
	phase = Phase.FULL_TIME
	_phase_time = 0.0
	var line := "It's a draw"
	if score[0] != score[1]:
		line = "%s wins!" % TEAM_NAMES[Team.GREEN if score[0] > score[1] else Team.RED]
	hud.show_full_time(score[0], score[1], line)
	match_over.emit(score[0], score[1])
	_log("Full time: Green %d - %d Red. %s" % [score[0], score[1], line])


## Connected in the arena to the Red goal's Inside area: the whole ball is over Red's line, Green scores.
func _on_red_goal_body_entered(body: Node3D) -> void:
	if body == ball:
		_goal(Team.GREEN)


## Connected in the arena to the Green goal's Inside area: Red scores.
func _on_green_goal_body_entered(body: Node3D) -> void:
	if body == ball:
		_goal(Team.RED)


func _goal(team: Team) -> void:
	if phase != Phase.PLAYING or _is_guest():
		return
	score[team] += 1
	_last_scorer = team
	phase = Phase.GOAL
	_phase_time = 0.0
	goal_scored.emit(team)
	_log("GOAL for %s! Green %d - %d Red" % [TEAM_NAMES[team], score[0], score[1]])


func _log(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print(text)


# ---------------------------------------------------------------- screen

func _process(_delta: float) -> void:
	hud.visible = phase != Phase.IDLE and not _is_guest()
	if not hud.visible:
		return
	var status := "Push the ball into the Red goal"
	match phase:
		Phase.KICKOFF:
			var n := ceili(float(countdown) - _phase_time)
			hud.show_banner(str(n), Color.WHITE, _phase_time - floorf(_phase_time))
			status = "Kickoff"
		Phase.PLAYING:
			hud.show_banner("GO!" if _phase_time < go_hold else "", Color.WHITE, _phase_time / go_hold)
		Phase.GOAL:
			hud.show_banner("GOAL!", TEAM_COLORS[_last_scorer], _phase_time)
			status = "%s scores!" % TEAM_NAMES[_last_scorer]
		Phase.FULL_TIME:
			hud.show_banner("", Color.WHITE, 0.0)
			status = "Full time"
	hud.show_score(score[0], score[1], clock, status)
