class_name NetProtocol
extends RefCounted
## The multiplayer wire format: plain little-endian bytes, so the browser game (mobile/, JavaScript DataView) can
## speak it too. Every packet starts with a one-byte message type. Strings are a u32 byte length then UTF-8.
## A pose is position (3 x f32) then rotation quaternion x, y, z, w (4 x f32): 28 bytes.
##
##   HELLO     guest -> host  reliable    u16 version
##   WELCOME   host -> guest  reliable    u16 version, u32 your id, u8 level serial, u16 level bodies, str level path
##   REJECT    host -> guest  reliable    str reason
##   LEVEL     host -> guests reliable    u8 level serial, u16 level bodies, str level path
##   INPUT     guest -> host  unreliable  u8 level serial it has loaded, u8 keys held (bit i = ShoppingCart.ACTIONS[i]);
##                                        the host only sends snapshots to guests that have loaded its level
##   RESET     guest -> host  reliable    (nothing: put my cart back on its wheels where it is)
##   SNAPSHOT  host -> guests unreliable  u8 level serial, u32 tick, u8 carts, then per cart:
##                                          u32 player id, i16 left hand N, i16 right hand N, u8 flags (1 = fallen),
##                                          3 x f32 frame velocity, f32 turn rate, u8 bodies, a pose per body
##                                          (ShoppingCart.net_bodies() order);
##                                        then u16 level bodies, per body: u16 index, pose
##   LEFT      host -> guests reliable    u32 player id
## A snapshot too big for one packet is sent as several, each a complete SNAPSHOT for the same tick.

const VERSION := 1
## Bump VERSION whenever a message changes, so old and new builds refuse each other cleanly.

enum Msg { HELLO = 1, WELCOME, REJECT, LEVEL, INPUT, RESET, SNAPSHOT, LEFT }

const POSE_BYTES := 28


static func writer(type: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.put_u8(type)
	return b


static func reader(packet: PackedByteArray) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.data_array = packet
	return b


static func put_pose(b: StreamPeerBuffer, t: Transform3D) -> void:
	var q := t.basis.get_rotation_quaternion()
	for v in [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]:
		b.put_float(v)


## Returns [position: Vector3, rotation: Quaternion].
static func get_pose(b: StreamPeerBuffer) -> Array:
	var p := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	return [p, q.normalized()]


static func put_string(b: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer()
	b.put_u32(bytes.size())
	b.put_data(bytes)


static func get_string(b: StreamPeerBuffer) -> String:
	var n := b.get_u32()
	return (b.get_data(n)[1] as PackedByteArray).get_string_from_utf8()
