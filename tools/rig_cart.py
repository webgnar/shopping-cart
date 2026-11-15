"""Rig the shopping cart base model: hinge pivots for the gate, child seat and
seat flap, 360-degree swivel for the front casters, and axles for all wheels.

Run headless from the repo root:
    blender -b ShoppingCart_BaseModel.blend --python tools/rig_cart.py

Writes ShoppingCart_Rigged.blend (the base model file is not modified) and
exports shopping-cart/assets/models/shopping_cart.glb for Godot.

Each pivot is an Empty placed on the hinge line. Hinges and axles rotate about
the pivot's local Y axis (the cart's width); caster swivels rotate about local Z.
Rotation limits are stored as custom properties (exported to glTF extras, which
Godot imports as node metadata) and as Limit Rotation constraints for posing
in Blender. Angles in degrees; 0 = the pose the model was built in.
"""
import bpy, math, os
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- Pivot positions measured from the base model (metres, Blender Z-up, cart nose = +X)
GATE_HINGE = (0.068, 0.0, 0.985)   # top edge of the gate, under the handle bar
FLAP_HINGE = (0.138, 0.0, 0.775)   # back edge of the seat flap, where it meets the gate
SEAT_HINGE = (0.207, 0.0, 0.569)   # bottom of the child seat backrest, where it meets the gate
FRONT_SWIVEL_X, FRONT_Y = 0.887, 0.1545   # caster kingpin
FRONT_AXLE = (0.849, 0.063)               # x, z
REAR_AXLE = (0.0685, 0.062)
REAR_Y = 0.3045

# ---- Which mesh goes where. '+' / '-' = left / right side (Blender +Y / -Y).
GATE = ["WireMesh.LowBasketBack"]
SEAT = ["UpperBasket"]
FLAP = ["Plane.005", "WireMesh.UpperBasketSeat"]
FRONT_WHEEL = {"+": ["Cube", "Boss-Extrude6", "Indent1"],
               "-": ["Cube.003", "Boss-Extrude6.003", "Indent1.003"]}
REAR_WHEEL = {"+": ["Cube.001", "Boss-Extrude6.001", "Indent1.001"],
              "-": ["Cube.002", "Boss-Extrude6.002", "Indent1.002"]}
FORK_PARTS = ["Cut-Extrude3", "Fillet5", "Revolve4[2]", "Revolve5", "Revolve6"]  # + CirPattern1[n]


def fork(side):
    sfx = "" if side == "+" else ".001"
    names = [n + sfx for n in FORK_PARTS]
    names += [o.name for o in bpy.data.objects
              if o.name.startswith("CirPattern1[") and o.name.endswith("]" + sfx if sfx else "]")]
    return names


def empty(name, loc, parent=None, size=0.05):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    bpy.context.view_layer.update()
    return e


def attach(names, parent):
    for n in names:
        o = bpy.data.objects[n]
        mw = o.matrix_world.copy()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
        o.matrix_world = mw


def joint(e, kind, axis, lo=None, hi=None):
    """Tag a pivot for Godot and add a Blender limit for posing."""
    e["joint"] = kind          # hinge / swivel / axle
    e["axis"] = axis           # local axis in Blender: 'Y' or 'Z'
    if lo is not None:
        e["limit_min_deg"], e["limit_max_deg"] = lo, hi
        c = e.constraints.new("LIMIT_ROTATION")
        c.owner_space = "LOCAL"
        setattr(c, f"use_limit_{axis.lower()}", True)
        setattr(c, f"min_{axis.lower()}", math.radians(lo))
        setattr(c, f"max_{axis.lower()}", math.radians(hi))
    e.lock_rotation = [a != axis for a in "XYZ"]


ref = set(o.name for o in bpy.data.collections["Reference"].objects)
for o in bpy.data.objects:
    if o.name in ref:
        o.hide_render = True
        o.hide_viewport = True

root = empty("ShoppingCart", (0, 0, 0), size=0.2)
frame = empty("Frame", (0, 0, 0), root, size=0.1)

# Basket back: gate hangs from the top rail and swings forward into the basket.
# The child seat backrest and seat flap are mounted on the gate, so they ride along.
gate = empty("Gate_Hinge", GATE_HINGE, frame)
joint(gate, "hinge", "Y", -70, 0)   # about level at -70
seat = empty("ChildSeat_Hinge", SEAT_HINGE, gate)
joint(seat, "hinge", "Y", -30, 0)      # backrest folds back flat against the gate
flap = empty("SeatFlap_Hinge", FLAP_HINGE, gate)
joint(flap, "hinge", "Y", -105, 0)     # flap folds up flat against the gate
attach(GATE, gate)
attach(SEAT, seat)
attach(FLAP, flap)

for side, tag in (("+", "L"), ("-", "R")):
    y = FRONT_Y if side == "+" else -FRONT_Y
    sw = empty(f"Caster_F{tag}_Swivel", (FRONT_SWIVEL_X, y, FRONT_AXLE[1]), frame)
    joint(sw, "swivel", "Z")                       # free 360
    ax = empty(f"Wheel_F{tag}_Axle", (FRONT_AXLE[0], y, FRONT_AXLE[1]), sw)
    joint(ax, "axle", "Y")
    attach(fork(side), sw)
    attach(FRONT_WHEEL[side], ax)

    y = REAR_Y if side == "+" else -REAR_Y
    ax = empty(f"Wheel_R{tag}_Axle", (REAR_AXLE[0], y, REAR_AXLE[1]), frame)
    joint(ax, "axle", "Y")
    attach(REAR_WHEEL[side], ax)

# Everything else in the cart collection is rigid frame.
for o in bpy.data.objects:
    if o.type == "MESH" and o.parent is None and o.name not in ref and len(o.data.vertices):
        attach([o.name], frame)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(REPO, "ShoppingCart_Rigged.blend"), copy=True)

# ---- glTF for Godot
for o in bpy.data.objects:
    o.select_set(o.name not in ref and (o.type != "MESH" or len(o.data.vertices) > 0))
out = os.path.join(REPO, "shopping-cart", "assets", "models", "shopping_cart.glb")
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_apply=True,
                          export_extras=True, export_yup=True)
print("RIG DONE", out)
