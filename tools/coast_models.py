"""Build the coast highway level (console `coast`) in Blender from primitives and export it as .glb.

A long, winding two-lane road down a coastal mountainside in the style of California's Highway 1 (Big Sur):
ocean cliffs on the right going downhill, a hillside with Monterey pines and cypresses on the left, a steel
guardrail on the cliff side, and a tunnel through a headland at each end (where the traffic comes and goes).

Run from the repo root, with Blender or the `bpy` Python module:
    blender -b -P tools/coast_models.py -- [name ...]
    python3 tools/coast_models.py [name ...]           # needs `pip install bpy`
then, in shopping-cart/:
    godot --headless --import
    python3 ../tools/coast_models.py --link-materials  # each .glb uses the shared Godot materials
    godot --headless --import
    xvfb-run godot --rendering-method gl_compatibility -s res://tools/make_coast_resources_cli.gd  # shapes, trees
    python3 ../tools/coast_models.py --scenes          # the level and segment scenes (no Blender needed)

The road is laid out here once, from PIECES (lengths and turns) and GRADES (the downhill grade along the road), and
written to shopping-cart/assets/models/coast/coast_plan.json for the steps after it. Edit the plan here and re-run
every step to change the road; edit the scenes directly for anything else (traffic, spawn, lighting).

Writes shopping-cart/assets/models/coast/<name>/<name>.glb:
- segment_01 .. segment_10: 150 m of road each, with its lines, shoulders, ditch, guardrail, cliff and hillside.
- collision: the road deck, the guardrail and the terrain as coarse meshes (made into trimesh shapes in Godot).
- backdrop: the mountains behind the hillside, out to 800 m (no collision).
- headland_top, headland_bottom: the rock the road tunnels into at each end, with the concrete portal and tube.
- pine, cypress, shrub: the trees (placed by MultiMesh in Godot).

Conventions (sizes chosen are in docs/DEV_NOTES.md, "Coast highway level"):
- Meters, real-world sizes. Blender X = Godot X, Blender Y = Godot -Z, Blender Z = Godot Y.
- The road is built in level space: segment and headland models are placed at the level's origin.
- Trees face Blender +Y with the origin at the bottom centre of the trunk.
- Each object has ONE material, named after a shared Godot material (parking lot / SF hill / assets/coast/materials).
- No z-fighting: every model is scanned for overlapping coplanar faces before export.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
if __name__ == "__main__" and "--scenes" in sys.argv:   # plain Python: tools/coast_scenes.py
    import coast_scenes
    coast_scenes.write_all()
    sys.exit(0)
import parking_lot_models as plm  # noqa: E402  (primitives, material, export)

SCENES_ONLY = "--link-materials" in sys.argv or "--scenes" in sys.argv
if not SCENES_ONLY:
    import bpy  # noqa: F401  (first: provides bmesh and mathutils)
    import bmesh
    from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "shopping-cart")
OUT = os.path.join(GAME, "assets", "models", "coast")
plm.OUT = OUT
PLAN_PATH = os.path.join(OUT, "coast_plan.json")
LOT_MATERIALS = os.path.join(GAME, "assets", "parking_lot", "materials")
SF_MATERIALS = os.path.join(GAME, "assets", "sf_hill", "materials")
COAST_MATERIALS = "res://assets/coast/materials/"

plm.COLORS.update({
    "paint_yellow": (0.93, 0.72, 0.12), "gravel": (0.55, 0.52, 0.47), "guardrail_post": (0.36, 0.29, 0.21),
    "cliff_rock": (0.46, 0.42, 0.37), "cut_rock": (0.6, 0.53, 0.44), "hill_scrub": (0.42, 0.43, 0.24),
    "backdrop_hills": (0.36, 0.38, 0.24), "pine_needles": (0.15, 0.25, 0.13), "cypress_foliage": (0.17, 0.27, 0.15),
    "shrub_scrub": (0.3, 0.35, 0.2), "bark": (0.33, 0.27, 0.2), "tunnel_dark": (0.03, 0.03, 0.035),
})

# ------------------------------------------------------------------ the plan

DS = 2.0                 # m between cross-sections of the visible road
COL_DS = 4.0             # m between cross-sections of the collision meshes
# The road from the top tunnel to the bottom one: (length m, turn degrees; + = right, toward the ocean).
PIECES = [(60, 0), (80, 0), (110, -55), (60, 0), (140, 90), (70, 0), (120, -80), (50, 0), (100, 60), (90, -40),
          (80, 0), (130, 70), (60, -20), (120, -60), (70, 30), (100, 0), (60, 0)]
CURVE_SMOOTH = 40.0      # m: curvature eases in and out over this length (a clothoid-like transition)
# Downhill grade along the road (s m, grade), eased between: flat at both tunnels, 7 to 10 % between.
GRADES = [(0, 0.0), (130, 0.0), (200, 0.08), (450, 0.08), (520, 0.10), (700, 0.10), (760, 0.07), (900, 0.07),
          (960, 0.10), (1100, 0.10), (1160, 0.08), (1300, 0.08), (1370, 0.0), (1500, 0.0)]
BOTTOM_Y = 6.0           # m: the road's height over the sea at the bottom tunnel
PORTAL_TOP, PORTAL_BOTTOM = 40.0, 1460.0   # stations of the tunnel portals
SEGMENT = 150.0          # m of road per segment model
SPAWN_S, SPAWN_T = 80.0, 4.4

# Cross-section, t = metres right of the centre line (+ toward the ocean), h = height over the centre line.
LANE = 3.6               # two 12 ft lanes
SHOULDER_SEA = 5.4       # paved shoulder on the cliff side, 1.8 m
GRAVEL_SEA = 6.8         # gravel strip with the guardrail
SHOULDER_HILL = -5.0     # paved shoulder on the hill side, 1.4 m
DITCH = (-5.0, -5.5, -6.0)
RAIL_T = 5.9             # face of the guardrail
VERGE = 9.0              # the scrub verge on the cliff top ends here and the rock starts
HILL_EDGE = -60.0        # how far the hillside model reaches
LANE_T = 1.8             # traffic drives on the lane centres


def _ease(u):
    return (1 - math.cos(math.pi * max(0.0, min(1.0, u)))) / 2


def grade_at(s):
    for (a, ga), (b, gb) in zip(GRADES, GRADES[1:]):
        if a <= s <= b:
            return ga + (gb - ga) * _ease((s - a) / (b - a))
    return 0.0


def make_rows():
    """The centre line every 0.5 m: [s, x, y, z, heading] (Godot coordinates; heading 0 = +X, + turns to +Z)."""
    step = 0.5
    length = sum(p[0] for p in PIECES)
    n = int(round(length / step))
    k = [0.0] * n
    s0 = 0.0
    for l, a in PIECES:
        for i in range(int(round(s0 / step)), int(round((s0 + l) / step))):
            k[i] = math.radians(a) / l
        s0 += l
    w = int(CURVE_SMOOTH / step)
    pre = [0.0]
    for v in k:
        pre.append(pre[-1] + v)
    ks = [(pre[min(n, i + w // 2)] - pre[max(0, i - w // 2)]) / w for i in range(n)]
    rows = []
    x = y = z = th = 0.0
    for i in range(n + 1):
        s = i * step
        rows.append([s, x, y, z, th])
        if i < n:
            th += ks[i] * step
            x += math.cos(th) * step
            z += math.sin(th) * step
            y -= grade_at(s + step / 2) * step
    lift = BOTTOM_Y - rows[-1][2]
    for r in rows:
        r[2] += lift
    return rows


ROWS = make_rows()
LENGTH = ROWS[-1][0]


def at(s):
    """Centre point (x, y, z), heading and right vector (x, z) at station s."""
    i = max(0, min(len(ROWS) - 2, int(s / 0.5)))
    a, b = ROWS[i], ROWS[i + 1]
    u = (s - a[0]) / (b[0] - a[0])
    x, y, z = (a[j] + (b[j] - a[j]) * u for j in (1, 2, 3))
    th = a[4] + (b[4] - a[4]) * u
    return (x, y, z), th, (-math.sin(th), math.cos(th))


def point(s, t, h=0.0):
    """Godot position of (station, offset right, height over the road)."""
    (x, y, z), th, r = at(s)
    return (x + r[0] * t, y + h, z + r[1] * t)


def B(p):
    """Godot -> Blender coordinates."""
    return (p[0], -p[2], p[1])


def noise(*v, seed=0):
    """Smooth deterministic noise in about -1..1 (a few crossed sines)."""
    r = random.Random(seed)
    tot = 0.0
    for _ in range(4):
        f = [r.uniform(0.6, 1.4) for _ in v]
        ph = r.uniform(0, 6.283)
        tot += math.sin(sum(a * b for a, b in zip(f, v)) + ph)
    return tot / 2.4


# Hillside profile, d = metres left of the centre line (d >= 0): height over the road.
HILL_COLS = [6.0, 9.0, 12.0, 16.0, 21.0, 27.0, 34.0, 42.0, 51.0, 60.0]


def hill_h(s, d, rough=True):
    if d <= 5.0:
        return 0.0
    if d <= 6.0:
        return -0.3 + 0.15 * (d - 5.5) / 0.5 if d > 5.5 else -0.3 * (d - 5.0) / 0.5
    if d <= 12.0:   # the road cut: rock, about 42 degrees
        u = (d - 6.0) / 6.0
        return -0.15 + 5.65 * u + (0.4 * noise(s / 9.0, seed=3) * math.sin(math.pi * u) if rough else 0)
    u = (d - 12.0) / 48.0
    base = 5.5 + 26.5 * (1 - (1 - u) ** 1.6) + 5.0 * noise(s / 70.0, seed=7) * u
    if rough:
        base += 2.2 * noise(s / 23.0, d / 17.0, seed=11) * min(1.0, (d - 12.0) / 8.0)
    return base


# Cliff profile on the ocean side: verge, then rock down into the sea.
CLIFF_FRACS = [0.0, 0.08, 0.22, 0.4, 0.58, 0.75, 0.9, 1.0]


def cliff_points(s):
    """[(t, h)] from the gravel's outer edge down to 5 m under the sea."""
    (x, y, z), th, r = at(s)
    pts = [(GRAVEL_SEA, -0.03), ((GRAVEL_SEA + VERGE) / 2, -0.2), (VERGE, -0.6)]
    drop = y + 5.0 - 0.6
    reach = drop / 1.9 * (1.0 + 0.25 * noise(s / 60.0, seed=21)) + 4.0
    for f in CLIFF_FRACS[1:]:
        # Rounded cliff top, steep face, a little toe at the water.
        g = f ** 0.7 if f < 0.75 else 0.82 + (f - 0.75) / 0.25 * 0.18
        bulge = 3.0 * noise(s / 17.0, f * 3.0, seed=31) * math.sin(math.pi * f)
        pts.append((VERGE + reach * g + bulge, -0.6 - drop * (f ** 1.25)))
    return pts


# ------------------------------------------------------------------ model helpers

class Builder(plm.Model):
    """plm.Model with open sheets: objects in `sheets` keep the winding they were built with (bmesh's normal
    recalculation can flip an open surface), and a z-fighting scan that buckets faces by plane, for big models."""

    def __init__(self, name):
        super().__init__(name)
        self.sheets = set()

    def sheet(self, o, grid):
        """A surface through rows of points (Godot coordinates), each row the same length, left to right:
        faces point up for rows that run along the road with points from left to right."""
        n = len(grid[0])
        verts, faces = [], []
        for row in grid:
            verts += [Vector(B(p)) for p in row]
        for i in range(len(grid) - 1):
            for j in range(n - 1):
                a, b = i * n + j, (i + 1) * n + j
                faces.append((a, a + 1, b + 1, b))
        self.sheets.add(o)
        self._add(o, verts, faces)

    def quads(self, o, verts, faces, closed=False):
        """Faces through points in Godot coordinates. Open surfaces keep their winding; `closed` solids are
        oriented by bmesh."""
        if closed:
            self.sheets.discard(o)
        else:
            self.sheets.add(o)
        self._add(o, [Vector(B(p)) for p in verts], faces)

    def build(self):
        objects = []
        for name, (bm, mat) in self.objs.items():
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            if name not in self.sheets:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.normal_update()
            for f in bm.faces:
                f.smooth = True
            for e in bm.edges:
                if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(35):
                    e.smooth = False
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(plm.material(mat))
            ob = bpy.data.objects.new(name, me)
            bpy.context.scene.collection.objects.link(ob)
            objects.append(ob)
        hits = z_fighting(objects)
        for h in hits[:10]:
            print("  Z-FIGHT %s: %s" % (self.name, h))
        tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in objects)
        folder = os.path.join(OUT, self.name)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                                  export_materials="EXPORT", export_texcoords=False, export_tangents=False)
        print("MODEL %-16s %7d tris %6.0f KB  objects: %s  z-fighting: %d" % (
            self.name, tris, os.path.getsize(path) / 1024, ", ".join(o.name for o in objects), len(hits)))
        return len(hits)


def z_fighting(objects, eps=2e-4):
    """plm.z_fighting for big models in level coordinates: faces are bucketed by direction and by 30 m cell, the
    plane test is done locally (a face's distance from the other's plane, not plane constants hundreds of metres
    out) and an overlap must be at least 1 % of the smaller face (shared edges at 1 km out are not overlaps)."""
    import itertools
    faces = []
    for ob in objects:
        vs = ob.data.vertices
        for p in ob.data.polygons:
            n = p.normal.copy()
            pts = [vs[i].co.copy() for i in p.vertices]
            if n.z < -0.999 and abs(pts[0].z) < 1e-4:
                continue
            faces.append((ob.name, p.index, n, pts, p.center.copy(), p.area))
    cells = {}
    for k, f in enumerate(faces):
        n, c = f[2], f[4]
        key = (round(n.x * 20), round(n.y * 20), round(n.z * 20), int(c.x // 30), int(c.y // 30), int(c.z // 30))
        cells.setdefault(key, []).append(k)
    hits = []
    seen = set()
    for key, ks in cells.items():
        near = []
        for dx, dy, dz in itertools.product((-1, 0, 1), repeat=3):
            near += cells.get(key[:3] + (key[3] + dx, key[4] + dy, key[5] + dz), [])
        for i in ks:
            oa, ia, na, pa, ca, aa = faces[i]
            u = (Vector((1, 0, 0)) if abs(na.x) < 0.9 else Vector((0, 1, 0))).cross(na).normalized()
            v = na.cross(u)
            fa = [((q - pa[0]).dot(u), (q - pa[0]).dot(v)) for q in pa]
            for j in near:
                if j <= i or (i, j) in seen:
                    continue
                seen.add((i, j))
                ob, ib, nb, pb, cb, ab = faces[j]
                if na.dot(nb) < 0.999 or max(abs(na.dot(q - pa[0])) for q in pb) > eps:
                    continue
                fb = [((q - pa[0]).dot(u), (q - pa[0]).dot(v)) for q in pb]
                if plm._clip_area(fa, fb) > max(1e-4, 0.01 * min(aa, ab)):
                    hits.append("%s face %d at %s / %s face %d" % (oa, ia, tuple(round(c, 2) for c in ca), ob, ib))
    return hits


def stations(s0, s1, step):
    n = max(1, int(round((s1 - s0) / step)))
    return [s0 + (s1 - s0) * i / n for i in range(n + 1)]


def road_cross(s):
    """Deck cross-section [(t, h)] from the ditch's outer edge to the gravel's outer edge."""
    return [(DITCH[2], -0.15), (DITCH[1], -0.3), (SHOULDER_HILL, 0.0), (-LANE, 0.0), (0.0, 0.0), (LANE, 0.0),
            (SHOULDER_SEA, 0.0), (GRAVEL_SEA, -0.03)]


# ------------------------------------------------------------------ road segments

def build_road(m, s0, s1, objs, ds=DS, lines=True, rail=True):
    """The road from s0 to s1 into model m: asphalt, gravel, lines, guardrail."""
    ss = stations(s0, s1, ds)
    asphalt = m.obj("Asphalt", "asphalt")
    m.sheet(asphalt, [[point(s, t) for t in (SHOULDER_HILL, -LANE, 0.0, LANE, SHOULDER_SEA)] for s in ss])
    gravel = m.obj("Gravel", "gravel")
    m.sheet(gravel, [[point(s, t, h) for t, h in ((DITCH[2], -0.15), (DITCH[1], -0.3), (SHOULDER_HILL, 0.0))]
                     for s in ss])
    m.sheet(gravel, [[point(s, t, h) for t, h in ((SHOULDER_SEA, 0.0), (GRAVEL_SEA, -0.03))] for s in ss])
    objs += [asphalt, gravel]
    if lines:
        ls = [s for s in ss if PORTAL_TOP - 1 <= s <= PORTAL_BOTTOM + 1] or []
        if len(ls) > 1:
            white = m.obj("EdgeLines", "paint_white")
            for a, b in ((-LANE, -LANE + 0.15), (LANE - 0.15, LANE)):
                m.sheet(white, [[point(s, a, 0.003), point(s, b, 0.003)] for s in ls])
            yellow = m.obj("CenterLine", "paint_yellow")
            for a, b in ((-0.2, -0.1), (0.1, 0.2)):
                m.sheet(yellow, [[point(s, a, 0.003), point(s, b, 0.003)] for s in ls])
    if rail:
        rs = [s for s in ss if PORTAL_TOP + 0.5 <= s <= PORTAL_BOTTOM - 0.5]
        if len(rs) > 1:
            build_guardrail(m, rs)


# W-beam: a 31 cm deep steel rail with its top 79 cm up (2 ft 7 in), on 15 cm blockouts and wood posts.
RAIL_PROFILE = [(0.0, 0.48), (0.05, 0.55), (0.0, 0.63), (0.05, 0.71), (0.0, 0.79),
                (0.012, 0.79), (0.062, 0.71), (0.012, 0.63), (0.062, 0.55), (0.012, 0.48)]


def build_guardrail(m, ss):
    rail = m.obj("Guardrail", "rail_metal")
    n = len(RAIL_PROFILE)
    verts, faces = [], []
    for i, s in enumerate(ss):
        verts += [point(s, RAIL_T + dt, h) for dt, h in RAIL_PROFILE]
        if i:
            a, b = (i - 1) * n, i * n
            for j in range(n):
                k = (j + 1) % n
                faces.append((a + j, b + j, b + k, a + k))
    m.quads(rail, verts, faces, closed=True)
    posts = m.obj("GuardrailPosts", "guardrail_post")
    blocks = m.obj("GuardrailBlocks", "guardrail_post")
    for s in ss:
        if abs(s / 1.905 - round(s / 1.905)) * 1.905 > DS / 2 - 1e-6:
            continue
        _, th, _ = at(s)
        _post(m, posts, s, th, RAIL_T + 0.22, 0.15, 0.2, -0.6, 0.76)
        _post(m, blocks, s, th, RAIL_T + 0.088, 0.15, 0.15, 0.44, 0.79)


def _post(m, o, s, th, t, depth, width, h0, h1):
    """A box standing across the road at station s: `depth` along t, `width` along the road."""
    verts = []
    for hh in (h0, h1):
        for ds_, dt in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = point(s, t + dt * depth / 2, hh)
            verts.append((p[0] + math.cos(th) * ds_ * width / 2, p[1], p[2] + math.sin(th) * ds_ * width / 2))
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    m.quads(o, verts, faces, closed=True)


def build_terrain(m, s0, s1, ds=DS, rough=True, collision=False):
    """Verge and cliff on the ocean side, road cut and hillside on the inland side, from s0 to s1."""
    ss = stations(s0, s1, ds)
    if collision:
        o = m.obj("Terrain", "hill_scrub")
        hill = [[point(s, -d, hill_h(s, d, rough)) for d in HILL_COLS[::-1]] for s in ss]
        m.sheet(o, hill)
        m.sheet(o, [[point(s, t, h) for t, h in cliff_points(s)] for s in ss])
        return
    cut = m.obj("RoadCut", "cut_rock")
    m.sheet(cut, [[point(s, -d, hill_h(s, d, rough)) for d in (12.0, 10.0, 8.0, 6.0)] for s in ss])
    scrub = m.obj("Hillside", "hill_scrub")
    m.sheet(scrub, [[point(s, -d, hill_h(s, d, rough)) for d in HILL_COLS[::-1] if d >= 12.0] for s in ss])
    verge = m.obj("Verge", "shrub_scrub")
    cliff = m.obj("Cliff", "cliff_rock")
    vg, cl = [], []
    for s in ss:
        pts = [point(s, t, h) for t, h in cliff_points(s)]
        vg.append(pts[:3])
        cl.append(pts[2:])
    m.sheet(verge, vg)
    m.sheet(cliff, cl)


def segment_range(i):
    s0 = i * SEGMENT
    return s0, min(LENGTH, s0 + SEGMENT)


SEGMENTS = int(math.ceil(LENGTH / SEGMENT))
TERRAIN_S = (PORTAL_TOP - 8.0, PORTAL_BOTTOM + 8.0)   # the terrain runs a little into each headland


def segment(i):
    m = Builder("segment_%02d" % (i + 1))
    s0, s1 = segment_range(i)
    objs = []
    build_road(m, s0, s1, objs)
    a, b = max(s0, TERRAIN_S[0]), min(s1, TERRAIN_S[1])
    if b > a:
        build_terrain(m, a, b)
    return m.build()


def collision():
    """Coarse meshes for Godot's trimesh shapes: Deck (the whole road), Rail, and Terrain_NN per segment."""
    m = Builder("collision")
    ss = stations(0, LENGTH, COL_DS)
    deck = m.obj("Deck", "asphalt")
    m.sheet(deck, [[point(s, t, h) for t, h in road_cross(s) if t not in (-LANE, 0.0, LANE)] for s in ss])
    rail = m.obj("Rail", "rail_metal")
    rs = stations(PORTAL_TOP + 0.5, PORTAL_BOTTOM - 0.5, COL_DS)
    # The face the cart meets and the top, 4 cm proud of the beam's face, up to the beam's top.
    m.sheet(rail, [[point(s, RAIL_T - 0.04, -0.05), point(s, RAIL_T - 0.04, 0.8), point(s, RAIL_T + 0.1, 0.8)]
                   for s in rs])
    for i in range(SEGMENTS):
        s0, s1 = segment_range(i)
        a, b = max(s0, TERRAIN_S[0]), min(s1, TERRAIN_S[1])
        if b <= a:
            continue
        name = "Terrain_%02d" % (i + 1)
        o = m.obj(name, "hill_scrub")
        for s_ in [stations(a, b, COL_DS)]:
            m.sheet(o, [[point(s, -d, hill_h(s, d)) for d in HILL_COLS[::-1]] for s in s_])
            m.sheet(o, [[point(s, t, h) for t, h in cliff_points(s)] for s in s_])
    for end in ("top", "bottom"):
        o = m.obj("Headland_" + end, "cliff_rock")
        build_headland_surface(m, o, end, coarse=True)
        build_tube(m, m.obj("Tube_" + end, "tunnel_dark"), end, collision=True)
    return m.build()


# ------------------------------------------------------------------ headlands and tunnels

HEAD_DEPTH = 110.0       # m the headland reaches back from its portal
HEAD_SIDE_HILL = 110.0   # m inland and seaward
HEAD_SIDE_SEA = 90.0
FACE_H = 15.0            # rock face over the portal
TUBE_W = (-5.6, 6.2)     # the tube's walls (t), opening 11.8 m
TUBE_SPRING = 3.2        # the arch starts this high
TUBE_DEPTH = 38.0


def portal_frame(end):
    """(s of the portal, direction into the mountain along s: -1 at the top, +1 at the bottom)."""
    return (PORTAL_TOP, -1) if end == "top" else (PORTAL_BOTTOM, 1)


def head_point(end, u, t, h):
    """A point u m into the headland (straight on along the road's tangent at the portal), t right, h over the
    portal's road height."""
    sp, sign = portal_frame(end)
    (x, y, z), th, r = at(sp)
    f = (math.cos(th) * sign, math.sin(th) * sign)
    return (x + f[0] * u + r[0] * t, y + h, z + f[1] * u + r[1] * t)


def front_profile(end):
    """[(t, h)] of the ground at the portal's station, left to right: the hillside, the road, the cliff."""
    sp, _ = portal_frame(end)
    left = [(-d, hill_h(sp, d)) for d in HILL_COLS[::-1]]
    road = [(t, h) for t, h in road_cross(sp)][1:]
    sea = cliff_points(sp)[1:]
    return left + road + sea


def build_headland_surface(m, o, end, coarse=False):
    sp, sign = portal_frame(end)
    y0 = at(sp)[0][1]
    front = front_profile(end)
    # Outer columns: the hillside on further, the sea side straight down into the water.
    cols = [(-HEAD_SIDE_HILL, None), (-85.0, None)] + front + [(HEAD_SIDE_SEA, None)]
    us = [0.0, 1.5, 6.0, 14.0, 26.0, 42.0, 60.0, 82.0, HEAD_DEPTH] if not coarse else [0.0, 1.5, 14.0, 42.0, HEAD_DEPTH]
    grid = []
    for iu, u in enumerate(us):
        row = []
        for ic, (t, h) in enumerate(cols):
            edge = ic in (0, len(cols) - 1) or iu == len(us) - 1
            if iu == 0:
                hh = h if h is not None else (hill_h(sp, -t) if t < 0 else -y0 - 8)
                if t < -60:
                    hh = hill_h(sp, 60.0) + (-t - 60) * 0.5
            else:
                base = max(0.0, (hill_h(sp, -t) if t < 0 else 0.0)) if t > -60 else hill_h(sp, 60.0) + (-t - 60) * 0.5
                hh = base + FACE_H + 0.45 * (u - 1.5) + 4.0 * noise(u / 19.0, t / 23.0, seed=41 + (end == "top")) * min(1, u / 10)
                if t > 20:   # the sea side rounds down to the water
                    hh -= (t - 20) * 0.6
            if edge:
                hh = -y0 - 12.0 if (t > 0 or iu == len(us) - 1) else hh
            row.append(head_point(end, u, t, hh))
        grid.append(row)
    if sign > 0:   # keep the faces pointing up and out: rows run along -s at the bottom end, so flip columns
        grid = [row[::-1] for row in grid]
    n = len(cols)
    verts, faces = [], []
    for row in grid:
        verts += row
    lo, hi = TUBE_W
    for i in range(len(grid) - 1):
        for j in range(n - 1):
            ta, tb = cols[j][0], cols[j + 1][0]
            if sign > 0:
                ta, tb = cols[n - 1 - j][0], cols[n - 2 - j][0]
            if i == 0 and min(ta, tb) >= lo - 0.5 and max(ta, tb) <= hi + 0.7:
                continue   # the hole for the tunnel, behind the portal
            a, b = i * n + j, (i + 1) * n + j
            faces.append((a, b, b + 1, a + 1))
    m.quads(o, verts, faces)


def arch(t0, t1, spring, segs=12):
    cx, r = (t0 + t1) / 2, (t1 - t0) / 2
    return [(cx - r * math.cos(math.pi * k / segs), spring + r * math.sin(math.pi * k / segs)) for k in range(segs + 1)]


def build_tube(m, o, end, collision=False):
    """The tunnel's lining from the portal TUBE_DEPTH m in, and the dark wall closing it."""
    lo, hi = TUBE_W
    prof = [(lo, -0.3), (lo, TUBE_SPRING)] + arch(lo, hi, TUBE_SPRING)[1:-1] + [(hi, TUBE_SPRING), (hi, -0.3)]
    us = [1.8, TUBE_DEPTH] if collision else [1.8, 12.0, 24.0, TUBE_DEPTH]
    n = len(prof)
    verts, faces = [], []
    for u in us:
        verts += [head_point(end, u, t, h) for t, h in prof]
    for i in range(len(us) - 1):
        for j in range(n - 1):
            a, b = i * n + j, (i + 1) * n + j
            faces.append((a, a + 1, b + 1, b) if end == "top" else (a, b, b + 1, a + 1))
    # End wall.
    c = len(verts)
    verts += [head_point(end, TUBE_DEPTH, t, h) for t, h in prof]
    faces.append(tuple(range(c, c + n)) if end == "top" else tuple(range(c + n - 1, c - 1, -1)))
    m.quads(o, verts, faces)


def build_portal(m, end):
    """The concrete portal: a wall 2.4 m thick (it reaches back past the rock face) with the arched opening,
    standing FACE_H + 1 m over the road so it covers the hole in the rock."""
    o = m.obj("Portal", "concrete")
    lo, hi = TUBE_W
    out_lo, out_hi = lo - 3.0, hi + 3.0
    top = FACE_H + 1.0
    cx, wo = (lo + hi) / 2, (out_hi - out_lo) / 2
    a = arch(lo, hi, TUBE_SPRING)
    segs = len(a) - 1
    ring_in = [(lo, -0.3), (lo, TUBE_SPRING), (lo, TUBE_SPRING)] + a[1:-1] + [(hi, TUBE_SPRING), (hi, TUBE_SPRING), (hi, -0.3)]
    outer = [(out_lo, -0.3), (out_lo, TUBE_SPRING), (out_lo, top)]
    outer += [(cx - wo * math.cos(math.pi * k / segs), top) for k in range(1, segs)]
    outer += [(out_hi, top), (out_hi, TUBE_SPRING), (out_hi, -0.3)]
    n = len(ring_in)
    verts, faces = [], []
    for u in (-0.6, 1.8):
        verts += [head_point(end, u, t, h) for t, h in ring_in] + [head_point(end, u, t, h) for t, h in outer]
    F, Bk = 0, 2 * n
    for j in range(n - 1):
        faces.append((F + j, F + j + 1, F + n + j + 1, F + n + j))            # front
        faces.append((Bk + j, Bk + n + j, Bk + n + j + 1, Bk + j + 1))        # back
        faces.append((F + j + 1, F + j, Bk + j, Bk + j + 1))                  # inside of the opening
        faces.append((F + n + j, F + n + j + 1, Bk + n + j + 1, Bk + n + j))  # outside
    faces.append((F, F + n, Bk + n, Bk))                                       # bottoms
    faces.append((F + n - 1, Bk + n - 1, Bk + 2 * n - 1, F + 2 * n - 1))
    m.quads(o, verts, faces, closed=True)
    # Cap stone along the top.
    cap = m.obj("PortalCap", "concrete")
    _head_box(m, cap, end, -0.9, 2.1, out_lo - 0.3, out_hi + 0.3, top, top + 0.5)


def _head_box(m, o, end, u0, u1, t0, t1, h0, h1):
    verts = [head_point(end, u, t, h) for h in (h0, h1) for t in (t0, t1) for u in (u0, u1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    m.quads(o, verts, faces, closed=True)


def headland(end):
    m = Builder("headland_" + end)
    rock = m.obj("Rock", "cliff_rock")
    build_headland_surface(m, rock, end)
    build_tube(m, m.obj("Tube", "tunnel_dark"), end)
    build_portal(m, end)
    return m.build()


# ------------------------------------------------------------------ backdrop

BACK_RES = 12.0


def far_rise(x, z, d, m=math):
    """The mountains past the hillside model (d >= 60 m from the road): height over the hillside's top edge.
    Works on numbers (m = math) and numpy arrays (m = numpy)."""
    ridge = m.sin(x / 180.0) * 0.5 + m.sin(x / 71.0 + z / 97.0) * 0.3 + m.sin(z / 43.0 - x / 61.0) * 0.2
    k = (d - 60) / 80.0
    k = m.minimum(1, k) if m is not math else min(1.0, k)
    lip = (1 - (d - 60) / 15.0)
    lip = m.maximum(0, lip) if m is not math else max(0.0, lip)
    return (d - 60) * 0.55 + ridge * k * 70.0 - 3.0 * lip


def nearest_row(x, z):
    """(s, t, along) of the road point nearest (x, z): t right of the road, along past it."""
    best, bi = 1e18, 0
    for i in range(0, len(ROWS), 4):
        r = ROWS[i]
        d2 = (r[1] - x) ** 2 + (r[3] - z) ** 2
        if d2 < best:
            best, bi = d2, i
    r = ROWS[bi]
    dx, dz = x - r[1], z - r[3]
    return r[0], dx * -math.sin(r[4]) + dz * math.cos(r[4]), dx * math.cos(r[4]) + dz * math.sin(r[4])


def backdrop():
    """Mountains behind the hillside, out to about 800 m, rising to 300-450 m. Hidden under the hillside model
    near the road; under the sea on the ocean side (those cells are left out)."""
    import numpy as np
    pts = np.array([[r[1], r[3]] for r in ROWS[::4]])
    ss = np.array([r[0] for r in ROWS[::4]])
    ys = np.array([r[2] for r in ROWS[::4]])
    ths = np.array([r[4] for r in ROWS[::4]])
    x0, x1 = pts[:, 0].min() - 500, pts[:, 0].max() + 500
    z0, z1 = pts[:, 1].min() - 850, pts[:, 1].max() + 250
    xs = np.arange(x0, x1 + 1, BACK_RES)
    zs = np.arange(z0, z1 + 1, BACK_RES)
    gx, gz = np.meshgrid(xs, zs)
    P = np.stack([gx.ravel(), gz.ravel()], 1)
    best = np.full(len(P), 1e18)
    idx = np.zeros(len(P), int)
    for k in range(0, len(pts), 64):
        d2 = ((P[:, None, :] - pts[None, k:k + 64, :]) ** 2).sum(-1)
        j = d2.argmin(1)
        v = d2[np.arange(len(P)), j]
        better = v < best
        best[better] = v[better]
        idx[better] = j[better] + k
    s = ss[idx]
    rx, rz = -np.sin(ths[idx]), np.cos(ths[idx])
    fx, fz = np.cos(ths[idx]), np.sin(ths[idx])
    dx, dz = P[:, 0] - pts[idx, 0], P[:, 1] - pts[idx, 1]
    t = dx * rx + dz * rz
    along = dx * fx + dz * fz
    d = -t
    hvec = np.vectorize(lambda s_, d_: hill_h(s_, d_, rough=False))
    h = np.empty(len(P))
    near = d < 60
    h[near] = hvec(s[near], np.maximum(d[near], 0)) - 3.0 - np.maximum(0, 25 - d[near]) * 1.5
    far = ~near
    h60 = hvec(s, 60.0)
    h[far] = h60[far] + far_rise(P[far, 0], P[far, 1], d[far], np)
    h = ys[idx] + h
    ocean = t > 0
    # Past the road's ends the headlands take over: keep the backdrop under them.
    ends = ((s <= PORTAL_TOP + 1) & (along < 1)) | ((s >= PORTAL_BOTTOM - 1) & (along > -1))
    h[ocean] = -12.0
    h[ends & (np.abs(t) < 100)] = -12.0
    h[ends & (t >= 100)] = -12.0
    h = np.minimum(h, 460.0)
    H = h.reshape(gx.shape)
    m = Builder("backdrop")
    o = m.obj("Mountains", "backdrop_hills")
    verts, faces = [], []
    index = {}
    nz, nx = H.shape
    for iz in range(nz - 1):
        for ix in range(nx - 1):
            q = [(iz, ix), (iz, ix + 1), (iz + 1, ix + 1), (iz + 1, ix)]
            if max(H[a, b] for a, b in q) < -4.0:
                continue
            ids = []
            for a, b in q:
                if (a, b) not in index:
                    index[(a, b)] = len(verts)
                    verts.append((xs[b], H[a, b], zs[a]))
                ids.append(index[(a, b)])
            # Godot x right, z toward the viewer: seen from +Y, (x, z) -> (x+1, z) -> (x+1, z+1) is clockwise in
            # Blender's (x, -z); reverse it so the face points up.
            faces.append((ids[3], ids[2], ids[1], ids[0]))
    m.quads(o, verts, faces)
    return m.build()


# ------------------------------------------------------------------ trees

def pine():
    """Monterey pine, 15 m: a straight trunk and an open, irregular crown of six clumps."""
    m = Builder("pine")
    trunk = m.obj("Trunk", "bark")
    m.cyl(trunk, 0.32, 13.0, (0, 0, -0.5), segs=7, r_top=0.1)
    m.tube(trunk, (0, 0, 7.5), (1.8, 0.6, 10.5), 0.12, segs=5)
    m.tube(trunk, (0, 0, 9.0), (-1.6, -0.5, 11.5), 0.1, segs=5)
    crown = m.obj("Crown", "pine_needles")
    for i, (x, y, z, r, sq) in enumerate([(0.0, 0.0, 12.6, 2.7, 0.7), (1.9, 0.6, 10.4, 2.4, 0.6),
                                          (-1.7, -0.5, 11.0, 2.3, 0.6), (0.4, -1.4, 8.6, 2.2, 0.55),
                                          (-0.6, 1.2, 7.6, 2.0, 0.55), (1.0, 0.4, 6.4, 1.6, 0.5)]):
        m.ball(crown, r, (x, y, z), scale=(1, 1, sq), segs=6, rings=4, jitter=0.18, seed=i + 3)
    return m.build()


def cypress():
    """Monterey cypress, 9 m: a short trunk splitting into leaning leaders under a flat, windswept top."""
    m = Builder("cypress")
    trunk = m.obj("Trunk", "bark")
    m.cyl(trunk, 0.4, 3.2, (0, 0, -0.5), segs=7, r_top=0.3)
    for a, b in (((0, 0, 2.6), (-2.6, 0.8, 6.8)), ((0, 0, 2.6), (2.2, -0.6, 7.0)), ((0, 0, 2.6), (0.4, 1.6, 7.4))):
        m.tube(trunk, a, b, 0.2, segs=5)
    crown = m.obj("Crown", "cypress_foliage")
    for i, (x, y, z, r) in enumerate([(-2.6, 0.8, 7.4, 3.0), (2.2, -0.6, 7.6, 2.8), (0.3, 1.5, 8.1, 2.9),
                                      (0.0, -1.2, 7.1, 2.4), (-0.5, 0.2, 8.6, 2.2)]):
        m.ball(crown, r, (x, y, z), scale=(1.25, 1.0, 0.42), segs=7, rings=4, jitter=0.15, seed=i + 11)
    return m.build()


def shrub():
    """Coyote brush, 1.4 m: two low clumps (no trunk to speak of: the stems are hidden)."""
    m = Builder("shrub")
    crown = m.obj("Crown", "shrub_scrub")
    m.ball(crown, 1.1, (0, 0, 0.55), scale=(1.2, 1.0, 0.7), segs=7, rings=4, jitter=0.15, seed=5)
    m.ball(crown, 0.8, (0.9, 0.5, 0.45), scale=(1.0, 1.0, 0.7), segs=6, rings=4, jitter=0.15, seed=6)
    return m.build()


# ------------------------------------------------------------------ plan file (for Godot)

def tree_places():
    """Trees per segment: {segment: {kind: [[x, y, z, yaw, scale]]}}. Kinds: pine, cypress and shrub on the
    hillside and cliff top; far_pine and far_cypress on the mountains behind (60 to 220 m from the road)."""
    rnd = random.Random(1234)
    kinds = ("pine", "cypress", "shrub", "far_pine", "far_cypress")
    out = {i: {k: [] for k in kinds} for i in range(SEGMENTS)}
    lo, hi = TERRAIN_S[0] + 10, TERRAIN_S[1] - 10
    s = lo
    while s < hi:
        seg = min(SEGMENTS - 1, int(s // SEGMENT))
        dense = 0.5 + 0.5 * noise(s / 90.0, seed=55)   # pines grow in drifts along the road
        # Hillside: pines and the odd cypress, none on the road cut.
        for _ in range(5):
            d = rnd.uniform(14.0, 58.0)
            if rnd.random() < 0.2 + 0.7 * dense:
                kind = "pine" if rnd.random() < 0.8 else "cypress"
                ss = s + rnd.uniform(-2.5, 2.5)
                p = point(ss, -d, hill_surface(ss, d) - 0.4)
                out[seg][kind].append([*p, rnd.uniform(0, 6.283), rnd.uniform(0.75, 1.3)])
        for _ in range(4):
            d = rnd.uniform(13.0, 58.0)
            ss = s + rnd.uniform(-2.5, 2.5)
            p = point(ss, -d, hill_surface(ss, d) - 0.3)
            out[seg]["shrub"].append([*p, rnd.uniform(0, 6.283), rnd.uniform(0.7, 1.4)])
        # The mountains behind: thinner the further up.
        for _ in range(6):
            d = rnd.uniform(64.0, 220.0)
            if rnd.random() > (0.25 + 0.6 * dense) * (1.2 - d / 260.0):
                continue
            ss = s + rnd.uniform(-2.5, 2.5)
            x, _, z = point(ss, -d, 0.0)
            ns, nt, along = nearest_row(x, z)
            if nt > -62.0 or ns <= PORTAL_TOP + 20 or ns >= PORTAL_BOTTOM - 20:
                continue
            y = at(ns)[0][1] + hill_h(ns, 60.0, False) + far_rise(x, z, -nt) - 1.0
            kind = "far_pine" if rnd.random() < 0.85 else "far_cypress"
            out[seg][kind].append([x, y, z, rnd.uniform(0, 6.283), rnd.uniform(0.8, 1.4)])
        # Cliff top: the odd windswept cypress, and scrub on the verge.
        if rnd.random() < 0.1:
            ss = s + rnd.uniform(-2, 2)
            t = rnd.uniform(9.5, 12.0)
            h = _interp_profile(cliff_points(ss), t)
            out[seg]["cypress"].append([*point(ss, t, h - 0.5), rnd.uniform(0, 6.283), rnd.uniform(0.7, 1.0)])
        if rnd.random() < 0.5:
            ss = s + rnd.uniform(-2, 2)
            t = rnd.uniform(7.4, 8.8)
            out[seg]["shrub"].append([*point(ss, t, _interp_profile(cliff_points(ss), t) - 0.25),
                                      rnd.uniform(0, 6.283), rnd.uniform(0.6, 1.0)])
        s += 5.0
    return out


def hill_surface(s, d):
    """Height of the hillside model at (s, d): straight between its columns, as the mesh is."""
    cols = [c for c in HILL_COLS if c >= 12.0]
    for a, b in zip(cols, cols[1:]):
        if a <= d <= b:
            ha, hb = hill_h(s, a), hill_h(s, b)
            return ha + (hb - ha) * (d - a) / (b - a)
    return hill_h(s, d)


def _interp_profile(pts, t):
    for (a, ha), (b, hb) in zip(pts, pts[1:]):
        if a <= t <= b:
            return ha + (hb - ha) * (t - a) / (b - a)
    return pts[-1][1]


def write_plan():
    lane = lambda t, ss: [list(point(s, t, 0.0)) for s in ss]
    ss = stations(2.0, LENGTH - 2.0, 4.0)
    (sx, sy, sz), sth, _ = at(SPAWN_S)
    plan = {
        "length": LENGTH, "segment": SEGMENT, "segments": SEGMENTS,
        "portals": [PORTAL_TOP, PORTAL_BOTTOM],
        "spawn": {"pos": list(point(SPAWN_S, SPAWN_T, 0.0)), "yaw": -sth},
        "downhill": lane(LANE_T, ss),
        "uphill": lane(-LANE_T, ss[::-1]),
        "trees": {str(k + 1): v for k, v in tree_places().items()},
        "top_y": ROWS[0][2], "bottom_y": ROWS[-1][2],
    }
    os.makedirs(OUT, exist_ok=True)
    with open(PLAN_PATH, "w") as f:
        json.dump(plan, f, separators=(",", ":"))
    n = sum(len(v) for seg in plan["trees"].values() for v in seg.values())
    print("PLAN %.0f m, %.1f m drop, %d segments, %d trees/shrubs" % (LENGTH, ROWS[0][2] - ROWS[-1][2], SEGMENTS, n))


# ------------------------------------------------------------------ materials

def link_materials():
    """Point each .glb's materials at the shared Godot .tres of the same name: the parking lot's or the SF hill's
    when they have one, else the coast's own (assets/coast/materials/)."""
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

        def path(mm):
            if os.path.exists(os.path.join(LOT_MATERIALS, mm + ".tres")):
                return "res://assets/parking_lot/materials/%s.tres" % mm
            if os.path.exists(os.path.join(SF_MATERIALS, mm + ".tres")):
                return "res://assets/sf_hill/materials/%s.tres" % mm
            return COAST_MATERIALS + mm + ".tres"
        entries = ",\n".join('"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s"\n}' % (mm, path(mm))
                             for mm in mats)
        sub = '_subresources={\n"materials": {\n%s\n}\n}' % entries
        text = open(imp).read()
        text = re.sub(r"_subresources=\{.*?\n\}\n(?=\S)|_subresources=\{\}\n", sub + "\n", text, count=1, flags=re.S)
        open(imp, "w").write(text)
        print("LINKED", name, ", ".join(mats))


MODELS = {"segment_%02d" % (i + 1): (lambda i=i: segment(i)) for i in range(SEGMENTS)}
MODELS.update({"collision": collision, "backdrop": backdrop, "headland_top": lambda: headland("top"),
               "headland_bottom": lambda: headland("bottom"), "pine": pine, "cypress": cypress, "shrub": shrub})

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if args == ["--link-materials"]:
        link_materials()
        sys.exit(0)
    write_plan()
    fights = 0
    for n in args or list(MODELS):
        fights += MODELS[n]()
    print("DONE, z-fighting hits:", fights)
