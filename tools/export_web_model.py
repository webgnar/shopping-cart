"""Export a web-sized copy of the rigged cart for the JavaScript mock-up.

Run headless from the repo root after tools/rig_cart.py:
    blender -b ShoppingCart_Rigged.blend --python tools/export_web_model.py

Writes mockup/cart_model.js: the glTF (no UVs, tangents or extra attributes),
gzipped and base64-encoded into a script, so the page needs no file fetches.
"""
import base64, gzip, os, tempfile
import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = set(o.name for o in bpy.data.collections["Reference"].objects)
for o in bpy.data.objects:
    o.select_set(o.name not in ref and (o.type != "MESH" or len(o.data.vertices) > 0))

with tempfile.TemporaryDirectory() as tmp:
    glb = os.path.join(tmp, "cart_web.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_apply=True, export_extras=True,
                              export_yup=True, export_texcoords=False, export_tangents=False,
                              export_attributes=False)
    data = gzip.compress(open(glb, "rb").read(), compresslevel=9)

out = os.path.join(REPO, "mockup", "cart_model.js")
with open(out, "w") as f:
    f.write('window.CART_GLB_GZ_B64="' + base64.b64encode(data).decode() + '";\n')
print("WEB MODEL", out, os.path.getsize(out))
