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
- **Done:** phase 0 (two Godots play over the network by address) and phase 1 (join codes, the game list and
  WebRTC, with the rendezvous service running locally). Next is deploying the service to Cloudflare, which needs
  zack's Cloudflare account, so two players on different networks can play.

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

**Godot on desktop needs the WebRTC plugin.** Godot's `WebRTCPeerConnection` is built in only for Web exports. On
Windows, macOS and Linux it comes from the official `webrtc-native` GDExtension (godotengine/webrtc-native 1.1.0,
in `addons/webrtc/`, desktop libraries only, about 28 MB). So that the browser can talk to Godot, both sides open
two *negotiated* data channels with fixed ids (control = 1, state = 2) on a plain peer connection, not Godot's
`WebRTCMultiplayerPeer` layout. `scripts/net/webrtc_link.gd` wraps that as a `MultiplayerPeer`, so `NetSession`
polls it exactly like ENet. The ENet path stays for LAN play.

**The browser game as host.** A browser tab can host too (WebRTC works both ways), but browsers throttle background
tabs, so a hidden host tab would stall everyone. Plan: browser players join; hosting from the browser comes later,
if at all.

## What is synced

The wire format is in `shopping-cart/scripts/net/net_protocol.gd` (little-endian, so JavaScript's `DataView` reads
it). Version 1:

| Data | Direction | How often | Size |
| --- | --- | --- | --- |
| Keys held (6 bits) + the level the guest has loaded | guest -> host | on change and 30 times a second, unreliable | 3 bytes |
| Each player cart: hand power L/R, a flags byte (fallen, and the player's slot, which colours the cart's pennant flag), frame velocity and turn rate (for the HUD and rolling sound), and the pose of all 15 bodies (frame, gate, child seat, seat flap, 2 forks, 4 wheels, 5 groceries) | host -> guests | 30 Hz, unreliable | about 450 bytes |
| Level loose bodies (boxes, product cases, oil drums, spare and bot carts): every body that is awake, plus 24 resting ones in turn so a lost packet can't leave one stale | host -> guests | 30 Hz, unreliable | 30 bytes each |
| Joins, level changes, leaving, reset requests | both | when they happen, reliable | small |

A pose is position + quaternion as float32 (28 bytes). Snapshots are split into packets of at most 1,100 bytes,
each complete on its own. Rough load per guest: the supermarket with two players and its bot carts is about 60 bodies
a snapshot, so ~2 KB x 30 Hz = 60 KB/s (0.5 Mbit/s). Fine on any connection and cheap on TURN; quantising poses
(16-bit positions near the cart, smallest-three quaternions) would cut it to about a third if relay costs matter.

In the endless sandbox, terrain chunks load around every player's cart on every machine (the layout is a hash of
the square, so it's the same everywhere). The loose bodies in a chunk are sent by square and index in the
snapshot's third section.

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
- Host spawns a cart per guest at the level's `PlayerSpawns` markers (Spawn1 for the first guest, and so on), or
  in a row to the right of `CartSpawn` when the level has none. Host fast travel takes guests along; guests
  can't fast travel. P on a guest asks the host to put its cart back on its wheels.
- Guest: everything in the level is frozen and moved from snapshots; bot carts' bots are switched off; the HUD and
  rolling sound read the host's speed. Status line bottom right.
- Test: `godot --headless -s res://tests/multiplayer_test.gd` (real time, about 20 s) starts a second Godot as the
  guest and checks joining, both carts moving, the guest seeing both carts where the host has them, and following
  the host through all four levels.

**Phase 1: WebRTC + join codes, all local (done).**
- `addons/webrtc` and `WebRtcLink` (two negotiated channels) beside ENet.
- `services/rendezvous/`: the Worker and Durable Objects from the design doc (Room, Directory, SetupBudget,
  per-IP rate limits, 8-letter codes, a private host token, listings that go stale after 75 s, codes that expire
  after 24 h, games up to 8 players, no passwords). It runs locally with `npm run dev` (`wrangler dev`, no account).
  TURN credentials are handed out only once a TURN key is set up; until then it gives STUN only.
- The Multiplayer menu (M, `scenes/ui/multiplayer_menu.tscn`): host online (name, listed or unlisted), the join
  code with a Copy button, join by code, the public game list, and LAN host/join by address. Console: `online`,
  `join <code or address>`, `games`.
- Tests: `npm test` (27 API checks) and `npm run test:godot` (the two-process Godot test, joining by code over
  WebRTC: both carts drive, the guest sees them where the host has them, and follows the host through all levels).

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
- Player names and a colour per cart (handle or paint), player spawn markers in the levels that still lack them
  (the supermarket has `PlayerSpawns/Spawn1..7`; elsewhere guests line up beside `CartSpawn`), bots filling empty slots, pose quantisation, host migration is out of scope (the game ends with the host).

## Decisions (zack, 2026-11-21)

1. Up to 8 players per game.
2. Browser and desktop players play together.
3. No passwords to start: join codes plus listed/unlisted.
4. Joining by IP address stays, for LAN play.
