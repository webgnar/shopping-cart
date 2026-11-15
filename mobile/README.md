# Shopping Cart: mobile web version

A tap-and-play browser version of the game, built with three.js and the Rapier physics engine.
Open `index.html` (or the published link) on a phone, turn it sideways and tap **Tap to start**.

- **Left / right thumb:** the cart's left / right hand. Drag up to push, down to pull; the further you drag,
  the harder you push and the faster you can walk (from a stroll to a run).
- **Tilt the phone:** back for a wheelie, forward to lift the rear wheels, sideways to lean onto two wheels.
  **Set level** re-zeroes the tilt; **Tilt** cycles on / flipped / off.
- On a computer: Q/A left hand, E/D right hand, W/S lift/press, R reset, scroll to zoom.

## Files

| File | What it is | How it's made |
| --- | --- | --- |
| `index.html` | The game | Hand-written |
| `cart_tuning.js` | Cart feel (masses, forces, gears, friction...) | `python3 tools/sync_tuning.py` from `shopping-cart/tuning/cart_tuning.json`, which the Godot game also reads |
| `cart_model_mobile.js` | Phone-weight cart model (about 89k faces, 11 meshes) | `blender -b ShoppingCart_Rigged.blend --python tools/export_mobile_model.py` |

To change how the cart feels in both games, edit `shopping-cart/tuning/cart_tuning.json`, then run
`python3 tools/sync_tuning.py`.

## Test

```
node mobile/test/drive_test.js
```

Drives the thumbs and tilt through the page's test hook and checks pushing, pulling, turning, spinning,
stroll and run speeds, wheelie, rear lift, leaning, coming to rest and the gate (13 checks).
