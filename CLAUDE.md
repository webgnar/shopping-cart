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

## Layout

- `scenes/main.tscn` — the sandbox level (store floor, parking lot, boxes, `CartSpawn`).
- `scenes/levels/<name>.tscn` — further levels. Their root script extends `res://scripts/main.gd`,
  which supplies cart spawning, the follow camera, input and the HUD. A level scene places its own
  `CartSpawn` marker; if it has no `WorldEnvironment`, `Camera` or `HUD` node, `main.gd` adds the
  shared default scene for each.
- `scenes/cart/cart.tscn` — the cart rig (frame, gate, casters, wheels, hinge joints, groceries, model).
- `scenes/props/` — reusable props. `scenes/environment/` — shared sky and sun.
  `scenes/ui/hud.tscn` — the driving HUD. `scenes/cart_camera.tscn` — the follow camera.
- `assets/physics/*.tres` — shared physics materials (tile, asphalt, solid).
- `scripts/` — behaviour scripts for the scenes above.

## Checking a change

From `shopping-cart/`:

- Drive test (headless): `godot --headless --fixed-fps 120 -s res://tests/drive_test.gd`
- Screenshot: `xvfb-run godot -s res://tests/screenshot.gd -- out.png`
