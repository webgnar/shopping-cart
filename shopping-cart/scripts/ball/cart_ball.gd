class_name CartBall
extends Node
## Cart Ball: push the big ball into the other team's goal with your cart. You play for Green and attack the Red
## goal. Each kickoff puts the ball on its spot and your cart on yours, counts 3, 2, 1, GO! with your hands off the
## bar, then the match clock runs. When the whole ball is over a goal line it's a goal: GOAL! for a few seconds,
## then a replay of the last few seconds from the sideline camera (slowed down; press a push key to skip it), then
## the next kickoff. The first team to goals_to_win wins (after that goal's replay); the clock just shows how long the
## match has run, unless match_time sets a time limit.
##
## Red is played by the bot carts in the arena (scenes/ball/ball_bot_cart.tscn, scripts/ball/ball_bot.gd): where
## each one stands in the arena scene is its kickoff spot.
##
## Built as scenes/ball/cart_ball.tscn and placed in an arena level (scenes/levels/cart_ball_arena.tscn), which
## points its exports at the level's Ball, BallSpawn, CartSpawn and the two goals, and connects the goals' Inside
## areas' body_entered here. The console's `ball` loads the arena, and the match starts on load.
##
## Multiplayer: guests' carts are held at kickoff too, but the score and clock run on the host only for now.

signal goal_scored(team: Team)
signal match_over(green: int, red: int)

enum Team { GREEN, RED }
enum Phase { IDLE, KICKOFF, PLAYING, GOAL, REPLAY, FULL_TIME }

@export var goals_to_win := 5             ## first to this many goals wins
@export var match_time := 0.0              ## s time limit (the clock counts down to full time); 0: no limit
@export var countdown := 3                 ## the kickoff count: 3, 2, 1, then GO!
@export var go_hold := 1.0                 ## s GO! stays on screen
@export var goal_pause := 1.5              ## s GOAL! shows before the replay (play goes on meanwhile)
@export var start_on_ready := true         ## start a match as soon as the arena loads
## The ball is put back on its spot (no goal) if it ever gets past these, e.g. squeezed out of the arena.
@export var bounds := AABB(Vector3(-20, -3, -14), Vector3(40, 15, 28))
@export var ball: RigidBody3D
@export var ball_spawn: Marker3D
@export var kickoff_spot: Marker3D         ## where your cart starts each kickoff, facing the Red goal
@export var green_goal: Node3D            ## Green's goal (the bots read where the goals are from here)
@export var red_goal: Node3D
@export var hud: CartBallHUD
@export_group("Replay")
@export var replay_seconds := 4.0          ## s before the goal the replay starts (0: no replays)
@export var replay_speed := 0.6            ## playback speed (1 = real time)
@export var replay_camera: Camera3D        ## the sideline camera the replay is watched from
@export var replay_camera_height := 6.5    ## m up
@export var replay_camera_side := 7.0      ## m out from the middle of the arena, across it (+Z)
@export var replay_camera_follow := 0.8    ## how far along the arena it follows the ball (0 fixed, 1 level with it)
@export_group("")

const TEAM_NAMES := ["Green", "Red"]
const TEAM_COLORS := [Color(0.42, 0.9, 0.5), Color(1.0, 0.42, 0.36)]

var phase := Phase.IDLE
var score := [0, 0]
var clock := 0.0          ## match time left, or (no time limit) match time so far
var _phase_time := 0.0    ## s since the current phase began
var _last_scorer := Team.GREEN
var _bot_spots := {}      ## BallBot -> [kickoff spot, heading]: where it stands in the arena scene
## The replay tape: one {body: Transform3D} per physics tick, oldest first, of the ball and every cart's bodies.
var _tape: Array[Dictionary] = []
var _tape_bodies: Array[RigidBody3D] = []
var _taped_cart: Node = null
var _replay_at := 0.0     ## ticks into the tape
var _was_frozen := {}     ## body -> its freeze before the replay


func bots() -> Array[BallBot]:
	var out: Array[BallBot] = []
	for n in level().find_children("*", "", true, false):
		if n is BallBot:
			out.append(n)
	return out


## The goal `team` defends.
func goal_of(team: Team) -> Node3D:
	return green_goal if team == Team.GREEN else red_goal


func _ready() -> void:
	add_to_group("cart_ball")
	for b in bots():
		_bot_spots[b] = [b.cart.cart_origin(), b.cart.heading()]
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
	for b in _bot_spots:
		if is_instance_valid(b):
			b.cart.place(_bot_spots[b][0], _bot_spots[b][1])
	_lock_carts(true)
	_tape.clear()


func _place_ball() -> void:
	ball.global_transform = ball_spawn.global_transform
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO


func carts() -> Array[ShoppingCart]:
	var out: Array[ShoppingCart] = []
	for c in level().find_children("*", "", true, false):
		if c is ShoppingCart:
			out.append(c)
	return out


func _lock_carts(on: bool) -> void:
	for c in carts():
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
			_record()
			if match_time > 0.0:
				clock = maxf(clock - delta, 0.0)
			else:
				clock += delta
			if not bounds.has_point(ball.global_position):
				_place_ball()
			if match_time > 0.0 and clock <= 0.0:
				_full_time()
		Phase.GOAL:
			_record()
			if _phase_time >= goal_pause:
				_start_replay()
		Phase.REPLAY:
			_replay_at += delta * replay_speed * Engine.physics_ticks_per_second
			if _replay_at >= _tape.size() - 1:
				_end_replay()
			else:
				_show_tape(_replay_at)


# ---------------------------------------------------------------- replay

## Adds this tick's poses of the ball and every cart's bodies to the tape, and drops what's older than the replay.
func _record() -> void:
	if replay_seconds <= 0.0:
		return
	if _taped_cart != level().get("cart") or _tape_bodies.is_empty():
		_taped_cart = level().get("cart")
		_tape_bodies = [ball]
		for c in carts():
			_tape_bodies.append_array(c.net_bodies())
	var poses := {}
	for b in _tape_bodies:
		if is_instance_valid(b):
			poses[b] = b.global_transform
	_tape.append(poses)
	var keep := int((replay_seconds + goal_pause) * Engine.physics_ticks_per_second)
	if _tape.size() > keep:
		_tape = _tape.slice(_tape.size() - keep)


func _start_replay() -> void:
	if replay_seconds <= 0.0 or _tape.size() < 2:
		_next()
		return
	phase = Phase.REPLAY
	_phase_time = 0.0
	_replay_at = 0.0
	# Everything on the tape is held and moved by it: frozen, and the carts' own physics (hands, settling) off.
	_was_frozen.clear()
	for c in carts():
		c.puppet = true
	for b in _tape_bodies:
		if is_instance_valid(b):
			_was_frozen[b] = b.freeze
			b.freeze = true
	_show_tape(0.0)
	replay_camera.current = true


## Puts everything where the tape had it `at` ticks in, between two ticks for the slow motion.
func _show_tape(at: float) -> void:
	var i := clampi(int(at), 0, _tape.size() - 1)
	var a: Dictionary = _tape[i]
	var b: Dictionary = _tape[mini(i + 1, _tape.size() - 1)]
	var t := at - float(i)
	for body in a:
		if is_instance_valid(body):
			body.global_transform = (a[body] as Transform3D).interpolate_with(b.get(body, a[body]), t)


func _end_replay() -> void:
	for body in _was_frozen:
		if is_instance_valid(body):
			body.freeze = _was_frozen[body]
	_was_frozen.clear()
	for c in carts():
		c.puppet = false
	var cam = level().get("camera")
	if cam:
		cam.current = true
	_next()


## After a goal and its replay: the next kickoff, or full time once a team has won.
func _next() -> void:
	if score.max() >= goals_to_win:
		_full_time()
	else:
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
	var status := "Push the ball into the Red goal · first to %d" % goals_to_win
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
		Phase.REPLAY:
			hud.show_banner("", Color.WHITE, 0.0)
			status = "Replay · push to skip"
			_aim_replay_camera()
			if Input.is_action_just_pressed("push_left") or Input.is_action_just_pressed("push_right"):
				_end_replay()
	hud.show_replay(phase == Phase.REPLAY)
	hud.show_score(score[0], score[1], clock, status)


## The replay camera: up over the +Z side of the pitch, sliding along with the ball, looking at it.
func _aim_replay_camera() -> void:
	var b := ball.global_position
	var at := Vector3(b.x * replay_camera_follow, replay_camera_height, replay_camera_side)
	if at.distance_to(b) > 0.5:
		replay_camera.look_at_from_position(at, b)
