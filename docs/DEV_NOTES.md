# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

## 2026-11-21: wheel landings by impact speed; garage test without bots

zack asked for the slam to follow how fast each wheel hits the ground.

- **Impact speed:** each WheelSound takes the wheel's velocity into the ground along the floor's normal as it
  touches down (its last tick in the air, or the touching tick if it is still closing in), after at least 0.03 s
  off the ground. Under 0.3 m/s it touches down silently; 0.3 to 1.0 m/s is a tap; 1.0 m/s and up (about a 5 cm
  drop) is the full slam. Volume = ((impact - 0.3) / (3.0 - 0.3))^0.8, full at 3 m/s (a 45 cm drop), -1 dB at full.
- **Measured** (supermarket floor): S wheelie set down from standing 2.3 m/s, W back-up set down 1.7, a rolling
  wheelie 1.9, a hard-push wheelie 1.8; drops of 5 / 10 / 30 / 60 cm hit at 0.9 / 1.3 / 2.3 / 3.4 m/s, and the
  small rebounds after a drop at 0.2 to 0.4. So wheelies and drops slam, rebounds and small hops tap or stay quiet.
- **Sounds:** the slam is the drop recording's main hit with its bounces (`land.wav`, as before); the taps are the
  bounce (1.165 to 1.5 s) and the settle (1.545 to 1.85 s) of the same recording cut on their own and decayed
  (`land_tap_1/2.wav`, `land_taps.tres`, random pitch 1.1). Exports on WheelSound: `land_tap`, `land_slam`,
  `land_start`, `land_slam_speed`, `land_full`, `land_curve`, `land_db`. Ported to the browser.
- **Garage test:** `garage_test` failed now and then at floor 10 ("rolled 12 m downhill") before and after the
  wheel sounds. The cause is the level's three bot carts: they wander on unseeded random routes from near the roof
  and sometimes cross the test cart's aisle. The test now takes them out of the level before it starts; with them
  out it rolls the same 29.7 m on every run.

## 2026-11-21: Supermarket sweep

zack asked for a timed game mode in the supermarket in the spirit of TV grocery-sweep shows (the mechanics only: no
show name, host, branding or music). The console's `sweep` loads the supermarket (from anywhere), restocks it and
lines everyone up at the entrance; `sweep nobots` leaves the bot carts out, `sweep 60` plays a 60 s round (the
default is 1:30). In the browser it's the same command, or Level › Supermarket sweep on a phone.

- **Rules:** 3, 2, 1, GO (carts held with `ShoppingCart.locked`, as in the race), then the clock counts down. Every
  cart starts with an empty basket (`ShoppingCart.show_groceries(false)` takes its five groceries out of play: hidden,
  frozen, colliding with nothing, so the network's body lists stay the same). Roll slower than 1.4 m/s (a walk)
  with your cart's frame in a display's GrabZone and its items drop into your basket one every 0.35 s, top of the
  stack first; at most 5 of one product per cart (a pop-up says so once). Items are ordinary loose bodies once
  taken: they ride in the basket, spill when you crash or roll over, and can even land in someone else's cart. A
  cart's score is the price of what's in its basket (the same box `groceries_in_basket` uses, heaped up to 1.2 m,
  capped at 5 per product) plus its bonuses, counted in cents. When time's up the checkout table ranks everyone
  (ties: fewer items wins). A reset (P) mid-sweep leaves your basket's contents on the floor: that's the price.
- **Bonuses:** three giant inflatables (soda bottle $250 in the front corner by the produce, cereal box $150 in the
  back corner, soup can $100 by the meat): the first cart to touch one claims it and it's put away under the floor
  until the next sweep. Two bonus stations (deli counter and coffee grinder, $50 each, in the back aisle): stop in the
  taped 2 x 2 m box and hold still (under 0.25 m/s) for 3 s; once per cart.
- **Scenes:** `scenes/sweep/sweep.tscn` (`scripts/sweep/sweep.gd`, all the rules) with a 12-slot `Grid`;
  `product_display.tscn` (`ProductDisplay`: table, Title and Left labels on its price board, `Stock`, `GrabZone`
  2.6 x 1.6 x 3.2 m reaching 1.6 m into the aisle in front, `Stop` 0.95 m out for bots); 12 product scenes in
  `scenes/sweep/products/` (`Product`: name and price exported, a pack plus a label band, frozen until taken);
  `inflatable_bottle/cereal/can.tscn` (`Inflatable`, light 2 to 2.5 kg bodies with a floating BONUS price);
  `bonus_station.tscn` (`BonusStation`, an Area3D box, floor tape, a sign on a pole); the HUD
  `scenes/ui/sweep_hud.tscn` (clock, basket total, pop-ups, standings, checkout table). The supermarket instances
  the sweep and places 12 displays, 3 inflatables and 2 stations under it (104 products).
- **Products and prices** (pack sizes in metres, stock per table): cereal $4.79 (0.19 x 0.28 x 0.07, 10), coffee
  can $8.99 (r 0.065 x 0.16, 10), olive oil $12.49 (r 0.04 x 0.28, 8), detergent $13.99 (0.24 x 0.26 x 0.13, 8),
  steak $16.99 (0.22 x 0.05 x 0.15, 8), soda 12-pack $6.49 (0.40 x 0.13 x 0.27, 8), paper towels $9.99
  (0.30 x 0.28 x 0.20, 8), pasta $1.89 (10), soup $2.29 (10), cheese wheel $11.49 (r 0.11 x 0.08, 8), batteries
  $14.49 (0.12 x 0.17 x 0.035, 8), ham $19.99 (0.22 x 0.13 x 0.15, 8). Small, dear things (steak, batteries, ham)
  against big cheap ones that fill the basket (soda, towels) is the choice the round is about. Displays sit against
  the gondolas in the aisles (leaving 2.1 m of aisle), at the back against the meat fridges, by the dairy case, by
  the produce and in the front corner; the nav mesh was re-baked around them.
- **Models** (`tools/supermarket_models.py`, Blender primitives, shared materials): `sweep_table` 1.0 x 0.5 m tray at
  0.72 m on chrome legs, red skirts, price board on a pole at 1.62 to 1.92 m (204 tris, 15 KB);
  `inflatable_bottle` 1.7 m tall, 0.64 m across (24 KB); `inflatable_cereal` 0.9 x 1.4 x 0.35 m (72 tris, 7 KB);
  `inflatable_can` 1.0 m tall, 0.7 m across (432 tris, 21 KB). New shared materials: `vinyl_*` (glossy inflatables)
  and `pack_*` (the products, which are Godot BoxMesh/CylinderMesh: a box or a can plus a label band).
- **Z-fighting:** the builder's coplanar check passes for the new models (the tray rim stands 3 to 4 mm proud of the
  tray's edge, the can's rims overlap its ends instead of sharing them); the label bands are 1 mm proud of their
  packs; items sit 1.5 mm above the tray and 2 mm apart in a stack; the station's tape is 1.5 mm off the floor and
  its four strips butt without overlapping; the labels are 1.5 mm off the board.
- **Bots:** `CartBot` got an errand mode (`drive_to`, `at_errand`, `stop_errand`): drive somewhere, stop and hold
  still. In a sweep each bot heads for the display worth most to it (price times what it can still take, over the
  distance, cut to 30 % if another bot is already headed there), waits up to 6 s while its items drop in, then moves
  on. They fill $40 to $110 of cart in 45 s, so a decent run beats them.
- **Multiplayer:** the host runs the sweep; products and inflatables are level bodies, so snapshots move them. SWEEP
  (protocol version 5, after the cart flags took 4) carries scores, items left per display and a guest's own pop-ups (docs/MULTIPLAYER.md).
- **Browser:** `mobile/game/sweep.js` ports it (no multiplayer there). The level export now writes a sweep's products
  as loose props marked `frozen` (Rapier fixed bodies until taken) and a "sweep" section in `levels/market.json`
  (settings, slots, displays with their items, zones and "left" label, inflatables, stations); the live labels
  (items left, inflatable prices) are drawn by sweep.js instead of as static labels. `cart.js` got
  `dropGroceries()`, `bot.js` the errand mode, `level.js` exports `labelObject`. Zones are tested at three points
  along the frame (handle, basket, nose) and an inflatable claims on a Rapier contact with the frame.
- **Tests:** `tests/sweep_test.gd` (console, line-up, empty baskets, the count, grabbing to the limit, a spill,
  both bonus kinds, bots shop, results, restock), a sweep step at the end of `tests/multiplayer_test.gd` (the guest's
  cart is parked at the coffee: the guest sees the cans in its basket, its score, pop-ups, the sign and results), and
  a sweep block in `mobile/test/drive_test.js`. Renders: `tests/sweep_screenshot.gd`.
- **Left out for now:** a question round to earn extra time, the hidden-product bonus round, carrying the inflatables
  in the cart (touching one claims it), scooping spilled items back up off the floor, sounds for grabs and bonuses.

## 2026-11-21: Pennant flags on player carts in multiplayer

Every cart now carries a pennant flag on a tall pole, like a kids' store cart, hidden until a multiplayer game
starts; then every player's cart flies it in that player's colour so you can tell whose cart is whose.

- **Model:** `tools/blender/flag_models.py` (reuses the garage builder's `Model` and z-fighting scan) writes
  `assets/models/flag/flag.glb`: **192 tris, 11.6 KB**, z-fighting: none. Objects: `Pole` (12 mm tube, 1.75 m,
  `cart_handle` blue, as the coated steel poles on real cart flags), `Fittings` (two 40 mm clip sleeves with a jaw
  that grips the basket wire, and a top cap; `cart_plastic`) and `Pennant` (a 1.5 mm thick triangle, 0.28 m hoist by
  0.42 m fly, standing 1.5 mm clear of the tube; `flag_pennant`). Origin at the bottom of the pole.
- **Sizes:** the pole starts 0.5 m up at the basket's lower wires and its top is 2.25 m off the ground, about a head
  above the handle (1.0 m), so a flag shows over a shelf (1.8 m) or a parked car (1.4 m) from across the level.
- **Scene:** `scenes/cart/flag.tscn` (`CartFlag`, `scripts/cart/cart_flag.gd`): `colors` is the pennant palette
  (`assets/materials/flag/pennant_*.tres`: red, yellow, green, orange, purple, cyan, pink, white) and `color` picks
  one. It is instanced as `Cart/Frame/Flag` on the rear-left corner of the basket, outside the side wall, turned so
  the pennant trails behind the cart, with `visible` off. Spare and bot carts inherit it and stay without a flag.
- **No physics:** it is a plain Node3D with meshes, no body and no collision shape, under the Frame (which already
  sets its centre of mass by hand), so the cart's mass, centre of mass and tipping don't change; the camera's wall
  checks and the nest mouth never see it.
- **Net:** the host shows its own flag (slot 0) as soon as it hosts and each guest's in that guest's slot; the slot
  rides in the snapshot's per-cart flags byte (bits 1-3), so guests colour every cart the same way.
  `NetProtocol.VERSION` is 4. Leaving hides the host's flag again.
- **Browser:** the browser game has no multiplayer yet, so it shows no flag; the cart and level exports were re-run.
- Checked: `tests/multiplayer_test.gd` (host and guest see both flags, different colours, no collision), renders by
  `tests/flag_screenshot.gd`.

## 2026-11-21: Parking garage race

zack: "the parking garage should be a race. 3..2..1.. go. should be able to start race from console - goes to
parking garage". The console's `race` loads the garage (from anywhere) and lines everyone up on the roof; `race
nobots` races without the bot carts; `race` inside the garage starts over. In the browser it's the same command, or
Level › Race down the garage on a phone.

- **Scenes:** `scenes/race/race.tscn` (root script `scripts/race/race.gd`) is instanced at the end of
  `parking_garage.tscn` (its ext_resource is near the top of the file and the nodes at the bottom, away from the
  scene root and the Sun, which the unmerged Manhattan skyline branch edits). Its children are moved in the level:
  `Grid` (12 start-slot Marker3Ds, 3 abreast 1.8 m apart, rows 2.2 m apart, facing +X on the roof at x 2.7 to
  9.3, the middle column on the floor 10 aisle's centre line z = -3.3), a white start line (0.15 x 6.2 m, the aisle's
  width) and START painted ahead of the front row; `Finish`, an Area3D (2 x 3 x 22.8 m, carts' frames are layer 2)
  across the whole exit apron at x 93.1, with a chequered line (1 x 22.5 m PlaneMesh, 0.5 m squares) and FINISH
  painted past it; `BotGoal` 2.2 m past the line; `Route`, 24 Marker3Ds the racing bots drive through (three at
  each of the eight hairpin landings: in, across, and back onto the next aisle's centre line); and the HUD,
  `scenes/ui/race_hud.tscn` (a CanvasLayer: the count in the middle, the clock and a status line at the top, the
  results table). The finish chequer is painted by `tools/textures/make_race_textures.py` (64 x 1440 px PNG,
  `assets/materials/race/finish_checker.tres`); the start line uses the garage's `paint_white`.
- **Holding the carts:** `ShoppingCart.locked` makes every key read as let go, the keyboard's and a driver's
  (`controls`) alike, so the player, guests and bots are all held the same way through 3, 2, 1. `ShoppingCart.place()`
  moves a whole rig (bot carts are lined up with it, so they aren't rebuilt and the network's body lists stay valid);
  the player and guests get fresh carts on their slots.
- **Finishing:** the race ends when everyone is over the line, or 60 s (`finish_grace`) after the winner; the rest
  are DNF. Times are m:ss.cc.
- **Multiplayer:** the host runs it and sends RACE (protocol version 3) on each change and twice a second; it waits
  (up to 10 s) for every guest to load the garage before counting, so the count is shared. See docs/MULTIPLAYER.md.
- **Bots:** `CartBot` got a racing mode (`line_up`, `race_to(route)`, `stop_racing`): 4.5 m/s on the straights (the
  wanderers do 1.6), 90 N a hand, no slowing for the end of a trip, never gives up. Judgment calls from watching them:
  following the nav mesh's straight shortest path down a whole floor ran them along the centre wall until they
  stuck, so the route puts them back on each aisle's centre line after every hairpin; a 1.2 m path-point distance
  stops them overshooting a point and turning back for it; stuck detection now also counts trying to spin round with
  no room (against a wall end), for wandering bots too; and a racing bot that backs off three times on one leg
  (wedged against a parked car by another bot) is put back at the last waypoint facing the next, as racing games
  do. Three bots finish the ten floors in about 3:00 (2:57 to 3:02 in the test), so a good run beats them.
- **Browser:** `mobile/game/race.js` ports it (no multiplayer there); the race's grid, finish box, route and settings
  are in `levels/garage.json` ("race"); `cart.js` got `locked` and `place`, `bot.js` the racing mode.
- **Tests:** `tests/race_test.gd` (console, line-up, nobody moves through the count with keys held, GO, finishing,
  bots race all the way down, results, starting over), a race step at the end of `tests/multiplayer_test.gd`, and a
  race block in `mobile/test/drive_test.js`. `tests/garage_test.gd` now removes the bot carts first: one wandering on
  the roof was blocking the floor 10 roll check (it failed on main too). Renders: `tests/race_screenshot.gd`.
- **Z-fighting:** the start line sits 1.5 mm over the roof deck, the finish line 0.3 mm over the exit apron (which
  is itself 9 mm over the street), the painted words 2 cm up like EXIT; nothing else shares those planes
  (`garage_zfight_test` passes).
- **Left out:** live race positions (1st, 2nd...) while racing, a start gantry or finish banner, lap or checkpoint
  checks (the only way down is the ramps, so there's no shortcut to guard against), a best-time record.

## 2026-11-21: Parking lot background loop

The parking lot level plays zack's field recording ("parking lot back ground.wav": 9:15, stereo, 24-bit 48 kHz,
REAPER, 160 MB; kept in the project's shared files, not the repo) as a background loop.

- **Cut:** `tools/audio/make_ambience_loops.py` (numpy + ffmpeg). The recording clips (hits 0 dBFS) at 4 s, 70 s
  and 323-328 s, the last a loud event right by the mic, so the loop keeps 75-320.5 s and 332-553.5 s (the end of
  the file is 1.5 s of silence), spliced with a 4 s equal-power crossfade in a quiet stretch, and crossfaded 4 s from
  its end back into its start. DC removed, levelled to peak at -1 dBFS (RMS -23.8 dBFS). Loop: **459.0 s (7:39)**.
  The seam was checked by decoding the .ogg: the sample step across it is 0.004, smaller than ordinary steps in
  the recording, and the level either side is -30 / -29 dBFS.
- **Files:** `assets/audio/ambience/parking_lot.ogg` (Vorbis q2, 44.1 kHz stereo, 5.3 MB, imported with loop on;
  Ogg Vorbis loops sample-exact in Godot). Browser: `mobile/audio/parking_lot.mp3` (64 kb/s, 3.5 MB), the loop
  plus the 4 s that follow it, unfaded: `mobile/game/music.js` starts a copy every 459 s and crossfades the
  copies over that tail, so MP3 encoder padding can't leave a gap and Safari plays it.
- **Scene:** `ParkingLot/BackgroundMusic` (AudioStreamPlayer, autoplay, bus `Music`, `volume_db` -12, process mode
  Always so it keeps going with the console open). The `Music` bus (0 dB, into Master) is new, in
  `default_bus_layout.tres`. -12 dB is meant to sit under the wheel sounds; tune it on the node.
  Fast travel changes scene, which frees the level and its player, so it stops (tests/parking_lot_test.gd checks).
- **Browser:** the level export writes an autoplaying AudioStreamPlayer as the level's `"music"` (file, loop length,
  player + bus volume); main.js stops it on any level change and starts the new level's.
- Left as recorded: the low rumble (most of the energy is 20-200 Hz, traffic) and a faint 14 kHz whine from 5:30 on
  at about -80 dB.

## 2026-11-21: sandbox is an endless parking lot (lot-only chunks); Q and E push keys swapped

The sandbox (`scenes/main.tscn`) is now an open daytime parking lot that never ends, so the cart's physics can be
worked on with room to run. Reference: the aerial photos in `Level Reference Images/` (big, mostly empty lots,
double rows of painted stalls, light poles on the stall heads, planter islands with trees at the row ends).

- **Built on the chunk streamer.** This started as a separate endless grid (78 x 37 m blocks following the
  camera); main meanwhile got `ChunkStreamer` and multiplayer on top of it, so the lot was rebuilt as a 40 m
  chunk instead. The sandbox's `Chunks` node now streams only `scenes/sandbox/chunks/open_lot.tscn`, with the new
  `turns` export off so every chunk faces the same way and the rows read as one big lot (the browser's
  `stream.js` honours it too). Load distance 96 m, unload 120 m (main's other chunk sets used 64 / 88): at most
  33 chunks at once in `tests/sandbox_test.gd`. The store floor, old asphalt slab and yard (the home squares) are
  gone; there are no home squares now. The old lot, street, market, garage and hill chunks are untouched, ready
  to mix back in through `chunks` and `weights`; their browser exports were removed from `mobile/levels/chunks/`
  (the exporter writes them again when they're listed).
- **No seams: one ground plane.** Each chunk used to carry its own 40 x 40 m ground box, and a cart crossing
  from one box to the next at speed trips on the joint: the drive test's hard pull (backing across x = -20 at
  about 6 m/s) flipped there every time, and main's notes saw the same at the hill. The open lot has no ground
  of its own; the sandbox's `Ground` is one `WorldBoundaryShape3D` (asphalt) and the hard pull now lands on its
  wheels. Jolt makes a world boundary a square `world_boundary_shape_size` wide (2 km by default, so the ground
  ended 1 km out); `project.godot` sets it to 20 km, and the browser export uses the same size. Mixing chunks
  that bring their own ground back in would bring their seams back too.
- **Open-lot chunk:** 40 x 40 m. Two double rows of 11 stalls (2.7 x 5.5 m, as the parking lot level) along X,
  a 9 m drive aisle down the middle (z = 0, the spawn aisle) and a 4.5 m half aisle along each Z edge, so chunks
  meet in a full aisle. Each double row ends at +X in a planter island (2.4 x 11 m, streetlight and two palms,
  as `planter_island.tscn`) and a 7.3 m cross aisle runs on to the +X edge; a second streetlight stands on the
  stall heads at x = -6.2. Only 2 mm paint comes within 0.3 m of an edge. Collision: the chunk's 40 x 40 m
  ground box (asphalt) and one solid body with the island curbs, pole bases, poles and palm trunks (18 shapes).
- **Model** (`assets/models/parking_lot/open_lot/open_lot.glb`, `tools/parking_lot_models.py open_lot`): the
  existing hand-built props (stall markings, planter island, streetlight, palm tree) placed into one model and
  merged into one object per material, plus the 40 x 40 m asphalt face. 12,922 triangles, 483 KB, 12 objects /
  materials, all shared `.tres` by name. `Model` got a `by_material` mode and `at()` placement for this; the
  prop builders take an optional model to build into, and `stall_markings` a stall count (their own .glb output
  is unchanged). Merged so a chunk draws in about ten calls.
- **Z-fighting:** 0 hits. The scan is now a sorted sweep (fast enough for a whole chunk) and also measures the
  real gap between two faces; the old plane-offset test flagged palm trunk faces about 2 degrees apart only
  because their offsets happened to match at the palm's spot in the chunk.
- **Test strip** down the spawn aisle (+X), fixed in the world: speed bumps at x = 14 and 18 (0.35 x 0.05 x 6 m,
  as before), a 15 cm curb at x = 24, a 6.8 degree ramp (the old angle) at x = 28.4 to 31.6 up onto a 0.38 m
  ledge that drops off at x = 33.6, then two stacks of three cardboard boxes at x = 39. `CartSpawn` is at the
  origin facing +X; the `Chunks` grid starts at (-20, 0, -20), so the spawn is the middle of a chunk's aisle.
- **Sky:** clear day: blue procedural sky, the default sun, depth fog from 35 to 95 m in the horizon colour (the
  lower sky is the same colour, so the edge of the loaded chunks melts into it). The browser exporter now passes
  `fog_mode` and the depth range, and the browser uses three.js `Fog` for depth fog.
- **Left out:** the store tile floor (the supermarket has tile; the drive test's "tile push" and the rolling
  sound test's "sandbox tile" case are gone, the supermarket case still checks the tile sound), parked cars,
  wheel stops and cart corrals in the open lot (kept open for driving), bots (no navigation mesh).
- **Keys:** the two push keys swapped: **Q** is now the right hand's push and **E** the left hand's, so both
  left-side keys (Q push right, A pull left) turn the cart left and both right-side keys (E, D) turn it right.
  A and D are unchanged. `main.gd`, the HUD keycaps (each keeps its letter: Q reads RIGHT PUSH, E reads LEFT
  PUSH; the LEFT and RIGHT power bars still show the hands), the browser game's keys and keycaps, and the test
  labels.
- **Tests:** `drive_test` (Godot and browser) "coast then rest" now waits 30 s, not 12: with the retuned cart a
  coast from a 1 s push rolls about 15 m and is still at 0.5 m/s after 12 s on open ground; it only passed
  before because the cart ran into the old sandbox ramp. `multiplayer_test` expects chunk body poses only when
  the host's chunks have loose bodies (the open lot has none); the browser's stream check wants as many chunk
  kinds as the sandbox has, up to three. `sandbox_test.gd` adds the open lot's floor, scales its chunk limit with the unload distance and
  skips the hill when the sandbox has none. `camera_test.gd` sandbox spots sit next to a light pole (the default
  orbit passes through it with avoidance off), the ramp and an island. Playwright is installed at the repo root
  (`npm install --no-save playwright`, `npx playwright install chromium`; `node_modules/` is git-ignored), so
  the browser drive test runs here too.

## 2026-11-21: Stacked carts (nesting)

zack wants carts that nest into one another and move as a herd with very different physics (reference: a photo of a
nested row, each cart about 25 to 30 cm behind the one ahead, gates swung up, every caster on the ground).

- **Nest joint** (`scenes/cart/nest_joint.tscn`, `scripts/cart/cart_nest.gd`): a Generic6DOFJoint3D between the frame
  of the cart ahead (node_a) and the frame of the cart behind (node_b), placed at the cart behind's `pivot`
  (0.45, 0.5, 0), inside the basket ahead. Linear X is the slide: 0 is fully in, -0.8 m is just out (the nose leaves
  the basket); `linear_motor_x` with no target speed and an 80 N limit is the grip of the wire baskets, so sliding in
  or out takes a push. Linear Y/Z locked. Play: yaw +-0.12 rad with a soft spring back (40 N*m/rad), pitch +-0.05,
  roll +-0.03. Spacing 0.28 m handle to handle when fully in (renders matched the photo at 28 cm; 25 looked cramped,
  the baskets taper so the side walls don't overlap).
- **While nested**: the carts pass through each other (`ShoppingCart.ghost`: collision exceptions between every body
  of every cart in the stack, and their ground rays (wheel sounds too) look past each other), the gate of the cart
  ahead is swung up by its GateHinge motor (2 rad/s, 0.1 impulse; a stronger motor made the child seat and flap on
  the raised gate rattle forever, so the stack never came to rest), and the stack wakes, settles and stops as one
  (`cart.gd` `stack()`): any key held on any cart keeps the herd awake, and it only freezes when every cart is at rest.
- **Nesting by pushing in** (`Frame/NestMouth` Area3D on every cart, `scripts/cart/cart_nest_mouth.gd`): the last cart
  of a stack (or any loose cart) catches a nose that comes in through its open back lined up (nose at least 6 cm past
  the handle, within 9 cm of the centre line, 0.2 rad of straight, 0.12 rad of tilt, closing at 5 cm/s or more). The
  cart (and any carts nested behind it) is turned and slid onto the centre line in one rigid move, then a nest joint is
  made where it stands, its limits shifted by how far it still has to slide. Bot carts never nest.
- **Coming apart**: slid all the way out (a yank back pulls the last cart off), or a hard sideways knock passed through
  the nest (`break_impulse` 70 N*s within 60 ms). The load is read from momentum: a knock on one side of the nest
  (frames touching something solid, `contact_monitor` on the Frame) reaches the other side only through the joint, so
  that side's change of sideways momentum is the joint's load. A head-on crash never breaks a nest (the carts jam, as
  real ones do). After coming apart the carts keep passing through each other until their basket centres are 1.2 m
  apart (`ghost_clearance`), so nothing is pushed out of anything.
- **Feel** (tests/cart_stack_test.gd): a herd of 4 rolls straight at 4.5 m/s after 5 s of pushing; one hand alone
  hardly turns it (every cart's fixed rear wheels scrub), push one side and pull the other turns it about 20 degrees
  in 2 s; no measurable wobble between carts on a straight push. 1.8 to 2.4 ms per physics step for the whole parking
  lot with 7 stacked carts and 3 bots (cloud container).
- **Scenes**: `scenes/cart/cart_stack_3.tscn`, `cart_stack_4.tscn` (spare carts plus nest joints, front cart at the
  origin, nose +X). Placed: parking lot `CartStacks/ByTheSpawn` (3 carts, 2 m left of the spawn line, push in from
  behind) and `CartStacks/InCorral2A` (4 carts in corral 2A, nose to the closed end, open end toward the lot); sandbox
  `CartStack` (4 carts at (4.5, 0, 2.5)).
- **Multiplayer**: nothing new on the wire. The host runs the joints; the stack's carts are level bodies, so guests
  see them through the snapshots, and a guest's cart nests on the host like any other.
- **Browser** (`mobile/game/nest.js`): the export marks spare carts with `nested_in` and writes the nest settings to
  `cart.json` (`nest`). Rapier's prismatic joint stands in for the 6DOF joint (same slide, limits and grip as a
  velocity motor) but has no yaw or pitch play, so browser stacks bend less. Carts passing through each other share a
  collision bit instead of exceptions.
- **Z-fighting check**: nested carts are the same model offset 0.28 m along the nose. The basket walls taper, so they
  don't overlap; the lower trays and basket floors sit at the same heights, and their wires cross rather than lie on
  top of each other. No flicker showed in the renders (`tests/cart_stack_screenshot.gd`), but that is a still image:
  if the trays flicker in motion, lift each nested cart's tray a few mm in the model.
- **Left out**: no stack in the garage, market or hill yet; no way to start a level already pushing a stack (push your
  cart into one); bots don't avoid stacks.

## 2026-11-21: wheel sounds driven by each wheel's physics

zack wanted the cart sound to come from the wheels themselves. The one cart-wide RollingSound (a ray under the
middle, the frame's speed) is replaced by a sound per wheel, kept on the same speed warp zack liked.

- **Scene:** `scenes/cart/wheel_sound.tscn` (`scripts/cart/wheel_sound.gd`), instanced under each wheel body of
  `scenes/cart/cart.tscn`, with Roll and Scrub loop players and Knock and Land one-shot players. Each floor is a
  `CartFloorSound` resource (`assets/audio/cart/floors/{asphalt,tile,concrete}.tres`: physics materials, roll
  loop and level, scrub loop and level); concrete is the fallback (kerbs, props). Knocks and the landing are
  AudioStreamRandomizers (`knocks.tres`, `lands.tres`) for random pitch.
- **Per wheel, every physics tick:** a ray under the wheel (`Cart.ground_hit(wheel, gap)`, 5 mm of air at most,
  tighter than the cart's 2 cm wheels-down check so a lifted wheel spinning down doesn't count) gives contact,
  floor and normal. Roll speed = spin about the axle x radius; volume and pitch use the old curve on that
  (silent under 0.05 m/s, full at 1.5 m/s, pitch 1.0 at 1.3 m/s, 0.2 per m/s, 0.7 to 1.5), each wheel at -6 dB
  so four wheels sound like the old one. Slide = sideways speed along the axle on the ground, combined with skid
  (ground speed against roll speed, past a 15 % tolerance: rolling wheels run a few per cent off, about 10 % fast
  on Rapier's rear wheels); scrub fades in from 0.25 m/s to full at 1.5 m/s. Landing: back on the ground
  after 0.1 s or more in the air, coming down faster than 0.2 m/s (full at 1.5 m/s). Knock: a wheel that stayed
  down jolts upward by more than 0.6 m/s in one tick (kerbs, joints). One knock or landing per wheel per 0.12 s.
  Floor changes fade the old loop out before swapping. A multiplayer guest's frozen puppet cart reads its wheels'
  motion from how they moved between frames.
- **Sounds:** `tools/audio/make_cart_rolling_loops.py` now also makes `scrub_rough` (asphalt and concrete: the
  asphalt roll cut into 35 ms grains, shuffled at random rates to lose the roll's rhythm, with 30 Hz stick-slip
  chatter, low end cut and 1.5 to 6 kHz lifted) and `scrub_squeak` (tile: rubber stick-slip, a wavering 1.4 kHz
  tone in bursts a few times a second over grains of the tile roll), both 4 s loops. There is no real scrub
  recording, so these are stand-ins. `knock_1..4` are the four slab-joint clacks of the sidewalk recording (0.3 s,
  roll under them decayed away). `land.wav` is the second part of zack's new recording (`cart_drop.flac`, 0.83 to
  1.85 s: the hard hit at 0.86 s, a bounce at 1.18 s, the settle at 1.56 s), which zack heard as lifted wheels
  dropping. Its first part (0.14 to 0.8 s, a rattling roll) is too short for a loop and isn't used yet.
- **What it does in play:** a straight push rolls all four with no scrub; a wheelie quiets the lifted front pair
  and they land with the drop sound when set down; a cart spun hard on one hand or shoved sideways scrubs at the
  rear wheels; a spin on the spot (Q+D) mostly rolls (the rear wheels turn opposite ways, the casters swivel),
  scrubbing only once it is fast.
- **Browser:** `mobile/game/sound.js` ports it (`WheelSounds`): the physics part runs each physics step, the
  audio once per drawn frame; `cart.json` carries `wheel_sound` (settings, floors, files).
- **Tests:** `tests/rolling_sound_test.gd` (each level, wheelie quiet and landing, sideways shove scrubs, drop
  lands); the browser drive test checks each level the same way.
- **Left out:** no caster flutter (the physics casters don't shimmy), no rattle of the basket or groceries.

## 2026-11-21: San Francisco hill level

`scenes/levels/sf_hill.tscn` (root script `main.gd`, console `hill`): a San Francisco street that runs 445 m
downhill to the bay, after zack's skate-rogue references (its Chicago-as-SF hill floors: painted ladies stepping
down the hill, flat crests with cross streets, the steepest SF grade about 0.3, fog). You start on a flat block at
the top (y = 47.8 m) facing down the hill (+X). Then five flat crossings with four blocks of hill between them,
steeper each time: 10 %, 17 %, 24 % and 31 % (Filbert Street's 31.5 % is the steepest in SF). The last crossing
opens onto a flat block that runs into the Embarcadero seawall with the bay behind it.

- **Cross traffic:** every cross street has a lane each way (`CrossTraffic/*`, `scripts/props/traffic_lane.gd`).
  The cars are `traffic_car.tscn` instances (an AnimatableBody3D with the parking lot sedan) placed along the lane
  in the scene; each keeps its place and drives at the lane's speed, 8 m/s at the top crossing up to 13 m/s at the
  bottom one, with 3 to 5 cars a lane on a 190 m loop. They don't stop: time the crossing, or get knocked flying.
  Cars jump back to the start of the lane out in the fog at the far end.
- **Street:** `hill_block.tscn` (60 m along the slope) and `intersection.tscn` are built flat; the level tilts each
  block to its grade. 12 m curb to curb (two travel lanes and two parking lanes), 3 m sidewalks, 0.15 m curbs, a
  double yellow line, ladder crosswalks, storm drains, manholes and tree grates. The yards beside the street follow
  the slope out to 130 m so nothing shows the void.
- **Houses:** 203 row houses (`house_victorian.tscn`, `house_stucco.tscn`), 8 a side on every block, 5 a side on
  each corner of every cross street and 7 across the top. Each is painted in the inspector from shared paints in
  `assets/sf_hill/materials/` (Walls, Trim, Accent; `scripts/props/painted_house.gd`), so houses that share a paint
  share a material. They stand at the sidewalk height of their middle, on a 6 m foundation, so on the steep blocks
  they step down the hill with their foundations showing, the SF look.
- **Street furniture:** 12 street lights, 48 London plane trees, 6 hydrants (SF's white and blue high-pressure
  ones), 10 stop signs (the hill street stops, the cross street doesn't), 36 cars parked at the curb on the slope,
  nose downhill on the right.
- **Lighting:** afternoon sun from the west behind you, sky and SF fog (exponential, density 0.0045).

**Models** (`tools/sf_hill_models.py`, Blender primitives, `assets/models/sf_hill/<name>/<name>.glb`, reusing the
parking lot's `Model` builder and z-fighting scan). Materials link by name to the parking lot's `.tres` where it has
one (asphalt, concrete, curb, sidewalk, metals, paint white, roof tile, LED lens) and to `assets/sf_hill/materials/`
for the rest (`python3 tools/sf_hill_models.py --link-materials`).

| Model | Tris | KB | Size chosen | Notes |
| --- | --- | --- | --- | --- |
| hill_block | 1940 | 104 | 60 m along the slope, 18 m between lot lines | Road, gutters, curbs, scored sidewalk slabs (1 cm joints), double yellow, drains, manholes, tree grates, sloped yards |
| intersection | 3828 | 207 | 18 x 18 m crossing, cross street 100 m each way | Ladder crosswalks on four sides, cross street double yellow, yards past the ends |
| house_victorian | 1420 | 79 | 7 m wide, 15 m lot, 10.2 m to the cornice | Italianate painted lady: three-sided bay over the garage, stoop of 6 x 19 cm risers, belt courses, cornice with modillions and dentils |
| house_stucco | 1718 | 85 | 7 m wide, 10.4 m tall | Edwardian stucco: round-topped windows, iron balcony, red tile pent roof, parapet |
| street_lamp | 240 | 12 | 9.2 m pole, 2 m arm | Tapered pole, base, cobra head with lens (no light: daytime) |
| street_tree | 840 | 26 | 7.5 m | Trunk, three leaders, six leaf clumps (two-sided) |
| fire_hydrant | 644 | 21 | 0.8 m | White body, blue bonnet and caps, three outlets |
| stop_sign | 68 | 6 | 2.45 m post, 75 cm octagon | Red face 2 mm proud of the white border; STOP is a Label3D |
| seawall | 668 | 33 | 40 m long, 1.05 m over the street, railing to 2.1 m | Two placed end to end across the bottom of the street |

Judgment calls:
- The hill blocks are 60 m (shorter than real SF blocks, about 125 m) so the four grades fit in one run.
- The cross streets are flat (real ones slope too) so the crossings stay flat for the traffic.
- Houses are 7 m wide (a 25 ft lot less side gaps); the gaps between them are 16 to 50 cm.
- Corner houses show a blank side wall to the cross street.
- Wheel spin cap raised (zack's call): Jolt caps every body's spin at `max_angular_velocity`, 47 rad/s by
  default, so the cart's 6.35 cm wheels skidded above 3 m/s and a cart on the 31 % block never beat 3.5 m/s.
  `project.godot` now sets `physics/jolt_physics_3d/limits/max_angular_velocity = 120` (wheels free up to about
  7.6 m/s; it cannot be set per level). Measured top speeds over 12 s: 5.7 m/s on the 10 % block, 6.1 on the
  24 %, 6.3 on the 31 %. Higher caps were tried: 200 gives 7.5 to 8 m/s on the steep blocks, but with main's
  endless sandbox the cart rolling off the sandbox hill at 6.4 m/s nose-dives and flips at the chunk seam
  (`sandbox_test`), and every cap from 135 to 250 failed that or a garage ramp roll (`garage_test`, the cart
  drifting into the wall); 120 passes every test. 300 to 600 pitch hard at speed and often flip.
  The tuning export writes the cap as `max_angular_velocity` and the browser cart reads it.
- That skid drag had been holding the cart's wheelies down and its flat-floor speed back, so the cart is retuned
  to keep the old feel on flat floors: `wrist_lever` 0.4 -> 0.3 (ends lift at about the same hold times as
  before), the wrists now also damp the cart's pitch while a hand is held (half of `tilt_kd` each, so a wheelie
  grows steadily instead of flipping the moment an end lifts), `sprint_speed` 8 -> 5 m/s (pushing tops out at
  about 5 m/s; it was about 6 m/s, limited by skidding) and `brake_max` 110 -> 120 N. Every drive test case
  passes unchanged.
- Cars use the parking lot sedan (`parked_car.glb`) so the two levels share it.

Behaviour changes that came with it:
- `ShoppingCart.wheel_on_ground()`: a wheel counts as down when a short ray under it hits something (it used to be
  y < wheel radius, so on raised floors the HUD said 0/4 and rolling resistance switched off). The browser cart
  already did this.
- `settle_max_slope` (0.04): on anything steeper the cart left alone never settles or pins, it rolls away. Slope
  is read from the ground under the wheels. A pinned cart is also released by traffic (AnimatableBody3D) now.
- R puts the fresh cart on the floor under you (it used to drop it at y = 0), lifted to clear a slope.
- `drive_test.gd` "hard pull, held 4 s": the long pull now starts facing west. Facing east it ran off the
  sandbox's edge and fell; it only passed before because a falling wheel is below y = 0.12.
- Browser version: the export writes each `TrafficLane` (speed, length, the cars' places and shapes) and the phone
  drives kinematic cars the same way; the cart's guard sees kinematic bodies; settle and R match Godot.

Left out: power poles and overhead wires, cable cars, Muni buses, crossing lights, stairs on the steepest sidewalks,
building interiors.

Z-fighting: the builder scan reports 0 on all nine models (it first found hits on the corner boards under the
cornices, the balcony rail joints and the stop sign face, fixed). Placed objects: `tests/sf_hill_test.gd` checks no
two houses overlap and none stands in the street. The tree grates are part of the street so they lie on the slope.

Tests: `godot --headless --fixed-fps 120 -s res://tests/sf_hill_test.gd` (props, houses clear, spawn, rolling down
the 10 % and 31 % blocks, R on a slope, traffic driving and knocking the cart). Renders:
`xvfb-run godot -s res://tests/sf_hill_screenshot.gd -- <prefix>`. The camera test covers the level.

## 2026-11-21: online multiplayer by join code (phase 1)

Players can now host with a join code and join by code or from a game list, over WebRTC. The rendezvous service
runs locally for now; deploying it is phase 2. Details in `docs/MULTIPLAYER.md`.

- **Service:** `services/rendezvous/` is a Cloudflare Worker with `Room`, `Directory` and `SetupBudget` Durable
  Objects, following zack's design doc. Hosts register with `POST /host` and get a code and a private token. Hosts
  and guests then talk over room WebSockets, and the service only relays offers, answers and ICE candidates.
  Local: `npm run dev`. Tests: `npm test`, `npm run test:godot`.
- **Transport:** `scripts/net/webrtc_link.gd` is a `MultiplayerPeerExtension` over one WebRTC connection per
  guest, with negotiated channels 1 (reliable) and 2 (unordered, no resends). NetSession uses it the same way it
  uses ENet. Desktop WebRTC comes from `addons/webrtc` (webrtc-native 1.1.0-stable, MIT). Only the Windows/Linux
  x86_64 and macOS libraries are kept (28 MB of the 98 MB release).
- **Menu:** `scenes/ui/multiplayer_menu.tscn` is instanced in the Net scene and opened with M. All of its layout
  and signal connections are in the scene. The game keeps running while it's open. Cart keys are ignored while a
  text box has focus (`ShoppingCart.held`), so typing a code doesn't push the cart.
- **Judgment calls:** the host makes the WebRTC offer for each guest the service announces. Guests keep their
  signaling socket open so the service can count players and tell them when the host leaves. The host sends a
  heartbeat every 30 s to keep a public listing alive. With no TURN key the service hands out STUN only.
- **Endless sandbox in multiplayer:** `ChunkStreamer` now loads squares around every player's cart (the Net
  autoload's `carts`) and frees one only once it's far from all of them, so a guest who drives off alone still has
  ground under them on the host. Loose bodies in chunks are sent by square and index (protocol version 2). Guests
  freeze each chunk's bodies as it loads (`chunk_loaded` signal). The multiplayer test moves the guest's cart 320 m
  out and checks for ground on both machines.
- **Left out:** deploying (needs zack's Cloudflare account), TURN, and browser play (phase 3).
## 2026-11-21: endless sandbox

zack asked for the sandbox to be "more infinite, with the various elements we have so far as far as terrain is
concerned". The sandbox (`scenes/main.tscn`) now never ends: its hand-built store floor and parking lot stay at the
start, and every other 40 m square of ground around the cart is filled with a terrain chunk, built as the cart gets
near and freed once it's well behind.

- **Chunks** (`scenes/sandbox/chunks/`, each 40 x 40 m, centred on its origin, flat at height 0 along all four
  edges, so any chunk meets any other flush in any of four turns):
  - `lot.tscn`: asphalt, a double row of stalls (two `parking_row` instances, 16 stalls of 2.7 x 5.5 m) with
    planter islands at the ends, four parked cars, a cart corral in a stall, two 6 cm speed bumps.
  - `street.tscn`: a 10 m two-lane road with a crosswalk and centre dashes, 15 cm curbs and 2.8 m raised
    sidewalks with 2 m curb-cut ramps at the crosswalk and at both ends (the last 1.5 m to each edge is flat), 3 m
    grass parkways with palms, concrete plazas beyond (water machine, cart corral), two streetlights.
  - `market.tscn`: supermarket floor (tile) with three rows of gondolas, four fridge cases, produce tables, a
    display stack, four checkouts and a stack of cardboard boxes: the store without its walls.
  - `garage.tscn`: garage concrete with a raised deck 12 x 14 m, 2 m up (rooftop parking: two parked cars,
    yellow stall lines, 1 m parapets), 12 m ramps (1:6, 9.5 degrees) on and off at both ends, 7 m wide, pillars,
    floor arrows and oil drums around it.
  - `hill.tscn`: a street over a hill, crest 2.6 m, cosine profile over 17 m each side (steepest grade 24 %, 13.5
    degrees: an SF street is up to 31 %), 8 m road, 2.5 m flush sidewalks, grass banks easing down to the flat by
    18 m from the centre, palms on the flat ends. The SF hill level being built in another thread hadn't landed,
    so this is its own hill; its slopes can become another chunk once it has.
- **Hill model**: `tools/sandbox_models.py` (bpy) builds `assets/models/sandbox/hill/hill.glb` as height-field
  surfaces on a 0.5 m grid: road, sidewalk, lawn and centre line, one material each (asphalt, sidewalk, new shared
  `assets/materials/sandbox/grass.tres`, paint_white). 11,580 triangles, 474 KB. The collision is the same
  surface: `tools/make_sandbox_shapes_cli.gd` saves each mesh's trimesh as `<mesh>_shape.res`, one StaticBody3D per
  floor so each has its own physics material (and rolling sound).
- **Streaming** (`scripts/sandbox/chunk_streamer.gd`, on the `Chunks` node; its position is the grid's corner):
  squares within 64 m of the cart are loaded (nearest first, one per frame while driving, all at once at the
  start or after a jump), squares beyond 88 m are freed. 14 to 16 chunks are loaded at a time. Which chunk and which
  turn comes from a 32-bit hash of the square and `world_seed` (weights: lot 3, street 3, market 2, garage 2, hill
  2), so a square always gets the same chunk, though anything knocked over is put back when it reloads. The two
  home squares (the original 60 x 40 m plus a new 20 x 40 m concrete yard behind the store's back wall, to fill
  the second 40 m square) are left out.
- **Horizon**: the sandbox now has its own environment (the default one plus exponential fog, density 0.014, in
  the sky's horizon colour, not on the sky), and `Chunks/FarGround` (a 1.2 km plane 25 cm below the floors)
  follows the cart, so past the loaded chunks there is hazy ground rather than an edge.
- **Rolling sound**: new `assets/physics/grass.tres` (friction 0.8), listed under the cart's asphalt rumble
  (there's no grass recording). Street sidewalks and plazas and the garage are concrete, the market floor tile.
- **Day props**: the sandbox is lit by the sun, so `scenes/sandbox/props/streetlight_day.tscn` and
  `planter_island_day.tscn` inherit the parking lot's streetlight and planter island with their two shadowed spot
  lights hidden. A loaded sandbox has no lamps, which keeps it cheap.
- **Performance** (cloud, software GPU, so counts over milliseconds): sandbox at the start 417 draw calls, 201k
  triangles (the supermarket level is 1,162 and 676k); CPU 0.9 ms per frame (parking lot level 1.25 ms).
- **Browser version**: the level export writes the grid into `levels/sandbox.json` (`stream`, with a table of
  picks to check against) and each chunk to `levels/chunks/<name>.glb/.json`; `mobile/game/stream.js` streams them
  with the same hash (desktop at full reach, phones at 80 %), sharing the level's lamps, loose props and floor
  sounds. `tests/mobile_levels_sync_test.gd` checks the chunks too.
- **Checks**: `tests/sandbox_test.gd` (chunks load and unload, no holes under a 2 m grid within 40 m after four
  jumps, every chunk flat at 0 along its edges, each chunk's floor sound, and a cart walked up the hill street
  crests it and rolls down the far side). Overlap check: no collision shapes of different props overlap in any
  chunk (only inside the planter island prop, by design). No z-fighting: slabs, curbs, sidewalks and ramps sink
  1 to 5 cm into the floor below rather than sharing a face, painted lines are 4 mm boxes sunk 1 mm, the hill's
  centre line sits 4 mm above the road.
- **Left out**: roads don't line up from chunk to chunk (each chunk is turned at random); no bot carts in the
  sandbox yet (they need a navigation mesh per chunk); no lamps at night.

## 2026-11-21: multiplayer prototype (phase 0)

First step toward player-hosted multiplayer; the full plan (Cloudflare join codes, WebRTC, the browser) is in
`docs/MULTIPLAYER.md`.

- **Host-authoritative:** only the host simulates. Guests send their six keys; the host puts them in the guest
  cart's `controls` (the bot-cart hook) and sends 30 snapshots a second of every moving body. Guests freeze the
  whole level and move each body between snapshots, 100 ms behind the newest.
- **Scenes:** `scenes/net/net_session.tscn` is the `Net` autoload (settings as exports: port 24601, 7 guests,
  snapshot and input rates, interpolation delay, guest spacing) with its status label as a node. No new models.
- **Cart:** `ShoppingCart.puppet` (frozen, moved by the network, does nothing itself), `net_bodies()` (the sync
  order), `frame_velocity()` / `frame_spin()` (the HUD and rolling sound use these so a guest sees the host's
  speed). Not ported to `mobile/game/cart.js`: puppets are network-only, and the browser has no networking yet.
- **Console:** `host`, `join`, `leave`, `net` (Net adds them through the console's now-public `add_command`);
  fast travel is host-only while joined. While the console is open on the host the game pauses for everyone.
- **Judgment calls:** our own byte protocol over a polled `MultiplayerPeer` instead of Godot RPCs or
  `MultiplayerSynchronizer`, so the JavaScript game can speak it later. ENet is turned off throttling unreliable
  packets to a guest (it throttled snapshots for seconds after a guest paused to load a level), and the host only
  sends snapshots to guests that report they've loaded the current level.
- **Left out:** WebRTC, join codes and Cloudflare (phases 1-2), browser play (phase 3), prediction, player spawn
  markers (guests line up 1.2 m apart to the right of `CartSpawn`; in the supermarket that faces the second cart
  into a box display).

## 2026-11-21: bot carts (first pass)

Unmanned carts that drive themselves around the supermarket, parking lot and garage, three per level, as a first
step toward bots that play the game (and later, networked players driving carts the same way).

- **Same controls as a player:** a bot never moves the cart directly. `ShoppingCart` now reads its six keys through
  `held(action)`: the keyboard when `player_controlled`, otherwise the `controls` a driver sets each physics step
  (`cart.driver`, null for a spare cart). `CartBot` (`scripts/cart_bot.gd`) holds and lets go of Q/A/E/D the way a
  player taps them: each hand has a wanted force (forward speed toward `cruise_speed` plus a steering share),
  and its key is held while the hand's power bar is below that force. So the power ramp, wrist lever, braking with
  planted arms, spin brace and getting back up all apply to bots unchanged. A networked player can later fill
  `controls` from the wire instead.
- **Scene:** `scenes/cart/bot_cart.tscn` inherits `cart.tscn` (empty basket, not player controlled) and adds a
  `NavPoint` marker on the Frame at the middle of the basket (0.5 m ahead of the handle) with a
  `NavigationAgent3D` under it, and the `Bot` node (CartBot, physics priority -1 so its keys are in before the cart
  steps). Levels place bots as `BotCarts/BotCart<n>` instances; their transform is where they start.
- **Navigation:** each of the three levels has a `Navigation` NavigationRegion3D with its mesh saved to
  `assets/navigation/<level>.tres`; the level root is in the `navigation_geometry` group, so the editor's Bake button
  and `tools/bake_navigation_cli.gd` parse the same static colliders (carts and loose props are rigid, so left
  out). Settings: cell 0.1 m x 0.05 m (project navigation cell size set to match), agent radius 0.7 m (half the
  cart's 1 m length plus margin; supermarket aisles are 2.4 m), height 1.1 m, max climb 0.05 m (the 0.127 m
  parking blocks and the curbs block; 0.1 m let the bake climb onto the blocks), max slope 20 degrees (garage
  ramps are gentle). The garage bake is limited to the structure (filter AABB), so bots don't head off down the
  street. Polygons: supermarket 344, parking lot 615, garage 1,136. Re-run the bake after moving anything solid.
- **Wandering:** pick a random reachable spot (path end within 0.3 m of it, so not a checkout counter top or car
  roof) between 6 and 35 m of path away, drive there slowing for corners, stand 0.5 to 3 s holding the cart
  against rolling (garage ramps), repeat. Stuck while pushing for 1.5 s: pull back 1.2 s and re-plan; three
  back-offs or too long on one trip: pick another spot. Fallen over: let go, then hold both hands to haul it up.
- **Judgment calls:** max hand power 70 N, well short of a wheelie. Cruise 1.6 m/s, a brisk walk. No avoidance
  between carts yet: bots and the player bump into each other and the back-off sorts it out.
- **Browser version:** the level export adds `bot_carts` and `navmesh` (world-space vertices and polygons) to each
  level JSON and the CartBot settings to `levels/cart.json` (`bot`). `mobile/game/bot.js` ports `cart_bot.gd`;
  `mobile/game/nav.js` stands in for the navigation server (A* over the polygons through edge midpoints, then the
  funnel; on 120 random paths, all but 5 came within 10 % of Godot's path length, the worst 1.9 times as long) and NavigationAgent3D.
- **Tests:** `tests/bot_test.gd` (Godot) and the bot block in `mobile/test/drive_test.js` run each level's bots for
  60 s: every bot covers ground, finishes or gives up on a trip, stays on the level and ends on its wheels.
  In a 2-minute Godot run, bots covered 100 to 140 m each with 3 to 9 trips reached.
- **Left out:** steering around other carts (agent avoidance), bots in the sandbox (no navigation mesh), any goal
  beyond wandering (shopping lists, following the player, racing), respawning a bot that leaves the level.
## 2026-11-21: cart rolling sounds from zack's recordings

zack found three recordings of a real shopping cart (asphalt, a smoother roll, a sidewalk with joints). The cart
now plays them as it rolls, in Godot and in the browser version.

- **Loops:** `tools/audio/make_cart_rolling_loops.py` (numpy + ffmpeg) cuts one steady stretch of each recording
  (kept losslessly in `tools/audio/recordings/`), mixes it to mono, crossfades 0.5 s of tail into head so it loops
  without a click, and levels each to -20 dBFS RMS. Asphalt: `cart_asphalt.flac` 1.5 to 13.5 s. Tile: the
  smoother `cart_rolling.flac` 3 to 15 s (the quietest recording, about 10 dB under the asphalt one). Concrete:
  `cart_sidewalk.flac` 0.3 to 7.8 s, the slab joints clacking (it's only 8 s long). Stretches were picked from a
  0.25 s loudness and crest scan, away from the pick-up and the stop. Godot gets `assets/audio/cart/roll_*.ogg`
  (Vorbis q5, 80 to 130 KB, imported with loop on), the browser `mobile/audio/roll_*.wav` (22 kHz 16-bit,
  320 to 520 KB; WAV because MP3 pads its ends and Safari won't play Ogg, so a WAV is the one format that loops
  gaplessly everywhere). Seam check: the jump at the loop point is within normal sample-to-sample change.
- **Scene:** `Frame/RollingSound` in `scenes/cart/cart.tscn` (`scripts/cart/cart_rolling_sound.gd`): a
  `FloorProbe` RayCast3D down through the middle of the wheelbase (0.46 m ahead of the handle, 0.3 m up, 0.6 m
  long, world layer only) and one AudioStreamPlayer3D per ground (`scripts/cart/rolling_surface_sound.gd`), each
  listing the physics materials it is for: Asphalt (asphalt.tres), Tile (tile.tres, -5 dB), Concrete
  (concrete.tres, -2 dB; also the fallback for kerbs, props and any other floor). So the parking lot plays
  asphalt, the garage concrete, the supermarket tile, and the sandbox tile or asphalt depending on where you are.
  Spare carts have it too, so a shoved cart rolls audibly.
- **Feel:** silent under 0.05 m/s, full volume from 1.5 m/s (gain = (speed / 1.5)^0.7), pitch 1.0 at the
  recordings' pace (guessed at a 1.3 m/s walk), 0.2 per m/s either side, clamped to 0.7 to 1.5. Ground changes,
  lift-off and landing crossfade over 0.15 s. A cart in the air or lying on its side (the probe hits nothing)
  goes quiet. Each player starts at a random point in its loop so carts side by side don't sound in step.
  `unit_size` 4 m, `max_distance` 40 m.
- **Browser:** `mobile/game/sound.js` ports it with Web Audio (one looping source, gain and panner per sound,
  listener on the camera). The level export now tags each static collision shape with its physics material
  (`surface`), and `cart.json` carries the RollingSound settings, so the phone picks the same loop. Sound
  starts with the Start tap (browsers need one) and fades out while the menu or console is open.
- **Tests:** `tests/rolling_sound_test.gd` (every level: right loop, louder and higher when faster, quiet at
  rest); the browser drive test checks the same per level.
- **Left out:** no scrape sound for a fallen cart sliding, no clatter for hits or the groceries, no separate
  sound per wheel. Pitch-shifting a single recording is a stand-in for real speed-dependent rolling; if it sounds
  thin at a run, the next step is a second, faster recording per ground crossfaded by speed.

## 2026-11-21: parking lot cart corral moved off the sidewalk

The fifth corral (`CartCorrals/CorralSidewalk`) stood on the storefront sidewalk, which a real lot
would not do. It is now `CartCorrals/Corral1East` in an empty marked stall of row 1, east side
(stall centre x = 9.45, between the blue and white parked cars), open end facing the fire lane like
the other corrals. Centre z = -3.4, so its closed end sits 5 cm clear of that stall's parking block
(corral -5.49 to -1.32, block face at -1.27); no overlaps with the neighbouring cars (about 0.8 m
each side). The cart storage rows against the store wall stay where they were. Browser level
(`mobile/levels/plot.*`) re-exported.

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

## Multiplayer guest spawns (2026-11-21)

- A level can have a `PlayerSpawns` node with `Spawn1`..`Spawn7` Marker3Ds; guest slot N starts at SpawnN (wrapping if
  there are fewer). Levels without it keep the old row beside `CartSpawn`.
- Supermarket: the old row put the first guest at (-14, 0, 1.2) facing a box display 2 m ahead. The seven markers
  are in the open aisle on the host's left, at x = -14 / -11.5 / -9 / -6.5 and z = -1.2 / -2.4, all facing +X like
  `CartSpawn`. Each was checked with a shape query (cart footprint plus 0.3 m margin): nothing overlaps, and the
  aisle ahead is clear to about x = -6.
- `tests/multiplayer_test.gd` checks the guest starts at Spawn1 where a level has markers.

## 2026-11-21: Manhattan skyline round the parking garage (local only)

- **What.** The parking garage now stands in Bryant Park, midtown Manhattan, built from zack's Google Earth
  3D tiles (`~/Pictures/blender/MANHATTAN`: 41 OBJ tiles of ~600k triangles, each with its 8K PNG; the
  "missing" texture of tile 40 is `8fd1b8414f3a_gltf_tile_40.png` beside it, named in its `.mtl`). The lot
  is lined up with the street grid (turned 30.3 degrees), between 6th Ave and the library, 40th to 42nd St;
  the park inside the lot is cut out, so the level's street slab is the ground and the park's plane trees
  stand round its edges.
- **How.** `tools/manhattan_skyline.sh` (Blender + gltfpack + `tools/manhattan_skyline_scene.py`):
  buildings within 250 m are real meshes with the tiles' own photo UVs (cut, welded, thinned by gltfpack as
  far as the UV islands allow: 1.13M -> ~470k triangles, 4K photos), as unshaded, double-sided materials,
  slightly warm and dim to sit in the evening light, casting no shadows. Everything further out is one 8K
  panorama rendered at full detail from 8 m up in the middle of the lot, laid over the sky by
  `scenes/environment/skyline_sky.gdshader` (the old procedural sky, same settings, rewritten as a shader so
  it can take the panorama). The garage's `Skyline` node (`scripts/levels/optional_backdrop.gd`) instances
  `assets/manhattan_skyline/manhattan_skyline.tscn` and hands the panorama to the sky if the files exist.
- **Why local only.** Google's Map Tiles terms don't allow extracting the 3D tiles or using them outside
  Google Maps, and this repo is public, so the baked skyline stays out of git (`.gitignore`) and out of the
  browser game (`mobile_export_skip` group on `Skyline`; the exporter also reads the garage's sky shader's
  colours, so the browser garage's sky is unchanged). Without the files the garage is exactly as before.
  For a shipped game the skyline needs replacing with our own buildings.
- **Cost** (roof view, 1600x900, `tests/skyline_screenshot.gd`): 492 -> 494 draws, 467k -> 940k triangles.
  The panorama is free per frame. No collision on the city: the cart still only has the level's slab.
- **Tried and dropped.** Decimating the tiles with their photo UVs stalls at ~30-40 % (thousands of tiny
  UV islands); simplifying the bare shape and re-baking the photo onto new UVs (voxel remesh or gltfpack,
  then Cycles selected-to-active) smeared the photos, because the simplified walls sit metres off the
  photogrammetry.
- **Judgment calls.** The spot (Bryant Park: about the size of the level's 170 x 90 m slab, open sky over it);
  ground level -52.5 in tile coordinates (the lawn's lowest points); 250 m as the near/far split; panorama eye
  8 m (halfway up the garage), so from the roof or the street the far skyline is up to ~2 degrees off.
