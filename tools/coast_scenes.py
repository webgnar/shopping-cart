"""Writes the coast highway's scenes from the road plan (tools/coast_models.py, step 5 of its sequence):

- shopping-cart/scenes/coast/segment_NN.tscn: one per 150 m of road: its model (.glb), its trees (MultiMeshes,
  drawn only within a few hundred metres) and its terrain's collision.
- shopping-cart/scenes/levels/coast_highway.tscn: the level: sky and sun, the sea, the mountains, both headlands,
  the segments, the road and guardrail collision, the traffic (one TrafficRoute a lane, cars placed along it) and
  CartSpawn.

Plain Python (no Blender). Run once after the plan or the models change; after that the scenes are the source of
truth and can be edited in Godot (re-running overwrites them).
"""
import json
import math
import os
import random

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(REPO, "shopping-cart")
PLAN = os.path.join(GAME, "assets", "models", "coast", "coast_plan.json")
SEG_DIR = os.path.join(GAME, "scenes", "coast")
LEVEL = os.path.join(GAME, "scenes", "levels", "coast_highway.tscn")

TREE_NODES = [  # kind, node name, visibility range end (m), casts shadows, phone version draws it
    ("pine", "Pines", 360.0, True, True),
    ("cypress", "Cypresses", 360.0, True, True),
    ("shrub", "Shrubs", 140.0, False, True),
    ("far_pine", "FarPines", 800.0, False, False),
    ("far_cypress", "FarCypresses", 800.0, False, False),
]
CAR_COLORS = ["a8322d", "e6e4dc", "1d2a44", "6f7378", "2f5d3a", "c7a646", "121212", "8c9aa6", "5a2a4a", "b4b9bc",
              "3a6fa8", "d06a2c"]


def f(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))


def xf(cols, o):
    """Transform3D text from basis columns X, Y, Z and origin (Godot writes the basis row by row)."""
    X, Y, Z = cols
    vals = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2], *o]
    return "Transform3D(%s)" % ", ".join(f(round(v, 5)) for v in vals)


def hex_color(h):
    return "Color(%s, 1)" % ", ".join(f(round(int(h[i:i + 2], 16) / 255, 4)) for i in (0, 2, 4))


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return [c / n for c in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def facing(direction):
    """Basis columns for something whose front (-Z) faces `direction`, kept upright."""
    z = norm([-c for c in direction])
    x = norm(cross([0, 1, 0], z))
    y = cross(z, x)
    return x, y, z


def write_segments(plan):
    os.makedirs(SEG_DIR, exist_ok=True)
    for i in range(1, plan["segments"] + 1):
        n = "%02d" % i
        lines = ['[gd_scene format=3]', '',
                 '[ext_resource type="PackedScene" path="res://assets/models/coast/segment_%s/segment_%s.glb" id="1_model"]' % (n, n)]
        for k, (kind, _, _, _, _) in enumerate(TREE_NODES):
            lines.append('[ext_resource type="MultiMesh" path="res://assets/models/coast/trees/segment_%s_%s.tres" id="%d_%s"]'
                         % (n, kind, k + 2, kind))
        lines += ['[ext_resource type="Shape3D" path="res://assets/models/coast/collision/Terrain_%s.res" id="7_terrain"]' % n,
                  '[ext_resource type="PhysicsMaterial" path="res://assets/physics/grass.tres" id="8_grass"]', '',
                  '[node name="Segment%s" type="Node3D"]' % n, '',
                  '[node name="Model" parent="." instance=ExtResource("1_model")]', '']
        for k, (kind, node, far, shadows, phone) in enumerate(TREE_NODES):
            lines += ['[node name="%s" type="MultiMeshInstance3D" parent="."]' % node]
            if not shadows:
                lines.append('cast_shadow = 0')
            lines += ['visibility_range_end = %s' % f(far), 'visibility_range_end_margin = 20.0',
                      'multimesh = ExtResource("%d_%s")' % (k + 2, kind)]
            if not phone:
                lines.append('metadata/mobile_skip = true')
            lines.append('')
        lines += ['[node name="Terrain" type="StaticBody3D" parent="."]',
                  'physics_material_override = ExtResource("8_grass")', '',
                  '[node name="Shape" type="CollisionShape3D" parent="Terrain"]',
                  'shape = ExtResource("7_terrain")', '']
        with open(os.path.join(SEG_DIR, "segment_%s.tscn" % n), "w") as fh:
            fh.write("\n".join(lines))


def polyline_at(pts, cum, d):
    """Point and direction d m along a polyline (cum: cumulative lengths)."""
    i = 0
    while i < len(cum) - 2 and cum[i + 1] < d:
        i += 1
    a, b = pts[i], pts[i + 1]
    u = (d - cum[i]) / max(1e-6, cum[i + 1] - cum[i])
    p = [a[j] + (b[j] - a[j]) * u for j in range(3)]
    return p, norm([b[j] - a[j] for j in range(3)])


def curve_resource(rid, pts):
    data = []
    for p in pts:
        data += [0, 0, 0, 0, 0, 0] + [round(c, 4) for c in p]
    return ['[sub_resource type="Curve3D" id="%s"]' % rid, 'bake_interval = 0.5', '_data = {',
            '"points": PackedVector3Array(%s),' % ", ".join(f(v) for v in data),
            '"tilts": PackedFloat32Array(%s)' % ", ".join("0" for _ in pts), '}',
            'point_count = %d' % len(pts), '']


def write_level(plan):
    rnd = random.Random(77)
    out = ['[gd_scene format=3]', '',
           '[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]',
           '[ext_resource type="Script" path="res://scripts/props/traffic_route.gd" id="2_route"]',
           '[ext_resource type="PackedScene" path="res://scenes/props/sf_hill/traffic_car.tscn" id="3_car"]',
           '[ext_resource type="Material" path="res://assets/coast/materials/sea.tres" id="4_water"]',
           '[ext_resource type="PackedScene" path="res://assets/models/coast/backdrop/backdrop.glb" id="5_backdrop"]',
           '[ext_resource type="PackedScene" path="res://assets/models/coast/headland_top/headland_top.glb" id="6_head_top"]',
           '[ext_resource type="PackedScene" path="res://assets/models/coast/headland_bottom/headland_bottom.glb" id="7_head_bottom"]',
           '[ext_resource type="PhysicsMaterial" path="res://assets/physics/asphalt.tres" id="8_asphalt"]',
           '[ext_resource type="PhysicsMaterial" path="res://assets/physics/solid.tres" id="9_solid"]']
    shapes = ["Deck", "Rail", "Headland_top", "Tube_top", "Headland_bottom", "Tube_bottom"]
    for k, s in enumerate(shapes):
        out.append('[ext_resource type="Shape3D" path="res://assets/models/coast/collision/%s.res" id="%d_%s"]' % (s, 10 + k, s.lower()))
    for i in range(1, plan["segments"] + 1):
        out.append('[ext_resource type="PackedScene" path="res://scenes/coast/segment_%02d.tscn" id="%d_seg%02d"]' % (i, 20 + i, i))
    out += ['',
            '[sub_resource type="ProceduralSkyMaterial" id="Sky_coast"]',
            'sky_top_color = Color(0.32, 0.52, 0.8, 1)', 'sky_horizon_color = Color(0.76, 0.82, 0.87, 1)',
            'ground_bottom_color = Color(0.16, 0.26, 0.32, 1)', 'ground_horizon_color = Color(0.76, 0.82, 0.87, 1)',
            'sun_angle_max = 20.0', '',
            '[sub_resource type="Sky" id="Sky_c"]', 'sky_material = SubResource("Sky_coast")', '',
            '[sub_resource type="Environment" id="Environment_coast"]',
            'background_mode = 2', 'sky = SubResource("Sky_c")', 'ambient_light_source = 3', 'ambient_light_energy = 0.9',
            'reflected_light_source = 2', 'tonemap_mode = 3', 'glow_enabled = true', 'glow_intensity = 0.4',
            'glow_bloom = 0.02', 'glow_hdr_threshold = 1.4', 'fog_enabled = true',
            'fog_light_color = Color(0.77, 0.82, 0.87, 1)', 'fog_density = 0.0012', 'fog_sky_affect = 0.3', '',
            '[sub_resource type="PlaneMesh" id="PlaneMesh_sea"]', 'material = ExtResource("4_water")',
            'size = Vector2(6000, 6000)', '']
    out += curve_resource("Curve3D_downhill", plan["downhill"])
    out += curve_resource("Curve3D_uphill", plan["uphill"])

    sun = facing(norm([-0.35, -0.55, -0.75]))
    out += ['[node name="CoastHighway" type="Node3D"]', 'script = ExtResource("1_main")',
            'metadata/mobile_merge_cell = 100.0', '',
            '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Environment_coast")', '',
            '[node name="Sun" type="DirectionalLight3D" parent="."]',
            'transform = %s' % xf(sun, [600, 200, 0]),
            'light_color = Color(1, 0.94, 0.84, 1)', 'light_energy = 1.15', 'shadow_enabled = true',
            'directional_shadow_mode = 1', 'directional_shadow_max_distance = 90.0', '',
            '[node name="Sea" type="MeshInstance3D" parent="."]',
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 700, 0, 1200)', 'cast_shadow = 0',
            'mesh = SubResource("PlaneMesh_sea")', '',
            '[node name="Mountains" parent="." instance=ExtResource("5_backdrop")]', '',
            '[node name="HeadlandTop" parent="." instance=ExtResource("6_head_top")]', '',
            '[node name="HeadlandBottom" parent="." instance=ExtResource("7_head_bottom")]', '',
            '[node name="Road" type="Node3D" parent="."]', '']
    for i in range(1, plan["segments"] + 1):
        out += ['[node name="Segment%02d" parent="Road" instance=ExtResource("%d_seg%02d")]' % (i, 20 + i, i), '']
    out += ['[node name="RoadSurface" type="StaticBody3D" parent="Road"]',
            'physics_material_override = ExtResource("8_asphalt")', '',
            '[node name="Shape" type="CollisionShape3D" parent="Road/RoadSurface"]', 'shape = ExtResource("10_deck")', '',
            '[node name="Guardrail" type="StaticBody3D" parent="Road"]',
            'physics_material_override = ExtResource("9_solid")', '',
            '[node name="Shape" type="CollisionShape3D" parent="Road/Guardrail"]', 'shape = ExtResource("11_rail")', '',
            '[node name="Headlands" type="StaticBody3D" parent="Road"]',
            'physics_material_override = ExtResource("9_solid")', '']
    for k, (s, node) in enumerate(zip(shapes[2:], ("HeadlandTop", "TubeTop", "HeadlandBottom", "TubeBottom"))):
        out += ['[node name="%s" type="CollisionShape3D" parent="Road/Headlands"]' % node,
                'shape = ExtResource("%d_%s")' % (12 + k, s.lower()), '']

    out += ['[node name="Traffic" type="Node3D" parent="."]', '']
    car = 0
    for lane, speed, count in (("downhill", 11.0, 12), ("uphill", 10.0, 12)):
        name = lane.capitalize()
        pts = plan[lane]
        cum = [0.0]
        for a, b in zip(pts, pts[1:]):
            cum.append(cum[-1] + math.dist(a, b))
        out += ['[node name="%s" type="Path3D" parent="Traffic"]' % name,
                'curve = SubResource("Curve3D_%s")' % lane, 'script = ExtResource("2_route")',
                'speed = %s' % f(speed), '']
        gap = cum[-1] / count
        for k in range(count):
            d = (k + 0.5) * gap + rnd.uniform(-0.25, 0.25) * gap
            p, dirn = polyline_at(pts, cum, d)
            car += 1
            out += ['[node name="Car%d" parent="Traffic/%s" instance=ExtResource("3_car")]' % (car, name),
                    'transform = %s' % xf(facing(dirn), p),
                    'paint_color = %s' % hex_color(CAR_COLORS[(car * 5) % len(CAR_COLORS)]), '']

    sp = plan["spawn"]
    yaw = sp["yaw"]
    rot = ([math.cos(yaw), 0, -math.sin(yaw)], [0, 1, 0], [math.sin(yaw), 0, math.cos(yaw)])
    out += ['[node name="CartSpawn" type="Marker3D" parent="."]', 'transform = %s' % xf(rot, sp["pos"]), '']
    with open(LEVEL, "w") as fh:
        fh.write("\n".join(out))


def write_all():
    plan = json.load(open(PLAN))
    write_segments(plan)
    write_level(plan)
    print("SCENES: %d segments and %s" % (plan["segments"], os.path.relpath(LEVEL, REPO)))


if __name__ == "__main__":
    write_all()
