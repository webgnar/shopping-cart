"""Write the Godot side of the Manhattan skyline (see tools/manhattan_skyline.py).

In `shopping-cart/assets/manhattan_skyline/` (kept out of git): names each `near_<tile>.glb`'s node and
mesh (gltfpack drops them), writes one unshaded material per tile (`near_<tile>.tres`, its photo) and
`manhattan_skyline.tscn`, which instances every tile under `Near` with that material and no shadows.
The parking garage's `Skyline` node instances that scene when it's there.

    python3 tools/manhattan_skyline_scene.py
"""
import glob
import json
import os
import struct

DIR = os.path.join(os.path.dirname(__file__), "..", "shopping-cart", "assets", "manhattan_skyline")
RES = "res://assets/manhattan_skyline"
# The photos are daylight; the garage is lit by a low evening sun. A little warm and dim fits them in.
TINT = "Color(0.9, 0.84, 0.8, 1)"


def name_glb(path: str, name: str) -> None:
    data = open(path, "rb").read()
    json_len = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    rest = data[20 + json_len:]
    for node in doc["nodes"]:
        if "mesh" in node:
            node["name"] = name
    for mesh in doc["meshes"]:
        mesh["name"] = name
    # gltfpack always declares KHR_mesh_quantization, which Godot can't read; with -vpf -vtf the
    # positions and UVs are plain floats, so the declaration can go.
    kinds = {a["componentType"] for a in doc["accessors"] if a.get("type") in ("VEC2", "VEC3")}
    assert kinds == {5126}, "quantized attributes: run gltfpack with -vpf -vtf"
    for key in ("extensionsUsed", "extensionsRequired"):
        if key in doc:
            doc[key] = [e for e in doc[key] if e != "KHR_mesh_quantization"]
            if not doc[key]:
                del doc[key]
    blob = json.dumps(doc, separators=(",", ":")).encode()
    blob += b" " * (-len(blob) % 4)
    total = 12 + 8 + len(blob) + len(rest)
    out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(blob), 0x4E4F534A) + blob + rest
    open(path, "wb").write(out)


def main() -> None:
    tiles = sorted(os.path.basename(p)[5:-4] for p in glob.glob(os.path.join(DIR, "near_*.glb")))
    ext, nodes = [], []
    for i, t in enumerate(tiles):
        name_glb(os.path.join(DIR, "near_%s.glb" % t), "near_%s" % t)
        with open(os.path.join(DIR, "near_%s.tres" % t), "w") as f:
            f.write('[gd_resource type="StandardMaterial3D" format=3]\n\n'
                    '[ext_resource type="Texture2D" path="%s/near_%s.jpg" id="1"]\n\n'
                    '[resource]\n'
                    'resource_name = "near_%s"\n'
                    'cull_mode = 2\n'
                    'shading_mode = 0\n'
                    'albedo_color = %s\n'
                    'albedo_texture = ExtResource("1")\n'
                    'texture_filter = 5\n' % (RES, t, t, TINT))
        ext.append('[ext_resource type="PackedScene" path="%s/near_%s.glb" id="glb_%s"]' % (RES, t, t))
        ext.append('[ext_resource type="Material" path="%s/near_%s.tres" id="mat_%s"]' % (RES, t, t))
        nodes.append('[node name="Tile%s" parent="Near" instance=ExtResource("glb_%s")]\n\n'
                     '[node name="near_%s" parent="Near/Tile%s" index="0"]\n'
                     'material_override = ExtResource("mat_%s")\n'
                     'cast_shadow = 0\n' % (t, t, t, t, t))
    editable = "\n".join('[editable path="Near/Tile%s"]' % t for t in tiles)
    with open(os.path.join(DIR, "manhattan_skyline.tscn"), "w") as f:
        f.write("[gd_scene format=3]\n\n" + "\n".join(ext) + "\n\n"
                '[node name="ManhattanSkyline" type="Node3D"]\n'
                "metadata/_edit_lock_ = true\n\n"
                '[node name="Near" type="Node3D" parent="."]\n\n'
                + "\n".join(nodes) + "\n" + editable + "\n")
    print("wrote", len(tiles), "tiles")


main()
