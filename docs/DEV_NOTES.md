# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

## 2026-11-16: parking lot level

`scenes/levels/parking_lot.tscn` (root script `main.gd`): a supermarket lot at night, from zack's
reference photos. 60 x 43 m of asphalt in front of a 60 m store front: a fire lane, two double rows
of 32 stalls each, planter islands at the row ends, 10 LED poles, 5 cart corrals, 14 parked cars.
`CartSpawn` is in the fire lane, facing east. Test: `godot --headless --fixed-fps 120 -s
res://tests/parking_lot_test.gd`. Renders: `xvfb-run godot -s res://tests/parking_lot_screenshot.gd -- <prefix>`.

**Models** (`tools/parking_lot_models.py`, Blender primitives, `assets/models/parking_lot/<name>/<name>.glb`).
Each object has one material, linked by name to `assets/parking_lot/materials/<name>.tres` in the
`.glb.import` file (`python3 tools/parking_lot_models.py --link-materials` after a first import).

| Model | Tris | KB | Size chosen | Notes |
| --- | --- | --- | --- | --- |
| parking_block | 140 | 9 | 1.83 x 0.23 x 0.13 m | Chamfered top, two rebar pins, yellow reflector tape both faces |
| cart_corral | 2136 | 82 | 4.5 m long, 1.3 m wide, rails at 0.25 / 0.6 / 1.0 m | Open end -Z with flared mouth, base plates and bolts, rubber guards, sign panel on the closed end (text is a Label3D) |
| streetlight | 726 | 30 | 1 m pier, pole to 9.4 m, heads 2 m apart | Two LED shoebox heads, base plate, anchor bolts, handhole; the SpotLight3Ds are in the scene |
| palm_tree | 1492 | 60 | 7.6 m | Ringed, leaning trunk, 14 V-folded fronds, 4 dead fronds (two-sided materials) |
| planter_island | 1208 | 37 | 11 x 2.4 m, 0.15 m curb | Rounded curb ring, mulch 3 cm below the curb top, 10 shrubs; pole and palms are instanced scenes |
| parked_car | 1020 | 47 | 4.6 x 1.8 x 1.45 m | Sedan with wheel arches, glass, rims, bumpers, grille, mirrors, handles, lights, plates. Paint is set per car (`paint` in the inspector) |
| stall_markings | 324 | 16 | 8 stalls of 2.7 x 5.5 m, 10 cm lines | Hairpin dividers like the reference photo; paint 2 mm proud of the asphalt |
| store_front | 712 | 42 | 60 m wide, 7 m walls, 9.5 m entrance tower | Cornice, fascia, canopy on columns, glass with mullions, downspouts, wall packs, sign backers; sign text is Label3D |
| lot_surface | 480 | 18 | 64 x 62 m slab, 3 m sidewalk 0.15 m high | Curb cut at the entrance (1:6.7 slope), perimeter curb, two bollards |

Judgment calls:
- Stalls are 2.7 m wide (a little roomier than 2.5 m) so a cart fits beside a parked car.
- Cars sit with their front tyres against the parking block, so they clear it (body underside at 0.33 m).
- Store and lot surface use the building convention: front along X at z = 0 facing +Z, the lot.
  Stall markings' origin is the middle of the aisle edge, stalls running toward +Z.
- Collision is simple boxes and cylinders next to each model; car wheels, flares and shrubs have none.
- Concrete props use the shared `assets/physics/solid.tres`, the ground `asphalt.tres`.

Left out: lamp-post banners, litter, distant buildings and lights beyond the lot, car interiors.

Z-fighting: the builder scans every model for overlapping coplanar faces before export (bottom faces
resting on the ground are skipped); all nine models report 0. The first pass found real hits
(corral rail joints, palm trunk rings, store mullions and window bars, sidewalk curb cut), fixed in
the builder. The SpotLight shadows show some shadow acne on the store fascia in the cloud render.

## 2026-11-16: existing content rebuilt as scenes

- The cart rig, the sandbox level, sky and sun, follow camera and HUD moved from GDScript into
  `.tscn` scenes (`scenes/cart/cart.tscn`, `scenes/main.tscn`, `scenes/environment/`,
  `scenes/cart_camera.tscn`, `scenes/ui/hud.tscn`). Every size, position, mass and colour was
  copied from the old code unchanged, so the drive test numbers match.
- The sandbox's boxes became one instanced prop, `scenes/props/cardboard_box.tscn` (0.35 m cube, 2 kg).
- Groceries are named by what they stand in for (Cereal, Milk, Cheese, Juice, Eggs) but are still
  coloured boxes. No new models; no z-fighting check needed.
- Left as it is: the cart still faces +X with its origin under the handle, because the rig,
  physics and mobile game all use that frame.
