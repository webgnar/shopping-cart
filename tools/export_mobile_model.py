"""Export a phone-weight copy of the rigged cart for the mobile web game.

Run headless from the repo root after tools/rig_cart.py:
    blender -b ShoppingCart_Rigged.blend --python tools/export_mobile_model.py

- Drops the caster ball bearings (CirPattern1[n]): 30 tiny parts nobody can see.
- Lowers subdivision on the wheels and simplifies any part over FACE_BUDGET faces.
- Joins each moving part (frame, gate, child seat, flap, casters, wheels) into one mesh, so the phone
  draws about 10 meshes instead of 116. The rig pivots (empties) and their names are kept.
Writes mobile/cart_model_mobile.js: the glTF, gzipped and base64-encoded into a script (no fetches needed).
The rigged .blend is not modified (nothing is saved).
"""
import base64, gzip, os, tempfile
import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACE_BUDGET = 2500      # parts above this get decimated toward it
MIN_RATIO = 0.25        # never decimate a part below a quarter of its faces (keeps thin wires intact)

ref = set(o.name for o in bpy.data.collections["Reference"].objects)
for o in list(bpy.data.objects):
    if o.name in ref or (o.type == "MESH" and o.name.startswith("CirPattern1[")):
        bpy.data.objects.remove(o, do_unlink=True)

dg = bpy.context.evaluated_depsgraph_get()
before = 0
for o in bpy.data.objects:
    if o.type != "MESH" or not len(o.data.vertices):
        continue
    for m in o.modifiers:
        if m.type == "SUBSURF":
            m.levels = min(m.levels, 1)
            m.render_levels = min(m.render_levels, 1)
    e = o.evaluated_get(dg)
    faces = len(e.to_mesh().polygons)
    e.to_mesh_clear()
    before += faces
    if faces > FACE_BUDGET:
        d = o.modifiers.new("MobileDecimate", "DECIMATE")
        d.ratio = max(MIN_RATIO, FACE_BUDGET / faces)

# Apply modifiers, then join each pivot's meshes into one.
bpy.ops.object.select_all(action="DESELECT")
groups = {}
for o in bpy.data.objects:
    if o.type == "MESH" and len(o.data.vertices):
        groups.setdefault(o.parent.name if o.parent else "", []).append(o)
for pivot, objs in groups.items():
    for o in objs:
        o.data = o.data.copy()
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

bpy.ops.object.select_all(action="SELECT")
with tempfile.TemporaryDirectory() as tmp:
    glb = os.path.join(tmp, "cart_mobile.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_apply=True, export_extras=True,
                              export_yup=True, export_texcoords=False, export_tangents=False,
                              export_attributes=False)
    raw = open(glb, "rb").read()
data = gzip.compress(raw, compresslevel=9)
out = os.path.join(REPO, "mobile", "cart_model_mobile.js")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w") as f:
    f.write('window.CART_GLB_GZ_B64="' + base64.b64encode(data).decode() + '";\n')
print("MOBILE MODEL faces %d -> %d, %d meshes, glb %.1f MB, script %.1f MB -> %s" % (
    before, after, meshes, len(raw) / 1e6, os.path.getsize(out) / 1e6, out))
