# Speed perception: why the cart "feels a touch slow"

Measured 2026-11-26 in the sandbox (`scenes/main.tscn`), Godot 4.7, 1280 x 720. Nothing in the camera or sound
was changed for this; it is a proposal. Re-run the numbers with
`xvfb-run godot --rendering-method gl_compatibility --fixed-fps 60 -s res://tests/speed_cues_probe.gd`.

## The cart isn't slow

Holding Q+E on the coast-down lane: 1.9 km/h at 0.25 s, 11 km/h at 1 s, 22.6 km/h at 2 s, then about 17 km/h
coasting two seconds later. A brisk walk is 5 to 6 km/h and a jog 9 to 10, so 22 km/h is a sprint. The first 0.25 s
is weak (2 km/h), which the physics thread is fixing. Everything below is about how that speed is shown.

## What the screen and speakers give you

Ground flow is how fast the ground under the screen moves across it. An even grid of screen pixels is cast
onto the ground and moved by the camera's own motion. Results are in screen heights per second.

| Cue | Now | Notes |
|---|---|---|
| Ground flow at 22 km/h, mean / 90th pct / outer fifths | 1.23 / 2.66 / 1.49 | the camera rig is held rigid |
| ... with the camera's real lag | 1.13 / 2.42 / 1.38 | 8% less, because the camera falls back as the cart speeds up |
| Camera behind the handle | 2.52 m at rest, 3.18 m at 22 km/h | look target eased at 9/s, so it trails by v/9 (0.68 m at 22 km/h) |
| Camera height | 1.83 m | above a pusher's eye line, looking down at 20 degrees |
| FOV | 55 degrees vertical | narrow for a chase camera (racing games use about 65 to 75, more with a speed kick) |
| Cart on screen | 0.21 screen heights | |
| Camera shake | none | |
| Ground detail (mean brightness gradient) | spawn aisle 0.023, stall rows 0.023, coast lane 0.034 | the lane's marks and posts add 45% |
| Landmarks beside the path | spawn aisle: an island every 40 m (one every 6.5 s at 22 km/h) | stall stripes every 2.7 m only in the rows, none in the aisle |
| Wheel roll volume | stops growing at 1.5 m/s (5.4 km/h) | `wheel_sound.gd` `full_volume_speed` |
| Wheel roll pitch | stops rising at 3.8 m/s (13.7 km/h), at `max_pitch` 1.5 | `recorded_speed` 1.3 + (1.5 - 1) / `pitch_per_speed` 0.2 |
| Wind | none | |

So above about 14 km/h nothing you hear changes, the aisle you drive down has almost no texture, and the camera
sits high and far back with a narrow lens. Screenshots: `compare_aisle.png` and `compare_lane.png` in the report
(top is now, bottom is the proposed framing, both at 21 km/h).

### Ground flow at 22 km/h by camera setting

| FOV | Distance m | Pitch rad | Camera height m | Flow mean | 90th pct | Outer fifths | Cart on screen |
|---|---|---|---|---|---|---|---|
| 55 | 3.2 | 0.38 | 1.83 | 1.23 | 2.66 | 1.49 | 0.21 (now) |
| 65 | 3.2 | 0.38 | 1.83 | 1.33 | 2.89 | 1.64 | 0.17 |
| 75 | 3.2 | 0.38 | 1.83 | 1.48 | 3.18 | 1.85 | 0.14 |
| 55 | 2.4 | 0.38 | 1.53 | 1.47 | 3.20 | 1.79 | 0.29 |
| 55 | 3.2 | 0.25 | 1.43 | 1.33 | 2.88 | 1.66 | 0.25 |
| 55 | 2.4 | 0.25 | 1.24 | 1.56 | 3.38 | 1.94 | 0.33 |
| 65 | 2.6 | 0.30 | 1.41 | 1.61 | 3.51 | 2.02 | 0.24 |
| 70 | 2.4 | 0.25 | 1.24 | 1.88 | 4.11 | 2.38 | 0.25 |

Lower, closer and wider each add flow. Together (the last row) they give 53% more on average and 60% more at
the screen edges, which is where speed is read, while the cart stays the same size on screen. A wider lens
alone shrinks the cart, so the lens and the distance should change together.

## Proposal (for approval before any camera change)

In order of effect for the effort:

1. **Frame the camera lower, closer and wider.** Distance 2.4 to 2.6 m, pitch 0.25 to 0.30 (camera at 1.2 to
   1.4 m, about a pusher's chest), FOV 62 at rest. These are the defaults `cam_dist`, `cam_pitch` and `Camera.fov`
   in `main.gd` and `main.tscn`. Run `camera_test.gd`, since a lower camera meets more geometry.
2. **Add a speed FOV kick.** FOV eases from 62 at rest to about 72 at 25 km/h (an `@export` curve or range on the
   camera, eased at about 2/s so it never pumps). The sides of the screen stretch as you speed up, the classic
   cue, and it costs nothing at walking pace.
3. **Keep the lag, but make it read as acceleration.** The camera falling back by v/9 costs 8% of flow but
   shows the cart pulling away as you launch. I'd keep it, but make it build faster and settle back: ease the
   trail with the speed's change rather than the speed, so the cart pulls ahead on the launch, then the camera
   catches up at a steady speed. That gives the same flow as a rigid camera at cruising speed and a bigger
   launch cue.
4. **Add a small roll vibration on the camera.** 1 to 3 mm of high-frequency jitter scaling with speed and with
   the floor (asphalt more than tile), and a short jolt on wheel knocks (`wheel_sound.gd` already detects
   them). It should stay under what the eye reads as shake.
5. **Give the wheel sound room above 14 km/h** (for whoever owns `scripts/cart/wheel_sound.gd`). Spread the
   pitch rise to about 30 km/h (`pitch_per_speed` about 0.1, `max_pitch` about 1.8), let the volume keep climbing
   gently past `full_volume_speed`, and add a wind layer: filtered noise from about 10 km/h, its gain rising with
   the square of the speed.
6. **Put rhythm beside the path in the sandbox.** Things at 2 to 5 m intervals near the line you drive: the
   coast lane's posts (every 5 m) already add 45% ground detail. For the main aisle, either seams or patches in
   the asphalt (lot90, the start scene, already has aged, cracked sections) or a row of bollards or cart corrals.

Items 1 to 3 are camera changes in `main.gd` and `cart_camera.gd` and need a go-ahead. Item 5 touches the cart's
sound. Item 6 is level content.
