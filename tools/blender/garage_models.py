"""Builds the parking garage props from Blender primitives and exports them as .glb.

Run headless from the repo root (all models, or just the ones named):
    blender -b -P tools/blender/garage_models.py -- [parked_car pillar garage_light lamp_post exit_sign floor_arrow]
(or with the `bpy` Python module: python tools/blender/garage_models.py -- ...)

Writes shopping-cart/assets/models/garage/<name>/<name>.glb.
Conventions: meters; front faces Godot -Z (Blender +Y); origin at the bottom centre, except ceiling-hung props
(garage_light, exit_sign), whose origin is the top centre where they meet the ceiling. Each object has ONE
material, named after a shared Godot material in shopping-cart/assets/materials/garage/<name>.tres, which the
prop scenes put on by name. Every build ends with a z-fighting scan (coplanar overlapping faces facing the
same way) and fails if it finds any.
"""
import math, os, sys
import bpy  # noqa: first, so the bpy module build can load bmesh
import bmesh
from mathutils import Matrix, Vector, geometry

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "shopping-cart", "assets", "models", "garage")


class Model:
    def __init__(self, name):
        self.name = name
        self.objs = {}
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def obj(self, name, material, bevel=0.0):
        self.objs[name] = {"bm": bmesh.new(), "mat": material, "bevel": bevel}
        return name

    def _add(self, o, geom_verts, m):
        bmesh.ops.transform(self.objs[o]["bm"], matrix=m, verts=geom_verts)

    def box(self, o, size, loc, rot=(0, 0, 0), top=None):
        """Box `size` (x, y, z) centred at `loc`. `top` = (sx, sy, dy): scale and shift of the top face (tapers)."""
        bm = self.objs[o]["bm"]
        r = bmesh.ops.create_cube(bm, size=1.0)
        vs = r["verts"]
        if top:
            for v in vs:
                if v.co.z > 0:
                    v.co.x *= top[0]
                    v.co.y = v.co.y * top[1] + top[2] / size[1]
        m = Matrix.Translation(loc) @ _rot(rot) @ Matrix.Diagonal((*size, 1))
        self._add(o, vs, m)

    def cyl(self, o, r, depth, loc, rot=(0, 0, 0), r_top=None, segs=24):
        bm = self.objs[o]["bm"]
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                                    radius2=r if r_top is None else r_top, depth=depth)
        self._add(o, res["verts"], Matrix.Translation(loc) @ _rot(rot))

    def prism(self, o, pts, z0, z1):
        """Extrude a flat polygon (x, y points, counter-clockwise) from z0 to z1."""
        bm = self.objs[o]["bm"]
        bot = [bm.verts.new((x, y, z0)) for x, y in pts]
        top = [bm.verts.new((x, y, z1)) for x, y in pts]
        bm.faces.new(list(reversed(bot)))
        bm.faces.new(top)
        n = len(pts)
        for i in range(n):
            bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))

    def build(self):
        made = []
        for name, d in self.objs.items():
            mesh = bpy.data.meshes.new(name)
            bmesh.ops.remove_doubles(d["bm"], verts=d["bm"].verts, dist=1e-6)
            d["bm"].normal_update()
            d["bm"].to_mesh(mesh)
            ob = bpy.data.objects.new(name, mesh)
            bpy.context.scene.collection.objects.link(ob)
            mat = bpy.data.materials.get(d["mat"]) or bpy.data.materials.new(d["mat"])
            mesh.materials.append(mat)
            if d["bevel"]:
                bv = ob.modifiers.new("Bevel", "BEVEL")
                bv.width = d["bevel"]
                bv.segments = 3
                bv.limit_method = "ANGLE"
            made.append(ob)
        hits = find_z_fighting(made)
        tris = sum(len(_tris(o)) for o in made)
        os.makedirs(os.path.join(OUT, self.name), exist_ok=True)
        path = os.path.join(OUT, self.name, self.name + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        for o in made:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_materials="EXPORT")
        print("BUILT %-13s %5d tris  %5.1f KB  z-fighting: %s" % (
            self.name, tris, os.path.getsize(path) / 1024, "none" if not hits else hits))
        return not hits


def _rot(r):
    return (Matrix.Rotation(r[2], 4, "Z") @ Matrix.Rotation(r[1], 4, "Y") @ Matrix.Rotation(r[0], 4, "X"))


def _tris(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    e = ob.evaluated_get(dg)
    me = e.to_mesh()
    me.calc_loop_triangles()
    out = []
    for t in me.loop_triangles:
        out.append([ob.matrix_world @ me.vertices[i].co.copy() for i in t.vertices])
    e.to_mesh_clear()
    return out


def find_z_fighting(objs, eps=1e-4):
    """Pairs of triangles on the same plane, facing the same way, that overlap: they'd flicker in Godot."""
    tris = []
    for o in objs:
        for t in _tris(o):
            n = (t[1] - t[0]).cross(t[2] - t[0])
            if n.length < 1e-9:
                continue
            tris.append((o.name, t, n.normalized()))
    hits = set()
    for i in range(len(tris)):
        a_name, a, an = tris[i]
        for j in range(i + 1, len(tris)):
            b_name, b, bn = tris[j]
            if an.dot(bn) < 0.9999 or abs((b[0] - a[0]).dot(an)) > eps:
                continue
            if any((p - q).length < 1e-6 for p in a for q in b) and a_name == b_name:
                continue   # neighbours in one surface
            ca = (a[0] + a[1] + a[2]) / 3
            cb = (b[0] + b[1] + b[2]) / 3
            if geometry.intersect_point_tri(cb, *a) or geometry.intersect_point_tri(ca, *b):
                hits.add((a_name, b_name))
    return sorted(hits)


# ------------------------------------------------------------------ models

def parked_car():
    """A mid-size hatchback, 4.4 x 1.78 x 1.38 m. Body (with roof and mirrors) is one object so each parked car
    can be repainted in Godot."""
    m = Model("parked_car")
    m.obj("Body", "car_paint", bevel=0.05)
    m.box("Body", (1.78, 4.4, 0.55), (0, 0, 0.575))                                   # lower body 0.30-0.85 m
    m.box("Body", (1.40, 1.66, 0.05), (0, -0.25, 1.355))                              # roof
    for x in (-0.98, 0.98):
        m.box("Body", (0.18, 0.10, 0.12), (x, 0.85, 0.95))                            # mirrors
    m.obj("Windows", "car_glass")
    m.box("Windows", (1.62, 2.4, 0.48), (0, -0.2, 1.09), top=(0.84, 0.69, -0.1))      # glasshouse, raked screens
    m.obj("Trim", "trim_black", bevel=0.02)
    for y in (2.22, -2.22):
        m.box("Trim", (1.84, 0.16, 0.24), (0, y, 0.42))                               # bumpers
    m.box("Trim", (1.0, 0.03, 0.16), (0, 2.215, 0.66))                                # grille
    for x in (-0.905, 0.905):
        m.box("Trim", (0.04, 2.0, 0.08), (x, 0, 0.34))                                # side skirts
    m.obj("Headlights", "headlight")
    m.obj("Taillights", "taillight")
    for x in (-0.6, 0.6):
        m.box("Headlights", (0.36, 0.04, 0.12), (x, 2.205, 0.72))
        m.box("Taillights", (0.36, 0.04, 0.12), (x, -2.205, 0.72))
    m.obj("Plates", "plate")
    for y in (2.31, -2.31):
        m.box("Plates", (0.5, 0.02, 0.12), (0, y, 0.42))
    m.obj("Tyres", "rubber")
    m.obj("Hubs", "chrome")
    for x in (-0.80, 0.80):
        for y in (1.4, -1.4):
            m.cyl("Tyres", 0.33, 0.22, (x, y, 0.33), rot=(0, math.pi / 2, 0), segs=28)
            m.cyl("Hubs", 0.20, 0.226, (x, y, 0.33), rot=(0, math.pi / 2, 0), segs=20)
    return m.build()


def pillar():
    """Round concrete pillar, one floor tall (2.9 m clear between 0.3 m slabs), flared top, painted foot."""
    m = Model("pillar")
    m.obj("Pillar", "concrete_pillar")
    m.cyl("Pillar", 0.25, 2.53, (0, 0, 0.02 + 2.53 / 2), segs=32)                      # shaft 0.02-2.55
    m.cyl("Pillar", 0.25, 0.35, (0, 0, 2.55 + 0.175), r_top=0.5, segs=32)             # capital to 2.9
    m.obj("Foot", "paint_yellow")
    m.cyl("Foot", 0.26, 0.7, (0, 0, 0.35), segs=32)
    return m.build()


def garage_light():
    """Twin-tube fluorescent fixture, 1.3 m long. Origin at the top centre (against the ceiling)."""
    m = Model("garage_light")
    m.obj("Housing", "dark_metal")
    m.box("Housing", (1.3, 0.24, 0.05), (0, 0, -0.025))
    m.obj("Tubes", "light_fixture")
    for y in (-0.05, 0.05):
        m.cyl("Tubes", 0.022, 1.2, (0, y, -0.06), rot=(0, math.pi / 2, 0), segs=12)
    return m.build()


def lamp_post():
    """Rooftop lamp post, 4.6 m. The arm and head reach toward the front (-Z in Godot)."""
    m = Model("lamp_post")
    m.obj("Post", "dark_metal")
    m.cyl("Post", 0.14, 0.25, (0, 0, 0.125), segs=20)                                 # base
    m.cyl("Post", 0.08, 4.25, (0, 0, 0.25 + 4.25 / 2), r_top=0.06, segs=16)           # pole to 4.5
    m.box("Post", (0.08, 1.0, 0.08), (0, 0.5, 4.45))                                  # arm
    m.box("Post", (0.28, 0.55, 0.1), (0, 0.95, 4.42), top=(0.8, 0.9, 0))              # head
    m.obj("Lens", "light_fixture")
    m.box("Lens", (0.22, 0.45, 0.02), (0, 0.95, 4.36))
    return m.build()


def exit_sign():
    """Hanging sign board 1.8 x 0.42 m on two rods. Origin at the top centre (ceiling). Text is added in Godot."""
    m = Model("exit_sign")
    m.obj("Board", "sign_navy", bevel=0.01)
    m.box("Board", (1.8, 0.06, 0.42), (0, 0, -0.61))
    m.obj("Rods", "dark_metal")
    for x in (-0.7, 0.7):
        m.box("Rods", (0.03, 0.03, 0.4), (x, 0, -0.2))
    return m.build()


def floor_arrow():
    """Painted direction arrow, 2.4 m long, 1 mm proud of the floor... drawn 1 cm thick, tip to the front."""
    m = Model("floor_arrow")
    m.obj("Arrow", "paint_yellow")
    m.prism("Arrow", [(-0.5, 0.45), (0.5, 0.45), (0.0, 1.25)], 0.0, 0.01)            # head
    m.box("Arrow", (0.35, 1.6, 0.01), (0, -0.35, 0.005))                              # shaft
    return m.build()


MODELS = {f.__name__: f for f in (parked_car, pillar, garage_light, lamp_post, exit_sign, floor_arrow)}

if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ok = all(MODELS[n]() for n in (names or MODELS))
    sys.exit(0 if ok else 1)
