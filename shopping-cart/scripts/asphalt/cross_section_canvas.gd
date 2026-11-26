class_name CrossSectionCanvas
extends Control
## The asphalt lab's cross-section: a vertical slice across the road at `cut_y`, drawn to scale from the sim's
## build-up (AsphaltSim.pavement()) and its real height map (AsphaltSim.bake_height), in the diagram style of the
## LTPP Distress Identification Manual (FHWA-HRT-13-092): black line art on white, the section cut A-B, the
## shoulder hatched and boxed SHOULDER, the centreline, edge stripe and LANE marked, rut depth under a 1.2 m
## straightedge and crack width between arrows (figs. 1, 31, 43), and the map symbols of fig. 137 (heavy patch solid
## black, S for sealed). The LTPP figures draw only the surface; the layers under it use drafting hatches in the
## same style (asphalt stippled, aggregate base circles, subgrade earth hatch). Crack depth is still a placeholder
## (AsphaltSim.crack_depth): its solid notch is the opening, the dashed line below it the guessed depth. Depth is
## exaggerated by the largest of EXAGGERATIONS that fits. The cut is marked on `plan_view` (the colour map).

@export var sim: AsphaltSim
@export var plan_view: TextureRect             ## the plan (colour map) the cut line is drawn on
@export var cut_y := 5.0                        ## m along the road where the section is taken
@export var res := 0.02                         ## m between profile samples (and height-map pixels)
@export var subgrade_shown := 0.06              ## m of subgrade drawn under the build-up
@export var headroom := 0.02                    ## m drawn above the design level (patches, paint, sealant)
@export var paper := Color(1.0, 1.0, 1.0)
@export var ink := Color(0.0, 0.0, 0.0)
@export var plan_mark := Color(1.0, 1.0, 1.0)   ## the cut line on the colour plan

enum M { AIR, ASPHALT, BASE, SUBGRADE, SHOULDER, PATCH, FILL }

const MARGIN := Vector2(14.0, 44.0)             ## px: left/right and top margins inside the panel
const GUTTER := 150.0                           ## px on the right for the layer labels
const FOOT := 58.0                              ## px at the bottom: legend and caption
const EXAGGERATIONS := [20.0, 10.0, 5.0, 2.0, 1.0]   ## depth scales tried, largest first (section drawings use 10-20x)
const FONT := 10                                ## px: LTPP figure lettering is small sans

var _hmap := PackedFloat32Array()               ## the whole height map at `res`, baked once per sim change
var _w := 0                                     ## height-map columns
var profile := PackedFloat32Array()             ## m: surface height along the cut, one sample per `res`


func _ready() -> void:
	if plan_view:
		plan_view.draw.connect(_draw_cut_on_plan)
	resized.connect(queue_redraw)


## Bake the sim's height map again (after the road changes) and redraw.
func refresh() -> void:
	if sim == null:
		return
	_hmap = sim.bake_height(res)
	_w = int(round(sim.size.x / res)) + 1
	set_cut(cut_y)


## Move the cut (m along the road) and redraw; cheap, the height map is kept.
func set_cut(y: float) -> void:
	cut_y = clampf(y, 0.0, sim.size.y if sim else y)
	if _hmap.size() > 0:
		var iy := clampi(int(round(cut_y / res)), 0, _hmap.size() / _w - 1)
		profile = _hmap.slice(iy * _w, iy * _w + _w)
	queue_redraw()
	if plan_view:
		plan_view.queue_redraw()


## The cracks the cut crosses: { x, width, depth, sealed, kind, code }, in metres. `code` is the LTPP distress
## number with its width severity where the manual rates by width (e.g. "4aM", "6L"; "1" for fatigue).
func crossings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in sim.cracks:
		if not c.alive or c.pts.size() < 2:
			continue
		for k in c.pts.size() - 1:
			var a := c.pts[k]
			var b := c.pts[k + 1]
			if (a.y - cut_y) * (b.y - cut_y) > 0.0 or is_equal_approx(a.y, b.y):
				continue
			var x := lerpf(a.x, b.x, (cut_y - a.y) / (b.y - a.y))
			var i := sim.cell_index(Vector2(x, cut_y))
			if sim.fill_born[i] >= 0.0 and c.born[k + 1] <= sim.fill_born[i]:
				continue   # buried under a cold patch
			var w := c.width(k, sim.time)
			var sealed := c.sealed(sim.time)
			out.append({ x = x, width = w, depth = sim.crack_depth(c.width(k, c.seal_from) if sealed else w),
				sealed = sealed, kind = c.kind, code = _ltpp_code(c.kind, b - a, x, w, sealed) })
	return out


## LTPP DIM distress number for a crack, plus L/M/H where it is rated by mean width (<= 6, 6-19, > 19 mm).
func _ltpp_code(kind: int, dir: Vector2, x: float, w: float, sealed: bool) -> String:
	var along := absf(dir.y) >= absf(dir.x)     # runs with the road: longitudinal
	var code := ""
	match kind:
		AsphaltSim.Kind.FATIGUE:
			return "1"
		AsphaltSim.Kind.BLOCK:
			code = "2"
		AsphaltSim.Kind.EDGE:
			return "3"
		AsphaltSim.Kind.SEAM:
			return "7"
		AsphaltSim.Kind.TRANSVERSE:
			code = "6"
		_:
			if along:
				code = "4a" if _in_wheel_path(x) else "4b"
			else:
				code = "6"
	if sealed:
		return code + "L"   # sealed in good condition, width not measurable: low
	return code + AsphaltSurvey.severity_of_width(w)


func _in_wheel_path(x: float) -> bool:
	for wp in sim.wheel_paths:
		if absf(x - wp) <= AsphaltSurvey.WHEEL_PATH_HALF:
			return true
	return false


## Rut depth in each wheel path, m, the LTPP way (ACP 9): the largest gap under a 1.2 m straightedge laid across the
## wheel path. The profile is first smoothed over 14 cm so narrow cracks don't read as rutting.
## Returns [{ x, depth, a, b }] with the straightedge's ends a, b (Vector2: x m, z m).
func rut_depths() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if profile.is_empty():
		return out
	for wp in sim.wheel_paths:
		out.append(AsphaltSurvey.straightedge_rut(profile, res, wp))
	return out


## Where the plan image sits inside plan_view (the texture is square and kept centred).
func plan_rect() -> Rect2:
	var s := minf(plan_view.size.x, plan_view.size.y)
	return Rect2((plan_view.size - Vector2(s, s)) * 0.5, Vector2(s, s))


## m along the road for a point on plan_view, or -1 outside the image.
func plan_to_y(pos: Vector2) -> float:
	var r := plan_rect()
	if not r.has_point(pos):
		return -1.0
	return (pos.y - r.position.y) / r.size.y * sim.size.y


## The cut on the plan as in LTPP figs. 31 and 43: a dashed line with a flag and arrow at each end, A and B.
func _draw_cut_on_plan() -> void:
	if not visible or sim == null:
		return
	var r := plan_rect()
	var y := r.position.y + cut_y / sim.size.y * r.size.y
	var font := ThemeDB.fallback_font
	plan_view.draw_dashed_line(Vector2(r.position.x, y), Vector2(r.end.x, y), plan_mark, 1.5, 8.0)
	for end in [[r.position.x + 3.0, "A"], [r.end.x - 3.0, "B"]]:
		var x: float = end[0]
		plan_view.draw_line(Vector2(x, y - 14.0), Vector2(x, y + 4.0), plan_mark, 1.5)
		plan_view.draw_line(Vector2(x, y - 14.0), Vector2(x + 9.0 * (1.0 if end[1] == "A" else -1.0), y - 14.0), plan_mark, 1.5)
		var tip := Vector2(x + 9.0 * (1.0 if end[1] == "A" else -1.0), y - 14.0)
		plan_view.draw_line(tip, tip + Vector2(0.0, -3.0) + Vector2(-3.0 if end[1] == "A" else 3.0, 0.0), plan_mark, 1.5)
		plan_view.draw_line(tip, tip + Vector2(0.0, 3.0) + Vector2(-3.0 if end[1] == "A" else 3.0, 0.0), plan_mark, 1.5)
		plan_view.draw_string(font, Vector2(x + (12.0 if end[1] == "A" else -20.0), y - 9.0), end[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, plan_mark)


func _draw() -> void:
	var panel := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	draw_rect(panel, paper)
	draw_rect(panel, ink, false, 1.0)
	if sim == null or profile.is_empty():
		return
	var b := sim.pavement()
	var h_a := b.asphalt_thickness()
	var h_total := 0.0
	for l in b.layers:
		h_total += l.thickness
	var area := Rect2(MARGIN, size - MARGIN - Vector2(MARGIN.x + GUTTER, FOOT))
	var sx := area.size.x / sim.size.x                    # px per m across
	var depth_m := headroom + h_total + subgrade_shown
	var exag := 1.0
	for e: float in EXAGGERATIONS:
		if depth_m * sx * e <= area.size.y:
			exag = e
			break
	var sz := sx * exag                                   # px per m of depth
	var X := func(x: float) -> float: return area.position.x + x * sx
	var Y := func(z: float) -> float: return area.position.y + (headroom - z) * sz
	var font := ThemeDB.fallback_font
	var n := profile.size()
	var col_w := res * sx

	# What each column holds, top to bottom: the material bands [material, top z, bottom z].
	var cols: Array[Array] = []
	var patch_cols := { }
	for i in n:
		var x := i * res
		var p := Vector2(x, cut_y)
		var s := profile[i]
		var bands: Array = []
		var paved := sim.paved(p) if x > 0.0 and x < sim.size.x else false
		var patch := -1
		for k in sim.patches.size():
			if (sim.patches[k].rect as Rect2).has_point(p):
				patch = k
		if patch >= 0:
			bands.append([M.PATCH, s, -h_total])
			patch_cols[patch] = patch_cols.get(patch, []) + [i]
		elif not paved:
			bands.append([M.SHOULDER, s, -h_total])
		else:
			var ci := sim.cell_index(p)
			var top := s
			if sim.fill_born[ci] >= 0.0:
				bands.append([M.FILL, s, -sim.fill_depth[ci]])
				top = -sim.fill_depth[ci]
			if top > -h_a:
				bands.append([M.ASPHALT, top, -h_a])
			bands.append([M.BASE, minf(top, -h_a), -h_total])
		bands.append([M.SUBGRADE, -h_total, -h_total - subgrade_shown])
		cols.append(bands)

	# Fills: solid black for heavy patches (LTPP map symbol 7), as one polygon per patch; the rest stays paper and
	# gets its hatch.
	for k in patch_cols:
		var ii: Array = patch_cols[k]
		var poly := PackedVector2Array()
		for i: int in ii:
			poly.append(Vector2(X.call(i * res), Y.call(profile[i])))
		poly.append(Vector2(X.call(ii[ii.size() - 1] * res), Y.call(-h_total)))
		poly.append(Vector2(X.call(ii[0] * res), Y.call(-h_total)))
		if poly.size() >= 3:
			draw_colored_polygon(poly, ink)
	var hatch := PackedVector2Array()
	# Diagonal hatch lines, column by column: shoulder (LTPP's shoulder hatch, one way), subgrade (the other way,
	# wider), cold patch (both ways).
	for i in n:
		var x0: float = X.call(i * res) - col_w * 0.5
		var x1 := x0 + col_w
		for band in cols[i]:
			var ya: float = Y.call(band[1])
			var yb: float = Y.call(band[2])
			match band[0]:
				M.SHOULDER:
					_hatch(hatch, x0, x1, ya, yb, 5.0, 1.0)
				M.SUBGRADE:
					_hatch(hatch, x0, x1, ya, yb, 7.0, -1.0)
				M.FILL:
					_hatch(hatch, x0, x1, ya, yb, 3.5, 1.0)
					_hatch(hatch, x0, x1, ya, yb, 3.5, -1.0)
	if hatch.size() > 0:
		draw_multiline(hatch, ink, 1.0)
	# Stipple (asphalt) and circles (aggregate base) on fixed grids, so they don't crawl as the cut moves.
	var dots := PackedVector2Array()
	var gy0 := int(area.position.y)
	var gy1 := int(Y.call(-h_total - subgrade_shown))
	for gx in range(int(area.position.x), int(area.end.x), 4):
		var i := clampi(int(round((gx - area.position.x) / sx / res)), 0, n - 1)
		for gy in range(gy0, gy1, 4):
			var jx := gx + _hash(gx, gy) * 3.0
			var jy := gy + _hash(gy, gx) * 3.0
			if _material(cols[i], headroom - (jy - area.position.y) / sz) == M.ASPHALT:
				dots.append(Vector2(jx, jy))
				dots.append(Vector2(jx + 1.0, jy))
	if dots.size() > 0:
		draw_multiline(dots, ink, 1.0)
	var rings := PackedVector2Array()
	for gx in range(int(area.position.x), int(area.end.x), 9):
		for gy in range(gy0, gy1, 8):
			var c := Vector2(gx + 2.0 + _hash(gx, gy) * 4.0, gy + 2.0 + _hash(gy, gx) * 3.0)
			var r := 1.4 + _hash(gx + 7, gy) * 1.0
			var i := clampi(int(round((c.x - area.position.x) / sx / res)), 0, n - 1)
			var z0: float = headroom - (c.y - r - area.position.y) / sz
			var z1: float = headroom - (c.y + r - area.position.y) / sz
			if _material(cols[i], z0) == M.BASE and _material(cols[i], z1) == M.BASE:
				for k in 6:
					rings.append(c + Vector2.from_angle(TAU * k / 6.0) * r)
					rings.append(c + Vector2.from_angle(TAU * (k + 1) / 6.0) * r)
	if rings.size() > 0:
		draw_multiline(rings, ink, 1.0)

	# Outlines: the surface, the bottom of the asphalt, the bottom of the base, patch edges.
	var surface := PackedVector2Array()
	for i in n:
		surface.append(Vector2(X.call(i * res), Y.call(profile[i])))
	draw_polyline(surface, ink, 1.5)
	var run := PackedVector2Array()
	for i in n:
		var has := false
		for band in cols[i]:
			if band[0] == M.ASPHALT and is_equal_approx(band[2], -h_a):
				has = true
		if has:
			run.append(Vector2(X.call(i * res), Y.call(-h_a)))
		if (not has or i == n - 1) and run.size() > 1:
			draw_polyline(run, ink, 1.0)
		if not has:
			run = PackedVector2Array()
	draw_line(Vector2(area.position.x, Y.call(-h_total)), Vector2(area.end.x, Y.call(-h_total)), ink, 1.0)
	for k in patch_cols:
		var ii: Array = patch_cols[k]
		var xa: float = X.call(ii[0] * res) - col_w * 0.5
		var xb: float = X.call(ii[ii.size() - 1] * res) + col_w * 0.5
		# The code in a white circle on the black, as LTPP fig. 138 labels a patch.
		var pc := Vector2((xa + xb) * 0.5, (Y.call(0.0) + Y.call(-h_total)) * 0.5)
		draw_circle(pc, 7.0, ink)
		draw_arc(pc, 7.0, 0.0, TAU, 16, paper, 1.0)
		draw_string(font, pc + Vector2(-3.0, 3.5), "7", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, paper)

	# Sealcoat (a heavy line on the surface) and paint (an outlined strip on top).
	for i in n:
		var p := Vector2(i * res, cut_y)
		var top: float = Y.call(profile[i])
		for sp in sim.seal_spots:
			if Geometry2D.is_point_in_polygon(p, sp.poly) and sim.sealcoat_left(p, sp.born) > 0.1:
				draw_rect(Rect2(X.call(i * res) - col_w * 0.5, top - 2.5, col_w + 0.6, 2.5), ink)
		if _painted(p):
			draw_rect(Rect2(X.call(i * res) - col_w * 0.5, top - 3.0, col_w + 0.6, 3.0), paper)
			draw_line(Vector2(X.call(i * res) - col_w * 0.5, top - 3.0), Vector2(X.call(i * res) + col_w * 0.5, top - 3.0), ink, 1.0)

	# Cracks: the opening as a solid notch, the guessed depth dashed below it; S over a sealed one (fig. 137).
	var widest := { }
	for cr in crossings():
		var cx: float = X.call(cr.x)
		var top := _surface_at(cr.x, cr.width)
		var half := maxf(cr.width * 0.5 * sx, 0.6)
		var notch := minf(cr.depth, maxf(cr.width * 1.5, 0.003))
		draw_colored_polygon(PackedVector2Array([Vector2(cx - half, Y.call(top)), Vector2(cx + half, Y.call(top)),
			Vector2(cx, Y.call(top - notch))]), ink)
		draw_dashed_line(Vector2(cx, Y.call(top - notch)), Vector2(cx, Y.call(top - cr.depth)), ink, 1.0, 2.0)
		if cr.sealed:
			draw_string(font, Vector2(cx - 3.0, Y.call(top) - 4.0), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
		elif widest.is_empty() or cr.width > widest.width:
			widest = cr
	# Crack width, as LTPP fig. 1: two arrows pointing in at the crack edges, the label above.
	if not widest.is_empty():
		var cx: float = X.call(widest.x)
		var yt: float = Y.call(_surface_at(widest.x, widest.width)) - 10.0
		var half := maxf(widest.width * 0.5 * sx, 0.6)
		_arrow(Vector2(cx - half - 14.0, yt), Vector2(cx - half, yt))
		_arrow(Vector2(cx + half + 14.0, yt), Vector2(cx + half, yt))
		draw_line(Vector2(cx - half, yt - 3.0), Vector2(cx - half, yt + 3.0), ink, 1.0)
		draw_line(Vector2(cx + half, yt - 3.0), Vector2(cx + half, yt + 3.0), ink, 1.0)
		draw_string(font, Vector2(cx - 34.0, yt - 6.0), "Crack Width %.0f mm (%s)" % [widest.width * 1000.0, widest.code],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	# Rut depth under the 1.2 m straightedge, as LTPP fig. 31.
	for rut in rut_depths():
		if rut.depth < 0.002:
			continue
		var a: Vector2 = rut.a
		var e: Vector2 = rut.b
		draw_line(Vector2(X.call(a.x), Y.call(a.y)), Vector2(X.call(e.x), Y.call(e.y)), ink, 1.0)
		var rx: float = X.call(rut.x)
		var edge: float = lerpf(a.y, e.y, (rut.x - a.x) / maxf(e.x - a.x, 1e-4))
		var y_top: float = Y.call(edge)
		draw_line(Vector2(rx, y_top - 12.0), Vector2(rx, y_top), ink, 1.0)
		_arrow(Vector2(rx, y_top - 12.0), Vector2(rx, y_top))
		draw_string(font, Vector2(rx + 3.0, y_top - 13.0), "Rut %.0f mm" % (rut.depth * 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)

	# Road furniture: A and B at the ends of the cut, the centreline at the lane joint, LANE over each lane, the
	# pavement edges and SHOULDER boxed in its hatch (figs. 31, 43).
	var yz: float = Y.call(0.0)
	draw_string(font, Vector2(area.position.x - 11.0, yz + 4.0), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	draw_string(font, Vector2(area.end.x + 3.0, yz + 4.0), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	var cl: float = X.call(sim.lane_joint_x)
	draw_line(Vector2(cl, area.position.y - 30.0), Vector2(cl, area.position.y - 18.0), ink, 1.0)
	draw_string(font, Vector2(cl - 4.0, area.position.y - 31.0), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	draw_string(font, Vector2(cl - 1.0, area.position.y - 28.0), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
	for lane_x in [(sim.shoulder + sim.lane_joint_x) * 0.5, (sim.lane_joint_x + sim.size.x - sim.shoulder) * 0.5]:
		draw_string(font, Vector2(X.call(lane_x) - 12.0, area.position.y - 22.0), "LANE", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	if sim.shoulder > 0.0:
		for side in [0.0, 1.0]:
			var ex: float = X.call(sim.shoulder if side == 0.0 else sim.size.x - sim.shoulder)
			draw_line(Vector2(ex, area.position.y - 16.0), Vector2(ex, yz - 2.0), ink, 0.5)
			draw_string(font, Vector2(ex + (2.0 if side == 0.0 else -58.0), area.position.y - 9.0), "Pavement Edge",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
			var mid: float = X.call(sim.shoulder * 0.5 if side == 0.0 else sim.size.x - sim.shoulder * 0.5)
			var label := "SHOULDER"
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
			var box := Rect2(mid - tw * 0.5 - 2.0, Y.call(-h_total * 0.5) - 6.0, tw + 4.0, 9.0)
			draw_rect(box, paper)
			draw_rect(box, ink, false, 0.5)
			draw_string(font, box.position + Vector2(2.0, 7.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, ink)

	# Layer labels in the gutter, with leaders.
	var gx := area.end.x + 16.0
	var z := 0.0
	for l in b.layers:
		var mid: float = (Y.call(z) + Y.call(z - l.thickness)) * 0.5
		draw_line(Vector2(area.end.x + 1.0, mid), Vector2(gx - 3.0, mid), ink, 0.5)
		draw_string(font, Vector2(gx, mid - 1.0), l.title, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 18.0, FONT, ink)
		var note := "%.0f mm (%.1f in)" % [l.thickness * 1000.0, l.thickness / 0.0254]
		if z == 0.0 and sim.surface_born > 0.0:
			note += ", relaid yr %.0f" % sim.surface_born
		draw_string(font, Vector2(gx, mid + 10.0), note, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 18.0, FONT - 1, ink)
		z -= l.thickness
	var smid: float = Y.call(-h_total - subgrade_shown * 0.5)
	draw_line(Vector2(area.end.x + 1.0, smid), Vector2(gx - 3.0, smid), ink, 0.5)
	draw_string(font, Vector2(gx, smid - 1.0), "Subgrade", HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 18.0, FONT, ink)
	draw_string(font, Vector2(gx, smid + 10.0), "CBR %.0f (Mr ~%.0f MPa)" % [b.subgrade_cbr, b.subgrade_mr() / 1e6],
		HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 18.0, FONT - 1, ink)

	# Legend, scale bars and the caption, LTPP-style ("FIGURE n" bold, then the description).
	var ly := size.y - FOOT + 14.0
	var lx := MARGIN.x
	for item in [[M.ASPHALT, "Asphalt"], [M.BASE, "Aggregate base"], [M.SUBGRADE, "Subgrade"], [M.SHOULDER, "Shoulder"],
			[M.PATCH, "7 Heavy patch"], [M.FILL, "7 Cold patch"]]:
		_swatch(Rect2(lx, ly - 8.0, 16.0, 10.0), item[0])
		draw_string(font, Vector2(lx + 19.0, ly + 1.0), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
		lx += 30.0 + font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	draw_line(Vector2(lx, ly - 3.0), Vector2(lx + 4.0, ly - 3.0), ink, 2.0)
	draw_dashed_line(Vector2(lx + 4.0, ly - 3.0), Vector2(lx + 16.0, ly - 3.0), ink, 1.0, 2.0)
	draw_string(font, Vector2(lx + 19.0, ly + 1.0), "crack; dashed depth is a placeholder   S sealed",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	# Scale bars on the caption line, right.
	var by := size.y - 12.0
	var bx := size.x - MARGIN.x - sx - 70.0
	draw_line(Vector2(bx, by), Vector2(bx + sx, by), ink, 1.5)
	draw_string(font, Vector2(bx + sx * 0.5 - 6.0, by - 3.0), "1 m", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	draw_line(Vector2(bx + sx + 20.0, by), Vector2(bx + sx + 20.0, by - 0.05 * sz), ink, 1.5)
	draw_string(font, Vector2(bx + sx + 24.0, by), "50 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	draw_string(font, Vector2(MARGIN.x, size.y - 22.0), "SECTION A-B", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	draw_string(font, Vector2(MARGIN.x + 1.0, size.y - 22.0), "SECTION A-B", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	draw_string(font, Vector2(MARGIN.x, size.y - 9.0), "Across the road at %.2f m, year %.1f.  %s.  Depth drawn %.0fx." % [
		cut_y, sim.time, b.title, exag], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)


## Hatch lines at 45 degrees (`slope` 1 or -1), `gap` px apart, clipped to the strip [x0, x1] x [ya, yb].
func _hatch(out: PackedVector2Array, x0: float, x1: float, ya: float, yb: float, gap: float, slope: float) -> void:
	if yb - ya < 0.5:
		return
	# Lines y = slope * x + c, one every `gap` px of c; the strip is narrow, so each is one short segment.
	var k0 := int(floor(minf(ya - slope * x0, ya - slope * x1) / gap))
	var k1 := int(ceil(maxf(yb - slope * x0, yb - slope * x1) / gap))
	for k in range(k0, k1 + 1):
		var c := k * gap
		var p0 := Vector2(x0, slope * x0 + c)
		var p1 := Vector2(x1, slope * x1 + c)
		if (p0.y < ya and p1.y < ya) or (p0.y > yb and p1.y > yb):
			continue
		p0.y = clampf(p0.y, ya, yb)
		p1.y = clampf(p1.y, ya, yb)
		out.append(p0)
		out.append(p1)


func _material(bands: Array, z: float) -> int:
	for band in bands:
		if z <= band[1] and z >= band[2]:
			return band[0]
	return M.AIR


func _swatch(r: Rect2, m: int) -> void:
	draw_rect(r, paper)
	match m:
		M.PATCH:
			draw_rect(r, ink)
		M.ASPHALT:
			for k in 14:
				var d := r.position + Vector2(_hash(k, 3) * r.size.x, _hash(3, k) * r.size.y)
				draw_rect(Rect2(d, Vector2(1, 1)), ink)
		M.BASE:
			draw_arc(r.position + Vector2(4, 4), 1.8, 0.0, TAU, 8, ink, 1.0)
			draw_arc(r.position + Vector2(11, 6), 1.8, 0.0, TAU, 8, ink, 1.0)
		_:
			var h := PackedVector2Array()
			var gap := 3.5 if m == M.FILL else (5.0 if m == M.SHOULDER else 7.0)
			for x in range(int(r.position.x), int(r.end.x)):
				if m == M.FILL or m == M.SHOULDER:
					_hatch(h, x, x + 1.0, r.position.y, r.end.y, gap, 1.0)
				if m == M.FILL or m == M.SUBGRADE:
					_hatch(h, x, x + 1.0, r.position.y, r.end.y, gap, -1.0)
			if h.size() > 0:
				draw_multiline(h, ink, 1.0)
	draw_rect(r, ink, false, 0.5)


func _arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, ink, 1.0)
	var d := (to - from).normalized()
	var s := d.orthogonal()
	draw_colored_polygon(PackedVector2Array([to, to - d * 5.0 + s * 2.0, to - d * 5.0 - s * 2.0]), ink)


## 0..1, fixed for a grid point (the stipple and circles don't flicker or crawl).
func _hash(a: int, b: int) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


## m: the road surface beside a crack (the profile either side of it, not the dip it cuts).
func _surface_at(x: float, w: float) -> float:
	var i0 := clampi(int((x - w * 0.5) / res) - 1, 0, profile.size() - 1)
	var i1 := clampi(int((x + w * 0.5) / res) + 2, 0, profile.size() - 1)
	return maxf(profile[i0], profile[i1])


func _painted(p: Vector2) -> bool:
	if not sim.paved(p):
		return false
	var half := sim.paint_width * 0.5
	for k in range(0, sim.paint_lines.size() - 1, 2):
		var a := sim.paint_lines[k]
		var ab := sim.paint_lines[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-10), 0.0, 1.0)
		if p.distance_to(a + ab * t) <= half:
			return sim.paint_left(p) > 0.1
	return false
