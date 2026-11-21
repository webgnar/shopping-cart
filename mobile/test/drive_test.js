// Headless test for the browser version: the same drive checks as the Godot drive test
// (shopping-cart/tests/drive_test.gd), plus every level, spare carts, bot carts, cart-to-cart hits, stacked carts, the follow camera,
// the race down the garage, the supermarket sweep, the phone's touch rockers, the keyboard and the console.
//   node mobile/test/drive_test.js [screenshot-dir]
// Serves mobile/ on a local port (the game fetches its levels, so it can't run from file://).
const { chromium, devices } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');

const ROOT = path.join(__dirname, '..');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.wasm': 'application/wasm' };
const shots = process.argv[2];

function serve() {
  return new Promise(res => {
    const srv = http.createServer((q, r) => {
      let f = path.join(ROOT, decodeURIComponent(q.url.split('?')[0]));
      if (!f.startsWith(ROOT)) { r.writeHead(403); r.end(); return; }
      if (f.endsWith(path.sep)) f += 'index.html';
      fs.readFile(f, (e, d) => {
        if (e) { r.writeHead(404); r.end(); return; }
        r.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream' }); r.end(d);
      });
    }).listen(0, () => res(srv));
  });
}

// name, input held {L, R: -1/0/1, lift, press}, seconds, check  (sandbox, asphalt at (-10, 0, -3))
const SCENARIOS = [
  ['idle', {}, 5.0, 'still'],
  ['E+Q both push', { L: 1, R: 1 }, 1.5, 'forward_straight'],
  ['A+D both pull', { L: -1, R: -1 }, 1.5, 'backward'],
  ['Q right push', { R: 1 }, 1.5, 'turns_left'],
  ['E left push', { L: 1 }, 1.5, 'turns_right'],
  ['E+D spin', { L: 1, R: -1 }, 1.2, 'spins_right'],
  ['S front up', { press: true }, 1.5, 'wheelie'],
  ['W back up', { lift: true }, 1.5, 'rear_up'],
  ['W+Q right side up', { lift: true, R: 1 }, 1.5, 'right_up'],
  ['E+Q short push', { L: 1, R: 1 }, 1.2, 'flat'],
  ['E+Q hard push', { L: 1, R: 1 }, 2.1, 'wheelie'],
  ['A+D hard pull', { L: -1, R: -1 }, 2.6, 'rear_up'],
  ['coast then rest', { coast: true }, 30.0, 'comes_to_rest'],
  ['rested 4 s, then E+Q', { L: 1, R: 1 }, 1.5, 'wakes_and_moves'],
];

(async () => {
  const srv = await serve();
  const url = `http://localhost:${srv.address().port}/index.html`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const errors = [];
  let failures = 0;
  const report = (ok, name, text) => { if (ok === false) failures++; console.log(`${ok === null ? 'info' : ok ? 'PASS' : 'FAIL'}  ${name.padEnd(24)} ${text}`); };
  const open = async (opts, query = '') => {
    const page = await browser.newPage(opts);
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
    await page.goto(url + query);
    await page.waitForFunction(() => window.__cart && !document.getElementById('go').disabled, null, { timeout: 180000 });
    return page;
  };

  // ------------------------------------------------------------ drive checks (computer, sandbox)
  const page = await open({ viewport: { width: 1280, height: 720 } }, '?level=sandbox&controls=desk');
  await page.click('#go');
  // Helpers the checks share, defined once in the page.
  await page.evaluate(() => {
    const c = window.__cart;
    window.T = {
      c, STEP: 1 / 120,
      basis() { const q = c.cart.frame.rotation(), x = q.x, y = q.y, z = q.z, w = q.w;
        return { x: { x: 1 - 2 * (y * y + z * z), y: 2 * (x * y + w * z), z: 2 * (x * z - w * y) },
                 y: { x: 2 * (x * y - w * z), y: 1 - 2 * (x * x + z * z), z: 2 * (y * z + w * x) },
                 z: { x: 2 * (x * z + w * y), y: 2 * (y * z - w * x), z: 1 - 2 * (x * x + y * y) } }; },
      along() { const b = T.basis(), lv = c.cart.frame.linvel(), h = Math.hypot(b.x.x, b.x.z) || 1; return (lv.x * b.x.x + lv.z * b.x.z) / h; },
      wy(k) { return c.cart.wheels[k].translation().y; },
      rotq(q, v) { const [x, y, z] = v, ix = q.w * x + q.y * z - q.z * y, iy = q.w * y + q.z * x - q.x * z, iz = q.w * z + q.x * y - q.y * x, iw = -q.x * x - q.y * y - q.z * z;
        return { x: ix * q.w + iw * -q.x + iy * -q.z - iz * -q.y, y: iy * q.w + iw * -q.y + iz * -q.x - ix * -q.z, z: iz * q.w + iw * -q.z + ix * -q.y - iy * -q.x }; },
      fresh(x = -10, z = -3, settle = 1.0) { c.setInput(null); c.spawn(c.v3(x, 0, z), 0); c.setInput({}); c.simulate(settle); return c.cart; },
      hold(inp, s, sample) { c.setInput(inp); c.simulate(s, sample); c.setInput({}); },
    };
  });

  for (const [name, inp, secs, check] of SCENARIOS) {
    const r = await page.evaluate(([name, inp, secs, check]) => {
      const c = T.c, cart = T.fresh(-10, -3);
      if (check === 'wakes_and_moves') c.simulate(4.0);
      const p0 = { ...cart.origin() }, h0 = cart.heading(), wasPinned = cart.pinned;
      let maxFront = 0, maxRear = 0, maxRight = 0, maxPitch = 0, i = 0;
      const coast = !!inp.coast;
      c.setInput(coast ? { R: 1 } : inp);
      c.simulate(secs, () => {
        if (coast && ++i === 120) c.setInput({});
        const b = T.basis();
        maxPitch = Math.max(maxPitch, Math.abs(Math.asin(b.x.y)) * 57.3);
        maxRear = Math.max(maxRear, Math.min(T.wy('RL'), T.wy('RR')));
        maxFront = Math.max(maxFront, Math.min(T.wy('FL'), T.wy('FR')));
        maxRight = Math.max(maxRight, Math.asin(Math.max(-1, Math.min(1, b.z.y))) * 57.3);
      });
      c.setInput({});
      const p1 = cart.origin(), along = T.along();
      let turn = (cart.heading() - h0) * 57.2958; turn = ((turn + 540) % 360) - 180;
      return { d: Math.hypot(p1.x - p0.x, p1.z - p0.z), along, turn, maxPitch, maxFront, maxRear, maxRight, pinned: cart.pinned,
        wasPinned, wheels: cart.wheelsDown(), up: T.basis().y.y, groceries: cart.groceriesIn(), nan: !Number.isFinite(p1.x) };
    }, [name, inp, secs, check]);
    const ok = !r.nan && {
      still: r.d < 0.005 && Math.abs(r.turn) < 0.1 && r.pinned,
      forward_straight: r.along > 1.0 && Math.abs(r.turn) < 12,
      backward: r.along < -0.7 && Math.abs(r.turn) < 25,
      turns_left: r.turn > 30, turns_right: r.turn < -30,
      spins_right: r.turn < -60 && r.d < 1.0,
      wheelie: r.maxFront > 0.12 && r.maxRear < 0.09,
      rear_up: r.maxRear > 0.10 && r.maxFront < 0.09,
      right_up: r.maxRight > 5,
      flat: r.along > 2.0 && r.maxRear < 0.09 && r.maxFront < 0.09 && r.wheels === 4,
      wakes_and_moves: r.wasPinned && r.along > 1.0,
      comes_to_rest: r.pinned,
    }[check];
    report(ok, name, `moved ${r.d.toFixed(2)} m  speed ${r.along >= 0 ? '+' : ''}${r.along.toFixed(2)} m/s  turned ${Math.round(r.turn)} deg  pitch ${r.maxPitch.toFixed(0)}  front up ${r.maxFront.toFixed(2)}  rear up ${r.maxRear.toFixed(2)}  right up ${r.maxRight.toFixed(0)}  groceries ${r.groceries}${r.pinned ? '  (pinned)' : ''}`);
  }

  // Pulling back to stop a rolling cart (body plants, arms straighten).
  for (const pushS of [1.0, 1.8]) for (const mode of ['coast', 'brake']) {
    const r = await page.evaluate(([pushS, mode]) => {
      const c = T.c, cart = T.fresh(-14, -3, 0.5);
      T.hold({ L: 1, R: 1 }, pushS);
      const v0 = T.along(), p0 = { ...cart.origin() };
      c.setInput(mode === 'brake' ? { L: -1, R: -1 } : {});
      let t = 0, maxPitch = 0, done = false;
      c.simulate(8, () => {
        if (done) return;
        t += T.STEP;
        maxPitch = Math.max(maxPitch, Math.asin(T.basis().x.y) * 57.3);
        if (T.along() < 0.05) { done = true; c.setInput({}); }
      });
      c.setInput({});
      const p1 = cart.origin();
      return { v0, dist: Math.hypot(p1.x - p0.x, p1.z - p0.z), t, maxPitch, groceries: cart.groceriesIn() };
    }, [pushS, mode]);
    const ok = mode === 'coast' ? null : r.dist < 0.08 * r.v0 * 3.6 && r.t < 1.5 && r.maxPitch < 25 && r.groceries >= 4;
    report(ok, `${pushS} s push, ${mode === 'brake' ? 'pull' : 'let go'}`, `from ${(r.v0 * 3.6).toFixed(1)} km/h: stopped in ${r.dist.toFixed(2)} m and ${r.t.toFixed(2)} s, nose up ${r.maxPitch.toFixed(0)} deg, groceries ${r.groceries}/5`);
  }

  // Pushing and pulling build power the same way.
  const acc = await page.evaluate(() => {
    const out = {};
    for (const [k, d] of [['push', 1], ['pull', -1]]) { T.fresh(-10, -3, 0.5); T.hold({ L: d, R: d }, 0.5); const lv = T.c.cart.frame.linvel(); out[k] = Math.hypot(lv.x, lv.z); }
    return out;
  });
  report(Math.abs(acc.pull - acc.push) < 0.1 * acc.push, 'pull = push', `after 0.5 s from rest: pushing ${acc.push.toFixed(2)} m/s, pulling ${acc.pull.toFixed(2)} m/s`);

  // Countering a spin with the other hand stops it.
  for (const [first, then, label] of [[{ L: -1 }, { R: -1 }, 'A spin, then D'], [{ L: 1, R: -1 }, { L: -1, R: 1 }, 'E+D spin, then A+Q']]) {
    const r = await page.evaluate(([first, then]) => {
      const c = T.c, cart = T.fresh();
      T.hold(first, 1.5);
      const w0 = cart.frame.angvel().y * 57.3;
      c.setInput(then);
      let t = -1, i = 0, minWheels = 4;
      c.simulate(1.5, () => { i++; minWheels = Math.min(minWheels, cart.wheelsDown()); if (t < 0 && cart.frame.angvel().y * 57.3 * Math.sign(w0) < 10) t = i / 120; });
      c.setInput({});
      return { w0, t, minWheels };
    }, [first, then]);
    report(Math.abs(r.w0) > 90 && r.t > 0 && r.t < 1.0 && r.minWheels >= 2, label, `spinning ${Math.round(r.w0)} deg/s, stopped in ${r.t.toFixed(2)} s (wheels down at least ${r.minWheels})`);
  }

  // Hard push / pull tips the cart: hold on and it may go over, let go as soon as an end lifts and it comes down.
  // A push starts 25 m further back: let go at a run, the cart coasts about 30 m, and from (-10, -3) that reaches the
  // sandbox's speed bump at x = 14, which trips it over.
  for (const [dir, after, falls] of [[1, 4.0, true], [-1, 4.0, true], [1, 0.0, false], [-1, 0.0, false]]) {
    const r = await page.evaluate(([dir, after]) => {
      const c = T.c, cart = T.fresh(dir > 0 ? -35 : -10, -3);
      c.setInput({ L: dir, R: dir });
      let held = 0, lifted = 0, stop = false;
      c.simulate(6, () => {
        if (stop) return;
        held += T.STEP;
        const up = dir > 0 ? Math.min(T.wy('FL'), T.wy('FR')) : Math.min(T.wy('RL'), T.wy('RR'));
        if (up > 0.15 && !lifted) lifted = held;
        if (lifted && held >= lifted + after) { stop = true; c.setInput({}); }
      });
      c.setInput({}); c.simulate(3);
      const b = T.basis();
      return { lifted, fell: b.y.y < 0.7, up: b.y.y, pitch: Math.asin(b.x.y) * 57.3, wheels: cart.wheelsDown(), offFloor: cart.origin().y < -1 };
    }, [dir, after]);
    // Held on for 4 s at a run, the cart can leave the sandbox floor altogether; that's reported, not failed.
    const ok = r.offFloor && after > 0 ? null : r.lifted > 0 && (r.fell === falls || after > 0) && (r.fell || r.wheels === 4);
    if (r.offFloor) r.fell = 'ran off the floor';
    report(ok, 'hard ' + (dir > 0 ? 'push' : 'pull'), `${dir > 0 ? 'front' : 'rear'} lifted after ${r.lifted.toFixed(1)} s, let go ${after} s later: ${r.fell === true ? 'fell over' : r.fell || 'back on its wheels'} (up ${r.up.toFixed(2)}, pitch ${Math.round(r.pitch)}, wheels ${r.wheels})`);
  }

  // Holding W or S tips it over; a short hold only leans. Then letting go and holding the same key rights it.
  for (const [key, secs, falls] of [['press', 4.0, true], ['lift', 4.0, true], ['press', 0.8, false], ['lift', 0.8, false]]) {
    const r = await page.evaluate(([key, secs]) => {
      const c = T.c, cart = T.fresh();
      T.hold({ [key]: true }, secs); c.simulate(3);
      const b = T.basis(), fell = b.y.y < 0.4, pitch = Math.asin(Math.max(-1, Math.min(1, b.x.y))) * 57.3;
      let tUp = -1;
      if (fell) {
        let i = 0;
        c.setInput({ [key]: true });
        c.simulate(5, () => { i++; if (tUp < 0 && T.basis().y.y > 0.95) tUp = i / 120; });
        c.setInput({}); c.simulate(3);
      }
      return { fell, pitch, tUp, wheels: cart.wheelsDown() };
    }, [key, secs]);
    let ok = r.fell === falls && (r.fell || r.wheels === 4);
    if (r.fell) ok = ok && (key === 'press' ? r.pitch > 45 : r.pitch < -45) && r.tUp > 0 && r.wheels === 4;
    report(ok, `${key === 'press' ? 'S' : 'W'} held ${secs} s`, `${r.fell ? 'fell over' : 'back on its wheels'} (pitch ${Math.round(r.pitch)})${r.fell ? `, same key again: ${r.tUp > 0 ? 'upright in ' + r.tUp.toFixed(2) + ' s' : 'still down'}, ${r.wheels}/4 wheels down` : ''}`);
  }

  // Getting back up with a hand key after going over (hard push, hard pull, on its side).
  for (const setup of ['push', 'pull', 'side']) {
    const r = await page.evaluate(setup => {
      const c = T.c, cart = T.fresh();
      if (setup === 'side') {
        c.setInput(null); c.spawn(c.v3(-10, 0, -3), 0); c.setInput({});
        const q = { x: Math.SQRT1_2, y: 0, z: 0, w: Math.SQRT1_2 };   // rolled 90 degrees onto its side
        const f = c.cart.frame.translation();
        for (const b of c.cart.parts) { const p = b.translation(), d = { x: p.x - f.x, y: p.y - f.y, z: p.z - f.z };
          const r = { x: d.x, y: -d.z, z: d.y }; b.setTranslation({ x: f.x + r.x, y: 0.4 + r.y, z: f.z + r.z }, true); b.setRotation(q, true); }
        for (const g of c.cart.groceries) g.setTranslation({ x: -20, y: 0.2, z: 10 }, true);
        c.simulate(2);
      } else {
        const d = setup === 'push' ? 1 : -1;
        let held = 0, stop = false;
        c.setInput({ L: d, R: d });
        c.simulate(8, () => { if (stop) return; held += T.STEP; if (T.basis().y.y < 0.3) { stop = true; c.setInput({}); } });
        c.setInput({}); c.simulate(3);
      }
      const cartNow = c.cart, downUp = T.basis().y.y, wasFallen = cartNow.fallen, p0 = { ...cartNow.origin() };
      let tUp = -1, i = 0;
      c.setInput({ R: 1 });
      c.simulate(5, () => { i++; if (tUp < 0 && T.basis().y.y > 0.95) { tUp = i / 120; c.setInput({}); } });
      c.setInput({});
      const p1 = cartNow.origin(), slid = Math.hypot(p1.x - p0.x, p1.z - p0.z);
      c.simulate(3);
      return { downUp, wasFallen, tUp, slid, wheels: cartNow.wheelsDown() };
    }, setup);
    report(r.wasFallen && r.downUp < 0.3 && r.tUp > 0 && r.wheels === 4 && r.slid < 3.0, `get up (${setup})`,
      `lying at up ${r.downUp.toFixed(2)} (fallen ${r.wasFallen}), Q held: ${r.tUp > 0 ? 'upright in ' + r.tUp.toFixed(2) + ' s' : 'still down after 5 s'}, moved ${r.slid.toFixed(2)} m, ${r.wheels}/4 wheels down`);
  }

  // Gate, seat flap and backrest hinges (limits and resting on their stops).
  const hinge = await page.evaluate(() => {
    const c = T.c, out = {};
    const angle = (a, b) => { const d = Math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w); return 2 * Math.acos(Math.min(1, d)) * 57.3; };
    const yAxis = q => { const x = q.x, y = q.y, z = q.z, w = q.w; return { x: 2 * (x * y - w * z), y: 1 - 2 * (x * x + z * z), z: 2 * (y * z + w * x) }; };
    const between = (a, b) => Math.acos(Math.max(-1, Math.min(1, a.x * b.x + a.y * b.y + a.z * b.z))) * 57.3;
    // gate: empty basket so it can fall back
    let cart = T.fresh(-10, -3, 0.5);
    for (const g of cart.groceries) g.setTranslation({ x: -20, y: 0.2, z: 10 }, true);
    c.simulate(0.2);
    const gate = cart.gate, g0 = yAxis(gate.rotation());
    let i = 0;
    c.simulate(20 / 120, null, () => { const b = T.basis(); const at = gate.translation(), gy = yAxis(gate.rotation());
      gate.applyImpulseAtPoint({ x: b.x.x * 25 / 120, y: b.x.y * 25 / 120, z: b.x.z * 25 / 120 }, { x: at.x - gy.x * 0.5, y: at.y - gy.y * 0.5, z: at.z - gy.z * 0.5 }, true); });
    out.gateSwing = between(g0, yAxis(gate.rotation()));
    c.simulate(1.5);
    out.gateBack = between(g0, yAxis(gate.rotation()));
    for (const [name, key, push, dirLocal, force] of [['flap', 'SeatFlap', [0.13, 0, 0], 'up', 6], ['seat', 'ChildSeat', [0.13, 0.47, 0], 'left', 10]]) {
      cart = T.fresh(-10, -3, 0.5);
      const body = cart.b[key], b0 = yAxis(body.rotation());
      const start = angle(cart.gate.rotation(), body.rotation());
      let maxSwing = 0;
      const pushAt = () => { const p = body.translation(), v = T.rotq(body.rotation(), push); return { x: p.x + v.x, y: p.y + v.y, z: p.z + v.z }; };
      c.simulate(30 / 120, () => { maxSwing = Math.max(maxSwing, between(b0, yAxis(body.rotation()))); }, () => {
        const b = T.basis(), d = dirLocal === 'up' ? b.y : { x: -b.x.x, y: -b.x.y, z: -b.x.z };   // Godot Vector3.LEFT is -X
        body.applyImpulseAtPoint({ x: d.x * force / 120, y: d.y * force / 120, z: d.z * force / 120 }, pushAt(), true);
      });
      c.simulate(2);
      const stays = between(b0, yAxis(body.rotation()));
      if (key === 'ChildSeat') { c.simulate(30 / 120, null, () => { const b = T.basis(); body.applyImpulseAtPoint({ x: b.x.x * force / 120, y: b.x.y * force / 120, z: b.x.z * force / 120 }, pushAt(), true); }); c.simulate(2); }
      out[name] = { start, maxSwing, stays, back: between(b0, yAxis(body.rotation())) };
    }
    return out;
  });
  report(hinge.gateSwing > 10 && hinge.gateSwing < 75 && hinge.gateBack < 5, 'gate', `swung ${hinge.gateSwing.toFixed(0)} deg when shoved, back to ${hinge.gateBack.toFixed(0)} deg after`);
  report(hinge.flap.start < 2 && hinge.flap.maxSwing > 20 && hinge.flap.maxSwing < 110 && hinge.flap.back < 3, 'seat flap', `at rest ${hinge.flap.start.toFixed(1)} deg off its stop, swung ${hinge.flap.maxSwing.toFixed(0)} deg when pushed, back to ${hinge.flap.back.toFixed(1)} deg`);
  report(hinge.seat.start < 2 && hinge.seat.maxSwing > 5 && hinge.seat.maxSwing < 33 && hinge.seat.stays > 25 && hinge.seat.back < 3, 'seat backrest', `at rest ${hinge.seat.start.toFixed(1)} deg, swung ${hinge.seat.maxSwing.toFixed(0)} deg, stayed folded at ${hinge.seat.stays.toFixed(0)} deg, back to ${hinge.seat.back.toFixed(1)} deg`);

  // A pinned cart is knocked loose when a box hits it.
  const knock = await page.evaluate(() => {
    const c = T.c, R = c.RAPIER, cart = T.fresh(-10, -3, 2.0);
    const pinned = cart.pinned, p0 = { ...cart.origin() };
    // 8 kg box thrown at the cart's left side, as in the Godot test.
    const box = c.world.createRigidBody(R.RigidBodyDesc.dynamic().setTranslation(-10 + 0.55, 0.7, -3 - 1.2).setLinvel(0, 0, 4));
    c.world.createCollider(R.ColliderDesc.cuboid(0.15, 0.15, 0.15).setDensity(8 / 0.027).setCollisionGroups((1 << 16) | 0xfff1), box);
    c.simulate(1.5);
    const p1 = cart.origin();
    c.world.removeRigidBody(box);
    return { pinned, knocked: Math.hypot(p1.x - p0.x, p1.z - p0.z) };
  });
  report(knock.pinned && knock.knocked > 0.03, 'knocked when pinned', `pinned at rest: ${knock.pinned}, moved ${knock.knocked.toFixed(2)} m when a box hit it`);

  // Keyboard: real key presses drive the cart; the HUD bars follow the hands.
  const kb = await page.evaluate(() => { T.fresh(-10, -3, 0.5); T.c.setInput(null); return { ...T.c.cart.origin() }; });
  await page.keyboard.down('KeyQ'); await page.keyboard.down('KeyE'); await page.waitForTimeout(1200);
  const kbBar = await page.evaluate(() => [T.c.cart.handPower.L, document.getElementById('pushL').style.height]);
  await page.keyboard.up('KeyQ'); await page.keyboard.up('KeyE');
  const kb1 = await page.evaluate(() => ({ ...T.c.cart.origin() }));
  const kbMoved = Math.hypot(kb1.x - kb.x, kb1.z - kb.z);
  report(kbMoved > 0.001 && kbBar[0] > 25 && parseFloat(kbBar[1]) > 0, 'keys Q+E', `moved ${kbMoved.toFixed(2)} m, left hand ${Math.round(kbBar[0])} N, bar ${kbBar[1]}`);

  // Console: ` opens it, `garage` fast-travels.
  await page.keyboard.press('Backquote');
  await page.waitForTimeout(300);
  await page.keyboard.type('garage');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => window.__cart.levelKey === 'garage', null, { timeout: 120000 }).catch(() => {});
  const lk = await page.evaluate(() => ({ key: window.__cart.levelKey, open: !document.getElementById('console').hidden }));
  report(lk.key === 'garage' && !lk.open, 'console: garage', `level now ${lk.key}, console ${lk.open ? 'open' : 'closed'}`);

  // ------------------------------------------------------------ every level
  for (const lv of await page.evaluate(() => window.__cart.levels.map(l => l.key))) {
    const r = await page.evaluate(async key => {
      const c = window.__cart;
      await c.loadLevel(key);
      c.setInput({});
      const cart = c.cart, s = c.level.spawn;
      c.simulate(3);
      const p = cart.origin(), spares = c.spares.length, wheels = cart.wheelsDown(), pinned = cart.pinned;
      const sparesPinned = c.spares.filter(x => x.pinned).length;
      // Drive forward 2 s, then let it settle: never falls through the floor.
      c.setInput({ L: 1, R: 1 }); c.simulate(2); c.setInput({}); c.simulate(2);
      const p2 = cart.origin();
      // Camera: sweep around the cart, never inside the level.
      let inside = 0, minGap = 9;
      for (let a = 0; a < 24; a++) {
        c.cam.yaw = a / 24 * Math.PI * 2; c.renderOnce(0.5); c.renderOnce(0.5);
        const cp = c.camera.position;
        const hit = c.world.projectPoint({ x: cp.x, y: cp.y, z: cp.z }, true, undefined, (1 << 16) | 1);
        const gap = hit ? Math.hypot(hit.point.x - cp.x, hit.point.y - cp.y, hit.point.z - cp.z) * (hit.isInside ? -1 : 1) : 9;
        minGap = Math.min(minGap, gap); if (gap < 0.05) inside++;
      }
      c.cam.yaw = 0; c.renderOnce();
      // Wheel sounds: a fresh cart at the spawn is quiet at rest; pushed, every wheel rolls on this floor without
      // scrubbing; then a wheelie (S) lifts the front wheels quiet, and setting them down lands them.
      c.spawn(c.v3(...s.pos), s.yaw); c.setInput({}); c.simulate(3);
      const sound = c.cart.sound, sw = sound.wheels;
      const rolling = { atRest: sound.playing(), loaded: c.loadedLoops(), maxScrub: 0 };
      c.setInput({ L: 1, R: 1 }); c.simulate(1.5, () => { for (const w of Object.values(sw)) rolling.maxScrub = Math.max(rolling.maxScrub, w.scrub.gain); });
      rolling.floors = [...new Set(Object.values(sw).map(w => w.floor ? w.floor.name : 'air'))];
      rolling.gain = Math.min(...Object.values(sw).map(w => w.roll.gain));
      rolling.speed = sw.RL.rollSpeed;
      let up = 0, quiet = 0; const l0 = sw.FL.landings + sw.FR.landings;
      c.setInput({ L: 1, R: 1, press: true });
      c.simulate(0.7, () => { if (!sw.FL.grounded && !sw.FR.grounded) { up++; if (sw.FL.roll.gain === 0 && sw.FR.roll.gain === 0 && sw.RL.roll.gain > 0.5) quiet++; } });
      c.setInput({}); c.simulate(1.0);
      Object.assign(rolling, { up, quiet, landed: sw.FL.landings + sw.FR.landings - l0, impact: Math.max(sw.FL.lastImpact, sw.FR.lastImpact), slammed: sw.FL.slams + sw.FR.slams });
      sound.update(0.1);
      // Traffic (TrafficLane / TrafficRoute): every car drives on at its lane's speed (0.5 s, so none loops round).
      const cars = c.level.traffic || [], t0 = cars.map(k => ({ ...k.body.translation() }));
      c.simulate(0.5);
      const traffic = cars.map((k, i) => { const t = k.body.translation(); return Math.hypot(t.x - t0[i].x, t.y - t0[i].y, t.z - t0[i].z) / 0.5 / k.speed; });
      return { spawnDrop: s.pos[1] - p.y, wheels, pinned, spares, sparesPinned, fell: p2.y < s.pos[1] - 1,
        moved: Math.hypot(p2.x - p.x, p2.z - p.z), inside, minGap, rolling, traffic, ...c.stats() };
    }, lv);
    const want = { plot: 'asphalt', garage: 'concrete', market: 'tile' }[lv];
    const rs = r.rolling;
    report(rs.floors.length === 1 && (!want || rs.floors[0] === want) && rs.gain > 0.9 && rs.maxScrub < 0.2 && rs.atRest.length === 0
      && rs.loaded.length === 12 && rs.up > 20 && rs.quiet > 10 && rs.landed > 0, `sound ${lv}`,
      `every wheel on ${rs.floors}${want ? ' (expected ' + want + ')' : ''} at ${rs.speed.toFixed(1)} m/s, quietest gain ${rs.gain.toFixed(2)}, scrub ${rs.maxScrub.toFixed(2)}, at rest playing [${rs.atRest}]; wheelie: front up ${rs.up} ticks, quiet ${rs.quiet}, landings ${rs.landed} (${rs.slammed} slams) at ${rs.impact.toFixed(2)} m/s; sounds loaded ${rs.loaded.length}/12`);
    report(Math.abs(r.spawnDrop) < 0.1 && r.wheels === 4 && r.pinned && !r.fell && r.moved > 1 && r.inside === 0, `level ${lv}`,
      `spawned on 4 wheels and came to rest: ${r.wheels === 4 && r.pinned}, drove ${r.moved.toFixed(1)} m, camera never inside walls (closest ${r.minGap.toFixed(2)} m), ${r.spares} spare carts (${r.sparesPinned} at rest), ${r.meshes} meshes, ${r.drawCalls} draws, ${Math.round(r.triangles / 1000)}k triangles`);
    if (r.traffic.length) {
      const ok = r.traffic.filter(f => f > 0.9 && f < 1.1).length;
      report(ok >= r.traffic.length - 2, `traffic ${lv}`, `${ok} of ${r.traffic.length} cars drove at their lane's speed`);
    }
    if (shots) await page.screenshot({ path: path.join(shots, `level_${lv}.png`), timeout: 180000 });
  }

  // Background loop: the parking lot plays its loop (as the Godot level's BackgroundMusic), fast travel stops it.
  const music = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('plot');
    for (let i = 0; i < 100 && !(c.musicState().playing && c.musicState().passes >= 1); i++) await new Promise(r => setTimeout(r, 200));
    const plot = c.musicState();
    await c.loadLevel('garage');
    return { plot, garage: c.musicState() };
  });
  report(music.plot.playing && music.plot.loaded && music.plot.passes >= 1 && music.plot.nextIn > 400 && music.plot.volumeDb < -6 && !music.garage.playing && !music.garage.file,
    'background music', `parking lot: ${music.plot.file} playing ${music.plot.playing} at ${music.plot.volumeDb} dB, ${music.plot.passes} pass playing, next in ${Math.round(music.plot.nextIn)} s; garage: playing ${music.garage.playing}`);

  // Endless sandbox: the same chunk layout as Godot (its exported check table), chunks around the cart, and after a
  // jump far away the ground is there under a 4 m grid around the cart (shopping-cart/tests/sandbox_test.gd in Godot).
  const sb = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('sandbox');
    const st = c.streamer, start = st.loaded.size;
    const far = { x: 328, y: 0, z: 298 };
    await st.prime(far);
    const [i, j] = st.cellOf(far);
    const x0 = st.origin.x + i * st.size + 1.5, z0 = st.origin.z + j * st.size + 1.5;   // a chunk corner: always flat
    c.spawn(c.v3(x0, 0.05, z0), 0); c.setInput({}); c.simulate(1);
    const landed = { ...c.cart.origin() };
    let holes = 0;
    for (let x = -40; x <= 40; x += 4) for (let z = -40; z <= 40; z += 4) {
      const hit = c.world.castRay(new c.RAPIER.Ray({ x: x0 + x + 0.13, y: 20, z: z0 + z + 0.13 }, { x: 0, y: -1, z: 0 }), 30, true, undefined, (1 << 16) | 1);
      if (!hit || hit.timeOfImpact > 20.05) holes++;
    }
    const kinds = new Set([...st.loaded.values()].map(k => st.pick(k.i, k.j)[0]));
    c.setInput({ L: 1, R: 1 }); c.simulate(2); c.setInput({}); c.simulate(1);
    c.renderOnce();
    return { check: st.selfCheck(), start, after: st.loaded.size, holes, landed, kinds: kinds.size, kindsTotal: st.s.chunks.length, ...c.stats() };
  });
  report(sb.check && sb.start >= 8 && sb.holes === 0 && Math.abs(sb.landed.y) < 0.1 && sb.kinds >= Math.min(3, sb.kindsTotal), 'sandbox stream',
    `layout matches Godot: ${sb.check}, ${sb.start} chunks at the start, ${sb.after} after the jump (${sb.kinds} kinds), holes ${sb.holes}, landed at y ${sb.landed.y.toFixed(2)}, ${sb.drawCalls} draws, ${Math.round(sb.triangles / 1000)}k triangles`);
  if (shots) await page.screenshot({ path: path.join(shots, 'sandbox_stream.png'), timeout: 180000 });

  // Bot carts: each level's bots drive themselves for 60 s through the player's keys, reach spots on the navigation
  // mesh and stay on their wheels (the same checks as shopping-cart/tests/bot_test.gd).
  for (const lv of ['market', 'plot', 'garage']) {
    const r = await page.evaluate(async key => {
      const c = window.__cart;
      await c.loadLevel(key);
      c.setInput({});
      const bots = c.bots, last = bots.map(b => ({ ...b.cart.origin() })), moved = bots.map(() => 0), low = bots.map(b => b.cart.origin().y);
      let n = 0;
      const t0 = performance.now();
      c.simulate(60, () => {
        if (++n % 12) return;
        bots.forEach((b, i) => { const p = b.cart.origin(); moved[i] += Math.hypot(p.x - last[i].x, p.z - last[i].z); last[i] = { ...p }; low[i] = Math.min(low[i], p.y); });
      });
      return { ms: performance.now() - t0, bots: bots.map((b, i) => ({ moved: moved[i], drop: bots[i].cart.origin().y - low[i], low: low[i], fallen: b.cart.fallen, stats: b.stats })) };
    }, lv);
    report(r.bots.length >= 2, `bots ${lv}`, `${r.bots.length} bot carts, 60 s simulated in ${(r.ms / 1000).toFixed(0)} s`);
    r.bots.forEach((b, i) => report(b.moved > 24 && b.stats.trips + b.stats.gave_up >= 1 && !b.fallen && b.low > -2, `bots ${lv} #${i + 1}`,
      `${b.moved.toFixed(0)} m, ${JSON.stringify(b.stats)}, fallen ${b.fallen}, lowest y ${b.low.toFixed(2)}`));
    if (shots) { await page.evaluate(() => window.__cart.renderOnce()); await page.screenshot({ path: path.join(shots, `bots_${lv}.png`), timeout: 180000 }); }
  }

  // Race (race.js, as shopping-cart/tests/race_test.gd): `race` goes to the garage and lines you and the bots up on
  // the roof; nobody moves during 3, 2, 1 even with both hands held; at GO you go. Then your cart is put before the
  // finish line and pushed over it, and the bots race all ten floors down to it.
  const rc = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('sandbox');
    c.runCommand('race');
    for (let i = 0; i < 300 && !(c.levelKey === 'garage' && c.race && c.race.phase === 2); i++) await new Promise(r => setTimeout(r, 100));
    const race = c.race, out = { level: c.levelKey, phase: race && race.phase, racers: race ? race.racers.length : 0 };
    if (!race) return out;
    const slotOff = race.racers.map((r, i) => { const p = race.cartOf(r).origin(), s = race.D.slots[i].pos; return Math.hypot(p.x - s[0], p.z - s[2]); });
    out.slotOff = Math.max(...slotOff);
    const p0 = { ...c.cart.origin() };
    c.setInput({ L: 1, R: 1 }); c.simulate(2.9);
    out.heldMoved = Math.hypot(c.cart.origin().x - p0.x, c.cart.origin().z - p0.z);
    out.countShown = !document.getElementById('raceCount').hidden;
    c.simulate(1.2);
    out.goMoved = Math.hypot(c.cart.origin().x - p0.x, c.cart.origin().z - p0.z); out.phaseAfter = race.phase;
    c.setInput({}); c.simulate(1);
    const f = race.D.finish.xf;
    c.spawn(c.v3(f[9] - 1.6, 0, -3), 0); c.simulate(0.3);
    c.setInput({ L: 1, R: 1 }); c.simulate(6); c.setInput({});
    out.myTime = race.racers[0].time;
    const t0 = performance.now();
    race.D.finish_grace = 400;
    for (let s = 0; s < 360 && race.phase !== 4; s += 10) c.simulate(10);
    out.ms = performance.now() - t0;
    out.done = race.phase === 4; out.bots = race.racers.slice(1).map(r => r.time); out.puts = race.racers.slice(1).map(r => r.bot.stats.put_back);
    c.renderOnce();
    out.results = !document.getElementById('raceResults').hidden && document.getElementById('raceTable').textContent;
    return out;
  });
  report(rc.level === 'garage' && rc.phase === 2 && rc.racers === 4 && rc.slotOff < 0.15, 'race: line-up',
    `race took us to ${rc.level}, counting down, ${rc.racers} racers, all within ${(rc.slotOff ?? 9).toFixed(2)} m of their slots`);
  report(rc.heldMoved < 0.05 && rc.countShown && rc.goMoved > 0.3 && rc.phaseAfter === 3, 'race: 3 2 1 GO',
    `holding both pushes through the count moved ${(rc.heldMoved ?? 9).toFixed(3)} m; after GO ${(rc.goMoved ?? 0).toFixed(2)} m`);
  report(rc.myTime > 0, 'race: you finish', `your time ${(rc.myTime ?? -1).toFixed(2)} s`);
  report(rc.done && rc.bots.filter(t => t > 0).length >= 2 && !!rc.results, 'race: bots finish',
    `bots ${JSON.stringify(rc.bots && rc.bots.map(t => +t.toFixed(1)))} s (put back ${JSON.stringify(rc.puts)}), ${((rc.ms || 0) / 1000).toFixed(0)} s to simulate; results:\n${rc.results}`);
  if (shots) await page.screenshot({ path: path.join(shots, 'race_results.png'), timeout: 180000 });

  // Supermarket sweep (sweep.js, as shopping-cart/tests/sweep_test.gd): `sweep 40` goes to the supermarket and lines
  // you and the bots up at the entrance with empty baskets; nobody moves during 3, 2, 1. Parked by the coffee, five
  // cans drop in and no more; rolling over spills some; bumping the giant soup and holding still at the deli counter
  // earn their bonuses; the bots shop; `sweep nobots` restocks.
  const sw = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('sandbox');
    c.runCommand('sweep 40');
    for (let i = 0; i < 300 && !(c.levelKey === 'market' && c.sweep && c.sweep.phase === 2); i++) await new Promise(r => setTimeout(r, 100));
    const sweep = c.sweep, out = { level: c.levelKey, phase: sweep && sweep.phase, shoppers: sweep ? sweep.shoppers.length : 0 };
    if (!sweep) return out;
    out.round = sweep.roundTime; out.products = sweep.products.length; out.displays = sweep.displays.length;
    out.slotOff = Math.max(...sweep.shoppers.map((s, i) => { const p = sweep.cartOf(s).origin(), q = sweep.D.slots[i].pos; return Math.hypot(p.x - q[0], p.z - q[2]); }));
    const p0 = { ...c.cart.origin() };
    c.setInput({ L: 1, R: 1 }); c.simulate(2.9);
    out.groceries = c.cart.groceries.length;
    out.heldMoved = Math.hypot(c.cart.origin().x - p0.x, c.cart.origin().z - p0.z);
    out.countShown = !document.getElementById('sweepCount').hidden;
    c.setInput({}); c.simulate(0.4);
    out.phaseAfter = sweep.phase;
    const me = sweep.shoppers[0];
    const coffee = sweep.displays.find(d => d.name === 'Coffee');
    c.spawn(c.v3(coffee.stop[0] - 0.55, 0, coffee.stop[2]), 0); c.simulate(4);
    out.coffee = sweep.countOf(c.cart, 'Coffee'); out.cents = me.cents; out.left = sweep.left(coffee);
    c.simulate(2); out.leftLater = sweep.left(coffee);
    c.sweep.draw(0); out.toast = document.getElementById('sweepToasts').textContent;
    const before = me.cents, q = c.cart.frame.rotation();
    const nose = { x: 1 - 2 * (q.y * q.y + q.z * q.z), y: 2 * (q.x * q.y + q.w * q.z), z: 2 * (q.x * q.z - q.w * q.y) };
    c.cart.wake(); c.cart.frame.setAngvel({ x: -12 * nose.x, y: -12 * nose.y, z: -12 * nose.z }, true); c.cart.frame.setLinvel({ x: 0, y: 3.5, z: 0 }, true);
    c.simulate(3);
    // Upside down, the groceries lie under the basket; set the cart back on its wheels beside them (as a reset does).
    { const o = c.cart.origin(); c.spawn(c.v3(o.x - 3, 0, o.z), 0); c.simulate(0.5); }
    out.spilled = [before, me.cents];
    const soup = sweep.bonuses.find(b => b.name === 'Giant soup');
    c.spawn(c.v3(soup.rest.p.x - 2.2, 0, soup.rest.p.z), 0); c.simulate(0.2);
    c.setInput({ L: 1, R: 1 }); c.simulate(2.5); c.setInput({});
    out.soup = [soup.claimed, me.bonus];
    const deli = sweep.stations.find(s => s.title === 'DELI COUNTER');
    c.spawn(c.v3(deli.zone.inv.clone().invert().elements[12] - 0.5, 0, deli.zone.inv.clone().invert().elements[14]), 0);
    c.simulate(4); out.deli = me.bonus; c.simulate(3); out.deliAgain = me.bonus;
    const t0 = performance.now();
    for (let s = 0; s < 60 && sweep.phase !== 4; s += 5) c.simulate(5);
    out.ms = performance.now() - t0;
    out.done = sweep.phase === 4;
    out.bots = sweep.shoppers.slice(1).map(s => [s.items, s.cents, JSON.stringify(s.bot.stats)]);
    c.renderOnce();
    out.results = !document.getElementById('sweepResults').hidden && document.getElementById('sweepTable').textContent;
    c.runCommand('sweep nobots');
    for (let i = 0; i < 50 && sweep.phase !== 2; i++) await new Promise(r => setTimeout(r, 100));
    out.again = [sweep.phase, sweep.shoppers.length, sweep.left(coffee), soup.claimed, sweep.roundTime];
    return out;
  });
  report(sw.level === 'market' && sw.phase === 2 && sw.shoppers === 4 && sw.slotOff < 0.15 && sw.round === 40, 'sweep: line-up',
    `sweep took us to ${sw.level}, counting down a ${sw.round} s round, ${sw.shoppers} shoppers within ${(sw.slotOff ?? 9).toFixed(2)} m of their slots, ${sw.displays} displays, ${sw.products} products`);
  report(sw.groceries === 0 && sw.heldMoved < 0.3 && sw.countShown && sw.phaseAfter === 3, 'sweep: 3 2 1 GO',
    `empty basket (${sw.groceries} groceries), moved ${(sw.heldMoved ?? 9).toFixed(3)} m during the count, then sweeping`);
  report(sw.coffee === 5 && sw.cents === 4495 && sw.left === 5 && sw.leftLater === 5 && /Coffee/.test(sw.toast || ''), 'sweep: grab and limit',
    `${sw.coffee} coffee in the basket, ${sw.cents} cents, ${sw.left} then ${sw.leftLater} left on the table, pop-up "${(sw.toast || '').split('\n')[0]}"`);
  report(sw.spilled && sw.spilled[1] < sw.spilled[0], 'sweep: spill', `rolled over: ${JSON.stringify(sw.spilled)} cents`);
  report(sw.soup && sw.soup[0] && sw.soup[1] === 10000 && sw.deli === 15000 && sw.deliAgain === 15000, 'sweep: bonuses',
    `giant soup ${JSON.stringify(sw.soup)}, then the deli counter: bonus ${sw.deli}, ${sw.deliAgain} after waiting more`);
  report(sw.done && sw.bots.reduce((n, b) => n + b[0], 0) >= 3 && !!sw.results, 'sweep: bots and checkout',
    `bots ${JSON.stringify(sw.bots)}, ${((sw.ms || 0) / 1000).toFixed(0)} s to simulate; results:\n${sw.results}`);
  report(sw.again && sw.again[0] === 2 && sw.again[1] === 1 && sw.again[2] === 10 && !sw.again[3] && sw.again[4] === 90, 'sweep: again', `sweep nobots: ${JSON.stringify(sw.again)}`);
  if (shots) await page.screenshot({ path: path.join(shots, 'sweep_results.png'), timeout: 180000 });

  // Cart-to-cart: roll the player's cart into a spare cart in the supermarket; the spare moves.
  const hit = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('market');
    c.setInput({}); c.simulate(1);
    const spare = c.spares[0], sp = spare.origin();
    c.spawn(c.v3(sp.x + 0.5, sp.y, sp.z - 1.4), -Math.PI / 2);   // facing +Z, side-on toward the spare's basket
    c.setInput({}); c.simulate(0.5);
    const s0 = { ...spare.origin() };
    c.setInput({ L: 1, R: 1 }); c.simulate(1.5); c.setInput({}); c.simulate(1);
    const s1 = spare.origin();
    return { moved: Math.hypot(s1.x - s0.x, s1.z - s0.z), wasPinned: true };
  });
  report(hit.moved > 0.05, 'cart hits spare cart', `spare cart moved ${hit.moved.toFixed(2)} m`);

  // Stacks: the parking lot's stack by the spawn holds together, the player's cart nests by pushing in, the herd
  // rolls as one, and a hard yank pulls the cart back off.
  const st = await page.evaluate(async () => {
    const c = window.__cart;
    await c.loadLevel('plot');
    c.setInput({}); c.simulate(2);
    const nested = c.spares.filter(s => s.nestedIn).length;
    const front = c.spares[0], last = c.spares[2], p0 = { ...front.origin() };
    const lp = last.origin(), h = last.heading();
    c.spawn(c.v3(lp.x - 1.5 * Math.cos(h), lp.y, lp.z + 1.5 * Math.sin(h)), h);
    c.setInput({}); c.simulate(0.5);
    c.setInput({ L: 1, R: 1 });
    let t = 0;
    while (!c.cart.nestedIn && t < 6) { c.simulate(0.05); t += 0.05; }
    const caught = c.cart.nestedIn === last;
    c.simulate(4);
    const herd = c.cart.stack().length, p1 = front.origin(), moved = Math.hypot(p1.x - p0.x, p1.z - p0.z);
    let fastest = 0;
    for (const s of c.cart.stack()) for (const b of s.parts) { const v = b.linvel(); fastest = Math.max(fastest, Math.hypot(v.x, v.y, v.z)); }
    c.setInput({}); c.simulate(4);
    c.setInput({ L: -1, R: -1 });
    let u = 0;
    while (c.cart.nestedIn && u < 5) { c.simulate(0.05); u += 0.05; }
    c.setInput({}); c.simulate(2);
    return { nested, caught, t, herd, moved, fastest, off: !c.cart.nestedIn, u, left: front.stack().length, ghosts: c.cart.ghosts.size };
  });
  report(st.nested === 5, 'stacks built', `${st.nested} spare carts nested in another`);
  report(st.caught && st.herd === 4 && st.moved > 1.5 && st.fastest < 6, 'cart nests into stack',
    `caught after ${st.t.toFixed(2)} s, herd of ${st.herd} moved ${st.moved.toFixed(1)} m, fastest body ${st.fastest.toFixed(2)} m/s`);
  report(st.off && st.left === 3 && st.ghosts === 0, 'yank pulls it off', `came off after ${st.u.toFixed(2)} s, stack left with ${st.left}, ghosts ${st.ghosts}`);

  await page.close();   // its draw loop would slow the phone page down

  // ------------------------------------------------------------ phone: touch rockers
  const phone = await open({ ...devices['Pixel 7 landscape'] }, '?level=sandbox');
  await phone.tap('#go');
  const t0 = await phone.evaluate(() => { const c = window.__cart; c.spawn(c.v3(-10, 0, -3), 0); return { mode: c.mode, p: { ...c.cart.origin() } }; });
  const rocker = async side => phone.evaluate(s => { const r = document.getElementById('rock' + s).getBoundingClientRect(); return { x: r.left + r.width / 2, top: r.top, h: r.height }; }, side);
  const L = await rocker('L'), R = await rocker('R');
  const cdp = await phone.context().newCDPSession(phone);
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((p, i) => ({ x: p.x, y: p.y, id: i })) });
  await touch('touchStart', [{ x: L.x, y: L.top + L.h * 0.25 }, { x: R.x, y: R.top + R.h * 0.25 }]);
  await phone.waitForTimeout(1200);
  const mid = await phone.evaluate(() => ({ L: window.__cart.cart.handPower.L, R: window.__cart.cart.handPower.R, rock: document.getElementById('rockL').dataset.dir }));
  // Slide the right thumb below the middle: that hand pulls, and the cart turns.
  await touch('touchMove', [{ x: L.x, y: L.top + L.h * 0.25 }, { x: R.x, y: R.top + R.h * 0.8 }]);
  await phone.waitForTimeout(700);
  const slid = await phone.evaluate(() => ({ R: window.__cart.cart.handPower.R, rock: document.getElementById('rockR').dataset.dir }));
  await touch('touchEnd', []);
  await phone.waitForTimeout(300);
  const t1 = await phone.evaluate(() => ({ p: { ...window.__cart.cart.origin() }, L: window.__cart.cart.handPower.L }));
  const tMoved = Math.hypot(t1.p.x - t0.p.x, t1.p.z - t0.p.z);
  report(t0.mode === 'touch' && mid.L > 25 && mid.R > 25 && mid.rock === 'push' && slid.R < 0 && slid.rock === 'pull' && tMoved > 0.3,
    'touch rockers', `controls ${t0.mode}; both thumbs above the middle: push ${Math.round(mid.L)} / ${Math.round(mid.R)} N; right thumb slid down: ${Math.round(slid.R)} N (${slid.rock}); cart moved ${tMoved.toFixed(2)} m`);
  const lean = await phone.evaluate(async () => {
    const b = document.getElementById('leanFront').getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  });
  await touch('touchStart', [lean]);
  await phone.waitForFunction(() => /front up/.test(window.__cart.cart.handState.L), null, { timeout: 15000 }).catch(() => {});
  const leaning = await phone.evaluate(() => window.__cart.cart.handState.L);
  await touch('touchEnd', []);
  report(/front up/.test(leaning), 'touch lean button', `holding Front up: "${leaning}"`);
  if (shots) await phone.screenshot({ path: path.join(shots, 'phone.png') });

  report(errors.length === 0, 'no page errors', errors.length ? '\n' + errors.join('\n') : '');
  console.log(`RESULT: ${failures ? 'FAILURES (' + failures + ' failing)' : 'ALL PASS'}`);
  await browser.close(); srv.close();
  process.exit(failures ? 1 : 0);
})();
