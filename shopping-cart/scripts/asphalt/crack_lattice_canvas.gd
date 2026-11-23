class_name CrackLatticeCanvas
extends Node2D
## Draws a CrackLattice patch from above: mastic that greys as the binder ages, the stones (their binder film wears
## off with age and traffic) and the cracks. A crack is drawn along the faces of its broken springs, and each piece is
## pushed off any stone it would cross, so it runs round the stones the way real cracks do.

const ROUTE_STEP := 0.0015  ## m between the points of a drawn crack
const CROSS_SPREAD := 0.3  ## a crack crosses a spring anywhere in its middle 60%
const BRIDGE := 3.0         ## crack tips closer than this many mesh spacings are drawn joined
const MAX_DETOUR := 0.006   ## m a crack goes out of its way round a stone (past that it breaks through it)

@export var sim: CrackLattice
@export var px_per_m := 512.0
@export var grain: Texture2D                ## tiling noise over the mastic
@export var grain_scale := 0.6              ## m the grain texture spans
@export var grain_strength := 0.35

@export_group("Colours")
@export var fresh_mastic := Color(0.075, 0.075, 0.08)
@export var aged_mastic := Color(0.33, 0.325, 0.31)
@export var stone_dark := Color(0.36, 0.34, 0.31)
@export var stone_light := Color(0.62, 0.6, 0.56)
@export var crack_color := Color(0.025, 0.025, 0.025)
@export var spall_color := Color(0.30, 0.285, 0.27)

var _routes := { }          ## crack pieces in metres, routed round the stones
var _mids := { }            ## spring -> its middle, off the stones


func _ready() -> void:
	if sim:
		sim.changed.connect(_refresh)


func _refresh() -> void:
	if sim and sim.time == 0.0:
		_routes.clear()
		_mids.clear()
	queue_redraw()


func _draw() -> void:
	if not sim or sim.pos.is_empty():
		return
	var ox := sim.oxidation()
	var mastic := fresh_mastic.lerp(aged_mastic, ox)
	var area := Rect2(Vector2.ZERO, sim.size * px_per_m)
	draw_rect(area, mastic)
	if grain:
		var g := Color(mastic.r * 1.5, mastic.g * 1.5, mastic.b * 1.5, grain_strength)
		draw_texture_rect(grain, area, true, g)
	# stones: coated in binder when new, the film wears off with age, faster in the wheel path
	var coat := fresh_mastic.lerp(aged_mastic, ox).lightened(0.08)
	for i in sim.stone_c.size():
		var wear := clampf(0.15 + 0.5 * ox + 0.35 * sim._wheel_load(sim.stone_c[i].x) * clampf(sim.time / 15.0, 0.0, 1.0),
				0.0, 1.0)
		var col := coat.lerp(stone_dark.lerp(stone_light, sim.stone_shade[i]), wear)
		var pts := sim.stone_outline(i)
		for off in _copies(sim.stone_c[i], sim.stone_r[i] * 1.3):
			var poly := PackedVector2Array()
			for p in pts:
				poly.append((p + off) * px_per_m)
			draw_colored_polygon(poly, col)
	# cracks: through each triangle from the middle of one broken side to the next (spalled edges first)
	var pieces := _pieces()
	for pass_i in 2:
		for pc: Array in pieces:
			var route: PackedVector2Array = pc[0]
			var w: float = pc[1]
			var col := crack_color
			if pass_i == 0:
				var spall: float = clampf((sim.time - pc[2]) / 12.0, 0.0, 1.0) * 1.4
				if spall <= 0.05:
					continue
				w *= 1.0 + spall
				col = spall_color.lerp(mastic, 0.3)
			var wp := maxf(1.0, w * px_per_m)
			for off in _copies(route[0], 0.03):
				var line := PackedVector2Array()
				for p in route:
					line.append((p + off) * px_per_m)
				draw_polyline(line, col, wp, true)
				if wp > 2.0:
					draw_circle(line[0], wp * 0.5, col, true, -1.0, true)
					draw_circle(line[line.size() - 1], wp * 0.5, col, true, -1.0, true)


## The drawn pieces of crack now: [route (m), width (m), year the older side broke]. A triangle with two broken sides
## carries a crack from one side's middle to the other's; with three, all three meet at its centre; with one, it is
## the tip of a crack running into it (drawn halfway in), unless the spring broke on its own (a microcrack, not drawn).
func _pieces() -> Array:
	var out := []
	var tips: Array[Vector2] = []
	var tip_w := PackedFloat32Array()
	var tip_born := PackedFloat32Array()
	var nt := sim.tri_c.size()
	for t in nt:
		var bs := PackedInt32Array()
		for j in 3:
			var s := sim.tri[t * 3 + j]
			if sim.broke_at[s] >= 0.0:
				bs.append(s)
		if bs.is_empty():
			continue
		var c := sim.tri_c[t]
		if bs.size() == 2:
			out.append(_piece(bs[0], _near(_mid(bs[1]), _mid(bs[0])), _mid(bs[0]), sim.crack_width(bs[0]),
					sim.crack_width(bs[1]), minf(sim.broke_at[bs[0]], sim.broke_at[bs[1]]), "%d-%d" % [bs[0], bs[1]]))
		elif bs.size() == 3:
			for s in bs:
				var w := sim.crack_width(s)
				out.append(_piece(s, _near(sim.push_off_stones(c), _mid(s)), _mid(s), w, w, sim.broke_at[s], "%d@%d" % [s, t]))
		else:
			var s := bs[0]
			var other := sim.spring_tri[s * 2] if sim.spring_tri[s * 2] != t else sim.spring_tri[s * 2 + 1]
			var n_other := 0
			for j in 3:
				if sim.broke_at[sim.tri[other * 3 + j]] >= 0.0:
					n_other += 1
			if n_other < 2:
				continue
			var m := _mid(s)
			var w := sim.crack_width(s)
			out.append(_piece(s, m, _near(m.lerp(_near(c, m), 0.5), m), w, w * 0.3, sim.broke_at[s], "%d^%d" % [s, t]))
			tips.append(m)
			tip_w.append(w)
			tip_born.append(sim.broke_at[s])
	# Cracks that run past each other leave thin ligaments between their tips that still hold. They break later, but
	# from above the two cracks already look like one: join tips that end close together with a thinner piece.
	var used := { }
	for i in tips.size():
		if used.has(i):
			continue
		var best := -1
		var best_d := BRIDGE * sim.spacing
		for j in range(i + 1, tips.size()):
			if used.has(j):
				continue
			var d := _near(tips[j], tips[i]).distance_to(tips[i])
			if d < best_d and d > 0.4 * sim.spacing:
				best_d = d
				best = j
		if best >= 0:
			used[i] = true
			used[best] = true
			var w := minf(tip_w[i], tip_w[best]) * 0.6
			out.append(_piece(-1, tips[i], _near(tips[best], tips[i]), w, w, maxf(tip_born[i], tip_born[best]),
					"b%d,%d" % [i, best] + str(tips[i])))
	return out


func _piece(s: int, a: Vector2, b: Vector2, wa: float, wb: float, born: float, key: String) -> Array:
	var route: PackedVector2Array = _routes.get(key, PackedVector2Array())
	if route.is_empty():
		route = _route(a, b)
		_routes[key] = route
	return [route, (wa + wb) * 0.5, born]


## Where the crack crosses spring s: somewhere along it (so cracks don't follow the mesh's rows), off the stones.
func _mid(s: int) -> Vector2:
	if not _mids.has(s):
		var along := (float(hash(s * 7919 + sim.seed) % 1000) / 999.0 - 0.5) * 2.0 * CROSS_SPREAD
		_mids[s] = sim.push_off_stones(sim.mid[s] + sim.dir[s] * sim.length[s] * along)
	return _mids[s]


## p moved by whole patch sizes to sit next to `to` (across the wrapped edge).
func _near(p: Vector2, to: Vector2) -> Vector2:
	var d := p - to
	return to + Vector2(d.x - roundf(d.x / sim.size.x) * sim.size.x, d.y - roundf(d.y / sim.size.y) * sim.size.y)


## A crack piece from a to b, split into ROUTE_STEP pieces, every inner point pushed off the stones sideways (at
## most MAX_DETOUR), so it runs round them.
func _route(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := b - a
	var n := maxi(1, int(ceil(d.length() / ROUTE_STEP)))
	var normal := Vector2(-d.y, d.x).normalized()
	var out := PackedVector2Array([a])
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var q := sim.push_off_stones(p, normal)
		out.append(q if q.distance_to(p) < MAX_DETOUR else p)
	out.append(b)
	return out


## Offsets (m) to draw something at p of radius r so it also shows across the wrapped edges of the patch.
func _copies(p: Vector2, r: float) -> Array[Vector2]:
	var xs := [0.0]
	var ys := [0.0]
	if p.x - r < 0.0:
		xs.append(sim.size.x)
	if p.x + r > sim.size.x:
		xs.append(-sim.size.x)
	if p.y - r < 0.0:
		ys.append(sim.size.y)
	if p.y + r > sim.size.y:
		ys.append(-sim.size.y)
	var out: Array[Vector2] = []
	for x: float in xs:
		for y: float in ys:
			out.append(Vector2(x, y))
	return out
