"""Builds the parking garage props from Blender primitives and exports them as .glb.

Run headless from the repo root (all models, or just the ones named):
    blender -b -P tools/blender/garage_models.py -- [parked_car pillar garage_light lamp_post exit_sign floor_arrow
                                                     sprinkler_pipe oil_drum fire_cabinet]
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

    def obj(self, name, material, bevel=0.0, origin=(0, 0, 0)):
        """A new object with one material. `origin` is its pivot (e.g. a wheel's axle), in model coordinates."""
        self.objs[name] = {"bm": bmesh.new(), "mat": material, "bevel": bevel, "origin": Vector(origin)}
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
            bmesh.ops.translate(d["bm"], vec=-d["origin"], verts=d["bm"].verts)
            d["bm"].to_mesh(mesh)
            ob = bpy.data.objects.new(name, mesh)
            ob.location = d["origin"]
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
# Second pass (Nov 16): every prop is built at its finished detail, with separate objects and materials
# where the real thing has them.

def parked_car():
    """A mid-size hatchback, 4.4 x 1.78 x 1.38 m. Body (panels, roof, pillars, mirror shells) is one object so
    each car can be repainted in Godot. Each wheel is its own tyre + rim pair pivoting on its axle."""
    m = Model("parked_car")
    m.obj("Body", "car_paint", bevel=0.04)
    m.box("Body", (1.78, 4.4, 0.5), (0, 0, 0.57))                                     # lower body 0.32-0.82 m
    m.box("Body", (1.38, 1.62, 0.05), (0, -0.25, 1.355))                              # roof
    # A and C pillars follow the raked screens: glass base y 1.0 / -1.4 at z 0.85, roof edge y 0.53 / -1.13 at 1.33
    for x in (-0.75, 0.75):
        m.box("Body", (0.08, 0.07, 0.69), (x, 0.764, 1.09), rot=(math.atan2(0.472, 0.48), 0, 0))     # A pillars
        m.box("Body", (0.08, 0.07, 0.57), (x, -1.264, 1.09), rot=(-math.atan2(0.272, 0.48), 0, 0))   # C pillars
        m.box("Body", (0.06, 0.1, 0.5), (x, -0.2, 1.09), rot=(0, math.copysign(0.27, -x), 0))   # B pillars
        m.box("Body", (0.2, 0.12, 0.13), (math.copysign(0.99, x), 0.85, 0.97))        # mirror shells
        m.box("Body", (0.12, 0.05, 0.04), (math.copysign(0.86, x), 0.86, 0.93))       # mirror arms
    m.obj("Windows", "car_glass")
    m.box("Windows", (1.62, 2.4, 0.48), (0, -0.2, 1.09), top=(0.84, 0.69, -0.1))      # glasshouse, raked screens
    for x in (-1.0, 1.0):
        m.box("Windows", (0.16, 0.012, 0.1), (math.copysign(0.99, x), 0.784, 0.97))   # mirror glass, facing back
    m.obj("Interior", "car_interior")
    for x in (-0.38, 0.38):
        m.box("Interior", (0.5, 0.5, 0.14), (x, 0.05, 0.79))                          # front seat cushions, 4 cm above the sills
        m.box("Interior", (0.48, 0.12, 0.55), (x, -0.22, 1.0), rot=(0.18, 0, 0))      # front seat backs
        m.box("Interior", (0.26, 0.1, 0.14), (x, -0.27, 1.32))                        # head rests
    m.box("Interior", (1.4, 0.5, 0.14), (0, -0.85, 0.79))                             # rear bench
    m.box("Interior", (1.38, 0.12, 0.5), (0, -1.12, 0.98), rot=(0.2, 0, 0))
    m.box("Interior", (1.5, 0.35, 0.16), (0, 0.72, 0.94))                             # dashboard, clear of the glass base
    m.obj("Trim", "trim_black", bevel=0.015)
    for y in (2.22, -2.22):
        m.box("Trim", (1.84, 0.16, 0.24), (0, y, 0.42))                               # bumpers
    m.box("Trim", (1.0, 0.03, 0.16), (0, 2.215, 0.66))                                # grille surround
    for x in (-0.905, 0.905):
        m.box("Trim", (0.04, 2.0, 0.08), (x, 0, 0.36))                                # side skirts
        for y in (1.4, -1.4):
            m.box("Trim", (0.05, 0.9, 0.06), (x, y, 0.69))                            # wheel-arch flares
        for y in (1.0, -0.15, -1.25):
            m.box("Trim", (0.008, 0.012, 0.42), (math.copysign(0.892, x), y, 0.58))   # door shut lines, 2 mm proud
    m.box("Trim", (1.64, 2.42, 0.03), (0, -0.2, 0.835))                               # window seal / belt line
    for x in (-0.3, 0.3):
        m.box("Trim", (0.5, 0.02, 0.015), (x, 1.06, 0.8275), rot=(0, 0, 0.15))        # wipers, on the scuttle just ahead of the glass
    m.cyl("Trim", 0.004, 0.35, (0, -0.95, 1.38 + 0.175), segs=6)                      # antenna
    m.obj("Chrome", "chrome")
    for i in range(4):
        m.box("Chrome", (0.94, 0.01, 0.018), (0, 2.235, 0.6 + i * 0.04))              # grille slats
    for x in (-0.9, 0.9):
        for y in (0.55, -0.6):
            m.box("Chrome", (0.02, 0.14, 0.03), (math.copysign(0.9, x), y, 0.74))     # door handles
    m.cyl("Chrome", 0.03, 0.15, (0.55, -2.27, 0.3), rot=(math.pi / 2, 0, 0), segs=12) # exhaust
    m.obj("Headlights", "headlight")
    m.obj("Taillights", "taillight")
    m.obj("Indicators", "indicator")
    for x in (-0.6, 0.6):
        m.box("Headlights", (0.36, 0.04, 0.12), (x, 2.205, 0.72))
        m.box("Taillights", (0.36, 0.04, 0.12), (x, -2.205, 0.72))
        m.box("Indicators", (0.14, 0.02, 0.05), (math.copysign(0.7, x), 2.30, 0.48))
        m.box("Indicators", (0.08, 0.04, 0.04), (math.copysign(0.75, x), -2.30, 0.48))
    m.obj("Plates", "plate")
    for y in (2.31, -2.31):
        m.box("Plates", (0.5, 0.02, 0.12), (0, y, 0.42))
    for side, x in (("L", -0.80), ("R", 0.80)):
        for end, y in (("F", 1.4), ("B", -1.4)):
            ax = (x, y, 0.33)
            m.obj("Tyre" + end + side, "rubber", origin=ax)
            m.cyl("Tyre" + end + side, 0.33, 0.22, ax, rot=(0, math.pi / 2, 0), segs=28)
            m.obj("Rim" + end + side, "rim_metal", origin=ax)
            out = math.copysign(1, x)
            m.cyl("Rim" + end + side, 0.21, 0.226, ax, rot=(0, math.pi / 2, 0), segs=24)     # rim face
            for k in range(5):                                                          # spokes, 1 cm proud
                a = k * 2 * math.pi / 5
                m.box("Rim" + end + side, (0.02, 0.05, 0.17),
                      (x + out * 0.118, y + math.sin(a) * 0.1, 0.33 + math.cos(a) * 0.1), rot=(-a, 0, 0))
            m.cyl("Rim" + end + side, 0.05, 0.25, ax, rot=(0, math.pi / 2, 0), segs=12)       # centre cap
    return m.build()


def pillar():
    """Round concrete pillar, one floor tall (2.9 m clear between 0.3 m slabs): flared top, painted foot,
    reflective band, and an electrical conduit with straps and a junction box up its front."""
    m = Model("pillar")
    m.obj("Pillar", "concrete_pillar")
    m.cyl("Pillar", 0.25, 2.53, (0, 0, 0.02 + 2.53 / 2), segs=32)                      # shaft 0.02-2.55
    m.cyl("Pillar", 0.25, 0.35, (0, 0, 2.55 + 0.175), r_top=0.5, segs=32)             # capital to 2.9
    m.obj("Foot", "paint_yellow")
    m.cyl("Foot", 0.26, 0.7, (0, 0, 0.35), segs=32)
    m.obj("Band", "paint_white")
    m.cyl("Band", 0.253, 0.1, (0, 0, 1.25), segs=32)                                  # reflective band
    m.obj("Conduit", "galvanized")
    m.cyl("Conduit", 0.018, 1.91, (0, 0.29, 0.75 + 0.955), segs=10)                   # 0.75 to 2.66, top buried in the capital
    for z in (0.9, 1.6, 2.3):
        m.box("Conduit", (0.06, 0.05, 0.02), (0, 0.272, z))                           # pipe straps
    m.box("Conduit", (0.12, 0.07, 0.14), (0, 0.29, 0.68))                             # junction box
    m.box("Conduit", (0.13, 0.012, 0.15), (0, 0.331, 0.68))                           # its cover plate
    return m.build()


def garage_light():
    """Surface-mounted twin-tube fluorescent fixture with a wire guard, 1.34 m long. Origin at the top centre
    (against the ceiling)."""
    m = Model("garage_light")
    m.obj("Housing", "white_enamel")
    m.box("Housing", (1.3, 0.24, 0.058), (0, 0, -0.031))                              # 2 mm below the ceiling
    for x in (-0.66, 0.66):
        m.box("Housing", (0.02, 0.25, 0.068), (x, 0, -0.036))                          # end caps
        m.box("Housing", (0.03, 0.18, 0.03), (math.copysign(0.625, x), 0, -0.075))    # lampholders
    m.obj("Tubes", "light_fixture")
    for y in (-0.05, 0.05):
        m.cyl("Tubes", 0.013, 1.2, (0, y, -0.08), rot=(0, math.pi / 2, 0), segs=12)
    m.obj("Guard", "galvanized")
    for y in (-0.09, 0.09):
        m.cyl("Guard", 0.004, 1.24, (0, y, -0.11), rot=(0, math.pi / 2, 0), segs=6)    # long wires
    for x in (-0.48, -0.16, 0.16, 0.48):
        m.box("Guard", (0.008, 0.19, 0.008), (x, 0, -0.113))                          # cross wires
        for y in (-0.095, 0.095):
            m.box("Guard", (0.008, 0.008, 0.05), (x, y, -0.087))                      # up to the housing
    return m.build()


def lamp_post():
    """Rooftop lamp post on a concrete pier, 4.6 m. The arm and shoebox head reach to the front (-Z in Godot)."""
    m = Model("lamp_post")
    m.obj("Pier", "concrete_pillar", bevel=0.02)
    m.cyl("Pier", 0.24, 0.5, (0, 0, 0.25), segs=24)
    m.obj("Post", "dark_metal")
    m.box("Post", (0.32, 0.32, 0.03), (0, 0, 0.515))                                  # base plate
    m.cyl("Post", 0.085, 0.12, (0, 0, 0.59), segs=16)                                 # base collar
    m.cyl("Post", 0.075, 3.94, (0, 0, 0.54 + 3.94 / 2), r_top=0.055, segs=16)         # pole 0.54-4.48, foot inside the collar
    m.box("Post", (0.07, 0.012, 0.16), (0, 0.075, 1.2))                               # handhole cover
    m.box("Post", (0.07, 0.95, 0.07), (0, 0.5, 4.45))                                 # arm
    m.box("Post", (0.04, 0.5, 0.04), (0, 0.24, 4.27), rot=(math.atan2(0.3, 0.45), 0, 0))   # brace
    m.box("Post", (0.32, 0.6, 0.1), (0, 0.98, 4.43), top=(0.85, 0.92, 0))             # shoebox head
    m.cyl("Post", 0.025, 0.05, (0, 0.98, 4.505), segs=10)                             # photocell
    m.obj("Bolts", "galvanized")
    for x in (-0.12, 0.12):
        for y in (-0.12, 0.12):
            m.cyl("Bolts", 0.014, 0.08, (x, y, 0.55), segs=8)                         # anchor bolts
            m.cyl("Bolts", 0.024, 0.025, (x, y, 0.5425), segs=6)                      # nuts
    m.obj("Lens", "light_fixture")
    m.box("Lens", (0.24, 0.48, 0.02), (0, 0.98, 4.37))
    return m.build()


def exit_sign():
    """Hanging sign board 1.8 x 0.42 m in an aluminium frame on two rods with ceiling plates. Origin at the top
    centre (ceiling). The text is a Label3D in Godot."""
    m = Model("exit_sign")
    m.obj("Board", "sign_navy", bevel=0.005)
    m.box("Board", (1.8, 0.06, 0.42), (0, 0, -0.61))
    m.obj("Frame", "brushed_metal")
    for z in (-0.40, -0.82):
        m.box("Frame", (1.84, 0.07, 0.022), (0, 0, z))                                # top and bottom rails
    for x in (-0.91, 0.91):
        m.box("Frame", (0.022, 0.07, 0.462), (x, 0, -0.61))                           # side rails
    m.obj("Rods", "galvanized")
    for x in (-0.7, 0.7):
        m.cyl("Rods", 0.008, 0.37, (x, 0, -0.198), segs=8)
        m.cyl("Rods", 0.045, 0.012, (x, 0, -0.008), segs=16)                          # ceiling plates, 2 mm clear
        m.box("Rods", (0.03, 0.03, 0.03), (x, 0, -0.38))                              # clamps on the frame
    return m.build()


def floor_arrow():
    """Painted direction arrow, 2.4 m long, drawn 1 cm thick, tip to the front. Wear is in the paint texture."""
    m = Model("floor_arrow")
    m.obj("Arrow", "paint_yellow")
    m.prism("Arrow", [(-0.5, 0.45), (0.5, 0.45), (0.0, 1.25)], 0.0, 0.01)            # head
    m.box("Arrow", (0.35, 1.6, 0.01), (0, -0.35, 0.005))                              # shaft
    return m.build()


def sprinkler_pipe():
    """One stall's length (2.6 m) of red sprinkler main hung below the beams, with a hanger and a pendant
    sprinkler head. Origin at the top centre (ceiling); the pipe runs front to back."""
    m = Model("sprinkler_pipe")
    m.obj("Pipe", "red_paint")
    m.cyl("Pipe", 0.05, 2.6, (0, 0, -0.52), rot=(math.pi / 2, 0, 0), segs=16)
    m.obj("Fittings", "dark_metal")
    m.cyl("Fittings", 0.062, 0.08, (0, -1.25, -0.52), rot=(math.pi / 2, 0, 0), segs=16)   # grooved coupling
    m.cyl("Fittings", 0.02, 0.08, (0, 0.6, -0.6), segs=10)                            # drop nipple
    m.obj("Hanger", "galvanized")
    m.cyl("Hanger", 0.006, 0.44, (0, 0, -0.227), segs=6)                              # threaded rod, top buried in the anchor
    m.cyl("Hanger", 0.066, 0.025, (0, 0, -0.52), rot=(math.pi / 2, 0, 0), segs=16)    # clevis band
    m.cyl("Hanger", 0.03, 0.01, (0, 0, -0.007), segs=10)                              # ceiling anchor, 2 mm clear
    m.obj("Head", "brushed_metal")
    m.cyl("Head", 0.012, 0.05, (0, 0.6, -0.665), segs=10)
    m.cyl("Head", 0.032, 0.004, (0, 0.6, -0.692), segs=16)                            # deflector
    return m.build()


def oil_drum():
    """55-gallon steel drum used as a bin, 0.58 x 0.9 m, with rolling hoops and a black liner over the rim."""
    m = Model("oil_drum")
    m.obj("Drum", "drum_paint")
    m.cyl("Drum", 0.29, 0.86, (0, 0, 0.012 + 0.43), segs=28)                          # body 0.012-0.872
    for z in (0.3, 0.6):
        m.cyl("Drum", 0.298, 0.03, (0, 0, z), segs=28)                                # rolling hoops
    m.cyl("Drum", 0.296, 0.012, (0, 0, 0.006), segs=28)                               # bottom chime
    m.obj("Liner", "rubber")
    m.cyl("Liner", 0.302, 0.1, (0, 0, 0.84), segs=28)                                 # bag folded over the rim
    m.cyl("Liner", 0.27, 0.06, (0, 0, 0.9), r_top=0.2, segs=20)                       # bag gathered on top
    return m.build()


def fire_cabinet():
    """Wall-mounted extinguisher cabinet, 0.32 x 0.2 x 0.62 m, glazed door, extinguisher inside. Origin at the
    bottom centre of the back (against the wall); the door faces the front."""
    m = Model("fire_cabinet")
    m.obj("Cabinet", "red_paint")
    m.box("Cabinet", (0.32, 0.02, 0.62), (0, 0.01, 0.31))                             # back
    for x in (-0.15, 0.15):
        m.box("Cabinet", (0.02, 0.18, 0.62), (x, 0.11, 0.31))                         # sides
    for z in (0.01, 0.61):
        m.box("Cabinet", (0.28, 0.18, 0.02), (0, 0.11, z))                            # top and bottom
    m.obj("DoorFrame", "brushed_metal")
    for z in (0.03, 0.59):
        m.box("DoorFrame", (0.32, 0.02, 0.04), (0, 0.21, z))
    for x in (-0.145, 0.145):
        m.box("DoorFrame", (0.03, 0.02, 0.6), (x, 0.21, 0.31))
    m.box("DoorFrame", (0.015, 0.03, 0.08), (0.12, 0.235, 0.31))                      # handle
    m.obj("Glass", "car_glass")
    m.box("Glass", (0.262, 0.006, 0.522), (0, 0.208, 0.31))
    m.obj("Extinguisher", "red_paint")
    m.cyl("Extinguisher", 0.075, 0.4, (0, 0.1, 0.03 + 0.2), segs=20)
    m.cyl("Extinguisher", 0.075, 0.05, (0, 0.1, 0.455), r_top=0.03, segs=20)          # shoulder
    m.obj("Valve", "dark_metal")
    m.cyl("Valve", 0.02, 0.06, (0, 0.1, 0.505), segs=10)
    m.box("Valve", (0.02, 0.12, 0.015), (0, 0.13, 0.54))                              # lever
    m.obj("Hose", "rubber")
    m.cyl("Hose", 0.011, 0.3, (0.085, 0.1, 0.36), segs=8)
    return m.build()


MODELS = {f.__name__: f for f in (parked_car, pillar, garage_light, lamp_post, exit_sign, floor_arrow, sprinkler_pipe,
                                   oil_drum, fire_cabinet)}

if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ok = all(MODELS[n]() for n in (names or MODELS))
    sys.exit(0 if ok else 1)
