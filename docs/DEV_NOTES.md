# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

## 2026-11-16: holding W or S tips the cart over

`scripts/cart.gd`: W (lift) and S (press) still lean the cart to `lift_pitch` / `press_pitch` at first.
Held past `tip_delay` (0.6 s), the target lean keeps growing at `tip_rate` (0.7 rad/s). Once the nose
passes `let_go_pitch` (0.95 rad, about 54 degrees, past the balance point over either axle, about 45
degrees) or the cart goes upside down, the hands slip off (HUD shows "lost grip") and gravity
finishes it: W puts it on its nose, S lays it on its back on the handle. Releasing the key gives
the hands back. A tap shorter than about a second still drops back onto four wheels. The three values are
in `tuning/cart_tuning.json`; the mobile game does not read them yet (its thumb tilt is unchanged).
Tested in `tests/drive_test.gd` (W/S held 4 s fall over, 0.8 s taps don't). No models or materials changed.

## 2026-11-16: in-game debug console

`scenes/ui/console.tscn` (script `scripts/ui/console.gd`), registered as the `Console` autoload in
`project.godot`, so it is there in every level. The tilde key (` / ~, matched by physical key, so it works on any
layout) opens it; while open the game is paused and the mouse is free. Esc closes it, Up / Down
recall earlier commands. Commands: `help`, `clear`, `where`, and one fast-travel command per entry
in the `destinations` export on the Console node: `plot` (parking lot), `garage`, `market`
(`res://scenes/levels/supermarket.tscn`, which says it isn't built yet until that level lands) and
`sandbox` (`main.tscn`). Travel uses `change_scene_to_file`, so the level spawns the cart at its own
`CartSpawn`. Add a destination in the inspector; add other commands with `_add_command` in
`_ready`. Test: `godot --headless --fixed-fps 120 -s res://tests/console_test.gd`.

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

## 2026-11-16: parking garage level

- **Level** `scenes/levels/parking_garage.tscn` (root script `scripts/levels/parking_garage.gd`, which only
  extends `main.gd`). The cart starts on the roof and rolls down 10 floors. Each floor is a 30 m sloped deck
  dropping 1.6 m (3.05°), with flat 12 m landings at the ends. Floors 10-6 (wing A) U-turn right. The
  halfway landing (y = 8 m) runs straight into wing B, where floors 5-1 U-turn left. Floor 1 ends at a
  street exit.
- **Sizes chosen:** floors stack 3.2 m apart with 0.3 m slabs (2.9 m clear). Each lane is 11.4 m wide:
  a 6 m aisle plus 5.4 x 2.6 m stalls. Rails are 1.0 m high and 0.22-0.25 m thick. Pillars are 0.25 m
  radius with 0.5 m flared tops. Beams are 0.45 m deep. Wing A is 54 x 22.8 m and 17 m tall, wing B is
  54 x 22.8 m. Concrete grip is the same as asphalt (friction 0.9, `assets/physics/concrete.tres`).
- **Models** (`tools/blender/garage_models.py`, built from primitives, in `assets/models/garage/<name>/`,
  props in `scenes/props/garage/`):

  | Model | Size | Tris | glb |
  | --- | --- | --- | --- |
  | parked_car | 4.4 x 1.78 x 1.38 m (Body, Windows, Trim, Headlights, Taillights, Plates, Tyres, Hubs) | 2512 | 132 KB |
  | pillar | 2.9 m, r 0.25 m, yellow 0.7 m foot | 342 | 17 KB |
  | garage_light | 1.3 m twin-tube fluorescent | 100 | 6 KB |
  | lamp_post | 4.6 m, 1 m arm (rooftop) | 172 | 10 KB |
  | exit_sign | 1.8 x 0.42 m board on 0.4 m rods | 212 | 13 KB |
  | floor_arrow | 2.4 x 1.0 m, 1 cm thick | 20 | 2 KB |

  Front is -Z with the origin at the bottom centre. The exception is `garage_light` and `exit_sign`,
  which hang from the ceiling: their origin is the top centre. Materials are shared `.tres` files in
  `assets/materials/garage/`, set on by object name. A car's Body (lower body, roof, mirrors) is one
  object, so `parked_car.gd`'s Paint Color can recolour it per car. The sign text is a Label3D in the
  prop scene ("Exit ->" on the front, "<- Exit" on the back), so one scene serves both turn directions.
- **Placement:** 55 cars, with about 58% of stalls filled and a quarter of the cars backed in. Each car
  is shifted up to 12-15 cm and turned up to 2° so the rows don't look stamped. Pillars and beams stand
  every 3 stalls on covered floors. Wing A's lowest floors stand on 0.3 m stilts. Floors 6 and 1 have
  no exit sign because they run straight on.
- **Z-fighting:** the Blender builder scans every model and finds none. `tests/garage_zfight_test.gd`
  scans every box piece of the level and finds 0 flush faces. To get there, rails stand 2-2.5 cm proud
  of deck edges and undersides and run 1 cm past deck ends, end rails are 1 cm taller and deeper than
  side rails, and the street-level walls are offset by 1 cm.
- **Tests:** `tests/garage_test.gd` (12 checks) covers the roof start, a roll down every floor
  (24.5 m in 9 s, about 10.5 km/h, staying on the deck), and the run across the halfway landing.
- **Left out / known:** the HUD's "Wheels down" counter reads 0/4 above street level, because
  `ShoppingCart.wheels_down()` compares wheel height with y = 0. The decks are plain grey with no
  texture or grime yet. There's no ticket booth or barrier at the exit. Cloud renders use the
  Compatibility renderer.


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
