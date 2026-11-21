class_name Sweep
extends Node3D
## A supermarket sweep: everyone lines up at the entrance, the screen counts 3, 2, 1, GO!, and then each shopper has
## `duration` seconds to fill their cart. Roll slowly past a ProductDisplay and its items drop into your basket one at
## a time (at most item_limit of any one product). Bump a giant Inflatable first to claim its bonus; stop in a
## BonusStation's box and hold still to earn its bonus. When the clock runs out, a cart's score is the price of what's
## in its basket at that moment plus its bonuses: whatever spilled out on the way doesn't count.
##
## Built as scenes/sweep/sweep.tscn and placed in a level (the supermarket has one): its Grid holds a Marker3D per
## starting slot, and the level puts its displays, inflatables and stations under the Sweep's Displays, Bonuses and
## Stations nodes. The HUD is scenes/ui/sweep_hud.tscn.
##
## Start it with the console's `sweep` command (scripts/ui/console.gd), which loads the supermarket first if needed.
## Who shops: the player, every multiplayer guest, and the level's bot carts unless started with `sweep nobots`.
##
## Multiplayer: the host runs the sweep (the items are level bodies, so its snapshots move them on every screen) and
## sends the sweep's state to the guests (SWEEP, net_protocol.gd) whenever it changes and every sync_interval.

signal sweep_finished(results: Array)   ## [{id, name, cents, items, bonus_cents}], best first

## Set by the console's sweep command just before it loads the sweep's level: the level's Sweep starts once it's in.
static var start_on_load := false
static var bots_on_load := true
static var duration_on_load := 0.0

@export var duration := 90.0               ## s of shopping
@export var countdown := 3                 ## the count: 3, 2, 1, then GO!
@export var go_hold := 1.0                 ## s GO! stays on screen after the start
@export var item_limit := 5                ## the most of any one product that counts in (or is dropped into) a cart
@export var grab_speed := 1.4              ## m/s: a cart slower than this at a display gets its items
@export var grab_interval := 0.35          ## s between items dropping into one cart
@export var bots_shop := true              ## the level's bot carts shop too
@export var bot_linger := 6.0              ## s a bot waits at a display at most before moving on
@export var guest_wait := 10.0             ## s the host waits for guests to load the level before the count
@export var sync_interval := 0.5           ## s between the host's sweep updates to its guests
@export var grid: Node3D                   ## its Marker3D children are the starting slots
@export var displays: Node3D               ## ProductDisplay children
@export var bonuses: Node3D                ## Inflatable children
@export var stations: Node3D               ## BonusStation children
@export var hud: SweepHUD

enum Phase { IDLE, WAITING, COUNTDOWN, SWEEPING, DONE }
var phase := Phase.IDLE
## COUNTDOWN: s to GO. SWEEPING: s left. WAITING: s waited. DONE: 0.
var clock := 0.0
var round_time := 90.0
## [{id, name, bot (CartBot or null), cents (basket total, capped), items, bonus_cents, ...host-only bookkeeping}].
## Ids: 1 the host (or the player offline), a guest's network id, -1, -2... the bots.
var shoppers: Array = []
var _sync_clock := 0.0
var _events: Array = []   ## [[shopper id, text]] not yet sent to the guests
var _last_my_cents := -1   ## what our basket was worth last frame (spill warnings)


func _ready() -> void:
	add_to_group("sweep")
	round_time = duration
	if start_on_load:
		start_on_load = false
		var secs := duration_on_load
		duration_on_load = 0.0
		start.call_deferred(bots_on_load, secs)   # after the level's own _ready has spawned the cart


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


func display_list() -> Array[ProductDisplay]:
	var out: Array[ProductDisplay] = []
	for c in displays.get_children():
		if c is ProductDisplay:
			out.append(c)
	return out


func inflatable_list() -> Array[Inflatable]:
	var out: Array[Inflatable] = []
	for c in bonuses.get_children():
		if c is Inflatable:
			out.append(c)
	return out


func station_list() -> Array[BonusStation]:
	var out: Array[BonusStation] = []
	for c in stations.get_children():
		if c is BonusStation:
			out.append(c)
	return out


## Every product in the store, on its display or not.
func products() -> Array[Product]:
	var out: Array[Product] = []
	for d in display_list():
		out.append_array(d.items())
	return out


## Restocks the store, lines everyone up and starts the count (after the guests have loaded). `seconds` > 0 sets
## the round's length (else `duration`). Returns false on a guest, where the host starts sweeps. Calling it again
## mid-sweep starts over.
func start(with_bots := bots_shop, seconds := 0.0) -> bool:
	if _is_guest():
		return false
	round_time = seconds if seconds > 0.0 else duration
	for s in shoppers:
		if s.bot and is_instance_valid(s.bot):
			s.bot.stop_errand()
	shoppers.clear()
	hud.hide_results()
	for d in display_list():
		d.restock()
	for b in inflatable_list():
		b.restock()
	var net := _net()
	var hosting := net != null and net.is_host()
	shoppers.append(_shopper(1, "Player 1" if hosting else "You", null))
	if hosting:
		for id in net.guest_ids():
			shoppers.append(_shopper(id, net.guest_name(id), null))
	if with_bots:
		var n := 0
		for bot in level().find_children("*", "", true, false):
			if bot is CartBot and bot.cart and not bot.cart.puppet:
				n += 1
				shoppers.append(_shopper(-n, "Bot %d" % n, bot))
	var marks := slots()
	if shoppers.size() > marks.size():
		push_warning("Sweep: %d shoppers but only %d slots; the rest sit this one out" % [shoppers.size(), marks.size()])
		shoppers.resize(marks.size())
	for i in shoppers.size():
		_line_up(shoppers[i], marks[i])
	clock = 0.0
	phase = Phase.WAITING if hosting else Phase.COUNTDOWN
	if phase == Phase.COUNTDOWN:
		clock = float(countdown)
	_last_my_cents = -1
	_lock_all(true)
	_send_state()
	return true


func _shopper(id: int, name: String, bot: CartBot) -> Dictionary:
	return {"id": id, "name": name, "bot": bot, "cents": 0, "items": 0, "bonus_cents": 0,
		"grab_wait": 0.0, "warned": {}, "station_time": {}, "stations_done": {}, "target": null, "linger": 0.0,
		"visited": null}


func _line_up(s: Dictionary, mark: Marker3D) -> void:
	var at := mark.global_position
	var yaw := mark.global_basis.get_euler().y
	if s.bot:
		s.bot.cart.place(at, yaw)
		s.bot.stop_errand()
		s.bot.drive_to(at)   # stands on its slot until GO
	elif s.id == 1:
		level().spawn_cart(at, yaw)
	else:
		_net().place_guest_cart(s.id, at, yaw)
	var c := cart_of(s)
	if c:
		c.show_groceries(false)


## The cart shopping for `s` right now (a reset swaps the player's cart for a new one), or null if it has gone.
func cart_of(s: Dictionary) -> ShoppingCart:
	if s.bot:
		return s.bot.cart if is_instance_valid(s.bot) else null
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
		# Only showing the host's sweep: run the clock between its updates, and keep every cart's own groceries
		# out of the way (the host has taken them out of play).
		if phase == Phase.COUNTDOWN or phase == Phase.SWEEPING:
			clock = maxf(clock - delta, 0.0)
		_hide_all_groceries()
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
		Phase.SWEEPING:
			clock -= delta
			_shop(delta)
			if clock <= 0.0:
				clock = 0.0
				_end()
	for s in shoppers:
		var c := cart_of(s)
		if c:
			c.show_groceries(false)   # a cart reset mid-sweep comes with its groceries: out they go
	_sync_clock += delta
	if _sync_clock >= sync_interval or not _events.is_empty():
		_send_state()


func _hide_all_groceries() -> void:
	for c in level().find_children("*", "", true, false):
		if c is ShoppingCart:
			c.show_groceries(false)


## A guest who joined after the line-up but before GO gets a slot too.
func _join_late_guests() -> void:
	var net := _net()
	if net == null or not net.is_host():
		return
	var marks := slots()
	for id in net.guest_ids():
		if shoppers.any(func(s): return s.id == id) or shoppers.size() >= marks.size():
			continue
		var s := _shopper(id, net.guest_name(id), null)
		shoppers.append(s)
		_line_up(s, marks[shoppers.size() - 1])


func _go() -> void:
	phase = Phase.SWEEPING
	clock = round_time
	_lock_all(false)
	_send_state()


func _end() -> void:
	_tally()
	phase = Phase.DONE
	for s in shoppers:
		if s.bot and is_instance_valid(s.bot):
			s.bot.stop_errand()
	_send_state()
	sweep_finished.emit(results())
	_log("Sweep over. " + ", ".join(results().map(func(r): return "%s %s" % [r.name, SweepHUD.money(r.cents)])))


# ---------------------------------------------------------------- the rules (host)

func _shop(delta: float) -> void:
	_tally()
	var by_frame := {}   # frame body -> shopper
	for s in shoppers:
		var c := cart_of(s)
		if c == null:
			continue
		by_frame[c.frame] = s
		var speed := c.frame.linear_velocity.length()
		# Displays: rolling slowly through one, the next item drops in (unless this cart has its limit of it).
		s.grab_wait = maxf(0.0, s.grab_wait - delta)
		if s.grab_wait <= 0.0 and speed < grab_speed and not c.fallen:
			for d in display_list():
				if not d.zone.overlaps_body(c.frame):
					continue
				var item := d.next_item()
				if item == null:
					continue
				if _count_of(c, item.product_name) >= item_limit:
					if not s.warned.has(item.product_name):
						s.warned[item.product_name] = true
						_event(s, "Limit %d of %s" % [item_limit, item.product_name])
					continue
				item.drop_into(c, c.basket_drop(Vector2(randf_range(-1, 1), randf_range(-1, 1))))
				s.grab_wait = grab_interval
				_event(s, "+%s  %s" % [SweepHUD.money(item.cents()), item.product_name])
				break
		# Bonus stations: stand still in the box for its hold_time.
		for st in station_list():
			var key := st.get_instance_id()
			if s.stations_done.has(key):
				continue
			if st.overlaps_body(c.frame) and speed < st.still_speed:
				var t: float = s.station_time.get(key, 0.0) + delta
				s.station_time[key] = t
				if t >= st.hold_time:
					s.stations_done[key] = true
					s.bonus_cents += st.cents()
					_event(s, "BONUS +%s  %s" % [SweepHUD.money(st.cents()), st.title.capitalize()])
			else:
				s.station_time.erase(key)
	# Inflatables: the first shopper's cart to touch one claims it.
	for b in inflatable_list():
		if b.claimed:
			continue
		for body in b.get_colliding_bodies():
			var cart := body.get_parent() as ShoppingCart
			if cart == null or not by_frame.has(cart.frame):
				continue
			var s: Dictionary = by_frame[cart.frame]
			b.claim()
			s.bonus_cents += b.cents()
			_event(s, "BONUS +%s  %s!" % [SweepHUD.money(b.cents()), b.bonus_name])
			break
	for s in shoppers:
		if s.bot:
			_steer_bot(s, delta)
	_tally()


## Counts what's in each cart's basket: items and their price, at most item_limit of each product.
func _tally() -> void:
	var loose := products().filter(func(p): return not p.on_display)
	for s in shoppers:
		var c := cart_of(s)
		var per := {}
		var cents := 0
		var items := 0
		if c:
			for p in loose:
				if c.in_basket(p.global_position):
					var n: int = per.get(p.product_name, 0)
					if n < item_limit:
						per[p.product_name] = n + 1
						cents += p.cents()
						items += 1
		s.cents = cents + s.bonus_cents
		s.items = items


func _count_of(c: ShoppingCart, product_name: String) -> int:
	var n := 0
	for p in products():
		if not p.on_display and p.product_name == product_name and c.in_basket(p.global_position):
			n += 1
	return n


## Bots: drive to the display worth most to them (price times what they can still take, over the distance, and
## less if another bot is already headed there), wait there while the items drop in, then on to the next.
func _steer_bot(s: Dictionary, delta: float) -> void:
	var bot: CartBot = s.bot
	if not is_instance_valid(bot) or bot.cart.fallen:
		return
	var d: ProductDisplay = s.target
	if d and bot.at_errand():
		s.linger += delta
		var done := d.left() == 0 or _count_of(bot.cart, d.product_name()) >= item_limit
		if done or s.linger > bot_linger:
			s.visited = d
			s.target = null
	if s.target == null:
		var best: ProductDisplay = null
		var best_v := 0.0
		var at := bot.cart.cart_origin()
		var taken := shoppers.filter(func(o): return o.bot and o != s).map(func(o): return o.target)
		for c in display_list():
			if c == s.visited:
				continue
			var can := mini(c.left(), item_limit - _count_of(bot.cart, c.product_name()))
			if can <= 0:
				continue
			var v := c.price() * can / (at.distance_to(c.stop.global_position) + 6.0)
			if c in taken:
				v *= 0.3   # another bot is headed there: spread out
			if v > best_v:
				best_v = v
				best = c
		if best:
			s.target = best
			s.linger = 0.0
			bot.drive_to(best.stop.global_position)


func _event(s: Dictionary, text: String) -> void:
	if s.id == my_id():
		hud.toast(text)
	elif s.id > 1:
		_events.append([s.id, text])


## Shoppers best first: by score, then by fewer items (the same total with less in the cart wins), then by name.
func results() -> Array:
	var out := shoppers.map(func(s): return {"id": s.id, "name": s.name, "cents": s.cents, "items": s.items,
		"bonus_cents": s.bonus_cents})
	out.sort_custom(func(a, b):
		if a.cents != b.cents:
			return a.cents > b.cents
		if a.items != b.items:
			return a.items < b.items
		return a.name < b.name)
	return out


## Our own shopper id: 1 offline and on the host, our network id on a guest.
func my_id() -> int:
	return _net().my_id if _is_guest() else 1


func _me() -> Dictionary:
	for s in shoppers:
		if s.id == my_id():
			return s
	return {}


# ---------------------------------------------------------------- screen

func _process(_delta: float) -> void:
	hud.visible = phase != Phase.IDLE
	if phase == Phase.IDLE:
		return
	var me := _me()
	match phase:
		Phase.WAITING:
			hud.show_countdown("", 0.0)
			hud.show_clock(round_time, "Waiting for everyone to load...")
		Phase.COUNTDOWN:
			var n := ceili(clock)
			hud.show_countdown(str(n) if n > 0 else "GO!", float(n) - clock if n > 0 else 0.0)
			hud.show_clock(round_time, "Get ready to shop! %d of any one item counts" % item_limit)
		Phase.SWEEPING:
			var since := round_time - clock
			hud.show_countdown("GO!" if since < go_hold else "", since / go_hold)
			hud.show_clock(clock, "Roll slowly past a display to grab · don't spill!" if since < 8.0 else "")
		Phase.DONE:
			hud.show_countdown("", 0.0)
			hud.show_clock(0.0, "Time's up!")
	if not me.is_empty():
		hud.show_basket(me.cents, me.items, me.bonus_cents)
		# What's in the basket went down: something fell out.
		var basket: int = me.cents - me.bonus_cents
		if phase == Phase.SWEEPING and _last_my_cents >= 0 and basket < _last_my_cents:
			hud.toast("Spilled! -%s" % SweepHUD.money(_last_my_cents - basket))
		_last_my_cents = basket
	hud.show_standings(results().map(func(r): return {"name": r.name, "cents": r.cents, "me": r.id == my_id()}) \
		if shoppers.size() > 1 else [])


func _show_results() -> void:
	hud.show_results(results().map(func(r): return {"name": r.name, "cents": r.cents, "items": r.items,
		"bonus_cents": r.bonus_cents, "me": r.id == my_id()}))


func _log(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print(text)


# ---------------------------------------------------------------- multiplayer

## Host: the sweep as it stands, to every guest (SWEEP in net_protocol.gd). Also shows the results here once done.
func _send_state() -> void:
	_sync_clock = 0.0
	if phase == Phase.DONE:
		_show_results()
	var net := _net()
	if net == null or not net.is_host():
		_events.clear()
		return
	var b := NetProtocol.writer(NetProtocol.Msg.SWEEP)
	b.put_u8(net.level_serial)
	b.put_u8(phase)
	b.put_float(clock)
	b.put_float(round_time)
	b.put_u8(item_limit)
	b.put_u8(shoppers.size())
	for s in shoppers:
		b.put_32(s.id)
		b.put_u32(s.cents)
		b.put_u16(s.items)
		b.put_u32(s.bonus_cents)
		NetProtocol.put_string(b, s.name)
	var ds := display_list()
	b.put_u8(ds.size())
	for d in ds:
		b.put_u8(d.left())
	b.put_u8(_events.size())
	for e in _events:
		b.put_32(e[0])
		NetProtocol.put_string(b, e[1])
	_events.clear()
	net.send_to_guests(b.data_array)


## Guest: the host's sweep (the SWEEP message after its level serial).
func apply_state(b: StreamPeerBuffer) -> void:
	var was := phase
	phase = b.get_u8() as Phase
	clock = b.get_float()
	round_time = b.get_float()
	item_limit = b.get_u8()
	shoppers.clear()
	for i in b.get_u8():
		var s := _shopper(b.get_32(), "", null)
		s.cents = b.get_u32()
		s.items = b.get_u16()
		s.bonus_cents = b.get_u32()
		s.name = NetProtocol.get_string(b)
		shoppers.append(s)
	var ds := display_list()
	for i in b.get_u8():
		var n := b.get_u8()
		if i < ds.size():
			ds[i].left_override = n
	for i in b.get_u8():
		var id := b.get_32()
		var text := NetProtocol.get_string(b)
		if id == my_id():
			hud.toast(text)
	if phase == Phase.DONE:
		_show_results()
	elif was == Phase.DONE or phase == Phase.IDLE:
		hud.hide_results()
	if was == Phase.IDLE and phase != Phase.IDLE:
		_last_my_cents = -1
