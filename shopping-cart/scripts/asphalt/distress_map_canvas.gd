class_name DistressMapCanvas
extends Control
## The asphalt lab's LTPP distress map: the road surveyed (AsphaltSurvey) and drawn as an LTPP map sheet for asphalt
## surfaces (Distress Identification Manual, FHWA-HRT-13-092, appendix A): one strip per lane as in fig. 138, the
## distance along the lane left to right (direction of travel) and the offset from the pavement edge bottom to top,
## a metre grid with feet on the top and right axes, both wheel paths marked, every distress drawn to scale with its
## fig. 137 symbol and labelled with its circled code (type, a/b, severity L/M/H, "s" when well sealed). Beside it,
## the data sheet 1 and 2 quantities for each lane.

@export var sim: AsphaltSim
@export var res := 0.02                         ## m: height-map resolution for the rut measurements
@export var paper := Color(1.0, 1.0, 1.0)
@export var ink := Color(0.0, 0.0, 0.0)

const FONT := 9
const TABLE_W := 262.0                          ## px for the data sheet table on the right
const LEGEND_ROWS := 7                          ## rows the symbol legend takes at the foot of the table column
const LABEL_MIN := 0.6                          ## m: shorter cracks are drawn and counted but not labelled
const AXIS := Vector2(54.0, 18.0)               ## px left of / above each strip for its axes

var survey: AsphaltSurvey
var _labels: Array[Rect2] = []                  ## label boxes placed so far (labels dodge each other)
var _bounds := Rect2()                          ## the strip being drawn: labels stay inside it


## Survey the road again (after it changes) and redraw.
func refresh() -> void:
	if sim == null:
		return
	survey = AsphaltSurvey.take(sim, sim.bake_height(res), res)
	queue_redraw()


## A road point (m) in lane `lane`'s map coordinates: x = distance along the lane in its direction of travel,
## y = offset from the pavement edge towards the centreline.
func to_map(lane: int, p: Vector2) -> Vector2:
	if lane == 1:
		return Vector2(p.y, sim.size.x - sim.shoulder - p.x)
	return Vector2(sim.size.y - p.y, p.x - sim.shoulder)


func lane_width() -> float:
	return sim.lane_joint_x - sim.shoulder


func _draw() -> void:
	var panel := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	draw_rect(panel, paper)
	draw_rect(panel, ink, false, 1.0)
	if sim == null or survey == null:
		return
	_labels.clear()
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(12.0, 18.0), "DISTRESS MAP  -  PAVEMENTS WITH ASPHALT CONCRETE SURFACES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	draw_string(font, Vector2(12.6, 18.0), "DISTRESS MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	var b := sim.pavement()
	var build := ""
	for l in b.layers:
		build += "%.0f mm %s / " % [l.thickness * 1000.0, "asphalt" if l.kind == PavementLayer.Kind.ASPHALT else "base"]
	draw_string(font, Vector2(12.0, 31.0), "LTPP DIM appendix A (figs. 137, 138).  Lab section, seed %d, %.0f m long.  Survey at year %.1f.  %ssubgrade CBR %.0f." % [
		sim.seed, sim.size.y, survey.year, build, b.subgrade_cbr], HORIZONTAL_ALIGNMENT_LEFT, size.x - TABLE_W - 24.0, FONT, ink)
	draw_string(font, Vector2(12.0, 43.0), "Units: metres on the bottom and left axes (LTPP measures in SI); feet on the top and right, as LTPP sheets print them. Grid 0.5 m.",
		HORIZONTAL_ALIGNMENT_LEFT, size.x - TABLE_W - 24.0, FONT - 1, ink)
	var map_w := size.x - TABLE_W - 24.0
	var strip_h := (size.y - 56.0 - 2.0 * (AXIS.y + 44.0)) * 0.5
	var scale := minf((map_w - AXIS.x - 30.0) / sim.size.y, strip_h / lane_width())
	var y0 := 56.0
	for lane in [1, 0]:
		var origin := Vector2(12.0 + AXIS.x, y0 + AXIS.y + lane_width() * scale)
		_strip(lane, origin, scale)
		y0 += AXIS.y + lane_width() * scale + 44.0
	_sheet(Rect2(size.x - TABLE_W - 8.0, 40.0, TABLE_W, size.y - 48.0))


## One lane's map: frame, grid, axes, wheel paths, then the distresses.
func _strip(lane: int, origin: Vector2, s: float) -> void:
	var font := ThemeDB.fallback_font
	var L := sim.size.y
	var W := lane_width()
	var P := func(m: Vector2) -> Vector2: return origin + Vector2(m.x * s, -m.y * s)
	_bounds = Rect2(origin + Vector2(0.0, -W * s), Vector2(L * s, W * s))
	# Grid: dotted every 0.5 m, the frame solid.
	var g := 0.5
	while g < L - 0.01:
		draw_dashed_line(P.call(Vector2(g, 0.0)), P.call(Vector2(g, W)), Color(ink, 0.35), 0.5, 1.5)
		g += 0.5
	g = 0.5
	while g < W - 0.01:
		draw_dashed_line(P.call(Vector2(0.0, g)), P.call(Vector2(L, g)), Color(ink, 0.35), 0.5, 1.5)
		g += 0.5
	draw_rect(Rect2(P.call(Vector2(0.0, W)), Vector2(L * s, W * s)), ink, false, 1.0)
	# Axes: metres bottom and left, feet top and right.
	for m in int(L) + 1:
		draw_string(font, P.call(Vector2(m, 0.0)) + Vector2(-3.0, 11.0), "%d%s" % [m, " m" if m == 0 or m == int(L) else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	for m in int(W) + 1:
		draw_string(font, P.call(Vector2(0.0, m)) + Vector2(-20.0, 3.0), "%d m" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	var ft := 0
	while ft * 0.3048 <= L + 0.01:
		draw_line(P.call(Vector2(ft * 0.3048, W)), P.call(Vector2(ft * 0.3048, W)) + Vector2(0.0, -3.0), ink, 0.5)
		if ft % 10 == 0:
			draw_string(font, P.call(Vector2(ft * 0.3048, W)) + Vector2(-4.0, -5.0), "%d'" % ft, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
		ft += 5
	ft = 0
	while ft * 0.3048 <= W + 0.01:
		draw_string(font, P.call(Vector2(L, ft * 0.3048)) + Vector2(4.0, 3.0), "%d'" % ft, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
		ft += 5
	draw_string(font, P.call(Vector2(L * 0.5, 0.0)) + Vector2(-60.0, 22.0), "distance along the lane (m)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	draw_string(font, P.call(Vector2(0.0, W)) + Vector2(-50.0, -5.0), "offset (m)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	draw_string(font, P.call(Vector2(L * 0.5, W)) + Vector2(-34.0, -5.0), "(ft)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	draw_string(font, P.call(Vector2(L, W)) + Vector2(4.0, -6.0), "(ft)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	# Wheel paths: 0.76 m bands at the sim's wheel paths (fig. 136: drawn where the traffic actually runs).
	for wp in sim.wheel_paths:
		if survey.lane_of(wp) != lane:
			continue
		var off := to_map(lane, Vector2(wp, 0.0)).y
		for e in [-AsphaltSurvey.WHEEL_PATH_HALF, AsphaltSurvey.WHEEL_PATH_HALF]:
			draw_line(P.call(Vector2(0.0, off + e)), P.call(Vector2(L, off + e)), ink, 1.0)
		var top: Vector2 = P.call(Vector2(0.0, off + AsphaltSurvey.WHEEL_PATH_HALF))
		var bot: Vector2 = P.call(Vector2(0.0, off - AsphaltSurvey.WHEEL_PATH_HALF))
		var bx := origin.x - 26.0
		draw_line(Vector2(bx + 4.0, top.y), Vector2(bx, top.y + 3.0), ink, 0.75)
		draw_line(Vector2(bx, top.y + 3.0), Vector2(bx, bot.y - 3.0), ink, 0.75)
		draw_line(Vector2(bx, bot.y - 3.0), Vector2(bx + 4.0, bot.y), ink, 0.75)
		draw_string(font, Vector2(bx - 26.0, (top.y + bot.y) * 0.5 - 2.0), "Wheel", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
		draw_string(font, Vector2(bx - 24.0, (top.y + bot.y) * 0.5 + 8.0), "Path", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)

	var M := func(p: Vector2) -> Vector2: return P.call(to_map(lane, p))
	# Patches (7) solid black; their labels come last, white on black.
	var patch_labels: Array = []
	for a in survey.areas:
		if a.lane != lane or a.type != 7:
			continue
		if a.get("heavy", false):
			var r: Rect2 = a.rect
			var poly := PackedVector2Array([M.call(r.position), M.call(Vector2(r.end.x, r.position.y)), M.call(r.end),
				M.call(Vector2(r.position.x, r.end.y))])
			draw_colored_polygon(poly, ink)
		else:
			for i in a.cells:
				_cell(lane, i, M, ink, true)
		if a.counted:
			patch_labels.append([M.call((a.rect as Rect2).get_center()), a.code])
	# Fatigue (1): as fig. 138, a rounded outline round the area with X's inside it.
	for a in survey.areas:
		if a.lane != lane or a.type != 1:
			continue
		var r: Rect2 = a.rect
		var m0 := to_map(lane, r.position)
		var m1 := to_map(lane, r.end)
		var box := Rect2(m0, Vector2.ZERO).expand(m1)
		box = box.intersection(Rect2(0.0, 0.0, sim.size.y, lane_width()))
		var rr := Rect2(P.call(Vector2(box.position.x, box.end.y)), box.size * s)
		var rad := minf(rr.size.y * 0.5, 10.0)
		var outline := PackedVector2Array()
		for k in 4:
			var corner: Vector2 = [rr.position + Vector2(rr.size.x - rad, rad), rr.position + Vector2(rr.size.x - rad, rr.size.y - rad),
				rr.position + Vector2(rad, rr.size.y - rad), rr.position + Vector2(rad, rad)][k]
			for t in 7:
				outline.append(corner + Vector2.from_angle(-PI * 0.5 + PI * 0.5 * (k + t / 6.0)) * rad)
		outline.append(outline[0])
		draw_polyline(outline, ink, 1.0)
		# X's on a 0.5 m by 0.3 m grid inside the outline.
		var rows := maxi(1, int(box.size.y / 0.3))
		var x := box.position.x + 0.25
		var stagger := 0
		while x < box.end.x - 0.1:
			for k in rows:
				var y := box.position.y + box.size.y * (k + 0.5) / rows
				var q: Vector2 = P.call(Vector2(x + (0.12 if (k + stagger) % 2 == 1 else 0.0), y))
				draw_line(q + Vector2(-2.5, -2.5), q + Vector2(2.5, 2.5), ink, 1.0)
				draw_line(q + Vector2(-2.5, 2.5), q + Vector2(2.5, -2.5), ink, 1.0)
			x += 0.5
			stagger += 1
		_label(Vector2(rr.end.x - 14.0, rr.get_center().y), a.code, false)
	# Block (2): the block cracks themselves, with the area's label.
	for a in survey.areas:
		if a.lane == lane and a.type == 2:
			_label(M.call((a.rect as Rect2).get_center()), a.code, false)
	# Crack lines: 2 (block), 4, 6, 7 (patch seams), 16 (slippage); "s" along sealed ones.
	# Every crack is drawn where it lies inside this lane (clipped to the frame); only the lane that owns it labels it.
	var frame := PackedVector2Array([Vector2(0.0, 0.0), Vector2(L, 0.0), Vector2(L, W), Vector2(0.0, W)])
	for l in survey.lines:
		var mp := PackedVector2Array()
		for q in l.pts:
			mp.append(to_map(lane, q))
		for part in Geometry2D.intersect_polyline_with_polygon(mp, frame):
			var screen := PackedVector2Array()
			for q in part:
				screen.append(P.call(q))
			if screen.size() >= 2:
				draw_polyline(screen, ink, 1.25 if l.type == 4 or l.type == 6 else 1.0)
		if l.lane != lane:
			continue
		var pts := PackedVector2Array()
		for q in l.pts:
			var mq := to_map(lane, q)
			if mq.x >= 0.0 and mq.x <= L and mq.y >= 0.0 and mq.y <= W:
				pts.append(P.call(mq))
		if pts.size() < 2:
			continue
		if l.sealed:
			var acc := 0.0
			var flip := 1.0
			for k in pts.size() - 1:
				acc += pts[k].distance_to(pts[k + 1])
				if acc > 0.5 * s:
					acc = 0.0
					var n := (pts[k + 1] - pts[k]).normalized().orthogonal() * 6.0 * flip
					draw_string(ThemeDB.fallback_font, pts[k] + n + Vector2(-2.0, 3.0), "s", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
					flip = -flip
		if l.code != "" and l.length >= LABEL_MIN:
			_label(pts[pts.size() / 2] + Vector2(8.0, -8.0), l.code + ("s" if l.sealed else ""), false)
	# Edge cracking (3): a hatched strip along the pavement edge over the rows affected.
	for e in survey.edges:
		if e.lane != lane:
			continue
		for run: Vector2i in e.rows:
			var ya := run.x * AsphaltSim.CELL
			var yb := (run.y + 1) * AsphaltSim.CELL
			var xa := to_map(lane, Vector2(0.0, ya)).x
			var xb := to_map(lane, Vector2(0.0, yb)).x
			var r := Rect2(P.call(Vector2(minf(xa, xb), 0.25)), Vector2(absf(xb - xa) * s, 0.25 * s))
			draw_rect(r, paper)
			var h := PackedVector2Array()
			var x := r.position.x - r.size.y
			while x < r.end.x:
				var a := Vector2(maxf(x, r.position.x), r.end.y - maxf(0.0, r.position.x - x))
				var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + maxf(0.0, x + r.size.y - r.end.x))
				h.append(a)
				h.append(b)
				x += 4.0
			draw_multiline(h, ink, 1.0)
			draw_rect(r, ink, false, 1.0)
		var first: Vector2i = e.rows[0]
		_label(P.call(Vector2(to_map(lane, Vector2(0.0, (first.x + 0.5) * AsphaltSim.CELL)).x, 0.5)), e.code, false)
	# Potholes (8): an ellipse with a cross, to the hole's plan size.
	var small := 0
	for a in survey.areas:
		if a.lane != lane or a.type != 8:
			continue
		var r: Rect2 = a.rect
		var c: Vector2 = M.call(r.get_center())
		var half: Vector2 = (M.call(r.end) - M.call(r.position)).abs() * 0.5
		half = Vector2(maxf(half.x, 3.0), maxf(half.y, 2.0))
		var ring := PackedVector2Array()
		for k in 25:
			ring.append(c + Vector2(cos(TAU * k / 24.0) * half.x, sin(TAU * k / 24.0) * half.y))
		draw_colored_polygon(ring, paper)
		draw_polyline(ring, ink, 1.0)
		draw_line(c - Vector2(half.x, 0.0), c + Vector2(half.x, 0.0), ink, 0.75)
		draw_line(c - Vector2(0.0, half.y), c + Vector2(0.0, half.y), ink, 0.75)
		if a.counted:
			_label(c + Vector2(half.x + 8.0, -6.0), a.code, false)
		else:
			small += 1
	# 16 Other: spot sealcoat outlined dotted.
	for a in survey.areas:
		if a.lane != lane or a.type != 16:
			continue
		var pts := PackedVector2Array()
		for q in a.poly:
			pts.append(M.call(q))
		pts.append(pts[0])
		for k in range(0, pts.size() - 1, 2):
			draw_line(pts[k], pts[k + 1], ink, 1.0)
		var c := Vector2.ZERO
		for q in pts:
			c += q
		_label(c / pts.size(), "16", false)
	for pl in patch_labels:
		_label(pl[0], pl[1], true)
	# Under the strip: the lane, its direction of travel and the comments.
	var font2 := ThemeDB.fallback_font
	var cy := origin.y + 34.0
	var note := "Lane %d, traffic left to right.  " % (lane + 1)
	if small > 0:
		note += "%d hole%s under the 150 mm minimum drawn, not counted.  " % [small, "" if small == 1 else "s"]
	for n in survey.notes:
		if n.begins_with("Lane %d" % (lane + 1)):
			note += n.substr(8) + "  "
	draw_string(font2, Vector2(origin.x - 40.0, cy), "Comments:", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	draw_string(font2, Vector2(origin.x + 10.0, cy), note, HORIZONTAL_ALIGNMENT_LEFT, sim.size.y * s, FONT - 1, ink)
	draw_line(Vector2(origin.x + 8.0, cy + 2.0), Vector2(origin.x + sim.size.y * s, cy + 2.0), ink, 0.5)


## A 10 cm cell of the sim's grid, filled, in map coordinates.
func _cell(lane: int, i: int, M: Callable, color: Color, filled: bool) -> void:
	var c := sim.cell_center(i)
	var h := AsphaltSim.CELL * 0.5
	var poly := PackedVector2Array([M.call(c + Vector2(-h, -h)), M.call(c + Vector2(h, -h)), M.call(c + Vector2(h, h)),
		M.call(c + Vector2(-h, h))])
	if filled:
		draw_colored_polygon(poly, color)


## A circled code, as on LTPP maps; white on black for patches. Dodges labels already placed.
func _label(at: Vector2, text: String, inverse: bool) -> void:
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var r := maxf(tw * 0.5 + 3.0, 7.0)
	var box := Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)
	for k in 6:
		var hit := false
		for o in _labels:
			if o.intersects(box):
				hit = true
				break
		if not hit:
			break
		box.position.y += (2.0 * r + 1.0) * (1.0 if k % 2 == 0 else -2.0)
	if _bounds.has_area():
		box.position = box.position.clamp(_bounds.position, _bounds.end - box.size)
	_labels.append(box)
	var c := box.get_center()
	draw_circle(c, r, ink if inverse else paper)
	draw_arc(c, r, 0.0, TAU, 20, paper if inverse else ink, 1.0)
	draw_string(font, c + Vector2(-tw * 0.5, 3.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, paper if inverse else ink)


## The data sheet 1 and 2 quantities for both lanes.
func _sheet(r: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(r, ink, false, 1.0)
	var x0 := r.position.x + 6.0
	var y := r.position.y + 14.0
	draw_string(font, Vector2(x0, y), "DATA SHEETS 1 AND 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
	y += 14.0
	var colx := [r.position.x + 112.0, r.position.x + 186.0]
	for lane in 2:
		draw_string(font, Vector2(colx[lane], y), "Lane %d" % (lane + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	y += 11.0
	for lane in 2:
		draw_string(font, Vector2(colx[lane], y), "L    M    H", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	y += 4.0
	draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), ink, 0.5)
	y += 11.0
	var rows := [["1 Fatigue (m2)", "1", 1], ["2 Block (m2)", "2", 1], ["3 Edge (m)", "3", 1], ["4a Wheel path (m)", "4a", 1],
		["   sealed (m)", "4a_sealed", 1], ["4b Non-wheel path (m)", "4b", 1], ["   sealed (m)", "4b_sealed", 1],
		["6 Transverse (no.)", "6_count", 0], ["   length (m)", "6_m", 1], ["   sealed (m)", "6_sealed", 1],
		["7 Patches (no.)", "7_count", 0], ["   area (m2)", "7_m2", 1], ["8 Potholes (no.)", "8_count", 0],
		["   area (m2)", "8_m2", 2]]
	for row in rows:
		draw_string(font, Vector2(x0, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, 104.0, FONT - 1, ink)
		for lane in 2:
			var v: Array = survey.totals_for(lane)[row[1]]
			for k in 3:
				var txt := ("%." + str(row[2]) + "f") % v[k] if v[k] > 0.0 else "-"
				draw_string(font, Vector2(colx[lane] + k * 22.0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, 24.0, FONT - 1, ink)
		y += 11.5
	draw_line(Vector2(r.position.x, y - 7.0), Vector2(r.end.x, y - 7.0), ink, 0.5)
	y += 4.0
	draw_string(font, Vector2(x0, y), "9 Rutting, 1.2 m straightedge (mm)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	y += 11.0
	for lane in 2:
		var ruts: Array = survey.totals_for(lane).get("rut", [])
		var txt := "Lane %d:" % (lane + 1)
		for rut in ruts:
			txt += "  WP %.1f m mean %.0f, max %.0f" % [rut.x, rut.mean * 1000.0, rut.max * 1000.0]
		draw_string(font, Vector2(x0 + 6.0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14.0, FONT - 2, ink)
		y += 10.0
	y += 4.0
	draw_string(font, Vector2(x0, y), "10-13, 15  not simulated (shoving, bleeding,", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	y += 10.0
	draw_string(font, Vector2(x0, y), "   polished aggregate, raveling, pumping)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	y += 12.0
	draw_string(font, Vector2(x0, y), "16 Other", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
	y += 10.0
	var legend_top := r.end.y - LEGEND_ROWS * 14.0 - 22.0
	for lane in 2:
		for item in survey.totals_for(lane)["16"]:
			if y > legend_top - 4.0:
				break
			draw_string(font, Vector2(x0 + 6.0, y), "Lane %d: %s" % [lane + 1, item], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14.0, FONT - 2, ink)
			y += 9.5
	_legend(Rect2(r.position.x, legend_top, r.size.x, r.end.y - legend_top))


## The symbols used on the map (LTPP fig. 137), each drawn as it appears on the map.
func _legend(r: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_line(r.position, Vector2(r.end.x, r.position.y), ink, 0.5)
	var x0 := r.position.x + 6.0
	var y := r.position.y + 13.0
	draw_string(font, Vector2(x0, y), "MAP SYMBOLS (LTPP fig. 137)", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, ink)
	y += 6.0
	var items := [["1", "1 Fatigue (m2)"], ["2", "2 Block (m2)"], ["3", "3 Edge (m)"], ["4", "4a / 4b Longitudinal (m)"],
		["6", "6 Transverse (no., m)"], ["s", "s Sealed crack"], ["7", "7 Patch (no., m2)"], ["8", "8 Pothole (no., m2)"],
		["16", "16 Other"], ["wp", "Wheel path, 0.76 m"]]
	var col := 0
	for k in items.size():
		var box := Rect2(x0 + col * (r.size.x * 0.5), y + (k / 2) * 14.0, 20.0, 10.0)
		col = 1 - col
		_symbol(box, items[k][0])
		draw_string(font, box.position + Vector2(24.0, 8.5), items[k][1], HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.5 - 30.0, FONT - 2, ink)
	y += (items.size() + 1) / 2 * 14.0 + 4.0
	draw_string(font, Vector2(x0, y), "Circled code: number, a/b, severity L/M/H (4aM).", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0, FONT - 2, ink)
	draw_string(font, Vector2(x0, y + 10.0), "Not drawn (LTPP): 9 rutting, 14 dropoff.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0, FONT - 2, ink)


func _symbol(b: Rect2, kind: String) -> void:
	var c := b.get_center()
	match kind:
		"1":
			draw_rect(b, ink, false, 1.0)
			for dx in [-5.0, 5.0]:
				draw_line(c + Vector2(dx - 2.0, -2.0), c + Vector2(dx + 2.0, 2.0), ink, 1.0)
				draw_line(c + Vector2(dx - 2.0, 2.0), c + Vector2(dx + 2.0, -2.0), ink, 1.0)
		"2":
			draw_rect(b, ink, false, 1.0)
			draw_line(Vector2(c.x, b.position.y), Vector2(c.x, b.end.y), ink, 1.0)
			draw_line(Vector2(b.position.x, c.y), Vector2(b.end.x, c.y), ink, 1.0)
		"3":
			var h := PackedVector2Array()
			for x in range(int(b.position.x), int(b.end.x), 3):
				h.append(Vector2(x, b.end.y))
				h.append(Vector2(minf(x + b.size.y, b.end.x), b.position.y))
			draw_multiline(h, ink, 1.0)
			draw_rect(b, ink, false, 1.0)
		"4":
			draw_polyline(PackedVector2Array([Vector2(c.x - 1.0, b.position.y), Vector2(c.x + 2.0, c.y), Vector2(c.x - 1.0, b.end.y)]), ink, 1.25)
		"6":
			draw_polyline(PackedVector2Array([Vector2(b.position.x, c.y + 1.0), Vector2(c.x, c.y - 2.0), Vector2(b.end.x, c.y + 1.0)]), ink, 1.25)
		"s":
			draw_line(Vector2(b.position.x, c.y + 2.0), Vector2(b.end.x, c.y + 2.0), ink, 1.25)
			draw_string(ThemeDB.fallback_font, Vector2(c.x - 3.0, c.y), "s", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT - 1, ink)
		"7":
			draw_rect(b, ink)
		"8":
			var ring := PackedVector2Array()
			for k in 17:
				ring.append(c + Vector2(cos(TAU * k / 16.0) * 9.0, sin(TAU * k / 16.0) * 4.5))
			draw_polyline(ring, ink, 1.0)
			draw_line(c - Vector2(9.0, 0.0), c + Vector2(9.0, 0.0), ink, 0.75)
			draw_line(c - Vector2(0.0, 4.5), c + Vector2(0.0, 4.5), ink, 0.75)
		"16":
			for x in range(int(b.position.x), int(b.end.x), 4):
				draw_line(Vector2(x, b.position.y), Vector2(x + 2, b.position.y), ink, 1.0)
				draw_line(Vector2(x, b.end.y), Vector2(x + 2, b.end.y), ink, 1.0)
		"wp":
			draw_line(Vector2(b.position.x, b.position.y + 1.0), Vector2(b.end.x, b.position.y + 1.0), ink, 1.0)
			draw_line(Vector2(b.position.x, b.end.y - 1.0), Vector2(b.end.x, b.end.y - 1.0), ink, 1.0)
