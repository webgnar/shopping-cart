class_name WebRtcLink
extends MultiplayerPeerExtension
## The online transport: WebRTC data channels between the host and each guest, introduced by the rendezvous
## service (services/rendezvous) over a WebSocket. NetSession uses it exactly like ENet (it is a MultiplayerPeer),
## so the game code doesn't care which one it has.
##
## Each host-guest pair gets one RTCPeerConnection with two negotiated data channels, the same on every machine so
## the browser game can join too:
##   id 1 "control": reliable, ordered        -> TRANSFER_MODE_RELIABLE packets
##   id 2 "state":   unordered, no resends    -> every other packet (inputs, snapshots)
## The host makes the offer for each guest the service announces; candidates trickle both ways through the service.
## Player ids come from the service: the host is 1, guests 2 and up.
## Desktop Godot gets WebRTC from addons/webrtc (godotengine/webrtc-native); web exports have it built in.

signal signal_message(msg: Dictionary)   ## every message from the service (hosted, welcome, closed, error...)

const CONTROL := 0
const STATE := 1

var server := false
var url := ""                  ## the service's room WebSocket URL
var error_text := ""           ## why the link failed or closed, for the player
var join_code := ""
var _ws := WebSocketPeer.new()
var _ws_open := false
var _id := 0
var _ice_servers: Array = []
var _status := MultiplayerPeer.CONNECTION_CONNECTING
var _peers := {}               ## id -> {"pc": WebRTCPeerConnection, "ch": [control, state], "up": bool}
var _queue: Array = []         ## [from, packet, channel index]
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false


## Host side: `room_url` is ws(s)://<service>/room/<code>/host, `token` the private token /host returned.
static func hosting(room_url: String, token: String, code: String) -> WebRtcLink:
	var link := WebRtcLink.new()
	link.server = true
	link.join_code = code
	link._id = 1
	link.url = room_url
	link._ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + token])
	link._connect_ws()
	return link


## Guest side: `room_url` is ws(s)://<service>/room/<code>/join?protocol=N.
static func joining(room_url: String, code: String) -> WebRtcLink:
	var link := WebRtcLink.new()
	link.join_code = code
	link.url = room_url
	link._connect_ws()
	return link


func _connect_ws() -> void:
	_ws.inbound_buffer_size = 1 << 18
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("Couldn't reach the multiplayer service (error %d)." % err)


func _fail(text: String) -> void:
	if error_text == "":
		error_text = text
	_close()


# ---------------------------------------------------------------- MultiplayerPeer

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_ws_open = true
			while _ws.get_available_packet_count() > 0:
				var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_on_signal(msg)
		WebSocketPeer.STATE_CLOSED:
			# Signaling can go once everyone is connected (links already up keep working), but a host that loses
			# it can't take new guests, and a guest that loses it before reaching the host never will.
			var why := _ws.get_close_reason()
			if _ws_open:
				_ws_open = false
				if server:
					push_warning("Lost the multiplayer service: %s" % why)
				elif not _peers.get(1, {}).get("up", false):
					_fail(why if why != "" else "The multiplayer service closed the connection.")
			elif _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_fail(why if why != "" else "Couldn't reach the multiplayer service.")
	for id in _peers.keys():
		var p: Dictionary = _peers[id]
		var pc: WebRTCPeerConnection = p.pc
		pc.poll()
		var state := pc.get_connection_state()
		if state in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]:
			_drop(id, "Couldn't connect to the %s directly." % ("guest" if server else "host"))
			continue
		var open: bool = p.ch.all(func(c: WebRTCDataChannel): return c.get_ready_state() == WebRTCDataChannel.STATE_OPEN)
		if open and not p.up:
			p.up = true
			if not server:
				_status = MultiplayerPeer.CONNECTION_CONNECTED
			peer_connected.emit(id)
		elif p.up and not open:
			_drop(id, "Lost the connection to the %s." % ("guest" if server else "host"))
			continue
		for i in p.ch.size():
			var ch: WebRTCDataChannel = p.ch[i]
			while ch.get_available_packet_count() > 0:
				_queue.append([id, ch.get_packet(), i])


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	return _queue.pop_front()[1] if not _queue.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _queue[0][0] if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if not _queue.is_empty() and _queue[0][2] == STATE:
		return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var lane := CONTROL if _mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE else STATE
	var sent := false
	for id in _peers:
		if _target == 0 or _target == id or (_target < 0 and -_target != id):
			var p: Dictionary = _peers[id]
			if p.up:
				(p.ch[lane] as WebRTCDataChannel).put_packet(buffer)
				sent = true
	return OK if sent else ERR_UNAVAILABLE


func _get_max_packet_size() -> int:
	return 65535


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return server


func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _disconnect_peer(peer: int, _force: bool) -> void:
	_drop(peer, "")


func _close() -> void:
	for id in _peers.keys():
		_drop(id, "")
	_ws.close()
	_queue.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


# ---------------------------------------------------------------- signaling

func _on_signal(msg: Dictionary) -> void:
	_handle_signal(msg)
	signal_message.emit(msg)


func _handle_signal(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"hosted":
			_ice_servers = msg.get("ice_servers", [])
			_status = MultiplayerPeer.CONNECTION_CONNECTED
		"welcome":
			_ice_servers = msg.get("ice_servers", [])
			_id = int(msg.id)
			_open_peer(1)
		"join":
			if server and not _refuse:
				var id := int(msg.id)
				_open_peer(id)
				_peers[id].pc.create_offer()
		"leave":
			if server:
				_drop(int(msg.id), "")
		"offer", "answer":
			var from := int(msg.get("from", 0))
			if _peers.has(from):
				# An offer makes the connection create its answer (session_description_created).
				_peers[from].pc.set_remote_description(msg.type, str(msg.get("sdp", "")))
		"candidate":
			var from := int(msg.get("from", 0))
			if _peers.has(from):
				_peers[from].pc.add_ice_candidate(str(msg.get("mid", "")), int(msg.get("index", 0)), str(msg.get("candidate", "")))
		"closed", "error":
			_fail(str(msg.get("reason", "The game has ended.")))


func _send_signal(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


## A connection to player `id` (as host: a guest; as guest: the host, id 1) with the two channels.
func _open_peer(id: int) -> void:
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize({"iceServers": _ice_servers})
	if err != OK:
		_fail("WebRTC isn't available in this build (error %d): addons/webrtc is missing for this platform." % err)
		return
	var control := pc.create_data_channel("control", {"negotiated": true, "id": 1})
	var state := pc.create_data_channel("state", {"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0})
	if control == null or state == null:
		_fail("Couldn't open WebRTC data channels.")
		return
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_send_signal({"type": type, "to": id, "sdp": sdp}))
	pc.ice_candidate_created.connect(func(mid: String, index: int, candidate: String):
		_send_signal({"type": "candidate", "to": id, "mid": mid, "index": index, "candidate": candidate}))
	_peers[id] = {"pc": pc, "ch": [control, state], "up": false}


func _drop(id: int, why: String) -> void:
	var p: Dictionary = _peers.get(id, {})
	if p.is_empty():
		return
	_peers.erase(id)
	for c in p.ch:
		(c as WebRTCDataChannel).close()
	(p.pc as WebRTCPeerConnection).close()
	_queue = _queue.filter(func(q): return q[0] != id)
	if p.up:
		peer_disconnected.emit(id)
	if not server and id == 1:
		if why != "" and error_text == "":
			error_text = why
		_ws.close()
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		if not p.up:
			return
	if server and why != "":
		push_warning("Player %d: %s" % [id, why])


## Keeps the public listing alive; the host calls this every 30 s.
func heartbeat() -> void:
	_send_signal({"type": "heartbeat"})
