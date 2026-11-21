"""Build the sandbox's terrain models in Blender and export them as .glb.

Run from the repo root, either with Blender or with the `bpy` Python module:
    blender -b -P tools/sandbox_models.py -- [name ...]
    python3 tools/sandbox_models.py [name ...]        # needs `pip install bpy`

Writes shopping-cart/assets/models/sandbox/<name>/<name>.glb. After a change, run
`godot --headless --import` in shopping-cart/, then `python3 tools/sandbox_models.py --link-materials`
(no Blender needed) so each .glb uses the shared Godot materials, then
`godot --headless -s res://tools/make_sandbox_shapes_cli.gd` to rebuild the collision shapes from the meshes,
and import again.

Only things that can't be a box or a wedge in the scene are built here. Today that is the hill street: a 40 m
sandbox chunk (scenes/sandbox/chunks/hill.tscn) whose ground is a smooth hump. Everything else in the sandbox
chunks is Godot primitive meshes and the existing props.

Conventions:
- Meters. The hill is a whole 40 x 40 m chunk, origin at its centre on the ground (not bottom-centre of a
  prop): every edge sits at height 0 so it meets any neighbouring chunk flush.
- Each object has ONE material, named after a shared Godot material (see MATERIALS).
- No texture coordinates: the shared materials are world-triplanar in Godot.
"""
import math
import os
import sys

if "--link-materials" not in sys.argv:
    import bpy  # first: the bpy module provides bmesh and mathutils
    import bmesh

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "shopping-cart", "assets", "models", "sandbox")

# Shared Godot material for each material name used here.
MATERIALS = {
    "asphalt": "res://assets/parking_lot/materials/asphalt.tres",
    "sidewalk": "res://assets/parking_lot/materials/sidewalk.tres",
    "paint_white": "res://assets/parking_lot/materials/paint_white.tres",
    "grass": "res://assets/materials/sandbox/grass.tres",
}
# Preview colours only: in Godot the shared .tres materials replace these by name.
COLORS = {"asphalt": (0.19, 0.21, 0.23), "sidewalk": (0.56, 0.55, 0.52), "paint_white": (0.91, 0.91, 0.89),
          "grass": (0.23, 0.33, 0.16)}

# ------------------------------------------------------------------ the hill street
HALF = 20.0          # half the chunk: the sandbox grid is 40 m
CREST = 2.6          # m above the flat at the top of the hill
RUN = 17.0           # m from the crest to the foot of the climb (3 m of flat apron to the chunk edge)
ROAD = 4.0           # half width of the road: two 4 m lanes
WALK = 6.5           # the sidewalks run from the road edge out to here
LAWN_FOOT = 18.0     # the lawn falls from the sidewalk to the flat by here
STEP = 0.5           # mesh spacing (m)


def profile(x):
    """Height along the street: a cosine hump, flat beyond RUN. Steepest grade CREST * pi / (2 RUN) = 24 %."""
    if abs(x) >= RUN:
        return 0.0
    return CREST * 0.5 * (1 + math.cos(math.pi * x / RUN))


def falloff(z):
    """Across the street: full height over road and sidewalks, easing down to the flat over the lawn."""
    a = abs(z)
    if a <= WALK:
        return 1.0
    if a >= LAWN_FOOT:
        return 0.0
    return 0.5 * (1 + math.cos(math.pi * (a - WALK) / (LAWN_FOOT - WALK)))


def height(x, z):
    return profile(x) * falloff(z)


def stops(a, b, step, extra=()):
    """Sample positions from a to b about `step` apart, always including a, b and any `extra` inside."""
    n = max(1, round((b - a) / step))
    pts = {round(a + (b - a) * i / n, 4) for i in range(n + 1)}
    pts.update(round(e, 4) for e in extra if a <= e <= b)
    return sorted(pts)


def to_blender(x, y, z):
    """Godot (x right, y up, z back) to Blender (x right, y front, z up): Godot -Z is Blender +Y."""
    return (x, -z, y)


class Model:
    def __init__(self, name):
        self.name = name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.objs = {}

    def obj(self, name, mat):
        self.objs[name] = (bmesh.new(), mat)
        return name

    def surface(self, o, xs, zs, lift=0.0):
        """A height-field patch over the grid xs by zs (Godot coordinates), `lift` m above the ground."""
        bm = self.objs[o][0]
        rows = [[bm.verts.new(to_blender(x, height(x, z) + lift, z)) for x in xs] for z in zs]
        for j in range(len(zs) - 1):
            for i in range(len(xs) - 1):
                # Godot z grows toward the viewer, so this order faces up.
                bm.faces.new([rows[j][i], rows[j + 1][i], rows[j + 1][i + 1], rows[j][i + 1]])

    def export(self):
        os.makedirs(os.path.join(OUT, self.name), exist_ok=True)
        tris = 0
        objects = []
        for name, (bm, mat) in self.objs.items():
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            me.update()
            m = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
            m.diffuse_color = (*COLORS[mat], 1)
            me.materials.append(m)
            ob = bpy.data.objects.new(name, me)
            bpy.context.scene.collection.objects.link(ob)
            tris += sum(len(p.vertices) - 2 for p in me.polygons)
            objects.append(ob)
        path = os.path.join(OUT, self.name, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                                  export_materials="EXPORT", export_texcoords=False, export_tangents=False)
        print("MODEL %-12s %6d tris %5.0f KB  objects: %s" % (
            self.name, tris, os.path.getsize(path) / 1024, ", ".join(o.name for o in objects)))


def hill():
    """The hill street: road over the crest, flush sidewalks either side, lawn banks easing down to the flat,
    a dashed centre line. Road, sidewalks and lawn are separate objects (separate floors for the rolling sound)."""
    m = Model("hill")
    # Finer near the crest's flanks isn't needed: 0.5 m keeps the steepest stretch within 2 cm of the curve.
    xs = stops(-HALF, HALF, STEP, extra=(-RUN, RUN))
    m.surface(m.obj("road", "asphalt"), xs, stops(-ROAD, ROAD, 1.0))
    walk = m.obj("sidewalk", "sidewalk")
    m.surface(walk, xs, stops(-WALK, -ROAD, 0.5))
    m.surface(walk, xs, stops(ROAD, WALK, 0.5))
    lawn = m.obj("lawn", "grass")
    m.surface(lawn, xs, stops(-HALF, -WALK, STEP, extra=(-LAWN_FOOT,)))
    m.surface(lawn, xs, stops(WALK, HALF, STEP, extra=(LAWN_FOOT,)))
    # Centre line: 3 m dashes with 3 m gaps over the climb, 12 cm wide, 4 mm above the road (no z-fighting).
    paint = m.obj("centre_line", "paint_white")
    x = -RUN + 1.5
    while x + 3 <= RUN - 1.0:
        m.surface(paint, stops(x, x + 3, STEP), [-0.06, 0.06], lift=0.004)
        x += 6
    m.export()


def link_materials():
    """Point each .glb's materials at the shared Godot .tres of the same name, in its .import file
    (the editor's Advanced Import Settings > Materials > Use External). Run after `godot --import`."""
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
        entries = ",\n".join(
            '"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s"\n}' % (mm, MATERIALS[mm]) for mm in mats)
        sub = '_subresources={\n"materials": {\n%s\n}\n}' % entries
        text = open(imp).read()
        text = re.sub(r"_subresources=\{.*?\n\}\n(?=\S)|_subresources=\{\}\n", sub + "\n", text, count=1, flags=re.S)
        open(imp, "w").write(text)
        print("LINKED", name, ", ".join(mats))


MODELS = {"hill": hill}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if args == ["--link-materials"]:
        link_materials()
        sys.exit(0)
    for n in args or list(MODELS):
        MODELS[n]()
