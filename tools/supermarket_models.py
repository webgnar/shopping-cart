"""Build the supermarket level's props in Blender from primitives and export them as .glb for Godot.

Run headless from the repo root (either works):
    blender -b -P tools/supermarket_models.py -- [name ...]
    python3 tools/supermarket_models.py [name ...]        # with the `bpy` pip module (Blender 4.2)
No names = build everything. Then open the Godot project (or `godot --headless --import`) and run this
script once more with --link-materials so every .glb uses the shared Godot materials (see below).

Conventions (same as zack's other projects):
  - Metres, real-world sizes. Every size chosen is listed in docs/levels/supermarket.md.
  - Front faces Godot -Z (Blender +Y), origin at the bottom centre. The store shell is the exception:
    its origin is the centre of the shop floor, entrance on -X.
  - Parts are authored here in Godot coordinates (x right, y up, z toward the viewer) and converted.
  - Each exported object has ONE material, named after a shared Godot material in
    shopping-cart/assets/materials/supermarket/. All parts that share a material are merged into one object,
    so a whole gondola is a handful of draw calls. This script writes those .tres files too, and
    --link-materials points each .glb's import settings at them by name.
  - No z-fighting: every box is checked against every other box in its model for coplanar, overlapping
    faces that point the same way; the build stops if any are found.
"""
import math, os, random, re, sys

import bpy, bmesh
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.path.join(REPO, "shopping-cart")
MODEL_DIR = os.path.join(GODOT, "assets", "models", "supermarket")
MAT_DIR = os.path.join(GODOT, "assets", "materials", "supermarket")
FACINGS = "res://assets/textures/supermarket/product_facings.png"

# ---------------------------------------------------------------- shared materials
# name: (colour, roughness, metallic, emission colour or None, emission energy, uses the product-facings texture)
STOCK = {"red": "c8302c", "orange": "e9a23b", "yellow": "f2d24b", "green": "3a7d44", "lime": "6dbf67",
         "blue": "2f6db5", "sky": "6fb3e0", "purple": "8a3b8f", "cream": "f0ece2", "rust": "d65f2a",
         "brown": "5a3825", "pink": "e86f8a", "navy": "1f3b5c", "olive": "b9c33a", "white": "ffffff",
         "crimson": "a4161a"}
PRODUCE = {"red": "c8302c", "orange": "e9862b", "yellow": "f2d24b", "green": "6dbf67", "brown": "8b5a2b",
           "purple": "6b2d6b"}
MATERIALS = {
    "shelf_metal": ("b7bcc2", 0.45, 0.4, None, 0, False),
    "shelf_dark": ("4a4f57", 0.6, 0.2, None, 0, False),
    "price_tag": ("f2c230", 0.6, 0, None, 0, False),
    "sale_red": ("c8302c", 0.5, 0, None, 0, False),
    "cardboard": ("b08a5a", 0.9, 0, None, 0, False),
    "packing_tape": ("8c6a3f", 0.4, 0, None, 0, False),
    "case_label": ("d9822b", 0.7, 0, None, 0, False),
    "chrome": ("d6dadf", 0.25, 0.9, None, 0, False),
    "fridge_body": ("2b2f36", 0.5, 0.3, None, 0, False),
    "fridge_trim": ("2f6db5", 0.4, 0.2, None, 0, False),
    "fridge_glow": ("e8f4ff", 0.3, 0, "cfe8ff", 0.8, False),
    "grille": ("16181c", 0.7, 0.3, None, 0, False),
    "light_white": ("ffffff", 0.3, 0, "ffffff", 3.0, False),
    "wood_crate": ("8a6239", 0.9, 0, None, 0, False),
    "wood_dark": ("5e4027", 0.9, 0, None, 0, False),
    "pallet_wood": ("a37c4f", 0.9, 0, None, 0, False),
    "card_white": ("f4f4f0", 0.8, 0, None, 0, False),
    "counter_white": ("d9dde2", 0.5, 0, None, 0, False),
    "counter_steel": ("aab0b6", 0.3, 0.7, None, 0, False),
    "belt_black": ("16181c", 0.45, 0, None, 0, False),
    "scanner_glass": ("2d6d8a", 0.1, 0, "1c6f9a", 0.6, False),
    "register_dark": ("2b2f36", 0.4, 0.1, None, 0, False),
    "screen": ("0f2a3a", 0.2, 0, "3b8fc4", 0.7, False),
    "lane_light": ("3ddc84", 0.5, 0, "3ddc84", 2.0, False),
    "sign_dark": ("1d2127", 0.6, 0, None, 0, False),
    "sign_yellow": ("f2c230", 0.5, 0, None, 0, False),
    "lamp_shade": ("dfe3e8", 0.3, 0.6, None, 0, False),
    "lamp_lens": ("ffffff", 0.3, 0, "ffe9c4", 4.0, False),
    "banner_red": ("c8302c", 0.8, 0, None, 0, False),
    "concrete_polished": ("7e8285", 0.15, 0.05, None, 0, False),
    "entrance_mat": ("2b2f36", 0.95, 0, None, 0, False),
    "wall_paint": ("e8dfc8", 0.85, 0, None, 0, False),   # cream stucco, as on the store front
    "accent_green": ("7d8f5a", 0.8, 0, None, 0, False),   # the facade's green sign band
    "wall_upper": ("6f7268", 0.85, 0, None, 0, False),
    "wall_base": ("3a3f47", 0.6, 0, None, 0, False),
    "window_sky": ("bcd8f0", 0.2, 0, "d6e9fa", 1.6, False),
    "window_frame": ("3a3f47", 0.5, 0.4, None, 0, False),
    "roof_deck": ("4d5157", 0.9, 0, None, 0, False),
    "steel_white": ("e5e7ea", 0.6, 0.3, None, 0, False),
    "duct": ("dcdfe3", 0.45, 0.5, None, 0, False),
    # supermarket sweep: glossy vinyl for the giant inflatables
    "vinyl_red": ("d7261e", 0.25, 0, None, 0, False),
    "vinyl_white": ("f4f2ec", 0.25, 0, None, 0, False),
    "vinyl_yellow": ("f5c518", 0.25, 0, None, 0, False),
    "vinyl_green": ("2f9e4f", 0.2, 0, None, 0, False),
    "vinyl_blue": ("2a62c9", 0.25, 0, None, 0, False),
    # supermarket sweep: the packs and labels of the products shoppers grab (Godot primitive meshes)
    "pack_yellow": ("f2c12e", 0.6, 0, None, 0, False),
    "pack_brown": ("4a2c1c", 0.5, 0, None, 0, False),
    "pack_olive": ("6b7a22", 0.25, 0, None, 0, False),
    "pack_sky": ("4fa3e0", 0.4, 0, None, 0, False),
    "pack_crimson": ("9c1b22", 0.35, 0, None, 0, False),
    "pack_red": ("d0312d", 0.4, 0, None, 0, False),
    "pack_white": ("f3f3ef", 0.6, 0, None, 0, False),
    "pack_blue": ("2c58b0", 0.55, 0, None, 0, False),
    "pack_orange": ("ee8a26", 0.45, 0, None, 0, False),
    "pack_pink": ("e59a92", 0.5, 0, None, 0, False),
    "pack_gold": ("d9a62e", 0.35, 0.3, None, 0, False),
    "pack_cream": ("efe6cf", 0.6, 0, None, 0, False),
    "column_paint": ("f0f0ee", 0.6, 0, None, 0, False),
}
for k, c in STOCK.items():
    MATERIALS["stock_" + k] = (c, 0.6, 0, None, 0, True)
for k, c in {"blue": "2f6db5", "red": "c8302c", "green": "3a7d44", "yellow": "f2c230"}.items():
    MATERIALS["case_label_" + k] = (c, 0.7, 0, None, 0, False)   # swapped onto product cases per display
for k, c in PRODUCE.items():
    MATERIALS["produce_" + k] = (c, 0.5, 0, None, 0, False)


def _rgb(hexcol):
    return tuple(int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def write_godot_materials():
    os.makedirs(MAT_DIR, exist_ok=True)
    for name, (colour, rough, metal, emit, energy, facings) in MATERIALS.items():
        r, g, b = _rgb(colour)
        out = ['[gd_resource type="StandardMaterial3D" format=3]', ""]
        if facings:
            out += ['[ext_resource type="Texture2D" path="%s" id="1"]' % FACINGS, ""]
        out += ["[resource]", 'resource_name = "%s"' % name, "albedo_color = Color(%.4f, %.4f, %.4f, 1)" % (r, g, b)]
        if facings:   # one block of stock reads as a row of separate products
            out += ['albedo_texture = ExtResource("1")', "uv1_scale = Vector3(4, 4, 4)", "uv1_triplanar = true"]
        if metal:
            out.append("metallic = %.2f" % metal)
        out.append("roughness = %.2f" % rough)
        if emit:
            er, eg, eb = _rgb(emit)
            out += ["emission_enabled = true", "emission = Color(%.4f, %.4f, %.4f, 1)" % (er, eg, eb),
                    "emission_energy_multiplier = %.2f" % energy]
        path = os.path.join(MAT_DIR, name + ".tres")
        text = "\n".join(out) + "\n"
        if not os.path.exists(path) or _strip_uid(open(path).read()) != _strip_uid(text):
            open(path, "w").write(text)


def _strip_uid(text):
    return re.sub(r' uid="uid://[a-z0-9]+"', "", text)


def blender_material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    colour, rough, metal, emit, energy, _ = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = tuple(_srgb_to_linear(c) for c in _rgb(colour)) + (1,)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = tuple(_srgb_to_linear(c) for c in _rgb(emit)) + (1,)
        p.inputs["Emission Strength"].default_value = energy
    return m


# ---------------------------------------------------------------- the model helper
def g2b(v):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


class ZFightingError(Exception):
    pass


class Model:
    """Collects primitives per material (Godot coordinates), then builds one object per material."""

    def __init__(self, name, folder=None):
        self.name, self.folder = name, folder or name
        self.parts = {}          # material -> [callable(bm)]
        self.boxes = []          # (material, centre, size, label) for the z-fighting check

    def _add(self, mat, fn):
        assert mat in MATERIALS, mat
        self.parts.setdefault(mat, []).append(fn)

    def box(self, mat, size, centre, label=""):
        size, centre = tuple(size), tuple(centre)
        self.boxes.append((mat, centre, size, label))
        m = Matrix.Translation(g2b(centre)) @ Matrix.Diagonal((size[0], size[2], size[1], 1))
        self._add(mat, lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=m))

    def box_span(self, mat, x0, x1, y0, y1, z0, z1, label=""):
        self.box(mat, (x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), label)

    def cyl(self, mat, r_bottom, r_top, h, centre, axis="y", seg=16):
        """Cylinder or cone along a Godot axis; r_bottom is at the low end of that axis."""
        rot = {"y": Matrix.Identity(4), "x": Matrix.Rotation(math.pi / 2, 4, "Y"),
               "z": Matrix.Rotation(math.pi / 2, 4, "X")}[axis]
        m = Matrix.Translation(g2b(centre)) @ rot
        self._add(mat, lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r_bottom,
                                                        radius2=r_top, depth=h, matrix=m))

    def ball(self, mat, r, centre, scale=(1, 1, 1), seg=12):
        m = Matrix.Translation(g2b(centre)) @ Matrix.Diagonal((scale[0], scale[2], scale[1], 1))
        self._add(mat, lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(4, seg // 2),
                                                            radius=r, matrix=m))

    def check_z_fighting(self, eps=1e-5, min_area=1e-6):
        hits = []
        for i in range(len(self.boxes)):
            mi, ci, si, li = self.boxes[i]
            for j in range(i + 1, len(self.boxes)):
                mj, cj, sj, lj = self.boxes[j]
                for k in range(3):
                    for sgn in (-1, 1):
                        if abs((ci[k] + sgn * si[k] / 2) - (cj[k] + sgn * sj[k] / 2)) > eps:
                            continue
                        area = 1.0
                        for a in range(3):
                            if a == k:
                                continue
                            lo = max(ci[a] - si[a] / 2, cj[a] - sj[a] / 2)
                            hi = min(ci[a] + si[a] / 2, cj[a] + sj[a] / 2)
                            area *= max(0.0, hi - lo)
                        if area > min_area:
                            hits.append("%s(%s) / %s(%s) on %s%s" % (li or mi, mi, lj or mj, mj, "-+"[sgn > 0], "xyz"[k]))
        return hits

    def build(self):
        hits = self.check_z_fighting()
        if hits:
            raise ZFightingError("%s: %d coplanar overlaps\n  " % (self.name, len(hits)) + "\n  ".join(hits[:20]))
        bpy.ops.wm.read_factory_settings(use_empty=True)
        root = bpy.data.objects.new(self.name, None)
        bpy.context.scene.collection.objects.link(root)
        tris = 0
        for mat, fns in sorted(self.parts.items()):
            bm = bmesh.new()
            for fn in fns:
                fn(bm)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            me = bpy.data.meshes.new(mat)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(blender_material(mat))
            for poly in me.polygons:
                poly.use_smooth = False
            tris += sum(len(p.vertices) - 2 for p in me.polygons)
            ob = bpy.data.objects.new(mat, me)
            ob.parent = root
            bpy.context.scene.collection.objects.link(ob)
        out_dir = os.path.join(MODEL_DIR, self.folder)
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, self.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                                  export_materials="EXPORT", export_extras=False)
        kb = os.path.getsize(path) / 1024
        print("built %-18s %6d tris %7.1f KB  %d materials" % (self.name, tris, kb, len(self.parts)))
        return tris, kb


# ---------------------------------------------------------------- shared bits
def stock_row(m, rng, x0, x1, y, zc, depth, hmax, along="x", palette=None, label="stock"):
    """A shelf's worth of product blocks from x0 to x1 (along z when along='z'), lifted 1.5 mm off the shelf."""
    palette = palette or list(STOCK)
    x = x0
    while x < x1 - 0.2:
        w = min(rng.choice([0.3, 0.45, 0.6, 0.9, 1.2]), x1 - x)
        h = rng.choice([v for v in [0.16, 0.22, 0.28, 0.34] if v <= hmax])
        mat = "stock_" + rng.choice(palette)
        if along == "x":
            m.box(mat, (w - 0.02, h, depth), (x + w / 2, y + 0.0015 + h / 2, zc), label)
        else:
            m.box(mat, (depth, h, w - 0.02), (zc, y + 0.0015 + h / 2, x + w / 2), label)
        x += w


# ---------------------------------------------------------------- props
def gondola():
    """Double-sided aisle shelving, 12 m run + a 0.6 m endcap each end. Sides face -Z (A) and +Z (B)."""
    rng = random.Random(7)
    L, H = 12.0, 1.8
    m = Model("gondola")
    m.box_span("shelf_dark", -L / 2, L / 2, 0, 0.12, -0.48, 0.48, "plinth")
    m.box_span("shelf_metal", -L / 2 + 0.01, L / 2 - 0.01, 0.12, 1.797, -0.025, 0.025, "back panel")
    m.box_span("shelf_metal", -L / 2 - 0.005, L / 2 + 0.005, 1.8, 1.84, -0.5, 0.5, "top cap")
    for i in range(11):   # uprights every 1.2 m
        x = -L / 2 + 0.03 + i * (L - 0.06) / 10
        m.box("shelf_dark", (0.05, 1.798, 0.07), (x, 0.002 + 1.798 / 2, 0), "upright")
    for side in (-1, 1):
        zf = side * 0.48
        m.box_span("price_tag", -L / 2 + 0.01, L / 2 - 0.01, 0.075, 0.115, *sorted((zf, zf + side * 0.012)), label="tag0")
        stock_row(m, rng, -L / 2 + 0.05, L / 2 - 0.05, 0.12, side * 0.24, 0.40, 0.36)
        for li, top in enumerate([0.56, 0.99, 1.42]):
            board_z = sorted((side * 0.028, side * 0.468))
            m.box_span("shelf_metal", -L / 2 + 0.03, L / 2 - 0.03, top - 0.025, top, *board_z, label="shelf")
            lip = sorted((side * 0.4685, side * 0.4805))
            m.box_span("price_tag", -L / 2 + 0.03, L / 2 - 0.03, top - 0.042, top - 0.002, *lip, label="tag")
            for i in range(11):   # brackets under each board, between uprights' faces
                x = -L / 2 + 0.03 + i * (L - 0.06) / 10
                m.box_span("shelf_dark", x - 0.012, x + 0.012, top - 0.07, top - 0.025,
                           *sorted((side * 0.036, side * 0.42)), label="bracket")
            stock_row(m, rng, -L / 2 + 0.05, L / 2 - 0.05, top, side * 0.24, 0.40, 0.36)
    for i, x in enumerate([-4.8, -2.1, 0.9, 3.6]):   # overstock on top, taped shut
        x += rng.uniform(-0.3, 0.3)
        m.box("cardboard", (1.1, 0.3, 0.7), (x, 1.84 + 0.0015 + 0.15, 0), "overstock")
        m.box("packing_tape", (1.104, 0.002, 0.06), (x, 1.84 + 0.0015 + 0.3 + 0.0005, 0), "tape")
    for sx in (-1, 1):   # endcaps
        x_in, x_out = sx * L / 2, sx * (L / 2 + 0.6)
        xs = sorted((x_in, x_out))
        m.box_span("shelf_dark", *xs, 0, 0.12, -0.479, 0.479, label="endcap plinth")
        m.box_span("shelf_metal", *sorted((x_in + sx * 0.001, x_in + sx * 0.041)), 0.12, 1.46, -0.47, 0.47, label="endcap panel")
        m.box_span("sale_red", *sorted((x_in + sx * 0.001, x_in + sx * 0.031)), 1.46, 1.78, -0.47, 0.47, label="endcap header")
        m.box_span("price_tag", *sorted((x_out, x_out + sx * 0.012)), 0.075, 0.115, -0.47, 0.47, label="endcap tag0")
        ec = x_in + sx * 0.33
        stock_row(m, rng, -0.46, 0.46, 0.12, ec, 0.5, 0.34, along="z")
        for top in [0.55, 0.98]:
            m.box_span("shelf_metal", *sorted((x_in + sx * 0.041, x_out - sx * 0.002)), top - 0.025, top, -0.465, 0.465, label="endcap shelf")
            m.box_span("price_tag", *sorted((x_out - sx * 0.0015, x_out + sx * 0.0105)), top - 0.042, top - 0.002, -0.465, 0.465, label="endcap tag")
            stock_row(m, rng, -0.46, 0.46, top, ec, 0.5, 0.34, along="z")
    return m


def fridge_case():
    """Open multi-deck dairy case, 4 m long, front -Z, back against the wall at +Z."""
    rng = random.Random(11)
    L = 4.0
    m = Model("fridge_case")
    pal = ["white", "cream", "sky", "blue", "yellow", "red", "green", "pink"]
    m.box_span("fridge_body", -L / 2 + 0.05, L / 2 - 0.05, 0, 0.32, -0.4, 0.48, "base")
    for i, y in enumerate([0.06, 0.12, 0.18, 0.24]):
        m.box_span("grille", -L / 2 + 0.1, L / 2 - 0.1, y, y + 0.025, -0.41, -0.4, "grille slat")
    for sx in (-1, 1):
        m.box_span("fridge_body", *sorted((sx * L / 2, sx * (L / 2 - 0.05))), 0, 2.3, -0.5, 0.5, label="end panel")
    m.box_span("fridge_body", -L / 2 + 0.05, L / 2 - 0.05, 0, 2.3, 0.48, 0.5, "back panel")
    m.box_span("fridge_glow", -L / 2 + 0.05, L / 2 - 0.05, 0.32, 1.94, 0.44, 0.48, "lit back")
    m.box_span("fridge_body", -L / 2 + 0.05, L / 2 - 0.05, 1.94, 2.299, -0.2, 0.48, "canopy")
    m.box_span("fridge_trim", -L / 2 + 0.05, L / 2 - 0.05, 2.05, 2.17, -0.21, -0.2, "canopy stripe")
    m.box_span("light_white", -L / 2 + 0.05, L / 2 - 0.05, 1.918, 1.938, -0.19, -0.13, "light strip")
    m.cyl("chrome", 0.02, 0.02, L - 0.12, (0, 0.30, -0.43), axis="x")
    stock_row(m, rng, -L / 2 + 0.08, L / 2 - 0.08, 0.32, 0.12, 0.56, 0.34, palette=pal)
    for top in [0.74, 1.14, 1.52]:
        m.box_span("chrome", -L / 2 + 0.05, L / 2 - 0.05, top - 0.02, top, -0.19, 0.43, "shelf")
        m.box_span("chrome", -L / 2 + 0.05, L / 2 - 0.05, top - 0.0005, top + 0.045, -0.2, -0.19, "shelf lip")
        stock_row(m, rng, -L / 2 + 0.08, L / 2 - 0.08, top, 0.12, 0.56, 0.34, palette=pal)
    return m


def produce_table():
    """Slatted produce crate table, 2.6 x 1.6 m, six heaped bins. Front (price cards) -Z."""
    m = Model("produce_table")
    W, D = 2.6, 1.6
    m.box_span("wood_dark", -W / 2 + 0.05, W / 2 - 0.05, 0.02, 0.719, -D / 2 + 0.05, D / 2 - 0.05, "core")
    for i in range(4):   # slatted sides
        y0 = 0.03 + i * 0.175
        for sz in (-1, 1):
            m.box_span("wood_crate", -W / 2 + 0.01, W / 2 - 0.01, y0, y0 + 0.15, *sorted((sz * (D / 2 - 0.035), sz * (D / 2 - 0.005))), label="side slat")
        for sx in (-1, 1):
            m.box_span("wood_crate", *sorted((sx * (W / 2 - 0.035), sx * (W / 2 - 0.005))), y0, y0 + 0.15, -D / 2 + 0.04, D / 2 - 0.04, label="end slat")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box_span("wood_dark", *sorted((sx * (W / 2 - 0.09), sx * W / 2)), 0, 0.72, *sorted((sz * (D / 2 - 0.09), sz * D / 2)), label="post")
    m.box_span("wood_dark", -W / 2 - 0.05, W / 2 + 0.05, 0.72, 0.78, -D / 2 - 0.05, D / 2 + 0.05, "rim")
    for x in (-0.43, 0.43):
        m.box_span("wood_crate", x - 0.02, x + 0.02, 0.78, 0.83, -D / 2, D / 2, "divider")
    m.box_span("wood_crate", -W / 2, W / 2, 0.7805, 0.829, -0.02, 0.02, "long divider")
    fruit = ["red", "orange", "yellow", "green", "brown", "purple"]
    i = 0
    for zi, z in enumerate([-0.4, 0.4]):
        for x in [-0.86, 0, 0.86]:
            mat = "produce_" + fruit[(i + zi) % len(fruit)]
            m.ball(mat, 0.4, (x, 0.79, z), scale=(1, 0.38, 0.9), seg=16)
            for fx, fz in [(-0.22, -0.16), (0, -0.18), (0.22, -0.14), (-0.2, 0.13), (0.02, 0.15),
                           (0.23, 0.16), (-0.1, -0.01), (0.12, 0.02), (-0.3, 0), (0.31, -0.02)]:
                lift = 0.07 if abs(fx) < 0.15 and abs(fz) < 0.05 else 0.0
                m.ball(mat, 0.085, (x + fx, 0.84 + lift + 0.04 * (1 - abs(fz) / 0.2), z + fz), seg=8)
            i += 1
    for x in (-0.86, 0, 0.86):   # price cards clipped to the front rim
        m.box_span("card_white", x - 0.15, x + 0.15, 0.80, 0.98, -D / 2 - 0.065, -D / 2 - 0.053, "price card")
        m.box_span("wood_dark", x - 0.01, x + 0.01, 0.76, 0.80, -D / 2 - 0.063, -D / 2 - 0.055, "card clip")
    return m


def checkout_counter():
    """Checkout lane counter, 3.2 m along X; the customer side faces -Z."""
    m = Model("checkout_counter")
    m.box_span("belt_black", -1.59, 1.59, 0, 0.08, -0.34, 0.34, "kick")
    m.box_span("counter_white", -1.6, 1.6, 0.08, 0.9, -0.35, 0.35, "body")
    m.box_span("counter_steel", -1.62, 1.62, 0.9, 0.93, -0.37, 0.37, "top")
    m.box_span("belt_black", -1.55, 0.5, 0.93, 0.942, -0.25, 0.25, "belt")
    for x in (-1.55, 0.5):
        m.cyl("chrome", 0.012, 0.012, 0.5, (x, 0.942, 0), axis="z", seg=12)
    m.box_span("chrome", -1.55, 0.5, 0.942, 0.99, -0.29, -0.27, "belt rail")
    m.box_span("scanner_glass", 0.6, 0.96, 0.93, 0.94, -0.2, 0.2, "scanner")
    m.box_span("register_dark", 1.1, 1.4, 0.93, 1.03, 0.0, 0.3, "register base")
    m.box_span("register_dark", 1.22, 1.28, 1.03, 1.12, 0.12, 0.18, "screen stem")
    m.box_span("register_dark", 1.1, 1.4, 1.12, 1.36, 0.13, 0.16, "screen back")
    m.box_span("screen", 1.12, 1.38, 1.14, 1.34, 0.125, 0.13, "screen")
    m.box_span("register_dark", 1.3, 1.4, 0.93, 1.05, -0.3, -0.22, "card reader")
    m.box_span("screen", 1.31, 1.39, 1.0, 1.04, -0.3005, -0.2995, "card reader screen")
    m.box_span("chrome", 1.475, 1.525, 0.93, 2.4, 0.275, 0.325, "lane pole")
    m.box_span("lane_light", 1.34, 1.66, 2.4, 2.72, 0.26, 0.34, "lane light")
    # impulse rack on the customer side
    m.box_span("sale_red", -1.35, -0.45, 0, 1.2, -0.66, -0.64, "rack back")
    for sx in (-1.35, -0.47):
        m.box_span("sale_red", sx, sx + 0.02, 0, 1.2, -0.79, -0.66, label="rack side")
    for i, top in enumerate([0.3, 0.62, 0.94]):
        m.box_span("chrome", -1.33, -0.47, top - 0.015, top, -0.79, -0.66, "rack shelf")
        rng = random.Random(i)
        stock_row(m, rng, -1.32, -0.48, top, -0.725, 0.11, 0.22, palette=["red", "yellow", "orange", "pink", "purple"])
    return m


def product_case():
    """A cardboard case of groceries, 36 x 26 x 28 cm, with a printed band and tape."""
    m = Model("product_case")
    m.box("cardboard", (0.36, 0.26, 0.28), (0, 0.13, 0), "carton")
    m.box("case_label", (0.362, 0.1, 0.282), (0, 0.13, 0), "band")
    m.box("packing_tape", (0.364, 0.0015, 0.05), (0, 0.26 + 0.00075, 0), "tape")
    return m


def pallet():
    """Wooden pallet, 1.2 x 1.0 m, 14 cm tall."""
    m = Model("pallet")
    for z in (-0.45, 0, 0.45):
        m.box_span("pallet_wood", -0.6, 0.6, 0, 0.022, z - 0.05, z + 0.05, "bottom board")
    for x in (-0.55, 0, 0.55):
        m.box_span("wood_dark", x - 0.05, x + 0.05, 0.022, 0.118, -0.495, 0.495, "block")
    for i in range(7):
        z = -0.45 + i * 0.15
        m.box_span("pallet_wood", -0.6, 0.6, 0.118, 0.14, z - 0.05, z + 0.05, "deck board")
    return m


def aisle_sign():
    """Hanging aisle sign, 1.8 m wide, double-sided (faces -Z and +Z). Origin bottom centre; rods go up 3 m."""
    m = Model("aisle_sign")
    m.box_span("sign_dark", -0.9, 0.9, 0, 0.62, -0.03, 0.03, "board")
    m.box_span("sign_yellow", -0.9, 0.9, 0.62, 0.9, -0.04, 0.04, "header")
    for sx in (-1, 1):
        m.box_span("chrome", *sorted((sx * 0.9, sx * 0.92)), 0, 0.9, -0.045, 0.045, label="frame edge")
        m.cyl("chrome", 0.006, 0.006, 3.0, (sx * 0.7, 0.9 + 1.5, 0), seg=8)
    return m


def strip_light():
    """Warm linear LED fixture, 2.4 m long along X, hung on two 2.6 m cables. Origin at the bottom of the diffuser."""
    m = Model("strip_light")
    m.box_span("lamp_lens", -1.19, 1.19, 0, 0.012, -0.11, 0.11, "diffuser")
    m.box_span("steel_white", -1.2, 1.2, 0.012, 0.09, -0.125, 0.125, "housing")
    for sx in (-1, 1):
        m.box_span("register_dark", *sorted((sx * 1.2, sx * 1.212)), 0.012, 0.09, -0.125, 0.125, label="end cap")
        m.cyl("chrome", 0.004, 0.004, 2.6, (sx * 0.9, 0.09 + 1.3, 0), seg=6)
    return m


def banner():
    """Hanging fabric sale banner, 0.7 x 1.8 m, double-sided. Origin bottom centre."""
    m = Model("banner")
    m.box_span("banner_red", -0.35, 0.35, 0, 1.8, -0.01, 0.01, "cloth")
    m.box_span("sign_yellow", -0.349, 0.349, 0.2, 0.3, -0.011, 0.011, "stripe")
    m.cyl("chrome", 0.015, 0.015, 0.8, (0, 1.82, 0), axis="x", seg=12)
    for sx in (-1, 1):
        m.ball("chrome", 0.025, (sx * 0.41, 1.82, 0), seg=8)
        m.cyl("chrome", 0.004, 0.004, 1.0, (sx * 0.3, 1.82 + 0.5, 0), seg=6)
    return m


# ---------------------------------------------------------------- the building
X0, X1, Z0, Z1, HGT, T = -18.0, 18.0, -14.0, 14.0, 8.0, 0.4
COLUMNS = [(-5.5, -12), (-5.5, 12), (14.5, -12), (14.5, 12), (14.5, 0)]


def store_shell():
    """Floor, walls with clerestory windows, entrance doors, roof deck, trusses, ducts and columns.
    Origin: centre of the shop floor. Entrance on -X."""
    m = Model("store_shell")
    m.box_span("concrete_polished", X0, X1, -0.1, 0, Z0, Z1, "floor")
    m.box_span("entrance_mat", X0 + 0.4, X0 + 2.8, 0.0005, 0.0065, -1.8, 1.8, "entrance mat")
    # walls: painted lower band, grey upper wall, dark base trim
    for name, xs, zs in [("front", (X0 - T, X0), (Z0 - T, Z1 + T)), ("back", (X1, X1 + T), (Z0 - T, Z1 + T)),
                         ("left", (X0, X1), (Z0 - T, Z0)), ("right", (X0, X1), (Z1, Z1 + T))]:
        m.box_span("wall_paint", *xs, 0, 3.0, *zs, label=name + " lower")
        m.box_span("wall_upper", *xs, 3.0, HGT, *zs, label=name + " upper")
    for xs, zs in [((X0, X0 + 0.012), (Z0 + 0.012, -1.95)), ((X0, X0 + 0.012), (1.95, Z1 - 0.012)),
                   ((X1 - 0.012, X1), (Z0 + 0.012, Z1 - 0.012)), ((X0 + 0.012, X1 - 0.012), (Z0, Z0 + 0.012)),
                   ((X0 + 0.012, X1 - 0.012), (Z1 - 0.012, Z1))]:
        m.box_span("wall_base", *xs, 0, 0.12, *zs, label="base trim")
    # green accent band (the facade's sign band carried inside), 2.95-3.25 m
    for xs, zs in [((X0, X0 + 0.015), (Z0 + 0.015, Z1 - 0.015)), ((X1 - 0.015, X1), (Z0 + 0.015, Z1 - 0.015)),
                   ((X0 + 0.015, X1 - 0.015), (Z0, Z0 + 0.015)), ((X0 + 0.015, X1 - 0.015), (Z1 - 0.015, Z1))]:
        m.box_span("accent_green", *xs, 2.95, 3.25, *zs, label="accent band")
    # shop-front windows either side of the doors, like the store front photo
    for cz in (-5.0, 5.0):
        m.box_span("window_frame", X0, X0 + 0.03, 0.85, 2.65, cz - 2.05, cz + 2.05, label="front window frame")
        m.box_span("window_sky", X0 + 0.03, X0 + 0.04, 0.9, 2.6, cz - 2.0, cz + 2.0, label="front window")
        for k in (-1, 0, 1):
            m.box_span("window_frame", X0 + 0.04, X0 + 0.05, 0.9, 2.6, cz + k * 1.33 - 0.025, cz + k * 1.33 + 0.025, label="front mullion")
    # clerestory windows: glass set 1 cm proud of the wall, frame around it
    def window(cx, cz, along, w):
        if along == "z":   # on an X wall
            sx = 1 if cx > 0 else -1
            x_in = cx - sx * 0.0
            m.box_span("window_frame", *sorted((x_in, x_in - sx * 0.03)), 5.55, 7.05, cz - w / 2 - 0.05, cz + w / 2 + 0.05, label="window frame")
            m.box_span("window_sky", *sorted((x_in - sx * 0.03, x_in - sx * 0.04)), 5.6, 7.0, cz - w / 2, cz + w / 2, label="window")
            for k in (-1, 1):
                m.box_span("window_frame", *sorted((x_in - sx * 0.04, x_in - sx * 0.05)), 5.6, 7.0, cz + k * w / 6 - 0.025, cz + k * w / 6 + 0.025, label="mullion")
        else:
            sz = 1 if cz > 0 else -1
            m.box_span("window_frame", cx - w / 2 - 0.05, cx + w / 2 + 0.05, 5.55, 7.05, *sorted((cz, cz - sz * 0.03)), label="window frame")
            m.box_span("window_sky", cx - w / 2, cx + w / 2, 5.6, 7.0, *sorted((cz - sz * 0.03, cz - sz * 0.04)), label="window")
            for k in (-1, 1):
                m.box_span("window_frame", cx + k * w / 6 - 0.025, cx + k * w / 6 + 0.025, 5.6, 7.0, *sorted((cz - sz * 0.04, cz - sz * 0.05)), label="mullion")
    for i in range(9):
        cx = X0 + (i + 0.5) * (X1 - X0) / 9
        window(cx, Z0, "x", 3.4)
        window(cx, Z1, "x", 3.4)
    for i in range(7):
        window(X1, Z0 + (i + 0.5) * (Z1 - Z0) / 7, "z", 3.4)
    # entrance: two sliding doors with daylight behind, a frame and a canopy
    m.box_span("window_frame", X0 + 0.0, X0 + 0.06, 0.0, 2.8, -1.95, 1.95, "door frame")
    m.box_span("window_sky", X0 + 0.06, X0 + 0.07, 0.04, 2.7, -1.85, 1.85, "door glass")
    m.box_span("window_frame", X0 + 0.07, X0 + 0.09, 0.04, 2.7, -0.03, 0.03, "door meeting rail")
    m.box_span("window_frame", X0 + 0.06, X0 + 0.14, 2.7, 2.8, -1.85, 1.85, "door header")
    # roof deck, trusses, joists, ducts with hangers
    m.box_span("roof_deck", X0 - T, X1 + T, HGT, HGT + 0.1, Z0 - T, Z1 + T, "roof")
    for x in range(-16, 17, 4):
        m.box_span("steel_white", x - 0.06, x + 0.06, HGT - 0.7, HGT - 0.001, Z0 + 0.06, Z1 - 0.06, "truss")
        m.box_span("steel_white", x - 0.1, x + 0.1, HGT - 0.72, HGT - 0.7, Z0 + 0.061, Z1 - 0.061, "truss chord")
    for z in [-10, -3, 4, 11]:
        m.box_span("steel_white", X0 + 0.06, X1 - 0.06, HGT - 0.95, HGT - 0.83, z - 0.04, z + 0.04, "joist")
    for z in (-5.4, 5.4):
        m.cyl("duct", 0.5, 0.5, X1 - X0 - 0.4, (0, HGT - 1.6, z), axis="x", seg=28)
        for x in range(-14, 15, 4):
            m.cyl("steel_white", 0.52, 0.52, 0.06, (x, HGT - 1.6, z), axis="x", seg=28)   # duct band
            m.cyl("steel_white", 0.008, 0.008, 1.1, (x, HGT - 0.55, z), seg=6)            # hanger rod
    for x, z in COLUMNS:
        m.box_span("column_paint", x - 0.2, x + 0.2, 0.001, HGT - 0.001, z - 0.2, z + 0.2, "column")
        m.box_span("wall_base", x - 0.212, x + 0.212, 0, 0.3, z - 0.212, z + 0.212, "column guard")
    return m


# ---------------------------------------------------------------- supermarket sweep props
def sweep_table():
    """Sale table for one product in a supermarket sweep: 1.0 x 0.5 m tray at 0.72 m on chrome legs, a red skirt on
    both long sides and a price board on a pole at the back-left corner (the Godot scene puts its text on). Long
    axis along X; the front (the side carts shop from) faces -Z, but carts shop from either side."""
    m = Model("sweep_table")
    L, D, top = 1.0, 0.5, 0.72
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box("chrome", (0.03, top - 0.03, 0.03), (sx * (L / 2 - 0.03), (top - 0.03) / 2, sz * (D / 2 - 0.03)), "leg")
        m.box("chrome", (0.024, 0.024, D - 0.09), (sx * (L / 2 - 0.03), 0.12, 0), "foot rail")
    m.box("chrome", (L - 0.09, 0.024, 0.024), (0, 0.12, D / 2 - 0.03), "back rail")
    m.box_span("shelf_dark", -L / 2, L / 2, top - 0.03, top, -D / 2, D / 2, "tray")
    for sz in (-1, 1):   # rim round the tray, standing proud of its edge so no face lines up with the tray's
        m.box_span("chrome", -L / 2 - 0.004, L / 2 + 0.004, top, top + 0.035, *sorted((sz * (D / 2 + 0.004), sz * (D / 2 - 0.012))), label="rim")
    for sx in (-1, 1):
        m.box_span("chrome", *sorted((sx * (L / 2 + 0.003), sx * (L / 2 - 0.013))), top, top + 0.034, -D / 2 + 0.013, D / 2 - 0.013, label="rim end")
    for sz in (-1, 1):
        m.box_span("sale_red", -L / 2 + 0.05, L / 2 - 0.05, top - 0.22, top - 0.032, *sorted((sz * (D / 2 - 0.02), sz * (D / 2 - 0.035))), label="skirt")
    # price board on a pole
    m.box("chrome", (0.025, 1.62 - top, 0.025), (-L / 2 + 0.06, top + (1.62 - top) / 2, D / 2 - 0.06), "pole")
    m.box("sign_dark", (0.56, 0.3, 0.02), (-L / 2 + 0.06, 1.62 + 0.15, D / 2 - 0.06), "board")
    m.box("sign_yellow", (0.564, 0.03, 0.024), (-L / 2 + 0.06, 1.62 + 0.3 + 0.015, D / 2 - 0.06), "board cap")
    return m


def inflatable_bottle():
    """Giant inflatable soda bottle, 1.7 m tall, 0.64 m across: base ring, body, label band, shoulder, neck, cap."""
    m = Model("inflatable_bottle")
    m.cyl("vinyl_green", 0.28, 0.32, 0.12, (0, 0.06, 0), seg=24)             # rounded-off base
    m.cyl("vinyl_green", 0.32, 0.32, 0.9, (0, 0.12 + 0.45, 0), seg=24)       # body
    m.cyl("vinyl_red", 0.326, 0.326, 0.36, (0, 0.62, 0), seg=24)              # label band
    m.cyl("vinyl_green", 0.32, 0.11, 0.42, (0, 1.02 + 0.21, 0), seg=24)      # shoulder
    m.cyl("vinyl_green", 0.11, 0.11, 0.14, (0, 1.44 + 0.07, 0), seg=16)      # neck
    m.cyl("vinyl_white", 0.125, 0.125, 0.12, (0, 1.58 + 0.06, 0), seg=16)    # cap
    return m


def inflatable_cereal():
    """Giant inflatable cereal box, 0.9 x 1.4 x 0.35 m, front -Z: yellow box, white panel and red stripe front and back."""
    m = Model("inflatable_cereal")
    m.box("vinyl_yellow", (0.9, 1.4, 0.35), (0, 0.7, 0), "box")
    m.box("vinyl_red", (0.904, 0.16, 0.354), (0, 1.18, 0), "stripe")
    for sz in (-1, 1):
        m.box("vinyl_white", (0.6, 0.5, 0.004), (0, 0.62, sz * (0.175 + 0.002)), "panel")
        m.box("vinyl_blue", (0.3, 0.12, 0.004), (0, 0.95, sz * (0.175 + 0.002)), "name strip")
    return m


def inflatable_can():
    """Giant inflatable soup can, 1.0 m tall, 0.7 m across: red can, white label, silver rims."""
    m = Model("inflatable_can")
    m.cyl("vinyl_red", 0.35, 0.35, 0.994, (0, 0.003 + 0.497, 0), seg=28)
    m.cyl("vinyl_white", 0.356, 0.356, 0.46, (0, 0.5, 0), seg=28)
    m.cyl("chrome", 0.362, 0.362, 0.04, (0, 0.02, 0), seg=28)
    m.cyl("chrome", 0.362, 0.362, 0.04, (0, 1.0 - 0.02, 0), seg=28)
    return m


BUILDERS = {f.__name__: f for f in [gondola, fridge_case, produce_table, checkout_counter, product_case, pallet,
                                     aisle_sign, strip_light, banner, store_shell,
                                     sweep_table, inflatable_bottle, inflatable_cereal, inflatable_can]}


# ---------------------------------------------------------------- linking .glb imports to the shared materials
def link_materials():
    """Point each .glb's Godot import settings at materials/supermarket/<name>.tres (run after an import)."""
    for name in BUILDERS:
        imp = os.path.join(MODEL_DIR, name, name + ".glb.import")
        if not os.path.exists(imp):
            print("no import file yet for %s: open the project in Godot (or godot --headless --import) first" % name)
            continue
        text = open(imp).read()
        glb = open(os.path.join(MODEL_DIR, name, name + ".glb"), "rb").read()
        mats = sorted(set(re.findall(rb'"materials":\[(.*?)\],"meshes"', glb, re.S)[0].decode().split('"name":"')[1:]))
        mats = sorted({m.split('"')[0] for m in mats})
        entries = ", ".join('"%s": {"use_external/enabled": true, "use_external/path": "res://assets/materials/supermarket/%s.tres"}'
                            % (mt, mt) for mt in mats)
        text = re.sub(r"^_subresources=.*$", '_subresources={"materials": {%s}}' % entries, text, flags=re.M)
        open(imp, "w").write(text)
        print("linked %s: %s" % (name, ", ".join(mats)))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--link-materials" in argv:
        link_materials()
        sys.exit(0)
    names = [a for a in argv if not a.startswith("-")] or list(BUILDERS)
    write_godot_materials()
    for n in names:
        BUILDERS[n]().build()
