@tool
class_name LotGenerator
extends Node3D
## Lays out a surface parking lot from a few parameters (scenes/lot_gen/lot_generator.tscn): rows of stalls at
## 90, 60, 45 or 30 degrees, the drive aisles between them, curbed islands at the row ends, wheel stops, stall
## striping, a perimeter curb with an entrance, and cart corrals in some stalls. Sizes come from "Complete Parking
## Lot Design" (References/Levels/c620content.pdf): 8.5 x 18 ft stalls, Table 1 for the angles and aisle widths,
## 4 in stripes, wheel stops set back for a 2 ft overhang.
##
## The lot runs +X from this node's origin, which is the middle of the entrance on the lot's -X edge; it is
## size.y deep, centred on Z. Rows run along X. Across Z it goes: a single row against the edge, then
## aisle / double row / aisle ... and a single row against the far edge. Round the row ends is an end drive.
##
## Everything is built from the piece scenes below and put under the group nodes. If they are all empty when the
## scene loads, the lot is generated then. In the editor, Generate builds it into the scene (saved, hand-editable);
## Clear empties it again so it is generated on load.

const FT := 0.3048
const STRIPE_WIDTH := 4.0 * 0.0254          ## 4 in stall stripes
const OVERHANG := 2.0 * FT                  ## a car's nose goes this far past its wheel stop
const ISLAND_RADIUS := 0.45                 ## island corner radius (fill stays under the curb top, see _island)
const ISLAND_FILL_INSET := 0.14             ## fill edge inside the curb line, under the 6" curb top
const ISLAND_FILL_TOP := 0.13               ## m, just under the curb top
const PERIMETER_RADIUS := 1.5
## Table 1: one-way aisle width (ft) by stall angle. Two-way aisles are 24 ft at every angle.
const ONE_WAY_AISLE_FT := {90: 22.0, 60: 16.0, 45: 14.0, 30: 12.0}
const TWO_WAY_AISLE_FT := 24.0

@export_tool_button("Generate", "Reload") var generate_button := _generate_in_editor
@export_tool_button("Clear", "Clear") var clear_button := clear

@export var seed := 1                       ## picks the corral stalls
@export var size := Vector2(70.0, 60.0)     ## m: X along the rows (entrance to back), Z across them
@export_enum("90:90", "60:60", "45:45", "30:30") var stall_angle := 90
@export var two_way := true                 ## two-way aisles (24 ft); off: one-way, narrower, alternating direction
@export var stall_width := 8.5 * FT
@export var stall_length := 18.0 * FT
@export var end_drive := 24.0 * FT          ## drive round the ends of the rows
@export var end_islands := true             ## curbed planting islands at the ends of the double rows
@export var island_length := 2.4            ## m along the row
@export var wheel_stops := true
@export var perimeter_curb := true
@export var entrance_width := 24.0 * FT     ## gap in the perimeter curb, middle of the -X edge
@export var corrals := 2                    ## cart corrals, each in a stall of a double row

@export_group("Nodes")
@export var surface: Node3D                 ## the asphalt: a 1 x 1 m plane, scaled to the lot
@export var stripes: Node3D                 ## generated pieces go under these
@export var stops: Node3D
@export var curbs: Node3D
@export var islands: Node3D
@export var corral_group: Node3D

@export_group("Pieces")
@export var stripe_scene: PackedScene       ## a 1 x 1 m painted stripe, scaled to length and width
@export var curb_scene: PackedScene         ## scenes/curb/curb.tscn
@export var wheel_stop_scene: PackedScene   ## the Nitterhouse 6 ft wheel stop, long along X
@export var island_fill_scene: PackedScene  ## an IslandFill (mulch box with collision), sized per island
@export var corral_scene: PackedScene       ## a cart corral, long along Z

## Set by the console's `lotgen` before the level loads; used once, then cleared.
static var next_options := {}

var stall_count := 0                        ## stalls laid out last time (corral stalls included)
var _baking := false                        ## Generate in the editor: pieces are saved with the scene


func _ready() -> void:
	if not next_options.is_empty() and not Engine.is_editor_hint():
		for k: String in next_options:
			set(k, next_options[k])
		next_options = {}
		clear()
	if _groups().all(func(g: Node3D) -> bool: return g.get_child_count() == 0):
		generate()


## Stall depth at right angles to the aisle (Table 1, D).
func stall_depth() -> float:
	var a := deg_to_rad(stall_angle)
	return stall_length * sin(a) + stall_width * cos(a)


## Aisle width for the angle and traffic (Table 1, E).
func aisle_width() -> float:
	return (TWO_WAY_AISLE_FT if two_way else ONE_WAY_AISLE_FT[stall_angle]) * FT


## Removes the generated lot.
func clear() -> void:
	for g in _groups():
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	stall_count = 0


## Builds the lot from the parameters.
func generate() -> void:
	clear()
	surface.position = Vector3(size.x * 0.5, 0.0, 0.0)
	surface.scale = Vector3(size.x, 1.0, size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := stall_depth()
	var e := aisle_width()
	var aisles := maxi(1, int(size.y / (2.0 * d + e)))
	var margin := (size.y - aisles * (2.0 * d + e)) * 0.5   # spare depth, left as asphalt at both edges
	var x0 := end_drive
	var x1 := size.x - end_drive
	var stalls: Array[Dictionary] = []      # double-row stalls, where corrals may go
	var z := -size.y * 0.5 + margin
	for j in aisles:
		# Rows either side of aisle j: the head of the row behind it, then the aisle, then the row in front.
		var dir := 1.0 if (two_way or j % 2 == 0) else -1.0
		var za := z + d                     # this aisle's -Z edge
		var zb := za + e                    # and its +Z edge
		var inner_lo := j > 0
		var inner_hi := j < aisles - 1
		var xs_lo := x0 + (island_length if (end_islands and inner_lo) else 0.0)
		var xe_lo := x1 - (island_length if (end_islands and inner_lo) else 0.0)
		var xs_hi := x0 + (island_length if (end_islands and inner_hi) else 0.0)
		var xe_hi := x1 - (island_length if (end_islands and inner_hi) else 0.0)
		var lo := _row(xs_lo, xe_lo, za, -1.0, dir)
		var hi := _row(xs_hi, xe_hi, zb, 1.0, dir)
		if inner_lo:
			stalls.append_array(lo)
		if inner_hi:
			stalls.append_array(hi)
		# Islands at the ends of the double row beyond this aisle's +Z side.
		if end_islands and inner_hi:
			_island(Rect2(x0, zb, island_length, 2.0 * d))
			_island(Rect2(x1 - island_length, zb, island_length, 2.0 * d))
		z = zb + d
	if perimeter_curb:
		var h := size.y * 0.5
		var g := entrance_width * 0.5
		var c: Curb = curb_scene.instantiate()
		c.name = "Perimeter"
		# Wound so the lot is on the curb's right (the street side).
		c.curve = Curb.curve_through(PackedVector3Array([Vector3(0, 0, -g), Vector3(0, 0, -h), Vector3(size.x, 0, -h),
				Vector3(size.x, 0, h), Vector3(0, 0, h), Vector3(0, 0, g)]), PERIMETER_RADIUS)
		_add(curbs, c)
	for i in mini(corrals, stalls.size()):
		var s: Dictionary = stalls.pop_at(rng.randi_range(0, stalls.size() - 1))
		var corral: Node3D = corral_scene.instantiate()
		corral.transform = Transform3D(Basis(Vector3.UP, s.yaw), s.center)
		_add(corral_group, corral)
		if s.stop:
			stops.remove_child(s.stop)
			s.stop.free()


## Stripes one row of stalls along X from xs to xe. The aisle edge is at z = za and the stalls go off it toward
## `side` (+1: +Z). Cars drive along the aisle toward `dir` (+1: +X) and turn into the stalls. Returns the stalls
## as { center, yaw (turns local +Z onto the stall axis), stop (its wheel stop or null) }.
func _row(xs: float, xe: float, za: float, side: float, dir: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := deg_to_rad(stall_angle)
	var d := stall_depth()
	var pitch := stall_width / sin(a)            # along the aisle (Table 1, C)
	var run := d * cos(a) / sin(a)               # how far along X a stripe goes as it crosses the row
	var u := Vector3(dir * cos(a), 0.0, side * sin(a))   # stall axis, aisle to head
	var g := d / sin(a)                          # stripe length (Table 1, G)
	var n := int(floor((xe - xs - run) / pitch))
	if n < 1:
		return out
	# Stripes start on the aisle edge at first + i * pitch; their head ends lean `run` toward dir.
	var first := xs + (xe - xs - n * pitch - run) * 0.5 + (run if dir < 0.0 else 0.0)
	for i in n + 1:
		var p := Vector3(first + i * pitch, 0.0, za)
		_stripe(p, p + u * g)
	var yaw := atan2(u.x, u.z)
	for i in n:
		var aisle_mid := Vector3(first + (i + 0.5) * pitch, 0.0, za)
		var head_mid := aisle_mid + u * g
		var stall := { center = (aisle_mid + head_mid) * 0.5, yaw = yaw, stop = null }
		if wheel_stops:
			# The car's nose corner touches the head line; its front edge centre is (W/2) cot A short of it.
			var front := head_mid - u * (stall_width * 0.5 * cos(a) / sin(a))
			var w: Node3D = wheel_stop_scene.instantiate()
			w.transform = Transform3D(Basis(Vector3.UP, yaw), front - u * OVERHANG)
			_add(stops, w)
			stall.stop = w
		out.append(stall)
		stall_count += 1
	return out


func _stripe(from: Vector3, to: Vector3) -> void:
	var s: Node3D = stripe_scene.instantiate()
	var v := to - from
	# The stripe's mesh is 1 m along X and 1 m along Z: X becomes the stripe's length, Z its width.
	var basis := Basis(Vector3.UP, atan2(-v.z, v.x))
	s.transform = Transform3D(basis.scaled_local(Vector3(v.length(), 1.0, STRIPE_WIDTH)), (from + to) * 0.5)
	_add(stripes, s)


## A curbed island over `r` (x along the row, y across it, in lot X/Z), with a mulch fill.
func _island(r: Rect2) -> void:
	var c: Curb = curb_scene.instantiate()
	# Wound so the street side of the curb faces out.
	c.curve = Curb.curve_through(PackedVector3Array([Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y),
			Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.position.y)]), ISLAND_RADIUS, true)
	_add(curbs, c)
	var fill: IslandFill = island_fill_scene.instantiate()
	var centre := r.get_center()
	fill.position = Vector3(centre.x, 0.0, centre.y)
	fill.size = Vector3(r.size.x - 2.0 * ISLAND_FILL_INSET, ISLAND_FILL_TOP, r.size.y - 2.0 * ISLAND_FILL_INSET)
	_add(islands, fill)


func _groups() -> Array[Node3D]:
	return [stripes, stops, curbs, islands, corral_group]


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	if Engine.is_editor_hint() and _baking:
		child.owner = get_tree().edited_scene_root


func _generate_in_editor() -> void:
	_baking = true
	generate()
	_baking = false
