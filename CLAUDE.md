# Shopping Cart

The game lives in `shopping-cart/` (Godot 4.7, Jolt physics). `mobile/` is a three.js web version,
`tools/` holds Blender and sync scripts, and `tuning/cart_tuning.json` is shared by both games.

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
- Values that the tuning file overrides at start (cart masses, floor friction) still have
  their defaults set on the nodes, so the scene shows sensible values in the editor.

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

- `scenes/main.tscn` — the sandbox level (store floor, parking lot, boxes, `CartSpawn`).
- `scenes/levels/<name>.tscn` — further levels. Their root script extends `res://scripts/main.gd`,
  which supplies cart spawning, the follow camera, input and the HUD. A level scene places its own
  `CartSpawn` marker; if it has no `WorldEnvironment`, `Camera` or `HUD` node, `main.gd` adds the
  shared default scene for each.
- `scenes/cart/cart.tscn` — the cart rig (frame, gate, casters, wheels, hinge joints, groceries, model).
  `scenes/cart/spare_cart.tscn` — the same cart, empty and not player controlled, to place in levels.
- `scenes/props/` — reusable props. `scenes/environment/` — shared sky and sun.
  `scenes/ui/hud.tscn` — the driving HUD. `scenes/ui/console.tscn` — the debug console autoload
  (tilde key; fast-travel destinations are its `destinations` export). `scenes/cart_camera.tscn` — the follow camera.
- `assets/physics/*.tres` — shared physics materials (tile, asphalt, solid).
- `scripts/` — behaviour scripts for the scenes above.
- `tools/` (repo root) — Blender builder and export scripts. `docs/DEV_NOTES.md` — dev notes.

## Checking a change

From `shopping-cart/`:

- Drive test (headless): `godot --headless --fixed-fps 120 -s res://tests/drive_test.gd`
- Screenshot: `xvfb-run godot -s res://tests/screenshot.gd -- out.png`
- Console test: `godot --headless --fixed-fps 120 -s res://tests/console_test.gd`
- Parking lot level test: `godot --headless --fixed-fps 120 -s res://tests/parking_lot_test.gd`
- Supermarket level check: `xvfb-run godot -s res://tests/supermarket_check.gd -- <out dir>`
