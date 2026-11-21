class_name NetSession
extends Node
## Multiplayer, host-authoritative: one player hosts, and the host's physics is the only physics. The `Net`
## autoload (scenes/net/net_session.tscn). Prototype: guests join by address (LAN, or two copies on one machine);
## join codes, the server browser and NAT traversal come later through the Cloudflare rendezvous (docs/MULTIPLAYER.md).
##
## Host: plays as usual. Each guest gets a cart (cart.tscn) beside the level's CartSpawn, driven through the cart's
## `controls`, exactly like a bot cart, from the keys the guest holds (INPUT packets). Every tick it sends
## snapshots of every moving body: all player carts (whole rigs and groceries) and the level's loose bodies (boxes,
## spare and bot carts). Resting bodies are resent a few at a time, so a lost packet can't leave one stale for long.
## Guest: loads the host's level, freezes every body in it and shows the host's world: each body is moved between
## the two snapshots around (newest - interp_delay). Its own keys go to the host; its own cart is one of the
## snapshot carts. Bot carts' bots don't run on a guest.
##
## Start it from the console (`host`, `join <address>`, `leave`, `net`) or the command line:
##   godot --path shopping-cart -- --host            (port: --host=24601)
##   godot --path shopping-cart -- --join=127.0.0.1  (or --join=192.168.1.20:24601)
## The transport is any MultiplayerPeer, polled directly with our own packets (net_protocol.gd), not Godot's RPCs,
## so the browser game can speak the same bytes: ENet for now, WebRTCMultiplayerPeer once signaling exists.

signal status_changed(text: String)

const CART_SCENE := preload("res://scenes/cart/cart.tscn")

@export var default_port := 24601
@export var max_guests := 7
@export var snapshot_rate := 30.0         ## snapshots a second the host sends
@export var input_rate := 30.0            ## a guest resends its keys this often even when nothing changes
@export var interp_delay := 0.1           ## s a guest shows the world behind the newest snapshot
@export var refresh_per_snapshot := 24    ## resting bodies resent with each snapshot
@export var spawn_spacing := 1.2          ## m between guest carts, in a row to the right of CartSpawn
@export var max_packet := 1100            ## bytes: snapshots are split to stay under one network packet
@export var connect_timeout := 8.0        ## s a guest waits for the host to answer

enum Role { OFFLINE, HOST, GUEST }
var role := Role.OFFLINE
var peer: MultiplayerPeer = null
var my_id := 0
var host_address := ""
## The level being played (a main.gd scene) once it has called level_ready, else null.
var level: Node = null
var level_serial := 0
var level_bodies: Array[RigidBody3D] = []   ## the level's loose bodies, in the same order on every machine
## Player id -> ShoppingCart. Host: guests' carts. Guest: every player's cart as shown here, its own included.
var carts := {}
## What has gone through, for the status line and tests.
var stats := {"snapshots_sent": 0, "snapshots_received": 0, "inputs_received": 0, "packets_in": 0}

@onready var _overlay: CanvasLayer = $Overlay
@onready var _status: Label = %Status

# host
var _guests := {}            ## id -> {"keys": int, "slot": int} for guests that said HELLO
var _tick := 0
var _snap_clock := 0.0
var _refresh_cursor := 0
# guest
var _samples := {}           ## RigidBody3D -> [t0, pos0, rot0, t1, pos1, rot1]
var _newest := -1.0          ## host time (s) of the newest snapshot
var _render_time := 0.0      ## host time (s) the guest is showing
var _keys_sent := -1
var _input_clock := 0.0
var _welcomed := false
var _connecting_for := 0.0
var _expected_bodies := -1


func _ready() -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("add_command"):
		console.add_command("host", _cmd_host, "host a multiplayer game: host [port]")
		console.add_command("join", _cmd_join, "join a game: join <address>[:port]")
		console.add_command("leave", func(_a): leave(), "leave or stop the multiplayer game")
		console.add_command("net", func(_a): _log(status_text()), "show the multiplayer status")
	for arg in OS.get_cmdline_user_args():
		if arg == "--host" or arg.begins_with("--host="):
			host.call_deferred(int(arg.get_slice("=", 1)) if "=" in arg else default_port)
		elif arg.begins_with("--join="):
			_join_address.call_deferred(arg.get_slice("=", 1))
	_update_status()


# ---------------------------------------------------------------- starting and stopping

func host(port: int = 0) -> bool:
	leave()
	port = port if port > 0 else default_port
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_guests, 2)
	if err != OK:
		_log("[color=#ff8a7a]Couldn't host on port %d (error %d).[/color]" % [port, err])
		return false
	peer = enet
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	role = Role.HOST
	my_id = 1
	host_address = "port %d" % port
	# The level already running becomes the hosted one.
	var scene := get_tree().current_scene
	if scene and scene.has_method("spawn_cart"):
		level_ready(scene)
	_log("Hosting on port %d. Others join with: join <this computer's address>" % port)
	_update_status()
	return true


func join(address: String, port: int = 0) -> bool:
	leave()
	port = port if port > 0 else default_port
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port, 2)
	if err != OK:
		_log("[color=#ff8a7a]Couldn't reach %s:%d (error %d).[/color]" % [address, port, err])
		return false
	peer = enet
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	role = Role.GUEST
	host_address = "%s:%d" % [address, port]
	_connecting_for = 0.0
	_log("Joining %s..." % host_address)
	_update_status()
	return true


## Ends the session. A guest goes back to playing the level on its own.
func leave() -> void:
	if role == Role.OFFLINE:
		return
	var was_guest := role == Role.GUEST
	peer.close()
	peer = null
	role = Role.OFFLINE
	my_id = 0
	for id in carts:
		if is_instance_valid(carts[id]) and (was_guest or id != 1):
			if not (was_guest and level and carts[id] == level.get("cart")):
				carts[id].queue_free()
	carts.clear()
	_guests.clear()
	_samples.clear()
	_welcomed = false
	_newest = -1.0
	_log("Left the multiplayer game.")
	_update_status()
	if was_guest and get_tree().current_scene:
		get_tree().reload_current_scene()


func is_host() -> bool:
	return role == Role.HOST


func is_guest() -> bool:
	return role == Role.GUEST


# ---------------------------------------------------------------- levels

## Called by main.gd when a level has finished _ready (its own cart is spawned). Lists the level's loose bodies,
## then the host spawns a cart per guest and tells guests to load the level; a guest freezes everything.
func level_ready(new_level: Node) -> void:
	if role == Role.OFFLINE:
		return
	level = new_level
	if not level.tree_exiting.is_connected(_on_level_exiting):
		level.tree_exiting.connect(_on_level_exiting.bind(level))
	var own: Node = level.get("cart")
	level_bodies.clear()
	for n in level.find_children("*", "RigidBody3D", true, false):
		if n.is_queued_for_deletion() or (own and own.is_ancestor_of(n)):
			continue
		level_bodies.append(n)
	level_bodies.sort_custom(func(a, b): return str(level.get_path_to(a)) < str(level.get_path_to(b)))
	carts.clear()
	_samples.clear()
	_refresh_cursor = 0
	if role == Role.HOST:
		level_serial = (level_serial + 1) % 256
		for id in _guests:
			_spawn_guest_cart(id)
		var b := NetProtocol.writer(NetProtocol.Msg.LEVEL)
		b.put_u8(level_serial)
		b.put_u16(level_bodies.size())
		NetProtocol.put_string(b, level.scene_file_path)
		for id in _guests:
			_send(id, b.data_array, true)
	else:
		if _expected_bodies >= 0 and _expected_bodies != level_bodies.size():
			_log("[color=#ff8a7a]This level doesn't match the host's (%d loose bodies here, %d there): different builds?[/color]" % [level_bodies.size(), _expected_bodies])
		for b in level_bodies:
			b.freeze = true
		for c in level.find_children("*", "", true, false):
			if c is ShoppingCart:
				c.make_puppet()
			elif c is CartBot:
				c.process_mode = Node.PROCESS_MODE_DISABLED
		if own:
			carts[my_id] = own
	_update_status()


func _on_level_exiting(old: Node) -> void:
	if level == old:
		level = null
		carts.clear()
		_samples.clear()
		level_bodies.clear()


## Host: a cart for guest `id`, in a row to the right of CartSpawn.
func _spawn_guest_cart(id: int, at := Vector3.INF, yaw := 0.0) -> void:
	if at == Vector3.INF:
		var spawn := level.get_node_or_null("CartSpawn") as Node3D
		var base := spawn.global_transform if spawn else Transform3D(Basis(), Vector3(2, 0, 0))
		at = base.origin + base.basis.z.normalized() * spawn_spacing * _guests[id].slot
		yaw = base.basis.get_euler().y
	if carts.has(id) and is_instance_valid(carts[id]):
		level.remove_child(carts[id])
		carts[id].free()
	var cart: ShoppingCart = CART_SCENE.instantiate()
	cart.name = "Player%d" % id
	cart.player_controlled = false
	cart.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.005, 0))
	level.add_child(cart)
	cart.driver = self
	carts[id] = cart


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	if peer == null:   # polling can end the session (the host went away)
		return
	while peer and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var packet := peer.get_packet()
		stats.packets_in += 1
		if packet.size() > 0:
			if role == Role.HOST:
				_host_receive(from, packet)
			else:
				_guest_receive(packet)
	if role == Role.HOST:
		_host_tick(delta)
	elif role == Role.GUEST:
		_guest_tick(delta)


func _send(to: int, data: PackedByteArray, reliable: bool) -> void:
	peer.set_target_peer(to)
	peer.transfer_channel = 0 if reliable else 1
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	peer.put_packet(data)


func _on_peer_connected(id: int) -> void:
	if role == Role.GUEST and id == 1:
		var b := NetProtocol.writer(NetProtocol.Msg.HELLO)
		b.put_u16(NetProtocol.VERSION)
		_send(1, b.data_array, true)


func _on_peer_disconnected(id: int) -> void:
	if role == Role.GUEST:
		if id == 1:
			_log("[color=#ffc66d]The host has gone.[/color]")
			leave.call_deferred()
		return
	if _guests.erase(id):
		if carts.has(id) and is_instance_valid(carts[id]):
			carts[id].queue_free()
		carts.erase(id)
		var b := NetProtocol.writer(NetProtocol.Msg.LEFT)
		b.put_u32(id)
		for g in _guests:
			_send(g, b.data_array, true)
		_log("Player %d left." % id)
		_update_status()


# ---------------------------------------------------------------- host

func _host_receive(from: int, packet: PackedByteArray) -> void:
	var b := NetProtocol.reader(packet)
	match b.get_u8():
		NetProtocol.Msg.HELLO:
			var version := b.get_u16()
			if version != NetProtocol.VERSION:
				var r := NetProtocol.writer(NetProtocol.Msg.REJECT)
				NetProtocol.put_string(r, "The host runs a different version (%d, yours %d)." % [NetProtocol.VERSION, version])
				_send(from, r.data_array, true)
				peer.disconnect_peer(from)
				return
			var used := _guests.values().map(func(g): return g.slot)
			var slot := 1
			while slot in used:
				slot += 1
			_guests[from] = {"keys": 0, "slot": slot, "serial": -1}
			# ENet slows unreliable traffic to a peer that stalls (a guest loading a level) and is slow to speed back
			# up; snapshots replace each other, so keep sending them at full rate.
			if peer is ENetMultiplayerPeer:
				(peer as ENetMultiplayerPeer).get_peer(from).throttle_configure(1000, 32, 0)
			var w := NetProtocol.writer(NetProtocol.Msg.WELCOME)
			w.put_u16(NetProtocol.VERSION)
			w.put_u32(from)
			w.put_u8(level_serial)
			w.put_u16(level_bodies.size())
			NetProtocol.put_string(w, level.scene_file_path if level else "")
			_send(from, w.data_array, true)
			if level:
				_spawn_guest_cart(from)
			_log("Player %d joined." % from)
			_update_status()
		NetProtocol.Msg.INPUT:
			if _guests.has(from):
				_guests[from].serial = b.get_u8()
				_guests[from].keys = b.get_u8()
				stats.inputs_received += 1
		NetProtocol.Msg.RESET:
			if _guests.has(from) and level and carts.has(from) and is_instance_valid(carts[from]):
				var old: ShoppingCart = carts[from]
				var p := old.cart_origin()
				_spawn_guest_cart(from, Vector3(p.x, p.y + 0.05, p.z), old.heading())


func _host_tick(delta: float) -> void:
	_tick += 1
	if level == null or not is_instance_valid(level):
		return
	# Guests hold their carts' bars through `controls`, as a bot does.
	for id in _guests:
		var cart: ShoppingCart = carts.get(id)
		if cart == null or not is_instance_valid(cart):
			continue
		var keys: int = _guests[id].keys
		for i in ShoppingCart.ACTIONS.size():
			cart.controls[ShoppingCart.ACTIONS[i]] = keys & (1 << i) != 0
	_snap_clock += delta
	if _snap_clock < 1.0 / snapshot_rate or _guests.is_empty():
		return
	_snap_clock = fmod(_snap_clock, 1.0 / snapshot_rate)
	# Only to guests that have loaded this level (their keys come with its serial).
	var ready := _guests.keys().filter(func(id): return _guests[id].serial == level_serial)
	if ready.is_empty():
		return
	for packet in _build_snapshot():
		for id in ready:
			_send(id, packet, false)
	stats.snapshots_sent += 1


## The snapshot for this tick, as one or more packets.
func _build_snapshot() -> Array[PackedByteArray]:
	var cart_blocks: Array[PackedByteArray] = []
	var all_carts := {1: level.get("cart")}
	all_carts.merge(carts)
	for id in all_carts:
		var cart: ShoppingCart = all_carts[id]
		if cart == null or not is_instance_valid(cart) or not cart.is_inside_tree():
			continue
		var b := StreamPeerBuffer.new()
		b.put_u32(id)
		b.put_16(clampi(roundi(cart.hand_power.L), -32768, 32767))
		b.put_16(clampi(roundi(cart.hand_power.R), -32768, 32767))
		b.put_u8(1 if cart.fallen else 0)
		var v := cart.frame_velocity()
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
		b.put_float(cart.frame_spin())
		var bodies := cart.net_bodies()
		b.put_u8(bodies.size())
		for body in bodies:
			NetProtocol.put_pose(b, body.global_transform)
		cart_blocks.append(b.data_array)
	# Level bodies: everything moving, plus a few resting ones in turn.
	var picked := {}
	for i in level_bodies.size():
		var body := level_bodies[i]
		if is_instance_valid(body) and not body.sleeping and not body.freeze:
			picked[i] = true
	for k in mini(refresh_per_snapshot, level_bodies.size()):
		picked[_refresh_cursor] = true
		_refresh_cursor = (_refresh_cursor + 1) % level_bodies.size()
	var body_blocks: Array[PackedByteArray] = []
	for i in picked:
		if not is_instance_valid(level_bodies[i]):
			continue
		var b := StreamPeerBuffer.new()
		b.put_u16(i)
		NetProtocol.put_pose(b, level_bodies[i].global_transform)
		body_blocks.append(b.data_array)
	# Pack greedily: carts first, then bodies; every packet is a complete SNAPSHOT.
	var packets: Array[PackedByteArray] = []
	var ci := 0
	var bi := 0
	while ci < cart_blocks.size() or bi < body_blocks.size() or packets.is_empty():
		var size := 1 + 1 + 4 + 1 + 2
		var carts_in: Array[PackedByteArray] = []
		while ci < cart_blocks.size() and (carts_in.is_empty() or size + cart_blocks[ci].size() <= max_packet):
			size += cart_blocks[ci].size()
			carts_in.append(cart_blocks[ci])
			ci += 1
		var bodies_in: Array[PackedByteArray] = []
		while bi < body_blocks.size() and size + body_blocks[bi].size() <= max_packet:
			size += body_blocks[bi].size()
			bodies_in.append(body_blocks[bi])
			bi += 1
		var p := NetProtocol.writer(NetProtocol.Msg.SNAPSHOT)
		p.put_u8(level_serial)
		p.put_u32(_tick)
		p.put_u8(carts_in.size())
		for c in carts_in:
			p.put_data(c)
		p.put_u16(bodies_in.size())
		for c in bodies_in:
			p.put_data(c)
		packets.append(p.data_array)
	return packets


# ---------------------------------------------------------------- guest

func _guest_receive(packet: PackedByteArray) -> void:
	var b := NetProtocol.reader(packet)
	match b.get_u8():
		NetProtocol.Msg.WELCOME:
			var version := b.get_u16()
			my_id = b.get_u32()
			_welcomed = true
			_log("Joined %s as player %d." % [host_address, my_id])
			_load_level(b.get_u8(), b.get_u16(), NetProtocol.get_string(b))
			if version != NetProtocol.VERSION:
				_log("[color=#ffc66d]Host version %d, ours %d.[/color]" % [version, NetProtocol.VERSION])
		NetProtocol.Msg.REJECT:
			_log("[color=#ff8a7a]The host turned us away: %s[/color]" % NetProtocol.get_string(b))
			leave.call_deferred()
		NetProtocol.Msg.LEVEL:
			_load_level(b.get_u8(), b.get_u16(), NetProtocol.get_string(b))
		NetProtocol.Msg.LEFT:
			var id := b.get_u32()
			if carts.has(id) and is_instance_valid(carts[id]) and id != my_id:
				carts[id].queue_free()
			carts.erase(id)
			_update_status()
		NetProtocol.Msg.SNAPSHOT:
			_read_snapshot(b)


func _load_level(serial: int, bodies: int, path: String) -> void:
	level_serial = serial
	_expected_bodies = bodies
	level = null
	carts.clear()
	_samples.clear()
	_newest = -1.0
	if path == "" or not ResourceLoader.exists(path):
		_log("[color=#ff8a7a]The host's level %s isn't in this build.[/color]" % path)
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(path)


func _read_snapshot(b: StreamPeerBuffer) -> void:
	if b.get_u8() != level_serial or level == null or not is_instance_valid(level):
		return
	var t := float(b.get_u32()) / Engine.physics_ticks_per_second
	if t > _newest:
		stats.snapshots_received += 1
		if _newest < 0.0:
			_render_time = t - interp_delay
		_newest = t
	for c in b.get_u8():
		var id := b.get_u32()
		var cart := _puppet(id)
		cart.hand_power.L = b.get_16()
		cart.hand_power.R = b.get_16()
		cart.fallen = b.get_u8() & 1 != 0
		cart.puppet_velocity = Vector3(b.get_float(), b.get_float(), b.get_float())
		cart.puppet_spin = b.get_float()
		var bodies := cart.net_bodies()
		for i in b.get_u8():
			var pose := NetProtocol.get_pose(b)
			if i < bodies.size():
				_add_sample(bodies[i], t, pose)
	for k in b.get_u16():
		var i := b.get_u16()
		var pose := NetProtocol.get_pose(b)
		if i < level_bodies.size() and is_instance_valid(level_bodies[i]):
			_add_sample(level_bodies[i], t, pose)


## The cart shown for player `id`, made on first sight.
func _puppet(id: int) -> ShoppingCart:
	var cart: ShoppingCart = carts.get(id)
	if cart and is_instance_valid(cart):
		return cart
	cart = CART_SCENE.instantiate()
	cart.name = "Player%d" % id
	cart.player_controlled = false
	level.add_child(cart)
	cart.make_puppet()
	carts[id] = cart
	_update_status()
	return cart


func _add_sample(body: RigidBody3D, t: float, pose: Array) -> void:
	var s: Array = _samples.get(body, [])
	if s.is_empty():
		_samples[body] = [t, pose[0], pose[1], t, pose[0], pose[1]]
	elif t > s[3]:
		_samples[body] = [s[3], s[4], s[5], t, pose[0], pose[1]]


func _guest_tick(delta: float) -> void:
	if not _welcomed:
		_connecting_for += delta
		if _connecting_for > connect_timeout:
			_log("[color=#ff8a7a]No answer from %s.[/color]" % host_address)
			leave()
		return
	# Our keys, to the host: whenever they change, and input_rate times a second anyway (packets can be lost).
	var keys := 0
	var console := get_node_or_null("/root/Console")
	if not (console and console.is_open()):
		for i in ShoppingCart.ACTIONS.size():
			if Input.is_action_pressed(ShoppingCart.ACTIONS[i]):
				keys |= 1 << i
	_input_clock += delta
	if level == null:
		return   # still loading: no keys, so the host holds its snapshots until we're ready
	if keys != _keys_sent or _input_clock >= 1.0 / input_rate:
		var b := NetProtocol.writer(NetProtocol.Msg.INPUT)
		b.put_u8(level_serial)
		b.put_u8(keys)
		_send(1, b.data_array, false)
		_keys_sent = keys
		_input_clock = 0.0
	if _newest < 0.0:
		return
	# Show the world interp_delay behind the newest snapshot; drift back toward that if packets bunch up.
	_render_time += delta
	var target := _newest - interp_delay
	if absf(_render_time - target) > 0.25:
		_render_time = target
	else:
		_render_time = lerpf(_render_time, target, 0.05)
	for body in _samples:
		if not is_instance_valid(body):
			continue
		var s: Array = _samples[body]
		var w := 1.0
		if s[3] > s[0]:
			w = clampf((_render_time - s[0]) / (s[3] - s[0]), 0.0, 1.0)
		body.global_transform = Transform3D(Basis((s[2] as Quaternion).slerp(s[5], w)), (s[1] as Vector3).lerp(s[4], w))


## A guest's reset key: the host puts the guest's cart back on its wheels.
func request_reset() -> void:
	if role == Role.GUEST and _welcomed:
		_send(1, NetProtocol.writer(NetProtocol.Msg.RESET).data_array, true)


# ---------------------------------------------------------------- status

func status_text() -> String:
	match role:
		Role.HOST:
			return "Hosting on %s · %s" % [host_address, _players(_guests.size() + 1)]
		Role.GUEST:
			if not _welcomed:
				return "Joining %s..." % host_address
			return "Joined %s · %s" % [host_address, _players(maxi(carts.size(), 1))]
	return "Offline"


func _players(n: int) -> String:
	return "1 player" if n == 1 else "%d players" % n


func _update_status() -> void:
	if _overlay:
		_overlay.visible = role != Role.OFFLINE
		_status.text = status_text()
	status_changed.emit(status_text())


func _log(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print_rich(text)


func _cmd_host(args: PackedStringArray) -> void:
	host(int(args[0]) if args.size() > 0 else 0)


func _cmd_join(args: PackedStringArray) -> void:
	if args.is_empty():
		_log("Usage: join <address>[:port], e.g. join 127.0.0.1")
		return
	_join_address(args[0])


func _join_address(text: String) -> void:
	var parts := text.rsplit(":", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		join(parts[0], int(parts[1]))
	else:
		join(text)
