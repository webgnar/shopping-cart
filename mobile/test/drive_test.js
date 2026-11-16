// Headless drive test for the mobile web game: drives the two thumbs and the tilt through the page's
// test hook and checks the cart does what the design says (same checks as the Godot drive test).
//   node mobile/test/drive_test.js [path-to-index.html] [screenshot.png]
const { chromium, devices } = require('playwright');
const path = require('path');

const page_url = 'file://' + path.resolve(process.argv[2] || path.join(__dirname, '..', 'index.html'));
const SCENARIOS = [
  // name, thumbs {L, R}, tilt {pitch, roll} degrees, seconds, check
  ['idle', {}, null, 4, 'still'],
  ['both thumbs push', { L: 0.5, R: 0.5 }, null, 3, 'forward_straight'],
  ['both thumbs pull', { L: -0.5, R: -0.5 }, null, 3, 'backward'],
  ['right thumb push', { R: 0.5 }, null, 3, 'turns_left'],
  ['left thumb push', { L: 0.5 }, null, 3, 'turns_right'],
  ['push L, pull R (spin)', { L: 0.5, R: -0.5 }, null, 2, 'spins_right'],
  ['light thumbs (stroll)', { L: 0.15, R: 0.15 }, null, 4, 'slow'],
  ['full thumbs (run)', { L: 1, R: 1 }, null, 4, 'fast'],
  ['tilt back (wheelie)', {}, { pitch: 25, roll: 0 }, 1.5, 'wheelie'],
  ['tilt forward (rear up)', {}, { pitch: -25, roll: 0 }, 1.5, 'rear_up'],
  ['tilt sideways', { R: 0.4 }, { pitch: 0, roll: -25 }, 1.5, 'leans'],
  ['coast then rest', { coast: true }, null, 10, 'comes_to_rest'],
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  await page.goto(page_url);
  await page.waitForFunction(() => window.__cart && !document.getElementById('go').disabled, null, { timeout: 120000 });
  await page.click('#go');
  let failures = 0;
  for (const [name, thumbs, tilt, secs, check] of SCENARIOS) {
    const r = await page.evaluate(async ([thumbs, tilt, secs]) => {
      const c = window.__cart;
      const wait = ms => new Promise(res => setTimeout(res, ms));
      c.setThumb('L', 0); c.setThumb('R', 0); c.setTilt(null);
      c.spawn(c.v3(-10, 0, -3), 0);
      c.simulate(1.0);
      const cart = c.cart, f = cart.frame;
      const p0 = { ...f.translation() }, h0 = c.heading();
      if (!thumbs.coast) { c.setThumb('L', thumbs.L || 0); c.setThumb('R', thumbs.R || 0); }
      if (tilt) c.setTilt(tilt);
      let maxFront = 0, maxRear = 0, maxRoll = 0;
      c.simulate(secs, () => {
        const w = cart.wheels;
        maxFront = Math.max(maxFront, Math.min(w.FL.translation().y, w.FR.translation().y));
        maxRear = Math.max(maxRear, Math.min(w.RL.translation().y, w.RR.translation().y));
        const q = f.rotation(), sy = 2 * (q.y * q.z + q.w * q.x);   // world-up component of the cart's side axis
        maxRoll = Math.max(maxRoll, Math.abs(Math.asin(Math.max(-1, Math.min(1, sy)))) * 57.3);
      }, t => { if (thumbs.coast) c.setThumb('R', t < 1 ? 0.5 : 0); });
      c.setThumb('L', 0); c.setThumb('R', 0); c.setTilt(null);
      const p1 = f.translation(), lv = f.linvel();
      const q = f.rotation(), nx = 1 - 2 * (q.y * q.y + q.z * q.z), nz = 2 * (q.x * q.z - q.w * q.y);
      const along = (lv.x * nx + lv.z * nz) / (Math.hypot(nx, nz) || 1);
      let turn = (c.heading() - h0) * 57.3; turn = ((turn + 540) % 360) - 180;
      return { moved: Math.hypot(p1.x - p0.x, p1.z - p0.z), along, turn, maxFront, maxRear, maxRoll, pinned: cart.pinned,
        groceries: c.groceriesIn(), nan: !Number.isFinite(p1.x) };
    }, [thumbs, tilt, secs]);
    const ok = !r.nan && {
      still: r.moved < 0.005 && Math.abs(r.turn) < 0.1 && r.pinned,
      forward_straight: r.along > 1.0 && Math.abs(r.turn) < 12,
      backward: r.along < -0.7 && Math.abs(r.turn) < 25,
      turns_left: r.turn > 30,
      turns_right: r.turn < -30,
      spins_right: r.turn < -60 && r.moved < 1.0,
      slow: r.along > 0.3 && r.along < 1.7,
      fast: r.along > 2.8,
      wheelie: r.maxFront > 0.12 && r.maxRear < 0.09,
      rear_up: r.maxRear > 0.10 && r.maxFront < 0.09,
      leans: r.maxRoll > 5,
      comes_to_rest: r.pinned,
    }[check];
    if (!ok) failures++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(24)} moved ${r.moved.toFixed(2)} m  speed along nose ${r.along >= 0 ? '+' : ''}${r.along.toFixed(2)} m/s  turned ${Math.round(r.turn)} deg  front up ${r.maxFront.toFixed(2)} m  rear up ${r.maxRear.toFixed(2)} m  roll ${r.maxRoll.toFixed(1)}  groceries ${r.groceries}/5${r.pinned ? '  (pinned)' : ''}`);
  }
  // Braking: run the cart up to speed with both thumbs, then pull both back fully (body plants, arms extend).
  for (const [label, push] of [['walk', 0.45], ['run', 1.0]]) {
    for (const mode of ['let go', 'pull back']) {
      const r = await page.evaluate(([push, mode]) => {
        const c = window.__cart;
        c.spawn(c.v3(-14, 0, -3), 0); c.simulate(0.5);
        const f = c.cart.frame;
        c.setThumb('L', push); c.setThumb('R', push); c.simulate(3);
        const nose = () => { const q = f.rotation(); return { x: 1 - 2 * (q.y * q.y + q.z * q.z), z: 2 * (q.x * q.z - q.w * q.y) }; };
        const along = () => { const n = nose(), lv = f.linvel(), h = Math.hypot(n.x, n.z); return (lv.x * n.x + lv.z * n.z) / h; };
        const v0 = along(), p0 = { ...f.translation() };
        c.setThumb('L', mode === 'let go' ? 0 : -1); c.setThumb('R', mode === 'let go' ? 0 : -1);
        let t = 0, maxPitch = 0, stopped = false;
        c.simulate(8, () => {
          if (stopped) return;
          t += 1 / 120;
          const q = f.rotation(), ny = 2 * (q.x * q.y + q.w * q.z);
          maxPitch = Math.max(maxPitch, Math.asin(Math.max(-1, Math.min(1, ny))) * 57.3);
          if (along() < 0.05) { stopped = true; c.setThumb('L', 0); c.setThumb('R', 0); }
        });
        const p1 = f.translation();
        return { v0, dist: Math.hypot(p1.x - p0.x, p1.z - p0.z), t, maxPitch, groceries: c.groceriesIn() };
      }, [push, mode]);
      const ok = mode === 'let go' || (r.dist < 1.0 && r.t < 1.5 && r.maxPitch < 25 && r.groceries >= 4);
      if (!ok) failures++;
      console.log(`${mode === 'let go' ? 'info' : ok ? 'PASS' : 'FAIL'}  ${(label + ' ' + mode).padEnd(24)} from ${(r.v0 * 3.6).toFixed(1)} km/h: stopped in ${r.dist.toFixed(2)} m and ${r.t.toFixed(2)} s  max nose-up ${r.maxPitch.toFixed(1)} deg  groceries ${r.groceries}/5`);
    }
  }
  const acc = await page.evaluate(() => {
    const c = window.__cart, out = {};
    for (const [k, v] of [['push', 0.5], ['pull', -0.5]]) {
      c.spawn(c.v3(-10, 0, -3), 0); c.simulate(0.5);
      c.setThumb('L', v); c.setThumb('R', v); c.simulate(0.5); c.setThumb('L', 0); c.setThumb('R', 0);
      const lv = c.cart.frame.linvel(); out[k] = Math.hypot(lv.x, lv.z);
    }
    return out;
  });
  const pullOk = acc.pull > acc.push * 1.2;
  if (!pullOk) failures++;
  console.log(`${pullOk ? 'PASS' : 'FAIL'}  ${'pull > push'.padEnd(24)} after 0.5 s from rest: pushing ${acc.push.toFixed(2)} m/s, pulling ${acc.pull.toFixed(2)} m/s`);

  // Gate: swings into the basket when shoved, stops at its limit, falls back to rest (empty basket).
  const g = await page.evaluate(() => {
    const c = window.__cart;
    c.spawn(c.v3(-10, 0, -3), 0);
    for (const b of c.cart.groceries) b.setTranslation(c.v3(-20, 5, 10), true);   // move groceries out of the way
    c.simulate(0.5);
    const rel = () => { const g = c.cart.gate.rotation(), f = c.cart.frame.rotation(); return (2 * Math.atan2(g.z, g.w) - 2 * Math.atan2(f.z, f.w)) * 57.3; };
    const before = rel();
    let maxSwing = 0;
    c.simulate(0.4, () => { maxSwing = Math.max(maxSwing, Math.abs(rel() - before)); },
      t => { if (t < 0.15) { const q = c.cart.frame.rotation(), nx = 1 - 2 * (q.y * q.y + q.z * q.z), nz = 2 * (q.x * q.z - q.w * q.y); c.cart.gate.applyImpulse(c.v3(nx * 0.25, 0, nz * 0.25), true); } });
    c.simulate(2.0);
    return { maxSwing, after: Math.abs(rel() - before), pinned: c.cart.pinned };
  });
  const gateOk = g.maxSwing > 10 && g.maxSwing < 75 && g.after < 5;
  if (!gateOk) failures++;
  console.log(`${gateOk ? 'PASS' : 'FAIL'}  ${'gate'.padEnd(24)} swung ${g.maxSwing.toFixed(0)} deg when shoved, back to ${g.after.toFixed(0)} deg after${g.pinned ? '  (pinned)' : ''}`);
  if (process.argv[3]) {
    await page.evaluate(async () => { const c = window.__cart; c.spawn(c.v3(2, 0, -1), 0.4); await new Promise(r => setTimeout(r, 800)); c.setThumb('L', 0.6); c.setThumb('R', 0.6); c.setTilt({ pitch: 25, roll: 0 }); await new Promise(r => setTimeout(r, 1500)); });
    await page.screenshot({ path: process.argv[3] });
  }
  console.log(errors.length ? 'PAGE ERRORS:\n' + errors.join('\n') : 'No page errors');
  console.log(`RESULT: ${failures ? 'FAILURES (' + failures + ' failing)' : 'ALL PASS'}`);
  await browser.close();
  process.exit(failures ? 1 : 0);
})();
