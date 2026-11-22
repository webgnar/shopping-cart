"""Rig the shopping cart base model: hinge pivots for the gate, child seat and
seat flap, 360-degree swivel for the front casters, and axles for all wheels.

Run headless from the repo root:
    blender -b ShoppingCart_BaseModel.blend --python tools/rig_cart.py

Writes ShoppingCart_Rigged.blend (the base model file is not modified) and
exports shopping-cart/assets/models/shopping_cart.glb for Godot.

Materials: every part gets ONE material, named after a shared Godot material in
shopping-cart/assets/materials/cart/<name>.tres (see PART_MATERIALS below). The colours set
here are previews only; shopping_cart.glb.import maps each name to its .tres (Advanced Import
Settings > Materials > Use External), so tune the look in Godot, not here.

Each pivot is an Empty placed on the hinge line. Hinges and axles rotate about
the pivot's local Y axis (the cart's width); caster swivels rotate about local Z.
Rotation limits are stored as custom properties (exported to glTF extras, which
Godot imports as node metadata) and as Limit Rotation constraints for posing
in Blender. Angles in degrees; 0 = the pose the model was built in.
"""
import bpy, math, os
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- Pivot positions measured from the base model (metres, Blender Z-up, cart nose = +X)
GATE_HINGE = (0.068, 0.0, 0.985)   # top edge of the gate, under the handle bar
# The base model has the child seat set up for a toddler: wire backrest leaning 16.4 degrees forward into the basket
# from its bottom bar on the gate, seat (wire seat + plastic plate) level between the gate and the backrest. The rig
# folds it away (how a cart stands in a lot) and that folded pose is the model's rest pose; the open seat is the far
# end of each hinge. Each part turns about its own origin in the base model, which sits on its hinge:
#  - Child seat (backrest, UpperBasket): hinged on the gate at its bottom bar. Folded back SEAT_FOLD degrees it lies
#    against the gate and the folded seat; the gate swinging up lifts it with it.
#  - Seat flap (seat + plastic, origins on the seat's loops): the loops hook round a gate wire and are its hinge, so
#    it hangs on the gate and the loops never move. Folded up FLAP_FOLD degrees it stands against the gate's front.
GATE_LEAN = 18.2      # degrees: the gate's top leans back (toward the handle) from vertical
SEAT_FOLD = 30.0      # degrees the backrest folds back from the base model: 1 mm clear of the gate and folded seat
FLAP_FOLD = 98.0      # degrees the seat folds up about its loops: 0.5 mm clear of the gate's front wires
FRONT_SWIVEL_X, FRONT_Y = 0.887, 0.1545   # caster kingpin
FRONT_AXLE = (0.849, 0.063)               # x, z
REAR_AXLE = (0.0685, 0.062)
REAR_Y = 0.3045

# ---- Which mesh goes where. '+' / '-' = left / right side (Blender +Y / -Y).
# Part names are the restructured base model's (2026-11-21: Frame.Base, Basket.Main, Caster.*, ...). It has the
# front-right caster only (collection Wheel.Front.Right > Caster), so MIRRORED below copies its parts across the
# cart's centre line to make the front-left one, with ".L" added to each name.
GATE = ["WireMesh.LowBasketBack"]
SEAT = ["UpperBasket"]
FLAP = ["Plane.005", "WireMesh.UpperBasketSeat"]
FRONT_WHEEL = {"+": ["Wheel", "Bolt", "Indent1.003.L"],
               "-": ["Cube.003", "Boss-Extrude6.003", "Indent1.003"]}
REAR_WHEEL = {"+": ["Cube.001", "Boss-Extrude6.001", "Indent1.001"],
              "-": ["Cube.002", "Boss-Extrude6.002", "Indent1.002"]}
# The fork turns on the kingpin; the plate's screw, washer and nut stay with the frame.
FORK = {"-": ["Caster.Bracket", "Caster.Cap", "Caster.Washer", "BallBearing", "BallBearing.Plate"]}
FORK["+"] = [n + ".L" for n in FORK["-"]]
PLATE = ["Screw", "Screw.Base", "Washer", "Nut"]
MIRRORED = FORK["-"] + PLATE + ["Indent1.003"]   # the left wheel's indent is missing too


def fork(side):
    return FORK[side]


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

# ---- Front-left caster: mirror the front-right one's parts across the centre line (Blender Y = 0). Each copy
# gets its modifiers applied and the mirror baked into its mesh (faces kept outward), with an identity
# transform, so attach() below places it like any other part.
from mathutils import Matrix
deps = bpy.context.evaluated_depsgraph_get()
for n in MIRRORED:
    src = bpy.data.objects[n]
    me = bpy.data.meshes.new_from_object(src.evaluated_get(deps))
    to_world = Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)) @ src.matrix_world
    me.transform(to_world)
    if to_world.determinant() < 0:   # an odd number of mirrors reverses the faces' winding
        me.flip_normals()
    me.name = n + ".L"
    o = bpy.data.objects.new(n + ".L", me)
    for c in src.users_collection:
        c.objects.link(o)
bpy.context.view_layer.update()

# ---- Materials: one per part, named after the shared Godot material. Preview colours (linear) only.
CART_MATERIALS = {
    "cart_chrome": ((0.6, 0.62, 0.64), 1.0, 0.2),      # basket wire, frame tubes, gate, seat
    "cart_steel": ((0.4, 0.41, 0.43), 1.0, 0.45),      # caster forks, brackets, bolts, bearings
    "cart_handle": ((0.05, 0.07, 0.8), 0.0, 0.45),     # handlebar grip
    "cart_plastic": ((0.06, 0.065, 0.075), 0.0, 0.6),  # corner bumpers, child seat flap
    "wheel_rubber": ((0.012, 0.012, 0.014), 0.0, 0.85),  # tyres
    "wheel_hub": ((0.3, 0.31, 0.33), 0.0, 0.55),       # wheel hubs and caps
}
PART_MATERIALS = [   # (name prefix, material); first match wins, anything else is chrome
    ("Handbar.Grip", "cart_handle"),
    ("Bumpers", "cart_plastic"), ("Plane.005", "cart_plastic"),
    ("Cube", "wheel_rubber"), ("Wheel", "wheel_rubber"),
    ("Boss-Extrude6", "wheel_hub"), ("Indent1", "wheel_hub"), ("Bolts", "cart_steel"), ("Bolt", "wheel_hub"),
    ("Caster", "cart_steel"), ("BallBearing", "cart_steel"), ("Screw", "cart_steel"), ("Washer", "cart_steel"),
    ("Nut", "cart_steel"),
    ("Cut-Extrude3", "cart_steel"), ("Fillet", "cart_steel"), ("Revolve", "cart_steel"),
    ("CirPattern", "cart_steel"), ("Cut-Sweep2", "cart_steel"), ("Indent2", "cart_steel"),
    ("Cylinder", "cart_steel"), ("Bolts", "cart_steel"), ("Plane.001", "cart_steel"),
    ("Plane.004", "cart_steel"), ("Plane.006", "cart_steel"),
]
for name, (col, metal, rough) in CART_MATERIALS.items():
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*col, 1)
    m.metallic = metal
    m.roughness = rough
for o in bpy.data.objects:
    if o.type != "MESH" or o.name in ref or not len(o.data.vertices):
        continue
    mat = next((m for prefix, m in PART_MATERIALS if o.name.startswith(prefix)), "cart_chrome")
    o.data.materials.clear()
    o.data.materials.append(bpy.data.materials[mat])

# ---- Fix inside-out parts. The right-hand casters were made by mirroring the left ones with a -1 scale,
# which renders inside out once exported; and the rear-right wheel's faces point inward. Bake each mirror
# into its mesh with faces turned the right way, and flip the rear-right wheel's faces.
from mathutils import Matrix
REAR_RIGHT_INWARD = ["Cube.002", "Boss-Extrude6.002", "Indent1.002"]
fixed = []
for o in bpy.data.objects:
    if o.type != "MESH" or o.name in ref or not len(o.data.vertices):
        continue
    if o.matrix_world.determinant() < 0:
        me = o.data.copy()
        me.transform(Matrix.Diagonal((o.scale.x, o.scale.y, o.scale.z, 1.0)))
        me.flip_normals()          # the mirror reversed the winding; restore outward faces
        o.data = me
        o.scale = (1, 1, 1)
        fixed.append(o.name)
    elif o.name in REAR_RIGHT_INWARD:
        o.data = o.data.copy()
        o.data.flip_normals()
        fixed.append(o.name)
print("FIXED INSIDE-OUT", len(fixed), fixed)
for o in bpy.data.objects:
    if o.name in ref:
        o.hide_render = True
        o.hide_viewport = True

root = empty("ShoppingCart", (0, 0, 0), size=0.2)
frame = empty("Frame", (0, 0, 0), root, size=0.1)

# ---- Fold the child seat away (see the notes at the top). Angles are as seen from the cart's right side
# (Blender -Y, Godot +Z) with the nose to the right: counter-clockwise is positive.
def turn(deg, about):
    """Rotation by deg (counter-clockwise seen from the cart's right side, nose to the right) about point (x, z)."""
    r = Matrix.Rotation(math.radians(-deg), 4, "Y")
    p = Vector((about[0], 0.0, about[1]))
    return Matrix.Translation(p) @ r @ Matrix.Translation(-p)


seat_pivot = bpy.data.objects[SEAT[0]].matrix_world.translation.copy()
flap_pivot = bpy.data.objects[FLAP[1]].matrix_world.translation.copy()   # the wire seat's loops
seat_fold = turn(SEAT_FOLD, (seat_pivot.x, seat_pivot.z))
flap_fold = turn(FLAP_FOLD, (flap_pivot.x, flap_pivot.z))
for n in FLAP:
    bpy.data.objects[n].matrix_world = flap_fold @ bpy.data.objects[n].matrix_world
for n in SEAT:
    bpy.data.objects[n].matrix_world = seat_fold @ bpy.data.objects[n].matrix_world
bpy.context.view_layer.update()
print("CHILD SEAT HINGE", tuple(round(v, 4) for v in seat_pivot), "FLAP HINGE", tuple(round(v, 4) for v in flap_pivot))

# Basket back: gate hangs from the top rail and swings forward into the basket. The child seat (backrest) and the
# seat flap both hang on the gate. Limits in degrees, same sign as Godot's hinge angle.
gate = empty("Gate_Hinge", GATE_HINGE, frame)
joint(gate, "hinge", "Y", -70, 0)   # about level at -70
seat = empty("ChildSeat_Hinge", tuple(seat_pivot), gate)
joint(seat, "hinge", "Y", 0, SEAT_FOLD)   # 0 folded on the gate .. leaning into the basket for a toddler
flap = empty("SeatFlap_Hinge", tuple(flap_pivot), gate)
joint(flap, "hinge", "Y", 0, FLAP_FOLD)   # 0 folded up against the gate .. level as a seat
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
