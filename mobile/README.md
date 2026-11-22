# Shopping Cart: browser version

The in-browser build (three.js + Rapier) for phones and computers. It plays the same levels and the same cart
as the Godot game, copied from the Godot scenes by export tools, so the Godot project stays the source of truth.

It fetches its levels, so serve the folder instead of opening the file: `python3 -m http.server -d mobile`
and open http://localhost:8000 (or upload the `mobile/` folder as an HTML5 game on itch.io). Add
`?level=garage` (sandbox, plot, garage, market) or `?controls=desk` / `?controls=touch` to the URL to pick.

## Controls

- **Phones** (touch screen detected): the bottom corners are your hands. Hold above the middle of the left rocker
  to push with the left hand, below to pull; slide across to switch. The longer you hold, the harder the hand
  pushes (its bar fills, as in Godot). One hand turns, push one and pull the other to spin. Lean: tip the phone
  back for the front up (S), forward for the back up (W), or hold the **Back up** / **Front up** buttons.
  Drag near the top of the screen to look around. **Level** fast-travels, **Tilt** cycles on / flipped / off,
  **Set level** re-zeroes the tilt.
- **Computers** (mouse and keyboard detected): the Godot keys. Q/A left hand push/pull, E/D right (the left hand pushing turns the cart right; tap a key to move that hand out along the bar), W/S lean the
  back/front up, P a fresh cart where you are, click to look around (Esc to let go), wheel to zoom,
  ` opens the console (`help`, `where`, `plot`, `garage`, `market`, `sandbox`), F full screen. Touching the screen
  switches to the phone controls and a game key switches back.

## Files

| Path | What it is | How it's made |
| --- | --- | --- |
| `index.html`, `game/*.js` | The game: `cart.js` is a line-for-line port of `scripts/cart.gd`, `bot.js` of `scripts/cart_bot.gd` (bot carts), `nav.js` stands in for Godot's navigation server and NavigationAgent3D, `level.js` builds an exported level, `stream.js` streams the endless sandbox's chunks around the cart (as `scripts/sandbox/chunk_streamer.gd`, same hash so the same layout), `main.js` is input, camera (`cart_camera.gd`), HUD, console and the loop | Hand-written |
| `cart_tuning.js` | Cart feel (every Cart export and body mass) | `shopping-cart/tools/export_cart_tuning.gd` |
| `levels/<key>.glb` + `.json` | Each fast-travel level: meshes and materials; collision shapes with friction, loose props, CartSpawn, spare carts, bot carts and their navigation mesh, sky, sun, lamps, 3D labels | `godot --headless -s res://tools/export_mobile_levels_cli.gd` (from `shopping-cart/`) |
| `levels/chunks/<name>.glb` + `.json` | The endless sandbox's terrain chunks (`scenes/sandbox/chunks/`), each exported like a level; `levels/sandbox.json` has the grid (`stream`) | same |
| `levels/cart.json` | The cart rig (bodies, masses, shapes, hinges and limits), its materials and the bot's settings | same |
| `models/cart.glb` | Phone-weight cart model (85k faces, 10 meshes) from the Godot one | `blender -b --python tools/export_mobile_model.py` |
| `audio/*.wav` | The cart's wheel sounds (rolls, scrubs, knocks, landing), played per wheel by `game/sound.js` as in `scripts/cart/wheel_sound.gd` | `python3 tools/audio/make_cart_rolling_loops.py` |
| `vendor/` | three.js 0.170 and Rapier 0.14 (so it runs without a CDN) | copied from npm |

Change levels and the cart in Godot, then run both export tools. `tests/tuning_sync_test.gd` and
`tests/mobile_levels_sync_test.gd` (Godot) fail when the copies are out of date.

## Test

```
node mobile/test/drive_test.js [screenshot-dir]
```

Serves the folder and runs the same checks as the Godot drive test (push, pull, turn, spin, wheelies, W/S lean and
tip-over, hard push/pull, braking, spin brace, getting back up, gate, child seat, knocked when pinned), then loads
every level (spawns, comes to rest, drives, camera never inside a wall), lets each level's bot carts drive for a minute, rams a spare cart, and drives the phone's
touch rockers, the keyboard and the console.
