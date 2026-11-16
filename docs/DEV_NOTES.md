# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

## 2026-11-16: browser version brought up to date with the Godot game

The browser build (`mobile/`, three.js + Rapier) is the itch.io in-browser version, so it now plays the Godot
levels and cart instead of its own sandbox. Nothing is rebuilt by hand: export tools copy the Godot scenes.

- **Levels:** `tools/mobile_level_export.gd` loads each console fast-travel destination as the game does, then
  writes `mobile/levels/<key>.glb` (meshes and materials, glTF exporter, textures shrunk to 512 px JPEG) and
  `<key>.json` (every collision shape with its friction, loose props with mass and shapes, CartSpawn, spare carts,
  WorldEnvironment sky/ambient/fog/tonemap, the sun, lamps, Label3D text). Sizes: sandbox 18 KB, parking lot
  2.6 MB, garage 4.6 MB, supermarket 1.2 MB of glb. The phone merges static meshes per material within 24 m
  cells (garage: 1,835 meshes become 222) so it draws a few hundred meshes.
- **Cart:** `levels/cart.json` is the rig from `scenes/cart/cart.tscn` (10 bodies, 9 hinges with limits,
  groceries, guard zone) and the six cart materials from `assets/materials/cart/*.tres`. `models/cart.glb`
  (`tools/export_mobile_model.py`) now starts from the Godot model `shopping_cart.glb`, so it has the child seat
  and flap pivots and the material names: 447,934 faces decimated to 84,685 (budget 1,000 per part, never below
  15 %), 10 meshes, 2.5 MB. It replaces the old base64 `cart_model_mobile.js` (no materials).
- **Behaviour:** `mobile/game/cart.js` ports `scripts/cart.gd` line for line: hand power bars (ramp, relax,
  sprint cap), wrist lever wheelies, braking with planted arms, spin brace, W/S lean with the long-hold flip
  (PRs #20, #21), getting back up with hand keys or W/S, settling and pinning, guard zone wake-up, rolling
  resistance. Spare carts collide with the player's cart (each cart gets its own collision bit, so its own parts
  never touch). The follow camera ports `cart_camera.gd` (sphere sweep, rise over walls, pull in under ceilings).
- **Jolt finding:** Jolt caps every body's spin at 47 rad/s (`max_angular_velocity`, 0.25 * pi * 60). The cart's
  6.35 cm wheels hit that at 3 m/s (10.8 km/h), so above a fast walk the Godot cart's wheels skid and drag: a
  300 N push for 1 s reaches 6.4 m/s in Godot against 9.9 m/s with free wheels. The Godot cart is tuned with
  that drag, so the browser cart caps its wheels the same way. Left as is in Godot; raising
  `physics/jolt_physics_3d/simulation/max_angular_velocity` would change how the cart drives.
- **Lamps:** the levels have 28 to 53 lamps, too many for a phone to shade. A fixed pool of lights (phones 4
  point + 3 spot, computers 6 + 5) moves to the lamps nearest the cart; light energy is multiplied by pi as
  Godot does. On phones the level casts no sun shadows (the carts still do), to keep the garage's 511k
  triangles affordable.
- **Controls:** phones get a push/pull rocker per hand in the bottom corners (above the middle pushes, below
  pulls, hold to ramp, as the keys do), phone tilt or two buttons for W/S, a look-drag at the top, and a Level
  menu. Computers get the Godot keys, pointer-lock mouse look, wheel zoom and the ` console with the same
  commands. The page picks by pointer type and switches on the first touch or game key.
- **Small differences from Godot:** wheels count as down when something solid is right under them (Godot checks
  y < radius, so its HUD reads 0/4 on the garage's upper floors). R respawns on the floor under the cart (Godot
  drops it to y = 0.05). A cart that falls off the edge of the world respawns at CartSpawn.
- **Tests:** `node mobile/test/drive_test.js` runs the Godot drive test's checks in the browser (all pass) plus
  every level, cart-to-cart, camera, touch, keys and console. `tests/mobile_levels_sync_test.gd` fails when a
  level or the cart changed since the last export. `cart_tuning_export.gd` now drops settings the cart no longer
  has (the old gears and drive_height were still in the file), and `arm_relax_rate`, `settle_brake` and
  `stop_delay` joined `ShoppingCart.TUNING_KEYS`.
- **Not ported:** baked lighting and Godot's per-pixel lamps (pooled instead), Label3D fonts (drawn with the page's
  font), the HUD's turn-rate decimals. three.js and Rapier are vendored in `mobile/vendor/` (2.9 MB) so the game
  and its test run without a CDN.

## 2026-11-16: W/S tip the cart over again, and haul it back up

- zack asked for the old long-hold flip back: holding W or S leans the cart, and after `tip_delay` (0.6 s) the
  lean keeps growing at `tip_rate` (0.7 rad/s) until the hands slip off past `let_go_pitch` (0.95 rad) and it
  falls over on its own, onto its nose for W, back onto the handle for S. A short hold (0.8 s) only leans it.
  This replaces the cap from the previous entry.
- On a fallen cart, W or S now hauls it back up too (after letting go once), with the wrists' full
  `tilt_max` (200 N*m), damped by `tilt_kd`. Either key works whichever way it fell, so the key that tipped it
  over gets it back up: about 0.8 s, faster than one hand key (about 3.5 s).
- Drive test: W held 4 s falls onto its nose, S held 4 s onto the handle, and the same key again rights each
  in under a second.

## 2026-11-16: W/S lean keys are back, and a fallen cart can be hauled up

- **W/S lean keys** (zack picked this over hand keys alone). W tips the back up (`lift_pitch` -0.2 rad,
  rear wheels about 0.19 m up), S tips the front up (`press_pitch` 0.3 rad, front wheels about 0.28 m up), at
  any speed, using the earlier wrist controller (`tilt_kp` 1400, `tilt_kd` 80, capped at `tilt_max` 200 N*m).
  With one hand key held as well, only that side leans (`side_roll` 0.22 rad). Unlike the first W/S there's no
  hold-to-tip: holding W or S for 4 s keeps the lean and never throws the cart over (reverted in the next entry). The point is lifting the
  back for a drift at walking pace. The HUD keycaps are back (W "BACK UP", S "FRONT UP").
- **Getting back up.** Tests first (both floors, cart metal friction 0.5 and 1.0): raising friction made no
  real difference, because grip is the lower of metal and floor (tile stays 0.5) and what rights the cart is a
  twist, not friction. What did block it: the hands' push skated a cart lying on its nose across the floor
  (with the nose vertical, "forward" is undefined), and nothing could roll a cart off its side. So:
  - The hands' push and pull fade out as the cart tips past 45 degrees and are gone by `fallen_upright`
    (cos 0.3, about 73 degrees), so they never shove a tipped cart.
  - Once the cart lies past that tilt and has nearly stopped (`fallen_still`, 1 rad/s), it is "fallen". After
    every key has been let go once, a held hand key twists it toward upright by the hand's power times
    `wrist_lever`, damped by `tilt_kd` so it settles instead of going over the other way. Any hand key works,
    whichever way it fell, including from its side or upside down.
  - Back within `stood_upright` (about 18 degrees): the hand power resets and the hands rest until the keys are
    let go, so the power built up hauling doesn't throw it over again.
  - One hand gets it up in about 3.5 s (the power has to climb to about 400 N); two hands are quicker. It moved
    0.4 to 0.8 m while getting up (`tests/drive_test.gd`, "get up").
- Holding a very hard push for 4 s after the front lifts now usually brings the cart back down instead of
  over (the push fades as it tips); a very hard pull still goes over. The drive test reports either.
- Diagram of the forces: `cart-tip/righting_forces.png` in the project files.

## 2026-11-16: performance pass (why the laptop fans spin up)

Profiled every level (`tests/perf_probe.gd` for CPU, `tests/perf_render.gd` for rendering; in the cloud the
GPU is software, so the draw and triangle counts are the trustworthy part).

- **CPU is not the problem.** One 120 Hz physics step plus all scripts takes 0.6 ms (sandbox, garage, lot)
  to 1.0 ms (supermarket, 170 rigid bodies) on the cloud CPU, so about 7 to 12 % of one core. Jolt with
  30 velocity steps is fine; nothing was changed in physics.
- **The GPU is.** Vsync was the only limit, so on a 120 Hz Retina MacBook the game rendered 120 frames a
  second at full Retina resolution with SSAO, glow and real-time shadows. Per frame at 1080p:
  sandbox 287 draws / 158k triangles; lot 2150 / 952k; garage 1782 / 1.55M; supermarket 1051 / 497k.
  Shadow passes are most of that: the lot's 20 shadowed streetlight spots were 1923 of its 2150 draws, the
  garage sun shadow 1178 of 1782, the supermarket skylight shadow 749 of 1051. On the software GPU SSAO was
  roughly a third of the frame and glow about a tenth; rendering 3D at half scale roughly halved it.
- **Changes (look and feel the same in play):**
  - `application/run/max_fps = 60` (vsync stays on). Halves GPU work on 120 Hz screens. Physics still
    runs at 120 Hz, so the cart drives exactly the same. Set it to 0 to go back to uncapped.
  - Streetlight spots fade their shadows out beyond 30 m from the camera (`distance_fade_shadow`, light
    itself never fades). The play camera is 3 m from the cart, so the view is pixel-identical near the cart;
    only the high overview shot loses a few far pole and car shadows. Lot: 2150 -> 1504 draws,
    952k -> 684k triangles.
  - Garage sprinkler pipes, light fixtures and floor arrows no longer cast shadows (they sit under a deck
    or flat on the floor, so their sun shadows were never visible). Garage: 1782 -> 1695 draws.
- **Left for a decision:** rendering 3D below full Retina resolution, shorter sun shadow distance in the
  garage, SSAO off or lower, and the cart model (about 500k triangles at full detail; LODs keep it
  lower in practice). The five spare carts in the supermarket never sleep (`can_sleep = false` on the
  cart rig), but that costs well under 1 ms.
## 2026-11-16: follow camera rises over walls instead of clipping

- **What.** `scenes/cart_camera.tscn` now has a script (`scripts/cart_camera.gd`, class `CartCamera`) and a
  `Probe` ShapeCast3D child (0.25 m sphere, mask 1 = level geometry; the cart is on layers 2 and 4 so it is
  never hit). `main.gd` still owns the orbit (`cam_yaw`, `cam_pitch`, `cam_dist`, wheel zoom) and hands
  the wanted camera position to `camera.follow()`.
- **How it avoids things.** One sphere cast from the look target (above the cart) to the wanted spot. If
  something is in the way it tries spots raised by `lift_step` (0.5 m) up to `max_lift` (2.0 m) and rises
  to the lowest one with a clear view, so it goes up and over shelves, cars and walls. Under the garage's
  low ceilings none of those clear, so it takes the lift that gets furthest out and pulls in along that
  line until the probe fits. Pulling in is instant (no clipping, ever); rising (`rise_speed`), settling
  (`settle_speed`) and moving back out (`out_speed`) are eased. All are exports on the Camera node;
  `avoid_collisions` off gives the old camera.
- **Cost.** 1 cast per frame in the open, at most 6 when blocked (lift search plus the final fit).
  Measured by `tests/camera_test.gd` (headless, 4.7 stable): average 19 to 58 us per frame per level,
  99th percentile under 0.32 ms; open-space frames are about 5 to 20 us.
- **Test.** `tests/camera_test.gd` orbits the camera through 16 headings x 5 zoom/pitch views at 2 to 5
  spots per level (next to shelves, cars, pillars, under garage decks). Clipping frames with avoidance
  off / on: sandbox 71 / 0, parking lot 8 / 0, supermarket 192 / 0, garage 168 / 0.
- **Left out.** Loose props on layer 1 (boxes, product cases, oil drums) also push the camera; spare carts
  (layers 2/4) do not, so the camera can still pass through a parked spare cart.

## 2026-11-16: push lifts the front, pull lifts the back; faster power bars

- zack chose the lift direction: a very hard **push lifts the front wheels** (wheelie) and a very hard
  **pull lifts the back wheels** onto the front casters, to break the back loose for a drift. The bare
  physics of a force at the handle (above the centre of mass) is the reverse, so `drive_height` is replaced
  by `wrist_lever` (0.4 m): each hand twists the cart about its axle line by its full power times that
  lever (push: nose up, pull: nose down), as if the wrists press or lift the bar while the arms strain.
  The push and pull themselves now act at the centre of mass height, so they don't tilt the cart on their own.
- The bars ramp twice as fast (`power_ramp` 60 to 120 N/s, at zack's request). With that, holding both
  hands lifts the front after about 1.8 s (about 240 N per hand, about 22 km/h) and the back after about
  2.1 s. Let go right away and it lands on four wheels; keep holding and it goes over. The HUD bars now
  show up to 400 N.
- Drifting itself isn't tuned yet: the back wheels lose grip when they lift, and floor friction is at the
  real-world values from the floor friction change. zack wants to drive it before deciding more.

## 2026-11-16: hand power bars replace the scroll-wheel gears and W/S

- **Controls.** Q/A (left hand) and E/D (right hand) are the only driving keys. Holding a hand's key ramps
  that hand's force from `power_base` (25 N) by `power_ramp` (60 N/s) with no cap; letting go relaxes it
  back to zero at `power_relax` (400 N/s). Push and pull share the same base and ramp (`pull_ratio` is gone).
  The scroll wheel now just zooms the camera (no Ctrl needed); 1-5, W and S do nothing.
- **Speed.** The per-gear walking speeds are replaced by one `sprint_speed` (8 m/s): a hand stops adding
  force as the cart approaches it. Holding both hands for 1.5 s from rest gives about 14 km/h.
- **Tilt is emergent.** The lift/press wrist controller and the hold-to-tip timer are removed. The hands'
  force acts at the handle (1.0 m up), above the centre of mass (0.42 m), so a very hard push pitches the
  nose down onto the front casters and the **rear wheels lift** (about 2.2 s of holding both, roughly
  150 N per hand at about 16 km/h); keep holding and it goes over onto its nose. A very hard pull pitches the
  nose up and the **front wheels lift** (about 2.8 s, roughly 190 N per hand); keep holding and it goes
  over backwards. Let go as soon as an end lifts and it drops back onto four wheels. Pulling to brake a
  rolling cart still uses the planted-arms brake (up to `brake_max`, 110 N), but a hand pulling harder than
  that wins out, so a hard yank while rolling also lifts the front.
- **HUD.** `scenes/ui/hud.tscn` has a vertical bar beside each pair of keycaps (left of Q/A, right of E/D):
  a `TextureProgressBar` above a white zero line that fills up in green while the hand pushes and one
  below it that fills down in red while it pulls, each with a `GradientTexture2D`, plus the hand's force in
  newtons. The bars show up to 250 N (their `max_value`); past that they stay full and the number keeps
  climbing. The gear meter and the W/S keycaps are gone.
- **Spin brace** is unchanged and still passes (A spin then D stops in 0.71 s, Q+D then A+E in 0.22 s).
- **Tests.** `drive_test.gd` drops the gear and W/S cases and adds: short push stays flat, hard push lifts
  the rear, hard pull lifts the front, held on they fall over, let go they land on four wheels, and
  pull = push from rest. Level tests that drive for several seconds pin the hands at a steady force
  (`power_ramp = 0`) so the long push doesn't tip the cart.
- **Which end lifts** is set by `drive_height`, the height the hands' force acts at. It is 1.0 m (the grip)
  here, which gives the physics above. zack wants it the other way round (a hard push lifts the front, a
  hard pull lifts the rear to break the back wheels loose for a drift); that follows in the next change.
- **Mobile.** The exporter adds the new keys and keeps the old ones (gears, tilt, pull_ratio) in
  `tuning/cart_tuning.json`, so the mobile game drives as before; it doesn't have the hand bars yet.

## 2026-11-16: floor friction at real-world values

- The floors were tuned by feel: tile 0.18 (very slippery), asphalt and garage concrete 0.9. They now use
  typical dry sliding friction for polyurethane/rubber caster treads: **asphalt 0.7** and **concrete 0.7**
  (typical range 0.6 to 0.8), **polished store tile 0.5** (typical range 0.4 to 0.6). Solid (walls,
  shelves, props) stays 0.5. These are textbook ranges for rubber-like treads on dry surfaces, not
  measurements of a specific cart.
- The wheel material stays at friction 1.0 so the floor sets the grip (Godot uses the lower friction of
  the pair when neither material is rough), and `rolling_resistance` stays 0.015.
- Effect: the store floor grips much better than before, so the cart slides sideways less on tile.
  All tests passed without changing any expectations. The mobile game's copy was re-exported.

## 2026-11-16: the inspector is the source of truth for cart physics

- The Godot game no longer reads `tuning/cart_tuning.json`. Every cart setting is an export on the Cart
  node or a property on its bodies in `scenes/cart/cart.tscn`, and floor friction is in
  `assets/physics/*.tres`. What the inspector shows is what runs. The values were already equal to the
  JSON's, so the cart drives exactly as before.
- Values that were hidden in code are now exports too: `hand_position`, `arm_relax_rate`, `settle_brake`
  (was 40) and `stop_delay` (was 0.25 s). The centre of mass and wheel radius are read from the Frame
  body and the wheel shapes instead of constants that had to match them.
- The mobile web game still reads the JSON (as `mobile/cart_tuning.js`). `tools/export_cart_tuning.gd`
  (File > Run in the editor, or `tools/export_cart_tuning_cli.gd` headless) writes both files from the
  scene; `tests/tuning_sync_test.gd` fails if they drift. `tools/sync_tuning.py` is retired.
- The mobile drive test could not run in the cloud (the three.js CDN is blocked); the exported values
  are unchanged.

## 2026-11-16: the other hand stops a spin

`scripts/cart.gd`: spin the cart with one hand (say A, left pull), then pull with the other (D) and it
used to keep spinning at about 120 to 160 degrees a second, because a single hand's force sits only 0.2 m
off the centre line and the walking-speed limit cut it further. Now, when the hands as a whole work against
the spin, each hand doing so braces the bar like a planted arm: a twist about the vertical of
`spin_grip` (150 N per m/s of bar sweep) times its lever, capped at `brake_max` (110 N) at that lever,
about 55 N*m. It only acts while the cart spins faster than `spin_grip_min` (0.1 rad/s), so after stopping the
cart the held key turns it the other way as usual. Applied as a pure yaw torque: an earlier try that pushed
sideways at the handle height tipped the cart onto two wheels. Results: A spin then D stops in 0.64 s,
Q+D spin then A+E in 0.20 s, all four wheels down (`tests/drive_test.gd`). Holding both pulls (braking) is
unchanged: the hands cancel, so nothing grabs. Values are in `tuning/cart_tuning.json`; the mobile game
doesn't read them yet.

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

## 2026-11-16: parking lot props at real-world scale

zack asked for the lot props to match real dimensions, checked against our cart. Sources:
cart corral, R.W. Rogers CC8030370 single-wide ([Zoro](https://www.zoro.com/zoro-select-cart-corral-single-wide-168-x-32-rwr-nat-cc8030370/i/G9867627),
[WebstaurantStore](https://argo.webstaurantstore.com/r-w-rogers-company-360-series-14-x-30-galvanized-steel-single-wide-outdoor-cart-corral-with-liability-sign/36BCC8030370.html));
parking block, [Kuhlman 8085508](https://shop.kuhlman-corp.com/concrete-parking-stop-6-l-x-5-h-7-w/p2564/);
shopping cart, [Regency 460SHPCRT64](https://www.webstaurantstore.com/regency-supermarket-grocery-cart-6-3-cu-ft/460SHPCRT64.html)
and handle heights from [FinanceBuzz](https://financebuzz.com/shopping-cart-sizes); stall, the common 9 x 18 ft code minimum.

| Thing | Real | Ours before | Ours now |
| --- | --- | --- | --- |
| Shopping cart (L x W x handle) | 1.01 x 0.60 x 1.01 m, 5" wheels; handles 0.97-1.14 m | 0.98 x 0.67 x 1.04 m, 5" wheels | unchanged |
| Cart corral | rails 4.17 m (13'8"), 14' overall, 0.81 m (32") clear, rails 0.91 m (36"), sign poles 2.44 m (8') | 4.5 m, 1.27 m clear, rails 1.0 m, sign 1.6 m | 4.17 m rails + 0.25 m flare, 0.81 m clear, rails 0.25 / 0.58 / 0.914 m, 0.8 x 0.5 m sign on 2.44 m poles |
| Parking block | 1.83 x 0.178 x 0.127 m (6' x 7" x 5") | 1.83 x 0.23 x 0.13 m | 1.83 x 0.178 x 0.127 m |
| Parking stall | 2.74 x 5.49 m (9 x 18 ft) | 2.7 x 5.5 m | unchanged (within 4 cm) |

- cart_corral 2136 tris / 82 KB, parking_block 140 tris / 9 KB. Z-fighting scan: 0 hits; the block's
  reflector strips sit 0.2 mm off the new chamfer.
- Collision shapes in `cart_corral.tscn` and `parking_block.tscn` follow the new sizes; corral
  placements kept their centres. The corral leaves about 7 cm each side of our cart.
- Left as is: the player cart is 7 cm wider than the Regency cart (other full-size carts run
  0.6-0.66 m); narrowing it changes the physics rig and the mobile version, so it is a separate
  call. Stall size and `cart_row` were already within a few centimetres.

## 2026-11-16: spare carts to crash into

- `scenes/cart/spare_cart.tscn` inherits the cart scene with `player_controlled = false` (ignores the keys,
  no hand forces, only moves when hit) and `empty_basket = true` (groceries removed at start). Five are
  placed in the supermarket under `SpareCarts`: three by the doors, one in aisle 4, one in the front aisle.
- Carts now collide with other carts: the cart bodies' collision masks include `LAYER_CART`, the Guard
  area that wakes a resting cart also watches carts, and each cart adds collision exceptions between its
  own frame, gate, child seat, seat flap, forks and wheels so it still ignores its own parts (as before, when masks left them out).
- Checked: drive test, parking lot, garage and console tests all pass; the supermarket check now also
  verifies a spare cart stays put while the keys are held and rolls away (3.3 m) when rammed.
- No new models; no z-fighting check needed.

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
