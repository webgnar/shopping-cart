# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

## 2026-11-16: child seat and seat flap on physics

- `cart.tscn` now has `ChildSeat` (backrest, 0.8 kg) and `SeatFlap` (0.4 kg) rigid bodies, each on a
  HingeJoint3D to the gate at the model's pivots (`ChildSeat_Hinge`, `SeatFlap_Hinge`), with the rig's
  limits: backrest folds back 0 to 30 degrees, flap folds up 0 to 105 degrees. The model pivots follow
  the bodies, like the gate.
- Collision: a 0.02 x 0.49 x 0.47 m panel along the backrest and a 0.13 x 0.012 x 0.48 m plate for
  the flap. They hit groceries and the world but not other cart parts.
- Behaviour: the flap lifts and drops back onto its stop. Folded back, the backrest leans past
  upright and stays flat against the gate until pushed forward again, like a real one.
- The gate assembly is now 2.7 kg instead of 1.5 kg, so the same shove swings it 27 degrees instead
  of 52. The drive test now checks the seat and the flap as well.

## 2026-11-16: parking lot store front from zack's photo, lot sweep

Store front rebuilt after zack's night photo of a supermarket front (`tools/parking_lot_models.py`):

| Model | Tris | KB | Size chosen | Notes |
| --- | --- | --- | --- | --- |
| store_front | 2054 | 104 | 60 m wide; 4 m deep covered walkway; 0.9 m square columns 7.5 m apart; sign band 3.6-5.6 m; pergola piers to 8.6 m; tile mansard to 8.2 m | Column bases and capitals, pilasters through the band, green sign panels with two lightboxes ("service deli", "liquor", Label3D text), stepped pergola with sloping fins and coping over those two bays, red tile mansard with tile courses over the rest, soffit with 14 downlights, sliding entry doors with transom, three mullioned shop windows, downspouts, posted notices |
| water_machine | 96 | 9 | 0.8 x 0.75 x 2.05 m | Generic "WATER / REFILL STATION" (no brand), window, bottle nook, tap, keypad |
| cart_row | 11184 | 546 | 12 nested carts, 4.5 m; each cart 0.97 m long, 0.62 m wide, 1.0 m handle | Wire baskets, chassis, tray, casters, handle grips; each cart 0.32 m along and 6 mm up from the one in front |
| lot_surface | 528 | 21 | + red curb paint 0.2 m on top, full face | Red fire-lane curb as in the photo; stops at the curb cut |

Scene: `scenes/props/parking_lot/store_front.tscn` instances two water machines and two cart rows
(their own scenes), 14 walkway downlights tipped toward the shop wall, 4 warm pergola uplights,
7 warm washes on the tile roof and an entrance glow. The walkway floor is level with the sidewalk
(0.15 m), so the cart rolls up the curb cut and under the walkway.

Sweep of the whole lot:
- Asphalt, concrete, curb, sidewalk, stucco (facade, trim, soffit), mulch and roof tile materials got
  world-space triplanar noise: albedo grain plus a normal map (asphalt and sidewalk also roughness).
  The models have no UVs, so triplanar is what makes this work. Sidewalk darkened a little (it glared).
- Streetlight shadows: `shadow_normal_bias` 2.5 to stop the acne seen on walls.
- The west fire-lane pole moved from x = -15 to -19 so it no longer sits in front of the deli sign.
- Left out: the scooters and the neighbouring vape shop in the photo; script lettering (Godot's default
  font stands in).

Z-fighting: all new and changed models scan at 0. Real hits found and fixed on the way: column tops vs
capitals and soffit, pilasters vs sign band, pier vs band cap, door and window frame bars vs mullions.

## 2026-11-16: holding W or S tips the cart over

`scripts/cart.gd`: W (lift) and S (press) still lean the cart to `lift_pitch` / `press_pitch` at first.
Held past `tip_delay` (0.6 s), the target lean keeps growing at `tip_rate` (0.7 rad/s). Once the nose
passes `let_go_pitch` (0.95 rad, about 54 degrees, past the balance point over either axle, about 45
degrees) or the cart goes upside down, the hands slip off (HUD shows "lost grip") and gravity
finishes it: W puts it on its nose, S lays it on its back on the handle. Releasing the key gives
the hands back. A tap shorter than about a second still drops back onto four wheels. The three values are
in `tuning/cart_tuning.json`; the mobile game does not read them yet (its thumb tilt is unchanged).
Tested in `tests/drive_test.gd` (W/S held 4 s fall over, 0.8 s taps don't). No models or materials changed.
## 2026-11-16: parking garage second pass (props and textures)

Every garage prop rebuilt at full detail, three new props, and every garage material textured.

**Textures** (`tools/textures/make_garage_textures.py`, run with `python3`, writes
`shopping-cart/assets/textures/garage/<name>_{color,normal,rough}.jpg`, 1024 px, tileable). The
usual CC0 sites (TextureCan, ambientCG, Poly Haven) are blocked from the cloud, so the maps are
painted from layered noise in numpy. Materials use world triplanar mapping (no UVs needed) with
`uv1_scale = 1 / tile`. Tile sizes: concrete_deck 4 m (soft oil stains, trowel marks),
concrete_wall 2.4 m (formwork lines, tie holes), concrete_pillar 1.6 m, asphalt 3 m, paint_yellow /
paint_white 2 m (worn chips), rubber 0.5 m, dark_metal 1 m, brushed_metal 0.6 m, galvanized 1 m,
sign_paint 0.8 m, seat_fabric 0.3 m, car_paint 2 m (near white so each car's tint shows),
red_paint 0.8 m, drum_paint 1.2 m (object-space, not world). Texture `.import` files have
mipmaps on and VRAM compression; normals are flagged as normal maps. New shared materials:
car_interior, rim_metal, indicator, white_enamel, galvanized, brushed_metal, red_paint, drum_paint.

**Models** (`tools/blender/garage_models.py`):

| Model | Tris | KB | What changed |
| --- | --- | --- | --- |
| parked_car | 7544 | 399 | A/B/C pillars, roof, mirrors, glass incl. mirror glass, seats and dash, bumpers, grille slats, skirts, arch flares, shut lines, wipers, antenna, handles, exhaust, indicators, plates; each wheel is a Tyre + Rim pivoting on its axle |
| pillar | 562 | 27 | Foot, white band, galvanized conduit (0.75-2.66 m) with straps and junction box |
| garage_light | 332 | 19 | Enamel housing, end caps, lampholders, tubes, wire guard |
| lamp_post | 800 | 42 | Concrete pier, base plate, collar, pole, handhole, arm, brace, shoebox head, photocell, bolts |
| exit_sign | 436 | 24 | Brushed metal frame, hanging rods with ceiling plates and clamps |
| floor_arrow | 20 | 2 | Unchanged |
| sprinkler_pipe (new) | 368 | 19 | 2.6 m red pipe 0.52 m below the ceiling, coupling, drop and head, hanger rod |
| oil_drum (new) | 616 | 27 | 55 gal drum, 0.57 m dia x 0.88 m, rolling hoops, chime, rubber liner |
| fire_cabinet (new) | 342 | 20 | 0.6 x 0.9 x 0.2 m red cabinet, glass door, extinguisher, valve and hose |

**Placement:** sprinkler runs under every covered floor (10 segments per floor, 2.9 m up); an oil
drum by about 40% of pillars on the aisle side (`oil_drum.tscn` is a 15 kg RigidBody3D the cart
can knock over); fire cabinets on the centre walls of wing A (two floors' worth of bands) and wing
B. Cars show "GRG 4K2" plates as Label3D.

**Z-fighting:** every model reports none in the builder (fixed: seats/dash vs body, wipers vs
glass, pole vs collar, hanger rod vs anchor). `tests/garage_zfight_test.gd` reports 0 flush faces;
`garage_test.gd` and `drive_test.gd` pass.

**Left out:** no grime gradient at the bottom of walls (triplanar tiles can't know the wall
height; would need a second UV or a decal pass), glass and light lenses stay flat colour, every
car has the same plate text.

## 2026-11-16: cart materials

- The cart model never had materials: none of the 109 meshes in ShoppingCart_Rigged.blend had
  one (the only images in the file are reference photos), so it rendered plain white in Godot.
- `tools/rig_cart.py` now gives every part one material by name: `cart_chrome` (basket wire,
  frame, gate, seat), `cart_steel` (caster forks, brackets, bolts, bearings), `cart_handle` (blue
  grip, matching the old ShoppingCart_Physics.blend), `cart_plastic` (corner bumpers, seat flap),
  `wheel_rubber` (tyres), `wheel_hub`. The shared Godot materials are in
  `assets/materials/cart/*.tres`, linked by name in `shopping_cart.glb.import`.
- The .glb was re-exported from the base model; node names and pivots are unchanged and the
  drive tests pass. ShoppingCart_Rigged.blend was not re-saved (the cloud Blender is 5.3 and would
  write a file Blender 4.5 can't open); re-run `tools/rig_cart.py` locally to update it.
- No geometry changed, so no z-fighting check was needed.

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

## 2026-11-16: supermarket level

`scenes/levels/supermarket.tscn` (root script `main.gd`): the inside of the store, from zack's reference
photos (long stocked aisles with hanging aisle signs, polished concrete, a high warehouse ceiling with
trusses and ducts) and matched to the store-front photo the parking lot uses (cream stucco walls, the
green sign band carried inside, shop-front windows either side of the doors, warm light). 36 x 28 m,
8 m to the roof deck. Entrance on -X, `CartSpawn` just inside it facing +X. Six 12 m gondolas make seven
aisles (signs 1-7), checkouts and produce up front, dairy cases on three walls, five pallet displays of
loose cases to crash into. Check: `xvfb-run godot -s res://tests/supermarket_check.gd -- <out dir>`
(spawn on 4 wheels, push 5+ m through the store, ram a display and knock cases; saves 7 screenshots).

**Models** (`tools/supermarket_models.py`, Blender primitives, `assets/models/supermarket/<name>/<name>.glb`).
One material per object, all parts sharing a material merged into one object; materials are
`assets/materials/supermarket/<name>.tres`, written by the builder and linked by name in each `.glb.import`
(`python3 tools/supermarket_models.py --link-materials` after a first import). Shelf stock uses one
triplanar texture (`assets/textures/supermarket/product_facings.png`) so each block reads as a row of products.

| Model | Tris | KB | Size chosen | Notes |
| --- | --- | --- | --- | --- |
| gondola | 3192 | 179 | 12 m run, 1.0 m deep, 1.8 m tall (+ 0.6 m endcap each end) | Plinth, back panel, 11 uprights, 3 shelves a side on brackets, price-tag channels, stock, taped overstock on top, endcaps with red SALE header (text is a Label3D) |
| fridge_case | 492 | 35 | 4 m long, 1.0 m deep, 2.3 m tall | Open multi-deck: grille, lit back, chrome shelves with lips, canopy with blue stripe and light strip, bumper rail |
| produce_table | 4596 | 264 | 2.6 x 1.6 m, 0.78 m to the rim | Slatted crate sides, corner posts, dividers, six heaped bins of fruit, clipped price cards |
| checkout_counter | 388 | 29 | 3.2 m long, 0.93 m high | Belt with rollers and rail, scanner, register with screen, card reader, lane pole and light, impulse rack |
| product_case | 36 | 4 | 36 x 26 x 28 cm, 2 kg | Carton, printed band (material set per display), tape |
| pallet | 156 | 10 | 1.2 x 1.0 x 0.14 m | Deck boards, blocks, bottom boards |
| aisle_sign | 104 | 8 | 1.8 x 0.9 m, hung 3.2 m up on 3 m rods | Double-sided; number and aisle contents are Label3Ds set from the sign's inspector |
| strip_light | 88 | 8 | 2.4 m linear LED, hung at 5 m | Warm diffuser, housing, end caps, cables; an OmniLight3D sits under each one in the scene |
| banner | 204 | 14 | 0.7 x 1.8 m | Fabric with stripe, rod and finials, hangers; "LOW PRICES" is a Label3D |
| store_shell | 4256 | 212 | 36 x 28 m floor, 8 m walls, 0.4 m thick | Floor, cream lower walls / grey upper, green band at 2.95-3.25 m, base trim, clerestory and shop-front windows, sliding doors, roof deck, trusses, joists, two ducts with bands and hangers, five columns with guards. Building convention: origin at the floor centre, entrance on -X |

Judgment calls:
- Gondolas are 1.8 m (the low end of real ones) so the follow camera sees over them.
- Aisles are 2.6 m clear: room to turn the cart around, tight enough to clip shelves at speed.
- Pallet displays put the bottom layer 4 cases wide, overhanging the pallet a little; with cases
  flush the cart's casters stop on the 14 cm pallet before the basket reaches the cases.
- Collision is plain boxes next to each model (gondola + endcaps, case bodies, the building's floor,
  walls and columns); fruit, signs, lights and banners have none. Shelves use `solid.tres`, the floor `tile.tres`.
- Products on shelves are static; only the display cases are loose.

Left out: shoppers, baskets, a deli/bakery counter, freezer doors, the tile roof and pergola (outside).

Z-fighting: the builder checks every pair of boxes in a model for coplanar, overlapping faces pointing
the same way and refuses to export if it finds any. All ten models pass. Fixed on the way: produce
table core vs posts and crossing dividers, banner stripe edges, windows vs trusses and joists in the
shell, column feet vs their guards.

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
