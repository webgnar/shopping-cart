"""Builds the cart's pennant flag (multiplayer: one per player cart) from Blender primitives and exports a .glb.

Run headless from the repo root:
    blender -b -P tools/blender/flag_models.py
(or with the `bpy` Python module: python tools/blender/flag_models.py)

Writes shopping-cart/assets/models/flag/flag.glb. Uses the garage builder's Model class (one material per object,
z-fighting scan on every build).
Conventions: meters. Origin at the bottom of the pole. The pennant flies toward Blender -Y (Godot +Z), the pole's
clips reach toward Blender +X (Godot +X): scenes/cart/flag.tscn sits it on the cart's rear-left basket corner
turned so the pennant trails behind the cart and the clips meet the basket's side wall.
Objects: Pole (cart_handle, the blue of the handle, like the real coated steel pole), Fittings (cart_plastic: the
two clips and the top cap) and Pennant (flag_pennant: recoloured per player in Godot).
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import garage_models as gm  # noqa: E402  (imports bpy first)

gm.OUT = os.path.join(gm.REPO, "shopping-cart", "assets", "models")

POLE_LEN = 1.75     # m: from the basket's lower wires (0.5 m up) to 2.25 m above the ground, well over a head
POLE_R = 0.006      # 12 mm tube
PENNANT_H = 0.28    # hoist (along the pole)
PENNANT_L = 0.42    # fly (out to the tip)
PENNANT_T = 0.0015  # cloth/plastic sheet thickness, so it reads from both sides
CLIPS = (0.06, 0.44)  # clip heights on the pole: at the basket's lower rail and just under its top rim


def flag():
    m = gm.Model("flag")
    m.obj("Pole", "cart_handle")
    m.cyl("Pole", POLE_R, POLE_LEN, (0, 0, POLE_LEN / 2), segs=10)
    m.obj("Fittings", "cart_plastic")
    for z in CLIPS:
        m.cyl("Fittings", POLE_R + 0.005, 0.04, (0, 0, z), segs=12)                  # sleeve round the pole
        m.box("Fittings", (0.022, 0.012, 0.03), (POLE_R + 0.005 + 0.009, 0, z))     # jaw that grips the basket wire
    m.cyl("Fittings", POLE_R + 0.003, 0.02, (0, 0, POLE_LEN + 0.0095), segs=10)    # top cap, sitting on the tube end
    m.obj("Pennant", "flag_pennant")
    top = POLE_LEN - 0.02
    x = POLE_R + 0.0015                         # sheet starts just clear of the tube, so it never cuts into it
    # The sheet is a thin triangular prism in the YZ plane: hoist along the pole, tip trailing out along -Y.
    pts = [(-x, top), (-x, top - PENNANT_H), (-x - PENNANT_L, top - PENNANT_H * 0.55)]
    # prism() extrudes along Z, so build it flat in XY and stand it up: (y, z) -> points, thickness along X.
    import bmesh
    from mathutils import Matrix
    bm = m.objs["Pennant"]["bm"]
    before = set(bm.verts)
    m.prism("Pennant", [(p[0], p[1]) for p in pts], -PENNANT_T / 2, PENNANT_T / 2)
    new = [v for v in bm.verts if v not in before]
    # (a, b, c) -> (x=c, y=a, z=b): the prism's points become Y (fly) and Z (height), its depth becomes X.
    bmesh.ops.transform(bm, matrix=Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))), verts=new)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return m.build()


if __name__ == "__main__":
    sys.exit(0 if flag() else 1)
