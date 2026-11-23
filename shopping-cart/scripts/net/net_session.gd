class_name NetSession
extends Node
## Multiplayer, host-authoritative: one player hosts, and the host's physics is the only physics. The `Net`
## autoload (scenes/net/net_session.tscn). Two ways to connect (docs/MULTIPLAYER.md):
##  - Online, by join code: the host registers with the rendezvous service (services/rendezvous, a Cloudflare
##    Worker; `rendezvous_url`) and gets an 8-letter code; players connect over WebRTC (webrtc_link.gd), straight
##    to each other or through a TURN relay. Public games are listed for anyone to browse.
##  - LAN, by address: ENet straight to the host's IP and port (no service needed).
##
## Host: plays as usual. Each guest gets a cart (cart.tscn) beside the level's CartSpawn, driven through the cart's
## `controls`, exactly like a bot cart, from the keys the guest holds (INPUT packets). Every tick it sends
## snapshots of every moving body: all player carts (whole rigs and groceries) and the level's loose bodies (boxes,
## spare and bot carts). Resting bodies are resent a few at a time, so a lost packet can't leave one stale for long.
## Guest: loads the host's level, freezes every body in it and shows the host's world: each body is moved between
## the two snapshots around (newest - interp_delay). Bot carts' bots don't run on a guest. Its own keys go to the
## host, and its own cart is predicted: it drives here at once with real physics (passing through the frozen bodies,
## which the host's cart pushes), and each snapshot nudges it toward where the host has it (see _correct_own).
##
## Start it from the Multiplayer menu (M), the console (`online`, `host`, `join <code or address>`, `games`,
## `leave`, `net`) or the command line:
##   godot --path shopping-cart -- --online           (unlisted: --online=unlisted; name: --name=Zack's store)
##   godot --path shopping-cart -- --join=ABCD-EFGH   (a join code)
##   godot --path shopping-cart -- --host             (LAN; port: --host=24601)
##   godot --path shopping-cart -- --join=127.0.0.1   (LAN; or --join=192.168.1.20:24601)
##   add --rendezvous=<url> to use another rendezvous service (default: rendezvous_url)
## The transport is any MultiplayerPeer, polled directly with our own packets (net_protocol.gd), not Godot's RPCs,
## so the browser game can speak the same bytes.

signal status_changed(text: String)
signal hosted_online(code: String)       ## the join code to share
signal games_listed(games: Array)        ## answer to list_games(): [{code, name, level, players, max_players}]
signal message(text: String)             ## something to tell the player (also in the console), BBCode

const CART_SCENE := preload("res://scenes/cart/cart.tscn")

@export var default_port := 24601
@export var max_guests := 7
@export var snapshot_rate := 30.0         ## snapshots a second the host sends
@export var input_rate := 30.0            ## a guest resends its keys this often even when nothing changes
@export var interp_delay := 0.08          ## s a guest shows the world behind the newest snapshot
@export var refresh_per_snapshot := 24    ## resting bodies resent with each snapshot
@export var spawn_spacing := 1.2          ## m between guest carts, in a row to the right of CartSpawn
@export var max_packet := 1100            ## bytes: snapshots are split to stay under one network packet
@export var connect_timeout := 20.0       ## s a guest waits to reach the host (WebRTC needs a few round trips)
@export_group("Guest's own cart")
@export var correction_time := 0.2        ## s over which a guest eases its own cart onto the host's (prediction error)
@export var snap_distance := 2.5          ## m: an error bigger than this (a reset, a race grid) moves the cart at once
@export var history_length := 2.0         ## s of its own cart's poses a guest keeps, to compare with late snapshots
@export_group("Testing")
@export var test_latency := 0.0           ## s added to every packet this machine sends, to try a slow connection
@export_group("Online")
## The rendezvous service (services/rendezvous), deployed on zack's Cloudflare account. For a local one
## (`npm run dev` there): --rendezvous=http://127.0.0.1:8787 on the command line.
@export var rendezvous_url := "https://shopping-cart-rendezvous.shopping-cart-rendezvous.workers.dev"
@export var game_name := "Shopping cart"   ## shown in the game list
@export var listed := true                 ## public games appear in the game list; unlisted ones only by code
@export var heartbeat_interval := 30.0     ## s between "still here" messages that keep a listing alive
@export_group("")

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
var stats := {"snapshots_sent": 0, "snapshots_received": 0, "inputs_received": 0, "packets_in": 0, "chunk_poses": 0,
	"own_error": 0.0}   ## own_error: the biggest prediction error a guest has had to ease out, m

@onready var _overlay: CanvasLayer = $Overlay
@onready var _status: Label = %Status
@onready var _http: HTTPRequest = $Rendezvous
var join_code := ""          ## the online game's code, host or guest
var _heartbeat_clock := 0.0
var _http_busy := false

# host
var _guests := {}            ## id -> {"keys": int, "slot": int} for guests that said HELLO
var _tick := 0
var _snap_clock := 0.0
var _refresh_cursor := 0
var _chunk_cursor := 0
var _streamers: Array = []   ## the level's ChunkStreamers (the endless sandbox has one)
# guest
var _samples := {}           ## RigidBody3D -> [t0, pos0, rot0, t1, pos1, rot1]
var _newest := -1.0          ## host time (s) of the newest snapshot
var _render_time := 0.0      ## host time (s) the guest is showing
var _keys_sent := -1
var _input_clock := 0.0
var _welcomed := false
var _connecting_for := 0.0
var _expected_bodies := -1
var _own: ShoppingCart = null  ## our own cart, predicted here (the level's `cart`)
var _own_live := false         ## it has been put where the host has it and drives (until then: frozen, locked)
var _own_tick := -1            ## host tick of the snapshot that last corrected it
var _history: Array = []       ## [local ms, frame position, frame rotation] each tick, oldest first
var _err_pos := Vector3.ZERO   ## what is left to ease out of our cart's error
var _err_rot := Quaternion.IDENTITY
var _outbox: Array = []        ## test_latency: [due ms, to, data, reliable]


func _ready() -> void:
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("add_command"):
		console.add_command("host", _cmd_host, "host a multiplayer game: host [port]")
		console.add_command("join", _cmd_join, "join a game: join <address>[:port]")
		console.add_command("leave", func(_a): leave(), "leave or stop the multiplayer game")
		console.add_command("net", func(_a): _log(status_text()), "show the multiplayer status")
		console.add_command("online", _cmd_online, "host an online game with a join code: online [unlisted] [name]")
		console.add_command("games", func(_a): _cmd_games(), "list public online games")
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--rendezvous="):
			rendezvous_url = arg.get_slice("=", 1)
		elif arg.begins_with("--name="):
			game_name = arg.get_slice("=", 1)
	for arg in args:
		if arg == "--online" or arg.begins_with("--online="):
			if arg.get_slice("=", 1) == "unlisted":
				listed = false
			host_online.call_deferred()
		elif arg == "--host" or arg.begins_with("--host="):
			host.call_deferred(int(arg.get_slice("=", 1)) if "=" in arg else default_port)
		elif arg.begins_with("--join="):
			_join_address.call_deferred(arg.get_slice("=", 1))
	_update_status()


# ---------------------------------------------------------------- starting and stopping

## LAN: host on a UDP port; others join by this computer's address.
func host(port: int = 0) -> bool:
	leave()
	port = port if port > 0 else default_port
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_guests, 2)
	if err != OK:
		_log("[color=#ff8a7a]Couldn't host on port %d (error %d).[/color]" % [port, err])
		return false
	_start_host(enet, "port %d" % port)
	_log("Hosting on port %d. Others join with: join <this computer's address>" % port)
	return true


## Online: registers with the rendezvous service and hosts under a join code (hosted_online gives the code).
## Returns the code, or "" if the service said no or couldn't be reached.
func host_online() -> String:
	leave()
	_log("Asking %s for a join code..." % rendezvous_url)
	var body := {"name": game_name, "level": _level_key(), "max_players": max_guests + 1, "public": listed,
		"protocol": NetProtocol.VERSION}
	var res: Array = await _request("/host", HTTPClient.METHOD_POST, JSON.stringify(body))
	if res[0] != 200 or not res[1] is Dictionary or not res[1].has("code"):
		var why: String = res[1].get("error", "") if res[1] is Dictionary else ""
		_log("[color=#ff8a7a]Couldn't host online: %s[/color]" % (why if why else "no answer from %s" % rendezvous_url))
		return ""
	var code: String = res[1].code
	var link := WebRtcLink.hosting(_ws_url("/room/%s/host" % code), res[1].token, code)
	join_code = code
	_heartbeat_clock = 0.0
	_start_host(link, "code " + pretty_code(code))
	_log("Hosting online. Join code: [b]%s[/b]%s" % [pretty_code(code), "" if listed else " (unlisted)"])
	hosted_online.emit(code)
	return code


func _start_host(transport: MultiplayerPeer, address: String) -> void:
	peer = transport
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if peer is WebRtcLink:
		peer.signal_message.connect(func(_msg): _update_status())
	role = Role.HOST
	my_id = 1
	host_address = address
	# The level already running becomes the hosted one.
	var scene := get_tree().current_scene
	if scene and scene.has_method("spawn_cart"):
		level_ready(scene)
	_update_status()


## LAN: joins the host at `address`.
func join(address: String, port: int = 0) -> bool:
	leave()
	port = port if port > 0 else default_port
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port, 2)
	if err != OK:
		_log("[color=#ff8a7a]Couldn't reach %s:%d (error %d).[/color]" % [address, port, err])
		return false
	_start_guest(enet, "%s:%d" % [address, port])
	return true


## Online: joins the game with this join code (dashes and case don't matter).
func join_online(code: String) -> bool:
	leave()
	code = code.to_upper().replace("-", "").strip_edges()
	if not is_join_code(code):
		_log("[color=#ff8a7a]'%s' isn't a join code (8 letters and numbers).[/color]" % code)
		return false
	join_code = code
	_start_guest(WebRtcLink.joining(_ws_url("/room/%s/join?protocol=%d" % [code, NetProtocol.VERSION]), code),
		"code " + pretty_code(code))
	return true


func _start_guest(transport: MultiplayerPeer, address: String) -> void:
	peer = transport
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if peer is WebRtcLink:
		peer.signal_message.connect(func(_msg): _update_status())
	role = Role.GUEST
	host_address = address
	_connecting_for = 0.0
	_log("Joining %s..." % host_address)
	_update_status()


## Public online games (also sent as games_listed). Each: {code, name, level, players, max_players, protocol}.
func list_games() -> Array:
	var res: Array = await _request("/games?protocol=%d" % NetProtocol.VERSION, HTTPClient.METHOD_GET, "")
	var games: Array = res[1].get("games", []) if res[0] == 200 and res[1] is Dictionary else []
	if res[0] != 200:
		_log("[color=#ff8a7a]Couldn't get the game list from %s.[/color]" % rendezvous_url)
	games_listed.emit(games)
	return games


## A join code: 8 of the letters and digits the service uses (no I, L, O, 0 or 1).
static func is_join_code(text: String) -> bool:
	var code := text.to_upper().replace("-", "")
	if code.length() != 8:
		return false
	for c in code:
		if not c in "ABCDEFGHJKMNPQRSTUVWXYZ23456789":
			return false
	return true


static func pretty_code(code: String) -> String:
	return code.substr(0, 4) + "-" + code.substr(4)


## [status code, parsed JSON or null]. One request at a time; a second waits for the first.
func _request(path: String, method: int, body: String) -> Array:
	while _http_busy:
		await get_tree().process_frame
	_http_busy = true
	var err := _http.request(rendezvous_url.rstrip("/") + path, ["Content-Type: application/json"], method, body)
	if err != OK:
		_http_busy = false
		return [0, null]
	var r: Array = await _http.request_completed
	_http_busy = false
	return [r[1], JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())]


func _ws_url(path: String) -> String:
	return rendezvous_url.rstrip("/").replace("https://", "wss://").replace("http://", "ws://") + path


## The level's console fast-travel key (what the rendezvous service lists), "sandbox" if it has none.
func _level_key() -> String:
	var console := get_node_or_null("/root/Console")
	var scene := get_tree().current_scene
	if console and scene:
		for key in console.destinations:
			if console.destinations[key] == scene.scene_file_path:
				return key
	return "sandbox"


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
	_own = null
	_outbox.clear()
	join_code = ""
	if level and is_instance_valid(level):
		_show_flag(level.get("cart"), -1)
	_log("Left the multiplayer game.")
	_update_status()
	if was_guest and get_tree().current_scene:
		get_tree().reload_current_scene()


## Every player's cart flies its flag (scenes/cart/flag.tscn) in its player slot's colour; slot -1 hides it.
static func _show_flag(cart: Node, slot: int) -> void:
	var flag := cart.get_node_or_null("Frame/Flag") as CartFlag if cart and is_instance_valid(cart) else null
	if flag == null:
		return
	if slot < 0:
		flag.visible = false
	elif not flag.visible or flag.color != slot:
		flag.color = slot
		flag.visible = true


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
	# Streamed terrain (the endless sandbox): its chunks come and go, so their loose bodies are sent by square.
	_streamers.clear()
	for n in level.find_children("*", "", true, false):
		if n is ChunkStreamer:
			_streamers.append(n)
			if role == Role.GUEST and not n.chunk_loaded.is_connected(_on_chunk_loaded):
				n.chunk_loaded.connect(_on_chunk_loaded)
	level_bodies.clear()
	for n in level.find_children("*", "RigidBody3D", true, false):
		if n.is_queued_for_deletion() or (own and own.is_ancestor_of(n)):
			continue
		if _streamers.any(func(st): return st.is_ancestor_of(n)):
			continue
		level_bodies.append(n)
	level_bodies.sort_custom(func(a, b): return str(level.get_path_to(a)) < str(level.get_path_to(b)))
	carts.clear()
	_samples.clear()
	_refresh_cursor = 0
	_chunk_cursor = 0
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
		_freeze_all(level)
		for st in _streamers:
			for cell in st.loaded:
				_freeze_all(st.loaded[cell])
		if own:
			carts[my_id] = own
			_own = own
			_own_live = false
			_own_tick = -1
			_history.clear()
			_err_pos = Vector3.ZERO
			_err_rot = Quaternion.IDENTITY
			# Held still until the first snapshot says where the host has it.
			own.locked = true
			for b in own.net_bodies():
				b.freeze = true
			_ignore_for_own(level_bodies)
			for st in _streamers:
				for cell in st.loaded:
					_ignore_for_own(_chunk_bodies(st.loaded[cell]))
	_update_status()


## Guest: everything under `root` only shows the host's world: bodies frozen, carts puppets, bots off.
func _freeze_all(root: Node) -> void:
	for c in root.find_children("*", "", true, false):
		if c is ShoppingCart and c == level.get("cart"):
			continue   # our own: predicted (level_ready)
		if c is ShoppingCart:
			c.make_puppet()
		elif c is CartBot:
			c.process_mode = Node.PROCESS_MODE_DISABLED
		elif c is RigidBody3D:
			c.freeze = true


func _on_chunk_loaded(_cell: Vector2i, chunk: Node3D) -> void:
	if role == Role.GUEST:
		_freeze_all(chunk)
		_ignore_for_own(_chunk_bodies(chunk))


## Guest: our predicted cart passes through `bodies` (frozen copies of the host's): the host's cart pushes the
## real ones, and the correction brings ours along.
func _ignore_for_own(bodies: Array) -> void:
	if _own == null or not is_instance_valid(_own):
		return
	var mine := _own.net_bodies()
	for b in bodies:
		if is_instance_valid(b) and not mine.has(b):
			for m in mine:
				m.add_collision_exception_with(b)


## A chunk's loose bodies, in the same order on every machine.
func _chunk_bodies(chunk: Node) -> Array:
	if not chunk.has_meta("net_bodies"):
		var list := chunk.find_children("*", "RigidBody3D", true, false).filter(func(b): return not b.is_queued_for_deletion())
		list.sort_custom(func(a, b): return str(chunk.get_path_to(a)) < str(chunk.get_path_to(b)))
		chunk.set_meta("net_bodies", list)
	return chunk.get_meta("net_bodies")


func _on_level_exiting(old: Node) -> void:
	if level == old:
		level = null
		carts.clear()
		_samples.clear()
		level_bodies.clear()
		_own = null


## Host: a cart for guest `id`, in a row to the right of CartSpawn.
func _spawn_guest_cart(id: int, at := Vector3.INF, yaw := 0.0) -> void:
	if at == Vector3.INF:
		# The level's PlayerSpawns markers (Spawn1, Spawn2... one per guest slot), else a row beside CartSpawn.
		var slot: int = _guests[id].slot
		var marks := level.get_node_or_null("PlayerSpawns")
		var mark := marks.get_child((slot - 1) % marks.get_child_count()) as Node3D if marks and marks.get_child_count() > 0 else null
		if mark:
			at = mark.global_position
			yaw = mark.global_basis.get_euler().y
		else:
			var spawn := level.get_node_or_null("CartSpawn") as Node3D
			var base := spawn.global_transform if spawn else Transform3D(Basis(), Vector3(2, 0, 0))
			at = base.origin + base.basis.z.normalized() * spawn_spacing * slot
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


## Host: puts guest `id`'s cart (a fresh one) at `at`, facing `yaw` (a race's starting grid).
func place_guest_cart(id: int, at: Vector3, yaw: float) -> void:
	if role == Role.HOST and _guests.has(id) and level:
		_spawn_guest_cart(id, at, yaw)


## Host: the guests in the game, in the order they joined (by slot).
func guest_ids() -> Array:
	var ids := _guests.keys()
	ids.sort_custom(func(a, b): return _guests[a].slot < _guests[b].slot)
	return ids


## A guest's name as players see it: Player 2, Player 3... (the host is Player 1).
func guest_name(id: int) -> String:
	return "Player %d" % (_guests[id].slot + 1) if _guests.has(id) else "Player"


## Host: whether every guest has loaded the level being played (they send its serial with their keys).
func guests_loaded() -> bool:
	return _guests.values().all(func(g): return g.serial == level_serial)


## Host: a reliable message to every guest (a race update, scripts/race/race.gd).
func send_to_guests(data: PackedByteArray) -> void:
	if role != Role.HOST:
		return
	for id in _guests:
		_send(id, data, true)


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	if peer == null:
		return
	while not _outbox.is_empty() and _outbox[0][0] <= Time.get_ticks_msec():
		var o: Array = _outbox.pop_front()
		_put(o[1], o[2], o[3])
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
	if test_latency > 0.0:
		_outbox.append([Time.get_ticks_msec() + test_latency * 1000.0, to, data, reliable])
		return
	_put(to, data, reliable)


func _put(to: int, data: PackedByteArray, reliable: bool) -> void:
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
			_guests[from] = {"keys": 0, "slot": slot, "serial": -1, "stamp": 0, "stamp_at": 0}
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
				_guests[from].stamp = b.get_u16()
				_guests[from].stamp_at = Time.get_ticks_msec()
				stats.inputs_received += 1
		NetProtocol.Msg.RESET:
			if _guests.has(from) and level and carts.has(from) and is_instance_valid(carts[from]):
				var old: ShoppingCart = carts[from]
				var p := old.cart_origin()
				_spawn_guest_cart(from, Vector3(p.x, p.y + 0.05, p.z), old.heading())


func _host_tick(delta: float) -> void:
	_tick += 1
	if peer is WebRtcLink:
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_log("[color=#ff8a7a]Stopped hosting: %s[/color]" % peer.error_text)
			leave()
			return
		_heartbeat_clock += delta
		if _heartbeat_clock >= heartbeat_interval:
			_heartbeat_clock = 0.0
			peer.heartbeat()
	if level == null or not is_instance_valid(level):
		return
	_show_flag(level.get("cart"), 0)   # the host's own flag flies from the start, before anyone joins
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
		var slot: int = 0 if id == 1 else _guests.get(id, {}).get("slot", 0)
		_show_flag(cart, slot)
		b.put_u8((1 if cart.fallen else 0) | (slot & 7) << 1 | (16 if cart.locked else 0))
		# For a guest's own cart: its newest keys' stamp, and how long ago they came (prediction, _correct_own).
		var g: Dictionary = _guests.get(id, {})
		b.put_u16(g.get("stamp", 0))
		b.put_u16(mini(Time.get_ticks_msec() - g.get("stamp_at", 0), 65535) if g else 0)
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
	# Loose bodies in streamed chunks, by square: the same rule (moving, plus some resting ones in turn).
	var chunk_entries := []   # [cell, index, body]
	for st in _streamers:
		for cell in st.loaded:
			var list := _chunk_bodies(st.loaded[cell])
			for i in list.size():
				chunk_entries.append([cell, i, list[i]])
	var chunk_picked := {}
	for k in chunk_entries.size():
		var body: RigidBody3D = chunk_entries[k][2]
		if is_instance_valid(body) and not body.sleeping and not body.freeze:
			chunk_picked[k] = true
	for k in mini(refresh_per_snapshot, chunk_entries.size()):
		_chunk_cursor = (_chunk_cursor + 1) % chunk_entries.size()
		chunk_picked[_chunk_cursor] = true
	var chunk_blocks: Array[PackedByteArray] = []
	for k in chunk_picked:
		var e: Array = chunk_entries[k]
		if not is_instance_valid(e[2]):
			continue
		var b := StreamPeerBuffer.new()
		b.put_16(e[0].x)
		b.put_16(e[0].y)
		b.put_u16(e[1])
		NetProtocol.put_pose(b, (e[2] as RigidBody3D).global_transform)
		chunk_blocks.append(b.data_array)
	# Pack greedily: carts, then level bodies, then chunk bodies; every packet is a complete SNAPSHOT.
	var packets: Array[PackedByteArray] = []
	var lists := [cart_blocks, body_blocks, chunk_blocks]
	var at := [0, 0, 0]
	while at[0] < cart_blocks.size() or at[1] < body_blocks.size() or at[2] < chunk_blocks.size() or packets.is_empty():
		var size := 1 + 1 + 4 + 1 + 2 + 2
		var taken := [[], [], []]
		for l in 3:
			var blocks: Array[PackedByteArray] = lists[l]
			while at[l] < blocks.size() and (size + blocks[at[l]].size() <= max_packet or (l == 0 and taken[0].is_empty())):
				size += blocks[at[l]].size()
				taken[l].append(blocks[at[l]])
				at[l] += 1
		var p := NetProtocol.writer(NetProtocol.Msg.SNAPSHOT)
		p.put_u8(level_serial)
		p.put_u32(_tick)
		p.put_u8(taken[0].size())
		for c in taken[0]:
			p.put_data(c)
		p.put_u16(taken[1].size())
		for c in taken[1]:
			p.put_data(c)
		p.put_u16(taken[2].size())
		for c in taken[2]:
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
		NetProtocol.Msg.RACE:
			if b.get_u8() == level_serial and level and is_instance_valid(level):
				var race := get_tree().get_first_node_in_group("race")
				if race and race.has_method("apply_state"):
					race.apply_state(b)
		NetProtocol.Msg.SWEEP:
			if b.get_u8() == level_serial and level and is_instance_valid(level):
				var sweep := get_tree().get_first_node_in_group("sweep")
				if sweep and sweep.has_method("apply_state"):
					sweep.apply_state(b)
		NetProtocol.Msg.BALL:
			if b.get_u8() == level_serial and level and is_instance_valid(level):
				var game := get_tree().get_first_node_in_group("cart_ball")
				if game and game.has_method("apply_state"):
					game.apply_state(b)


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
	var tick := roundi(t * Engine.physics_ticks_per_second)
	for c in b.get_u8():
		var id := b.get_u32()
		var cart := _puppet(id)
		var power := Vector2(b.get_16(), b.get_16())
		var flags := b.get_u8()
		var stamp := b.get_u16()
		var held := b.get_u16()
		_show_flag(cart, flags >> 1 & 7)
		var velocity := Vector3(b.get_float(), b.get_float(), b.get_float())
		var spin := b.get_float()
		var poses := []
		for i in b.get_u8():
			poses.append(NetProtocol.get_pose(b))
		if cart == _own:
			if tick > _own_tick:
				_own_tick = tick
				cart.locked = flags & 16 != 0
				_correct_own(poses, velocity, stamp, held)
			continue
		cart.hand_power.L = power.x
		cart.hand_power.R = power.y
		cart.fallen = flags & 1 != 0
		cart.puppet_velocity = velocity
		cart.puppet_spin = spin
		var bodies := cart.net_bodies()
		for i in mini(poses.size(), bodies.size()):
			_add_sample(bodies[i], t, poses[i])
	for k in b.get_u16():
		var i := b.get_u16()
		var pose := NetProtocol.get_pose(b)
		if i < level_bodies.size() and is_instance_valid(level_bodies[i]):
			_add_sample(level_bodies[i], t, pose)
	for k in b.get_u16():
		var cell := Vector2i(b.get_16(), b.get_16())
		var i := b.get_u16()
		var pose := NetProtocol.get_pose(b)
		for st in _streamers:
			var chunk: Node = st.loaded.get(cell)
			if chunk and is_instance_valid(chunk):   # not loaded here (yet): skip, the next one will do
				var list := _chunk_bodies(chunk)
				if i < list.size() and is_instance_valid(list[i]):
					_add_sample(list[i], t, pose)
					stats.chunk_poses += 1


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
	_ignore_for_own(cart.net_bodies())
	_update_status()
	return cart


## Guest: the host's pose of our own cart (`poses`, every body) has come. Its frame is compared with where ours was
## when the host had our keys up to `stamp` (our clock, ms) and had simulated `held` ms more: that difference is our
## prediction error, eased out over correction_time. Too far off (or not driving yet): put it where the host has it.
func _correct_own(poses: Array, velocity: Vector3, stamp: int, held: int) -> void:
	var bodies := _own.net_bodies()
	if poses.size() < bodies.size():
		return
	var host_pos: Vector3 = poses[0][0]
	var host_rot: Quaternion = poses[0][1]
	var now := Time.get_ticks_msec()
	var then := now - ((now - stamp) & 0xffff) + held
	var past := _history_at(then) if _own_live else []
	if not past.is_empty():
		var err: Vector3 = host_pos - past[0]
		var rot: Quaternion = (host_rot * (past[1] as Quaternion).inverse()).normalized()
		if rot.w < 0.0:
			rot = -rot   # the short way round
		stats.own_error = maxf(stats.own_error, err.length())
		if err.length() < snap_distance and rot.get_angle() < PI / 3.0:
			_err_pos = err
			_err_rot = rot
			return
	if _own_live and past.is_empty():
		return   # keys too old to compare with (a stall): wait for the next snapshot
	for i in bodies.size():
		bodies[i].global_transform = Transform3D(Basis(poses[i][1]), poses[i][0])
		bodies[i].linear_velocity = velocity
		bodies[i].angular_velocity = Vector3.ZERO
		bodies[i].freeze = false
	for g in _own.groceries:
		g.freeze = not g.visible   # groceries out of play (a sweep) stay frozen
	_own_live = true
	_history.clear()
	_err_pos = Vector3.ZERO
	_err_rot = Quaternion.IDENTITY


## Our cart's frame pose [position, rotation] at local time `ms`, from the history (nearest tick), or [].
func _history_at(ms: int) -> Array:
	if _history.is_empty() or ms < _history[0][0] - 50 or ms > _history[-1][0] + 50:
		return []
	var best: Array = _history[0]
	for h in _history:
		if absi(h[0] - ms) < absi(best[0] - ms):
			best = h
	return [best[1], best[2]]


## Guest, every tick: records our cart's pose and eases a slice of the prediction error out of it (and out of the
## history, so the next snapshot measures only what is left).
func _drive_own(delta: float) -> void:
	if _own == null or not is_instance_valid(_own) or not _own_live:
		return
	var f := clampf(delta / correction_time, 0.0, 1.0)
	var dp := _err_pos * f
	var dq := Quaternion.IDENTITY.slerp(_err_rot, f)
	_err_pos -= dp
	_err_rot = (_err_rot * dq.inverse()).normalized()
	if dp.length_squared() > 1e-10 or dq.get_angle() > 1e-5:
		var pivot := _own.frame.global_position
		var rot := Basis(dq)
		for b in _own.net_bodies():
			var tf := b.global_transform
			b.global_transform = Transform3D(rot * tf.basis, pivot + dp + rot * (tf.origin - pivot))
			b.linear_velocity = rot * b.linear_velocity
			b.angular_velocity = rot * b.angular_velocity
		for h in _history:
			h[1] += dp
			h[2] = (dq * (h[2] as Quaternion)).normalized()
	var now := Time.get_ticks_msec()
	_history.append([now, _own.frame.global_position, _own.frame.global_transform.basis.get_rotation_quaternion()])
	while not _history.is_empty() and _history[0][0] < now - history_length * 1000.0:
		_history.pop_front()


func _add_sample(body: RigidBody3D, t: float, pose: Array) -> void:
	var s: Array = _samples.get(body, [])
	if s.is_empty():
		_samples[body] = [t, pose[0], pose[1], t, pose[0], pose[1]]
	elif t > s[3]:
		_samples[body] = [s[3], s[4], s[5], t, pose[0], pose[1]]


func _guest_tick(delta: float) -> void:
	if not _welcomed:
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			var why: String = peer.error_text if peer is WebRtcLink else ""
			_log("[color=#ff8a7a]Couldn't join %s%s[/color]" % [host_address, ": " + why if why else "."])
			leave()
			return
		_connecting_for += delta
		if _connecting_for > connect_timeout:
			_log("[color=#ff8a7a]No answer from %s.[/color]" % host_address)
			leave()
		return
	# Our keys, to the host: whenever they change, and input_rate times a second anyway (packets can be lost).
	var keys := 0
	var console := get_node_or_null("/root/Console")
	var focus := get_viewport().gui_get_focus_owner()
	if not (console and console.is_open()) and not (focus is LineEdit or focus is TextEdit):
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
		b.put_u16(Time.get_ticks_msec() & 0xffff)
		_send(1, b.data_array, false)
		_keys_sent = keys
		_input_clock = 0.0
	_drive_own(delta)
	if _newest < 0.0:
		return
	# Show the world interp_delay behind the newest snapshot; drift back toward that if packets bunch up.
	_render_time += delta
	var target := _newest - interp_delay
	if absf(_render_time - target) > 0.25:
		_render_time = target
	else:
		_render_time = lerpf(_render_time, target, 0.05)
	for body in _samples.keys():
		if not is_instance_valid(body):
			_samples.erase(body)   # its chunk was freed
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
	if role == Role.HOST and peer is WebRtcLink and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return "Starting online game..."
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
	message.emit(text)
	var console := get_node_or_null("/root/Console")
	if console and console.has_method("log_line"):
		console.log_line(text)
	else:
		print_rich(text)


func _cmd_host(args: PackedStringArray) -> void:
	host(int(args[0]) if args.size() > 0 else 0)


func _cmd_join(args: PackedStringArray) -> void:
	if args.is_empty():
		_log("Usage: join <join code> or join <address>[:port], e.g. join ABCD-EFGH or join 127.0.0.1")
		return
	_join_address(args[0])


func _cmd_online(args: PackedStringArray) -> void:
	var words := Array(args)
	if not words.is_empty() and words[0] in ["unlisted", "public"]:
		listed = words.pop_front() == "public"
	if not words.is_empty():
		game_name = " ".join(words)
	host_online()


func _cmd_games() -> void:
	var games := await list_games()
	if games.is_empty():
		_log("No public games right now.")
	for g in games:
		_log("  [b]%s[/b]  %s  (%s, %d/%d players)" % [pretty_code(g.code), g.name, g.level, g.players, g.max_players])


## A join code joins online; anything else is a LAN address.
func _join_address(text: String) -> void:
	if is_join_code(text) and not "." in text:
		join_online(text)
		return
	var parts := text.rsplit(":", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		join(parts[0], int(parts[1]))
	else:
		join(text)
