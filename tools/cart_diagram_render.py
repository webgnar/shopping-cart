"""Renders the cart model's side and top silhouettes for the HUD's force diagram (scenes/ui/hud.tscn).

    blender -b ShoppingCart_Rigged.blend --factory-startup -P tools/cart_diagram_render.py

Writes shopping-cart/assets/ui/cart_side.png and cart_top.png: the real model, flat white on transparent, drawn
orthographically at PX_PER_M pixels per metre. In the model, X is forward (the nose), Y is to the left (Godot -Z)
and Z is up; the cart's origin is on the ground under the handle.
- Side: nose to the right, up is up. The cart's origin is at pixel SIDE_ORIGIN.
- Top: nose up, the right hand to the right. The cart's origin is at pixel TOP_ORIGIN.
Those numbers are exports on the HUD's ForceView node (scripts/ui/force_diagram.gd); keep them in step.
"""
import math
import os

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "shopping-cart", "assets", "ui")
RES = 520            # px, square
ORTHO = 1.3          # m across the image
PX_PER_M = RES / ORTHO
CENTRE_X, CENTRE_Z = 0.47, 0.6   # m: the middle of the side image (forward, up)
SIDE_ORIGIN = (RES / 2 - CENTRE_X * PX_PER_M, RES / 2 + CENTRE_Z * PX_PER_M)
TOP_ORIGIN = (RES / 2, RES / 2 + CENTRE_X * PX_PER_M)
STRAY = {"Curve.021"}   # a loose curve outside the cart, not part of it

scene = bpy.context.scene
for o in scene.objects:
    if o.name in STRAY:
        o.hide_render = True

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "SINGLE"
scene.display.shading.single_color = (1.0, 1.0, 1.0)
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = False
scene.render.film_transparent = True
scene.render.resolution_x = RES
scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

cam_data = bpy.data.cameras.new("DiagramCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = ORTHO
cam = bpy.data.objects.new("DiagramCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def shoot(name, location, rotation):
    cam.location = location
    cam.rotation_euler = rotation
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)


os.makedirs(OUT, exist_ok=True)
# Side: from the cart's right (-Y), looking at +Y; up is +Z, right is +X (the nose).
shoot("cart_side.png", (CENTRE_X, -5.0, CENTRE_Z), (math.pi / 2, 0.0, 0.0))
# Top: from above looking down; turned so up is +X (the nose) and right is -Y (the cart's right).
shoot("cart_top.png", (CENTRE_X, 0.0, 5.0), (0.0, 0.0, -math.pi / 2))
print("SIDE_ORIGIN", SIDE_ORIGIN, "TOP_ORIGIN", TOP_ORIGIN, "PX_PER_M", PX_PER_M)
