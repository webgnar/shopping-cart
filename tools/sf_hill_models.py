"""Build the San Francisco hill level's models in Blender from primitives and export them as .glb.

Run from the repo root, either with Blender or with the `bpy` Python module:
    blender -b -P tools/sf_hill_models.py -- [name ...]
    python3 tools/sf_hill_models.py [name ...]        # needs `pip install bpy`

Writes shopping-cart/assets/models/sf_hill/<name>/<name>.glb. For new models, then run
`godot --headless --import` in shopping-cart/ and `python3 tools/sf_hill_models.py --link-materials`
(no Blender needed) so each .glb uses the shared Godot materials, and import again.

The primitives, the z-fighting scan and the export come from tools/parking_lot_models.py (`Model`).
Conventions (sizes chosen are in docs/DEV_NOTES.md, "San Francisco hill level"):
- Meters, real-world sizes. Blender X = Godot X, Blender Y = Godot -Z, Blender Z = Godot Y.
- Props face Blender +Y (= Godot -Z) with the origin at the bottom centre. Street pieces and houses
  document their own origin below.
- Each object has ONE material, named after a shared Godot material: assets/parking_lot/materials/<name>.tres
  when the parking lot already has it (asphalt, concrete, car parts...), else assets/sf_hill/materials/<name>.tres.
- No z-fighting: every model is scanned for overlapping coplanar faces before export.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parking_lot_models as plm  # noqa: E402  (Model, primitives, z-fighting scan, export)

if "--link-materials" not in sys.argv:
    from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "shopping-cart", "assets", "models", "sf_hill")
plm.OUT = OUT
LOT_MATERIALS = os.path.join(REPO, "shopping-cart", "assets", "parking_lot", "materials")
SF_MATERIALS = "res://assets/sf_hill/materials/"

# Preview colours only: in Godot the shared .tres materials replace these by name.
plm.COLORS.update({
    "paint_yellow": (0.93, 0.72, 0.12), "gutter": (0.6, 0.59, 0.56), "yard": (0.25, 0.3, 0.18),
    "house_paint_sky": (0.55, 0.72, 0.82), "house_stucco_cream": (0.9, 0.85, 0.74), "house_trim_white": (0.94, 0.93, 0.9),
    "house_accent_red": (0.6, 0.14, 0.12), "window_glass": (0.12, 0.15, 0.18), "roof_tar": (0.17, 0.17, 0.18),
    "foliage": (0.2, 0.33, 0.15), "bark": (0.33, 0.27, 0.2), "hydrant_white": (0.9, 0.9, 0.88),
    "hydrant_blue": (0.13, 0.3, 0.62), "stop_red": (0.72, 0.06, 0.07), "seawall": (0.62, 0.6, 0.56),
})

# Street cross-section (Blender Y, from the road's centre line): 12 m curb to curb (two travel lanes and two
# parking lanes, a 40 ft San Francisco residential street) and a 3 m (10 ft) sidewalk each side.
GUTTER = 5.55     # the gutter pan, 0.45 m of concrete along the curb
CURB = 6.0        # curb face
WALK = 6.15       # back of the curb, where the sidewalk starts
EDGE = 9.0        # back of the sidewalk, where the lots start
CURB_H = 0.15
SLAB = 0.5        # how deep the road slab goes under its surface
BLOCK = 60.0      # a block of street, measured along its slope
CROSS = 100.0     # how far the cross street runs each way from the middle of the intersection
GROUND = 130.0    # the yards beside a block reach this far from the centre line
TREE_WELLS = (7.5, 22.5, 37.5, 52.5)   # along a block: where its street trees stand, both sides
TREE_Y = 7.9      # a tree's distance from the centre line


def xz_prism(m, o, outline, y0, y1):
    """Extrude an outline in the XZ plane (counter-clockwise seen from +Y, the front) from y = y0 to y1 (y1 > y0)."""
    n = len(outline)
    verts = [Vector((p[0], y1, p[1])) for p in outline] + [Vector((p[0], y0, p[1])) for p in outline]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i + n, (i + 1) % n + n, (i + 1) % n, i) for i in range(n)]
    m._add(o, verts, faces)


def arch_outline(x0, x1, z0, z1, segs=8):
    """A window with a round top: straight sides from z0, a half circle on top reaching z1."""
    r = (x1 - x0) / 2
    cx, spring = (x0 + x1) / 2, z1 - r
    pts = [(x0, z0), (x1, z0)]
    for i in range(segs + 1):
        a = math.pi * i / segs
        pts.append((cx + r * math.cos(a), spring + r * math.sin(a)))
    return pts


def slab_row(m, o, x0, x1, y0, y1, top, pitch=1.5, gap=0.01, along="X"):
    """Sidewalk slabs 5 mm thick on a base, with 1 cm joints: the joints show as grooves."""
    length = x1 - x0 if along == "X" else y1 - y0
    n = max(1, round(length / pitch))
    step = length / n
    for i in range(n):
        if along == "X":
            a, b = x0 + i * step + gap / 2, x0 + (i + 1) * step - gap / 2
            m.box(o, (b - a, y1 - y0 - gap, 0.005), ((a + b) / 2, (y0 + y1) / 2, top - 0.0025))
        else:
            a, b = y0 + i * step + gap / 2, y0 + (i + 1) * step - gap / 2
            m.box(o, (x1 - x0 - gap, b - a, 0.005), ((x0 + x1) / 2, (a + b) / 2, top - 0.0025))


def box_span(m, o, x0, x1, y0, y1, z0, z1):
    m.box(o, (x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))


# ------------------------------------------------------------------ street pieces

def hill_block():
    """A block of street 60 m long, running along +X from its origin: the road's centre line at the uphill end,
    on the road surface. The level tilts it to the block's grade (it is built flat), so the sidewalks and yards
    follow the slope. Road with gutters and curbs, scored sidewalks, a double yellow line, storm drains and
    manholes, and the yards beside it out to 130 m."""
    m = plm.Model("hill_block")
    road = m.obj("Road", "asphalt")
    box_span(m, road, 0, BLOCK, -GUTTER, GUTTER, -SLAB, 0)
    gut = m.obj("Gutters", "gutter")
    curb = m.obj("Curbs", "curb_concrete")
    base = m.obj("SidewalkBase", "concrete")
    walk = m.obj("Sidewalk", "sidewalk")
    yard = m.obj("Yards", "yard")
    for s in (-1, 1):
        lo = lambda a, b: (min(s * a, s * b), max(s * a, s * b))
        box_span(m, gut, 0, BLOCK, *lo(GUTTER, CURB), -SLAB, 0)
        box_span(m, curb, 0, BLOCK, *lo(CURB, WALK), -SLAB - CURB_H, CURB_H)
        box_span(m, base, 0, BLOCK, *lo(WALK, EDGE), -SLAB - CURB_H, CURB_H - 0.005)
        slab_row(m, walk, 0, BLOCK, *lo(WALK, EDGE), CURB_H)
        box_span(m, yard, 0, BLOCK, *lo(EDGE, GROUND), -2.0, -0.3)
    paint = m.obj("CenterLine", "paint_yellow")
    for y in (-0.1, 0.1):
        box_span(m, paint, 0, BLOCK, y - 0.05, y + 0.05, 0, 0.002)
    metal = m.obj("Drains", "dark_metal")
    for s in (-1, 1):
        box_span(m, metal, BLOCK - 3.4, BLOCK - 2.5, s * 5.775 - 0.2, s * 5.775 + 0.2, 0, 0.002)
    m.cyl(metal, 0.35, 0.003, (18, -2.6, 0), segs=20)
    m.cyl(metal, 0.35, 0.003, (42, 2.4, 0), segs=20)
    for x in TREE_WELLS:   # iron tree grates, 1.2 m square, 1 cm proud of the sidewalk: bars across, in a frame
        for s in (-1, 1):
            y = s * TREE_Y
            for k in range(-2, 3):
                box_span(m, metal, x - 0.56, x + 0.56, y + k * 0.27 - 0.02, y + k * 0.27 + 0.02, CURB_H, CURB_H + 0.01)
            for e in (-1, 1):
                box_span(m, metal, *sorted((x + e * 0.56, x + e * 0.6)), y - 0.6, y + 0.6, CURB_H, CURB_H + 0.012)
    return m.build()


def intersection():
    """The flat crossing at the top and foot of each block, 18 x 18 m between the sidewalks' outer edges, origin
    in the middle on the road surface. The cross street runs along Y to 100 m each way, with its sidewalks, a
    double yellow line, ladder crosswalks on all four sides and yards beyond the ends."""
    m = plm.Model("intersection")
    road = m.obj("Road", "asphalt")
    gut = m.obj("Gutters", "gutter")
    curb = m.obj("Curbs", "curb_concrete")
    base = m.obj("SidewalkBase", "concrete")
    walk = m.obj("Sidewalk", "sidewalk")
    box_span(m, road, -CURB, CURB, -CURB, CURB, -SLAB, 0)                          # the crossing itself
    for s in (-1, 1):
        box_span(m, road, *sorted((s * CURB, s * EDGE)), -GUTTER, GUTTER, -SLAB, 0)   # main street stubs
        box_span(m, road, -GUTTER, GUTTER, *sorted((s * CURB, s * CROSS)), -SLAB, 0)  # cross street arms
    for sx in (-1, 1):
        for sy in (-1, 1):
            xs = lambda a, b: sorted((sx * a, sx * b))
            ys = lambda a, b: sorted((sy * a, sy * b))
            box_span(m, gut, *xs(GUTTER, CURB), *ys(CURB, CROSS), -SLAB, 0)        # along the cross street
            box_span(m, gut, *xs(CURB, EDGE), *ys(GUTTER, CURB), -SLAB, 0)         # along the main street stub
            box_span(m, curb, *xs(CURB, WALK), *ys(CURB, CROSS), -SLAB - CURB_H, CURB_H)
            box_span(m, curb, *xs(WALK, EDGE), *ys(CURB, WALK), -SLAB - CURB_H, CURB_H)
            box_span(m, base, *xs(WALK, EDGE), *ys(WALK, CROSS), -SLAB - CURB_H, CURB_H - 0.005)
            slab_row(m, walk, *xs(WALK, EDGE), *ys(WALK, CROSS), CURB_H, along="Y")
    yard = m.obj("Yards", "yard")
    for s in (-1, 1):
        box_span(m, yard, -EDGE, EDGE, *sorted((s * CROSS, s * GROUND)), -2.0, -0.3)
    paint = m.obj("CenterLine", "paint_yellow")
    for s in (-1, 1):
        for x in (-0.1, 0.1):
            box_span(m, paint, x - 0.05, x + 0.05, *sorted((s * 9.0, s * CROSS)), 0, 0.002)
    white = m.obj("Crosswalks", "paint_white")
    bars = [-4.8 + 1.2 * i for i in range(9)]
    for s in (-1, 1):
        for b in bars:
            box_span(m, white, s * 7.5 - 1.2, s * 7.5 + 1.2, b - 0.3, b + 0.3, 0, 0.002)   # across the main street
            box_span(m, white, b - 0.3, b + 0.3, s * 7.5 - 1.2, s * 7.5 + 1.2, 0, 0.002)   # across the cross street
    return m.build()


# ------------------------------------------------------------------ houses

W = 7.0           # house width (a 25 ft lot less side gaps)
SETBACK = 1.5     # the front apron and stoop between the sidewalk and the facade
DEPTH = 13.5      # facade to back wall
FOUND = 6.0       # the foundation runs this far down, so a house can stand on a slope


def _house_shell(m, height):
    """Foundation and apron, walls, roof and corner boards common to both houses. Returns the object names."""
    o = {
        "walls": m.obj("Walls", "house_paint_sky"),
        "trim": m.obj("Trim", "house_trim_white"),
        "accent": m.obj("Accent", "house_accent_red"),
        "glass": m.obj("Glass", "window_glass"),
        "base": m.obj("Base", "concrete"),
        "roof": m.obj("Roof", "roof_tar"),
        "rail": m.obj("Railings", "dark_metal"),
    }
    f = -SETBACK
    box_span(m, o["base"], -W / 2, W / 2, f - DEPTH, 0, -FOUND, 0)
    box_span(m, o["walls"], -W / 2, W / 2, f - DEPTH, f, 0, height)
    box_span(m, o["roof"], -W / 2 + 0.02, W / 2 - 0.02, f - DEPTH + 0.02, f - 0.02, height, height + 0.05)
    for s in (-1, 1):   # corner boards
        box_span(m, o["trim"], *sorted((s * (W / 2 - 0.02), s * (W / 2 - 0.2))), f, f + 0.04, 0, height - 0.55)
    # stoop on the right: 6 risers of 19 cm up to the entry, its treads 25 cm deep
    rise, n = 0.19, 6
    run = SETBACK / n
    m.prism(o["base"], _stair_profile(f, n, rise, run), 1.25, 2.85)
    for x in (1.3, 2.8):    # handrails
        top = rise * n + 0.9
        m.tube(o["rail"], (x, -0.05, 0.9 + rise), (x, f + 0.05, top), 0.022)
        m.tube(o["rail"], (x, -0.05, 0.0), (x, -0.05, 0.9 + rise), 0.02)
    # garage on the left: door, frame and panel rails
    box_span(m, o["accent"], -3.1, -0.7, f, f + 0.03, 0.0, 2.3)
    for z in (0.58, 1.15, 1.72):
        box_span(m, o["trim"], -3.05, -0.75, f + 0.03, f + 0.045, z - 0.025, z + 0.025)
    box_span(m, o["trim"], -3.25, -0.55, f, f + 0.06, 2.3, 2.45)
    for x in (-3.25, -0.7):
        box_span(m, o["trim"], x, x + 0.15, f, f + 0.06, 0.0, 2.3)
    # entry door at the top of the stoop, with its surround and a transom
    z0 = rise * n
    box_span(m, o["accent"], 1.5, 2.6, f, f + 0.03, z0, z0 + 2.05)
    box_span(m, o["glass"], 1.55, 2.55, f, f + 0.01, z0 + 2.12, z0 + 2.42)
    for x in (1.32, 2.6):
        box_span(m, o["trim"], x, x + 0.18, f, f + 0.08, z0, z0 + 2.5)
    box_span(m, o["trim"], 1.22, 2.88, f, f + 0.14, z0 + 2.5, z0 + 2.7)
    return o


def _stair_profile(f, n, rise, run):
    """A stoop's side outline in YZ (counter-clockwise seen from +X): from the sidewalk (y = 0) up to the facade."""
    pts = [(f, 0.0), (0.0, 0.0)]
    for k in range(1, n + 1):
        y = -(k - 1) * run
        pts += [(y, rise * k), (y - run, rise * k)]
    pts[-1] = (f, rise * n)
    # counter-clockwise seen from +X means going from -Y to +Y along the bottom
    return pts


def _window(m, o, cx, z0, w, h, face, sill=True, hood=True, arch=False):
    """A window on a facade facing +Y at y = face: glass 1 cm proud, a frame 4 cm proud, sill and hood."""
    if arch:
        xz_prism(m, o["glass"], arch_outline(cx - w / 2, cx + w / 2, z0, z0 + h), face, face + 0.01)
        outer = arch_outline(cx - w / 2 - 0.12, cx + w / 2 + 0.12, z0, z0 + h + 0.12)
        inner = arch_outline(cx - w / 2, cx + w / 2, z0, z0 + h)
        # frame: the arch ring, built as strips between the outer and inner outline
        for i in range(2, len(outer) - 1):
            xz_prism(m, o["trim"], [outer[i], outer[i + 1], inner[i + 1], inner[i]], face, face + 0.04)
        for x in (cx - w / 2 - 0.12, cx + w / 2):
            box_span(m, o["trim"], x, x + 0.12, face, face + 0.04, z0, z0 + h - w / 2)
    else:
        box_span(m, o["glass"], cx - w / 2, cx + w / 2, face, face + 0.01, z0, z0 + h)
        box_span(m, o["trim"], cx - 0.03, cx + 0.03, face + 0.01, face + 0.025, z0, z0 + h)   # mullion
        for a, b in ((cx - w / 2, cx - 0.03), (cx + 0.03, cx + w / 2)):                       # meeting rail
            box_span(m, o["trim"], a, b, face + 0.01, face + 0.02, z0 + h * 0.58, z0 + h * 0.58 + 0.05)
        for x in (cx - w / 2 - 0.12, cx + w / 2):
            box_span(m, o["trim"], x, x + 0.12, face, face + 0.04, z0, z0 + h)
        if hood:
            box_span(m, o["trim"], cx - w / 2 - 0.2, cx + w / 2 + 0.2, face, face + 0.12, z0 + h, z0 + h + 0.22)
    if sill:
        box_span(m, o["trim"], cx - w / 2 - 0.18, cx + w / 2 + 0.18, face, face + 0.09, z0 - 0.1, z0)


def _bay_window(m, o, cx, half_back, half_front, depth, z0, z1, f):
    """A three-sided bay standing out from the facade (y = f) over the garage, z0 to z1, with windows on all three
    faces on each floor, a corbelled base and a cap."""
    outline = [(cx - half_back, f), (cx + half_back, f), (cx + half_front, f + depth), (cx - half_front, f + depth)]
    m.prism(o["walls"], outline, z0, z1, plane="XY")
    grow = 0.07
    big = [(cx - half_back - grow, f), (cx + half_back + grow, f), (cx + half_front + grow, f + depth + grow),
           (cx - half_front - grow, f + depth + grow)]
    m.prism(o["trim"], big, z0 - 0.25, z0, plane="XY")          # base
    m.prism(o["trim"], big, z1, z1 + 0.22, plane="XY")          # cap
    for k in range(3):   # corbels under the base
        x = cx - half_front + 0.15 + k * (2 * half_front - 0.3) / 2
        box_span(m, o["trim"], x - 0.08, x + 0.08, f, f + depth - 0.05, z0 - 0.7, z0 - 0.25)
    floors = [(z0 + 0.45, 1.9), (z0 + 3.65, 1.9)] if z1 - z0 > 5 else [(z0 + 0.45, 1.9)]
    for wz, wh in floors:
        # front face
        _window(m, o, cx, wz, 2 * half_front - 0.6, wh, f + depth, hood=False)
        # angled sides: build a flat window, rotate it onto the side face
        for s in (-1, 1):
            a = Vector((cx + s * half_back, f, 0))
            b = Vector((cx + s * half_front, f + depth, 0))
            mid = (a + b) / 2
            t = (b - a).normalized()
            nrm = Vector((t.y, -t.x, 0)) * s   # outward
            ang = math.atan2(nrm.x, nrm.y)
            rot = Matrix.Rotation(-ang, 3, "Z")
            ln = (b - a).length
            gw = ln - 0.36
            m.box(o["glass"], (gw, 0.01, wh), mid + nrm * 0.005 + Vector((0, 0, wz + wh / 2)), rot=rot)
            for e in (-1, 1):
                m.box(o["trim"], (0.1, 0.04, wh), mid + nrm * 0.02 + t * e * (gw / 2 + 0.05) + Vector((0, 0, wz + wh / 2)),
                      rot=rot)
            m.box(o["trim"], (gw + 0.2, 0.09, 0.1), mid + nrm * 0.045 + Vector((0, 0, wz - 0.05)), rot=rot)


def house_victorian():
    """A three-storey Italianate row house (a "painted lady"), 7 m wide. Origin: the middle of the lot's front line
    at the sidewalk, front facing +Y. The garage and stoop sit on a 1.5 m apron, the facade stands 1.5 m back, the
    foundation runs 6 m down so the house can stand on a slope. Painted per house in Godot: Walls, Trim, Accent."""
    m = plm.Model("house_victorian")
    h = 10.2
    o = _house_shell(m, h)
    f = -SETBACK
    _bay_window(m, o, -1.75, 1.45, 0.9, 0.8, 3.4, 9.3, f)
    for wz in (4.2, 7.3):
        _window(m, o, 2.05, wz, 1.1, 2.0, f)
    for z in (3.88, 6.8):   # belt courses between the floors, beside the bay
        box_span(m, o["trim"], -0.2, W / 2 - 0.2, f, f + 0.08, z, z + 0.12)
    # cornice: fascia, crown, modillion blocks and dentils between them
    box_span(m, o["trim"], -W / 2, W / 2, f, f + 0.12, h - 0.55, h)
    box_span(m, o["trim"], -W / 2 - 0.05, W / 2 + 0.05, f, f + 0.45, h, h + 0.18)
    blocks = (-W / 2 + 0.1, -0.15, W / 2 - 0.4)
    for x in blocks:
        box_span(m, o["trim"], x, x + 0.25, f + 0.12, f + 0.42, h - 0.55, h)
    n = 30
    for i in range(n):
        x = -W / 2 + 0.25 + i * (W - 0.5) / (n - 1)
        if any(b - 0.06 < x < b + 0.31 for b in blocks):
            continue
        box_span(m, o["trim"], x - 0.04, x + 0.04, f + 0.12, f + 0.2, h - 0.12, h)
    return m.build()


def house_stucco():
    """A three-storey Edwardian stucco house, 7 m wide: flat front, round-topped windows, an iron balcony, a red
    tile pent roof along the top and a parapet. Same origin, apron, stoop and garage as house_victorian."""
    m = plm.Model("house_stucco")
    h = 10.4
    o = _house_shell(m, h)
    o["tile"] = m.obj("Tiles", "roof_tile")
    f = -SETBACK
    for cx in (-2.2, -0.45):
        _window(m, o, cx, 4.2, 1.2, 2.2, f, sill=False, arch=True)
        _window(m, o, cx, 7.0, 1.2, 1.9, f, arch=True)
    _window(m, o, 2.05, 7.0, 1.1, 1.9, f, arch=True)
    _window(m, o, 2.05, 4.2, 1.1, 2.0, f)
    # balcony on the second floor across the two arched windows
    box_span(m, o["trim"], -3.15, 0.5, f, f + 0.6, 4.05, 4.2)
    for i in range(16):
        x = -3.1 + i * 3.55 / 15
        m.tube(o["rail"], (x, f + 0.56, 4.2), (x, f + 0.56, 5.05), 0.012, segs=6)
    m.tube(o["rail"], (-3.15, f + 0.56, 5.08), (0.5, f + 0.56, 5.08), 0.025)
    for x in (-3.15, 0.5):
        m.tube(o["rail"], (x, f + 0.585, 5.08), (x, f + 0.03, 5.08), 0.025, segs=7)
    for z in (3.88, 6.7):
        box_span(m, o["trim"], 0.75, W / 2 - 0.2, f, f + 0.06, z, z + 0.1)
    # pent roof of red tile on the facade, then the parapet over it
    prof = [(f, h - 1.25), (f + 0.75, h - 1.0), (f + 0.75, h - 0.92), (f, h - 0.55)]
    m.prism(o["tile"], prof, -W / 2 + 0.2, W / 2 - 0.2)
    box_span(m, o["trim"], -W / 2, W / 2, f, f + 0.1, h - 0.3, h)
    box_span(m, o["trim"], -W / 2 - 0.04, W / 2 + 0.04, f, f + 0.2, h, h + 0.12)
    return m.build()


# ------------------------------------------------------------------ street props

def street_lamp():
    """A San Francisco street light: 9 m tapered steel pole on a base, an arm reaching 2 m over the street (+Y) and
    a cobra head with its lens facing down. The light itself is a SpotLight3D in the scene."""
    m = plm.Model("street_lamp")
    pole = m.obj("Pole", "pole_metal")
    m.cyl(pole, 0.17, 0.55, (0, 0, 0), segs=12, r_top=0.15)
    m.cyl(pole, 0.11, 8.6, (0, 0, 0.55), segs=12, r_top=0.065)
    m.tube(pole, (0, 0, 8.5), (0, 1.0, 8.95), 0.045)
    m.tube(pole, (0, 0.95, 8.93), (0, 2.0, 9.05), 0.04)
    m.cyl(pole, 0.07, 0.06, (0, 0, 9.15), segs=12, r_top=0.03)
    head = m.obj("Head", "dark_metal")
    m.box(head, (0.34, 0.75, 0.16), (0, 2.25, 9.05))
    m.box(head, (0.26, 0.4, 0.08), (0, 2.25, 9.17))
    lens = m.obj("Lens", "led_lens")
    m.box(lens, (0.26, 0.55, 0.01), (0, 2.27, 8.965))
    return m.build()


def street_tree():
    """A London plane street tree, 7.5 m: tapered trunk with three leaders and a broad crown of leaf clumps. Its
    tree grate is part of the street block (TREE_WELLS), so it lies on the sloped sidewalk."""
    m = plm.Model("street_tree")
    bark = m.obj("Trunk", "bark")
    m.cyl(bark, 0.14, 2.6, (0, 0, 0), segs=10, r_top=0.11)
    m.tube(bark, (0, 0, 2.5), (0.7, 0.3, 4.4), 0.09, segs=8)
    m.tube(bark, (0, 0, 2.5), (-0.6, -0.4, 4.6), 0.09, segs=8)
    m.tube(bark, (0, 0, 2.5), (0.1, -0.1, 5.0), 0.08, segs=8)
    leaf = m.obj("Crown", "foliage")
    for i, (c, r) in enumerate((((0.7, 0.3, 4.9), 1.5), ((-0.7, -0.4, 5.2), 1.6), ((0.1, -0.1, 6.0), 1.5),
                                ((0.3, 1.0, 5.1), 1.2), ((-0.4, 0.9, 5.6), 1.15), ((0.9, -0.9, 5.4), 1.1))):
        m.ball(leaf, r, c, scale=(1, 1, 0.8), segs=10, rings=7, jitter=0.12, seed=i + 3)
    return m.build()


def fire_hydrant():
    """A San Francisco high-pressure (AWSS) fire hydrant, 0.8 m: white body, blue bonnet and caps, the outlets
    left, right and to the front (+Y)."""
    m = plm.Model("fire_hydrant")
    body = m.obj("Body", "hydrant_white")
    m.cyl(body, 0.17, 0.06, (0, 0, 0), segs=16)
    m.cyl(body, 0.12, 0.5, (0, 0, 0.06), segs=16, r_top=0.11)
    m.cyl(body, 0.15, 0.05, (0, 0, 0.56), segs=16)
    for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0)):
        r = 0.065 if d[1] else 0.045
        m.cyl(body, r, 0.11, (d[0] * 0.08, d[1] * 0.08, 0.4), axis=Vector(d), segs=12)
    cap = m.obj("Caps", "hydrant_blue")
    m.cyl(cap, 0.13, 0.08, (0, 0, 0.61), segs=16, r_top=0.1)
    m.ball(cap, 0.1, (0, 0, 0.69), scale=(1, 1, 0.6), segs=12, rings=6)
    m.cyl(cap, 0.025, 0.06, (0, 0, 0.74), segs=6)
    for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0)):
        r = 0.075 if d[1] else 0.055
        m.cyl(cap, r, 0.04, (d[0] * 0.19, d[1] * 0.19, 0.4), axis=Vector(d), segs=12)
    return m.build()


def stop_sign():
    """A stop sign: 2.4 m square steel post and a 75 cm octagon facing +Y (the text is a Label3D in the scene)."""
    m = plm.Model("stop_sign")
    post = m.obj("Post", "pole_metal")
    box_span(m, post, -0.03, 0.03, -0.06, 0.0, 0.0, 2.45)
    oct_ = lambda r: [(r * math.cos(math.pi / 8 + i * math.pi / 4), 2.1 + r * math.sin(math.pi / 8 + i * math.pi / 4))
                      for i in range(8)]
    border = m.obj("Border", "paint_white")
    xz_prism(m, border, oct_(0.375 / math.cos(math.pi / 8)), 0.0, 0.015)
    face = m.obj("Face", "stop_red")
    xz_prism(m, face, oct_(0.345 / math.cos(math.pi / 8)), 0.015, 0.017)
    return m.build()


def seawall():
    """The Embarcadero seawall the street runs into at the bottom: 40 m of concrete wall along X with its top
    1.05 m over the street, a capstone and a steel railing. Origin: the middle of its street-side face at street
    level, the street on its +Y side; the wall drops 5 m on the water side."""
    m = plm.Model("seawall")
    wall = m.obj("Wall", "seawall")
    box_span(m, wall, -20, 20, -0.8, 0, -5.0, 0.95)
    cap = m.obj("Cap", "concrete")
    box_span(m, cap, -20.05, 20.05, -0.85, 0.05, 0.95, 1.05)
    rail = m.obj("Railing", "dark_metal")
    for i in range(21):
        x = -20 + 0.4 + i * 39.2 / 20
        m.tube(rail, (x, -0.4, 1.05), (x, -0.4, 2.1), 0.03, segs=8)
    m.tube(rail, (-19.6, -0.4, 2.1), (19.6, -0.4, 2.1), 0.035, segs=8)
    m.tube(rail, (-19.6, -0.4, 1.6), (19.6, -0.4, 1.6), 0.02, segs=8)
    return m.build()


# ------------------------------------------------------------------ materials

def link_materials():
    """Point each .glb's materials at the shared Godot .tres of the same name, in its .import file: the parking
    lot's when it has one, else the hill's own (assets/sf_hill/materials/)."""
    import json
    import re
    import struct
    for name in MODELS:
        glb = os.path.join(OUT, name, name + ".glb")
        imp = glb + ".import"
        if not os.path.exists(imp):
            print("no .import yet for", name, "- run godot --headless --import first")
            continue
        data = open(glb, "rb").read()
        length = struct.unpack_from("<I", data, 12)[0]
        mats = [mm["name"] for mm in json.loads(data[20:20 + length]).get("materials", [])]
        path = lambda mm: ("res://assets/parking_lot/materials/%s.tres" % mm
                           if os.path.exists(os.path.join(LOT_MATERIALS, mm + ".tres")) else SF_MATERIALS + mm + ".tres")
        entries = ",\n".join('"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s"\n}' % (mm, path(mm))
                             for mm in mats)
        sub = '_subresources={\n"materials": {\n%s\n}\n}' % entries
        text = open(imp).read()
        text = re.sub(r"_subresources=\{.*?\n\}\n(?=\S)|_subresources=\{\}\n", sub + "\n", text, count=1, flags=re.S)
        open(imp, "w").write(text)
        print("LINKED", name, ", ".join(mats))


MODELS = {f.__name__: f for f in (hill_block, intersection, house_victorian, house_stucco, street_lamp, street_tree,
                                   fire_hydrant, stop_sign, seawall)}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if args == ["--link-materials"]:
        link_materials()
        sys.exit(0)
    fights = 0
    for n in args or list(MODELS):
        fights += MODELS[n]()
    print("DONE, z-fighting hits:", fights)
