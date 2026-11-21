class_name Race
extends Node3D
## A race down a level: everyone lines up on the Grid, the screen counts 3, 2, 1, GO! with every cart's hands off
## the bar, then the clock runs until each racer's cart crosses the Finish line (an Area3D). The results table
## comes up once everyone is over the line, or finish_grace seconds after the winner (the rest didn't finish).
##
## Built as scenes/race/race.tscn and placed at the root of a level (the parking garage has one): move its Grid
## (a Marker3D per starting slot, front row first) and its Finish (the Area3D, the painted line and BotGoal, the
## spot past the line the bots drive to) to fit the level, and give it a Route: Marker3Ds the bots drive through in
## order on their way down (the nav mesh finds the way between them). The HUD is scenes/ui/race_hud.tscn.
##
## Start it with the console's `race` command (scripts/ui/console.gd), which loads the race level first if needed.
## Who races: the player, every multiplayer guest, and the level's bot carts (BotCarts) unless started with
## `race nobots`. Carts are held through ShoppingCart.locked, so a guest's or a bot's keys are ignored exactly
## like the keyboard until GO.
##
## Multiplayer: the host runs the race and sends its state to the guests (RACE, net_protocol.gd) whenever it
## changes and every sync_interval; guests only show it. The host waits for every guest to load the level (up to
## guest_wait seconds) before it counts down, so everyone sees the same 3, 2, 1.

signal race_finished(results: Array)   ## [{id, name, time}] in finishing order (time < 0: didn't finish)

## Set by the console's race command just before it loads a race level: the level's Race starts once it's in.
static var start_on_load := false
static var bots_on_load := true

@export var countdown := 3                 ## the count: 3, 2, 1, then GO!
@export var go_hold := 1.0                 ## s GO! stays on screen after the start
@export var bots_race := true              ## the level's bot carts line up and race too
@export var finish_grace := 60.0           ## s after the winner finishes until the race ends for everyone else
@export var guest_wait := 10.0             ## s the host waits for guests to load the level before the count
@export var sync_interval := 0.5           ## s between the host's race updates to its guests
@export var grid: Node3D                   ## its Marker3D children are the starting slots, front row first
@export var finish: Area3D                 ## crossing into it finishes
@export var bot_goal: Marker3D             ## past the finish line, where the racing bots drive to
## The racing bots' way down: its Marker3D children in order (wide of each hairpin, say), then bot_goal.
@export var route: Node3D
@export var hud: RaceHUD

enum Phase { IDLE, WAITING, COUNTDOWN, RACING, DONE }
var phase := Phase.IDLE
## COUNTDOWN: seconds left to GO. RACING and DONE: race time. WAITING: seconds waited.
var clock := 0.0
## [{id: int, name: String, time: float (-1 until over the line), bot: CartBot or null}]. Ids: 1 the host (or
## the player offline), a guest's network id, -1, -2... the bots.
var racers: Array = []
var _since_winner := -1.0
var _sync_clock := 0.0
var _with_bots := true


func _ready() -> void:
	add_to_group("race")
	if start_on_load:
		start_on_load = false
		start.call_deferred(bots_on_load)   # after the level's own _ready has spawned the cart


## The level this race is in (a main.gd scene: cart, spawn_cart).
func level() -> Node:
	return get_parent()


func _net() -> NetSession:
	return get_node_or_null("/root/Net") as NetSession


func _is_guest() -> bool:
	var net := _net()
	return net != null and net.is_guest()


func slots() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for c in grid.get_children():
		if c is Marker3D:
			out.append(c)
	return out


## Lines everyone up and starts the count (after the guests have loaded). Returns false on a guest, where the
## host starts races. Calling it again mid-race starts over.
func start(with_bots := bots_race) -> bool:
	if _is_guest():
		return false
	_with_bots = with_bots
	for r in racers:
		if r.bot and is_instance_valid(r.bot):
			r.bot.stop_racing()
	racers.clear()
	hud.hide_results()
	var net := _net()
	var hosting := net != null and net.is_host()
	racers.append({"id": 1, "name": "Player 1" if hosting else "You", "time": -1.0, "bot": null})
	if hosting:
		for id in net.guest_ids():
			racers.append({"id": id, "name": net.guest_name(id), "time": -1.0, "bot": null})
	if with_bots:
		var n := 0
		for bot in level().find_children("*", "", true, false):
			if bot is CartBot and bot.cart and not bot.cart.puppet:
				n += 1
				racers.append({"id": -n, "name": "Bot %d" % n, "time": -1.0, "bot": bot})
	var marks := slots()
	if racers.size() > marks.size():
		push_warning("Race: %d racers but only %d grid slots; the rest sit this one out" % [racers.size(), marks.size()])
		racers.resize(marks.size())
	for i in racers.size():
		_line_up(racers[i], marks[i])
	_since_winner = -1.0
	clock = 0.0
	phase = Phase.WAITING if hosting else Phase.COUNTDOWN
	if phase == Phase.COUNTDOWN:
		clock = float(countdown)
	_lock_all(true)
	_send_state()
	return true


func _line_up(r: Dictionary, mark: Marker3D) -> void:
	var at := mark.global_position
	var yaw := mark.global_basis.get_euler().y
	if r.bot:
		r.bot.cart.place(at, yaw)
		r.bot.line_up()
	elif r.id == 1:
		level().spawn_cart(at, yaw)
	else:
		_net().place_guest_cart(r.id, at, yaw)


## The cart racing for `r` right now (a reset swaps the player's cart for a new one), or null if it has gone.
func cart_of(r: Dictionary) -> ShoppingCart:
	if r.bot:
		return r.bot.cart if is_instance_valid(r.bot) else null
	if r.id == 1:
		return level().get("cart")
	var net := _net()
	var c: ShoppingCart = net.carts.get(r.id) if net else null
	return c if c and is_instance_valid(c) else null


func _lock_all(on: bool) -> void:
	for r in racers:
		var c := cart_of(r)
		if c:
			c.locked = on


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	if _is_guest():
		# Only showing the host's race: run the clock between its updates.
		if phase == Phase.COUNTDOWN:
			clock = maxf(clock - delta, 0.0)
		elif phase == Phase.RACING:
			clock += delta
		return
	match phase:
		Phase.WAITING:
			clock += delta
			_join_late_guests()
			_lock_all(true)
			if _net() == null or _net().guests_loaded() or clock >= guest_wait:
				phase = Phase.COUNTDOWN
				clock = float(countdown)
				_send_state()
		Phase.COUNTDOWN:
			_join_late_guests()
			_lock_all(true)   # every tick: a cart reset during the count is a new cart
			clock -= delta
			if clock <= 0.0:
				_go()
		Phase.RACING:
			clock += delta
			if _since_winner >= 0.0:
				_since_winner += delta
				if _since_winner >= finish_grace:
					_end()
	_sync_clock += delta
	if _sync_clock >= sync_interval:
		_send_state()


## A guest who joined after the line-up but before GO gets a slot too.
func _join_late_guests() -> void:
	var net := _net()
	if net == null or not net.is_host():
		return
	var marks := slots()
	for id in net.guest_ids():
		if racers.any(func(r): return r.id == id) or racers.size() >= marks.size():
			continue
		var r := {"id": id, "name": net.guest_name(id), "time": -1.0, "bot": null}
		racers.append(r)
		_line_up(r, marks[racers.size() - 1])


func _go() -> void:
	phase = Phase.RACING
	clock = 0.0
	_lock_all(false)
	var way: Array[Vector3] = []
	if route:
		for m in route.get_children():
			if m is Marker3D:
				way.append(m.global_position)
	way.append(bot_goal.global_position)
	for r in racers:
		if r.bot:
			r.bot.race_to(way)
	_send_state()


func _end() -> void:
	phase = Phase.DONE
	_lock_all(false)
	for r in racers:
		if r.bot and is_instance_valid(r.bot):
			r.bot.stop_racing()
	_send_state()
	race_finished.emit(results())
	_log("Race over. " + ", ".join(results().map(func(r): return "%s %s" % [r.name, RaceHUD.format_time(r.time) if r.time >= 0.0 else "DNF"])))


## Connected in the scene to the Finish area's body_entered.
func _on_finish_body_entered(body: Node3D) -> void:
	if phase != Phase.RACING or _is_guest():
		return
	var cart := body.get_parent() as ShoppingCart
	if cart == null or body != cart.frame:
		return
	for r in racers:
		if r.time < 0.0 and cart_of(r) == cart:
			r.time = clock
			var place := racers.filter(func(x): return x.time >= 0.0).size()
			_log("%s finished %s in %s" % [r.name, RaceHUD.ordinal(place), RaceHUD.format_time(clock)])
			if _since_winner < 0.0:
				_since_winner = 0.0
			if racers.all(func(x): return x.time >= 0.0 or cart_of(x) == null):
				_end()
			else:
				_send_state()
			return


## Racers in finishing order: those over the line by time, then the rest.
func results() -> Array:
	var out := racers.map(func(r): return {"id": r.id, "name": r.name, "time": r.time})
	out.sort_custom(func(a, b):
		if (a.time >= 0.0) != (b.time >= 0.0):
			return a.time >= 0.0
		return a.time < b.time if a.time >= 0.0 else false)
	return out


## Our own racer id: 1 offline and on the host, our network id on a guest.
func my_id() -> int:
	return _net().my_id if _is_guest() else 1


# ---------------------------------------------------------------- screen

func _process(_delta: float) -> void:
	hud.visible = phase != Phase.IDLE
	if phase == Phase.IDLE:
		return
	var me: Dictionary = {}
	for r in racers:
		if r.id == my_id():
			me = r
	match phase:
		Phase.WAITING:
			hud.show_countdown("", 0.0)
			hud.show_clock(0.0, "Waiting for everyone to load...")
		Phase.COUNTDOWN:
			var n := ceili(clock)
			hud.show_countdown(str(n) if n > 0 else "GO!", float(n) - clock if n > 0 else 0.0)
			hud.show_clock(0.0, "Get ready: race down to the exit")
		Phase.RACING:
			hud.show_countdown("GO!" if clock < go_hold else "", clock / go_hold)
			var done := racers.filter(func(x): return x.time >= 0.0).size()
			var status := "Race down to the exit"
			if not me.is_empty() and me.time >= 0.0:
				status = "You finished %s in %s" % [RaceHUD.ordinal(_place_of(me)), RaceHUD.format_time(me.time)]
			elif done > 0:
				status = "%d over the line · %d s left" % [done, ceili(maxf(finish_grace - _since_winner, 0.0))] \
					if _since_winner >= 0.0 else "%d over the line" % done
			hud.show_clock(me.time if not me.is_empty() and me.time >= 0.0 else clock, status)
		Phase.DONE:
			hud.show_countdown("", 0.0)
			hud.show_clock(me.time if not me.is_empty() and me.time >= 0.0 else clock, "Race over")


func _place_of(r: Dictionary) -> int:
	return racers.filter(func(x): return x.time >= 0.0 and x.time <= r.time).size()


func _show_results() -> void:
	hud.show_results(results().map(func(r): return {"name": r.name, "time": r.time, "me": r.id == my_id()}))


func _log(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print(text)


# ---------------------------------------------------------------- multiplayer

## Host: the race as it stands, to every guest (RACE in net_protocol.gd). Also shows the results here once done.
func _send_state() -> void:
	_sync_clock = 0.0
	if phase == Phase.DONE:
		_show_results()
	var net := _net()
	if net == null or not net.is_host():
		return
	var b := NetProtocol.writer(NetProtocol.Msg.RACE)
	b.put_u8(net.level_serial)
	b.put_u8(phase)
	b.put_float(clock)
	b.put_float(_since_winner)
	b.put_u8(racers.size())
	for r in racers:
		b.put_32(r.id)
		b.put_float(r.time)
		NetProtocol.put_string(b, r.name)
	net.send_to_guests(b.data_array)


## Guest: the host's race (the RACE message after its level serial).
func apply_state(b: StreamPeerBuffer) -> void:
	var was := phase
	phase = b.get_u8() as Phase
	clock = b.get_float()
	_since_winner = b.get_float()
	racers.clear()
	for i in b.get_u8():
		racers.append({"id": b.get_32(), "time": b.get_float(), "name": NetProtocol.get_string(b), "bot": null})
	if phase == Phase.DONE:
		_show_results()
	elif was == Phase.DONE or phase == Phase.IDLE:
		hud.hide_results()
