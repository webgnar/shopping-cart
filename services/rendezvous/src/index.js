// Shopping cart multiplayer rendezvous (Cloudflare Worker + SQLite-backed Durable Objects).
//
// It introduces players and then steps aside: gameplay goes player to player over WebRTC (direct, or through
// Cloudflare TURN). Adapted from zack's PLAYER_HOSTED_NETWORKING_OVERVIEW.md; see docs/MULTIPLAYER.md.
//
// HTTP API
//   GET  /health                      -> {ok, service}
//   POST /host   {name, level, max_players, public, protocol}
//                                     -> {code, token}   (token: private, proves the caller hosts that code)
//   GET  /games  [?protocol=N]        -> {games: [{code, name, level, players, max_players, protocol}]}
//   GET  /room/<CODE>/host?token=...  WebSocket for the host (or header Authorization: Bearer <token>)
//   GET  /room/<CODE>/join[?protocol=N]  WebSocket for a guest
//
// Signaling messages (JSON text frames). Server to host: {type:"hosted", ice_servers}, {type:"join", id},
// {type:"leave", id}. Server to guest: {type:"welcome", id, ice_servers}, {type:"closed", reason},
// {type:"error", reason}. Host to guest and back: {type:"offer"|"answer"|"candidate", to, ...}; the server adds
// `from` (the host is always 1, guests 2 and up) and forwards it. Host: {type:"heartbeat"} every 30 s keeps the
// public listing alive (stale after 75 s). Guests keep their socket open while they play.

import { DurableObject } from "cloudflare:workers";

const LEVELS = ["sandbox", "market", "plot", "garage"];   // the console's fast-travel keys
const MIN_PLAYERS = 2;
const MAX_PLAYERS = 8;
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";   // no I, L, O, 0, 1
const CODE_LENGTH = 8;
const ROOM_LIFETIME_MS = 24 * 3600 * 1000;
const LISTING_STALE_MS = 75 * 1000;
const MAX_MESSAGE_BYTES = 16 * 1024;
const SIGNAL_TYPES = ["offer", "answer", "candidate"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const ip = request.headers.get("CF-Connecting-IP") || "local";
    try {
      if (url.pathname === "/health") {
        return json({ ok: true, service: "shopping-cart-rendezvous" });
      }
      if (url.pathname === "/host" && request.method === "POST") {
        if (!(await allowed(env.HOST_LIMIT, ip))) return json({ error: "Too many games hosted from here, try again in a minute." }, 429);
        const listing = validateListing(await request.json().catch(() => null));
        if (typeof listing === "string") return json({ error: listing }, 400);
        if (!(await takeBudget(env, "host", env.MAX_HOST_REGISTRATIONS_PER_DAY))) {
          return json({ error: "Hosting is closed for today, try again tomorrow." }, 503);
        }
        for (let attempt = 0; attempt < 5; attempt++) {
          const code = randomCode();
          const token = randomHex(32);
          const res = await room(env, code).fetch("https://room/init", {
            method: "POST",
            body: JSON.stringify({ code, token_hash: await sha256(token), listing }),
          });
          if (res.status === 200) return json({ code, token });
        }
        return json({ error: "Couldn't make a join code, try again." }, 503);
      }
      if (url.pathname === "/games" && request.method === "GET") {
        if (!(await allowed(env.BROWSE_LIMIT, ip))) return json({ error: "Slow down a little." }, 429);
        const res = await directory(env).fetch("https://directory/list");
        const { games } = await res.json();
        const protocol = url.searchParams.get("protocol");
        return json({ games: protocol ? games.filter((g) => String(g.protocol) === protocol) : games });
      }
      const m = url.pathname.match(/^\/room\/([A-Za-z0-9-]+)\/(host|join)$/);
      if (m) {
        if (request.headers.get("Upgrade") !== "websocket") return json({ error: "WebSocket expected." }, 426);
        const code = normalizeCode(m[1]);
        if (!code) return json({ error: "That isn't a join code." }, 400);
        if (m[2] === "join" && !(await allowed(env.JOIN_LIMIT, ip))) return json({ error: "Slow down a little." }, 429);
        return room(env, code).fetch(request);
      }
      return json({ error: "Not found." }, 404);
    } catch (err) {
      return json({ error: "Server error." }, 500);
    }
  },
};

// ---------------------------------------------------------------- one hosted game

export class Room extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/init") return this.init(await request.json());
    const state = await this.ctx.storage.get("room");
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    if (url.pathname.endsWith("/host")) {
      const auth = request.headers.get("Authorization") || "";
      const token = url.searchParams.get("token") || auth.replace(/^Bearer\s+/i, "");
      if (!state || !token || (await sha256(token)) !== state.token_hash) {
        return refuse(client, server, "Wrong or expired host token.");
      }
      for (const old of this.ctx.getWebSockets("host")) old.close(4000, "Replaced by a new host connection.");
      this.ctx.acceptWebSocket(server, ["host"]);
      server.send(JSON.stringify({ type: "hosted", code: state.code, ice_servers: await iceServers(this.env) }));
      await this.publish(state);
      return new Response(null, { status: 101, webSocket: client });
    }
    // A guest.
    if (!state || Date.now() - state.created > ROOM_LIFETIME_MS || this.ctx.getWebSockets("host").length === 0) {
      return refuse(client, server, "No game with that code is running.");
    }
    const protocol = url.searchParams.get("protocol");
    if (protocol && String(state.listing.protocol) !== protocol) {
      return refuse(client, server, `That game runs a different version (${state.listing.protocol}, yours ${protocol}).`);
    }
    if (this.players() >= state.listing.max_players) return refuse(client, server, "That game is full.");
    const id = state.next_id;
    state.next_id += 1;
    await this.ctx.storage.put("room", state);
    this.ctx.acceptWebSocket(server, ["guest", `g:${id}`]);
    server.serializeAttachment({ id });
    server.send(JSON.stringify({ type: "welcome", id, ice_servers: await iceServers(this.env) }));
    this.toHost({ type: "join", id });
    await this.publish(state);
    return new Response(null, { status: 101, webSocket: client });
  }

  async init({ code, token_hash, listing }) {
    const old = await this.ctx.storage.get("room");
    if (old && Date.now() - old.created < ROOM_LIFETIME_MS) return new Response("taken", { status: 409 });
    await this.ctx.storage.put("room", { code, token_hash, listing, created: Date.now(), next_id: 2 });
    return new Response("ok");
  }

  players() {
    return 1 + this.ctx.getWebSockets("guest").length;
  }

  toHost(msg) {
    for (const ws of this.ctx.getWebSockets("host")) ws.send(JSON.stringify(msg));
  }

  // Keeps the public listing in step (unlisted games never appear).
  async publish(state, gone = false) {
    if (!state.listing.public) return;
    const dir = directory(this.env);
    if (gone) {
      await dir.fetch(`https://directory/listing/${state.code}`, { method: "DELETE" });
    } else {
      await dir.fetch("https://directory/listing", {
        method: "PUT",
        body: JSON.stringify({ code: state.code, ...state.listing, players: this.players() }),
      });
    }
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > MAX_MESSAGE_BYTES) return;
    let msg;
    try {
      msg = JSON.parse(message);
    } catch {
      return;
    }
    const tags = this.ctx.getTags(ws);
    if (tags.includes("host")) {
      if (msg.type === "heartbeat") {
        const state = await this.ctx.storage.get("room");
        if (state) await this.publish(state);
      } else if (SIGNAL_TYPES.includes(msg.type) && Number.isInteger(msg.to)) {
        for (const g of this.ctx.getWebSockets(`g:${msg.to}`)) g.send(JSON.stringify({ ...msg, from: 1 }));
      }
    } else if (SIGNAL_TYPES.includes(msg.type)) {
      const { id } = ws.deserializeAttachment();
      this.toHost({ ...msg, to: 1, from: id });
    }
  }

  async webSocketClose(ws, code) {
    try {
      ws.close(code === 1005 ? 1000 : code, "Bye.");   // finish the closing handshake
    } catch {
      // already closed
    }
    await this.gone(ws);
  }

  async webSocketError(ws) {
    await this.gone(ws);
  }

  async gone(ws) {
    const state = await this.ctx.storage.get("room");
    const tags = this.ctx.getTags(ws);
    if (tags.includes("host")) {
      // The game ends with its host: retire the code first (so the guests disconnecting below can't put the
      // listing back), then tell the guests' signaling and drop the listing.
      await this.ctx.storage.delete("room");
      for (const g of this.ctx.getWebSockets("guest")) {
        g.send(JSON.stringify({ type: "closed", reason: "The host has stopped hosting." }));
        g.close(1000, "Host left.");
      }
      if (state) await this.publish(state, true);
    } else if (tags.includes("guest")) {
      const id = Number(tags.find((t) => t.startsWith("g:")).slice(2));
      this.toHost({ type: "leave", id });
      // Only while the game still runs: a guest leaving because the host did mustn't re-list a finished game.
      const live = await this.ctx.storage.get("room");
      if (live && this.ctx.getWebSockets("host").length > 0) await this.publish(live);
    }
  }
}

// ---------------------------------------------------------------- public game list

export class Directory extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === "PUT" && url.pathname === "/listing") {
      const l = await request.json();
      await this.ctx.storage.put(`l:${l.code}`, { ...l, updated: Date.now() });
      return new Response("ok");
    }
    if (request.method === "DELETE" && url.pathname.startsWith("/listing/")) {
      await this.ctx.storage.delete(`l:${url.pathname.split("/").pop()}`);
      return new Response("ok");
    }
    const now = Date.now();
    const games = [];
    for (const [key, l] of await this.ctx.storage.list({ prefix: "l:" })) {
      if (now - l.updated > LISTING_STALE_MS) {
        await this.ctx.storage.delete(key);
      } else {
        games.push({ code: l.code, name: l.name, level: l.level, players: l.players, max_players: l.max_players, protocol: l.protocol });
      }
    }
    return json({ games });
  }
}

// ---------------------------------------------------------------- daily global budgets

export class SetupBudget extends DurableObject {
  async fetch(request) {
    const { kind, max } = await request.json();
    const key = `${new Date().toISOString().slice(0, 10)}:${kind}`;
    const used = (await this.ctx.storage.get(key)) || 0;
    if (used >= max) return json({ ok: false });
    await this.ctx.storage.put(key, used + 1);
    return json({ ok: true });
  }
}

// ---------------------------------------------------------------- helpers

function room(env, code) {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

function directory(env) {
  return env.DIRECTORY.get(env.DIRECTORY.idFromName("global"));
}

async function takeBudget(env, kind, max) {
  const stub = env.BUDGET.get(env.BUDGET.idFromName("global"));
  const res = await stub.fetch("https://budget/take", { method: "POST", body: JSON.stringify({ kind, max: Number(max) || 0 }) });
  return (await res.json()).ok;
}

async function allowed(limiter, key) {
  if (!limiter) return true;
  const { success } = await limiter.limit({ key });
  return success;
}

// STUN always; TURN credentials too when a TURN key is set up (they expire after TURN_TTL_SECONDS).
async function iceServers(env) {
  const servers = [];
  const stun = (env.STUN_URLS || "").split(",").map((s) => s.trim()).filter(Boolean);
  if (stun.length) servers.push({ urls: stun });
  if (env.TURN_KEY_ID && env.TURN_API_TOKEN && (await takeBudget(env, "turn", env.MAX_TURN_SESSIONS_PER_DAY))) {
    try {
      const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`, {
        method: "POST",
        headers: { Authorization: `Bearer ${env.TURN_API_TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({ ttl: Number(env.TURN_TTL_SECONDS) || 86400 }),
      });
      if (res.ok) {
        const body = await res.json();
        for (const s of [].concat(body.iceServers || [])) {
          if (s.username) servers.push({ urls: [].concat(s.urls), username: s.username, credential: s.credential });
        }
      }
    } catch {
      // No relay this time; direct connections still work.
    }
  }
  return servers;
}

function validateListing(body) {
  if (!body || typeof body !== "object") return "Expected a JSON body.";
  const name = String(body.name ?? "").trim();
  if (name.length < 1 || name.length > 32 || /[\u0000-\u001f]/.test(name)) return "The game name must be 1 to 32 characters.";
  if (!LEVELS.includes(body.level)) return `Unknown level (one of ${LEVELS.join(", ")}).`;
  const max = Number(body.max_players);
  if (!Number.isInteger(max) || max < MIN_PLAYERS || max > MAX_PLAYERS) return `max_players must be ${MIN_PLAYERS} to ${MAX_PLAYERS}.`;
  const protocol = Number(body.protocol);
  if (!Number.isInteger(protocol) || protocol < 1 || protocol > 65535) return "Missing protocol version.";
  return { name, level: body.level, max_players: max, public: body.public === true, protocol };
}

function refuse(client, server, reason) {
  server.accept();
  server.send(JSON.stringify({ type: "error", reason }));
  server.close(4004, reason.slice(0, 120));
  return new Response(null, { status: 101, webSocket: client });
}

function normalizeCode(text) {
  const code = text.toUpperCase().replace(/-/g, "");
  if (code.length !== CODE_LENGTH) return null;
  for (const c of code) if (!CODE_ALPHABET.includes(c)) return null;
  return code;
}

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

function randomHex(n) {
  return Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
