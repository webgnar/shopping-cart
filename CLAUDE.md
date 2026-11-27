# Shopping Cart

A Godot 4.7 game (Jolt physics, 120 Hz) in `shopping-cart/`. **Until further notice there are only two areas of
work: the cart's physics and the asphalt simulator.** Start from the files below and leave the rest of the repo
alone unless the task names it.

## Cart physics: the files that matter

All paths are under `shopping-cart/`.

- `scripts/cart.gd`: the cart's behaviour. It covers hand push and pull (Q/A for the left hand, E/D for the right), lean keys (W/S),
  turning, tipping, getting back up and coming to rest. All tuning is in its `@export`s.
- `scenes/cart/cart.tscn`: the rig, with its frame, gate, child seat, forks, wheels and hinge joints. Body masses, damping and
  collision shapes are set on the nodes here.
- `assets/physics/*.tres`: floor and cart friction and bounce (tile, asphalt, concrete, grass, solid).
- `project.godot` `[physics]`: Jolt settings, 120 ticks, solver steps and the wheel spin cap `max_angular_velocity`.
- `scenes/main.tscn` + `scripts/main.gd`: the sandbox where you test the cart. It's an endless flat lot with a test strip
  (speed bumps, curb, ramp, boxes) by `CartSpawn`. `main.gd` spawns the cart, sets up input and adds the camera
  and HUD.
- `tests/drive_test.gd`: presses the real keys and checks that the cart does what the design says.
- `tools/rig_cart.py` (repo root): builds the cart model and its pivots in Blender. Only touch it for model changes.

## Asphalt simulator: the files that matter

The asphalt lab is a 2D prototype for procedural roads. It shows a road section ageing year by year (cracks,
potholes) and getting repaired, drawn as a colour map and a height map. In 3D it only goes as far as the lab's
3D preview and the asphalt test lot, until zack asks for more.

- `scripts/asphalt/asphalt_sim.gd` (`AsphaltSim`): the simulation. `bake_height()` gives real heights in metres.
  It is split by concern into `asphalt_sim_*.gd` parts, each extending the last; the placeholder damage rules are
  in `asphalt_sim_rules.gd`. `docs/ASPHALT_SCIENCE.md` tracks what is sourced;
  `docs/ASPHALT_ROADMAP.md` lists the topics, what passes between them and where each stands: read it first, update it last.
- `scripts/asphalt/asphalt_canvas.gd`: draws the maps. `scripts/asphalt/asphalt_lab.gd`: the lab UI.
- `scenes/asphalt/asphalt_lab.tscn`: the lab scene. `assets/asphalt/`: the surface shader and grain.
- `scenes/asphalt/asphalt_section.tscn` (`asphalt_section.gd`): a 10 x 10 m section in 3D, displaced and with matching
  collision. `scenes/levels/asphalt_lot.tscn` (console `asphalt`): a 50 x 40 m test lot of 20 sections, the middle column
  repaired by the road crew. Its sections are baked (`tools/bake_asphalt_sections_cli.gd`, steps in its header) and load
  from `assets/asphalt/baked/`; re-bake after changing a section or the simulator.
- Test: `godot --headless -s res://tests/asphalt_test.gd`. Screenshots:
  `xvfb-run godot --rendering-method gl_compatibility -s res://tests/asphalt_screenshot.gd -- <out dir>`.
- Reference: zack's Asphalt Cracking Quick Guide (crack types), in the project files under `asphalt/`.

## Curbs

`scenes/curb/curb.tscn` (`scripts/curb/curb.gd`, `Curb`): the Type C curb from `References/Props/type_c_doweled_curb.png`,
swept along a Path3D, for the parking lot generator. Test: `godot --headless -s res://tests/curb_test.gd`.

## Parking lot generator

`scenes/lot_gen/lot_generator.tscn` (`scripts/lot_gen/lot_generator.gd`, `LotGenerator`): lays out a lot from a few
`@export`s (size, stall angle 90/60/45/30, two-way or one-way aisles, islands, wheel stops, perimeter curb, corrals),
sized from `References/Levels/c620content.pdf` Table 1, out of the curb, wheel stop, corral, `stripe.tscn` and
`island_fill.tscn` scenes. Its Generate button bakes the lot into the scene; left empty, it generates on load.
Level `scenes/levels/generated_lot.tscn`, console `lotgen [angle] [seed] [oneway]`. With `section_scene` set it paves
the lot with aged AsphaltSections whose sims paint the stall lines: `scenes/levels/lot90.tscn` (console `sandbox`, and the game's start scene), baked
with `tools/bake_lot_cli.gd` then `tools/bake_asphalt_sections_cli.gd` (steps in the first's header).
The lab, `scenes/lot_gen/lot_lab.tscn` (console `lotlab`), puts every setting on a panel, rebuilds as you change
them, and lists the sizes used next to Table 1.
Test: `godot --headless -s res://tests/lot_generator_test.gd`. Screenshots:
`xvfb-run godot --rendering-method gl_compatibility -s res://tests/lot_generator_screenshot.gd -- <out dir>`
(`lot_lab_screenshot.gd` for the lab).

## Testing a cart change

Run only the drive test, from `shopping-cart/` (for an asphalt change, run only `asphalt_test.gd`):

    godot --headless --fixed-fps 120 -s res://tests/drive_test.gd

Don't run the level, race, sweep, bot, multiplayer, camera or sound tests for a cart change. Run one of those only
when the task changes that part of the game, or when someone asks for it. The full list is in
`docs/LEVELS_AND_MODES.md`.

## What to skip

These folders aren't about the cart or the asphalt, so don't read or search them unless the task is about them:
`scenes/levels`, `scenes/race`, `scenes/sweep`, `scenes/net`, `scenes/coast`, `scenes/props`,
`scripts/net`, `scripts/race`, `scripts/sweep`, `scripts/levels`, `scripts/props`, `scripts/cart_bot.gd`,
`assets/models`, `assets/textures`, `assets/audio`, `assets/navigation`, `addons/`, `services/`, `Reference Images/`,
the root `tools/` builders, and the `.blend` files.

`docs/DEV_NOTES.md` is a long history covering the whole game. Search it for the thing you're changing instead of reading
it from start to finish. Levels, modes and the rest of the game are mapped in `docs/LEVELS_AND_MODES.md`. Model building
rules are in `docs/MODELS.md`.

## Rules

- **Keep each change tightly scoped to the task.** Don't add extra features, refactors or side updates.
- **Build scenes first.** Content is made of nodes in `.tscn` scenes that can be edited in the Godot editor. Scripts are for
  behaviour only and don't `new()` nodes, shapes or materials to lay out the world. Settings such as masses, sizes and
  materials go on the node or a `.tres`, not in code. Spawn points are `Marker3D` nodes. Nothing overrides
  inspector values at start: fixed values are `const`, and tunable ones are `@export`s or node properties.
- The cart's nose is +X and its origin is on the ground under the handle.

## Commits

- Claude stays the commit author. End every commit message with
  `Co-authored-by: webgnar <124617425+webgnar@users.noreply.github.com>`, and don't add a `Co-Authored-By: Claude ...`
  trailer. A `Claude-Session:` line may stay.
- Merge pull requests with a normal merge, not a squash.
