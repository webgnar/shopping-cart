class_name AsphaltCanvas
extends Node2D
## Draws an AsphaltSim on top of its base surface (a ColorRect with asphalt_base.gdshader), one pixel per
## 1 / px_per_m metres. In COLOR mode it paints what you see; in HEIGHT mode it paints a height map
## (0.5 grey = original surface, HEIGHT_RANGE metres either way to black and white) for the 3D roads later.

enum Mode { COLOR, HEIGHT }

const HEIGHT_RANGE := 0.1     ## m from mid grey to white (or black)
const PAINT_PIECE := 0.05     ## m: paint lines are drawn in pieces this long, each worn by its own amount
const CHUNK := 6              ## points per drawn piece of crack (each piece gets the width of its age)

@export var sim: AsphaltSim
@export var mode := Mode.COLOR
@export var px_per_m := 204.8
@export var base: CanvasItem                  ## the surface under the damage; its shader gets the surface state
@export var grain: Texture2D                  ## tiling noise for patches, fills, shoulder and pothole floors
@export var grain_scale := 0.6                ## m the grain texture spans

@export_group("Repair textures")
@export var patch_texture: Texture2D          ## fresh hot mix for heavy patches (seamless, top-down)
@export var patch_texture_m := 1.0            ## m the patch texture spans
@export var fill_texture: Texture2D           ## cold mix for throw-and-roll pothole fills
@export var fill_texture_m := 1.0
@export var sealant_texture: Texture2D        ## poured crack sealant
@export var sealant_texture_m := 0.5

@export_group("Damage textures")
@export var pothole_texture: Texture2D        ## wet base course at the bottom of a pothole
@export var pothole_texture_m := 0.5
@export var broken_texture: Texture2D         ## broken, ravelled asphalt: pothole rims and spalled crack edges
@export var broken_texture_m := 0.5
@export var base_course_texture: Texture2D    ## dry base course where the edge has fretted away
@export var base_course_texture_m := 1.0
@export var shoulder_texture: Texture2D       ## the gravel shoulders
@export var shoulder_texture_m := 1.0

@export_group("Paint")
@export var paint_texture: Texture2D          ## line paint, top-down (white, worn); without one, paint_color
@export var paint_texture_m := 0.5
@export var paint_color := Color(0.88, 0.88, 0.84)

@export_group("Colours")
@export var fresh_asphalt := Color(0.075, 0.075, 0.08)
@export var aged_asphalt := Color(0.37, 0.365, 0.35)
@export var cold_mix := Color(0.09, 0.085, 0.08)
@export var crack_color := Color(0.03, 0.03, 0.03)
@export var spall_color := Color(0.33, 0.31, 0.29)      ## broken crack edges, aggregate showing
@export var loose_stone := Color(0.42, 0.4, 0.37)      ## stones crumbled out of wide cracks
@export var sealant_fresh := Color(0.02, 0.02, 0.025)
@export var sealant_aged := Color(0.16, 0.16, 0.16)
@export var pothole_rim := Color(0.40, 0.37, 0.33)
@export var pothole_floor := Color(0.27, 0.23, 0.19)      ## wet base course
@export var base_course := Color(0.50, 0.45, 0.38)        ## where the edge has fretted away
@export var shoulder_color := Color(0.45, 0.40, 0.31)
@export var oxidation_years := 9.0


func _ready() -> void:
	if sim:
		sim.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if base and sim:
		base.size = sim.size * px_per_m
		var m := (base as CanvasItem).material as ShaderMaterial
		if m:
			var age := sim.surface_age()
			m.set_shader_parameter("size_m", sim.size)
			m.set_shader_parameter("surface_age", age * sim.climate)
			m.set_shader_parameter("ravel", clampf((age * sim.climate - 6.0) / 18.0, 0.0, 1.0))
			m.set_shader_parameter("rut_depth", sim.rut_depth())
			m.set_shader_parameter("chip_seal", 1.0 if sim.surface_kind == AsphaltSim.Surface.CHIP_SEAL else 0.0)
			m.set_shader_parameter("height_mode", mode == Mode.HEIGHT)
			m.set_shader_parameter("age_scale", oxidation_years)
			m.set_shader_parameter("seed", float(sim.seed % 97) * 3.17 + sim.surface_born * 7.3)
			var wp := sim.wheel_paths
			m.set_shader_parameter("wheel_paths", Vector4(wp[0], wp[1], wp[2], wp[3]) if wp.size() >= 4 else Vector4.ZERO)
			m.set_shader_parameter("lane_joint", sim.lane_joint_x)
			m.set_shader_parameter("shoulder", sim.shoulder)
	queue_redraw()


func _h(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0)


func _hc(h: float) -> Color:
	var v := clampf(0.5 + h / (2.0 * HEIGHT_RANGE), 0.0, 1.0)
	return Color(v, v, v)


func _aged(age: float) -> Color:
	return fresh_asphalt.lerp(aged_asphalt, 1.0 - exp(-maxf(age, 0.0) * sim.climate / oxidation_years))


func _poly(pts: PackedVector2Array, c: Color, scale := 1.0) -> void:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / (grain_scale * scale * px_per_m))
	if grain and mode == Mode.COLOR:
		draw_colored_polygon(pts, c, uvs, grain)
	else:
		draw_colored_polygon(pts, c)


## A damage area: its texture in the colour map (darkened by `dark`), else the flat colour with grain.
func _surface(pts: PackedVector2Array, c: Color, scale: float, tex: Texture2D, metres: float, dark := 0.0) -> void:
	if tex and mode == Mode.COLOR:
		_textured(pts, tex, metres, Color.BLACK, dark)
	else:
		_poly(pts, c, scale)


## How far a repair `age` years old has greyed towards aged_asphalt (fills grey faster: `speed` < 1).
func _greying(age: float, speed: float) -> float:
	return 0.85 * (1.0 - exp(-maxf(age, 0.0) * sim.climate / (oxidation_years * speed)))


## A polygon (pixels) filled with a tiling texture `metres` across, then washed with `wash` at `amount`.
func _textured(pts: PackedVector2Array, tex: Texture2D, metres: float, wash: Color, amount: float) -> void:
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / (metres * px_per_m))
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)
	if amount > 0.01:
		draw_colored_polygon(pts, Color(wash, amount))


## A texture `metres` across along a polyline (pixels) as a strip `width` pixels wide, washed with `wash` at
## `amount`. Neighbouring quads share their corners (the side offset at each point is the average of its two
## segments), so no steps.
func _textured_band(seg: PackedVector2Array, width: float, tex: Texture2D, metres: float, wash: Color, amount: float) -> void:
	var n := seg.size()
	var side := PackedVector2Array()
	side.resize(n)
	for j in n:
		var d := seg[mini(j + 1, n - 1)] - seg[maxi(j - 1, 0)]
		side[j] = d.orthogonal().normalized() * width * 0.5 if d.length_squared() > 1e-6 else Vector2.ZERO
	for j in n - 1:
		if side[j] == Vector2.ZERO or side[j + 1] == Vector2.ZERO:
			continue
		var quad := PackedVector2Array([seg[j] + side[j], seg[j + 1] + side[j + 1], seg[j + 1] - side[j + 1], seg[j] - side[j]])
		var uvs := PackedVector2Array()
		for q in quad:
			uvs.append(q / (metres * px_per_m))
		# draw_primitive, not a polygon: at a sharp bend the quad can fold over, which polygons refuse.
		draw_primitive(quad, PackedColorArray([Color.WHITE]), uvs, tex)
		if amount > 0.01:
			draw_primitive(quad, PackedColorArray([Color(wash, amount)]), PackedVector2Array())


func _circle_pts(c: Vector2, r: float, seed_n: float, rough: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 10
	for k in n:
		var a := TAU * k / n
		var rr := r * (1.0 + rough * (_h(seed_n + k * 1.7) - 0.5))
		pts.append((c + Vector2.from_angle(a) * rr) * px_per_m)
	return pts


## A cell outline grown or shrunk about its centre, its corners nudged so the edge looks broken, in pixels.
func _scaled(poly: PackedVector2Array, centre: Vector2, k: float, seed_n: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in poly.size():
		var q := centre + (poly[j] - centre) * (k + 0.08 * (_h(seed_n * 7.1 + j) - 0.5))
		out.append(q * px_per_m)
	return out


func _draw() -> void:
	if sim == null or sim.nx == 0:
		return
	var t := sim.time
	var hm := mode == Mode.HEIGHT
	# Paint lines, worn away in patches (patches and fills are drawn over them, cracks through them).
	var paint_dirt := clampf(sim.surface_age() / 20.0, 0.0, 1.0) * 0.3
	for k in range(0, sim.paint_lines.size() - 1, 2):
		var a := sim.paint_lines[k]
		var b := sim.paint_lines[k + 1]
		var along := (b - a).normalized()
		var side := along.orthogonal() * sim.paint_width * 0.5
		var n := maxi(1, int(ceil(a.distance_to(b) / PAINT_PIECE)))
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var left := sim.paint_left((p0 + p1) * 0.5)
			if left <= 0.02:
				continue
			var quad := PackedVector2Array([(p0 + side) * px_per_m, (p1 + side) * px_per_m, (p1 - side) * px_per_m, (p0 - side) * px_per_m])
			if hm:
				draw_primitive(quad, PackedColorArray([_hc(sim.paint_thickness * left)]), PackedVector2Array())
			elif paint_texture:
				var uvs := PackedVector2Array()
				for q in quad:
					uvs.append(q / (paint_texture_m * px_per_m))
				draw_primitive(quad, PackedColorArray([Color(Color.WHITE.lerp(aged_asphalt, paint_dirt), left)]), uvs, paint_texture)
			else:
				draw_primitive(quad, PackedColorArray([Color(paint_color.lerp(aged_asphalt, paint_dirt), left)]), PackedVector2Array())
	# Heavy patches: fresh full-depth asphalt in a saw-cut rectangle, greying with its own age.
	for p in sim.patches:
		var r: Rect2 = p.rect
		var age: float = t - p.born
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		for k in 4:
			pts[k] *= px_per_m
		if patch_texture and not hm:
			_textured(pts, patch_texture, patch_texture_m, aged_asphalt, _greying(age, 1.0))
		else:
			_poly(pts, _hc(0.003) if hm else _aged(age).lightened(0.12), 0.4)
	# Cracks, oldest part widest; wide ones have broken, ravelled edges.
	for c in sim.cracks:
		if not c.alive or c.pts.size() < 2:
			continue
		var n := c.pts.size()
		var k := 0
		while k < n - 1:
			var e := mini(k + CHUNK, n - 1)
			var w := c.width((k + e) / 2, t)
			var seg := c.pts.slice(k, e + 1)
			for j in seg.size():
				seg[j] *= px_per_m
			var wpx := w * px_per_m
			if w > 0.005:
				var spall := minf(w * 2.2 + 0.008, 0.06) * px_per_m
				if broken_texture and not hm:
					_textured_band(seg, spall, broken_texture, broken_texture_m, Color.BLACK, 0.0)
				else:
					draw_polyline(seg, _hc(-0.004) if hm else spall_color, spall)
			var depth := -clampf(w * 4.0, 0.006, 0.06)
			var col := _hc(depth) if hm else crack_color
			if wpx < 1.5 and not hm:
				col.a = clampf(wpx * 0.9, 0.55, 1.0)
			draw_polyline(seg, col, maxf(wpx, 1.2), true)
			# Loose stones crumbled off the edges of wide cracks, kicked about by traffic.
			if w > 0.006 and not hm:
				var stones := int(minf((w - 0.006) * 900.0, 6.0))
				for s in stones:
					var hs := _h(k * 7.1 + s * 3.3 + c.pts[0].x * 13.0)
					var at := seg[int(hs * (seg.size() - 1))]
					var off := Vector2(_h(hs * 91.0) - 0.5, _h(hs * 57.0) - 0.5) * (w * 3.0 + 0.02) * px_per_m
					draw_circle(at + off, (0.002 + 0.004 * _h(hs * 33.0)) * px_per_m, loose_stone.darkened(0.3 * _h(hs * 17.0)))
			k = e
	# Crack sealant: a band of rubberised bitumen poured over each filled crack, worn and debonding with age.
	for c in sim.cracks:
		if not c.alive or c.seal_from < 0.0 or c.seal_from > t or c.pts.size() < 2:
			continue
		var age := t - c.seal_from
		var col := _hc(0.002) if hm else sealant_fresh.lerp(sealant_aged, clampf(age / 10.0, 0.0, 1.0))
		var failing := clampf((age - AsphaltSim.SEAL_LIFE) / AsphaltSim.SEAL_LIFE, 0.0, 0.7)
		var n := c.pts.size()
		var k := 0
		var piece := 0
		while k < n - 1:
			var e := mini(k + CHUNK, n - 1)
			if c.born[e] > c.seal_from:
				break
			piece += 1
			if _h(floorf(piece / 3.0) * 3.1 + c.pts[0].x) >= failing:
				var seg := c.pts.slice(k, e + 1)
				for j in seg.size():
					seg[j] *= px_per_m
				var band := (0.06 + 0.025 * _h(piece + c.pts[0].y) + c.width(k, c.seal_from) * 2.0) * px_per_m
				draw_polyline(seg, col, band)
				if sealant_texture and not hm:
					_textured_band(seg, band, sealant_texture, sealant_texture_m, sealant_aged, clampf(age / 10.0, 0.0, 1.0) * 0.8)
			k = e
	# Throw-and-roll fills: lumpy cold-mix blobs over the cracks they filled, a little proud of the surface.
	for i in sim.nx * sim.ny:
		var fb := sim.fill_born[i]
		if fb < 0.0:
			continue
		var c := sim.cell_center(i) + Vector2(_h(i) - 0.5, _h(i + 0.5) - 0.5) * 0.03
		if fill_texture and not hm:
			_textured(_circle_pts(c, 0.105, i * 0.37, 0.35), fill_texture, fill_texture_m, aged_asphalt, _greying(t - fb, 0.6))
			continue
		var col := _hc(0.006) if hm else cold_mix.lerp(aged_asphalt, 1.0 - exp(-(t - fb) * sim.climate / (oxidation_years * 0.6)))
		_poly(_circle_pts(c, 0.105, i * 0.37, 0.35), col, 0.3)
	# Potholes. Where a crocodile cell has been plucked out: its broken rim, then the wet base course below,
	# darker the deeper it goes. Elsewhere a ragged hole round the 10 cm cell.
	for k in sim.plucked.size():
		var d := sim.plucked[k]
		if d <= 0.0 or sim.net_cells[k].is_empty():
			continue
		_surface(_scaled(sim.net_cells[k], sim.net_seeds[k], 1.1, k), _hc(-d * 0.3) if hm else pothole_rim, 0.25, broken_texture, broken_texture_m)
	for k in sim.plucked.size():
		var d := sim.plucked[k]
		if d <= 0.0 or sim.net_cells[k].is_empty():
			continue
		var col := _hc(-d) if hm else pothole_floor.darkened(clampf(d / AsphaltSim.HOLE_MAX, 0.0, 1.0) * 0.45)
		_surface(_scaled(sim.net_cells[k], sim.net_seeds[k], 1.0, k + 0.5), col, 0.15, pothole_texture, pothole_texture_m, clampf(d / AsphaltSim.HOLE_MAX, 0.0, 1.0) * 0.45)
	for i in sim.nx * sim.ny:
		if sim.hole[i] <= 0.0 or sim._cell_seed[i] >= 0:
			continue
		var c := sim.cell_center(i) + Vector2(_h(i * 1.3) - 0.5, _h(i * 2.1) - 0.5) * 0.03
		var d := sim.hole[i]
		_surface(_circle_pts(c, 0.11, i * 0.91, 0.5), _hc(-d * 0.3) if hm else pothole_rim, 0.25, broken_texture, broken_texture_m)
		_surface(_circle_pts(c, 0.085, i * 0.53, 0.35), _hc(-d) if hm else pothole_floor.darkened(clampf(d / AsphaltSim.HOLE_MAX, 0.0, 1.0) * 0.45), 0.15,
			pothole_texture, pothole_texture_m, clampf(d / AsphaltSim.HOLE_MAX, 0.0, 1.0) * 0.45)
	# Shoulders, and the pavement edge fretted back into them.
	for side in 2:
		var e := sim.edge_l if side == 0 else sim.edge_r
		var fret := PackedVector2Array()
		var dirt := PackedVector2Array()
		var x0 := 0.0 if side == 0 else sim.size.x
		var xs := sim.shoulder if side == 0 else sim.size.x - sim.shoulder
		var sgn := 1.0 if side == 0 else -1.0
		for row in sim.ny + 1:
			var r := mini(row, sim.ny - 1)
			var y := row * AsphaltSim.CELL
			var j := (_h(row * 4.7 + side) - 0.5) * 0.03 * minf(e[r] * 10.0, 1.0)
			fret.append(Vector2(xs + sgn * (e[r] + j), y) * px_per_m)
			dirt.append(Vector2(xs - sgn * (0.02 + 0.02 * _h(row + side * 9.0)) + sgn * e[r] * 0.35, y) * px_per_m)
		var fret_poly := PackedVector2Array([Vector2(x0, 0.0) * px_per_m])
		fret_poly.append_array(fret)
		fret_poly.append(Vector2(x0, sim.size.y) * px_per_m)
		_surface(fret_poly, _hc(-0.03) if hm else base_course, 0.2, base_course_texture, base_course_texture_m)
		var dirt_poly := PackedVector2Array([Vector2(x0, 0.0) * px_per_m])
		dirt_poly.append_array(dirt)
		dirt_poly.append(Vector2(x0, sim.size.y) * px_per_m)
		_surface(dirt_poly, _hc(-0.04) if hm else shoulder_color, 0.2, shoulder_texture, shoulder_texture_m)
