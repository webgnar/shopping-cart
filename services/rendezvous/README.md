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
npm run dev          # http://127.0.0.1:8787, which is the game's default rendezvous_url
```

Then start two copies of the game. In one, press M and click Host. In the other, press M, type the join code and
click Join. You can also use the console (`online`, then `join ABCD-EFGH`) or the command line:

```sh
godot --path shopping-cart -- --online
godot --path shopping-cart -- --join=ABCD-EFGH
```

## Tests

```sh
npm test             # starts the Worker locally and checks the API (hosting, codes, list, signaling, limits)
npm run test:godot   # starts the Worker and runs two Godots that join by code and play over WebRTC
```

`npm run test:godot` takes a path to Godot after `--` if `godot` isn't on your PATH.

## Deploy (needs a Cloudflare account; ask zack first)

1. `npx wrangler login`, which opens the browser to sign in to Cloudflare.
2. `npm run check` (a dry run), then `npm run deploy`. It prints the address, e.g.
   `https://shopping-cart-rendezvous.<your-subdomain>.workers.dev`. Check `<address>/health`.
3. Put that address in the game: the `Net` autoload's `rendezvous_url` (scenes/net/net_session.tscn, Online group).
4. Optional, for players whose networks block direct connections: create a Realtime TURN key in the Cloudflare
   dashboard, put its key id in `wrangler.toml` (`TURN_KEY_ID`), run `npx wrangler secret put TURN_API_TOKEN` and
   paste its API token, then deploy again. Without TURN, games still work for most home networks (STUN only).

Never commit the TURN API token or Wrangler credentials. The rate-limit `namespace_id`s in `wrangler.toml` must be
unused in the account. Pricing: Workers, Durable Objects and TURN each have free allowances. Check the current
pages linked in zack's design doc before opening it up widely.
