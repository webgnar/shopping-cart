class_name AsphaltSimState
extends Node
## AsphaltSim, part 1 of 7: its settings and state, the Crack class, the pavement it is built on (spacings and cell sizes
## from the build-up), and the queries the drawings and the survey use. See asphalt_sim.gd for the whole.


signal changed

enum Kind { TRANSVERSE, JOINT, WHEELPATH, FATIGUE, BLOCK, EDGE, SLIPPAGE, REFLECTION, SEAM }
enum Action { CRACK_FILL, POTHOLE_FILL, HEAVY_PATCH, SURFACE_SEAL, OVERLAY, REPAINT }

const KIND_NAMES := ["transverse", "lane joint", "wheel path", "fatigue", "block", "edge", "slippage",
	"reflection", "patch seam"]
const ACTION_NAMES := ["Crack filling", "Pothole fill", "Heavy patch", "Spot sealcoat", "Mill & overlay", "Repaint"]

const CELL := 0.1        ## m: cell grid for fatigue, water damage and potholes
const GRID := 0.02       ## m: crack occupancy grid (cracks that run into another one join it)
const STEP := 0.025      ## m: spacing of the points along a crack
const DT := 0.2          ## years per simulation step
const SEAL_LIFE := 6.0   ## years crack sealant holds before it debonds
const HOLE_MAX := 0.09   ## m: a pothole stops deepening at the base course
const FILL_PROUD := 0.004     ## m a fresh tamped cold patch stands above the road
const SEAL_PROUD := 0.0015  ## m the overbanded crack sealant stands above the road

@export var seed := 1
@export var size := Vector2(10.0, 10.0)                 ## m: X across the road, Y along it

@export_group("Road layout")
## The default is a standard two-lane road: two 3.65 m (12 ft) lanes meeting at the centreline joint, unpaved
## shoulders, the wheel paths where LTPP fig. 136 puts them (0.76 m and 2.9 m in from each edge stripe).
@export var shoulder := 1.35                            ## m of unsealed gravel shoulder each side
@export var unsealed_edges := true                      ## the outer edges crack and fret (off where more pavement butts on)
@export var lane_joint_x := 5.0                         ## m: the longitudinal paving joint between the lanes
@export var wheel_paths := PackedFloat32Array([2.11, 4.25, 5.75, 7.89])  ## m: centre of each wheel path
@export var wheel_path_width := 0.35                    ## m: spread of the wheel load either side of a path

@export_group("Pavement and conditions")
@export_range(0.3, 1.5, 0.05) var structure := 1.0     ## thickness and build quality (0.5 = thin or poorly compacted)
@export_range(0.0, 2.0, 0.05) var traffic := 1.0       ## heavy traffic load
@export_range(0.0, 2.0, 0.05) var climate := 1.0       ## freeze-thaw cycles and sun (oxidation, UV)
@export_range(0.0, 2.0, 0.05) var drainage := 1.0      ## how much water gets in and stays (1 = typical)
@export_range(0.0, 1.0, 0.05) var bond := 0.7          ## bond of the wearing course to the layer below (low = slippage)
@export var oxidation_years := 9.0                      ## years for the binder to go most of the way to grey
@export_range(0.0, 2.0, 0.05) var ponding := 1.0       ## how much water sits in low spots (poor grading)

@export_group("Pavement")
## The pavement's cross-section: layers and subgrade (assets/asphalt/buildups/). The crack spacings and cell sizes are
## worked out from it (thermal_spacing(), block_cell(), fatigue_cell()): a shrinking layer that slides on its base
## cracks a slip length apart (Li & Marasteanu 2005), and a wheel's bending breaks the wheel path into cells about
## Westergaard's radius across (as the CrackLattice runs showed). Empty: the c620 Table 3B baseline.
@export var buildup: PavementBuildup
## The site's climate (assets/asphalt/climates/): its pavement temperatures age the binder (BinderAgeing, T2).
## Empty: Burlington, Vermont.
@export var site_climate: SiteClimate

@export_group("Mix and crack paths")
@export_range(0.0, 1.0, 0.05) var mix_variation := 0.5 ## how uneven the asphalt's strength is (compaction, segregation)
@export var aggregate_size := 0.012                     ## m: the stones; the fine strength noise is this size
@export_range(0.0, 1.0, 0.05) var crack_bias := 0.6    ## how hard cracks seek the weaker mix as they grow
@export_range(0.0, 1.0, 0.05) var branching := 0.15    ## side branches per metre of freely growing crack
@export_range(0.0, 1.0, 0.05) var stop_short := 0.25   ## share of cracks that die out just short of another (the rest join it at a T)

@export_group("Crack networks")
@export_range(0.0, 1.0, 0.05) var block_onset := 0.55   ## oxidation (0..1) at which the first blocks crack

@export_group("Displacement")
@export var shoulder_drop := -0.025                     ## m: the gravel shoulder sits this far below the road
@export var fret_drop := -0.035                         ## m: where the edge has broken off, down to the base course
@export var spall_depth := 0.006                        ## m: broken shoulders either side of a wide crack
@export var edge_feather := 0.15                        ## m round the section easing back to 0 to meet flat ground

@export_group("Paint")
@export var paint_lines := PackedVector2Array()         ## painted lines: start and end point pairs, m
@export var paint_colors := PackedColorArray()          ## colour of each line (one per pair); missing: the canvas's paint_color
@export var paint_width := 0.1                          ## m (4 in, the standard stall line)
@export var paint_thickness := 0.0008                   ## m fresh traffic paint stands above the asphalt
@export var paint_life := 8.0                           ## years for the paint to wear off under a wheel path
## The lines are repainted by Repaint and by an overlay; repairs made since cover them until the next repaint.

@export_group("Spot sealcoat")
@export var sealcoat_life := 3.0                        ## years for a spot sealcoat to wear through in the wheel paths
@export var sealcoat_spots := 3                         ## spots per sealcoat, over the roughest areas
@export var sealcoat_size := Vector2(0.6, 1.3)          ## m radius of a spot, smallest to largest

@export_group("Maintenance")
@export var auto_maintain := false                      ## a road crew repairs the road on its own (see _auto_maintain)

@export_group("Science")
## Run the placeholder models: the damage rules (asphalt_sim_rules.gd), rutting, paint wear and the time-driven looks
## (greying, ravelling), none of which is sourced yet (docs/ASPHALT_SCIENCE.md). On for the game's lots, which were
## built with them; the lab turns it off, so it shows only what is sourced.
@export var placeholders := true

## Time since the road was built, years.
var time := 0.0
## When the current wearing surface went down (overlay or seal) and what it is.
var surface_born := 0.0
var _binder: BinderAgeing
var _binder_key := []
var paint_born := 0.0                     ## year the lines were last painted
var rut_born := 0.0
var cracks: Array[Crack] = []
var seal_spots: Array[Dictionary] = []    ## spot sealcoats: { poly: PackedVector2Array (m), born: float }
var patches: Array[Dictionary] = []       ## { rect: Rect2, born: float, seams_at: PackedFloat32Array }
var events: Array[Dictionary] = []        ## repairs asked for by hand: { t, action }
var log_lines: PackedStringArray = []     ## every repair done, in order, for the lab's history

# Cell grid (CELL), row-major: i = cy * nx + cx.
var nx := 0
var ny := 0
var weak := PackedFloat32Array()      ## 0..1 subgrade weakness (soft spots, poor support)
var pond := PackedFloat32Array()      ## 0..1 low spots where water stands after rain
var load := PackedFloat32Array()      ## traffic load per cell (wheel paths)
var _wheel_cells := PackedInt32Array()  ## cells with load >= 0.25 (where wheel-path cracks can start)
var fatigue := PackedFloat32Array()   ## accumulated fatigue; cracks start at 1, break up into cells past FATIGUE_CELLS
var damage := PackedFloat32Array()    ## water damage under open cracks; a pothole breaks out at 1
var hole := PackedFloat32Array()      ## pothole depth, m
var fill_born := PackedFloat32Array() ## year a throw-and-roll fill went in, -1 for none
var fill_depth := PackedFloat32Array() ## m: how deep the hole was that the fill went into (for the cross-section)
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

## Ratios from the CrackLattice runs: thermal cracks start about two slip lengths apart in new binder and close in
## to about 0.6 of one as it hardens and fatigues; blocks are about a slip length; crocodile cells about Westergaard's
## radius (a bit narrower across the road, where the wheel bends it hardest).
const THERMAL_SPACING := Vector2(2.0, 0.6)
const BLOCK_CELL := Vector2(0.7, 1.0)
const FATIGUE_CELL := Vector2(0.7, 1.0)
const REF_THICKNESS := 0.076   ## m the fatigue rate was tuned for (a 3 in lot)
const DEFAULT_BUILDUP := preload("res://assets/asphalt/buildups/c620_table3b_cbr9.tres")
const DEFAULT_CLIMATE := preload("res://assets/asphalt/climates/burlington_vt.tres")
const AGEING_YEARS := 40       ## years of binder ageing worked out; older surfaces stay at the last year
const BOND_FULL_DEPTH := 0.1e6 ## Pa: placeholder shear strength for full-depth asphalt on the subgrade (no source yet)
const BRANCH_SCATTER := 0.26   ## rad (15 degrees): spread of a shrinkage branch's angle (Shorlin et al. 1999)
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


## The build-up in use: `buildup`, or the c620 Table 3B baseline.
func pavement() -> PavementBuildup:
	return buildup if buildup else DEFAULT_BUILDUP


## The site's climate in use: `site_climate`, or Burlington.
func site() -> SiteClimate:
	return site_climate if site_climate else DEFAULT_CLIMATE


## The surface binder's ageing (T2) for this site and the build-up's binder grade, worked out again only when
## either changes.
func binder() -> BinderAgeing:
	var key := [site(), pavement().surface().binder_hpg]
	if _binder == null or key != _binder_key:
		_binder = BinderAgeing.for_layer(site(), pavement().surface(), AGEING_YEARS)
		_binder_key = key
	return _binder


## log |G*| (kPa, 64 C, 10 rad/s) of the binder `depth_m` below the surface, at the surface's age.
func binder_log_g(depth_m: float) -> float:
	return binder().log_g(depth_m, surface_age())


## m of bound asphalt.
func thickness() -> float:
	return pavement().asphalt_thickness()


## m from a crack to where friction on the base has built the layer back up to its cold strength: Li & Marasteanu
## 2005 eq. 4, Xc = sigma_t / (C / h + rho g tan(phi)), with the base's cohesion C and friction angle phi. Full-depth
## asphalt on the subgrade (no aggregate base) is not covered by it yet: it uses BOND_FULL_DEPTH.
func slip_length() -> float:
	var b := pavement()
	var s := b.surface()
	var g := b.base()
	var h := b.asphalt_thickness()
	if g == null:
		return s.tensile_strength * h / BOND_FULL_DEPTH
	return s.tensile_strength / (g.cohesion / h + s.density * 9.81 * g.friction_tan)


## m: Westergaard's radius of relative stiffness, how far a wheel's bending spreads in the layer, on the subgrade's
## modulus of reaction (PavementBuildup.subgrade_k()).
func wheel_spread() -> float:
	var b := pavement()
	var s := b.surface()
	return pow(s.stiffness_warm * pow(b.asphalt_thickness(), 3.0)
		/ (12.0 * (1.0 - s.poisson * s.poisson) * b.subgrade_k()), 0.25)


## m between thermal cracks: new binder, fully aged.
func thermal_spacing() -> Vector2:
	return THERMAL_SPACING * slip_length()


## m: size of a block in block cracking (across, along the road).
func block_cell() -> Vector2:
	return BLOCK_CELL * slip_length()


## m: size of a crocodile-skin cell (across, along the road).
func fatigue_cell() -> Vector2:
	return FATIGUE_CELL * wheel_spread()


## Years of ageing the looks show (greying, ravelling, paint dirt): none while the placeholders are off, since no
## sourced model drives them yet.
func look_age(years: float) -> float:
	return years if placeholders else 0.0


func surface_age() -> float:
	return time - surface_born


## How weak the asphalt mix is at p, 0..1: a slow variation over metres plus a stone-by-stone one.
func mix_weakness(p: Vector2) -> float:
	return clampf(0.5 + mix_variation * (0.6 * _mix_low.get_noise_2d(p.x, p.y) + 0.5 * _mix_fine.get_noise_2d(p.x, p.y)), 0.0, 1.0)


## How much paint is left at p, 0..1: it wears with age and traffic (fastest in the wheel paths), in patches.
func paint_left(p: Vector2) -> float:
	if not placeholders:
		return 1.0
	var wear := (time - paint_born) * traffic * (0.15 + load[cell_index(p)]) / paint_life
	if wear <= 0.0:
		return 1.0
	# Value noise on a 20 cm grid: some stretches go first.
	var q := p * 5.0
	var i := q.floor()
	var f := q - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var n := lerpf(lerpf(_hash2(i), _hash2(i + Vector2(1, 0)), f.x), lerpf(_hash2(i + Vector2(0, 1)), _hash2(i + Vector2(1, 1)), f.x), f.y)
	return clampf(1.0 - wear * (0.4 + 1.2 * n), 0.0, 1.0)


## m a cold patch stands proud: tamped a few millimetres high, then packed down by traffic over a couple of years.
func fill_proud(age: float) -> float:
	return FILL_PROUD * (1.0 - 0.7 * clampf(age / 2.0, 0.0, 1.0))


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
	if not placeholders:
		return 0.0
	return minf(0.025, 0.0011 * (time - rut_born) * traffic / structure)


## m: how deep an open crack of width w goes. Placeholder (4 x the width, 4 to 50 mm): no source yet; the
## cross-section draws it hatched until crack depth comes from the models.
func crack_depth(w: float) -> float:
	return clampf(w * 4.0, 0.004, 0.05)


## How much of a spot sealcoat born at `born` is left at p, 0..1: it wears off the wheel paths first, in patches.
func sealcoat_left(p: Vector2, born: float) -> float:
	var wear := (time - born) * traffic * (0.08 + load[cell_index(p)]) / sealcoat_life
	if wear <= 0.0:
		return 1.0
	var q := p * 8.0
	var i := q.floor()
	var f := q - i
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var n := lerpf(lerpf(_hash2(i), _hash2(i + Vector2(1, 0)), f.x), lerpf(_hash2(i + Vector2(0, 1)), _hash2(i + Vector2(1, 1)), f.x), f.y)
	return clampf(1.0 - wear * (0.5 + n), 0.0, 1.0)


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
