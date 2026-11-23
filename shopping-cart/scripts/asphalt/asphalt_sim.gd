class_name AsphaltSim
extends Node
## A 2D (top-down) simulation of an asphalt road section ageing and being repaired, year by year.
##
## The section runs along +Y (direction of travel) and across X, in metres: a gravel shoulder each side, two
## lanes meeting at a longitudinal construction joint, and two wheel paths per lane where the traffic load goes.
## It follows the Austroads crack types in the project's "Asphalt Cracking Quick Guide":
##   - oxidation and UV harden and grey the surface, then the aggregate starts to ravel out
##   - transverse (thermal) cracks run across the road, spaced closer as the binder hardens
##   - the lane joint opens into a longitudinal crack early on
##   - traffic fatigue builds in the wheel paths (faster on thin or poorly built pavement, and on wet,
##     weak subgrade); it starts as longitudinal wheel-path cracks that branch into fatigue ("alligator") cells
##   - old, hard binder shrinks into block cracking off the long cracks
##   - edge cracking and fretting where the pavement meets an unsealed shoulder
##   - slippage crescents where the wearing course is poorly bonded
##   - water through open cracks (freeze-thaw) wears the base until potholes break out and grow
##   - after a surface seal or an overlay the old cracks and patch edges come back as reflection cracks
## Repairs: crack filling (overbanded sealant), throw-and-roll pothole fill (which tends to fail again), saw-cut
## heavy patches (whose seams crack later), a surface seal, and cold planing plus an asphalt overlay.
##
## The state is vector data (crack polylines, patch rectangles) plus a 10 cm cell grid; AsphaltCanvas draws it.
## The simulation is deterministic for a seed and the list of repairs, so scrubbing back in time just replays it.

signal changed

enum Kind { TRANSVERSE, JOINT, WHEELPATH, FATIGUE, BLOCK, EDGE, SLIPPAGE, REFLECTION, SEAM }
enum Action { CRACK_FILL, POTHOLE_FILL, HEAVY_PATCH, SURFACE_SEAL, OVERLAY }
enum Surface { HOT_MIX, CHIP_SEAL }

const KIND_NAMES := ["transverse", "lane joint", "wheel path", "fatigue", "block", "edge", "slippage",
	"reflection", "patch seam"]
const ACTION_NAMES := ["Crack filling", "Pothole fill", "Heavy patch", "Surface seal", "Mill & overlay"]

const CELL := 0.1        ## m: cell grid for fatigue, water damage and potholes
const GRID := 0.02       ## m: crack occupancy grid (cracks that run into another one join it)
const STEP := 0.025      ## m: spacing of the points along a crack
const DT := 0.2          ## years per simulation step
const SEAL_LIFE := 6.0   ## years crack sealant holds before it debonds
const HOLE_MAX := 0.09   ## m: a pothole stops deepening at the base course
const SEAL_PROUD := 0.0015  ## m the overbanded crack sealant stands above the road

@export var seed := 1
@export var size := Vector2(10.0, 10.0)                 ## m: X across the road, Y along it

@export_group("Road layout")
@export var shoulder := 0.7                             ## m of unsealed gravel shoulder each side
@export var unsealed_edges := true                      ## the outer edges crack and fret (off where more pavement butts on)
@export var lane_joint_x := 5.0                         ## m: the longitudinal paving joint between the lanes
@export var wheel_paths := PackedFloat32Array([1.95, 3.75, 6.25, 8.05])  ## m: centre of each wheel path
@export var wheel_path_width := 0.35                    ## m: spread of the wheel load either side of a path

@export_group("Pavement and conditions")
@export_range(0.3, 1.5, 0.05) var structure := 1.0     ## thickness and build quality (0.5 = thin or poorly compacted)
@export_range(0.0, 2.0, 0.05) var traffic := 1.0       ## heavy traffic load
@export_range(0.0, 2.0, 0.05) var climate := 1.0       ## freeze-thaw cycles and sun (oxidation, UV)
@export_range(0.0, 2.0, 0.05) var drainage := 1.0      ## how much water gets in and stays (1 = typical)
@export_range(0.0, 1.0, 0.05) var bond := 0.7          ## bond of the wearing course to the layer below (low = slippage)
@export var oxidation_years := 9.0                      ## years for the binder to go most of the way to grey
@export var thermal_spacing := Vector2(5.0, 1.4)        ## m between thermal cracks: new binder, fully aged (colder and thinner: closer)
@export_range(0.0, 2.0, 0.05) var ponding := 1.0       ## how much water sits in low spots (poor grading)

@export_group("Mix and crack paths")
@export_range(0.0, 1.0, 0.05) var mix_variation := 0.5 ## how uneven the asphalt's strength is (compaction, segregation)
@export var aggregate_size := 0.012                     ## m: the stones; the fine strength noise is this size
@export_range(0.0, 1.0, 0.05) var crack_bias := 0.6    ## how hard cracks seek the weaker mix as they grow
@export_range(0.0, 1.0, 0.05) var branching := 0.15    ## side branches per metre of freely growing crack
@export_range(0.0, 1.0, 0.05) var t_junctions := 0.55  ## share of cracks that run into another and join it at a T
@export_range(0.0, 1.0, 0.05) var stop_short := 0.25   ## share that die out just short of it (the rest turn and run along it)

@export_group("Crack networks")
@export var fatigue_cell := Vector2(0.14, 0.2)          ## m: size of a crocodile-skin cell (across, along the road)
@export var block_cell := Vector2(1.6, 2.2)             ## m: size of a block in block cracking
@export_range(0.0, 1.0, 0.05) var block_onset := 0.55   ## oxidation (0..1) at which the first blocks crack

@export_group("Displacement")
@export var shoulder_drop := -0.025                     ## m: the gravel shoulder sits this far below the road
@export var fret_drop := -0.035                         ## m: where the edge has broken off, down to the base course
@export var spall_depth := 0.006                        ## m: broken shoulders either side of a wide crack
@export var edge_feather := 0.15                        ## m round the section easing back to 0 to meet flat ground

@export_group("Paint")
@export var paint_lines := PackedVector2Array()         ## painted lines (stall lines): start and end point pairs, m
@export var paint_width := 0.1                          ## m (4 in, the standard stall line)
@export var paint_thickness := 0.0008                   ## m fresh traffic paint stands above the asphalt
@export var paint_life := 8.0                           ## years for the paint to wear off under a wheel path
## The lines are repainted with every surface seal or overlay; patches and fills cover them.

@export_group("Maintenance")
@export var auto_maintain := false                      ## a road crew repairs the road on its own (see _auto_maintain)
@export var show_repairs := true                        ## off: the repairs in `events` are kept but not done

## Time since the road was built, years.
var time := 0.0
## When the current wearing surface went down (overlay or seal) and what it is.
var surface_born := 0.0
var surface_kind := Surface.HOT_MIX
var rut_born := 0.0
var cracks: Array[Crack] = []
var patches: Array[Dictionary] = []       ## { rect: Rect2, born: float, seams_at: PackedFloat32Array }
var events: Array[Dictionary] = []        ## repairs asked for by hand: { t, action }
var log_lines: PackedStringArray = []     ## every repair done, in order, for the lab's history

# Cell grid (CELL), row-major: i = cy * nx + cx.
var nx := 0
var ny := 0
var weak := PackedFloat32Array()      ## 0..1 subgrade weakness (soft spots, poor support)
var pond := PackedFloat32Array()      ## 0..1 low spots where water stands after rain
var load := PackedFloat32Array()      ## traffic load per cell (wheel paths)
var fatigue := PackedFloat32Array()   ## accumulated fatigue; cracks start at 1, break up into cells past FATIGUE_CELLS
var damage := PackedFloat32Array()    ## water damage under open cracks; a pothole breaks out at 1
var hole := PackedFloat32Array()      ## pothole depth, m
var fill_born := PackedFloat32Array() ## year a throw-and-roll fill went in, -1 for none
var patch_of := PackedInt32Array()    ## index of the heavy patch covering the cell, -1 for none
var crack_len := PackedFloat32Array() ## m of crack in the cell
var open_len := PackedFloat32Array()  ## m of unsealed crack in the cell
var edge_l := PackedFloat32Array()    ## m of pavement edge fretted away per row, left side
var edge_r := PackedFloat32Array()    ## same, right side

# Occupancy grid (GRID): crack index + 1 and point index.
var gx := 0
var gy := 0
var occ := PackedInt32Array()
var occ_pt := PackedInt32Array()

var _rng := RandomNumberGenerator.new()
var _mix_low := FastNoiseLite.new()    ## asphalt strength over metres (compaction, segregation)
var _mix_fine := FastNoiseLite.new()   ## and stone by stone
var _next_event := 0
var _latent: Array[Dictionary] = []   ## buried crack paths waiting to reflect: { path, at }
var _transverse_y: PackedFloat32Array = []

# Crack networks laid out at year 0, waiting under the surface: the Voronoi cells of jittered seed points. The fatigue
# network (small cells, longer along the road) covers the wheel paths and becomes crocodile cracking; the block
# network (cells a couple of metres across, nearly square to the road) covers the whole road and becomes block
# cracking. Each edge opens once the stress on it passes its own threshold, starting from a crack it touches.
var net_seeds := PackedVector2Array()       ## fatigue cell centres
var net_cells: Array[PackedVector2Array] = []   ## each fatigue cell's outline (empty at the rim of the network)
var plucked := PackedFloat32Array()         ## per fatigue cell: pothole depth where the cell has been plucked out, m
var _cell_seed := PackedInt32Array()        ## per 10 cm cell: the fatigue cell over it, -1 for none
var _net_edges: Array[Dictionary] = []          ## { a, b, kind, thr, on, ci (cell of the midpoint) }
var _last := { }                      ## year each repair was last done (auto maintenance)
var _seal_check := INF                ## next year a crack's sealant gives out

const FATIGUE_CELLS := 1.2            ## fatigue past which the wheel paths break up into crocodile cells


class Crack:
	var kind := 0
	var pts := PackedVector2Array()
	var born := PackedFloat32Array()  ## year each point formed
	var dir := 0.0                    ## heading of the growing tip, rad
	var pref := 0.0                   ## heading it tends back to
	var steer := 0.0                  ## how hard it turns back to pref per step
	var wander := 0.1                 ## rad of random turn per step
	var speed := 1.0                  ## m per year
	var max_len := 1e9
	var length := 0.0
	var growing := true
	var carry := 0.0                  ## growth not yet turned into points
	var twin := -1                    ## crack growing the other way from the same start
	var parent := -1                  ## crack it branched off
	var widen := 1.0                  ## how fast it opens
	var guide := PackedVector2Array() ## path it follows (reflection and seam cracks)
	var guide_i := 0
	var seal_from := -1.0             ## year it was filled, -1 for never
	var sealed_before := 0.0          ## opening it missed while sealed before seal_from (see _g)
	var alive := true
	var local := 1.0                  ## how fast it opens where it is: traffic, support, standing water, climate
	var surf0 := 0.0                  ## when the surface it is in was laid
	var ox_k := 0.11                  ## binder ageing rate, 1/years
	var deflects := 0                 ## times it has turned to run along another crack

	## Opening drive from year t0 to t1: thermal cycling and traffic, both worse as the binder hardens
	## (0.4 + 0.9 x oxidation, integrated).
	func _g(t0: float, t1: float) -> float:
		if t1 <= t0:
			return 0.0
		var e0 := exp(-maxf(t0 - surf0, 0.0) * ox_k)
		var e1 := exp(-maxf(t1 - surf0, 0.0) * ox_k)
		return 1.3 * (t1 - t0) - 0.9 * (e0 - e1) / ox_k

	func seal_to() -> float:
		return seal_from + SEAL_LIFE if seal_from >= 0.0 else -1.0

	func sealed(t: float) -> bool:
		return seal_from >= 0.0 and t >= seal_from and t < seal_from + SEAL_LIFE

	## Width of the crack at point i at year t, m: it opens while it is not sealed, at its local rate. Width is
	## separate from growth: the tip grows on its own, the opening comes from cycling, traffic and water.
	func width(i: int, t: float) -> float:
		var b := born[i]
		var open := _g(b, t)
		if seal_from >= 0.0:
			open -= _g(maxf(seal_from, b), minf(t, seal_from + SEAL_LIFE))
			if b < seal_from:
				open -= sealed_before
		var rate := 0.0016 * widen * local
		return clampf(0.001 + rate * maxf(open, 0.0), 0.001, 0.03)


func _ready() -> void:
	reset()


# --- Public ---------------------------------------------------------------------------------------------------

## Rebuild the road as new at year 0 (repairs in `events` are replayed as time passes).
func reset() -> void:
	_rng.seed = seed
	time = 0.0
	surface_born = 0.0
	surface_kind = Surface.HOT_MIX
	rut_born = 0.0
	cracks.clear()
	patches.clear()
	log_lines.clear()
	_latent.clear()
	_transverse_y.clear()
	_last = { }
	_next_event = 0
	_seal_check = INF
	nx = int(round(size.x / CELL))
	ny = int(round(size.y / CELL))
	var n := nx * ny
	for a in [weak, pond, load, fatigue, damage, hole, crack_len, open_len]:
		a.resize(n)
		a.fill(0.0)
	fill_born.resize(n)
	fill_born.fill(-1.0)
	patch_of.resize(n)
	patch_of.fill(-1)
	edge_l.resize(ny)
	edge_l.fill(0.0)
	edge_r.resize(ny)
	edge_r.fill(0.0)
	gx = int(round(size.x / GRID))
	gy = int(round(size.y / GRID))
	occ.resize(gx * gy)
	occ.fill(0)
	occ_pt.resize(gx * gy)
	occ_pt.fill(0)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.35
	noise.fractal_octaves = 3
	var grade := FastNoiseLite.new()
	grade.seed = seed + 101
	grade.frequency = 0.25
	_mix_low.seed = seed + 202
	_mix_low.frequency = 1.0
	_mix_low.fractal_octaves = 2
	_mix_fine.seed = seed + 303
	_mix_fine.frequency = 1.0 / maxf(aggregate_size, 0.002)
	_mix_fine.fractal_octaves = 1
	for cy in ny:
		for cx in nx:
			var i := cy * nx + cx
			var p := Vector2(cx + 0.5, cy + 0.5) * CELL
			weak[i] = clampf(0.5 + 0.9 * noise.get_noise_2d(p.x * 10.0, p.y * 10.0), 0.0, 1.0)
			pond[i] = clampf((grade.get_noise_2d(p.x, p.y) - 0.15) * 2.5, 0.0, 1.0)
			var l := 0.06
			for w in wheel_paths:
				l += exp(-pow((p.x - w) / wheel_path_width, 2.0))
			load[i] = l if paved(p) else 0.0
	_build_networks()
	changed.emit()


## Run the simulation forward to year t (repairs made at t included).
func advance_to(t: float) -> void:
	var stepped := false
	while time + DT * 0.5 <= t:
		_step()
		stepped = true
	if _apply_due() or stepped:
		changed.emit()


## Do the repairs that are due now; true if there were any.
func _apply_due() -> bool:
	var any := false
	while show_repairs and _next_event < events.size() and events[_next_event].t <= time + DT * 0.25:
		_apply(events[_next_event].action)
		_next_event += 1
		any = true
	return any


## Show the road at year t (replays from year 0 when going back).
func seek(t: float) -> void:
	if t < time - DT * 0.5:
		reset()
	advance_to(t)


## Do a repair now and remember it, so it is replayed when scrubbing. Later repairs are dropped (a new timeline).
func do_action(action: int) -> void:
	if not show_repairs:   # bring the hidden repairs back first, so they aren't dropped
		set_show_repairs(true)
	_apply_due()
	while events.size() > _next_event:
		events.pop_back()
	events.append({ t = time, action = action })
	_next_event = events.size()
	_apply(action)
	changed.emit()


## Forget the repairs done by hand and replay to the current year.
func clear_events() -> void:
	events.clear()
	var t := time
	reset()
	advance_to(t)


## Turn the repairs in `events` on or off and replay to the current year, to compare the road with and without them.
func set_show_repairs(on: bool) -> void:
	show_repairs = on
	var t := time
	reset()
	advance_to(t)


func surface_age() -> float:
	return time - surface_born


## How weak the asphalt mix is at p, 0..1: a slow variation over metres plus a stone-by-stone one.
func mix_weakness(p: Vector2) -> float:
	return clampf(0.5 + mix_variation * (0.6 * _mix_low.get_noise_2d(p.x, p.y) + 0.5 * _mix_fine.get_noise_2d(p.x, p.y)), 0.0, 1.0)


## How much paint is left at p, 0..1: it wears with age and traffic (fastest in the wheel paths), in patches.
func paint_left(p: Vector2) -> float:
	var wear := surface_age() * traffic * (0.15 + load[cell_index(p)]) / paint_life
	if wear <= 0.0:
		return 1.0
	# Value noise on a 20 cm grid: some stretches go first.
	var q := p * 5.0
	var i := q.floor()
	var f := q - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var n := lerpf(lerpf(_hash2(i), _hash2(i + Vector2(1, 0)), f.x), lerpf(_hash2(i + Vector2(0, 1)), _hash2(i + Vector2(1, 1)), f.x), f.y)
	return clampf(1.0 - wear * (0.4 + 1.2 * n), 0.0, 1.0)


func _hash2(v: Vector2) -> float:
	return fposmod(sin(v.x * 127.1 + v.y * 311.7 + seed * 17.3) * 43758.5453, 1.0)


## True where the road is asphalt (not shoulder, not fretted away).
func paved(p: Vector2) -> bool:
	if p.y < 0.0 or p.y >= size.y:
		return false
	var row := clampi(int(p.y / CELL), 0, ny - 1)
	var l := shoulder + (edge_l[row] if edge_l.size() > row else 0.0)
	var r := size.x - shoulder - (edge_r[row] if edge_r.size() > row else 0.0)
	return p.x >= l and p.x <= r


func cell_index(p: Vector2) -> int:
	return clampi(int(p.y / CELL), 0, ny - 1) * nx + clampi(int(p.x / CELL), 0, nx - 1)


func cell_center(i: int) -> Vector2:
	return Vector2(i % nx + 0.5, i / nx + 0.5) * CELL


## m the wheel paths have sunk since the last overlay (traffic rutting).
func rut_depth() -> float:
	return minf(0.025, 0.0011 * (time - rut_born) * traffic / structure)


## The road surface as heights in metres (0 = as built, down is negative) on a grid `res` metres apart, for the
## ground's displacement and collision: (size / res + 1) points across X, rows along Y, row-major. Cracks are cut
## at their real width and depth (one narrower than the grid makes a shallower dip), with broken shoulders on wide
## ones; potholes go down to their depth; wheel paths rut; the fretted edge drops to the base course and the
## shoulders sit lower. The outer `edge_feather` metres ease back to 0 so the section meets flat ground.
func bake_height(res := 0.01) -> PackedFloat32Array:
	var w := int(round(size.x / res)) + 1
	var h := int(round(size.y / res)) + 1
	var out := PackedFloat32Array()
	out.resize(w * h)
	# Ruts depend only on X; the shoulders and fretted edge on X and the 10 cm row.
	var rut := PackedFloat32Array()
	rut.resize(w)
	var rd := rut_depth()
	for ix in w:
		var x := ix * res
		var r := 0.0
		for wp in wheel_paths:
			r += exp(-pow((x - wp) / 0.35, 2.0))
		rut[ix] = -rd * r
	var row := PackedFloat32Array()
	row.resize(w)
	for iy in h:
		var y := iy * res
		var cr := clampi(int(y / CELL), 0, ny - 1)
		var l := shoulder + edge_l[cr]
		var r := size.x - shoulder - edge_r[cr]
		for ix in w:
			var x := ix * res
			var v := rut[ix]
			if x < shoulder or x > size.x - shoulder:
				v = shoulder_drop
			elif x < l or x > r:
				v = fret_drop
			row[ix] = v
		for ix in w:
			out[iy * w + ix] = row[ix]
	# Patches and fills sit a few millimetres proud (fresh mix, rolled). They bury every crack that was there
	# before them: `covered` holds the year each pixel was last repaired, and only cracks newer than that cut it.
	var covered := PackedFloat32Array()
	covered.resize(w * h)
	covered.fill(-1.0)
	for p in patches:
		var rect: Rect2 = p.rect
		for iy in range(int(ceil(rect.position.y / res)), int(rect.end.y / res) + 1):
			for ix in range(int(ceil(rect.position.x / res)), int(rect.end.x / res) + 1):
				if iy >= 0 and iy < h and ix >= 0 and ix < w:
					out[iy * w + ix] = 0.003
					covered[iy * w + ix] = maxf(covered[iy * w + ix], p.born)
	# The tar band over a patch's seam stands a hair proud until it debonds.
	for p in patches:
		if time - p.born >= SEAL_LIFE * 1.5:
			continue
		var rect: Rect2 = p.rect
		var outer := rect.grow(0.035)
		var inner := rect.grow(-0.035)
		for iy in range(maxi(0, int(outer.position.y / res)), mini(h - 1, int(ceil(outer.end.y / res))) + 1):
			for ix in range(maxi(0, int(outer.position.x / res)), mini(w - 1, int(ceil(outer.end.x / res))) + 1):
				var q := Vector2(ix * res, iy * res)
				if outer.has_point(q) and not inner.has_point(q):
					out[iy * w + ix] += SEAL_PROUD
	for i in nx * ny:
		if fill_born[i] >= 0.0:
			# Lumpy: each shovelful packed down a different amount.
			var lump := 0.004 + 0.004 * fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			_stamp_disk(out, w, h, res, cell_center(i), 0.12, lump, false)
			_stamp_disk(covered, w, h, res, cell_center(i), 0.1, fill_born[i], false)
	# Paint stands a hair proud where it is left (not under a patch or fill); cracks still cut through it.
	var half_w := paint_width * 0.5
	var painted := PackedByteArray()
	if not paint_lines.is_empty():
		painted.resize(w * h)
	for k in range(0, paint_lines.size() - 1, 2):
		var a := paint_lines[k]
		var b := paint_lines[k + 1]
		var x0 := maxi(0, int((minf(a.x, b.x) - half_w) / res))
		var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + half_w) / res)))
		var y0 := maxi(0, int((minf(a.y, b.y) - half_w) / res))
		var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + half_w) / res)))
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1e-10)
		for iy in range(y0, y1 + 1):
			for ix in range(x0, x1 + 1):
				var q := Vector2(ix * res, iy * res)
				var j := iy * w + ix
				if painted[j] == 0 and covered[j] < 0.0 and q.distance_to(a + ab * clampf((q - a).dot(ab) / len2, 0.0, 1.0)) <= half_w:
					out[j] += paint_thickness * paint_left(q)
					painted[j] = 1
	# Filled cracks: the sealant fills the crack flush and the overband stands a little proud, until it debonds.
	var surface := PackedFloat32Array(out)
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or not c.sealed(time):
			continue
		for k in c.pts.size() - 1:
			var half := 0.03 + c.width(k, c.seal_from)
			var a := c.pts[k]
			var b := c.pts[k + 1]
			var x0 := maxi(0, int((minf(a.x, b.x) - half) / res))
			var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + half) / res)))
			var y0 := maxi(0, int((minf(a.y, b.y) - half) / res))
			var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + half) / res)))
			var ab := b - a
			var len2 := maxf(ab.length_squared(), 1e-10)
			for iy in range(y0, y1 + 1):
				for ix in range(x0, x1 + 1):
					var q := Vector2(ix * res, iy * res)
					var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
					if q.distance_to(a + ab * t) <= half:
						var j := iy * w + ix
						out[j] = maxf(out[j], surface[j] + SEAL_PROUD)
	# Open cracks.
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or c.sealed(time):
			continue
		for k in c.pts.size() - 1:
			var cw := c.width(k, time)
			var depth := clampf(cw * 4.0, 0.004, 0.05)
			var half := cw * 0.5
			var spall := (minf(cw * 2.2 + 0.008, 0.06) * 0.5) if cw > 0.005 else 0.0
			var reach := maxf(maxf(half, spall), res * 0.75)
			var a := c.pts[k]
			var b := c.pts[k + 1]
			var x0 := maxi(0, int((minf(a.x, b.x) - reach) / res))
			var x1 := mini(w - 1, int(ceil((maxf(a.x, b.x) + reach) / res)))
			var y0 := maxi(0, int((minf(a.y, b.y) - reach) / res))
			var y1 := mini(h - 1, int(ceil((maxf(a.y, b.y) + reach) / res)))
			var ab := b - a
			var len2 := maxf(ab.length_squared(), 1e-10)
			for iy in range(y0, y1 + 1):
				for ix in range(x0, x1 + 1):
					var q := Vector2(ix * res, iy * res)
					var t := clampf((q - a).dot(ab) / len2, 0.0, 1.0)
					var d := q.distance_to(a + ab * t)
					var v := 0.0
					if d <= maxf(half, res * 0.5):
						v = -depth * minf(1.0, cw / res)   # narrower than a grid step: a shallower dip
					elif d <= spall:
						v = -spall_depth * (1.0 - (d - half) / maxf(spall - half, 1e-4))
					var j := iy * w + ix
					if v < out[j] and c.born[k + 1] > covered[j]:
						out[j] = v
	# Potholes: whole crocodile cells plucked out, steep-sided, down to the hole's depth; a disk where no cell is.
	for k in plucked.size():
		if plucked[k] <= 0.0 or net_cells[k].is_empty():
			continue
		var poly := net_cells[k]
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		for iy in range(maxi(0, int(bb.position.y / res)), mini(h - 1, int(ceil(bb.end.y / res))) + 1):
			for ix in range(maxi(0, int(bb.position.x / res)), mini(w - 1, int(ceil(bb.end.x / res))) + 1):
				var q := Vector2(ix * res, iy * res)
				if Geometry2D.is_point_in_polygon(q, poly):
					var j := iy * w + ix
					out[j] = minf(out[j], -plucked[k])
	for i in nx * ny:
		if hole[i] > 0.0 and (_cell_seed[i] < 0):
			_stamp_disk(out, w, h, res, cell_center(i), 0.1, -hole[i], true)
	# Ease the outer edge back to 0.
	var n := int(edge_feather / res)
	if n > 0:
		for iy in h:
			for ix in w:
				var e := mini(mini(ix, w - 1 - ix), mini(iy, h - 1 - iy))
				if e < n:
					out[iy * w + ix] *= smoothstep(0.0, 1.0, float(e) / n)
	return out


func _stamp_disk(out: PackedFloat32Array, w: int, h: int, res: float, c: Vector2, r: float, v: float, down: bool) -> void:
	var x0 := maxi(0, int((c.x - r) / res))
	var x1 := mini(w - 1, int(ceil((c.x + r) / res)))
	var y0 := maxi(0, int((c.y - r) / res))
	var y1 := mini(h - 1, int(ceil((c.y + r) / res)))
	for iy in range(y0, y1 + 1):
		for ix in range(x0, x1 + 1):
			var d := Vector2(ix * res, iy * res).distance_to(c)
			if d > r:
				continue
			# Steep broken walls: full depth inside 70 % of the radius.
			var hv := v * smoothstep(r, r * 0.7, d)
			var j := iy * w + ix
			if down:
				out[j] = minf(out[j], hv)
			else:
				out[j] = maxf(out[j], hv)


## Rough condition numbers for the lab panel.
func stats() -> Dictionary:
	var by_kind := PackedFloat32Array()
	by_kind.resize(Kind.size())
	var open := 0.0
	var wide := 0.0
	for c in cracks:
		if not c.alive:
			continue
		by_kind[c.kind] += c.length
		if not c.sealed(time):
			open += c.length
			if c.pts.size() > 0 and c.width(0, time) > 0.003:
				wide += c.length
	var paved_cells := 0
	var alligator := 0
	var holes := 0
	var filled := 0
	var patched := 0
	for i in nx * ny:
		var p := cell_center(i)
		if not paved(p):
			continue
		paved_cells += 1
		if hole[i] > 0.0:
			holes += 1
		if fill_born[i] >= 0.0:
			filled += 1
		if patch_of[i] >= 0:
			patched += 1
		if fatigue[i] > FATIGUE_CELLS and crack_len[i] > 0.08:
			alligator += 1
	var area := maxf(paved_cells, 1) * CELL * CELL
	var pct := func(cells: int) -> float: return 100.0 * cells / maxf(paved_cells, 1)
	# A rough pavement condition index (100 = new), loosely after the ASTM D6433 deduct idea.
	var pci := 100.0
	pci -= minf(35.0, open / area * 12.0)
	pci -= minf(35.0, pct.call(alligator) * 1.2)
	pci -= minf(30.0, pct.call(holes) * 6.0)
	pci -= minf(10.0, (pct.call(patched) + pct.call(filled)) * 0.2)
	pci -= minf(10.0, clampf((surface_age() - 8.0) / 3.0, 0.0, 10.0) * climate)
	return {
		year = time, surface_age = surface_age(), crack_m = open, wide_crack_m = wide, by_kind = by_kind,
		alligator_pct = pct.call(alligator), pothole_pct = pct.call(holes), potholes = _count_clusters(),
		filled_pct = pct.call(filled), patched_pct = pct.call(patched), pci = clampf(pci, 0.0, 100.0),
		cracks = cracks.size(),
	}


# --- Simulation step ------------------------------------------------------------------------------------------

func _step() -> void:
	_apply_due()
	if auto_maintain:
		_auto_maintain()
	var age := surface_age()
	var ox := 1.0 - exp(-age * climate / oxidation_years)
	_fatigue_and_water(ox)
	_initiate(age, ox)
	for i in cracks.size():
		var c := cracks[i]
		if c.alive and c.growing and not c.sealed(time):
			_grow(i, c.speed * DT * (0.6 + 0.4 * climate))
	_reflect()
	_edges(age)
	time += DT
	if time >= _seal_check:
		_seal_check = INF
		_rebuild_lengths()


func _fatigue_and_water(ox: float) -> void:
	var k_f := 0.085 * traffic / structure
	var k_d := 0.6 * drainage * climate
	for i in nx * ny:
		if load[i] <= 0.0:
			continue
		# Water in the base: through open cracks, and standing in low spots.
		var wet := (clampf(open_len[i] / 0.1, 0.0, 2.0) + pond[i] * ponding) * drainage
		# Traffic fatigue: wheel load on a weak, wet base, worse once the binder is brittle.
		var f_rate := k_f * load[i] * (0.55 + 0.9 * weak[i]) * (1.0 + 0.6 * wet) * (0.8 + 0.4 * ox)
		if patch_of[i] >= 0:
			f_rate *= 0.6     # new full-depth base
		fatigue[i] += DT * f_rate
		# Water damage: water through open cracks softens the base and freeze-thaw pumps it out.
		if open_len[i] > 0.0 or pond[i] > 0.0 or hole[i] > 0.0 or fill_born[i] >= 0.0:
			# Only broken-up (fatigue-cracked) asphalt lets the wheels pump the base out through it.
			var broken := clampf((fatigue[i] - 1.4) / 0.6, 0.0, 1.5)
			# Potholes need all three: water getting in (open cracks, standing water), a structure already broken up,
			# and wheels to pump it.
			var water := maxf(open_len[i] - 0.05, 0.0) + 0.06 * pond[i] * ponding
			var d_rate := k_d * water * (0.3 + load[i]) * (0.4 + weak[i]) * broken
			if fill_born[i] >= 0.0:
				d_rate += 0.12 * climate * drainage * (0.4 + load[i])   # cold mix ravels out of the hole
			damage[i] += DT * d_rate
	# Potholes break out where the water damage is done, then deepen and eat into their neighbours.
	for i in nx * ny:
		if load[i] <= 0.0:
			continue
		if hole[i] > 0.0:
			hole[i] = minf(HOLE_MAX, hole[i] + DT * 0.03 * (0.5 + load[i]) * climate)
			_pluck(i)
			var cx := i % nx
			var cy := i / nx
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x := cx + o.x
				var y := cy + o.y
				if x < 0 or y < 0 or x >= nx or y >= ny:
					continue
				var j := y * nx + x
				if load[j] > 0.0 and patch_of[j] == patch_of[i] and crack_len[j] > 0.02:
					damage[j] += DT * 0.18 * (0.3 + load[j]) * climate * drainage * (0.5 + weak[j])
		elif damage[i] >= 1.0:
			hole[i] = 0.012
			_pluck(i)


func _initiate(age: float, ox: float) -> void:
	var px0 := shoulder
	var px1 := size.x - shoulder
	# Transverse (thermal) cracks: once the binder hardens, cold snaps crack it across. Each crack relieves the
	# shrinkage stress for a stretch either side, so a new one opens in the middle of the longest uncracked stretch,
	# once that is long enough; the spacing shrinks as the binder hardens.
	if age > 1.5:
		var rate := 0.8 * climate * ox * (1.4 - 0.4 * structure)
		if _rng.randf() < rate * DT:
			# Colder climates and thinner pavement crack closer together.
			var spacing := lerpf(thermal_spacing.x, thermal_spacing.y, ox) * sqrt(structure) / sqrt(maxf(climate, 0.25))
			var ys := PackedFloat32Array(_transverse_y)
			ys.sort()
			# The section is part of a longer road: its ends count as half a spacing from the last crack.
			var prev := -spacing * 0.5
			var best_gap := 0.0
			var best_y := -1.0
			ys.append(size.y + spacing * 0.5)
			for y in ys:
				if y - prev > best_gap:
					best_gap = y - prev
					best_y = (prev + y) * 0.5 + _rng.randf_range(-0.2, 0.2) * (y - prev)
				prev = y
			if best_gap > 1.6 * spacing and best_y > 0.2 and best_y < size.y - 0.2:
				_transverse_y.append(best_y)
				var x := _rng.randf_range(px0 + 0.3, px1 - 0.3)
				_twin(Kind.TRANSVERSE, Vector2(x, best_y), 0.0, 0.12, 0.08, 3.5, 1.3)
	# The lane joint: the paving seam opens early.
	if age > 0.8 and _rng.randf() < 0.45 * climate * DT:
		var y := _rng.randf_range(0.2, size.y - 0.2)
		var p := Vector2(lane_joint_x + _rng.randf_range(-0.02, 0.02), y)
		if _free(p, 0.15):
			_twin(Kind.JOINT, p, PI * 0.5, 0.05, 0.35, 1.2, 1.0)
	# Wheel-path cracks where fatigue has built up, branching into alligator cells as it goes on.
	for i in nx * ny:
		var f := fatigue[i]
		if f < 1.0 or load[i] < 0.25:
			continue
		var p := cell_center(i) + Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * CELL
		if not paved(p):
			continue
		if crack_len[i] < 0.01:
			if _rng.randf() < DT * 0.2 * (f - 0.9) and _free(p, 0.08):
				var c := _twin(Kind.WHEELPATH, p, PI * 0.5, 0.2, 0.12, 0.5 + 0.3 * f, 0.9)
				for k in [c, c - 1]:
					cracks[k].max_len = _rng.randf_range(0.8, 2.5)
	# Fatigue (crocodile) cells in the wheel paths and block cracking across the road: edges of the networks open.
	_open_edges(age, ox)
	# Edge cracking near the unsealed shoulders.
	if unsealed_edges and age > 3.0:
		var rate := 0.5 * traffic * climate * drainage / structure * clampf((age - 3.0) / 6.0, 0.0, 1.0)
		if _rng.randf() < rate * DT:
			var left := _rng.randf() < 0.5
			var y := _rng.randf_range(0.2, size.y - 0.2)
			var row := clampi(int(y / CELL), 0, ny - 1)
			var x := shoulder + edge_l[row] + 0.03 if left else size.x - shoulder - edge_r[row] - 0.03
			var inward := 0.0 if left else PI
			var along := PI * 0.5 if _rng.randf() < 0.5 else -PI * 0.5
			var d := lerp_angle(inward, along, _rng.randf_range(0.3, 0.6))
			_crack(Kind.EDGE, Vector2(x, y), d, along, 0.25, 0.06, 0.7, _rng.randf_range(0.4, 1.6), 1.4)
	# Slippage: crescents in sets where the wearing course slides on a poor bond.
	if age > 1.0 and bond < 0.95:
		if _rng.randf() < 0.25 * (1.0 - bond) * (1.0 - bond) * traffic * DT * 4.0:
			_slippage()


func _slippage() -> void:
	var w := wheel_paths[_rng.randi_range(0, wheel_paths.size() - 1)]
	var y := _rng.randf_range(0.8, size.y - 0.8)
	# Lanes left of the joint travel -Y, right of it +Y; crescents point the way the wheels shove the mat.
	var fwd := -1.0 if w < lane_joint_x else 1.0
	var r := _rng.randf_range(0.35, 0.7)
	var span := _rng.randf_range(1.6, 2.3)
	var n := _rng.randi_range(2, 4)
	for k in n:
		var centre := Vector2(w, y - fwd * k * _rng.randf_range(0.08, 0.14))
		var c := _new_crack(Kind.SLIPPAGE, centre)
		c.growing = false
		c.widen = 0.6
		r *= _rng.randf_range(0.85, 1.15)
		var a0 := (PI * 0.5 if fwd > 0 else -PI * 0.5) - span * 0.5
		var steps := int(r * span / STEP)
		for s in steps + 1:
			var a := a0 + span * s / steps
			var q := centre - Vector2(0, fwd * r * 0.6) + Vector2(cos(a), sin(a)) * Vector2(r, r * 0.6) \
				+ Vector2(_rng.randf_range(-0.012, 0.012), _rng.randf_range(-0.012, 0.012))
			if not paved(q):
				continue
			c.pts.append(q)
			c.born.append(time)
		if c.pts.size() > 3:
			for j in c.pts.size() - 1:
				c.length += c.pts[j].distance_to(c.pts[j + 1])
			_add_points(c, cracks.size(), 0)
			cracks.append(c)


## A new crack's opening rate from where it starts, and the surface's age.
func _new_crack(kind: int, p: Vector2) -> Crack:
	var c := Crack.new()
	c.kind = kind
	c.surf0 = surface_born
	c.ox_k = maxf(climate, 0.05) / oxidation_years
	var i := cell_index(p)
	c.local = (0.5 + 0.5 * climate) * (0.45 + 0.45 * minf(load[i], 1.5) * traffic + 0.3 * weak[i]
		+ 0.4 * pond[i] * ponding * drainage)
	return c


## Two cracks growing opposite ways from one start; returns the second's index.
func _twin(kind: int, p: Vector2, heading: float, wander: float, steer: float, speed: float, widen: float) -> int:
	var a := _crack(kind, p, heading, heading, wander, steer, speed, 1e9, widen)
	var b := _crack(kind, p, heading + PI, heading + PI, wander, steer, speed, 1e9, widen)
	cracks[a].twin = b
	cracks[b].twin = a
	return b


func _crack(kind: int, p: Vector2, heading: float, pref: float, wander: float, steer: float, speed: float,
		max_len: float, widen: float) -> int:
	var c := _new_crack(kind, p)
	c.dir = heading
	c.pref = pref
	c.wander = wander
	c.steer = steer
	c.speed = speed
	c.max_len = max_len
	c.widen = widen * _rng.randf_range(0.7, 1.3)
	c.pts.append(p)
	c.born.append(time)
	cracks.append(c)
	return cracks.size() - 1


func _grow(ci: int, dist: float) -> void:
	var c := cracks[ci]
	c.carry += dist
	while c.carry >= STEP and c.growing:
		c.carry -= STEP
		var p := c.pts[c.pts.size() - 1]
		var q: Vector2
		if c.guide.size() > 0:
			if c.guide_i >= c.guide.size():
				c.growing = false
				break
			q = c.guide[c.guide_i] + Vector2(_rng.randf_range(-0.004, 0.004), _rng.randf_range(-0.004, 0.004))
			c.guide_i += 1
		else:
			var d := c.dir + _rng.randfn(0.0, c.wander) + angle_difference(c.dir, c.pref) * c.steer
			# The tip takes the weakest way of three: around the stones, through the poorly compacted mix.
			if crack_bias > 0.0:
				var best := -INF
				var pick := d
				for o in [-0.45, 0.0, 0.45]:
					var score := mix_weakness(p + Vector2.from_angle(d + o) * STEP) * crack_bias * 3.0 - absf(o) * 0.8 \
						+ _rng.randf() * 0.3
					if score > best:
						best = score
						pick = d + o
				d = pick
			c.dir = d
			q = p + Vector2.from_angle(c.dir) * STEP
		if not paved(q) or patch_of[cell_index(q)] != patch_of[cell_index(p)] and c.kind != Kind.SEAM:
			c.growing = false
			break
		if c.guide.is_empty():
			var hit := _hit(q, ci, c)
			if hit.x >= 0:
				var other := cracks[hit.x]
				var r := _rng.randf()
				if r < t_junctions or c.deflects >= 3 or other.pts.size() < 2:
					# Runs into it and stops at a T: the other crack's free edge takes the stress off.
					q = other.pts[mini(hit.y, other.pts.size() - 1)]
					_append(c, ci, q)
					c.growing = false
					break
				if r < t_junctions + stop_short:
					# Dies out just short of it, in the other crack's stress shadow.
					c.growing = false
					break
				# Turns and runs alongside it for a while before joining.
				var k := clampi(hit.y, 1, other.pts.size() - 1)
				var along := (other.pts[k] - other.pts[k - 1]).angle()
				if absf(angle_difference(c.dir, along)) > PI * 0.5:
					along += PI
				c.dir = lerp_angle(c.dir, along, 0.7)
				c.pref = along
				c.deflects += 1
				continue
		_append(c, ci, q)
		# Now and then a side branch splits off (more as the binder gets brittle).
		if c.guide.is_empty() and branching > 0.0 and c.kind != Kind.SLIPPAGE \
				and _rng.randf() < branching * STEP * (0.5 + c.local * 0.5):
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var b := _crack(c.kind, q, c.dir + side * _rng.randf_range(0.5, 1.0), c.pref + side * 0.6,
				c.wander * 1.5, c.steer * 0.5, c.speed * 0.8, _rng.randf_range(0.15, 0.9), c.widen * 0.7)
			cracks[b].parent = ci
			c = cracks[ci]
		if c.length >= c.max_len:
			c.growing = false


func _append(c: Crack, ci: int, q: Vector2) -> void:
	var p := c.pts[c.pts.size() - 1]
	c.length += p.distance_to(q)
	c.pts.append(q)
	c.born.append(time)
	_add_points(c, ci, c.pts.size() - 1)


## Mark points from index `from` on in the grids.
func _add_points(c: Crack, ci: int, from: int) -> void:
	for k in range(from, c.pts.size()):
		var q := c.pts[k]
		var seg := q.distance_to(c.pts[k - 1]) if k > 0 else 0.0
		if k > 0:
			_mark((q + c.pts[k - 1]) * 0.5, ci, k)
		_mark(q, ci, k)
		var i := cell_index(q)
		crack_len[i] += seg
		if not c.sealed(time):
			open_len[i] += seg


func _mark(q: Vector2, ci: int, k: int) -> void:
	var g := _grid(q)
	if g >= 0:
		occ[g] = ci + 1
		occ_pt[g] = k


func _grid(q: Vector2) -> int:
	var x := int(q.x / GRID)
	var y := int(q.y / GRID)
	if x < 0 or y < 0 or x >= gx or y >= gy:
		return -1
	return y * gx + x


## Another crack within a grid cell of q: Vector2i(crack, point), or x = -1.
func _hit(q: Vector2, ci: int, c: Crack) -> Vector2i:
	var x := int(q.x / GRID)
	var y := int(q.y / GRID)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= gx or yy >= gy:
				continue
			var g := yy * gx + xx
			var o := occ[g] - 1
			if o < 0 or o == ci or o == c.twin:
				continue
			if o == c.parent and c.pts.size() < 5:
				continue
			if not cracks[o].alive:
				continue
			return Vector2i(o, occ_pt[g])
	return Vector2i(-1, -1)


func _free(p: Vector2, r: float) -> bool:
	var n := int(ceil(r / GRID))
	var x := int(p.x / GRID)
	var y := int(p.y / GRID)
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and yy >= 0 and xx < gx and yy < gy and occ[yy * gx + xx] != 0:
				return false
	return true


func _reflect() -> void:
	for k in range(_latent.size() - 1, -1, -1):
		var l: Dictionary = _latent[k]
		if time < l.at:
			continue
		_latent.remove_at(k)
		var path: PackedVector2Array = l.path
		if path.size() < 3:
			continue
		var c := _new_crack(l.get("kind", Kind.REFLECTION), path[0])
		c.speed = l.get("speed", 1.5)
		c.widen = l.get("widen", 1.1)
		c.guide = path
		c.guide_i = 1
		c.pts.append(path[0])
		c.born.append(time)
		cracks.append(c)


func _edges(age: float) -> void:
	if not unsealed_edges or age < 4.0:
		return
	# Fretting: traffic on the unsupported edge breaks it off into the shoulder, row by row.
	var k := 0.025 * traffic * climate * drainage / structure * clampf((age - 4.0) / 6.0, 0.0, 1.0)
	for row in ny:
		var y := (row + 0.5) * CELL
		for side in 2:
			var e: PackedFloat32Array = edge_l if side == 0 else edge_r
			var x := shoulder + e[row] + 0.05 if side == 0 else size.x - shoulder - e[row] - 0.05
			var i := cell_index(Vector2(x, y))
			var rate := k * (0.3 + 1.4 * weak[i]) * (1.0 + 2.0 * clampf(open_len[i] / 0.1, 0.0, 1.0))
			if _rng.randf() < 0.3:
				e[row] = minf(e[row] + rate * DT * _rng.randf_range(1.0, 4.0), 0.6)
	# Edge loss of neighbouring rows pulls each other a little (no single-row notches).
	for side in 2:
		var e: PackedFloat32Array = edge_l if side == 0 else edge_r
		for row in range(1, ny - 1):
			e[row] = maxf(e[row], (e[row - 1] + e[row + 1]) * 0.5 - 0.02)



# --- Crack networks ---------------------------------------------------------------------------------------------

func _build_networks() -> void:
	_net_edges.clear()
	net_cells.clear()
	# Fatigue cells: about 14 x 20 cm (crocodile skin has a longitudinal grain), over each wheel path.
	var seeds := PackedVector2Array()
	for wp in wheel_paths:
		var x0 := wp - wheel_path_width * 1.3
		var cols := int(round(wheel_path_width * 2.6 / fatigue_cell.x))
		var rows := int(ceil(size.y / fatigue_cell.y)) + 1
		for r in rows:
			for c in cols + 1:
				var p := Vector2(x0 + c * fatigue_cell.x, (r - 0.5) * fatigue_cell.y) \
					+ Vector2(_rng.randf_range(-0.4, 0.4) * fatigue_cell.x, _rng.randf_range(-0.4, 0.4) * fatigue_cell.y)
				if paved(p):
					seeds.append(p)
	net_seeds = seeds
	plucked.resize(seeds.size())
	plucked.fill(0.0)
	_add_network(seeds, Kind.FATIGUE, fatigue_cell.y * 2.2, true)
	# Block cells: about 1.6 x 2.2 m, little jitter so they come out nearly rectangular.
	var bs := PackedVector2Array()
	var bcols := int(ceil((size.x - 2.0 * shoulder) / block_cell.x)) + 1
	var brows := int(ceil(size.y / block_cell.y)) + 2
	for r in brows:
		for c in bcols:
			bs.append(Vector2(shoulder + (c + _rng.randf_range(-0.12, 0.12)) * block_cell.x,
				(r - 1 + _rng.randf_range(-0.12, 0.12)) * block_cell.y))
	_add_network(bs, Kind.BLOCK, block_cell.y * 2.5, false)
	# Which fatigue cell is over each 10 cm cell (potholes pluck whole cells out).
	_cell_seed.resize(nx * ny)
	_cell_seed.fill(-1)
	for k in seeds.size():
		var q := seeds[k]
		var r := int(ceil(maxf(fatigue_cell.x, fatigue_cell.y) / CELL))
		var cx := int(q.x / CELL)
		var cy := int(q.y / CELL)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= nx or y >= ny:
					continue
				var i := y * nx + x
				var cur := _cell_seed[i]
				if cur < 0 or cell_center(i).distance_squared_to(seeds[cur]) > cell_center(i).distance_squared_to(q):
					_cell_seed[i] = k
	for i in nx * ny:
		var k := _cell_seed[i]
		if k >= 0 and (cell_center(i).distance_to(seeds[k]) > maxf(fatigue_cell.x, fatigue_cell.y) or net_cells[k].is_empty()):
			_cell_seed[i] = -1


## Voronoi edges of `pts` (from their Delaunay triangles) as closed-off crack paths; edges longer than `max_len`
## (the open rim) are dropped. With `cells`, also each point's cell outline.
func _add_network(pts: PackedVector2Array, kind: int, max_len: float, cells: bool) -> void:
	var tri := Geometry2D.triangulate_delaunay(pts)
	var centers := PackedVector2Array()
	var n := tri.size() / 3
	var by_edge := { }
	var around: Array[PackedInt32Array] = []
	if cells:
		around.resize(pts.size())
	for t in n:
		var a := pts[tri[t * 3]]
		var b := pts[tri[t * 3 + 1]]
		var c := pts[tri[t * 3 + 2]]
		centers.append(_circumcenter(a, b, c))
		for e in 3:
			var i := tri[t * 3 + e]
			var j := tri[t * 3 + (e + 1) % 3]
			var key := mini(i, j) * pts.size() + maxi(i, j)
			if by_edge.has(key):
				by_edge[key].append(t)
			else:
				by_edge[key] = [t]
			if cells:
				around[i].append(t)
	for key in by_edge:
		var ts: Array = by_edge[key]
		if ts.size() != 2:
			continue
		var a: Vector2 = centers[ts[0]]
		var b: Vector2 = centers[ts[1]]
		if a.distance_to(b) > max_len or a.distance_to(b) < 0.02:
			continue
		_net_edges.append({ a = a, b = b, kind = kind, thr = _rng.randf(), on = false, ci = cell_index((a + b) * 0.5) })
	if cells:
		for i in pts.size():
			var ring := PackedVector2Array()
			var ok := around[i].size() >= 3
			var angs := []
			for t in around[i]:
				var c := centers[t]
				if c.distance_to(pts[i]) > max_len:
					ok = false
				angs.append([(c - pts[i]).angle(), c])
			if ok:
				angs.sort_custom(func(u: Array, v: Array) -> bool: return u[0] < v[0])
				for av in angs:
					ring.append(av[1])
				# A cell on the rim of the network is open on one side: its ring of corners has a gap.
				var gap := false
				for k in ring.size():
					if ring[k].distance_to(ring[(k + 1) % ring.size()]) > max_len:
						gap = true
				if gap:
					ring = PackedVector2Array()
			net_cells.append(ring)


func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-9:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


## Open the network edges whose stress has passed their threshold. Fatigue edges go when the fatigue at their
## middle passes FATIGUE_CELLS (plus up to 0.35 more, per edge); block edges when the binder's oxidation passes
## block_onset (plus up to 0.45). An edge opens from an end that touches a crack, so the cracking spreads out
## from the wheel-path cracks and the long cracks; now and then one starts on its own.
func _open_edges(age: float, ox: float) -> void:
	# Block cracking is the same everywhere, so its threshold is worked out once a step.
	var block_level := ox * climate * (1.25 - 0.25 * structure) if age > 5.0 else -1.0
	for e in _net_edges:
		if e.on:
			continue
		if e.kind == Kind.FATIGUE:
			if fatigue[e.ci] <= FATIGUE_CELLS + 0.35 * e.thr:
				continue
		elif block_level <= block_onset + 0.45 * e.thr:
			continue
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		if not paved((a + b) * 0.5):
			continue
		var touch_a := not _free(a, 0.03)
		var touch_b := not _free(b, 0.03)
		# Crocodile cells grow out of the wheel-path cracks: an edge touching no crack rarely opens on its own.
		if not touch_a and not touch_b and _rng.randf() > DT * (0.12 if e.kind == Kind.FATIGUE else 0.3):
			continue
		e.on = true
		var from := b if touch_b and not touch_a else a
		var to := a if from == b else b
		var c := _new_crack(e.kind, from)
		c.speed = 1.2 if e.kind == Kind.FATIGUE else 2.0
		c.widen = 1.3 if e.kind == Kind.FATIGUE else 1.0   # crocodile cells rock under every wheel and open fast
		c.guide = _wobble(from, to, 0.012 if e.kind == Kind.FATIGUE else 0.07)
		c.guide_i = 1
		c.pts.append(from)
		c.born.append(time)
		cracks.append(c)
		_mark(from, cracks.size() - 1, 0)


## A path from a to b, STEP apart, wandering up to `amp` m either side (ends fixed).
func _wobble(a: Vector2, b: Vector2, amp: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	var n := maxi(2, int(a.distance_to(b) / STEP))
	var side := (b - a).orthogonal().normalized()
	var p1 := _rng.randf() * TAU
	var p2 := _rng.randf() * TAU
	var k1 := _rng.randf_range(1.0, 2.0)
	var k2 := _rng.randf_range(2.5, 4.5)
	for k in n + 1:
		var t := float(k) / n
		var off := amp * sin(PI * t) * (0.7 * sin(TAU * k1 * t + p1) + 0.3 * sin(TAU * k2 * t + p2))
		off += _rng.randf_range(-0.002, 0.002) if k > 0 and k < n else 0.0
		path.append(a.lerp(b, t) + side * off)
	return path


## A pothole in this 10 cm cell plucks out the fatigue cell over it.
func _pluck(i: int) -> void:
	var k := _cell_seed[i] if _cell_seed.size() > i else -1
	if k >= 0:
		plucked[k] = maxf(plucked[k], hole[i])

# --- Repairs --------------------------------------------------------------------------------------------------

func _apply(action: int) -> void:
	_last[action] = time
	var note := ""
	match action:
		Action.CRACK_FILL:
			note = _crack_fill()
		Action.POTHOLE_FILL:
			note = _pothole_fill()
		Action.HEAVY_PATCH:
			note = _heavy_patch()
		Action.SURFACE_SEAL:
			note = _resurface(Surface.CHIP_SEAL)
		Action.OVERLAY:
			note = _resurface(Surface.HOT_MIX)
	log_lines.append("Year %.1f  %s: %s" % [time, ACTION_NAMES[action], note])
	_rebuild_lengths()


## Crack filling: hot rubberised sealant poured into every crack wider than a hairline, overbanded on top.
## The sealant stops water and stops the crack opening, until it debonds after SEAL_LIFE years.
func _crack_fill() -> String:
	var n := 0
	var m := 0.0
	for c in cracks:
		if not c.alive or c.pts.size() < 2 or c.sealed(time):
			continue
		if c.width(0, time) < 0.0015 and c.kind != Kind.TRANSVERSE:
			continue
		if c.seal_from >= 0.0:
			c.sealed_before += c._g(c.seal_from, minf(time, c.seal_to()))
		c.seal_from = time
		n += 1
		m += c.length
		_seal_check = minf(_seal_check, time + SEAL_LIFE)
	return "%d cracks, %.0f m" % [n, m]


## Throw-and-roll: cold mix shovelled into each pothole and rolled with the truck tyre. Cheap and quick, and
## water gets in round its edges, so it tends to ravel out again in a year or three.
func _pothole_fill() -> String:
	var n := _count_clusters()
	var filled := PackedInt32Array()
	for i in nx * ny:
		if hole[i] > 0.0:
			filled.append(i)
	for i in filled:
		if _cell_seed[i] >= 0:
			plucked[_cell_seed[i]] = 0.0
		hole[i] = 0.0
		fill_born[i] = time
		damage[i] = 0.35
		# The crew shovels the mix a little past the broken edge.
		for o in [1, -1, nx, -nx]:
			var j: int = i + o
			if j >= 0 and j < nx * ny and hole[j] <= 0.0:
				damage[j] = minf(damage[j], 0.6)
	return "%d potholes" % n


## Heavy patching: saw-cut a rectangle round each area of fatigue cells and potholes, dig out the failed asphalt
## and base, and replace it full depth. Cracks inside are gone; the cut edges are joints that crack open later.
func _heavy_patch() -> String:
	# The crew cuts round the failed spots (potholes, fills, the worst crocodile cracking), not whole wheel paths.
	var bad := PackedByteArray()
	bad.resize(nx * ny)
	for i in nx * ny:
		if load[i] > 0.0 and (hole[i] > 0.0 or fill_born[i] >= 0.0 \
				or fatigue[i] > FATIGUE_CELLS + 0.7 and crack_len[i] > 0.15):
			bad[i] = 1
	var rects: Array[Rect2] = []
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	for i in nx * ny:
		if bad[i] == 0 or seen[i] == 1:
			continue
		var r := Rect2(cell_center(i), Vector2.ZERO)
		var stack := [i]
		seen[i] = 1
		var count := 0
		while not stack.is_empty():
			var j: int = stack.pop_back()
			count += 1
			r = r.expand(cell_center(j) - Vector2.ONE * CELL * 0.5).expand(cell_center(j) + Vector2.ONE * CELL * 0.5)
			var cx := j % nx
			var cy := j / nx
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var y := cy + dy
					if x >= 0 and y >= 0 and x < nx and y < ny and bad[y * nx + x] == 1 and seen[y * nx + x] == 0:
						seen[y * nx + x] = 1
						stack.append(y * nx + x)
		if count < 2:
			continue
		rects.append(r.grow(0.3))
	# Merge overlapping cuts into one, square to the road and on a 5 cm grid, inside the pavement.
	var merged := true
	while merged:
		merged = false
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				if rects[a].grow(0.05).intersects(rects[b]):
					rects[a] = rects[a].merge(rects[b])
					rects.remove_at(b)
					merged = true
					break
			if merged:
				break
	var made := 0
	for r in rects:
		var p0 := (r.position / 0.05).floor() * 0.05
		var p1 := (r.end / 0.05).ceil() * 0.05
		p0.x = maxf(p0.x, shoulder + 0.05)
		p1.x = minf(p1.x, size.x - shoulder - 0.05)
		p0.y = maxf(p0.y, 0.0)
		p1.y = minf(p1.y, size.y)
		var rect := Rect2(p0, p1 - p0)
		if rect.size.x < 0.3 or rect.size.y < 0.3:
			continue
		var id := patches.size()
		var seams := PackedFloat32Array()
		for s in 4:
			seams.append(time + _rng.randf_range(2.0, 6.0) * structure)
		patches.append({ rect = rect, born = time, seams_at = seams })
		made += 1
		for i in nx * ny:
			var c := cell_center(i)
			if rect.has_point(c):
				patch_of[i] = id
				fatigue[i] = 0.0
				damage[i] = 0.0
				hole[i] = 0.0
				fill_born[i] = -1.0
				weak[i] *= 0.4
				if _cell_seed[i] >= 0:
					plucked[_cell_seed[i]] = 0.0
		_cut_cracks(rect)
		# Seams: each cut edge opens into a crack along it a few years on.
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for s in 4:
			var a: Vector2 = corners[s]
			var b: Vector2 = corners[(s + 1) % 4]
			var path := PackedVector2Array()
			var n := maxi(2, int(a.distance_to(b) / STEP))
			var out := (b - a).orthogonal().normalized() * 0.006
			for k in n + 1:
				path.append(a.lerp(b, float(k) / n) - out)
			var keep := PackedVector2Array()
			for q in path:
				if paved(q):
					keep.append(q)
			_latent.append({ path = keep, at = seams[s], kind = Kind.SEAM, speed = 1.2, widen = 1.6 })
	return "%d patches" % made


## Cut every crack where it crosses into the rectangle: the part inside is dug out.
func _cut_cracks(rect: Rect2) -> void:
	var count := cracks.size()
	for ci in count:
		var c := cracks[ci]
		if not c.alive:
			continue
		var inside := false
		for q in c.pts:
			if rect.has_point(q):
				inside = true
				break
		if not inside:
			continue
		var runs: Array[Array] = []
		var cur: Array = []
		for k in c.pts.size():
			if rect.has_point(c.pts[k]):
				if cur.size() > 0:
					runs.append(cur)
					cur = []
			else:
				cur.append(k)
		if cur.size() > 0:
			runs.append(cur)
		c.alive = false
		for run in runs:
			if run.size() < 2:
				continue
			var n := Crack.new()
			n.kind = c.kind
			n.widen = c.widen
			n.local = c.local
			n.surf0 = c.surf0
			n.ox_k = c.ox_k
			n.seal_from = c.seal_from
			n.sealed_before = c.sealed_before
			n.growing = false
			for k: int in run:
				n.pts.append(c.pts[k])
				n.born.append(c.born[k])
			# Run the cut end right up to the saw cut.
			var first: int = run[0]
			var last: int = run[run.size() - 1]
			if last < c.pts.size() - 1:
				n.pts.append(_edge_point(c.pts[last], c.pts[last + 1], rect))
				n.born.append(c.born[last])
			if first > 0:
				n.pts.insert(0, _edge_point(c.pts[first], c.pts[first - 1], rect))
				n.born.insert(0, c.born[first])
			for k in n.pts.size() - 1:
				n.length += n.pts[k].distance_to(n.pts[k + 1])
			cracks.append(n)
	_rebuild_grid()


func _edge_point(outside: Vector2, inside: Vector2, rect: Rect2) -> Vector2:
	var a := outside
	var b := inside
	for _k in 8:
		var m := (a + b) * 0.5
		if rect.has_point(m):
			b = m
		else:
			a = m
	return a


## Surface seal or cold plane and overlay: a new wearing surface over everything. Potholes are filled first.
## The old cracks and the patch edges stay in the layer below and come back through it as reflection cracks.
func _resurface(kind: int) -> String:
	var overlay := kind == Surface.HOT_MIX
	var buried := 0
	for c in cracks:
		if not c.alive or c.pts.size() < 3:
			c.alive = false
			continue
		var w := c.width(0, time)
		# Hairlines mostly stay buried; wide, working cracks come back first.
		var chance := clampf(w / 0.006, 0.15, 1.0) * (0.75 if overlay else 1.0)
		if _rng.randf() < chance:
			var delay := (_rng.randf_range(1.5, 5.0) * structure if overlay else _rng.randf_range(0.4, 2.5)) \
				* lerpf(1.6, 0.6, clampf(w / 0.015, 0.0, 1.0))
			_latent.append({ path = c.pts.duplicate(), at = time + delay })
			buried += 1
		c.alive = false
	for p in patches:
		var r: Rect2 = p.rect
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for s in 4:
			if _rng.randf() < 0.6:
				var a: Vector2 = corners[s]
				var b: Vector2 = corners[(s + 1) % 4]
				var path := PackedVector2Array()
				var n := maxi(2, int(a.distance_to(b) / STEP))
				for k in n + 1:
					path.append(a.lerp(b, float(k) / n))
				_latent.append({ path = path, at = time + _rng.randf_range(2.0, 6.0) * structure })
	cracks = cracks.filter(func(c: Crack) -> bool: return c.alive)
	patches.clear()
	_transverse_y.clear()
	plucked.fill(0.0)
	for e in _net_edges:
		e.on = false
	for i in nx * ny:
		hole[i] = 0.0
		fill_born[i] = -1.0
		patch_of[i] = -1
		damage[i] *= 0.3
		fatigue[i] *= 0.45 if overlay else 0.9
	if overlay:
		edge_l.fill(0.0)
		edge_r.fill(0.0)
		rut_born = time
	surface_born = time
	surface_kind = kind
	_rebuild_grid()
	return "%d cracks will reflect through" % buried


func _rebuild_grid() -> void:
	occ.fill(0)
	for ci in cracks.size():
		var c := cracks[ci]
		if not c.alive:
			continue
		for k in c.pts.size():
			_mark(c.pts[k], ci, k)
			if k > 0:
				_mark((c.pts[k] + c.pts[k - 1]) * 0.5, ci, k)
	_rebuild_lengths()


func _rebuild_lengths() -> void:
	crack_len.fill(0.0)
	open_len.fill(0.0)
	for c in cracks:
		if not c.alive:
			continue
		var sealed := c.sealed(time + 0.001)
		if sealed:
			_seal_check = minf(_seal_check, c.seal_to())
		for k in range(1, c.pts.size()):
			var seg := c.pts[k].distance_to(c.pts[k - 1])
			var i := cell_index(c.pts[k])
			crack_len[i] += seg
			if not sealed:
				open_len[i] += seg


## What a road crew does left to itself: fill cracks once they open up, fill potholes straight away, patch the
## worst fatigue areas, and overlay the road when it is beyond patching.
func _auto_maintain() -> void:
	var since := func(a: int) -> float: return time - float(_last.get(a, -100.0))
	if surface_age() < 1.0:
		return
	var s := stats()
	if s.pci < 30.0 and since.call(Action.OVERLAY) > 6.0:
		_apply(Action.OVERLAY)
		return
	if s.pothole_pct > 0.0 and since.call(Action.POTHOLE_FILL) > 0.5:
		_apply(Action.POTHOLE_FILL)
	if s.alligator_pct > 3.0 and since.call(Action.HEAVY_PATCH) > 4.0:
		_apply(Action.HEAVY_PATCH)
	if s.wide_crack_m > 6.0 and since.call(Action.CRACK_FILL) > 3.0:
		_apply(Action.CRACK_FILL)


func _count_clusters() -> int:
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var n := 0
	for i in nx * ny:
		if seen[i] == 1 or hole[i] <= 0.0:
			continue
		n += 1
		var stack := [i]
		seen[i] = 1
		while not stack.is_empty():
			var j: int = stack.pop_back()
			for o in [1, -1, nx, -nx]:
				var k: int = j + o
				if k >= 0 and k < nx * ny and seen[k] == 0 and hole[k] > 0.0:
					seen[k] = 1
					stack.append(k)
	return n
