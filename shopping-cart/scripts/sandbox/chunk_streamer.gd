class_name ChunkStreamer
extends Node3D
## Makes the sandbox endless: the ground is a grid of chunk_size squares, and the squares near the cart are filled
## with terrain chunks (scenes/sandbox/chunks/*.tscn: parking lot, street, supermarket floor, garage deck, hill),
## loaded ahead of the cart and freed behind it. Which chunk goes in a square, and which way it faces, comes from
## a hash of the square's grid position and `world_seed`, so a square always gets the same chunk when you come back
## (but anything you knocked over there is put back).
##
## This node's position is the corner of grid square (0, 0); square (i, j) covers
## [i, i + 1) * chunk_size in x and [j, j + 1) * chunk_size in z from here. `home_cells` are left empty for the
## hand-built part of the level (the store floor and parking lot in scenes/main.tscn).
##
## Every chunk is flat at height 0 along its edges, so any chunk meets any other flush in any of the four turns.
## `far_ground` (a big plane just below the floors) follows the cart, so the horizon past the loaded chunks is
## ground rather than sky; the level's fog hides where the chunks stop.
##
## The browser version streams the same grid (mobile/game/stream.js); keep pick() in step with it.

@export var main: Node                              ## the level; its `cart` is what the chunks gather around
@export var chunks: Array[PackedScene] = []         ## the terrain chunks to fill squares with
@export var weights: PackedFloat32Array = []        ## how often each chunk comes up, relative to the others
@export var chunk_size := 40.0                      ## m: the side of a grid square (and of every chunk)
@export var world_seed := 1                         ## a different seed lays out a different world
@export var load_distance := 64.0                   ## m: squares whose nearest point is closer than this are loaded
@export var unload_distance := 88.0                 ## m: loaded squares farther than this are freed
@export var loads_per_frame := 1                    ## chunks built per frame while driving (all at once at the start)
@export var home_cells: Array[Vector2i] = []        ## squares left empty for the level's own ground
@export var far_ground: Node3D                      ## follows the cart (snapped to the grid) to fill the horizon

var loaded := {}        ## Vector2i -> the chunk node in that square
var _last_focus := Vector3.INF


func _ready() -> void:
	assert(chunks.size() == weights.size(), "ChunkStreamer: one weight per chunk")


func _process(_delta: float) -> void:
	var focus := _focus()
	if far_ground:
		var snap := Vector3(snappedf(focus.x, chunk_size), far_ground.global_position.y, snappedf(focus.z, chunk_size))
		far_ground.global_position = snap
	# At the start, and after a jump (a fresh cart somewhere else), everything near is built at once so the cart
	# never lands on a missing square; while driving, a few per frame so there's no hitch.
	var jumped := _last_focus == Vector3.INF or focus.distance_to(_last_focus) > chunk_size * 0.5
	update(focus, 0 if jumped else loads_per_frame)
	_last_focus = focus


## Where the chunks gather: the cart if there is one, else the camera.
func _focus() -> Vector3:
	var cart: Node = main.get("cart") if main else null
	if cart is ShoppingCart and is_instance_valid(cart):
		return (cart as ShoppingCart).cart_origin()
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else global_position


## Loads the missing squares near `focus` (at most `budget` of them, nearest first; 0 = all) and frees far ones.
func update(focus: Vector3, budget: int = 0) -> void:
	var local := focus - global_position
	var c := Vector2i(floori(local.x / chunk_size), floori(local.z / chunk_size))
	var reach := ceili(load_distance / chunk_size)
	var wanted := []
	for i in range(c.x - reach, c.x + reach + 1):
		for j in range(c.y - reach, c.y + reach + 1):
			var cell := Vector2i(i, j)
			if loaded.has(cell) or home_cells.has(cell):
				continue
			var d := _distance(local, cell)
			if d < load_distance:
				wanted.append([d, cell])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for k in wanted.size() if budget <= 0 else mini(budget, wanted.size()):
		_load(wanted[k][1])
	for cell in loaded.keys():
		if _distance(local, cell) > unload_distance:
			loaded[cell].queue_free()
			loaded.erase(cell)


## Distance in the ground plane from `local` (relative to this node) to the nearest point of square `cell`.
func _distance(local: Vector3, cell: Vector2i) -> float:
	var x0 := cell.x * chunk_size
	var z0 := cell.y * chunk_size
	var dx := maxf(maxf(x0 - local.x, local.x - (x0 + chunk_size)), 0.0)
	var dz := maxf(maxf(z0 - local.z, local.z - (z0 + chunk_size)), 0.0)
	return Vector2(dx, dz).length()


func _load(cell: Vector2i) -> void:
	var p := pick(cell)
	var chunk: Node3D = chunks[p[0]].instantiate()
	chunk.name = "Chunk_%d_%d" % [cell.x, cell.y]
	chunk.transform = cell_transform(cell, p[1])
	add_child(chunk)
	loaded[cell] = chunk


## Where a chunk in `cell` sits (relative to this node): the square's centre, turned `turns` quarter turns.
func cell_transform(cell: Vector2i, turns: int) -> Transform3D:
	var centre := Vector3((cell.x + 0.5) * chunk_size, 0, (cell.y + 0.5) * chunk_size)
	return Transform3D(Basis(Vector3.UP, turns * PI / 2), centre)


## [chunk index, quarter turns] for a square. The same in the browser (mobile/game/stream.js): 32-bit integer
## hashing only, so both get the same world from the same seed.
func pick(cell: Vector2i) -> Array:
	var h := cell_hash(cell.x, cell.y, world_seed)
	var total := 0.0
	for w in weights:
		total += w
	var r := float(h % 10000) / 10000.0 * total
	var idx := 0
	for k in weights.size():
		r -= weights[k]
		if r < 0.0:
			idx = k
			break
		idx = k
	return [idx, (h >> 20) & 3]


static func cell_hash(x: int, z: int, s: int) -> int:
	var h := (s & 0xFFFF) ^ 0x9E37
	h = _mix(h ^ (x & 0xFFFFFFFF))
	h = _mix(h ^ (z & 0xFFFFFFFF))
	return h


## A 32-bit integer mix (lowbias32), the same as the browser's Math.imul version.
static func _mix(h: int) -> int:
	h &= 0xFFFFFFFF
	h ^= h >> 16
	h = _mul32(h, 0x7FEB352D)
	h ^= h >> 15
	h = _mul32(h, 0x846CA68B)
	h ^= h >> 16
	return h


## (a * b) mod 2^32 for 32-bit a and b, in halves so the product never overflows a 64-bit int.
static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF
