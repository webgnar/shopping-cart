# Shopping Cart

The game lives in `shopping-cart/` (Godot 4.7, Jolt physics). `mobile/` is the in-browser version (three.js +
Rapier, phones and computers; see `mobile/README.md`), `tools/` holds Blender scripts. The Godot scenes are the
source of truth: `shopping-cart/tools/export_cart_tuning.gd` copies the cart's settings to the browser game
(`tuning/cart_tuning.json`, `mobile/cart_tuning.js`) and `shopping-cart/tools/export_mobile_levels_cli.gd` copies
every fast-travel level and the cart rig (`mobile/levels/`). Never read those files from the Godot game. After
changing the cart or a level, run both exports (the sync tests below fail until you do).

## Commits

zack wants every commit to show their GitHub name and profile picture, and Claude only once:

- Claude stays the commit author. End every commit message with zack as co-author, using their GitHub
  noreply address so the avatar links:
  `Co-authored-by: webgnar <124617425+webgnar@users.noreply.github.com>`
- Do not add a `Co-Authored-By: Claude ...` trailer: Claude is already the author, and a second Claude line
  shows two Claude avatars. The `Claude-Session:` link line may stay.
- Keep merging pull requests with a normal merge (not squash).

## How we build: scenes first

This is a Godot project, so everything is built as scenes (`.tscn`) made of Godot nodes that can be
opened and edited in the editor. Do not build content procedurally in GDScript.

- **Levels, props, lights, cameras and UI are nodes in a scene.** Geometry is `StaticBody3D` /
  `RigidBody3D` with `CollisionShape3D` and `MeshInstance3D` children; lighting is `WorldEnvironment`
  and light nodes; UI is `Control` nodes in a `CanvasLayer`. Physics joints are joint nodes with
  `node_a` / `node_b` set in the scene.
- **Reusable things are their own scene**, instanced where they are used (the cart, a cardboard box,
  a shelf, a parked car). Edit the scene once and every copy updates.
- **Scripts are for behaviour only.** A script reads its nodes (`$Frame`, `%Stats`, `@export` node
  references) and drives them; it does not `new()` nodes, shapes, meshes or materials to lay out the
  world. Signals are connected in the scene where possible.
- **Settings go on the node or resource**, not in code: masses, colours, sizes, materials and
  styleboxes are set in the inspector. Shared resources (physics materials, themes) are `.tres` files.
- **Spawn points and other positions are `Marker3D` nodes**, not coordinates in a script.
- Instancing a prebuilt scene from code (`preload(...).instantiate()`) is fine for things that appear
  at runtime, such as respawning the cart.
- **What the inspector shows is what runs.** No file or script overrides node settings at start. Values
  that are fixed in code are `const`s; anything someone might tune is an `@export` or a node property.

## How we make models

- **Build models in Blender from primitives** (boxes, cylinders, beams, tubes) in a Python builder
  script under `tools/`, run headless (`blender -b -P tools/<builder>.py`), exporting a `.glb` to
  `assets/models/<name>/`. zack prefers hand-built models over generated or AI meshes. Small props
  that are just a box or two can stay as Godot primitive meshes in the scene.
- **Real-world scale in metres.** Use the real size of the thing (a parking bay is about
  2.5 x 5 m, a supermarket shelf about 1.8 m tall, a car about 4.5 m long) and check it against
  the cart and the level. Write down each size you chose in `docs/DEV_NOTES.md`.
- **Facing and origin:** a model's front faces Godot -Z (Blender +Y) with its origin at the bottom
  centre, unless its builder documents otherwise. The cart is the existing exception: its nose
  is +X and its origin is on the ground under the handle (see `tools/rig_cart.py`).
- **Moving parts are their own objects** with the pivot on the hinge or axle (doors, gates, wheels),
  as `tools/rig_cart.py` does for the cart.
- **One material per object**, named after a shared Godot material. Add a shared `.tres` rather
  than a material per model; plain `StandardMaterial3D` colour, metallic and roughness covers
  most props.
- **Detail from the start.** Build each model at its finished level of detail (the real parts,
  separate materials where the real object has them) instead of planning a second pass.
- **No z-fighting, anywhere.** Lift a flush face about 0.15 mm clear, and check placed objects
  for overlaps and clipping. Don't decimate unless a model is really heavy.
- **Repeated props are instanced sub-scenes**, never duplicated nodes.
- **Render and look before calling it done** (see "Checking a change"), compared before and after.
- **Write it down** in `docs/DEV_NOTES.md`: what was built, triangle count and file size, sizes
  chosen, judgment calls, what was left out and the z-fighting check.

## Layout

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
- `scenes/asphalt/asphalt_lab.tscn` — the 2D asphalt lab: a road section ageing year by year (the crack types in
  zack's Asphalt Cracking Quick Guide, potholes) and being repaired (crack filling, pothole fill, heavy patches, chip
  seal, overlay), drawn as a colour map and a height map. `scripts/asphalt/asphalt_sim.gd` simulates,
  `asphalt_canvas.gd` draws, `assets/asphalt/asphalt_base.gdshader` is the surface. Prototype for procedural roads.
- `scenes/props/` — reusable props. `scenes/environment/` — shared sky and sun, and the garage's sky shader
  (`skyline_sky.gdshader`). `assets/manhattan_skyline/` (not in git) — the garage's Manhattan skyline from
  zack's Google Earth tiles, made by `sh tools/manhattan_skyline.sh`; the garage shows it only where it exists.
  `scenes/ui/hud.tscn` — the driving HUD, styled after US road signs (MUTCD, `Reference Images/UI/`; fonts and
  colours in `assets/ui/road_sign_theme.tres` and the scene's styleboxes). `scenes/ui/console.tscn` — the debug console autoload
  (tilde key; fast-travel destinations are its `destinations` export). `scenes/cart_camera.tscn` — the follow camera (`scripts/cart_camera.gd` lifts it over walls, see its exports).
- `assets/physics/*.tres` — shared physics materials (tile, asphalt, solid).
- `assets/audio/cart/` — the cart's wheel sounds (rolls, scrubs, knocks, landing), cut from zack's recordings by
  `tools/audio/make_cart_rolling_loops.py` (also writes the browser's `mobile/audio/*.wav`). Every wheel has a
  `WheelSound` (`scenes/cart/wheel_sound.tscn`) driven by that wheel's spin, slide and contact; the floor's
  physics material picks a `CartFloorSound` (`assets/audio/cart/floors/*.tres`).
- `assets/audio/ambience/` — level background loops (`tools/audio/make_ambience_loops.py`, also writes
  `mobile/audio/*.mp3`), played by an autoplaying `AudioStreamPlayer` on the `Music` bus (`default_bus_layout.tres`),
  e.g. the parking lot's `BackgroundMusic`. The browser export picks it up as the level's `"music"`.
- `scripts/` — behaviour scripts for the scenes above.
- `tools/` (repo root) — Blender builder and export scripts. `docs/DEV_NOTES.md` — dev notes.

## Checking a change

From `shopping-cart/`:

- Drive test (headless): `godot --headless --fixed-fps 120 -s res://tests/drive_test.gd`
- Screenshot: `xvfb-run godot -s res://tests/screenshot.gd -- out.png`
- Console test: `godot --headless --fixed-fps 120 -s res://tests/console_test.gd`
- Tuning in sync with the mobile game: `godot --headless -s res://tests/tuning_sync_test.gd`
  (fix with `godot --headless -s res://tools/export_cart_tuning_cli.gd`)
- Levels and cart rig in sync with the browser game: `godot --headless -s res://tests/mobile_levels_sync_test.gd`
  (fix with `godot --headless -s res://tools/export_mobile_levels_cli.gd`)
- Browser game (from the repo root): `node mobile/test/drive_test.js`
- Camera never clips into levels (all levels): `godot --headless --fixed-fps 120 -s res://tests/camera_test.gd`
- Parking lot level test: `godot --headless --fixed-fps 120 -s res://tests/parking_lot_test.gd`
- Coast highway level test: `godot --headless --fixed-fps 120 -s res://tests/coast_test.gd` (the level is generated
  by `tools/coast_models.py`; its docstring lists the steps to rebuild it)
- Stacked carts (nest, herd, pull off, knocks): `godot --headless --fixed-fps 120 -s res://tests/cart_stack_test.gd`
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
- Asphalt lab (ageing, crack types, repairs, replay): `godot --headless -s res://tests/asphalt_test.gd`
- Asphalt lab screenshots (stages, close-ups, height maps): `xvfb-run godot --rendering-method gl_compatibility -s res://tests/asphalt_screenshot.gd -- <out dir>`
