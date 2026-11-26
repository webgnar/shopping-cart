class_name AsphaltSurvey
extends RefCounted
## An LTPP manual distress survey of an AsphaltSim road, as the Distress Identification Manual (FHWA-HRT-13-092)
## defines it for asphalt surfaces: every distress classified by type and severity, with the geometry the map
## draws (appendix A, figs. 137 and 138) and the quantities data sheets 1 and 2 total. Each lane is its own LTPP
## section (edge to centreline, fig. 134): lane 0 left of the paving joint, lane 1 right of it.
##
## Rules used (DIM page in brackets):
##   - cracks under 0.3 m are not recorded (6); severity by mean width: L <= 6 mm, M 6-19 mm, H > 19 mm; a sealed
##     crack with its width hidden is L (6, 10); "predominantly parallel" to the road is longitudinal (4a in a wheel
##     path, 4b elsewhere), "predominantly perpendicular" transverse (10). A transverse crack is rated at the
##     highest severity present over at least 10 % of its length, and its length inside fatigue areas is not
##     counted (10). Wheel-path cracks with random cracking round them (inside a fatigue area) are fatigue (8).
##   - fatigue (1): an area; L few connecting cracks, M a complete pattern, H spalled (4). Here: cells past
##     AsphaltSim.FATIGUE_CELLS with cracks in them; M once the crack density is that of a complete pattern of
##     crocodile cells, H once the cracks are wide enough to spall (SPALL_WIDTH) or the area is breaking out.
##     Pothole and patch areas are taken out of it (16).
##   - block (2): the area the block cracks divide, less fatigue; severity by mean width (5). The manual wants an
##     occurrence at least 15 m long; a 10 m section can't have one, so `notes` says so.
##   - edge (3): unpaved shoulders only; metres of edge affected; L no breakup, M breakup over up to 10 % of the
##     affected length, H more (6).
##   - patch (7): >= 0.1 m2; severity from the worst distress in it or on its boundary, a patch in a patch is H (14).
##     Heavy patches and cold patches both count.
##   - pothole (8): a 150 mm circle fits in it, >= 0.02 m2; severity by depth: L < 25 mm, M 25-50 mm, H > 50 mm.
##     Smaller holes are drawn but not counted (16).
##   - rutting (9): not mapped; the largest gap under a 1.2 m straightedge in each wheel path (22).
##   - 16 Other: sealant without aggregate (the spot sealcoat, 14) and slippage cracks (not an LTPP distress).
## Not simulated, so never reported: shoving (10), bleeding (11), polished aggregate (12), raveling (13),
## water bleeding and pumping (15).

const MIN_CRACK := 0.3          ## m: shorter cracks are not recorded
const WHEEL_PATH_HALF := 0.38   ## m: wheel paths are 0.76 m wide (fig. 136)
const EDGE_ZONE := 0.6          ## m from the pavement edge that edge cracking covers
const MIN_PATCH := 0.1          ## m2
const MIN_POTHOLE := 0.15       ## m: smallest plan dimension
const MIN_POTHOLE_AREA := 0.02  ## m2
const MIN_AREA := 0.05          ## m2: a fatigue area must have a quantifiable area; smaller specks are dropped
const FATIGUE_MERGE := 0.3     ## m: fatigue patches closer than this are one area
const SPALL_WIDTH := 0.005      ## m: cracks this wide spall (where AsphaltCanvas and bake_height start spalling)
const COMPLETE_PATTERN := 0.08  ## m of crack per 10 cm cell: a complete pattern of crocodile cells
const STRAIGHTEDGE := 1.2       ## m

var sim: AsphaltSim
var year := 0.0
## Cracks drawn as lines: { code, type, sub, severity, sealed, pts: PackedVector2Array, length, lane, counted }
var lines: Array[Dictionary] = []
## Areas: { code, type, severity, lane, area, counted, cells: PackedInt32Array, rect: Rect2, poly, depth }
var areas: Array[Dictionary] = []
## Edge cracking strips: { side, lane, rows: Array[Vector2i] (first, last 10 cm row of each run), length, severity }
var edges: Array[Dictionary] = []
## Per lane: the data sheet quantities (see totals_for()).
var sheets: Array[Dictionary] = [{ }, { }]
var notes: PackedStringArray = []


## Survey the road as it is now. `heights` (bake_height at `res`) is optional: with it, rutting is measured too.
static func take(s: AsphaltSim, heights := PackedFloat32Array(), res := 0.02) -> AsphaltSurvey:
	var v := AsphaltSurvey.new()
	v.sim = s
	v.year = s.time
	v._run(heights, res)
	return v


static func severity_of_width(w: float) -> String:
	return "L" if w <= 0.006 else ("M" if w <= 0.019 else "H")


## Rut depth under a straightedge across the wheel path at `wp` on a surface profile (m, one sample per res): the
## profile is smoothed over 14 cm (cracks are not ruts), the straightedge rests on the highest point each side.
## Returns { x, depth, a: Vector2(x, z), b: Vector2(x, z) }.
static func straightedge_rut(profile: PackedFloat32Array, res: float, wp: float) -> Dictionary:
	var n := profile.size()
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	for i in n:
		var win: Array[float] = []
		for j in range(maxi(0, i - 3), mini(n, i + 4)):
			win.append(profile[j])
		win.sort()
		smooth[i] = win[win.size() / 2]
	var half := int(STRAIGHTEDGE * 0.5 / res)
	var c := clampi(int(round(wp / res)), 0, n - 1)
	var i0 := maxi(0, c - half)
	var i1 := mini(n - 1, c + half)
	var la := i0
	for i in range(i0, c + 1):
		if smooth[i] > smooth[la]:
			la = i
	var lb := i1
	for i in range(c, i1 + 1):
		if smooth[i] > smooth[lb]:
			lb = i
	var depth := 0.0
	var deepest := c
	for i in range(la, lb + 1):
		var edge := lerpf(smooth[la], smooth[lb], float(i - la) / maxf(lb - la, 1))
		if edge - smooth[i] > depth:
			depth = edge - smooth[i]
			deepest = i
	return { x = deepest * res, depth = depth, a = Vector2(la * res, smooth[la]), b = Vector2(lb * res, smooth[lb]) }


func lane_of(x: float) -> int:
	return 0 if x < sim.lane_joint_x else 1


func in_wheel_path(x: float) -> bool:
	for wp in sim.wheel_paths:
		if absf(x - wp) <= WHEEL_PATH_HALF:
			return true
	return false


func _run(heights: PackedFloat32Array, res: float) -> void:
	var t := sim.time
	var nc := sim.nx * sim.ny
	# Widest crack in each 10 cm cell (fatigue severity reads it).
	var cell_w := PackedFloat32Array()
	cell_w.resize(nc)
	for c in sim.cracks:
		if not c.alive:
			continue
		for k in c.pts.size():
			var i := sim.cell_index(c.pts[k])
			if not c.sealed(t):
				cell_w[i] = maxf(cell_w[i], c.width(mini(k, c.pts.size() - 1), t))

	# --- Fatigue areas (1) ------------------------------------------------------------------------------------
	var fat := PackedByteArray()
	fat.resize(nc)
	for i in nc:
		var p := sim.cell_center(i)
		if sim.load[i] > 0.0 and sim.paved(p) and sim.fatigue[i] >= AsphaltSim.FATIGUE_CELLS and sim.crack_len[i] > 0.02 \
				and sim.hole[i] <= 0.0 and sim.patch_of[i] < 0 and sim.fill_born[i] < 0.0:
			fat[i] = 1
	# Each connected patch of cells gets its severity; patches within FATIGUE_MERGE of each other are one
	# occurrence ("an area"), rated at the highest severity in it (DIM p. 4).
	var parts: Array[Dictionary] = []
	for comp in _components(fat, true):
		var dens := 0.0
		var w := 0.0
		var breaking := false
		var bb := Rect2(sim.cell_center(comp[0]), Vector2.ZERO)
		for i in comp:
			dens += sim.crack_len[i]
			w += cell_w[i]
			var c := sim.cell_center(i)
			bb = bb.expand(c - Vector2.ONE * AsphaltSim.CELL * 0.5).expand(c + Vector2.ONE * AsphaltSim.CELL * 0.5)
			for o in [1, -1, sim.nx, -sim.nx]:
				var j: int = i + o
				if j >= 0 and j < nc and sim.hole[j] > 0.0:
					breaking = true
		dens /= comp.size()
		w /= comp.size()
		var sev := "H" if w > SPALL_WIDTH or breaking else ("M" if dens >= COMPLETE_PATTERN else "L")
		parts.append({ cells = comp, rect = bb, severity = sev, lane = lane_of(bb.get_center().x) })
	var merged := true
	while merged:
		merged = false
		for a in parts.size():
			for b in range(a + 1, parts.size()):
				if parts[a].lane == parts[b].lane and (parts[a].rect as Rect2).grow(FATIGUE_MERGE * 0.5).intersects(
						(parts[b].rect as Rect2).grow(FATIGUE_MERGE * 0.5)):
					var cells: PackedInt32Array = parts[a].cells
					cells.append_array(parts[b].cells)
					parts[a].cells = cells
					parts[a].rect = (parts[a].rect as Rect2).merge(parts[b].rect)
					if _rank(parts[b].severity) > _rank(parts[a].severity):
						parts[a].severity = parts[b].severity
					parts.remove_at(b)
					merged = true
					break
			if merged:
				break
	for part in parts:
		var area: float = part.cells.size() * AsphaltSim.CELL * AsphaltSim.CELL
		if area < MIN_AREA:
			for i in part.cells:
				fat[i] = 0
			continue
		areas.append({ code = "1" + part.severity, type = 1, severity = part.severity, lane = part.lane, area = area,
			counted = true, cells = part.cells, rect = part.rect })

	# --- Potholes (8) -----------------------------------------------------------------------------------------
	var holes := PackedByteArray()
	holes.resize(nc)
	for i in nc:
		if sim.hole[i] > 0.0 and sim.patch_of[i] < 0 and sim.fill_born[i] < 0.0:
			holes[i] = 1
	for comp in _components(holes, true):
		var depth := 0.0
		var bb := Rect2()
		var first := true
		var seen := { }
		var a := 0.0
		for i in comp:
			depth = maxf(depth, sim.hole[i])
			var c := sim.cell_center(i)
			var r := Rect2(c - Vector2.ONE * AsphaltSim.CELL * 0.5, Vector2.ONE * AsphaltSim.CELL)
			bb = r if first else bb.merge(r)
			first = false
			var k := sim._cell_seed[i]
			if k >= 0 and not sim.net_cells[k].is_empty() and not seen.has(k):
				seen[k] = true
				var poly: PackedVector2Array = sim.net_cells[k]
				for q in poly:
					bb = bb.expand(q)
				a += absf(_poly_area(poly))
		a = maxf(a, comp.size() * AsphaltSim.CELL * AsphaltSim.CELL)
		var sev := "L" if depth < 0.025 else ("M" if depth <= 0.05 else "H")
		var ok := minf(bb.size.x, bb.size.y) >= MIN_POTHOLE and a >= MIN_POTHOLE_AREA
		areas.append({ code = "8" + sev, type = 8, severity = sev, lane = lane_of(bb.get_center().x), area = a,
			counted = ok, rect = bb, depth = depth, cells = comp })

	# --- Patches (7): heavy patches and cold patch ------------------------------------------------------------
	for k in sim.patches.size():
		var rect: Rect2 = sim.patches[k].rect
		areas.append({ code = "7", type = 7, severity = "L", lane = lane_of(rect.get_center().x), area = rect.get_area(),
			counted = rect.get_area() >= MIN_PATCH, rect = rect, born = sim.patches[k].born, heavy = true })
	var fills := PackedByteArray()
	fills.resize(nc)
	for i in nc:
		if sim.fill_born[i] >= 0.0:
			fills[i] = 1
	for comp in _components(fills, false):
		var a := comp.size() * AsphaltSim.CELL * AsphaltSim.CELL
		var worst := "L"
		var born := 0.0
		for i in comp:
			born = maxf(born, sim.fill_born[i])
			if sim.hole[i] > 0.0:
				worst = "H"    # it has broken out again: loss of patch material, a hole in it
		var bb := Rect2(sim.cell_center(comp[0]), Vector2.ZERO)
		for i in comp:
			bb = bb.expand(sim.cell_center(i) - Vector2.ONE * 0.05).expand(sim.cell_center(i) + Vector2.ONE * 0.05)
		areas.append({ code = "7", type = 7, severity = worst, lane = lane_of(bb.get_center().x), area = a,
			counted = a >= MIN_PATCH, rect = bb, born = born, heavy = false, cells = comp })

	# --- Cracks: lines (4, 6, 2, 16), edge cracking (3), and the patch seams that rate the patches ----------------
	var done := { }
	var block_w := [0.0, 0.0]
	var block_len := [0.0, 0.0]
	var block_box: Array = [null, null]
	var edge_rows: Array = [{ }, { }]
	for ci in sim.cracks.size():
		var c := sim.cracks[ci]
		if not c.alive or c.pts.size() < 2 or done.has(ci):
			continue
		done[ci] = true
		# A crack and its twin (grown both ways from one start) are one crack.
		var pts := PackedVector2Array(c.pts)
		var wid := PackedFloat32Array()
		for k in c.pts.size():
			wid.append(c.width(k, t))
		if c.twin >= 0 and c.twin < sim.cracks.size() and sim.cracks[c.twin].alive and not done.has(c.twin):
			var o := sim.cracks[c.twin]
			done[c.twin] = true
			var rp := PackedVector2Array()
			var rw := PackedFloat32Array()
			for k in range(o.pts.size() - 1, 0, -1):
				rp.append(o.pts[k])
				rw.append(o.width(k, t))
			rp.append_array(pts)
			rw.append_array(wid)
			pts = rp
			wid = rw
		var length := 0.0
		var in_fat := 0.0
		var in_wp := 0.0
		var wsum := 0.0
		var seg_len := PackedFloat32Array()
		for k in pts.size() - 1:
			var l := pts[k].distance_to(pts[k + 1])
			seg_len.append(l)
			length += l
			var mid := (pts[k] + pts[k + 1]) * 0.5
			if fat[sim.cell_index(mid)] == 1:
				in_fat += l
			if in_wheel_path(mid.x):
				in_wp += l
			wsum += l * wid[k]
		if length < MIN_CRACK:
			continue
		var sealed := c.sealed(t)
		var mean_w := wsum / length
		var lane := lane_of((pts[0].x + pts[pts.size() - 1].x) * 0.5)
		match c.kind:
			AsphaltSim.Kind.FATIGUE:
				continue   # the crocodile network: drawn as the fatigue area
			AsphaltSim.Kind.EDGE:
				var side := 0 if pts[0].x < sim.size.x * 0.5 else 1
				for q in pts:
					edge_rows[side][clampi(int(q.y / AsphaltSim.CELL), 0, sim.ny - 1)] = true
				continue
			AsphaltSim.Kind.SEAM:
				_rate_patch_seam(pts, mean_w, sealed)
				lines.append({ code = "", type = 7, sub = "", severity = "", sealed = sealed, pts = pts, length = length,
					lane = lane, counted = false })
				continue
			AsphaltSim.Kind.BLOCK:
				block_w[lane] += wsum
				block_len[lane] += length
				var bb := Rect2(pts[0], Vector2.ZERO)
				for q in pts:
					bb = bb.expand(q)
				block_box[lane] = bb if block_box[lane] == null else (block_box[lane] as Rect2).merge(bb)
				lines.append({ code = "", type = 2, sub = "", severity = "", sealed = sealed, pts = pts, length = length,
					lane = lane, counted = false })
				continue
			AsphaltSim.Kind.SLIPPAGE:
				lines.append({ code = "16", type = 16, sub = "", severity = "", sealed = false, pts = pts, length = length,
					lane = lane, counted = true, what = "slippage crack" })
				continue
		if c.kind == AsphaltSim.Kind.WHEELPATH and in_fat > length * 0.5:
			continue   # meanders with random cracking round it: part of the fatigue area
		var span := pts[pts.size() - 1] - pts[0]
		var along := absf(span.y) >= absf(span.x)
		if c.kind == AsphaltSim.Kind.TRANSVERSE:
			along = false
		elif c.kind == AsphaltSim.Kind.JOINT:
			along = true
		var item := { type = 4 if along else 6, sealed = sealed, pts = pts, lane = lane, counted = true }
		if along:
			item.sub = "a" if in_wp > length * 0.5 else "b"
			item.severity = "L" if sealed else severity_of_width(mean_w)
			item.length = length
		else:
			# The highest severity present over at least 10 % of the length; length in fatigue areas not counted.
			var by := { "L": 0.0, "M": 0.0, "H": 0.0 }
			for k in seg_len.size():
				by[severity_of_width(wid[k])] += seg_len[k]
			var sev := "L"
			for s in ["M", "H"]:
				if by[s] >= 0.1 * length:
					sev = s
			item.sub = ""
			item.severity = "L" if sealed else sev
			item.length = length - in_fat
		item.code = str(item.type) + item.sub + item.severity
		lines.append(item)

	# Block areas: the box the block cracks span in each lane, paved, less fatigue, patches and potholes.
	for lane in 2:
		if block_box[lane] == null or block_len[lane] <= 0.0:
			continue
		var bb: Rect2 = block_box[lane]
		var cells := PackedInt32Array()
		for i in nc:
			var p := sim.cell_center(i)
			if bb.has_point(p) and sim.paved(p) and fat[i] == 0 and holes[i] == 0 and sim.patch_of[i] < 0 and sim.fill_born[i] < 0.0:
				cells.append(i)
		var sev := severity_of_width(block_w[lane] / block_len[lane])
		areas.append({ code = "2" + sev, type = 2, severity = sev, lane = lane, area = cells.size() * 0.01, counted = true,
			rect = bb, cells = cells })
		if sim.size.y < 15.0:
			notes.append("Lane %d: block cracking rated over %.0f m; the DIM asks for an occurrence of at least 15 m." % [lane + 1, sim.size.y])

	# Edge cracking: rows of edge with an edge crack or broken-off edge, per side; breakup (fretting) sets severity.
	if sim.unsealed_edges:
		for side in 2:
			var fret: PackedFloat32Array = sim.edge_l if side == 0 else sim.edge_r
			var rows := { }
			for r in edge_rows[side]:
				rows[r] = true
			for r in sim.ny:
				if fret[r] > 0.01:
					rows[r] = true
			if rows.is_empty():
				continue
			var keys := rows.keys()
			keys.sort()
			var broken := 0
			for r in keys:
				if fret[r] > 0.01:
					broken += 1
			var share := float(broken) / keys.size()
			var sev := "L" if broken == 0 else ("M" if share <= 0.1 else "H")
			var runs: Array[Vector2i] = []
			for r in keys:
				if runs.is_empty() or r > runs[runs.size() - 1].y + 1:
					runs.append(Vector2i(r, r))
				else:
					runs[runs.size() - 1].y = r
			edges.append({ side = side, lane = side, rows = runs, length = keys.size() * AsphaltSim.CELL, severity = sev,
				code = "3" + sev })

	# Spot sealcoat: sealant without aggregate, 16 Other (DIM p. 14), if 0.1 m2 or more.
	for sp in sim.seal_spots:
		var a := absf(_poly_area(sp.poly))
		if a >= MIN_PATCH:
			var c := Vector2.ZERO
			for q in sp.poly:
				c += q
			c /= (sp.poly as PackedVector2Array).size()
			areas.append({ code = "16", type = 16, severity = "", lane = lane_of(c.x), area = a, counted = true, poly = sp.poly,
				what = "spot sealcoat (sealant without aggregate)" })

	# Patch codes now that their seams have rated them.
	for a in areas:
		if a.type == 7:
			a.code = "7" + a.severity

	# Rutting under the straightedge, every metre along each wheel path.
	if heights.size() > 0:
		var w := int(round(sim.size.x / res)) + 1
		var h := heights.size() / w
		for lane in 2:
			sheets[lane].rut = []
		for wp in sim.wheel_paths:
			var lane := lane_of(wp)
			var deepest := 0.0
			var total := 0.0
			var count := 0
			var y := 0.5
			while y < sim.size.y:
				var iy := clampi(int(round(y / res)), 0, h - 1)
				var r := straightedge_rut(heights.slice(iy * w, iy * w + w), res, wp)
				deepest = maxf(deepest, r.depth)
				total += r.depth
				count += 1
				y += 1.0
			sheets[lane].rut.append({ x = wp, mean = total / maxf(count, 1), max = deepest })

	for lane in 2:
		_sum(lane)


func _rate_patch_seam(pts: PackedVector2Array, mean_w: float, sealed: bool) -> void:
	var sev := "L" if sealed else severity_of_width(mean_w)
	var mid := pts[pts.size() / 2]
	for a in areas:
		if a.type != 7:
			continue
		var r: Rect2 = a.rect
		if r.grow(0.15).has_point(mid) and _rank(sev) > _rank(a.severity):
			a.severity = sev


func _rank(s: String) -> int:
	return { "L": 0, "M": 1, "H": 2 }.get(s, -1)


## Data sheet 1 and 2 quantities for a lane: { "1": [L, M, H] m2, "2": m2, "3": m, "4a", "4a_sealed", "4b",
## "4b_sealed": m, "6_count", "6_m", "6_sealed": [L, M, H], "7_count", "7_m2", "8_count", "8_m2": [L, M, H],
## "16": [descriptions] }.
func totals_for(lane: int) -> Dictionary:
	return sheets[lane]


func _sum(lane: int) -> void:
	var s := sheets[lane]
	for key in ["1", "2", "3", "4a", "4a_sealed", "4b", "4b_sealed", "6_count", "6_m", "6_sealed", "7_count", "7_m2",
			"8_count", "8_m2"]:
		s[key] = [0.0, 0.0, 0.0]
	s["16"] = []
	for a in areas:
		if a.lane != lane or not a.counted:
			continue
		var r := _rank(a.severity)
		match a.type:
			1, 2:
				s[str(a.type)][r] += a.area
			7:
				s["7_count"][r] += 1
				s["7_m2"][r] += a.area
			8:
				s["8_count"][r] += 1
				s["8_m2"][r] += a.area
			16:
				s["16"].append("%s, %.1f m2" % [a.what, a.area])
	for e in edges:
		if e.lane == lane:
			s["3"][_rank(e.severity)] += e.length
	for l in lines:
		if l.lane != lane or not l.counted:
			continue
		if l.type == 16:
			s["16"].append("%s, %.1f m" % [l.what, l.length])
			continue
		var r := _rank(l.severity)
		if l.type == 4:
			s["4" + l.sub][r] += l.length
			if l.sealed:
				s["4" + l.sub + "_sealed"][r] += l.length
		elif l.type == 6:
			s["6_count"][r] += 1
			s["6_m"][r] += l.length
			if l.sealed:
				s["6_sealed"][r] += l.length


## Connected groups of flagged cells (8-neighbour with `diagonal`, else 4).
func _components(flag: PackedByteArray, diagonal: bool) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var seen := PackedByteArray()
	seen.resize(flag.size())
	var nb: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	if diagonal:
		nb.append_array([Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
	for i in flag.size():
		if flag[i] == 0 or seen[i] == 1:
			continue
		var comp := PackedInt32Array()
		var stack := [i]
		seen[i] = 1
		while not stack.is_empty():
			var j: int = stack.pop_back()
			comp.append(j)
			var cx := j % sim.nx
			var cy := j / sim.nx
			for o in nb:
				var x := cx + o.x
				var y := cy + o.y
				if x < 0 or y < 0 or x >= sim.nx or y >= sim.ny:
					continue
				var k := y * sim.nx + x
				if flag[k] == 1 and seen[k] == 0:
					seen[k] = 1
					stack.append(k)
		out.append(comp)
	return out


func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
