# Levels, modes and the rest of the game

Everything outside the cart physics core (see the root `CLAUDE.md`). Read the part you need; you do not need any
of this to work on how the cart drives.

## Layout of the whole game

- `scenes/main.tscn` — the sandbox level: an endless parking lot to work out the cart's physics in, with a test
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
  Console `ball` loads the arena and starts a match. The score runs on the host only, and multiplayer guests get no
  team yet.
- `scenes/levels/chain_lot.tscn` (console `chain`) — a blank asphalt lot for testing long chains of nested carts:
  a line of 10 single spare carts straight ahead of `CartSpawn` (3 m apart, facing +X, push into their backs) and 16
  more scattered at random headings under `Carts/Scattered`. Uses `scripts/main.gd`; no other props.
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
- Wheel sounds (all levels): `godot --headless --fixed-fps 120 -s res://tests/rolling_sound_test.gd`
- Sandbox screenshots (spawn, overview, test strip, 2 km out): `xvfb-run godot -s res://tests/sandbox_screenshot.gd -- <out prefix>`
- Supermarket level check: `xvfb-run godot -s res://tests/supermarket_check.gd -- <out dir>`
- Multiplayer, host plus a second Godot as guest (real time, no --fixed-fps): `godot --headless -s res://tests/multiplayer_test.gd`
- Rendezvous service, and online play by join code over WebRTC (from `services/rendezvous`, after `npm install`):
  `npm test` and `npm run test:godot`
- Garage race (console `race`, count, lock until GO, finish, bots race all ten floors): `godot --headless --fixed-fps 120 -s res://tests/race_test.gd`
- Supermarket sweep (console `sweep`, count, grab, limit, spills, bonuses, bots shop, results): `godot --headless --fixed-fps 120 -s res://tests/sweep_test.gd`
- Sweep screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/sweep_screenshot.gd -- <out dir>`
- Race screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/race_screenshot.gd -- <out dir>`
- Bot carts drive themselves in every level: `godot --headless --fixed-fps 120 -s res://tests/bot_test.gd`
- Endless sandbox (chunks load, no holes, flush edges, floors, hill): `godot --headless --fixed-fps 120 -s res://tests/sandbox_test.gd`
- Cart Ball (console `ball`, kickoff hold, bots score and keep goal, replay and skip, ball pushed, goals both ends, no-goal on the line, out of bounds, first to five): `godot --headless --fixed-fps 120 -s res://tests/cart_ball_test.gd`
- Cart Ball screenshots: `xvfb-run godot --rendering-method gl_compatibility -s res://tests/cart_ball_screenshot.gd -- <out dir>`
- Asphalt lab (ageing, crack types, repairs, replay): `godot --headless -s res://tests/asphalt_test.gd`
- Asphalt lab screenshots (stages, close-ups, height maps): `xvfb-run godot --rendering-method gl_compatibility -s res://tests/asphalt_screenshot.gd -- <out dir>`
