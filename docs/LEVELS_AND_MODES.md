# Levels, modes and the rest of the game

Everything outside the cart physics core (see the root `CLAUDE.md`). Read the part you need; you do not need any
of this to work on how the cart drives.

## Layout of the whole game

- `scenes/main.tscn` — the old sandbox (still what drive_test and most tests load; the console `sandbox` and the game start now go to `lot90.tscn`): an endless parking lot to work out the cart's physics in, with a test
  strip (speed bumps, a curb, a ramp up to a ledge, boxes) down the spawn aisle and `CartSpawn`. Its `Chunks` node
  (`scripts/sandbox/chunk_streamer.gd`) fills a 40 m grid around the cart with terrain chunks from
  `scenes/sandbox/chunks/`, picked by a hash of the square so the layout never changes. The sandbox uses only
  `open_lot.tscn` with `turns` off, so every stall row runs along X; the other chunks (parking lot with cars,
  street, supermarket floor, garage deck, hill street) are kept for mixing back in. Every chunk is 40 x 40 m,
  centred on its origin, and flat at height 0 along its edges so any chunk meets any other in any turn. Add a
  chunk by adding it to the `Chunks` node's `chunks` and `weights`. `tools/parking_lot_models.py open_lot` builds
  the open lot; `tools/sandbox_models.py` builds the hill (then `tools/make_sandbox_shapes_cli.gd`).
- `scenes/levels/<name>.tscn` — further levels. Their root script extends `res://scripts/main.gd`,
  which supplies cart spawning, the follow camera, input and the HUD. A level scene places its own
  `CartSpawn` marker; if it has no `WorldEnvironment`, `Camera` or `HUD` node, `main.gd` adds the
  shared default scene for each.
- `scenes/cart/cart.tscn` — the cart rig (frame, gate, casters, wheels, hinge joints, groceries, model). Keys: Q/A left hand push/pull, E/D right; holding sets how hard, tapping moves the hand out along the bar (see `scripts/cart.gd`).
  `scenes/cart/spare_cart.tscn` — the same cart, empty and not player controlled, to place in levels.
  `scenes/cart/bot_cart.tscn` — a cart driven by a bot (`scripts/cart_bot.gd`) pressing the same keys a player does;
  place instances under a level's `BotCarts` node. Bots need the level's `Navigation` region: re-bake it with
  `godot --headless -s res://tools/bake_navigation_cli.gd` after moving anything solid.
  `scenes/cart/cart_stack_3.tscn` / `cart_stack_4.tscn` — spare carts nested into each other (`nest_joint.tscn`,
  `scripts/cart/cart_nest.gd`); any cart pushed lined up into the back of another nests (`Frame/NestMouth`), a yank
  back pulls it off.
- `scenes/net/net_session.tscn` — the `Net` autoload: host-authoritative multiplayer (`scripts/net/`). Guests'
  carts are driven through `controls` like bot carts and start at the level's `PlayerSpawns` Marker3Ds (one per guest
  slot) or beside `CartSpawn`; guests only show the host's snapshots. Plan and wire format:
  `docs/MULTIPLAYER.md` (bump `NetProtocol.VERSION` when a message changes). Online play uses WebRTC
  (`scripts/net/webrtc_link.gd`, desktop plugin in `addons/webrtc/`) introduced by the rendezvous service in
  `services/rendezvous/` (Cloudflare Worker; `npm run dev` there runs it locally). M opens the Multiplayer menu
  (`scenes/ui/multiplayer_menu.tscn`). Don't deploy the Worker or create Cloudflare resources without asking zack.
- `scenes/race/race.tscn` — a race (`scripts/race/race.gd`): a `Grid` of start-slot Marker3Ds, a `Finish` Area3D with
  its painted line and `BotGoal`, a `Route` of Marker3Ds the racing bots follow, and the countdown/results HUD
  (`scenes/ui/race_hud.tscn`). The parking garage has one (roof to street exit). The console's `race` (or
  `race nobots`) loads the garage and starts it; in multiplayer the host starts it and guests follow (RACE message).
- `scenes/sweep/sweep.tscn` — a supermarket sweep (`scripts/sweep/sweep.gd`): a `Grid` of start slots, and the level
  puts `ProductDisplay`s (sale tables with a stack of `scenes/sweep/products/*.tscn`, each with its name and price
  exported) under `Displays`, giant `Inflatable`s under `Bonuses` and `BonusStation`s under `Stations`; HUD
  `scenes/ui/sweep_hud.tscn`. The supermarket has one. Console `sweep` (`sweep nobots`, `sweep 60`) loads it and
  starts; in multiplayer the host runs it (SWEEP message). Rebuild its models with `tools/supermarket_models.py`.
- `scenes/levels/cart_ball_arena.tscn` — Cart Ball, a car-soccer style mode: a 30 x 20 m walled asphalt arena (fenced
  concrete barriers, cut corners) with a Green goal and a Red goal (`scenes/ball/goal.tscn`; its `Inside` Area3D only
  catches a ball wholly over the line) and the big ball (`scenes/ball/ball.tscn`, 1.3 m, 4 kg, on layer 3). The match
  is `scenes/ball/cart_ball.tscn` (`scripts/ball/cart_ball.gd`, HUD `scenes/ui/cart_ball_hud.tscn`): you play Green
  against two Red bots (`scenes/ball/ball_bot_cart.tscn`, `scripts/ball/ball_bot.gd`: a striker and a keeper, pressing
  the same keys a player does; where each stands in the arena is its kickoff spot). Kickoff counts 3, 2, 1 with every
  cart held; a goal shows GOAL!, then a slowed replay of the last seconds from the `ReplayCamera` (a push key skips
  it), then a new kickoff. First to `goals_to_win` (5) wins; the clock counts up unless `match_time` sets a limit.
  Console `ball` loads the arena and starts a match. Multiplayer: the host plays Green and guests join Red, Green,
  Red... kicking off from the arena's `GreenSpots` / `RedSpots`; the Red bots play only while no player is on Red
  (else they wait at `Bench`). Each kickoff's count waits (up to `guest_wait`) for guests to load the arena. The host runs the match and sends it to guests (BALL message); the replay moves the
  real bodies on the host, so guests see it through the snapshots.
- `scenes/levels/cart_collect_lot.tscn` (console `collect`) — cart collection, a 5 minute round in the 90 degree
  lot (it inherits `lot90.tscn`) with 30 loose carts scattered under `Carts` and the parking lot's store front along
  the -X edge. Ram a cart from behind and it nests onto the front of yours (the ordinary nest physics); push the chain
  into the store's CART RETURN door (`scenes/collect/cart_door.tscn`): your cart stops at its `DropSensor` (the
  `StopBar` behind it holds back every cart but the loose ones), the carts you were pushing let go, roll on `Inside`
  and cash in, then stand in rows in the store room. A drop of n carts scores 10 for the first and 5 more for each one
  after (10, 15, 20...). The round is `scenes/collect/cart_collect.tscn` (`scripts/collect/cart_collect.gd`, HUD
  `scenes/ui/collect_hud.tscn`, the sweep's HUD with its own captions). The store front's one solid block is swapped
  for shapes around the opening in the level. Multiplayer: the host runs it (COLLECT message), every guest plays.
- `scenes/levels/downhill_highway.tscn` (console `downhill`; `race downhill` races it) — a 600 m dead-straight two-lane
  highway down a grassy canyon at 30 %, Jersey barriers both sides, for multiplayer races (players only, no
  bots). The road is CSGPolygon3D cross-sections swept along the `Road` Path3D; after editing it re-bake the collision
  with `godot --headless -s res://tools/bake_downhill_collision_cli.gd`.
- `scenes/levels/chain_lot.tscn` (console `chain`) — a blank asphalt lot for testing long chains of nested carts:
  a line of 10 single spare carts straight ahead of `CartSpawn` (3 m apart, facing +X, push into their backs) and 16
  more scattered at random headings under `Carts/Scattered`. Uses `scripts/main.gd`; no other props.
- `scenes/levels/generated_lot.tscn` (console `lotgen`, `lotgen 45 7 oneway` for 45 degree stalls, seed 7, one-way
  aisles) — a parking lot laid out on load by `LotGenerator` (`scenes/lot_gen/lot_generator.tscn`): stall rows,
  aisles, curbed end islands, wheel stops, striping, a perimeter curb and cart corrals. `CartSpawn` is just outside
  the entrance on the lot's -X edge.
- `scenes/levels/lot90.tscn` (console `sandbox`; the game starts here) — a 60 x 40 m 90 degree lot from the same generator, paved with 24
  aged asphalt sections (year 12) whose sims paint, wear and crack the stall lines; the traffic's wheel paths run down
  the aisles. Baked into the scene: re-run `tools/bake_lot_cli.gd` and the asphalt section bake after changing it.
- `scenes/lot_gen/lot_lab.tscn` (console `lotlab`) — the parking lot lab: the LotGenerator's settings (angle,
  aisles, lot size, islands, stops, curb, corrals, seed) on a panel, rebuilt live, top view or 3D orbit, with the
  sizes used next to Table 1 of the parking lot PDF.
- `scenes/asphalt/asphalt_lab.tscn` — the 2D asphalt lab: a road section ageing year by year (the crack types in
  zack's Asphalt Cracking Quick Guide, potholes) and being repaired (crack filling, pothole fill, heavy patches, chip
  seal, overlay), drawn as a colour map and a height map (`AsphaltSim.bake_height()` gives real heights in metres for displacement;
  the lab's "Colour + relief" view shades it). `scripts/asphalt/asphalt_sim.gd` simulates,
  `asphalt_canvas.gd` draws, `assets/asphalt/asphalt_base.gdshader` is the surface. Prototype for procedural roads.
- `scenes/props/` — reusable props. `scenes/environment/` — shared sky and sun, and the garage's sky shader
  (`skyline_sky.gdshader`). `assets/manhattan_skyline/` (not in git) — the garage's Manhattan skyline from
  zack's Google Earth tiles, made by `sh tools/manhattan_skyline.sh`; the garage shows it only where it exists.
  `scenes/ui/hud.tscn` — the driving HUD, styled after US road signs (MUTCD, `Reference Images/UI/`; fonts and
  colours in `assets/ui/road_sign_theme.tres` and the scene's styleboxes). `scenes/ui/console.tscn` — the debug console autoload
  (tilde key; fast-travel destinations are its `destinations` export). `scenes/cart_camera.tscn` — the follow camera (`scripts/cart_camera.gd` lifts it over walls, see its exports).
- `assets/physics/*.tres` — shared physics materials (tile, asphalt, solid).
- `assets/audio/cart/` — the cart's wheel sounds (rolls, scrubs, knocks, landing), cut from zack's recordings by
  `tools/audio/make_cart_rolling_loops.py`. Every wheel has a
  `WheelSound` (`scenes/cart/wheel_sound.tscn`) driven by that wheel's spin, slide and contact; the floor's
  physics material picks a `CartFloorSound` (`assets/audio/cart/floors/*.tres`).
- `assets/audio/ambience/` — level background loops (`tools/audio/make_ambience_loops.py`), played by an autoplaying `AudioStreamPlayer` on the `Music` bus (`default_bus_layout.tres`),
  e.g. the parking lot's `BackgroundMusic`.
- `scripts/` — behaviour scripts for the scenes above.
- `tools/` (repo root) — Blender builder and export scripts. `docs/DEV_NOTES.md` — dev notes.

## Whole-game checks (only when you changed that part of the game)

From `shopping-cart/`:

- Drive test (headless): `godot --headless --fixed-fps 120 -s res://tests/drive_test.gd`
- Screenshot: `xvfb-run godot -s res://tests/screenshot.gd -- out.png`
- Console test: `godot --headless --fixed-fps 120 -s res://tests/console_test.gd`
- Camera never clips into levels (all levels): `godot --headless --fixed-fps 120 -s res://tests/camera_test.gd`
- Parking lot level test: `godot --headless --fixed-fps 120 -s res://tests/parking_lot_test.gd`
- Coast highway level test: `godot --headless --fixed-fps 120 -s res://tests/coast_test.gd` (the level is generated
  by `tools/coast_models.py`; its docstring lists the steps to rebuild it)
- Stacked carts (nest, herd, pull off, knocks): `godot --headless --fixed-fps 120 -s res://tests/cart_stack_test.gd`
- Long cart chains in the chain lot (plough the line, turn, rest, pull off): `godot --headless --fixed-fps 120 -s res://tests/chain_lot_test.gd`
- Parking lot generator (Table 1 sizes at every angle, stops, islands): `godot --headless -s res://tests/lot_generator_test.gd`
- Parking lot generator screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/lot_generator_screenshot.gd -- <out dir>`
- Wheel sounds (all levels): `godot --headless --fixed-fps 120 -s res://tests/rolling_sound_test.gd`
- Sandbox screenshots (spawn, overview, test strip, 2 km out): `xvfb-run godot -s res://tests/sandbox_screenshot.gd -- <out prefix>`
- Supermarket level check: `xvfb-run godot -s res://tests/supermarket_check.gd -- <out dir>`
- Multiplayer, host plus a second Godot as guest, with the garage race, sweep and downhill race (real time, no --fixed-fps): `godot --headless -s res://tests/multiplayer_test.gd`
- Rendezvous service, and online play by join code over WebRTC (from `services/rendezvous`, after `npm install`):
  `npm test` and `npm run test:godot`
- Downhill highway race (`race downhill`, drives down to the finish): `godot --headless --fixed-fps 120 -s res://tests/downhill_test.gd`
- Garage race (console `race`, count, lock until GO, finish, bots race all ten floors): `godot --headless --fixed-fps 120 -s res://tests/race_test.gd`
- Supermarket sweep (console `sweep`, count, grab, limit, spills, bonuses, bots shop, results): `godot --headless --fixed-fps 120 -s res://tests/sweep_test.gd`
- Sweep screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/sweep_screenshot.gd -- <out dir>`
- Race screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/race_screenshot.gd -- <out dir>`
- Bot carts drive themselves in every level: `godot --headless --fixed-fps 120 -s res://tests/bot_test.gd`
- Endless sandbox (chunks load, no holes, flush edges, floors, hill): `godot --headless --fixed-fps 120 -s res://tests/sandbox_test.gd`
- Cart Ball (console `ball`, kickoff hold, bots score and keep goal, replay and skip, ball pushed, goals both ends, no-goal on the line, out of bounds, first to five): `godot --headless --fixed-fps 120 -s res://tests/cart_ball_test.gd`
- Cart Ball multiplayer, host plus a second Godot as guest (real time, no --fixed-fps): `godot --headless -s res://tests/cart_ball_multiplayer_test.gd`
- Cart Ball screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/cart_ball_screenshot.gd -- <out dir>`
- Cart collection (console `collect`, count, nest two carts, drop at the door, points, can't drive in, time's up): `godot --headless --fixed-fps 120 -s res://tests/cart_collect_test.gd`
- Cart collection multiplayer, host plus a second Godot as guest (real time, no --fixed-fps): `godot --headless -s res://tests/cart_collect_multiplayer_test.gd`
- Cart collection screenshots: `xvfb-run godot --rendering-method gl_compatibility --fixed-fps 120 -s res://tests/cart_collect_screenshot.gd -- <out dir>`
- Asphalt lab (ageing, crack types, repairs, replay): `godot --headless -s res://tests/asphalt_test.gd`
- Asphalt lab screenshots (stages, close-ups, height maps): `xvfb-run godot --rendering-method gl_compatibility -s res://tests/asphalt_screenshot.gd -- <out dir>`
