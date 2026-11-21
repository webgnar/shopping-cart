# Multiplayer plan

Player-hosted, host-authoritative multiplayer for the shopping cart game, adapted from zack's design doc
(`PLAYER_HOSTED_NETWORKING_OVERVIEW.md`, a Rust/Bevy reference) to Godot and the browser version in `mobile/`.
Written 2026-11-21 alongside the first prototype (phase 0 below).

## The short version

- **One player hosts and their physics is the only physics.** Guests send the six keys they hold (Q/A/E/D/W/S) and
  get back snapshots of every moving body. A guest never simulates, so a Godot (Jolt) host and a browser (Rapier)
  guest can play together: nothing has to agree on physics, only on the level and the byte format.
- **Guests drive carts exactly as bots do.** A guest's cart on the host is an ordinary `cart.tscn` whose `driver`
  is the network and whose `controls` are the guest's keys (the hook PR #26 added for bot carts).
- **WebRTC instead of raw ICE + QUIC.** The design doc's transport (ICE with STUN/TURN, encrypted datagrams, QUIC
  reliable streams) is what a WebRTC data channel already is: ICE with STUN/TURN, DTLS encryption, and SCTP
  channels that can be reliable/ordered or unreliable. Browsers can only do WebRTC, so using it everywhere gives
  one transport for Godot and the browser. The Cloudflare side stays as the doc describes (Worker + Durable
  Objects for join codes, the server browser and signaling, Cloudflare Realtime TURN for relaying).
- **Prototype done (phase 0):** two Godot copies play together over the network today (ENet, by address), with a
  test that runs a real second process. Next is the WebRTC transport plus a local signaling server, then the
  Cloudflare deployment, which needs zack's Cloudflare account.

## Architecture

```text
Connection setup (phase 1-2):
  Guest <-- HTTPS/WSS --> Cloudflare Worker + Durable Objects <-- HTTPS/WSS --> Host
          join code / browse, SDP offer/answer + ICE candidates, TURN credentials

Gameplay:
  Guest <======== WebRTC data channels (direct UDP, or Cloudflare TURN) ========> Host
          "state": unordered, no retransmits   -> INPUT (guest), SNAPSHOT (host)
          "control": reliable, ordered          -> HELLO / WELCOME / LEVEL / RESET / LEFT
```

| Design doc piece | Here |
| --- | --- |
| Worker: register host, join code, browse, rate limits | Same. Allowed level names are the console's fast-travel keys (`sandbox`, `market`, `plot`, `garage`). |
| `Room` DO: host auth, password proof, ICE signaling | Same, but it forwards SDP offers/answers and ICE candidates (WebRTC signaling) instead of raw ICE credentials. No per-peer encryption key: DTLS in WebRTC does that. |
| `Directory` DO, `SetupBudget` DO | Same: name, level, players/limit, password flag, protocol version. |
| Cloudflare Realtime TURN, temporary credentials | Same; the Worker hands them out as `iceServers` for `RTCPeerConnection` / `WebRTCPeerConnection`. |
| `webrtc-ice` + ChaCha20 datagrams | WebRTC data channel, unreliable (`ordered: false, maxRetransmits: 0`). |
| Quinn QUIC streams | WebRTC data channel, reliable and ordered. Large transfers aren't needed: both sides ship the same levels. |
| Dedicated server | Not needed at first: the host is a player. A headless Godot host (`godot --headless -- --host`) already works. |

**Godot on desktop needs the WebRTC plugin.** Godot's `WebRTCPeerConnection` is built in only for Web exports; on
Windows/macOS/Linux it comes from the official `webrtc-native` GDExtension (godotengine/webrtc-native), which we
add under `addons/`. To keep the browser able to talk to Godot, both sides open two *negotiated* data channels with
fixed ids (control = 1, state = 2) on a plain peer connection rather than Godot's `WebRTCMultiplayerPeer` layout,
and `NetSession` keeps polling raw packets as it does now. The ENet path stays for LAN and tests.

**The browser game as host.** A browser tab can host too (WebRTC works both ways), but browsers throttle background
tabs, so a hidden host tab would stall everyone. Plan: browser players join; hosting from the browser comes later,
if at all.

## What is synced

The wire format is in `shopping-cart/scripts/net/net_protocol.gd` (little-endian, so JavaScript's `DataView` reads
it). Version 1:

| Data | Direction | How often | Size |
| --- | --- | --- | --- |
| Keys held (6 bits) + the level the guest has loaded | guest -> host | on change and 30 times a second, unreliable | 3 bytes |
| Each player cart: hand power L/R, fallen flag, frame velocity and turn rate (for the HUD and rolling sound), and the pose of all 15 bodies (frame, gate, child seat, seat flap, 2 forks, 4 wheels, 5 groceries) | host -> guests | 30 Hz, unreliable | about 450 bytes |
| Level loose bodies (boxes, product cases, oil drums, spare and bot carts): every body that is awake, plus 24 resting ones in turn so a lost packet can't leave one stale | host -> guests | 30 Hz, unreliable | 30 bytes each |
| Joins, level changes, leaving, reset requests | both | when they happen, reliable | small |

A pose is position + quaternion as float32 (28 bytes). Snapshots are split into packets of at most 1,100 bytes,
each complete on its own. Rough load per guest: the supermarket with two players and its bot carts is about 60 bodies
a snapshot, so ~2 KB x 30 Hz = 60 KB/s (0.5 Mbit/s). Fine on any connection and cheap on TURN; quantising poses
(16-bit positions near the cart, smallest-three quaternions) would cut it to about a third if relay costs matter.

Loose bodies are matched by order: every machine lists the level's `RigidBody3D`s (outside the local player's
cart) sorted by node path. The host sends the count in WELCOME/LEVEL and a guest warns if its build differs. For
the browser, `export_mobile_levels_cli.gd` will write the same ordered list into each level's JSON.

**Guests show the past.** A guest moves every body between the two snapshots around (newest - 100 ms), so motion
is smooth through jitter and a lost packet. The cost is latency: the guest's own cart responds after the round trip
plus ~130 ms. The hand power ramps up over a second anyway, so this should be playable for a first version; if it
isn't, phase 4 adds prediction for the guest's own cart.

## Phases

**Phase 0: local prototype (done, this PR).**
- `Net` autoload (`scenes/net/net_session.tscn`, `scripts/net/net_session.gd`). Console: `host [port]`,
  `join <address>[:port]`, `leave`, `net`. Command line: `godot --path shopping-cart -- --host` and
  `-- --join=127.0.0.1`.
- Host spawns a cart per guest in a row to the right of `CartSpawn`. Host fast travel takes guests along; guests
  can't fast travel. P on a guest asks the host to put its cart back on its wheels.
- Guest: everything in the level is frozen and moved from snapshots; bot carts' bots are switched off; the HUD and
  rolling sound read the host's speed. Status line bottom right.
- Test: `godot --headless -s res://tests/multiplayer_test.gd` (real time, about 20 s) starts a second Godot as the
  guest and checks joining, both carts moving, the guest seeing both carts where the host has them, and following
  the host through all four levels.

**Phase 1: WebRTC + join codes, all local (no Cloudflare account needed).**
- Add `webrtc-native`; a `WebRtcLink` transport (two negotiated channels) beside ENet, chosen by the session.
- `services/rendezvous/`: the Worker and Durable Objects from the design doc, run locally with `wrangler dev`
  (it runs Workers and Durable Objects on the dev machine, no account). Host registers and gets a join code;
  guest joins by code; signaling over WebSocket.
- Host / Join / Browse screens as scenes under `scenes/ui/` (code field, copy-code button, progress and errors).
- Tests: Worker unit tests (`npm test`), and the two-process Godot test over WebRTC on localhost.

**Phase 2: deploy (needs zack).**
- A Cloudflare account, a Realtime TURN key and a Worker name; then `wrangler deploy` and
  `wrangler secret put TURN_API_TOKEN`, exactly as the design doc's setup section. The public Worker URL goes in a
  project setting. Nothing is created or deployed until zack says so.
- Test across two home networks, a phone hotspot, and with TURN forced, as the design doc lists.

**Phase 3: the browser joins.**
- `mobile/game/net.js`: the same protocol and guest logic as `net_session.gd` (freeze bodies, interpolate,
  send keys), with the browser's own `RTCPeerConnection`. Level body order from the export.
- Join by code from the browser menu; itch.io serves over HTTPS, which WebRTC needs.

**Phase 4: feel and polish.**
- Prediction for the guest's own cart if the delay feels bad (simulate it locally, blend toward the host).
- Player names and a colour per cart (handle or paint), player spawn markers per level (`PlayerSpawns` Marker3D
  nodes; today guests line up beside `CartSpawn`, which in the supermarket puts the second cart nose to a box
  display), bots filling empty slots, pose quantisation, host migration is out of scope (the game ends with the host).

## Open questions for zack

1. How many players per game? The prototype allows 8 (host + 7).
2. Should browser and desktop players play together (cross-play)? The plan assumes yes.
3. Is a password option wanted, or are join codes plus public/unlisted enough to start?
4. Keep joining by IP address (LAN parties) alongside join codes? It costs nothing to keep.
