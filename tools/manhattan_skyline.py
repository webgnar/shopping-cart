"""Turn zack's Manhattan photogrammetry tiles into the parking garage's skyline.

The tiles are OBJ exports of Google Earth 3D tiles of midtown (41 tiles, one OBJ + MTL + 8K PNG atlas
each, ~600k triangles a tile), kept outside the repo (default `~/Pictures/blender/MANHATTAN`). The
garage is set in Bryant Park (between 6th Ave and the library, 40th to 42nd St), lined up with the
street grid. Two parts, both run by `tools/manhattan_skyline.sh`:

- `near`: the buildings within `NEAR_M` of the garage, as real meshes with the tiles' own photo UVs.
  Each tile's part is moved into the level's space, the park inside the garage's lot is cut out
  (it's under the level's street), and the pieces are welded; gltfpack (meshoptimizer) then thins
  it as far as it can without breaking the photo's UV islands. One `near_<tile>.glb` per tile.
- `far`: everything further out, rendered at full detail from the middle of the garage into an
  equirectangular panorama (`far_panorama.png`, transparent sky) that the level uses as its sky.
  It costs nothing per frame; from inside the garage the far skyline barely shifts.

(The first try, simplifying every tile and re-baking its photo onto new UVs, smeared the photos:
the simplified shapes sit metres off the photogrammetry, so the bake rays land on the wrong walls.)

    blender -b -P tools/manhattan_skyline.py -- near <src dir> <out dir> <tile>
    blender -b -P tools/manhattan_skyline.py -- far <src dir> <small texture dir> <out png> <width>

The OBJs are Z-up with the grid in X/Y (read with up=Z, forward=Y, no turn). Positions are taken to
the level's space here, so the meshes sit at the origin of their Godot node: Blender (x, y, z) is
Godot (x, z, -y).
"""
import glob
import math
import sys

import bpy
import numpy as np

# Bryant Park in the tiles' coordinates: the middle of the garage's lot, the street grid's turn and
# the ground level (the lawn's lowest points).
PARK = (-170.0, -355.0, -52.5)
GRID_TURN_DEG = 30.3
# The middle of the level's street slab (Godot x 50, z -5) and its half size plus 2 m.
LOT_CENTRE = (50.0, 5.0)
LOT_HALF = (87.0, 47.0)
CUT_TOP_M = 30.0     # inside the lot, everything lower than this goes (the park's trees and kiosks)
NEAR_M = 250.0       # buildings closer than this to the lot's middle are real meshes
EYE_M = 8.0          # the panorama is taken from halfway up the garage
WELD_M = 0.03        # weld distance for the loose photogrammetry pieces


def tile_path(src: str, tile: str) -> str:
    return "%s/8fd1b8414f3a_gltf_tile_%s.obj" % (src, tile)


def to_level(xyz: np.ndarray) -> np.ndarray:
    """Tile coordinates to the level's (Blender-axis) coordinates."""
    a = math.radians(GRID_TURN_DEG)
    x = xyz[:, 0] - PARK[0]
    y = xyz[:, 1] - PARK[1]
    out = np.empty_like(xyz)
    out[:, 0] = x * math.cos(a) - y * math.sin(a) + LOT_CENTRE[0]
    out[:, 1] = x * math.sin(a) + y * math.cos(a) + LOT_CENTRE[1]
    out[:, 2] = xyz[:, 2] - PARK[2]
    return out


def import_tile(path: str) -> bpy.types.Object:
    before = set(bpy.context.scene.objects)
    bpy.ops.wm.obj_import(filepath=path, up_axis="Z", forward_axis="Y")
    objs = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        o.select_set(True)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = ob.data
    co = np.empty(len(me.vertices) * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    me.vertices.foreach_set("co", to_level(co.reshape(-1, 3)).reshape(-1).astype(np.float32))
    me.update()
    return ob


def keep_faces(ob: bpy.types.Object, near: bool) -> int:
    """Delete the faces in the lot, and those beyond (near) or within (far) NEAR_M. Returns faces left."""
    me = ob.data
    n = len(me.polygons)
    if n == 0:
        return 0
    centres = np.empty(n * 3, dtype=np.float32)
    me.polygons.foreach_get("center", centres)
    c = centres.reshape(-1, 3)
    dx = c[:, 0] - LOT_CENTRE[0]
    dy = c[:, 1] - LOT_CENTRE[1]
    in_lot = (np.abs(dx) < LOT_HALF[0]) & (np.abs(dy) < LOT_HALF[1]) & (c[:, 2] < CUT_TOP_M)
    close = np.hypot(dx, dy) < NEAR_M
    drop = in_lot | (~close if near else close)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    me.polygons.foreach_set("select", drop)
    me.update()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="FACE")
    if near:
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=WELD_M)
    bpy.ops.object.mode_set(mode="OBJECT")
    return len(me.polygons)


def near(src: str, out_dir: str, tile: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob = import_tile(tile_path(src, tile))
    before = len(ob.data.polygons)
    left = keep_faces(ob, near=True)
    print("NEAR %s: %d of %d faces" % (tile, left, before))
    if left == 0:
        return
    ob.name = "near_%s" % tile
    ob.data.name = "near_%s" % tile
    ob.data.materials.clear()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath="%s/near_%s_full.glb" % (out_dir, tile), export_format="GLB",
                              export_normals=False, export_materials="NONE", use_selection=True)


def far(src: str, small_tex: str, out_png: str, width: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paths = sorted(glob.glob("%s/8fd1b8414f3a_gltf_tile_*.obj" % src))
    for path in paths:
        tile = path.rsplit("_", 1)[1][:-4]
        ob = import_tile(path)
        left = keep_faces(ob, near=False)
        print("FAR %s: %d faces" % (tile, left), flush=True)
        if left == 0:
            bpy.data.objects.remove(ob)
            continue
        for mat in ob.data.materials:
            nt = mat.node_tree
            img = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
            # The full 8K atlases of 41 tiles don't fit in memory; a 2K copy is as sharp as the
            # panorama's pixels at this distance.
            old = img.image
            img.image = bpy.data.images.load("%s/tile_%s.jpg" % (small_tex, tile))
            if old is not None:
                bpy.data.images.remove(old)
            out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            emit = nt.nodes.new("ShaderNodeEmission")
            nt.links.new(img.outputs["Color"], emit.inputs["Color"])
            nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])

    scene = bpy.context.scene
    cam = bpy.data.cameras.new("Panorama")
    cam.type = "PANO"
    cam.panorama_type = "EQUIRECTANGULAR"
    cam.clip_end = 5000.0
    cam_ob = bpy.data.objects.new("Panorama", cam)
    scene.collection.objects.link(cam_ob)
    scene.camera = cam_ob
    cam_ob.location = (LOT_CENTRE[0], LOT_CENTRE[1], EYE_M)
    # Level horizon; which way the image's middle faces is matched in Godot by the sky's rotation.
    cam_ob.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as err:  # no Metal: the CPU is fine, only slower
        print("GPU not used:", err)
    scene.cycles.samples = 4
    scene.render.film_transparent = True
    scene.render.resolution_x = width
    scene.render.resolution_y = width // 2
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)


args = sys.argv[sys.argv.index("--") + 1:]
if args[0] == "near":
    near(args[1], args[2], args[3])
else:
    far(args[1], args[2], args[3], int(args[4]))
