"""Export a phone-weight copy of the rigged cart for the mobile web game.

Run headless from the repo root (after tools/rig_cart.py has exported the Godot model):
    blender -b --python tools/export_mobile_model.py

Starts from the same model the Godot game uses (shopping-cart/assets/models/shopping_cart.glb), so the
rig pivots and material names match it exactly:
- Drops the caster ball bearings (BallBearing, BallBearing.L): tiny parts nobody can see.
- Simplifies any part over FACE_BUDGET faces (the wheels and wire basket are very dense).
- Joins each moving part (frame, gate, child seat, flap, casters, wheels) into one mesh, so the phone
  draws about 10 meshes (one draw per material in each) instead of 116. Pivot names are kept.
- Keeps each part's material name (cart_chrome, cart_steel, ...). The phone colours them from the shared Godot
  materials (assets/materials/cart/*.tres, copied into mobile/levels/cart.json by the level export), the same
  way Godot's import does, so tune the look in Godot.
Writes mobile/models/cart.glb.
"""
import os
import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "shopping-cart", "assets", "models", "shopping_cart.glb")
OUT = os.path.join(REPO, "mobile", "models", "cart.glb")
FACE_BUDGET = 1000      # parts above this get decimated toward it
MIN_RATIO = 0.15        # never decimate a part below this share of its faces (keeps thin wires intact)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name in ("BallBearing", "BallBearing.L"):
        bpy.data.objects.remove(o, do_unlink=True)

before = 0
for o in bpy.data.objects:
    if o.type != "MESH" or not len(o.data.vertices):
        continue
    faces = len(o.data.polygons)
    before += faces
    if faces > FACE_BUDGET:
        d = o.modifiers.new("MobileDecimate", "DECIMATE")
        d.ratio = max(MIN_RATIO, FACE_BUDGET / faces)

# Apply modifiers, then join each pivot's meshes into one (materials stay per face).
groups = {}
for o in bpy.data.objects:
    if o.type == "MESH" and len(o.data.vertices):
        groups.setdefault(o.parent.name if o.parent else "", []).append(o)
for pivot, objs in groups.items():
    for o in objs:
        o.data = o.data.copy()
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                o.modifiers.remove(m)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    objs[0].name = (pivot or "Cart") + "_Mesh"

after = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
meshes = sum(1 for o in bpy.data.objects if o.type == "MESH")
mats = sorted({s.material.name for o in bpy.data.objects if o.type == "MESH" for s in o.material_slots if s.material})

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_apply=True, export_extras=True,
                          export_yup=True, export_texcoords=False, export_tangents=False,
                          export_attributes=False, export_draco_mesh_compression_enable=False)
print("MOBILE MODEL faces %d -> %d, %d meshes, materials %s, glb %.1f MB -> %s" % (
    before, after, meshes, ", ".join(mats), os.path.getsize(OUT) / 1e6, OUT))
