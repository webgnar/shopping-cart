"""Build the parking lot level's props in Blender from primitives and export them as .glb.

Run from the repo root, either with Blender or with the `bpy` Python module:
    blender -b -P tools/parking_lot_models.py -- [name ...]
    python3 tools/parking_lot_models.py [name ...]        # needs `pip install bpy`

Writes shopping-cart/assets/models/parking_lot/<name>/<name>.glb. For new models, then run
`godot --headless --import` in shopping-cart/ and `python3 tools/parking_lot_models.py --link-materials [name ...]`
(no Blender needed) so each .glb uses the shared Godot materials, and import again.

Conventions (see docs/levels/parking_lot.md for every size chosen):
- Meters, real-world sizes.
- Front faces Blender +Y (= Godot -Z), origin at the bottom center, unless the model's
  docstring says otherwise (store front, lot surface, stall markings).
- Each object has ONE material, named after a shared Godot material in
  shopping-cart/assets/parking_lot/materials/<name>.tres; the .glb import maps it by name.
- No z-fighting: every model is scanned for overlapping coplanar faces before export.
"""
import math
import os
import random
import sys

if "--link-materials" not in sys.argv:   # that step is plain Python and needs no Blender
    import bpy  # first: the bpy module provides bmesh and mathutils
    import bmesh
    from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "shopping-cart", "assets", "models", "parking_lot")

# Preview colours only: in Godot the shared .tres materials replace these by name.
COLORS = {
    "asphalt": (0.17, 0.18, 0.2), "paint_white": (0.91, 0.91, 0.88), "concrete": (0.65, 0.64, 0.61),
    "curb_concrete": (0.73, 0.71, 0.68), "sidewalk": (0.61, 0.6, 0.56), "pole_metal": (0.78, 0.8, 0.82),
    "dark_metal": (0.23, 0.24, 0.27), "rail_metal": (0.81, 0.83, 0.85), "led_lens": (1, 1, 1),
    "mulch": (0.29, 0.21, 0.15), "shrub": (0.18, 0.29, 0.15), "palm_trunk": (0.42, 0.35, 0.27),
    "palm_frond": (0.24, 0.35, 0.17), "palm_frond_dead": (0.45, 0.36, 0.22), "car_paint": (0.54, 0.56, 0.6),
    "car_glass": (0.08, 0.09, 0.11), "tire": (0.1, 0.1, 0.1), "headlight": (0.87, 0.87, 0.87),
    "taillight": (0.35, 0.05, 0.05), "facade": (0.85, 0.77, 0.6), "facade_trim": (0.92, 0.86, 0.71),
    "store_glass": (1, 0.94, 0.78), "sign_panel": (0.16, 0.16, 0.16), "bollard_yellow": (0.89, 0.73, 0.15),
    "rubber_black": (0.07, 0.07, 0.08), "soffit": (0.81, 0.77, 0.67), "sign_green": (0.37, 0.42, 0.27),
    "roof_tile": (0.49, 0.2, 0.15), "lightbox_face": (0.95, 0.96, 1.0), "water_blue": (0.12, 0.43, 0.77),
    "water_panel": (0.24, 0.56, 0.88), "curb_red": (0.55, 0.16, 0.13),
}


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*COLORS[name], 1)
    return m


class Model:
    """Collects primitives into named objects (one material each), then exports a .glb."""

    def __init__(self, name, by_material=False):
        """by_material: one object per material (named after it), so whole props can be placed into this
        model with `at()` and merged; each prop builder then adds to the object for its material."""
        self.name = name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.objs = {}
        self.by_material = by_material
        self.xf = Matrix.Identity(4)

    def obj(self, name, mat):
        if self.by_material:
            if mat not in self.objs:
                self.objs[mat] = (bmesh.new(), mat)
            return mat
        assert name not in self.objs, name
        self.objs[name] = (bmesh.new(), mat)
        return name

    def at(self, x, z, yaw_deg=0.0):
        """Place the next primitives at Godot (x, 0, z), turned yaw_deg about Godot +Y (= Blender +Z)."""
        self.xf = Matrix.Translation((x, -z, 0)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")

    def _bm(self, o):
        return self.objs[o][0]

    def _add(self, o, verts, faces):
        bm = self._bm(o)
        vs = [bm.verts.new(self.xf @ Vector(v)) for v in verts]
        for f in faces:
            bm.faces.new([vs[i] for i in f])

    # --- primitives (Blender coordinates: X right, Y front, Z up)
    def box(self, o, size, center, rot=None):
        """Axis-aligned box; `rot` is an optional Matrix (3x3) applied about its center."""
        sx, sy, sz = (s / 2 for s in size)
        c = Vector(center)
        corners = [Vector((x, y, z)) for z in (-sz, sz) for y in (-sy, sy) for x in (-sx, sx)]
        if rot is not None:
            corners = [rot @ v for v in corners]
        verts = [c + v for v in corners]
        faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        self._add(o, verts, faces)

    def cyl(self, o, r, h, base, axis="Z", segs=16, r_top=None, rot=None):
        """Cylinder (or cone frustum) standing on `base` along `axis` (X, Y, Z or a Vector)."""
        r_top = r if r_top is None else r_top
        if isinstance(axis, str):
            axis = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]
        d = Vector(axis).normalized()
        q = d.to_track_quat("Z", "Y").to_matrix()
        if rot is not None:
            q = rot @ q
        b = Vector(base)
        verts = []
        for z, rr in ((0, r), (h, r_top)):
            for i in range(segs):
                a = 2 * math.pi * i / segs
                verts.append(b + q @ Vector((rr * math.cos(a), rr * math.sin(a), z)))
        faces = [tuple(range(segs - 1, -1, -1)), tuple(range(segs, 2 * segs))]
        faces += [(i, (i + 1) % segs, segs + (i + 1) % segs, segs + i) for i in range(segs)]
        self._add(o, verts, faces)

    def tube(self, o, a, b, r, segs=10):
        """Cylinder from point a to point b."""
        a, b = Vector(a), Vector(b)
        self.cyl(o, r, (b - a).length, a, axis=(b - a), segs=segs)

    def ball(self, o, r, center, scale=(1, 1, 1), segs=12, rings=8, jitter=0.0, seed=0):
        rnd = random.Random(seed)
        c = Vector(center)
        verts = [c + Vector((0, 0, -r * scale[2]))]
        for j in range(1, rings):
            phi = math.pi * j / rings - math.pi / 2
            for i in range(segs):
                th = 2 * math.pi * i / segs
                k = 1 + (rnd.uniform(-jitter, jitter) if jitter else 0)
                verts.append(c + Vector((r * scale[0] * k * math.cos(phi) * math.cos(th),
                                         r * scale[1] * k * math.cos(phi) * math.sin(th),
                                         r * scale[2] * k * math.sin(phi))))
        verts.append(c + Vector((0, 0, r * scale[2])))
        top = len(verts) - 1
        faces = [(0, 1 + (i + 1) % segs, 1 + i) for i in range(segs)]
        for j in range(rings - 2):
            r0, r1 = 1 + j * segs, 1 + (j + 1) * segs
            faces += [(r0 + i, r0 + (i + 1) % segs, r1 + (i + 1) % segs, r1 + i) for i in range(segs)]
        last = 1 + (rings - 2) * segs
        faces += [(last + i, last + (i + 1) % segs, top) for i in range(segs)]
        self._add(o, verts, faces)

    def prism(self, o, profile, x0, x1, plane="YZ"):
        """Extrude a 2D outline (counter-clockwise seen from +X) from x = x0 to x1.
        plane="XY" extrudes an outline in the XY plane (counter-clockwise from +Z) from z = x0 to x1."""
        n = len(profile)
        if plane == "YZ":
            verts = [Vector((x0, p[0], p[1])) for p in profile] + [Vector((x1, p[0], p[1])) for p in profile]
        else:
            verts = [Vector((p[0], p[1], x0)) for p in profile] + [Vector((p[0], p[1], x1)) for p in profile]
        faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        self._add(o, verts, faces)

    def ring_prism(self, o, outer, inner, z0, z1):
        """Extrude the area between two closed XY outlines (same point count, both CCW) from z0 to z1."""
        n = len(outer)
        assert len(inner) == n
        verts = []
        for z in (z0, z1):
            verts += [Vector((p[0], p[1], z)) for p in outer] + [Vector((p[0], p[1], z)) for p in inner]
        ob, ib, ot, it = 0, n, 2 * n, 3 * n
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append((ot + i, ot + j, it + j, it + i))      # top
            faces.append((ob + j, ob + i, ib + i, ib + j))      # bottom
            faces.append((ob + i, ob + j, ot + j, ot + i))      # outer wall
            faces.append((ib + j, ib + i, it + i, it + j))      # inner wall
        self._add(o, verts, faces)

    def strip(self, o, pts, widths, up=None, fold=0.0):
        """A ribbon along `pts` (a leaf), `widths` per point, folded into a V by `fold` radians."""
        up = Vector((0, 0, 1)) if up is None else up
        verts, faces = [], []
        for i, p in enumerate(pts):
            p = Vector(p)
            t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            side = t.cross(up).normalized()
            n = side.cross(t).normalized()
            w = widths[i] / 2
            lift = math.sin(fold) * w
            verts += [p - side * w * math.cos(fold) + n * lift, p, p + side * w * math.cos(fold) + n * lift]
        for i in range(len(pts) - 1):
            a, b = 3 * i, 3 * (i + 1)
            faces += [(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2)]
        self._add(o, verts, faces)

    # --- output
    def build(self):
        objects = []
        for name, (bm, mat) in self.objs.items():
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.normal_update()
            for f in bm.faces:
                f.smooth = True
            for e in bm.edges:   # auto-smooth: sharp edges above 35 degrees
                if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(35):
                    e.smooth = False
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(material(mat))
            ob = bpy.data.objects.new(name, me)
            bpy.context.scene.collection.objects.link(ob)
            objects.append(ob)
        hits = z_fighting(objects)
        for h in hits:
            print("  Z-FIGHT %s: %s" % (self.name, h))
        tris = sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in objects)
        folder = os.path.join(OUT, self.name)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                                  export_materials="EXPORT", export_texcoords=False, export_tangents=False)
        print("MODEL %-16s %6d tris %5.0f KB  objects: %s  z-fighting: %d" % (
            self.name, tris, os.path.getsize(path) / 1024, ", ".join(o.name for o in objects), len(hits)))
        return len(hits)


def _clip_area(subject, clip):
    """Area of the intersection of two convex polygons (2D point lists), Sutherland-Hodgman."""
    def area(poly):
        return abs(sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))) / 2

    def ccw(poly):
        s = sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))
        return poly if s < 0 else poly[::-1]

    out = ccw(subject)
    clip = ccw(clip)
    for i in range(len(clip)):
        a, b = clip[i - 1], clip[i]
        inp, out = out, []
        if not inp:
            break
        side = lambda p: (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        for j in range(len(inp)):
            p, q = inp[j - 1], inp[j]
            sp, sq = side(p), side(q)
            if sq >= 0:
                if sp < 0:
                    t = sp / (sp - sq)
                    out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
                out.append(q)
            elif sp >= 0:
                t = sp / (sp - sq)
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return area(out) if len(out) >= 3 else 0.0


def z_fighting(objects, eps=2e-4):
    """Faces that face the same way on the same plane and overlap: they would flicker.
    Bottom faces resting on the ground (facing down at z = 0) are never seen and are skipped."""
    faces = []
    for ob in objects:
        for p in ob.data.polygons:
            n = p.normal.copy()
            pts = [ob.data.vertices[i].co.copy() for i in p.vertices]
            if n.z < -0.999 and abs(pts[0].z) < 1e-4:
                continue
            u = (Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))).cross(n).normalized()
            v = n.cross(u)
            flat = [(q.dot(u), q.dot(v)) for q in pts]
            xs, ys = [f[0] for f in flat], [f[1] for f in flat]
            faces.append((ob.name, p.index, n, n.dot(pts[0]), flat, (min(xs), max(xs), min(ys), max(ys)), p.center.copy()))
    hits = []
    faces.sort(key=lambda f: f[3])   # by plane offset: only faces within eps of each other can fight
    for i in range(len(faces)):
        oa, ia, na, da, fa, ba, ca = faces[i]
        for j in range(i + 1, len(faces)):
            ob, ib, nb, db, fb, bb, cb = faces[j]
            if db - da > eps:
                break
            if na.dot(nb) < 0.999 or abs(na.dot(cb - ca)) > eps:   # same way, and really on the same plane here
                continue
            if min(ba[1], bb[1]) - max(ba[0], bb[0]) <= 1e-3 or min(ba[3], bb[3]) - max(ba[2], bb[2]) <= 1e-3:
                continue
            if _clip_area(fa, fb) > 1e-6:
                hits.append("%s face %d at %s / %s face %d" % (oa, ia, tuple(round(c, 3) for c in ca), ob, ib))
    return hits


def stadium(length, width, segs=12):
    """Rounded-end outline in XY, long along Y, counter-clockwise from +Z."""
    r = width / 2
    half = length / 2 - r
    pts = []
    for i in range(segs + 1):   # front end (+Y)
        a = math.pi * i / segs
        pts.append((r * math.cos(a), half + r * math.sin(a)))
    for i in range(segs + 1):   # back end (-Y)
        a = math.pi + math.pi * i / segs
        pts.append((r * math.cos(a), -half + r * math.sin(a)))
    return pts


# ------------------------------------------------------------------ models

def parking_block():
    """Precast concrete wheel stop, 6' x 7" x 5" (1.83 x 0.178 x 0.127 m, Kuhlman 8085508). Long along X."""
    m = Model("parking_block")
    b = m.obj("Block", "concrete")
    # Trapezoid section with chamfered top corners (front is +Y).
    prof = [(-0.089, 0.0), (0.089, 0.0), (0.089, 0.07), (0.06, 0.127), (-0.06, 0.127), (-0.089, 0.07)]
    m.prism(b, prof, -0.915, 0.915)
    p = m.obj("Pins", "dark_metal")
    for x in (-0.6, 0.6):   # rebar pins, domed tops proud of the block
        m.cyl(p, 0.016, 0.006, (x, 0, 0.125), segs=10)
    s = m.obj("Reflectors", "bollard_yellow")
    for x in (-0.75, 0.75):   # yellow reflective tape on the face toward the car
        a = math.atan2(0.029, 0.057)   # chamfer slope
        m.box(s, (0.14, 0.004, 0.035), (x, -0.0765, 0.0995), rot=Matrix.Rotation(-a, 3, "X"))
        m.box(s, (0.14, 0.004, 0.035), (x, 0.0765, 0.0995), rot=Matrix.Rotation(a, 3, "X"))
    return m.build()


def cart_corral():
    """Single-wide cart return corral, sized from the R.W. Rogers CC8030370 spec (Zoro / Webstaurant):
    side rails 13'8" (4.17 m) long and 36" (0.91 m) tall, 32" (0.81 m) clear between rails, sign
    poles 8' (2.44 m). Open end at the front (+Y) with a short flared mouth."""
    m = Model("cart_corral")
    w, r = 0.43, 0.024           # rail centre lines; 0.406 m clear each side of centre + tube radius
    yf, yb = 2.085, -2.085       # mouth and back posts (4.17 m side rails)
    top, fl = 0.914, 0.25        # top rail height, flare reach
    f = m.obj("Frame", "rail_metal")
    ys = (yf, 0.0, yb)
    for y in ys:
        for x in (-w, w):
            m.cyl(f, 0.03, top + 0.03, (x, y, 0.012), segs=12)
            m.ball(f, 0.032, (x, y, top + 0.042), segs=10, rings=6)   # post caps
    for z in (0.25, 0.58, top):
        for x in (-w, w):
            m.tube(f, (x, yf, z), (x, yb, z), r)
        m.tube(f, (-w, yb, z), (w, yb, z), r * 0.92)
    for x in (-1, 1):   # flared mouth so carts funnel in
        for z in (0.58, top):
            m.tube(f, (x * w, yf, z), (x * (w + fl), yf + fl, z), r * 0.9)
        m.cyl(f, 0.026, top - 0.03, (x * (w + fl), yf + fl, 0.012), segs=10)
    for x in (-w, w):   # 8 ft sign poles on the back posts
        m.tube(f, (x, yb, top), (x, yb, 2.44), r)
    pl = m.obj("BasePlates", "dark_metal")
    for y in ys:
        for x in (-w, w):
            m.box(pl, (0.14, 0.14, 0.012), (x, y, 0.006))
            for dx in (-0.045, 0.045):
                m.cyl(pl, 0.009, 0.012, (x + dx, y + 0.045, 0.012), segs=6)
                m.cyl(pl, 0.009, 0.012, (x + dx, y - 0.045, 0.012), segs=6)
    for x in (-1, 1):
        m.box(pl, (0.12, 0.12, 0.012), (x * (w + fl), yf + fl, 0.006))
    s = m.obj("SignPanel", "sign_panel")
    m.box(s, (0.8, 0.03, 0.5), (0, yb, 2.15))
    bump = m.obj("Bumpers", "rubber_black")   # rubber guards on the low rail where carts hit
    for x in (-w, w):
        m.cyl(bump, 0.034, 1.6, (x, yf - 0.3, 0.25), axis="Y", segs=10, rot=Matrix.Rotation(math.pi, 3, "X"))
    return m.build()


def streetlight(m=None):
    """Parking lot pole: 1 m concrete pier, 8.4 m steel pole, two LED shoebox heads at 9.4 m along X."""
    own = m is None
    m = Model("streetlight") if own else m
    c = m.obj("Base", "concrete")
    m.cyl(c, 0.36, 0.95, (0, 0, 0), segs=24, r_top=0.33)
    m.cyl(c, 0.33, 0.05, (0, 0, 0.95), segs=24, r_top=0.29)   # chamfered top
    p = m.obj("Pole", "pole_metal")
    m.cyl(p, 0.11, 8.3, (0, 0, 1.025), segs=16, r_top=0.07)
    m.cyl(p, 0.075, 0.12, (0, 0, 9.325), segs=16)               # tenon
    m.box(p, (2.0, 0.08, 0.08), (0, 0, 9.4))                     # cross arm
    m.ball(p, 0.08, (0, 0, 9.445), segs=12, rings=6)             # top cap
    h = m.obj("Hardware", "dark_metal")
    m.box(h, (0.36, 0.36, 0.025), (0, 0, 1.0125))                # base plate
    for x in (-0.13, 0.13):
        for y in (-0.13, 0.13):
            m.cyl(h, 0.018, 0.075, (x, y, 1.02), segs=8)         # anchor bolts
            m.cyl(h, 0.028, 0.025, (x, y, 1.025), segs=6)        # nuts
    m.box(h, (0.09, 0.02, 0.2), (0, 0.105, 1.55), rot=Matrix.Rotation(math.radians(-0.3), 3, "X"))  # handhole cover
    for x in (-1.0, 1.0):
        m.box(h, (0.7, 0.42, 0.1), (x, 0, 9.4))                  # housing
        m.box(h, (0.6, 0.36, 0.03), (x, 0, 9.465))               # top fins
        m.box(h, (0.12, 0.1, 0.06), (x * 0.66 if x > 0 else -0.66, 0, 9.4))  # arm adapter
    lens = m.obj("Lens", "led_lens")
    for x in (-1.0, 1.0):
        m.box(lens, (0.6, 0.34, 0.012), (x, 0, 9.344))
    return m.build() if own else 0


def palm_tree(m=None):
    """Washingtonia-style palm, 7.6 m tall, slight lean toward +X."""
    own = m is None
    m = Model("palm_tree") if own else m
    rnd = random.Random(3)
    t = m.obj("Trunk", "palm_trunk")
    segs, H = 14, 7.0
    prev = Vector((0, 0, 0))
    for i in range(segs):
        z1 = H * (i + 1) / segs
        lean = 0.35 * (z1 / H) ** 2
        top = Vector((lean, 0, z1))
        r0 = 0.24 - 0.09 * i / segs
        r1 = 0.24 - 0.09 * (i + 1) / segs
        m.cyl(t, r0, (top - prev).length, prev, axis=top - prev, segs=10, r_top=r1 * 0.94)
        m.cyl(t, r1 * 1.06, 0.04, top - (top - prev).normalized() * 0.05, axis=top - prev, segs=10, r_top=r1 * 1.01)
        prev = top
    crown = prev
    m.ball(t, 0.3, crown + Vector((0, 0, 0.1)), scale=(1, 1, 1.4), segs=10, rings=6)   # boot
    fr = m.obj("Fronds", "palm_frond")
    dead = m.obj("DeadFronds", "palm_frond_dead")
    for i in range(14):
        a = 2 * math.pi * i / 14 + rnd.uniform(-0.15, 0.15)
        rise = rnd.uniform(0.15, 0.6)
        length = rnd.uniform(2.3, 2.9)
        d = Vector((math.cos(a), math.sin(a), 0))
        pts, widths = [], []
        for k in range(7):
            s = k / 6
            pts.append(crown + Vector((0, 0, 0.35)) + d * length * s + Vector((0, 0, rise * s - 1.6 * s * s)))
            widths.append(0.08 + 0.9 * math.sin(math.pi * min(1, s * 1.1)) ** 0.8 if k < 6 else 0.02)
        m.strip(fr, pts, widths, fold=math.radians(25))
    for i in range(4):   # old fronds hanging down the trunk
        a = 2 * math.pi * i / 4 + 0.4
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [crown + d * 0.2 + Vector((0, 0, 0.1)), crown + d * 0.55 + Vector((0, 0, -0.5)),
               crown + d * 0.62 + Vector((0, 0, -1.2)), crown + d * 0.6 + Vector((0, 0, -1.7))]
        m.strip(dead, pts, [0.1, 0.45, 0.4, 0.1], fold=math.radians(30))
    return m.build() if own else 0


def planter_island(m=None):
    """Curbed landscape island, 11 m long (along Y) and 2.4 m wide, with mulch and shrubs.
    The streetlight and palms are separate scenes placed on it."""
    own = m is None
    m = Model("planter_island") if own else m
    outer = stadium(11.0, 2.4)
    inner = stadium(11.0 - 0.3, 2.4 - 0.3)
    c = m.obj("Curb", "curb_concrete")
    m.ring_prism(c, outer, inner, 0.0, 0.15)
    mu = m.obj("Mulch", "mulch")
    m.prism(mu, inner, 0.0, 0.12, plane="XY")
    s = m.obj("Shrubs", "shrub")
    rnd = random.Random(7)
    spots = [(-0.5, -4.4), (0.45, -3.2), (-0.35, -1.7), (0.55, -0.6), (-0.55, 0.9), (0.5, 1.8),
             (-0.45, 3.1), (0.35, 4.5), (0.1, -4.9), (-0.1, 4.95)]
    for i, (x, y) in enumerate(spots):
        r = rnd.uniform(0.28, 0.4)
        m.ball(s, r, (x, y, 0.12 + r * 0.55), scale=(1, 1, 0.75), segs=9, rings=6, jitter=0.12, seed=i)
    return m.build() if own else 0


def parked_car():
    """Mid-size sedan, 4.6 m long, 1.8 m wide, 1.45 m tall. Nose to the front (+Y).
    Paint objects (Body, Cabin, Mirrors) are recoloured per car in Godot."""
    m = Model("parked_car")
    hw = 0.88   # half width of the body
    body = m.obj("Body", "car_paint")
    prof = [(-2.3, 0.33), (-1.86, 0.33), (-1.78, 0.6), (-1.4, 0.72), (-1.02, 0.6), (-0.94, 0.33),
            (0.94, 0.33), (1.02, 0.6), (1.4, 0.72), (1.78, 0.6), (1.86, 0.33), (2.3, 0.33),
            (2.34, 0.55), (2.27, 0.8), (1.15, 0.92), (-1.65, 0.94), (-2.27, 0.88), (-2.34, 0.6)]
    m.prism(body, prof, -hw, hw)
    cab = [(1.15, 0.92), (0.2, 1.43), (-1.05, 1.44), (-1.68, 0.94)]
    cabin = m.obj("Cabin", "car_paint")
    m.prism(cabin, cab, -0.76, 0.76)
    glass = m.obj("Windows", "car_glass")
    # side windows: an inset cabin outline, 1 cm proud of each cabin side
    side = [(0.95, 0.99), (0.22, 1.37), (-1.0, 1.38), (-1.48, 0.99)]
    for x0, x1 in ((0.76, 0.77), (-0.77, -0.76)):
        m.prism(glass, side, x0, x1)
    for (a, b) in (((1.15, 0.92), (0.2, 1.43)), ((-1.05, 1.44), (-1.68, 0.94))):   # windshield, rear window
        a, b = Vector((0, *a)), Vector((0, *b))
        t = (b - a).normalized()
        n = Vector((0, t.z, -t.y)) if a.y > 0 else Vector((0, -t.z, t.y))
        p0, p1 = a + t * 0.06 + n * 0.006, b - t * 0.06 + n * 0.006
        q0, q1 = p0 + n * 0.01, p1 + n * 0.01
        m.prism(glass, [(p0.y, p0.z), (q0.y, q0.z), (q1.y, q1.z), (p1.y, p1.z)] if a.y > 0 else
                [(p0.y, p0.z), (p1.y, p1.z), (q1.y, q1.z), (q0.y, q0.z)], -0.66, 0.66)
    tires = m.obj("Tires", "tire")
    rims = m.obj("Rims", "rail_metal")
    for y in (-1.4, 1.4):
        for x in (-1, 1):
            m.cyl(tires, 0.33, 0.22, (x * 0.68, y, 0.33), axis=Vector((x, 0, 0)), segs=20)
            m.cyl(rims, 0.21, 0.012, (x * 0.9, y, 0.33), axis=Vector((x, 0, 0)), segs=16)
            m.cyl(rims, 0.06, 0.02, (x * 0.912, y, 0.33), axis=Vector((x, 0, 0)), segs=10)
    trim = m.obj("Trim", "rubber_black")
    for y, d in ((2.33, 1), (-2.33, -1)):   # bumpers
        m.box(trim, (1.78, 0.12, 0.16), (0, y, 0.42))
    m.box(trim, (0.9, 0.03, 0.14), (0, 2.31, 0.66), rot=Matrix.Rotation(math.radians(-15), 3, "X"))   # grille
    for x in (-1, 1):
        m.box(trim, (0.012, 1.8, 0.05), (x * (hw + 0.006), 0.0, 0.52))   # side rub strips
        for y in (0.45, -0.75):
            m.box(trim, (0.02, 0.14, 0.03), (x * (hw + 0.01), y, 0.86))   # door handles
    mir = m.obj("Mirrors", "car_paint")
    for x in (-1, 1):
        m.box(mir, (0.16, 0.08, 0.1), (x * 0.9, 0.98, 1.0))
    hl = m.obj("Headlights", "headlight")
    for x in (-0.62, 0.62):
        m.box(hl, (0.36, 0.05, 0.11), (x, 2.29, 0.7), rot=Matrix.Rotation(math.radians(-18), 3, "X"))
    tl = m.obj("Taillights", "taillight")
    for x in (-0.64, 0.64):
        m.box(tl, (0.34, 0.04, 0.12), (x, -2.32, 0.76), rot=Matrix.Rotation(math.radians(12), 3, "X"))
    pl = m.obj("Plates", "paint_white")
    m.box(pl, (0.3, 0.012, 0.15), (0, 2.395, 0.42))
    m.box(pl, (0.3, 0.012, 0.15), (0, -2.395, 0.42))
    return m.build()


def stall_markings(m=None, count=8):
    """Paint for one row of `count` stalls (8 for the parking lot level), 2.7 m wide and 5.5 m deep, with
    hairpin dividers.
    Origin: bottom center of the row's open (aisle) edge; stalls run toward -Y (Godot +Z) from there."""
    own = m is None
    m = Model("stall_markings") if own else m
    p = m.obj("Paint", "paint_white")
    t = 0.002
    for k in range(count + 1):
        x = -1.35 * count + 2.7 * k
        for dx in (-0.15, 0.15):   # hairpin: two lines joined at the aisle end
            m.box(p, (0.1, 5.4, t), (x + dx, -2.8, t / 2))
        m.box(p, (0.4, 0.1, t), (x, -0.05, t / 2))
    return m.build() if own else 0


# The sandbox's open-lot chunk (scenes/sandbox/chunks/open_lot.tscn), in Godot metres, centred on the chunk.
OPEN_LOT_SIZE = 40.0                 # every sandbox chunk is 40 x 40 m (scripts/sandbox/chunk_streamer.gd)
OPEN_LOT_ROW_CENTERS = (-10.0, 10.0) # Z of each double row's centre line (the stall heads meet there)
OPEN_LOT_STALLS = 11                 # stalls per row: 11 x 2.7 m = 29.7 m
OPEN_LOT_ROW_X = -4.85               # X of the middle of each row (from x = -19.7 to 10.0)
OPEN_LOT_ISLAND_X = 11.5             # planter island at the +X end of each double row
OPEN_LOT_POLE_X = -6.2               # streetlight on the stall heads, on the 6th divider


def open_lot():
    """One 40 x 40 m chunk of the sandbox's endless parking lot, laid out from the aerial reference photos
    (Level Reference Images/): two double rows of 11 stalls (2.7 x 5.5 m) along X with a 9 m drive aisle down
    the middle (z = 0) and half an aisle along each Z edge, so neighbouring chunks meet in a full aisle; each
    double row ends at +X in a planter island (streetlight, two palms) and a 7.3 m cross aisle runs from there to
    the +X edge. A second streetlight stands on the stall heads of each double row. Nothing but 2 mm paint comes
    within 0.3 m of an edge, so it meets any chunk flush.
    The parts are the lot props themselves (stall markings, planter island, streetlight, palm tree), merged into
    one object per material so a chunk draws in about ten calls, plus the 40 x 40 m asphalt face at y = 0.
    Origin: chunk centre on the ground (Godot coordinates in the comments; z = -Blender y)."""
    m = Model("open_lot", by_material=True)
    h = OPEN_LOT_SIZE / 2
    m.at(0, 0)
    a = m.obj("Asphalt", "asphalt")
    m._add(a, [(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [(0, 1, 2, 3)])
    for zc in OPEN_LOT_ROW_CENTERS:
        m.at(OPEN_LOT_ROW_X, zc - 5.5)          # row facing the aisle on its -Z side (stalls run toward +Z)
        stall_markings(m, OPEN_LOT_STALLS)
        m.at(OPEN_LOT_ROW_X, zc + 5.5, 180)     # row facing the aisle on its +Z side
        stall_markings(m, OPEN_LOT_STALLS)
        m.at(OPEN_LOT_ISLAND_X, zc)
        planter_island(m)
        m.at(OPEN_LOT_ISLAND_X, zc, 90)          # as placed in scenes/props/parking_lot/planter_island.tscn
        streetlight(m)
        m.at(OPEN_LOT_ISLAND_X, zc - 3.8, 20)
        palm_tree(m)
        m.at(OPEN_LOT_ISLAND_X, zc + 3.8, 200)
        palm_tree(m)
        m.at(OPEN_LOT_POLE_X, zc, 90)
        streetlight(m)
    m.at(0, 0)
    return m.build()


COLUMNS = (-26.25, -18.75, -11.25, -3.75, 3.75, 11.25, 18.75, 26.25)   # store front column centres
PERGOLA_BAYS = ((-18.75, -11.25), (-11.25, -3.75))                    # stepped pergola over these bays


def store_front():
    """Supermarket front, 60 m wide, after zack's photo: a 4 m deep covered walkway behind square
    stucco columns, a sign band with green panels and two lightbox signs, a stepped, uplit pergola
    over those two bays and red tile mansard roof over the rest, entry doors and shop windows on the
    back wall. Origin: bottom centre of the column face line, which faces -Y (Godot +Z, the lot);
    the building runs 16 m back. Sign text, lights, water machines and cart rows are added in Godot."""
    m = Model("store_front")
    D = 4.0          # walkway depth (column face to shop wall)
    BAND = (3.6, 5.6)
    st = m.obj("Stucco", "facade")
    m.box(st, (60, 12, 7.0), (0, D + 6, 3.5))                       # the store behind the walkway
    for x in (-29.5, 29.5):
        m.box(st, (1.0, D, BAND[0]), (x, D / 2, BAND[0] / 2))        # walkway end walls
    for x in COLUMNS:
        m.box(st, (0.9, 0.9, BAND[0] - 0.01), (x, 0.45, BAND[0] / 2 - 0.005))   # column shafts
    m.box(st, (60, 1.2, BAND[1] - BAND[0]), (0, 0.55, (BAND[0] + BAND[1]) / 2))   # sign band (front y -0.05)
    for x in COLUMNS:
        m.box(st, (0.9, 0.3, BAND[1] - BAND[0] - 0.01), (x, 0.0, (BAND[0] + BAND[1]) / 2))  # pilasters, front y -0.15
    # stepped pergola: a pier over each bay's left column, a sloping fin down to the next column,
    # and horizontal slats stepping down under the fin
    top = 8.6
    ang = math.atan2(top - BAND[1], 7.5)
    for xa, xb in PERGOLA_BAYS:
        m.box(st, (0.9, 1.3, top - BAND[1] - 0.02), (xa, 0.5, (top + BAND[1]) / 2 + 0.01))   # pier
        mid = Vector(((xa + xb) / 2, 0.5, (top + BAND[1]) / 2 + 0.05))
        m.box(st, (math.hypot(7.5, top - BAND[1]) + 0.2, 1.24, 0.5), mid, rot=Matrix.Rotation(ang, 3, "Y"))
        m.box(st, (7.5, 0.25, 2.4), ((xa + xb) / 2, 3.2, BAND[1] + 1.2))           # back panel the slats light up
        for k in range(4):
            z = BAND[1] + 0.45 + 0.62 * k
            x_end = xa + (top - z - 0.3) / (top - BAND[1]) * 7.5
            m.box(st, (x_end - xa - 0.5, 0.45, 0.3), ((xa + 0.45 + x_end) / 2 - 0.05, 1.4 + 0.3 * k, z))
    tr = m.obj("Trim", "facade_trim")
    for x in COLUMNS:
        m.box(tr, (1.15, 1.15, 0.45), (x, 0.45, 0.225))             # column bases
        m.box(tr, (1.04, 1.04, 0.18), (x, 0.45, BAND[0] - 0.09))    # capitals
    m.box(tr, (60.2, 1.44, 0.16), (0, 0.55, BAND[1] + 0.08))        # band cap
    so = m.obj("Soffit", "soffit")
    m.box(so, (58.0, D - 0.06, 0.15), (0, D / 2 + 0.03, BAND[0] - 0.08))
    fl = m.obj("WalkwayFloor", "sidewalk")
    m.box(fl, (58.0, D - 0.02, 0.15), (0, D / 2 + 0.01, 0.075))
    co = m.obj("Coping", "concrete")
    for xa, xb in PERGOLA_BAYS:   # tile-edged coping on the fins and piers
        mid = Vector(((xa + xb) / 2, 0.5, (top + BAND[1]) / 2 + 0.05))
        n = Vector((math.sin(ang), 0, math.cos(ang)))
        m.box(co, (math.hypot(7.5, top - BAND[1]) + 0.2, 1.36, 0.1), mid + n * 0.3, rot=Matrix.Rotation(ang, 3, "Y"))
        m.box(co, (1.0, 1.4, 0.12), (xa, 0.5, top + 0.06))
    rf = m.obj("RoofTiles", "roof_tile")
    slope = math.atan2(8.2 - BAND[1] - 0.16, 3.2)
    for x0, x1 in ((-30.0, PERGOLA_BAYS[0][0] - 0.45), (PERGOLA_BAYS[-1][1] + 0.45, 30.0)):
        z0 = BAND[1] + 0.16
        m.prism(rf, [(-0.1, z0), (3.1, z0), (3.1, 8.2)], x0, x1)       # mansard, sloping up toward the back
        for k in range(1, 10):   # tile courses
            t = k / 10
            y, z = -0.1 + 3.2 * t, z0 + (8.2 - z0) * t
            m.box(rf, (x1 - x0, 0.06, 0.05), ((x0 + x1) / 2, y - 0.03 * math.sin(slope) - 0.02, z + 0.03),
                  rot=Matrix.Rotation(slope, 3, "X"))
    m.box(rf, (60.0, 1.0, 0.15), (0, 3.6, 8.275))                      # ridge cap along the back
    gl = m.obj("Glass", "store_glass")
    door = (-0.8, 2.4)
    m.box(gl, (door[1] - door[0], 0.03, 2.4), ((door[0] + door[1]) / 2, D - 0.015, 0.15 + 1.2))   # sliding doors
    m.box(gl, (door[1] - door[0], 0.03, 0.75), ((door[0] + door[1]) / 2, D - 0.015, 2.65 + 0.375))  # transom
    windows = ((5.0, 10.0), (12.5, 17.5), (20.0, 25.0))
    for x0, x1 in windows:
        m.box(gl, (x1 - x0, 0.03, 1.3), ((x0 + x1) / 2, D - 0.015, 2.35))
    fr = m.obj("Frames", "dark_metal")
    fy = D - 0.065
    for x in (door[0], (door[0] + door[1]) / 2, door[1]):
        m.box(fr, (0.1, 0.07, 3.25), (x, fy, 0.15 + 1.625))
    for z in (0.18, 2.6, 3.4):
        m.box(fr, (door[1] - door[0] + 0.08, 0.05, 0.08), ((door[0] + door[1]) / 2, fy, z))
    for x0, x1 in windows:
        for x in (x0, (2 * x0 + x1) / 3, (x0 + 2 * x1) / 3, x1):
            m.box(fr, (0.08, 0.07, 1.4), (x, fy, 2.35))
        for z in (1.68, 3.02):
            m.box(fr, (x1 - x0 + 0.06, 0.05, 0.07), ((x0 + x1) / 2, fy, z))
    for x in (-29.0 + 0.1, 29.0 - 0.1):
        m.cyl(fr, 0.06, BAND[0] - 0.15, (x, D - 0.08, 0.15), segs=8)    # downspouts in the walkway corners
    po = m.obj("Notices", "paint_white")
    for x, z, w, h in ((-5.2, 1.6, 0.35, 0.5), (-5.2, 1.0, 0.35, 0.3), (4.4, 1.5, 0.25, 0.3)):
        m.box(po, (w, 0.01, h), (x, D - 0.005, z))
    gr = m.obj("SignBands", "sign_green")
    for xa, xb in PERGOLA_BAYS:
        m.box(gr, (xb - xa - 0.9 - 0.1, 0.04, 1.6), ((xa + xb) / 2, -0.07, (BAND[0] + BAND[1]) / 2))
    bx = m.obj("SignBoxes", "dark_metal")
    lf = m.obj("SignFaces", "lightbox_face")
    for xa, xb in PERGOLA_BAYS:
        cx = (xa + xb) / 2
        m.box(bx, (4.2, 0.22, 0.95), (cx, -0.2, 4.6))
        m.box(lf, (4.0, 0.02, 0.8), (cx, -0.32, 4.6))
    dl = m.obj("Downlights", "led_lens")
    for c in range(len(COLUMNS) - 1):
        for f in (0.3, 0.7):
            x = COLUMNS[c] + (COLUMNS[c + 1] - COLUMNS[c]) * f
            m.cyl(dl, 0.09, 0.012, (x, D / 2, BAND[0] - 0.155 - 0.012), segs=12)
    return m.build()


def cart_row(count=12, pitch=0.32):
    """A row of nested shopping carts as left along the store wall: 12 carts, 4.5 m long, 1.0 m tall,
    0.62 m wide. Noses toward -X; each cart sits 0.32 m further along +X and 6 mm higher (nested
    carts ride up on the one in front). Origin: bottom centre under the first cart's nose."""
    m = Model("cart_row")
    wire = m.obj("Wire", "rail_metal")
    grip = m.obj("Handles", "rubber_black")
    wheels = m.obj("Casters", "tire")
    for i in range(count):
        ox, oz = i * pitch, i * 0.006
        def P(x, y, z):
            return (ox + x, y, oz + z)
        top = [(0.05, 0.25), (0.88, 0.31)]
        bot = [(0.12, 0.22), (0.85, 0.28)]
        for sy in (-1, 1):
            m.tube(wire, P(top[0][0], sy * top[0][1], 0.92), P(top[1][0], sy * top[1][1], 0.92), 0.008, segs=6)
            m.tube(wire, P(bot[0][0], sy * bot[0][1], 0.45), P(bot[1][0], sy * bot[1][1], 0.45), 0.006, segs=6)
            for k in range(6):   # side wires
                t = k / 5
                xt = top[0][0] + (top[1][0] - top[0][0]) * t
                yt = top[0][1] + (top[1][1] - top[0][1]) * t
                xb = bot[0][0] + (bot[1][0] - bot[0][0]) * t
                yb = bot[0][1] + (bot[1][1] - bot[0][1]) * t
                m.tube(wire, P(xb, sy * yb, 0.45), P(xt, sy * yt, 0.92), 0.004, segs=5)
            m.tube(wire, P(0.05, sy * 0.2, 0.14), P(0.9, sy * 0.28, 0.14), 0.011, segs=6)      # chassis rails
            m.tube(wire, P(0.12, sy * 0.22, 0.45), P(0.07, sy * 0.2, 0.14), 0.01, segs=6)      # front legs
            m.tube(wire, P(0.85, sy * 0.28, 0.45), P(0.9, sy * 0.28, 0.14), 0.011, segs=6)     # back legs
            m.tube(wire, P(0.88, sy * 0.31, 0.92), P(0.97, sy * 0.3, 1.0), 0.011, segs=6)      # handle arms
            for x, y in ((0.07, 0.2), (0.9, 0.28)):
                m.cyl(wheels, 0.055, 0.03, P(x, sy * y - 0.015, 0.06), axis="Y", segs=10)
                m.box(wire, (0.03, 0.04, 0.05), P(x, sy * y, 0.1))
        for z, y0, y1, x in ((0.92, 0.25, 0.25, 0.05), (0.45, 0.22, 0.22, 0.12)):
            m.tube(wire, P(x, -y0, z), P(x, y1, z), 0.007, segs=6)                              # nose rims
        for k in range(5):   # floor wires and bottom tray
            y = -0.2 + 0.1 * k
            m.tube(wire, P(0.13, y, 0.452), P(0.84, y * 1.25, 0.452), 0.004, segs=5)
            m.tube(wire, P(0.1, y, 0.2), P(0.86, y * 1.25, 0.2), 0.004, segs=5)
        for k in range(5):   # back gate
            y = -0.24 + 0.12 * k
            m.tube(wire, P(0.86, y, 0.47), P(0.875, y * 1.1, 0.9), 0.004, segs=5)
        m.tube(grip, P(0.97, -0.31, 1.0), P(0.97, 0.31, 1.0), 0.017, segs=8)
    return m.build()


def water_machine():
    """Self-serve water refill machine, 0.8 x 0.75 x 2.05 m, front (+Y, Godot -Z) with window and nook."""
    m = Model("water_machine")
    b = m.obj("Cabinet", "water_blue")
    m.box(b, (0.8, 0.75, 1.95), (0, 0, 0.05 + 0.975))
    m.box(b, (0.74, 0.69, 0.05), (0, 0, 2.025))
    p = m.obj("FrontPanel", "water_panel")
    m.box(p, (0.68, 0.02, 1.7), (0, 0.385, 1.05))
    d = m.obj("Dark", "dark_metal")
    m.box(d, (0.8, 0.75, 0.05), (0, 0, 0.025))                    # plinth
    m.box(d, (0.42, 0.02, 0.4), (0, 0.405, 0.85))                 # bottle nook
    m.box(d, (0.08, 0.03, 0.06), (0.12, 0.42, 1.0))               # tap
    g = m.obj("Window", "car_glass")
    m.box(g, (0.5, 0.02, 0.42), (0, 0.405, 1.45))
    k = m.obj("Keypad", "rail_metal")
    m.box(k, (0.12, 0.02, 0.16), (0.24, 0.405, 1.15))
    return m.build()


def lot_surface():
    """Asphalt, sidewalk with a curb cut, perimeter curb and bollards, in level coordinates
    (origin = level origin; Godot z = -Blender y)."""
    m = Model("lot_surface")
    a = m.obj("Asphalt", "asphalt")
    m.box(a, (64, 62, 0.3), (0, -3, -0.15))
    w = m.obj("Sidewalk", "sidewalk")
    m.box(w, (28.5, 3, 0.15), (-15.75, 14.5, 0.075))
    m.box(w, (28.5, 3, 0.15), (15.75, 14.5, 0.075))
    m.box(w, (3, 2, 0.15), (0, 15, 0.075))
    ang = math.atan(0.15 / 1.0)
    m.box(w, (2.98, 1.15, 0.1), (0, 13.5 + 0.05 * math.sin(ang), 0.075 - 0.05 * math.cos(ang)),
          rot=Matrix.Rotation(-ang, 3, "X"))
    rp = m.obj("CurbPaint", "curb_red")   # red-painted curb edge along the fire lane, as in the photo
    for x0, x1 in ((-30.0, -1.5), (1.5, 30.0)):
        m.box(rp, (x1 - x0, 0.2, 0.002), ((x0 + x1) / 2, 13.1, 0.151))
        m.box(rp, (x1 - x0, 0.002, 0.152), ((x0 + x1) / 2, 12.999, 0.076))
    c = m.obj("Curbs", "curb_concrete")
    m.box(c, (0.3, 43, 0.15), (-30.15, -8.5, 0.075))
    m.box(c, (0.3, 43, 0.15), (30.15, -8.5, 0.075))
    m.box(c, (60.6, 0.3, 0.15), (0, -30.15, 0.075))
    b = m.obj("Bollards", "bollard_yellow")
    for x in (-2.0, 2.0):
        m.cyl(b, 0.11, 0.9, (x, 13.4, 0.13), segs=14)
        m.ball(b, 0.11, (x, 13.4, 1.03), scale=(1, 1, 0.5), segs=14, rings=6)
    return m.build()


def link_materials(names=None):
    """Point each .glb's materials at the shared Godot .tres of the same name, in its .import file
    (the editor's Advanced Import Settings > Materials > Use External). Run after `godot --import`."""
    import json
    import re
    import struct
    for name in names or MODELS:
        glb = os.path.join(OUT, name, name + ".glb")
        imp = glb + ".import"
        if not os.path.exists(imp):
            print("no .import yet for", name, "- run godot --headless --import first")
            continue
        data = open(glb, "rb").read()
        length = struct.unpack_from("<I", data, 12)[0]
        mats = [m["name"] for m in json.loads(data[20:20 + length]).get("materials", [])]
        entries = ",\n".join(
            '"%s": {\n"use_external/enabled": true,\n"use_external/path": "res://assets/parking_lot/materials/%s.tres"\n}'
            % (m, m) for m in mats)
        sub = '_subresources={\n"materials": {\n%s\n}\n}' % entries
        text = open(imp).read()
        text = re.sub(r"_subresources=\{.*?\n\}\n(?=\S)|_subresources=\{\}\n", sub + "\n", text, count=1, flags=re.S)
        open(imp, "w").write(text)
        print("LINKED", name, ", ".join(mats))


MODELS = {f.__name__: f for f in (parking_block, cart_corral, streetlight, palm_tree, planter_island,
                                   parked_car, stall_markings, store_front, water_machine, cart_row, lot_surface,
                                   open_lot)}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if args[:1] == ["--link-materials"]:
        link_materials(args[1:])
        sys.exit(0)
    names = args or list(MODELS)
    fights = 0
    for n in names:
        fights += MODELS[n]()
    print("DONE, z-fighting hits:", fights)

