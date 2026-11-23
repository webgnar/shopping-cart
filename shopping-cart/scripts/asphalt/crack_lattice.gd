class_name CrackLattice
extends Node
## Experiment: asphalt cracking from mechanics instead of rules, on a small patch (2 x 2 m). Separate from AsphaltSim.
##
## The patch is stones in a binder-and-fines mastic, modelled as a triangular mesh of springs (one node every
## `spacing` m) that is glued to the base by soft springs under every node. Two loads pull on the mesh:
##   - cold: the asphalt wants to shrink each winter night, more as the binder ages and hardens. The base holds it
##     back, so the springs go into tension; the road is long, so the pull along it is stronger than across it.
##   - wheels: each axle bends the layer over the wheel path, stretching its underside, mostly across the road.
## Each load is solved for its own displacement field (they superpose), with its own base stiffness: the base holds
## the shrinking layer over a long distance and a bending plate over a short one (about its thickness).
## Every winter each spring's tension adds fatigue (Miner's rule, damage ~ (stress / strength)^m); a spring snaps
## when its peak tension passes its strength left after fatigue. When one snaps the mesh around it is relaxed again,
## which can snap the next one along (a crack running), so crack spacing, T-junctions, crocodile cells and paths
## that weave between the stones come out of the mechanics, not from rules.
## Units: strength and stress are relative to the mastic's mean strength (1.0); the loads are given the same way.

signal changed

enum Kind { MASTIC, FACE, STONE }   ## spring through mastic, across a stone's face (weak bond), inside a stone

const ROOT3_2 := 0.8660254
## The six neighbours of a node on the triangular mesh (odd rows sit half a step to the right).
const NB_EVEN := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
const NB_ODD := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const TOL := 1e-3          ## relaxation stops when no node moves more than this share of a spring's stretch
const STONE_CELL := 0.02   ## m: bucket size of the stone lookup grid
const JITTER := 0.03       ## nodes are nudged this share of the spacing off the regular grid (more makes the mesh
                           ## itself uneven: its springs would carry very different loads before anything breaks)
const OVER_RELAX := 1.5    ## successive over-relaxation: settles the mesh in fewer passes

@export var seed := 1
@export var size := Vector2(2.0, 2.0)             ## m: X across the road, Y along it (wraps round at the edges)
@export var spacing := 0.02                       ## m between mesh nodes
@export var dt := 0.25                            ## years per step

@export_group("Mix")
## Coarse aggregate gradation: [sieve mm, share of the patch area that is stones between this sieve and the next
## size down]. A dense 19 mm mix; the fines (< 4.75 mm) are part of the mastic.
@export var gradation := PackedVector2Array([Vector2(25.0, 0.04), Vector2(19.0, 0.14), Vector2(12.5, 0.11),
		Vector2(9.5, 0.17), Vector2(4.75, 0.0)])
@export var stone_stiffness := 4.0                ## stone springs are this much stiffer than the mastic
@export var face_strength := 0.8                 ## bond of the mastic to a stone face, relative to the mastic
@export var strength_scatter := 0.08             ## spread of mastic strength (fines, air voids, compaction)
@export var void_share := 0.01                   ## share of springs crossing an air void (half as strong)

@export_group("Cold and ageing")
@export var cold_stress := 0.3                   ## tension a cold winter night puts in new, uncracked asphalt
@export var along_share := 1.0                    ## shrinkage held back along the road ...
@export var across_share := 0.7                   ## ... and across it (the lane's free edges let it give a bit)
@export var oxidation_years := 9.0                ## years for the binder to harden most of the way
@export var hardening := 1.7                      ## fully aged binder carries this much more cold tension
@export var cold_transfer := 0.45                 ## m over which the base takes up the pull of a shrinking layer
@export var cold_life := 40.0                    ## winters a spring lasts at half its strength

@export_group("Traffic")
@export var wheel_path_x := 1.0                   ## m: centre of the wheel path
@export var wheel_path_width := 0.22              ## m: spread (one sigma) of where the wheels run
@export var wheel_stress := 0.12                  ## underside tension of one heavy axle across the road ...
@export var wheel_along := 0.55                   ## ... and along it, as a share of that
@export var wheel_transfer := 0.07                ## m: how far a bending plate spreads its load (about its thickness)
@export var traffic_life := 10.0                  ## years of traffic a spring lasts when each axle pulls it to a quarter of its strength
@export var fatigue_exponent := 4.0               ## m in damage ~ (stress / strength)^m
@export var fatigue_weakening := 0.8              ## share of its strength a spring has lost when fully fatigued

@export_group("Crack width")
@export var width_min := 0.0005                   ## m: a hairline crack
@export var width_per_opening := 0.01             ## m of width per unit of opening (stress relieved x spacing)
@export var ravel_rate := 0.00025                 ## m a crack's edges break away per year (more in the wheel path)

var time := 0.0
var cols := 0
var rows := 0
var cell := Vector2.ZERO                          ## m: x step and row step of the mesh

## Nodes
var pos := PackedVector2Array()                   ## rest position, m
var stone_of := PackedInt32Array()                ## stone the node sits in, -1 for mastic
var adj := PackedInt32Array()                     ## 6 per node: spring * 2 + (0 if the node is the spring's a, else 1)
var u_cold := PackedVector2Array()                ## displacement under the unit cold load
var u_wheel := PackedVector2Array()               ## and under the unit wheel load
var kinv_cold := PackedFloat32Array()             ## 3 per node: inverse of the node's 2x2 stiffness (xx, xy, yy)
var kinv_wheel := PackedFloat32Array()

## Springs
var sa := PackedInt32Array()
var sb := PackedInt32Array()
var dir := PackedVector2Array()                   ## unit vector a -> b
var length := PackedFloat32Array()
var k := PackedFloat32Array()                     ## stiffness (0 once broken)
var strength := PackedFloat32Array()
var kind := PackedInt32Array()
var e_cold := PackedFloat32Array()                ## shrinkage strain along the spring under the unit cold load
var e_wheel := PackedFloat32Array()               ## and under the unit wheel load
var damage := PackedFloat32Array()                ## Miner's fatigue, 0..1
var broke_at := PackedFloat32Array()              ## year it snapped, -1 while whole
var mid := PackedVector2Array()                   ## middle of the spring, m (where its crack crosses it)

## Triangles of the mesh: a crack runs through a triangle from the middle of one broken side to the next
var tri := PackedInt32Array()                     ## 3 springs per triangle
var tri_c := PackedVector2Array()                 ## centre, m
var spring_tri := PackedInt32Array()              ## the 2 triangles each spring is a side of

## Stones: centre, mean radius, and a star-shaped outline of STONE_SIDES radii from angle stone_rot
const STONE_SIDES := 8
var stone_c := PackedVector2Array()
var stone_r := PackedFloat32Array()
var stone_rot := PackedFloat32Array()
var stone_radii := PackedFloat32Array()           ## STONE_SIDES per stone
var stone_shade := PackedFloat32Array()           ## 0..1 colour variation for drawing
var _sgrid: Array[PackedInt32Array] = []
var _sgx := 0
var _sgy := 0

var broken := PackedInt32Array()                  ## springs in the order they snapped
var _kb_cold := 0.0
var _kb_wheel := 0.0
var _rng := RandomNumberGenerator.new()
var _queued := PackedByteArray()
var _touched := PackedInt32Array()


func _ready() -> void:
	reset()


func reset() -> void:
	_rng.seed = seed
	time = 0.0
	broken.clear()
	_place_stones()
	_build_mesh()
	_solve_all()
	changed.emit()


## How hard the binder has become, 0 (new) .. 1 (fully oxidised).
func oxidation(t := time) -> float:
	return 1.0 - exp(-t / oxidation_years)


func cold_scale(t := time) -> float:
	return cold_stress * (1.0 + hardening * oxidation(t))


func wheel_scale(t := time) -> float:
	return wheel_stress * (1.0 + 0.5 * hardening * oxidation(t))


func advance_to(t: float) -> void:
	if t < time - 1e-6:
		reset()
	while time < t - 1e-6:
		_step()
	changed.emit()


## Tension (relative to mastic strength) in spring s under the unit cold or wheel load.
func _tension(s: int, u: PackedVector2Array, e: PackedFloat32Array) -> float:
	var kk := k[s]
	if kk == 0.0:
		return 0.0
	return kk * ((u[sb[s]] - u[sa[s]]).dot(dir[s]) / length[s] + e[s])


## Opening of a broken spring under this winter's cold, as a strain (how far the faces have pulled apart / spacing).
func opening(s: int) -> float:
	return maxf(0.0, (u_cold[sb[s]] - u_cold[sa[s]]).dot(dir[s]) / length[s] + e_cold[s]) * cold_scale() \
			+ maxf(0.0, (u_wheel[sb[s]] - u_wheel[sa[s]]).dot(dir[s]) / length[s] + e_wheel[s]) * wheel_scale() * 0.3


## Width in metres of broken spring s's crack now.
func crack_width(s: int) -> float:
	var age := time - broke_at[s]
	var path := _wheel_load(pos[sa[s]].x)
	return width_min + width_per_opening * opening(s) * spacing + ravel_rate * age * (0.5 + 1.5 * path)


func _wheel_load(x: float) -> float:
	var d := x - wheel_path_x
	d -= roundf(d / size.x) * size.x
	return exp(-0.5 * d * d / (wheel_path_width * wheel_path_width))


func _step() -> void:
	var sc := cold_scale(time + dt)
	var sw := wheel_scale(time + dt)
	var m := fatigue_exponent
	# damage per year at the reference stress ratio r is 1 / life, so rate = 1 / (life * r^m)
	var rc := 1.0 / (cold_life * pow(0.5, m))
	var rw := 1.0 / (traffic_life * pow(0.25, m))
	var over := PackedInt32Array()
	for s in k.size():
		if k[s] == 0.0 or kind[s] == Kind.STONE:
			continue
		var tc := maxf(0.0, _tension(s, u_cold, e_cold) * sc)
		var tw := maxf(0.0, _tension(s, u_wheel, e_wheel) * sw)
		var st := strength[s]
		damage[s] = minf(1.0, damage[s] + dt * (rc * pow(tc / st, m) + rw * pow(tw / st, m)))
		if tc + tw >= _left(s):
			over.append(s)
	time += dt
	if not over.is_empty():
		_cascade(over, sc, sw)


## Snaps the most overloaded spring, relaxes the mesh round it, and repeats while any spring is past its strength.
func _cascade(cand: PackedInt32Array, sc: float, sw: float) -> void:
	var guard := 0
	while not cand.is_empty() and guard < 20000:
		guard += 1
		var best := -1
		var best_r := 1.0
		var keep := PackedInt32Array()
		for s in cand:
			if k[s] == 0.0:
				continue
			var r := (maxf(0.0, _tension(s, u_cold, e_cold) * sc) + maxf(0.0, _tension(s, u_wheel, e_wheel) * sw)) \
					/ (_left(s) + 1e-9)
			if r >= 1.0:
				keep.append(s)
				if r >= best_r:
					best_r = r
					best = s
		cand = keep
		if best < 0:
			break
		_snap(best)
		# springs round the nodes that moved may now be over
		var seen := { }
		for n in _touched:
			for j in 6:
				var e := adj[n * 6 + j]
				if e < 0:
					continue
				var s := e >> 1
				if k[s] == 0.0 or kind[s] == Kind.STONE or seen.has(s):
					continue
				seen[s] = true
				var t := maxf(0.0, _tension(s, u_cold, e_cold) * sc) + maxf(0.0, _tension(s, u_wheel, e_wheel) * sw)
				if t >= _left(s):
					cand.append(s)


## Strength left in spring s after fatigue.
func _left(s: int) -> float:
	return strength[s] * (1.0 - fatigue_weakening * damage[s])


func _snap(s: int) -> void:
	k[s] = 0.0
	broke_at[s] = time
	broken.append(s)
	_update_kinv(sa[s])
	_update_kinv(sb[s])
	_touched.clear()
	var seeds := PackedInt32Array([sa[s], sb[s]])
	_relax(seeds, u_cold, e_cold, kinv_cold, _kb_cold)
	_relax(seeds, u_wheel, e_wheel, kinv_wheel, _kb_wheel)


## Gauss-Seidel on the nodes that are out of balance, spreading outward from `seeds` until everything is still.
func _relax(seeds: PackedInt32Array, u: PackedVector2Array, e: PackedFloat32Array, kinv: PackedFloat32Array,
		kb: float, limit := 400000) -> void:
	var queue := PackedInt32Array(seeds)
	for n in seeds:
		_queued[n] = 1
	var head := 0
	var tol := TOL * spacing
	while head < queue.size() and head < limit:
		var n := queue[head]
		head += 1
		_queued[n] = 0
		var f := -kb * u[n]
		for j in 6:
			var ad := adj[n * 6 + j]
			if ad < 0:
				continue
			var s := ad >> 1
			var kk := k[s]
			if kk == 0.0:
				continue
			var d := dir[s]
			var t := kk * ((u[sb[s]] - u[sa[s]]).dot(d) + e[s] * length[s])
			f += d * t if (ad & 1) == 0 else -d * t
		var i := n * 3
		var du := Vector2(kinv[i] * f.x + kinv[i + 1] * f.y, kinv[i + 1] * f.x + kinv[i + 2] * f.y) * OVER_RELAX
		u[n] += du
		if du.length() > tol:
			_touched.append(n)
			for j in 6:
				var ad := adj[n * 6 + j]
				if ad < 0:
					continue
				var s := ad >> 1
				var o := sb[s] if (ad & 1) == 0 else sa[s]
				if _queued[o] == 0:
					_queued[o] = 1
					queue.append(o)
	if head < queue.size():
		push_warning("CrackLattice: relaxation hit its limit")
	for i in range(head, queue.size()):
		_queued[queue[i]] = 0


func _solve_all() -> void:
	var all := PackedInt32Array()
	all.resize(pos.size())
	for i in pos.size():
		all[i] = i
	_relax(all, u_cold, e_cold, kinv_cold, _kb_cold, 50000000)
	_relax(all, u_wheel, e_wheel, kinv_wheel, _kb_wheel, 50000000)


func _update_kinv(n: int) -> void:
	_kinv_for(n, kinv_cold, _kb_cold)
	_kinv_for(n, kinv_wheel, _kb_wheel)


func _kinv_for(n: int, kinv: PackedFloat32Array, kb: float) -> void:
	var xx := kb
	var xy := 0.0
	var yy := kb
	for j in 6:
		var ad := adj[n * 6 + j]
		if ad < 0:
			continue
		var s := ad >> 1
		var d := dir[s]
		var kk := k[s]
		xx += kk * d.x * d.x
		xy += kk * d.x * d.y
		yy += kk * d.y * d.y
	var det := xx * yy - xy * xy
	kinv[n * 3] = yy / det
	kinv[n * 3 + 1] = -xy / det
	kinv[n * 3 + 2] = xx / det


# --- Building the patch -------------------------------------------------------------------------------------------

func _place_stones() -> void:
	stone_c.clear()
	stone_r.clear()
	stone_rot.clear()
	stone_radii.clear()
	stone_shade.clear()
	_sgx = int(ceil(size.x / STONE_CELL))
	_sgy = int(ceil(size.y / STONE_CELL))
	_sgrid.clear()
	_sgrid.resize(_sgx * _sgy)
	for i in _sgrid.size():
		_sgrid[i] = PackedInt32Array()
	var area := size.x * size.y
	for g in gradation.size() - 1:
		var big := gradation[g].x * 0.001
		var small := gradation[g + 1].x * 0.001
		var want := gradation[g].y * area
		var got := 0.0
		var tries := 0
		while got < want and tries < 400000:
			tries += 1
			# a stone passes the bigger sieve but not the smaller; its cut face is a bit smaller than the sieve size
			var dia := exp(lerpf(log(small), log(big), _rng.randf())) * _rng.randf_range(0.7, 1.0)
			var r := dia * 0.5
			var c := Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
			if _stone_near(c, r + 0.0004):
				continue
			_add_stone(c, r)
			got += PI * r * r


func _add_stone(c: Vector2, r: float) -> void:
	var i := stone_c.size()
	stone_c.append(c)
	stone_r.append(r)
	stone_rot.append(_rng.randf() * TAU)
	var squash := _rng.randf_range(0.65, 1.0)    # flaky or cubic
	var turn := _rng.randf() * PI
	for j in STONE_SIDES:
		var a := TAU * j / STONE_SIDES
		var ell := 1.0 / sqrt(pow(cos(a - turn), 2.0) + pow(sin(a - turn) / squash, 2.0))
		stone_radii.append(r * clampf(ell * sqrt(squash) * _rng.randf_range(0.8, 1.15), 0.45, 1.2))
	stone_shade.append(_rng.randf())
	var gx0 := int(floor((c.x - r) / STONE_CELL))
	var gx1 := int(floor((c.x + r) / STONE_CELL))
	var gy0 := int(floor((c.y - r) / STONE_CELL))
	var gy1 := int(floor((c.y + r) / STONE_CELL))
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			_sgrid[posmod(gy, _sgy) * _sgx + posmod(gx, _sgx)].append(i)


func _wrap_p(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x, size.x), fposmod(p.y, size.y))


func _wrap_d(d: Vector2) -> Vector2:
	return Vector2(d.x - roundf(d.x / size.x) * size.x, d.y - roundf(d.y / size.y) * size.y)


func _stone_near(c: Vector2, r: float) -> bool:
	var gx0 := int(floor((c.x - r) / STONE_CELL)) - 1
	var gx1 := int(floor((c.x + r) / STONE_CELL)) + 1
	var gy0 := int(floor((c.y - r) / STONE_CELL)) - 1
	var gy1 := int(floor((c.y + r) / STONE_CELL)) + 1
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			for i in _sgrid[posmod(gy, _sgy) * _sgx + posmod(gx, _sgx)]:
				if _wrap_d(stone_c[i] - c).length() < stone_r[i] * 1.05 + r:
					return true
	return false


## The stone that point p (m) is inside, or -1.
func stone_at(p: Vector2) -> int:
	var gx := posmod(int(floor(p.x / STONE_CELL)), _sgx)
	var gy := posmod(int(floor(p.y / STONE_CELL)), _sgy)
	for i in _sgrid[gy * _sgx + gx]:
		if _inside(i, p):
			return i
	return -1


func _inside(i: int, p: Vector2) -> bool:
	var d := _wrap_d(p - stone_c[i])
	var rr := d.length()
	if rr > stone_r[i] * 1.25:
		return false
	var a := fposmod(atan2(d.y, d.x) - stone_rot[i], TAU)
	var j := int(a / TAU * STONE_SIDES) % STONE_SIDES
	var j2 := (j + 1) % STONE_SIDES
	var p0 := Vector2.from_angle(stone_rot[i] + TAU * j / STONE_SIDES) * stone_radii[i * STONE_SIDES + j]
	var p1 := Vector2.from_angle(stone_rot[i] + TAU * (j + 1) / STONE_SIDES) * stone_radii[i * STONE_SIDES + j2]
	# inside when d is on the centre's side of the edge p0 -> p1
	return (p1 - p0).cross(d - p0) >= 0.0


## Outline of stone i in metres (around its centre as placed, not wrapped).
func stone_outline(i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in STONE_SIDES:
		out.append(stone_c[i] + Vector2.from_angle(stone_rot[i] + TAU * j / STONE_SIDES) * stone_radii[i * STONE_SIDES + j])
	return out


## Moves p off any stone it is inside, along `normal` (both ways tried, the shorter wins); with normal zero, out
## from the stone's centre. This is how a crack goes round a stone instead of through it.
func push_off_stones(p: Vector2, normal := Vector2.ZERO) -> Vector2:
	for _pass in 3:
		var i := stone_at(p)
		if i < 0:
			return p
		var n := normal
		if n == Vector2.ZERO:
			n = _wrap_d(p - stone_c[i]).normalized()
			if n == Vector2.ZERO:
				n = Vector2.RIGHT
			p = _exit(i, p, n)
		else:
			var a := _exit(i, p, n)
			var b := _exit(i, p, -n)
			p = a if a.distance_squared_to(p) < b.distance_squared_to(p) else b
	return p


func _exit(i: int, p: Vector2, n: Vector2) -> Vector2:
	var lo := 0.0
	var hi := stone_r[i] * 2.6
	for _it in 10:
		var mid := (lo + hi) * 0.5
		if _inside(i, p + n * mid):
			lo = mid
		else:
			hi = mid
	return p + n * (hi + 0.0002)


func _build_mesh() -> void:
	cols = maxi(4, int(round(size.x / spacing)))
	rows = maxi(4, int(round(size.y / (spacing * ROOT3_2))))
	rows += rows % 2
	cell = Vector2(size.x / cols, size.y / rows)
	var n := cols * rows
	pos.resize(n)
	stone_of.resize(n)
	for r in rows:
		for c in cols:
			var i := r * cols + c
			var jit := Vector2(_rng.randf_range(-JITTER, JITTER), _rng.randf_range(-JITTER, JITTER)) * spacing
			var p := Vector2((c + 0.5 * (r % 2)) * cell.x, r * cell.y) + jit
			pos[i] = p
			stone_of[i] = stone_at(p)
	adj.resize(n * 6)
	adj.fill(-1)
	for arr: Variant in [sa, sb, dir, length, k, strength, kind, e_cold, e_wheel, damage, broke_at, mid, tri, tri_c]:
		arr.clear()
	# springs to the three "forward" neighbours of each node; the other three come from the nodes behind
	for r in rows:
		var nb: Array = NB_ODD if r % 2 == 1 else NB_EVEN
		for c in cols:
			var a := r * cols + c
			for j in 3:
				var o: Vector2i = nb[j]
				var b := posmod(r + o.y, rows) * cols + posmod(c + o.x, cols)
				var s := sa.size()
				var d := _wrap_d(pos[b] - pos[a])
				sa.append(a)
				sb.append(b)
				dir.append(d.normalized())
				length.append(d.length())
				adj[a * 6 + j] = s * 2
				adj[b * 6 + j + 3] = s * 2 + 1
				var pa := pos[a]
				var pb := pa + d
				mid.append(_wrap_p(pa + d * 0.5))
				_spring_material(s, pa, pb, stone_of[a], stone_of[b])
	spring_tri.resize(sa.size() * 2)
	spring_tri.fill(-1)
	# two triangles per node, up and to the right: (a, n0, n1) and (a, n1, n2), n0..n2 its forward neighbours
	for r in rows:
		var nb: Array = NB_ODD if r % 2 == 1 else NB_EVEN
		for c in cols:
			var a := r * cols + c
			var n0 := posmod(r + nb[0].y, rows) * cols + posmod(c + nb[0].x, cols)
			var n2 := posmod(r + nb[2].y, rows) * cols + posmod(c + nb[2].x, cols)
			for t in [[a * 3, a * 3 + 1, n0 * 3 + 2], [a * 3 + 1, a * 3 + 2, n2 * 3]]:
				for e: int in t:
					spring_tri[e * 2 + (1 if spring_tri[e * 2] >= 0 else 0)] = tri_c.size()
				tri.append_array(PackedInt32Array(t))
				var pa := pos[a]
				var p1 := pa + _wrap_d(pos[sb[t[0]]] - pa)
				var p2 := pa + _wrap_d(pos[sb[t[1]]] - pa)
				tri_c.append(_wrap_p((pa + p1 + p2) / 3.0))
	# loads: shrinkage strain along each spring (anisotropic: held back more along the road) and wheel bending
	for s in sa.size():
		var d := dir[s]
		e_cold[s] = along_share * d.y * d.y + across_share * d.x * d.x
		e_wheel[s] = _wheel_load(mid[s].x) * (d.x * d.x + wheel_along * d.y * d.y)
	# base springs per node, from the stress transfer length: l ~ spacing * sqrt(k / kb)
	_kb_cold = pow(spacing / cold_transfer, 2.0) * 3.0
	_kb_wheel = pow(spacing / wheel_transfer, 2.0) * 3.0
	u_cold.resize(n)
	u_cold.fill(Vector2.ZERO)
	u_wheel.resize(n)
	u_wheel.fill(Vector2.ZERO)
	kinv_cold.resize(n * 3)
	kinv_wheel.resize(n * 3)
	_queued.resize(n)
	_queued.fill(0)
	for i in n:
		_update_kinv(i)


func _spring_material(s: int, pa: Vector2, pb: Vector2, st_a: int, st_b: int) -> void:
	var st_m := stone_at((pa + pb) * 0.5)
	var scatter := exp(_rng.randfn(0.0, strength_scatter))
	if st_a >= 0 and st_a == st_b and st_m == st_a:
		kind.append(Kind.STONE)
		k.append(stone_stiffness)
		strength.append(1e9)
	elif st_a >= 0 or st_b >= 0 or st_m >= 0:
		kind.append(Kind.FACE)
		k.append(1.0)
		strength.append(face_strength * scatter)
	else:
		kind.append(Kind.MASTIC)
		k.append(1.0)
		strength.append(scatter * (0.5 if _rng.randf() < void_share else 1.0))
	damage.append(0.0)
	broke_at.append(-1.0)
	e_cold.append(0.0)
	e_wheel.append(0.0)


# --- Reading the result -------------------------------------------------------------------------------------------

func stats() -> Dictionary:
	var crack_m := 0.0
	var path_m := 0.0
	for s in broken:
		var l := spacing / sqrt(3.0)
		crack_m += l
		if _wheel_load(pos[sa[s]].x) > 0.3:
			path_m += l
	return { year = time, springs = sa.size(), broken = broken.size(), crack_m = crack_m, wheel_path_m = path_m,
			stones = stone_c.size() }
