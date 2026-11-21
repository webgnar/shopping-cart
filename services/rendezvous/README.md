# Rendezvous service

Join codes, the public game list and WebRTC signaling for shopping cart multiplayer: a Cloudflare Worker with three
SQLite-backed Durable Objects (`Room` per hosted game, `Directory` for the public list, `SetupBudget` for daily
limits). It only introduces players. Gameplay goes straight between them over WebRTC, or through Cloudflare's TURN
relay when a direct route fails. The API and messages are described at the top of `src/index.js`, and the bigger
picture is in `docs/MULTIPLAYER.md`.

## Run it locally (no Cloudflare account)

```sh
cd services/rendezvous
npm install
npm run dev          # http://127.0.0.1:8787
```

The game uses the deployed service by default (`rendezvous_url`), so point it at the local one with
`--rendezvous=http://127.0.0.1:8787` on the command line. Then start two copies of the game. In one, press M and click Host. In the other, press M, type the join code and
click Join. You can also use the console (`online`, then `join ABCD-EFGH`) or the command line:

```sh
godot --path shopping-cart -- --online --rendezvous=http://127.0.0.1:8787
godot --path shopping-cart -- --join=ABCD-EFGH --rendezvous=http://127.0.0.1:8787
```

## Tests

```sh
npm test             # starts the Worker locally and checks the API (hosting, codes, list, signaling, limits)
npm run test:godot   # starts the Worker and runs two Godots that join by code and play over WebRTC
```

`npm run test:godot` takes a path to Godot after `--` if `godot` isn't on your PATH.

## Deploy (zack's Cloudflare account; ask zack first)

Deployed 2026-11-21 to https://shopping-cart-rendezvous.shopping-cart-rendezvous.workers.dev (free plan, no TURN
key). To ship a change: `npx wrangler deploy` from here on a machine signed in to zack's account (wrangler needs
Node 22+).

1. `npx wrangler login`, which opens the browser to sign in to Cloudflare.
2. `npm run check` (a dry run), then `npm run deploy`. It prints the address, e.g.
   `https://shopping-cart-rendezvous.<your-subdomain>.workers.dev`. Check `<address>/health`.
3. Put that address in the game: the `Net` autoload's `rendezvous_url` (`scripts/net/net_session.gd`).
4. Optional, for players whose networks block direct connections: create a Realtime TURN key in the Cloudflare
   dashboard, put its key id in `wrangler.toml` (`TURN_KEY_ID`), run `npx wrangler secret put TURN_API_TOKEN` and
   paste its API token, then deploy again. Without TURN, games still work for most home networks (STUN only).

Never commit the TURN API token or Wrangler credentials. The rate-limit `namespace_id`s in `wrangler.toml` must be
unused in the account. Pricing: Workers, Durable Objects and TURN each have free allowances. Check the current
pages linked in zack's design doc before opening it up widely.
