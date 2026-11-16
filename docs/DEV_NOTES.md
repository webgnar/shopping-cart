# Dev notes

Newest first. One entry per change to models, levels or scenes: what was built, sizes chosen,
triangle count and file size for new models, judgment calls, what was left out, z-fighting check.

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
