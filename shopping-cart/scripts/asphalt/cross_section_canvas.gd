class_name CrossSectionCanvas
extends Control
## The asphalt lab's cross-section: a vertical slice across the road at `cut_y`, drawn to scale from the sim's
## build-up (AsphaltSim.pavement()) and its real height map (AsphaltSim.bake_height). It shows the layers
## (asphalt, aggregate base, subgrade), the surface profile (ruts, potholes, shoulders, patches), every crack the
## cut crosses at its real width, full-depth patches, cold patch in the hole it filled, sealant, sealcoat and paint.
## Crack depth is still a placeholder (AsphaltSim.crack_depth) and is drawn dashed. Depth is exaggerated by the
## largest of EXAGGERATIONS that fits the box. The cut is marked on `plan_view` (the colour map) as A-A.

@export var sim: AsphaltSim
@export var plan_view: TextureRect             ## the plan (colour map) the cut line is drawn on
@export var cut_y := 5.0                        ## m along the road where the section is taken
@export var res := 0.02                         ## m between profile samples (and height-map pixels)
@export var subgrade_shown := 0.06              ## m of subgrade drawn under the build-up
@export var headroom := 0.02                    ## m drawn above the design level (patches, paint, sealant)

@export_group("Colours")
@export var background := Color(0.11, 0.12, 0.14)
@export var asphalt_color := Color(0.30, 0.30, 0.31)
@export var base_color := Color(0.55, 0.49, 0.40)
@export var subgrade_color := Color(0.42, 0.33, 0.24)
@export var patch_color := Color(0.13, 0.13, 0.14)
@export var fill_color := Color(0.42, 0.37, 0.31)
@export var crack_color := Color(0.0, 0.0, 0.0)
@export var placeholder_color := Color(0.95, 0.45, 0.3)
@export var sealant_color := Color(0.04, 0.04, 0.05)
@export var paint_color := Color(0.95, 0.95, 0.9)
@export var line_color := Color(0.85, 0.87, 0.9)
@export var text_color := Color(0.85, 0.87, 0.9)
@export var dim_text := Color(0.6, 0.63, 0.68)

const MARGIN := Vector2(16.0, 76.0)             ## px: left/right and top margins
const GUTTER := 170.0                           ## px on the right for the layer labels
const LEGEND_H := 34.0                          ## px kept at the bottom for the scale and legend
const EXAGGERATIONS := [20.0, 10.0, 5.0, 2.0, 1.0]   ## depth scales tried, largest first (section drawings use 10-20x)

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


## The cracks the cut crosses: { x, width, depth, sealed, kind }, in metres.
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
				sealed = sealed, kind = c.kind })
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


func _draw_cut_on_plan() -> void:
	if not visible or sim == null:
		return
	var r := plan_rect()
	var y := r.position.y + cut_y / sim.size.y * r.size.y
	plan_view.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), placeholder_color, 2.0)
	var font := ThemeDB.fallback_font
	for x in [r.position.x + 4.0, r.end.x - 16.0]:
		plan_view.draw_string(font, Vector2(x, y - 5.0), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, placeholder_color)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
	if sim == null or profile.is_empty():
		return
	var b := sim.pavement()
	var h_a := b.asphalt_thickness()
	var h_total := 0.0
	for l in b.layers:
		h_total += l.thickness
	var area := Rect2(MARGIN, size - MARGIN - Vector2(MARGIN.x + GUTTER, LEGEND_H))
	var sx := area.size.x / sim.size.x                    # px per m across
	# Depth: the largest round exaggeration that fits.
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
	var col_w := maxf(res * sx, 1.0) + 0.5

	# Layers, column by column: subgrade, base, asphalt, patches and cold patch, cut down to the surface.
	var patch_spans := { }
	var surface := PackedVector2Array()
	for i in profile.size():
		var x := i * res
		var p := Vector2(x, cut_y)
		var s := profile[i]
		var x0: float = X.call(x) - col_w * 0.5
		surface.append(Vector2(X.call(x), Y.call(s)))
		draw_rect(Rect2(x0, Y.call(-h_total), col_w, Y.call(-h_total - subgrade_shown) - Y.call(-h_total)), subgrade_color)
		var paved := sim.paved(p) if x > 0.0 and x < sim.size.x else false
		var base_top := minf(s, -h_a) if paved else s
		draw_rect(Rect2(x0, Y.call(base_top), col_w, Y.call(-h_total) - Y.call(base_top)), base_color)
		if paved and s > -h_a:
			draw_rect(Rect2(x0, Y.call(s), col_w, Y.call(-h_a) - Y.call(s)), asphalt_color)
		for k in sim.patches.size():
			var rect: Rect2 = sim.patches[k].rect
			if rect.has_point(p):
				draw_rect(Rect2(x0, Y.call(s), col_w, Y.call(-h_total) - Y.call(s)), patch_color)
				if not patch_spans.has(k):
					patch_spans[k] = Vector2(x, x)
				patch_spans[k].y = x
		var ci := sim.cell_index(p)
		if paved and sim.fill_born[ci] >= 0.0:
			draw_rect(Rect2(x0, Y.call(s), col_w, Y.call(-sim.fill_depth[ci]) - Y.call(s)), fill_color)
		# Spot sealcoat (under a millimetre) and paint, on top.
		for sp in sim.seal_spots:
			if Geometry2D.is_point_in_polygon(p, sp.poly) and sim.sealcoat_left(p, sp.born) > 0.1:
				draw_rect(Rect2(x0, Y.call(s) - 2.0, col_w, 2.0), sealant_color)
		if paved and _painted(p):
			draw_rect(Rect2(x0, Y.call(s) - 2.5, col_w, 2.5), paint_color)

	# Layer interfaces and the surface.
	draw_line(Vector2(area.position.x, Y.call(-h_total)), Vector2(area.end.x, Y.call(-h_total)), Color(line_color, 0.35), 1.0)
	draw_polyline(surface, line_color, 1.5)
	for k in patch_spans:
		var span: Vector2 = patch_spans[k]
		var r := Rect2(X.call(span.x) - col_w * 0.5, Y.call(0.0), (span.y - span.x) * sx + col_w, Y.call(-h_total) - Y.call(0.0))
		draw_rect(r, line_color, false, 1.0)
		draw_string(font, Vector2(r.position.x, area.position.y + 10.0), "patch yr %.1f" % sim.patches[k].born,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)

	# Cracks crossing the cut: real width (at least a pixel), depth a placeholder (hatched outline).
	for cr in crossings():
		var cx: float = X.call(cr.x)
		var top := _surface_at(cr.x, cr.width)
		var half := maxf(cr.width * 0.5 * sx, 0.75)
		var bottom: float = Y.call(top - cr.depth)
		if cr.sealed:
			draw_rect(Rect2(cx - half, Y.call(top), half * 2.0, bottom - Y.call(top)), sealant_color)
			var band := 0.03 * sx
			draw_rect(Rect2(cx - band, Y.call(top + AsphaltSim.SEAL_PROUD), band * 2.0, Y.call(top) - Y.call(top + AsphaltSim.SEAL_PROUD) + 1.0), sealant_color)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(cx - half, Y.call(top)), Vector2(cx + half, Y.call(top)),
				Vector2(cx, bottom)]), crack_color)
		draw_dashed_line(Vector2(cx, Y.call(top)), Vector2(cx, bottom), placeholder_color, 1.0, 3.0)

	# Metre ticks and wheel paths along the top.
	for m in int(sim.size.x) + 1:
		draw_line(Vector2(X.call(m), area.position.y - 16.0), Vector2(X.call(m), area.position.y - 11.0), dim_text, 1.0)
		draw_string(font, Vector2(X.call(m) - 3.0, area.position.y - 19.0), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim_text)
	for wp in sim.wheel_paths:
		draw_string(font, Vector2(X.call(wp) - 9.0, area.position.y - 2.0), "WP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim_text)
	# Layer labels in the gutter, with leaders.
	var gx := area.end.x + 12.0
	var z := 0.0
	for l in b.layers:
		var mid: float = (Y.call(z) + Y.call(z - l.thickness)) * 0.5
		draw_line(Vector2(area.end.x, mid), Vector2(gx - 2.0, mid), Color(line_color, 0.4), 1.0)
		draw_string(font, Vector2(gx, mid - 2.0), l.title, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 14.0, 12, text_color)
		var note := "%.0f mm (%.1f in)" % [l.thickness * 1000.0, l.thickness / 0.0254]
		if z == 0.0 and sim.surface_born > 0.0:
			note += ", relaid yr %.1f" % sim.surface_born
		draw_string(font, Vector2(gx, mid + 12.0), note, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 14.0, 11, dim_text)
		z -= l.thickness
	var smid: float = Y.call(-h_total - subgrade_shown * 0.5)
	draw_line(Vector2(area.end.x, smid), Vector2(gx - 2.0, smid), Color(line_color, 0.4), 1.0)
	draw_string(font, Vector2(gx, smid - 2.0), "Subgrade", HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 14.0, 12, text_color)
	draw_string(font, Vector2(gx, smid + 12.0), "CBR %.0f (Mr ~%.0f MPa)" % [b.subgrade_cbr, b.subgrade_mr() / 1e6],
		HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 14.0, 11, dim_text)
	draw_string(font, Vector2(MARGIN.x, 22.0), "Section A-A across the road at %.2f m  |  year %.1f" % [cut_y, sim.time],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text_color)
	var sub := "%s  |  depth drawn %.0fx  |  " % [b.title, exag]
	draw_string(font, Vector2(MARGIN.x, 38.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim_text)
	var px := MARGIN.x + font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_dashed_line(Vector2(px, 34.0), Vector2(px + 14.0, 34.0), placeholder_color, 1.0, 3.0)
	draw_string(font, Vector2(px + 18.0, 38.0), "crack depth: placeholder (4 x width); widths are real",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, placeholder_color)

	# Scale bars and legend.
	var ly := size.y - LEGEND_H + 18.0
	draw_line(Vector2(MARGIN.x, ly), Vector2(MARGIN.x + sx, ly), line_color, 2.0)
	draw_string(font, Vector2(MARGIN.x, ly + 14.0), "1 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim_text)
	draw_line(Vector2(MARGIN.x + sx + 20.0, ly - 0.05 * sz + 4.0), Vector2(MARGIN.x + sx + 20.0, ly + 4.0), line_color, 2.0)
	draw_string(font, Vector2(MARGIN.x + sx + 26.0, ly + 4.0), "50 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim_text)
	var lx := MARGIN.x + sx + 90.0
	var row := ly
	for item in [[asphalt_color, "asphalt"], [base_color, "aggregate base"], [subgrade_color, "subgrade"],
			[patch_color, "heavy patch"], [fill_color, "cold patch"], [sealant_color, "sealant"], [paint_color, "paint"]]:
		var tw := font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if lx + 16.0 + tw > size.x - MARGIN.x:
			lx = MARGIN.x + sx + 90.0
			row += 18.0
		draw_rect(Rect2(lx, row - 9.0, 12.0, 12.0), item[0])
		draw_rect(Rect2(lx, row - 9.0, 12.0, 12.0), Color(line_color, 0.5), false, 1.0)
		draw_string(font, Vector2(lx + 16.0, row + 1.0), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)
		lx += 26.0 + tw



## m: the road surface beside a crack (the profile either side of it, not the dip it cuts).
func _surface_at(x: float, w: float) -> float:
	var i0 := clampi(int((x - w * 0.5) / res) - 1, 0, profile.size() - 1)
	var i1 := clampi(int((x + w * 0.5) / res) + 2, 0, profile.size() - 1)
	return maxf(profile[i0], profile[i1])


func _painted(p: Vector2) -> bool:
	var half := sim.paint_width * 0.5
	for k in range(0, sim.paint_lines.size() - 1, 2):
		var a := sim.paint_lines[k]
		var ab := sim.paint_lines[k + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-10), 0.0, 1.0)
		if p.distance_to(a + ab * t) <= half:
			return sim.paint_left(p) > 0.1
	return false
