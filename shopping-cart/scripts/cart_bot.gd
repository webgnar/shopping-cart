class_name CartBot
extends Node
## A bot that drives a cart the way a player does: it only presses the same six keys (Q/A left hand push/pull,
## E/D right, W/S lean) through the cart's `controls`, so the cart's hands, power ramp, wheelies, braking and
## getting back up all work exactly as they do for the keyboard. A networked player can later drive a cart the
## same way.
##
## It wanders: picks a random spot on the level's navigation mesh (a NavigationRegion3D in the level scene),
## follows the NavigationAgent3D's path there, stops a moment, and picks another. Lives in scenes/cart/bot_cart.tscn.
##
## Driving, like a player holding keys: each hand has a wanted force (+ push, - pull) made of a forward part
## (speed toward cruise_speed) and a steering part (push the outside hand harder, the inside hand less or pull).
## A hand's key is held while its power (the HUD bar) is below the wanted force and let go once above, so the bar
## hovers around it instead of ramping up forever.

## The cart this bot holds. Default: the parent.
@export var cart: ShoppingCart
## Follows the path. Sits under the cart's Frame at the middle of the basket, so the path is planned for the
## whole cart, not just the handle.
@export var agent: NavigationAgent3D
@export_group("Driving")
@export var cruise_speed := 1.6     ## m/s on a straight (a brisk walk)
@export var corner_speed := 0.6     ## m/s while turning hard
@export var speed_gain := 60.0      ## N per m/s short of the wanted speed, per hand
@export var max_power := 70.0       ## N: a hand never pushes or pulls harder than this (well short of a wheelie)
@export var steer_gain := 45.0      ## N per rad off the path heading
@export var steer_damping := 25.0   ## N per rad/s of turning
@export var spin_angle := 1.4       ## rad: further off than this, it spins (push one hand, pull the other)
@export_group("Wandering")
@export var min_trip := 6.0         ## m of path: the next spot is at least this far away
@export var max_trip := 35.0        ## m of path: and no further than this
@export var pause_min := 0.5        ## s it stands at a spot before picking the next
@export var pause_max := 3.0
@export var stuck_time := 1.5       ## s of trying to move without moving before it backs off
@export var back_off_time := 1.2    ## s it pulls back when stuck
@export var max_back_offs := 3      ## backing off this many times on one trip: it picks another spot
@export var give_up_slack := 10.0   ## s: it gives up on a trip that takes this much longer than at half cruise_speed
@export_group("Racing")
## In a race (scripts/race/race.gd) it drives to the finish faster and never gives up on the trip.
@export var race_speed := 4.5       ## m/s on a straight
@export var race_corner_speed := 1.2   ## m/s while turning hard
@export var race_max_power := 90.0  ## N per hand
## m: at racing speed it counts a path point as passed this far off (instead of the agent's path_desired_distance),
## so it doesn't overshoot one and turn back for it.
@export var race_path_distance := 1.2
@export var race_waypoint_radius := 2.5   ## m: this close (across the floor) to a waypoint of the route, it heads for the next
@export_group("")

enum State { PAUSE, DRIVE, BACK_OFF, GET_UP }
var state := State.PAUSE
## In a race: lined up at the start (holding still), then driving to the finish (race_to).
var racing := false
var _path_distance := -1.0          ## the agent's own path_desired_distance, while racing changes it
var _route: Array[Vector3] = []     ## racing: the waypoints still ahead, the finish last
var _passed := Vector3.INF          ## racing: the last waypoint it got past (where it's put back if wedged)
var _timer := 0.0
var _trip_time := 0.0
var _trip_limit := 0.0
var _backoffs := 0                  ## times it has backed off on this trip
var _stuck := 0.0
var _rng := RandomNumberGenerator.new()
## What it has done so far (for tests and the console): spots reached, trips given up, times it backed off or fell.
var stats := {"trips": 0, "gave_up": 0, "backed_off": 0, "fell": 0, "put_back": 0}


func _ready() -> void:
	if cart == null:
		cart = get_parent() as ShoppingCart
	cart.driver = self
	_rng.randomize()
	_timer = _rng.randf_range(pause_min, pause_max)
	_release()


## Picks a random spot on the navigation mesh it can get to (not the top of a checkout counter or a car roof),
## between min_trip and max_trip of path away, and sets it as the agent's target. Returns false while there is no
## navigation map yet (the first frames after the level loads) or no spot fits.
func pick_target() -> bool:
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var from := NavigationServer3D.map_get_closest_point(map, agent.get_parent().global_position)
	var best := from
	var best_len := 0.0
	for i in 12:
		var p := NavigationServer3D.map_get_random_point(map, agent.navigation_layers, true)
		var path := NavigationServer3D.map_get_path(map, from, p, true, agent.navigation_layers)
		if path.is_empty() or path[path.size() - 1].distance_to(p) > 0.3:
			continue
		var length := 0.0
		for k in range(1, path.size()):
			length += path[k].distance_to(path[k - 1])
		if length > max_trip:
			continue
		if length > best_len:
			best = p
			best_len = length
		if length >= min_trip:
			break
	if best_len < 1.5:
		return false
	agent.target_position = best
	_trip_time = 0.0
	_trip_limit = give_up_slack + best_len / (0.5 * cruise_speed)
	_stuck = 0.0
	_backoffs = 0
	return true


## Race: stand still at the start line until race_to.
func line_up() -> void:
	racing = true
	_route.clear()
	state = State.PAUSE
	_timer = INF
	_release()


## Race: drive through `route` (the race's waypoints, the spot past the finish line last) as fast as it safely can,
## and don't give up on the way. The nav mesh finds the way from one waypoint to the next.
func race_to(route: Array[Vector3]) -> void:
	racing = true
	_route = route.duplicate()
	_passed = cart.cart_origin()
	if _path_distance < 0.0:
		_path_distance = agent.path_desired_distance
	agent.path_desired_distance = race_path_distance
	agent.target_position = _route[0]
	state = State.DRIVE
	_trip_time = 0.0
	_trip_limit = INF
	_stuck = 0.0
	_backoffs = 0


## Racing: on to the next waypoint once near enough this one (the last one, past the finish, it drives right to).
func _next_waypoint() -> void:
	if _route.size() < 2:
		return
	var at: Vector3 = agent.get_parent().global_position
	var d := _route[0] - at
	if Vector2(d.x, d.z).length() < race_waypoint_radius and absf(d.y) < 1.0:
		_passed = _route.pop_front()
		agent.target_position = _route[0]
		_backoffs = 0


## Race over: back to wandering after a short rest.
func stop_racing() -> void:
	racing = false
	_route.clear()
	if _path_distance >= 0.0:
		agent.path_desired_distance = _path_distance
		_path_distance = -1.0
	if state != State.GET_UP:
		state = State.PAUSE
	_timer = _rng.randf_range(pause_min, pause_max)


func _physics_process(delta: float) -> void:
	if cart == null or agent == null or cart.frame == null:
		return
	var c := {}
	if cart.fallen:
		# Lying over: let go once, then hold both hands to haul it back onto its wheels (the cart's own rule).
		if state != State.GET_UP:
			stats.fell += 1
			state = State.GET_UP
			_timer = 0.3
		_timer -= delta
		if _timer <= 0.0:
			c = {"push_left": true, "push_right": true}
		_press(c)
		return
	if state == State.GET_UP:
		state = State.PAUSE
		_timer = INF if racing else 1.0
		if racing and not _route.is_empty() and not agent.is_navigation_finished():
			state = State.DRIVE   # back on its wheels mid-race: carry on
			agent.target_position = agent.target_position
	match state:
		State.PAUSE:
			# Standing still, as a player would: hold the cart against rolling away (down a ramp, or coasting in).
			c = _hands(-speed_gain * _speed(), 0.0)
			_timer -= delta
			if _timer <= 0.0 and pick_target():
				state = State.DRIVE
		State.DRIVE:
			_trip_time += delta
			if racing:
				_next_waypoint()
			if racing and _backoffs >= max_back_offs and not agent.is_navigation_finished():
				# Racing and wedged (against a parked car, or another cart): back to the last waypoint, facing
				# the next, as a racing game puts you back on the track.
				_backoffs = 0
				stats.put_back += 1
				var to := _route[0] - _passed
				cart.place(_passed, atan2(-to.z, to.x) if Vector2(to.x, to.z).length() > 0.1 else cart.heading())
				agent.target_position = _route[0]
			if agent.is_navigation_finished() or _trip_time > _trip_limit or _backoffs >= max_back_offs:
				stats["trips" if agent.is_navigation_finished() else "gave_up"] += 1
				state = State.PAUSE
				_timer = INF if racing else _rng.randf_range(pause_min, pause_max)
			else:
				c = _drive(delta)
		State.BACK_OFF:
			_timer -= delta
			c = _hands(-max_power * 0.6, _steer_err() * -steer_gain * 0.5)
			if _timer <= 0.0:
				state = State.DRIVE
				_stuck = 0.0
				agent.target_position = agent.target_position   # re-plan from where it ended up
	_press(c)


## Heading error (rad, + = the path turns left) from the cart's nose to the next path point.
func _steer_err() -> float:
	var at: Vector3 = agent.get_parent().global_position
	var to := agent.get_next_path_position() - at
	if Vector2(to.x, to.z).length() < 0.01:
		return 0.0
	return wrapf(atan2(-to.z, to.x) - cart.heading(), -PI, PI)


## m/s the cart is rolling along its nose (- = backwards).
func _speed() -> float:
	var nose := cart.frame.global_transform.basis.x
	return cart.frame.linear_velocity.dot(Vector3(nose.x, 0, nose.z).normalized())


func _drive(delta: float) -> Dictionary:
	var frame := cart.frame
	var speed := _speed()
	var yaw_rate := frame.angular_velocity.y
	var err := _steer_err()
	# Slow down for corners and for the end of the trip.
	var left := agent.distance_to_target()
	var top := race_speed if racing else cruise_speed
	var corner := race_corner_speed if racing else corner_speed
	var power := race_max_power if racing else max_power
	var want := lerpf(top, corner, clampf(absf(err) / spin_angle, 0.0, 1.0))
	if not racing:
		want = minf(want, maxf(0.4, left * 0.6))   # racing: straight through the finish, no slowing down
	var forward := 0.0 if absf(err) > spin_angle else clampf(speed_gain * (want - speed), -power, power)
	var steer := steer_gain * err - steer_damping * yaw_rate
	# Not getting anywhere while pushing (or while trying to spin round, say against the end of a wall): pull back
	# a little, then try again.
	if (forward > 0.0 or absf(err) > spin_angle) and absf(speed) < 0.15 and absf(yaw_rate) < 0.3:
		_stuck += delta
		if _stuck > stuck_time:
			state = State.BACK_OFF
			stats.backed_off += 1
			_backoffs += 1
			_timer = back_off_time
	else:
		_stuck = maxf(0.0, _stuck - delta)
	return _hands(forward, steer)


## The keys for a forward force and a steering force (+ = turn left: the right hand pushes harder).
func _hands(forward: float, steer: float) -> Dictionary:
	var c := {}
	var cap := race_max_power if racing else max_power
	var want := {"L": clampf(forward - steer, -cap, cap), "R": clampf(forward + steer, -cap, cap)}
	for side in ["L", "R"]:
		var suffix := "left" if side == "L" else "right"
		var w: float = want[side]
		var p: float = cart.hand_power[side]
		if w > 3.0 and p < w:
			c["push_" + suffix] = true
		elif w < -3.0 and p > w:
			c["pull_" + suffix] = true
	return c


func _release() -> void:
	_press({})


## Hands the keys to the cart, as a player's keyboard would.
func _press(c: Dictionary) -> void:
	cart.controls = c
