# How we make models

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
