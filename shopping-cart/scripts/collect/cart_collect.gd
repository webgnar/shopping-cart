class_name CartCollect
extends Node3D
## Cart collection: a timed round in a supermarket parking lot with loose carts scattered everywhere. Ram a cart
## from behind, lined up, and it nests onto the front of yours (Frame/NestMouth, scripts/cart/cart_nest.gd); ram
## more with the front of your chain to make it longer. Push the chain into the store's cart return door: when
## your own cart reaches the DropSensor in the doorway it stops there, the carts it was pushing let go and roll on
## into the store, and each one cashes in as it gets Inside. The most points when the clock runs out wins.
##
## Points: a drop of n carts scores cart_points for its first cart and chain_bonus more for every cart after that
## (10, 15, 20... by default), so one long chain beats the same carts brought in one at a time.
##
## Built as scenes/collect/cart_collect.tscn and placed in a level (scenes/levels/cart_collect_lot.tscn): its Grid
## holds a Marker3D per starting slot; the level points `carts` at the node holding the loose carts and `door` at
## its CartDoor (scenes/collect/cart_door.tscn: DropSensor, Inside, StopBar, StoreRoom). Returned carts are put
## away in rows in the store room, out of sight. HUD: scenes/ui/collect_hud.tscn. The round starts when the level
## loads (console `collect`); typing `collect` again reloads the lot and starts over.
##
## Multiplayer: the host runs the round (the carts are level bodies, so its snapshots move them on every screen),
## waits for every guest to load the lot before the count, and sends the round to the guests (COLLECT,
## net_protocol.gd) whenever it changes and every sync_interval. Guests who join late get a cart and play on.

signal round_finished(results: Array)   ## [{id, name, points, returned, best_chain}], best first

@export var start_on_ready := true          ## start a round as soon as the lot loads
@export var duration := 300.0               ## s of collecting
@export var countdown := 3                  ## the count: 3, 2, 1, then GO!
@export var go_hold := 1.0                  ## s GO! stays on screen after the start
@export var cart_points := 10               ## points for the first cart of a drop
@export var chain_bonus := 5                ## each further cart in the same drop is worth this much more
@export var roll_in_speed := 1.8            ## m/s: released carts roll on into the store at least this fast
@export var roll_time := 4.0                ## s a released cart has to get Inside, or it is back in play
@export var room_columns := 14              ## returned carts stand in rows this many wide in the store room
@export var room_spacing := Vector2(0.75, 1.3)   ## m between them: across a row, and row to row
@export var guest_wait := 10.0              ## s the host waits for guests to load the lot before the count
@export var sync_interval := 0.5            ## s between the host's updates to its guests
@export var grid: Node3D                    ## its Marker3D children are the starting slots
@export var carts: Node3D                   ## the loose carts (ShoppingCarts anywhere under it)
@export var door: Node3D                    ## the store's CartDoor
@export var hud: CollectHUD

enum Phase { IDLE, WAITING, COUNTDOWN, COLLECTING, DONE }
var phase := Phase.IDLE
## COUNTDOWN: s to GO. COLLECTING: s left. WAITING: s waited. DONE: 0.
var clock := 0.0
## [{id, name, points, returned, best_chain, carrying}]. Ids: 1 the host (or the player offline), else a guest's
## network id.
var shoppers: Array = []
var _home := {}       ## loose cart -> [handle position, heading] where it stood when the lot loaded
var _rolling := {}    ## released cart -> {id, points, left}: on its way in
var _returned := {}   ## loose cart -> true: cashed in and put away
var _sync_clock := 0.0
var _events: Array = []   ## [[shopper id, text]] not yet sent to the guests

@onready var drop_sensor: Area3D = door.get_node("DropSensor")
@onready var inside: Area3D = door.get_node("Inside")
@onready var stop_bar: StaticBody3D = door.get_node("StopBar")
@onready var store_room: Marker3D = door.get_node("StoreRoom")


func _ready() -> void:
	add_to_group("cart_collect")
	if start_on_ready:
		start.call_deferred()   # after the level's own _ready has spawned the cart


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


## Every loose cart in the lot, returned or not.
func loose_carts() -> Array[ShoppingCart]:
	var out: Array[ShoppingCart] = []
	for c in carts.find_children("*", "", true, false):
		if c is ShoppingCart:
			out.append(c)
	return out


## Into the store: the way a cart going through the door rolls.
func inward() -> Vector3:
	return -door.global_basis.x.normalized()


## Puts the loose carts back where they stood, lines everyone up and starts the count (after the guests have
## loaded). Returns false on a guest, where the host starts rounds. Calling it again mid-round starts over.
func start() -> bool:
	if _is_guest():
		return false
	hud.hide_results()
	_reset_carts()
	shoppers.clear()
	var net := _net()
	var hosting := net != null and net.is_host()
	shoppers.append(_shopper(1, "Player 1" if hosting else "You"))
	if hosting:
		for id in net.guest_ids():
			shoppers.append(_shopper(id, net.guest_name(id)))
	var marks := slots()
	if shoppers.size() > marks.size():
		push_warning("CartCollect: %d players but only %d slots; the rest sit this one out" % [shoppers.size(), marks.size()])
		shoppers.resize(marks.size())
	for i in shoppers.size():
		_line_up(shoppers[i], marks[i])
	clock = 0.0
	phase = Phase.WAITING if hosting else Phase.COUNTDOWN
	if phase == Phase.COUNTDOWN:
		clock = float(countdown)
	_lock_all(true)
	_send_state()
	return true


func _shopper(id: int, name: String) -> Dictionary:
	return {"id": id, "name": name, "points": 0, "returned": 0, "best_chain": 0, "carrying": 0}


## Every loose cart off any chain and back on its spot; the door's stop bar lets them (and only them) through.
func _reset_carts() -> void:
	_rolling.clear()
	_returned.clear()
	var list := loose_carts()
	if _home.is_empty():
		for c in list:
			_home[c] = [c.cart_origin(), c.heading()]
			for b in c.bodies():
				stop_bar.add_collision_exception_with(b)
	for c in list:
		for x in c.stack():
			if x.nest:
				x.nest.come_apart()
	for c in list:
		c.place(_home[c][0], _home[c][1])


func _line_up(s: Dictionary, mark: Marker3D) -> void:
	var at := mark.global_position
	var yaw := mark.global_basis.get_euler().y
	if s.id == 1:
		level().spawn_cart(at, yaw)
	else:
		_net().place_guest_cart(s.id, at, yaw)


## The cart playing for `s` right now (a reset swaps the player's cart for a new one), or null if it has gone.
func cart_of(s: Dictionary) -> ShoppingCart:
	if s.id == 1:
		return level().get("cart")
	var net := _net()
	var c: ShoppingCart = net.carts.get(s.id) if net else null
	return c if c and is_instance_valid(c) else null


func _lock_all(on: bool) -> void:
	for s in shoppers:
		var c := cart_of(s)
		if c:
			c.locked = on


func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	if _is_guest():
		# Only showing the host's round: run the clock between its updates.
		if phase == Phase.COUNTDOWN or phase == Phase.COLLECTING:
			clock = maxf(clock - delta, 0.0)
		return
	if phase != Phase.DONE:
		_join_late_guests()
	match phase:
		Phase.WAITING:
			clock += delta
			_lock_all(true)
			if _net() == null or _net().guests_loaded() or clock >= guest_wait:
				phase = Phase.COUNTDOWN
				clock = float(countdown)
				_send_state()
		Phase.COUNTDOWN:
			_lock_all(true)   # every tick: a cart reset during the count is a new cart
			clock -= delta
			if clock <= 0.0:
				_go()
		Phase.COLLECTING:
			clock -= delta
			_collect(delta)
			if clock <= 0.0:
				clock = 0.0
				_end()
	for s in shoppers:
		var c := cart_of(s)
		if c:
			c.show_groceries(false)   # empty carts: a reset comes with groceries, out they go
	_sync_clock += delta
	if _sync_clock >= sync_interval or not _events.is_empty():
		_send_state()


## A guest who joined after the line-up gets a slot (before GO) or plays on from where it spawned.
func _join_late_guests() -> void:
	var net := _net()
	if net == null or not net.is_host():
		return
	var marks := slots()
	for id in net.guest_ids():
		if shoppers.any(func(s): return s.id == id) or shoppers.size() >= marks.size():
			continue
		var s := _shopper(id, net.guest_name(id))
		shoppers.append(s)
		if phase != Phase.COLLECTING:
			_line_up(s, marks[shoppers.size() - 1])


func _go() -> void:
	phase = Phase.COLLECTING
	clock = duration
	_lock_all(false)
	_send_state()


func _end() -> void:
	phase = Phase.DONE
	_lock_all(true)
	_send_state()
	round_finished.emit(results())
	_log("Time's up. " + ", ".join(results().map(func(r): return "%s %d" % [r.name, r.points])))


# ---------------------------------------------------------------- the rules (host)

func _collect(delta: float) -> void:
	var player_carts := {}
	for s in shoppers:
		var c := cart_of(s)
		if c == null:
			s.carrying = 0
			continue
		player_carts[c] = true
		var ahead := _carried(c)
		s.carrying = ahead.size()
		# Our own cart at the door: it stops there, and the carts it was pushing go on in.
		if drop_sensor.overlaps_body(c.frame):
			_stop(c)
			if not ahead.is_empty():
				_drop(s, c, ahead)
				s.carrying = 0
	# Released carts cash in as they get Inside.
	for c in _rolling.keys():
		var r: Dictionary = _rolling[c]
		r.left -= delta
		if inside.overlaps_body(c.frame):
			var s := _shopper_by_id(r.id)
			if not s.is_empty():
				s.points += r.points
				s.returned += 1
				_event(s, "+%d  cart returned" % r.points)
			_rolling.erase(c)
			_put_away(c)
		elif r.left <= 0.0:
			_rolling.erase(c)   # didn't make it in: back in play
	# A loose cart shoved in on its own (not pushed in on a chain) is taken in too, for nobody's points.
	for c in loose_carts():
		if _returned.has(c) or _rolling.has(c) or c.nested_in != null or c.nested_behind != null:
			continue
		if inside.overlaps_body(c.frame):
			_put_away(c)


## The loose carts nested on the front of `c`, nearest first.
func _carried(c: ShoppingCart) -> Array[ShoppingCart]:
	var out: Array[ShoppingCart] = []
	var x := c.nested_in
	while x != null:
		if _home.has(x):
			out.append(x)
		x = x.nested_in
	return out


## Kills the cart's speed into the store (it can still back out).
func _stop(c: ShoppingCart) -> void:
	var dir := inward()
	for b in c.net_bodies():
		var v := b.linear_velocity.dot(dir)
		if v > 0.0:
			b.linear_velocity -= dir * v


## `c` lets go of the chain it was pushing: every nest from it forward comes apart, and the carts roll on in.
func _drop(s: Dictionary, c: ShoppingCart, ahead: Array[ShoppingCart]) -> void:
	var chain := c.stack()
	for i in range(chain.find(c), 0, -1):
		if chain[i].nest:
			chain[i].nest.come_apart()
	var dir := inward()
	var n := ahead.size()
	var total := 0
	for k in n:
		var x := ahead[n - 1 - k]   # the front cart is the drop's first
		var pts := cart_points + chain_bonus * k
		total += pts
		x._wake()
		for b in x.bodies():
			var v := b.linear_velocity.dot(dir)
			if v < roll_in_speed:
				b.linear_velocity += dir * (roll_in_speed - v)
		_rolling[x] = {"id": s.id, "points": pts, "left": roll_time}
	s.best_chain = maxi(s.best_chain, n)
	if n > 1:
		_event(s, "%d-cart chain!  +%d" % [n, total])


## Into the store room, out of play: the next spot in its rows.
func _put_away(c: ShoppingCart) -> void:
	var i := _returned.size()
	_returned[c] = true
	var at := store_room.global_transform * Vector3(room_spacing.y * (i / room_columns), 0, room_spacing.x * (i % room_columns))
	c.place(at, store_room.global_basis.get_euler().y)


func _shopper_by_id(id: int) -> Dictionary:
	for s in shoppers:
		if s.id == id:
			return s
	return {}


func _event(s: Dictionary, text: String) -> void:
	if s.id == my_id():
		hud.toast(text)
	elif s.id > 1:
		_events.append([s.id, text])


## Players best first: by points, then by carts returned, then by name.
func results() -> Array:
	var out := shoppers.map(func(s): return {"id": s.id, "name": s.name, "points": s.points,
		"returned": s.returned, "best_chain": s.best_chain})
	out.sort_custom(func(a, b):
		if a.points != b.points:
			return a.points > b.points
		if a.returned != b.returned:
			return a.returned > b.returned
		return a.name < b.name)
	return out


## Our own id: 1 offline and on the host, our network id on a guest.
func my_id() -> int:
	return _net().my_id if _is_guest() else 1


func _me() -> Dictionary:
	return _shopper_by_id(my_id())


# ---------------------------------------------------------------- screen

func _process(_delta: float) -> void:
	hud.visible = phase != Phase.IDLE
	if phase == Phase.IDLE:
		return
	match phase:
		Phase.WAITING:
			hud.show_countdown("", 0.0)
			hud.show_clock(duration, "Waiting for everyone to load...")
		Phase.COUNTDOWN:
			var n := ceili(clock)
			hud.show_countdown(str(n) if n > 0 else "GO!", float(n) - clock if n > 0 else 0.0)
			hud.show_clock(duration, "Round up the carts and push them into the store!")
		Phase.COLLECTING:
			var since := duration - clock
			hud.show_countdown("GO!" if since < go_hold else "", since / go_hold)
			hud.show_clock(clock, "Ram a cart from behind to hook it on · push the chain into CART RETURN" if since < 10.0 else "")
		Phase.DONE:
			hud.show_countdown("", 0.0)
			hud.show_clock(0.0, "Time's up!")
	var me := _me()
	if not me.is_empty():
		hud.show_score(me.points, me.returned, me.carrying)
	hud.show_board(results().map(func(r): return {"name": r.name, "points": r.points, "me": r.id == my_id()}) \
		if shoppers.size() > 1 else [])


func _show_results() -> void:
	hud.show_final(results().map(func(r): return {"name": r.name, "points": r.points, "returned": r.returned,
		"best_chain": r.best_chain, "me": r.id == my_id()}))


func _log(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print(text)


# ---------------------------------------------------------------- multiplayer

## Host: the round as it stands, to every guest (COLLECT in net_protocol.gd). Also shows the results here once done.
func _send_state() -> void:
	_sync_clock = 0.0
	if phase == Phase.DONE:
		_show_results()
	var net := _net()
	if net == null or not net.is_host():
		_events.clear()
		return
	var b := NetProtocol.writer(NetProtocol.Msg.COLLECT)
	b.put_u8(net.level_serial)
	b.put_u8(phase)
	b.put_float(clock)
	b.put_float(duration)
	b.put_u8(shoppers.size())
	for s in shoppers:
		b.put_32(s.id)
		b.put_u32(s.points)
		b.put_u16(s.returned)
		b.put_u16(s.best_chain)
		b.put_u16(s.carrying)
		NetProtocol.put_string(b, s.name)
	b.put_u8(_events.size())
	for e in _events:
		b.put_32(e[0])
		NetProtocol.put_string(b, e[1])
	_events.clear()
	net.send_to_guests(b.data_array)


## Guest: the host's round (the COLLECT message after its level serial).
func apply_state(b: StreamPeerBuffer) -> void:
	var was := phase
	phase = b.get_u8() as Phase
	clock = b.get_float()
	duration = b.get_float()
	shoppers.clear()
	for i in b.get_u8():
		var s := _shopper(b.get_32(), "")
		s.points = b.get_u32()
		s.returned = b.get_u16()
		s.best_chain = b.get_u16()
		s.carrying = b.get_u16()
		s.name = NetProtocol.get_string(b)
		shoppers.append(s)
	for i in b.get_u8():
		var id := b.get_32()
		var text := NetProtocol.get_string(b)
		if id == my_id():
			hud.toast(text)
	if phase == Phase.DONE:
		_show_results()
	elif was == Phase.DONE or phase == Phase.IDLE:
		hud.hide_results()
