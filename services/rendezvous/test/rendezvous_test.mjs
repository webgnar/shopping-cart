// Runs the rendezvous Worker locally (wrangler dev, no Cloudflare account) and checks its API:
//   cd services/rendezvous && npm install && npm test
// With RENDEZVOUS_URL set, it tests that server instead of starting one.
import { startDevServer } from "./dev_server.mjs";

let base = process.env.RENDEZVOUS_URL;
let server = null;
let failures = 0;

function check(name, ok, detail = "") {
  if (!ok) failures++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(44)} ${detail}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// A WebSocket with a queue of parsed messages.
function socket(path) {
  const ws = new WebSocket(base.replace(/^http/, "ws") + path);
  const inbox = [];
  const waiters = [];
  ws.addEventListener("message", (e) => {
    const msg = JSON.parse(e.data);
    const w = waiters.shift();
    if (w) w(msg);
    else inbox.push(msg);
  });
  ws.closed = new Promise((r) => ws.addEventListener("close", (e) => r(e)));
  ws.next = (ms = 5000) => {
    if (inbox.length) return Promise.resolve(inbox.shift());
    return new Promise((resolve) => {
      const w = (msg) => {
        clearTimeout(timer);
        resolve(msg);
      };
      const timer = setTimeout(() => {
        waiters.splice(waiters.indexOf(w), 1);   // a later message goes to the inbox, not this finished wait
        resolve(null);
      }, ms);
      waiters.push(w);
    });
  };
  ws.opened = new Promise((r, j) => {
    ws.addEventListener("open", r);
    ws.addEventListener("error", j);
  });
  return ws;
}

async function host(listing) {
  const res = await fetch(`${base}/host`, { method: "POST", body: JSON.stringify(listing) });
  return { status: res.status, body: await res.json() };
}

async function games() {
  return (await (await fetch(`${base}/games`)).json()).games;
}

async function main() {
  if (!base) {
    server = await startDevServer();
    base = server.url;
  }
  check("health", (await fetch(`${base}/health`)).ok);

  // Bad listings are refused.
  check("unknown level refused", (await host({ name: "x", level: "moon", max_players: 4, protocol: 1 })).status === 400);
  check("too many players refused", (await host({ name: "x", level: "market", max_players: 20, protocol: 1 })).status === 400);
  check("empty name refused", (await host({ name: " ", level: "market", max_players: 4, protocol: 1 })).status === 400);

  // A public game.
  const h = await host({ name: "Zack's store", level: "market", max_players: 3, public: true, protocol: 1 });
  check("host gets a code and token", h.status === 200 && /^[A-Z2-9]{8}$/.test(h.body.code) && h.body.token.length === 64, JSON.stringify(h.body).slice(0, 60));
  const code = h.body.code;

  const bad = socket(`/room/${code}/host?token=nope`);
  const badMsg = await bad.next();
  check("wrong host token refused", badMsg?.type === "error", badMsg?.reason);

  const hs = socket(`/room/${code}/host?token=${h.body.token}`);
  const hosted = await hs.next();
  check("host connects", hosted?.type === "hosted" && Array.isArray(hosted.ice_servers), JSON.stringify(hosted));
  check("no STUN when STUN_URLS is empty", hosted?.ice_servers?.length === 0 || !!process.env.RENDEZVOUS_URL);

  let list = await games();
  let g = list.find((x) => x.code === code);
  check("listed publicly", g && g.players === 1 && g.level === "market" && g.name === "Zack's store", JSON.stringify(g));
  check("listing has no token", g && !("token" in g) && !("token_hash" in g));

  // A guest joins by code (lower case, with a dash, still works) and they exchange signaling.
  const gs = socket(`/room/${code.slice(0, 4).toLowerCase()}-${code.slice(4)}/join?protocol=1`);
  const welcome = await gs.next();
  check("guest welcomed", welcome?.type === "welcome" && welcome.id === 2, JSON.stringify(welcome));
  const join = await hs.next();
  check("host told of the guest", join?.type === "join" && join.id === 2, JSON.stringify(join));
  hs.send(JSON.stringify({ type: "offer", to: 2, sdp: "v=0 offer" }));
  const offer = await gs.next();
  check("offer forwarded to the guest", offer?.type === "offer" && offer.sdp === "v=0 offer" && offer.from === 1, JSON.stringify(offer));
  gs.send(JSON.stringify({ type: "answer", sdp: "v=0 answer" }));
  const answer = await hs.next();
  check("answer forwarded to the host", answer?.type === "answer" && answer.from === 2, JSON.stringify(answer));
  gs.send(JSON.stringify({ type: "candidate", mid: "0", index: 0, candidate: "candidate:1 1 UDP 1 127.0.0.1 5000 typ host", to: 99 }));
  const cand = await hs.next();
  check("guest can only signal the host", cand?.type === "candidate" && cand.from === 2 && cand.to === 1, JSON.stringify(cand));
  gs.send(JSON.stringify({ type: "join", id: 5 }));
  check("other message types dropped", (await hs.next(800)) === null);

  list = await games();
  g = list.find((x) => x.code === code);
  check("player count goes up", g?.players === 2, JSON.stringify(g));

  // Full and wrong-version games refuse guests.
  const g3 = socket(`/room/${code}/join?protocol=1`);
  check("third player fits (max 3)", (await g3.next())?.type === "welcome");
  await hs.next();
  const g4 = socket(`/room/${code}/join?protocol=1`);
  const full = await g4.next();
  check("full game refuses", full?.type === "error" && /full/.test(full.reason), full?.reason);
  const old = socket(`/room/${code}/join?protocol=99`);
  const oldMsg = await old.next();
  check("different version refused", oldMsg?.type === "error" && /version/.test(oldMsg.reason), oldMsg?.reason);

  // A guest leaving tells the host.
  g3.close();
  const leave = await hs.next();
  check("host told when a guest leaves", leave?.type === "leave" && leave.id === 3, JSON.stringify(leave));

  // Unlisted game: joinable by code, not in the list.
  const u = await host({ name: "secret", level: "garage", max_players: 4, public: false, protocol: 1 });
  const us = socket(`/room/${u.body.code}/host?token=${u.body.token}`);
  await us.next();
  check("unlisted game not listed", !(await games()).some((x) => x.code === u.body.code));
  const ug = socket(`/room/${u.body.code}/join`);
  check("unlisted game joinable by code", (await ug.next())?.type === "welcome");

  // Unknown code.
  const none = socket(`/room/ABCDEFGH/join`);
  const noneMsg = await none.next();
  check("unknown code refused", noneMsg?.type === "error", noneMsg?.reason);

  // The host leaving ends the game.
  hs.close();
  const closed = await gs.next();
  check("guests told when the host leaves", closed?.type === "closed", JSON.stringify(closed));
  await sleep(300);
  check("listing removed", !(await games()).some((x) => x.code === code));
  const late = socket(`/room/${code}/join`);
  check("code retired", (await late.next())?.type === "error");

  for (const ws of [bad, gs, g4, old, us, ug, none, late]) ws.close();
}

main()
  .catch((e) => {
    failures++;
    console.log("FAIL  " + e.stack);
  })
  .finally(() => {
    console.log(`RESULT: ${failures ? `FAILURES (${failures})` : "ALL PASS"}`);
    if (server) server.stop();
    process.exit(failures ? 1 : 0);
  });
