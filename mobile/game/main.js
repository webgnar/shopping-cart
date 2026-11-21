// Shopping Cart in the browser: the Godot levels and cart (exported by the Godot tools), three.js + Rapier.
// Phones: two thumb rockers (push / pull per hand), tilt or buttons to lean. Computers: the Godot keys and mouse.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import RAPIER from 'rapier';
import { v3, add, sub, clamp, rot, color, widenMask } from './util.js';
import { catchNoses, regroup, buildStacks } from './nest.js';
import { Cart, SIDES } from './cart.js';
import { Bot } from './bot.js';
import { NavMesh } from './nav.js';
import { fetchLevel, buildLevel, layerPairs, applyEnvironment, ambientFor, makeSkyDome, disposeTree, stepTraffic, syncTraffic } from './level.js';
import { WheelSounds, unlockAudio, updateListener, loadedLoops } from './sound.js';
import { ChunkStreamer } from './stream.js';
import { setMusic, startMusic, musicState } from './music.js';

await RAPIER.init();
const STEP = 1 / 120;                // Godot physics ticks at 120 Hz
const LEVELS = 'levels', MODELS = 'models';
const TUNE = window.CART_TUNING || {};
const $ = id => document.getElementById(id);
const params = new URLSearchParams(location.search);

// ---------------------------------------------------------------- renderer
const touchFirst = matchMedia('(pointer: coarse)').matches;
const renderer = new THREE.WebGLRenderer({ antialias: !touchFirst || devicePixelRatio < 2, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, touchFirst ? 1.5 : 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.prepend(renderer.domElement);
const canvas = renderer.domElement;
const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;   // reflections for the chrome
scene.environmentIntensity = 0.35;
const camera = new THREE.PerspectiveCamera(55, innerWidth / innerHeight, 0.05, 600);
const skyDome = makeSkyDome(); scene.add(skyDome);
const sun = new THREE.DirectionalLight(0xffffff, 1);
sun.shadow.mapSize.set(touchFirst ? 1024 : 2048, touchFirst ? 1024 : 2048);
Object.assign(sun.shadow.camera, { left: -8, right: 8, top: 8, bottom: -8, near: 0.5, far: 60 });
sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.02;
scene.add(sun, sun.target);
addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });

// ---------------------------------------------------------------- shared assets
const [levelList, rig, cartGltf] = await Promise.all([
  fetch(`${LEVELS}/levels.json`).then(r => r.json()),
  fetch(`${LEVELS}/cart.json`).then(r => r.json()),
  new GLTFLoader().loadAsync(`${MODELS}/cart.glb`).catch(e => { console.warn('Cart model did not load', e); return null; }),
]);
// The cart's materials are the shared Godot ones (assets/materials/cart/*.tres), matched by name as Godot's import does.
const cartMats = {};
for (const [name, m] of Object.entries(rig.materials)) cartMats[name] = new THREE.MeshStandardMaterial({ color: color(m.color), metalness: m.metallic, roughness: m.roughness, name });
const cartModel = cartGltf && cartGltf.scene;
if (cartModel) cartModel.traverse(o => { if (o.isMesh) { o.castShadow = o.receiveShadow = true; o.material = cartMats[o.material.name] || o.material; } });

// ---------------------------------------------------------------- the world (rebuilt for each level)
let world = null, eventQueue = null, level = null, levelRoot = null, ambient = null, cart = null, spares = [], bots = [], ctx = null;
// Every cart but the player's: spare carts, then bot carts.
const others = () => spares.concat(bots.map(b => b.cart));
let levelKey = null, loading = false;
let streamer = null;   // the endless sandbox's chunks (stream.js), else null

async function loadLevel(key) {
  const entry = levelList.find(l => l.key === key) || levelList[0];
  loading = true;
  $('loading').textContent = `Loading ${entry.name}…`; $('loading').hidden = false;
  try {
    const data = await fetchLevel(LEVELS, entry.key);
    // Tear down the old level.
    if (levelRoot) { scene.remove(levelRoot); disposeTree(levelRoot); }
    if (ambient) scene.remove(ambient);
    for (const c of [cart, ...others()]) if (c && c.sound) c.sound.remove();
    setMusic(null);
    for (const c of [cart, ...others()]) if (c && c.root) scene.remove(c.root);
    for (const c of [cart, ...others()]) if (c) for (const [, g] of c.meshes) scene.remove(g);
    if (streamer) { streamer.dispose(); streamer = null; }
    if (world) world.free();
    cart = null; spares = []; bots = [];
    world = new RAPIER.World(v3(0, -9.81, 0));
    world.timestep = STEP;
    world.integrationParameters.numSolverIterations = 8;
    eventQueue = new RAPIER.EventQueue(true);
    const pairs = layerPairs(data.json, rig);
    ctx = { RAPIER, world, scene, rig, tune: TUNE, model: null, widen: (l, m) => widenMask(l, m, pairs) };
    levelRoot = new THREE.Group(); scene.add(levelRoot);
    level = buildLevel(ctx, data, levelRoot, { noShadows: touchFirst, lightCount: touchFirst ? { omni: 4, spot: 3 } : { omni: 6, spot: 5 } });
    applyEnvironment(renderer, scene, level.env, skyDome);
    ambient = ambientFor(level.env); scene.add(ambient);
    const s = level.sun;
    sun.visible = !!s;
    if (s) { sun.color.copy(color(s.color)); sun.intensity = s.energy * Math.PI; sun.castShadow = s.shadows; sun.userData.dir = new THREE.Vector3(...s.dir).normalize(); }
    // Spare carts (empty, nobody holding them), then the player's at CartSpawn.
    let bit = 1 << 5;
    for (const sc of level.spareCarts) {
      if (bit > 0x8000) break;
      const spare = new Cart({ ...ctx, model: cartModel ? cartModel.clone() : null }, { pos: v3(...sc.pos), yaw: sc.yaw, player: false, empty: true, bit });
      if (rig.wheel_sound) spare.sound = new WheelSounds(spare, rig.wheel_sound, level.surfaces);
      spares.push(spare);
      bit <<= 1;
    }
    // Stacks: spare carts nested into each other (scenes/cart/cart_stack_*.tscn in Godot).
    if (rig.nest) buildStacks(ctx, spares, level.spareCarts, rig.nest);
    // Bot carts: the same cart, driven by a bot pressing the player's keys over the level's navigation mesh.
    const nav = level.navmesh ? new NavMesh(level.navmesh) : null;
    for (const bc of nav ? level.botCarts : []) {
      if (bit > 0x8000) break;
      const c = new Cart({ ...ctx, model: cartModel ? cartModel.clone() : null }, { pos: v3(...bc.pos), yaw: bc.yaw, player: false, empty: true, bit });
      if (rig.wheel_sound) c.sound = new WheelSounds(c, rig.wheel_sound, level.surfaces);
      bots.push(new Bot(c, nav, rig.bot));
      bit <<= 1;
    }
    // The endless sandbox: terrain chunks around the cart, all of the near ones in before the cart is placed.
    if (level.stream) {
      streamer = new ChunkStreamer(ctx, level, level.stream, LEVELS, levelRoot, { noShadows: touchFirst, reach: touchFirst ? 0.8 : 1 });
      await streamer.prime(new THREE.Vector3(...level.spawn.pos));
    }
    levelKey = entry.key;
    setMusic(data.json.music);   // the level's background loop (parking lot), if it has one
    spawn(v3(...level.spawn.pos), level.spawn.yaw);
    world.step(eventQueue);   // settle the query structures before the first raycast
    localStorage.setItem('cart-level', levelKey);
    $('levelName').textContent = entry.name;
  } finally {
    loading = false; $('loading').hidden = true;
  }
}

const PLAYER_BIT = 1 << 4;
function spawn(pos, yaw) {
  if (cart) {
    // Out of any stack first: the carts on either side let go.
    if (cart.nest) cart.nest.comeApart();
    if (cart.nestedBehind && cart.nestedBehind.nest) cart.nestedBehind.nest.comeApart();
    for (const o of cart.ghosts) o.ghosts.delete(cart);
    cart.remove(); if (cart.sound) cart.sound.remove();
  }
  cart = new Cart({ ...ctx, model: cartModel ? cartModel.clone() : null }, { pos, yaw, player: true, bit: PLAYER_BIT });
  if (rig.wheel_sound) cart.sound = new WheelSounds(cart, rig.wheel_sound, level.surfaces);
  cam.heading = yaw; cam.target.set(pos.x, pos.y + 0.67, pos.z); cam.lift = 0; cam.reach = 1;
}

/** R: a fresh cart where this one is, on whatever floor is under it. */
function respawn() {
  const p = cart.origin(), h = cart.heading();
  const hit = world.castRayAndGetNormal(new RAPIER.Ray(v3(p.x, p.y + 1.2, p.z), v3(0, -1, 0)), 50, true, undefined, (1 << 16) | 1);
  // On a slope, high enough that the wheels (the front ones a metre from the handle) clear the uphill side.
  const lift = hit ? 0.05 + Math.sqrt(Math.max(0, 1 - hit.normal.y ** 2)) / Math.max(hit.normal.y, 0.2) : 0.05;
  spawn(v3(p.x, hit ? p.y + 1.2 - hit.timeOfImpact + lift : p.y + 0.05, p.z), h);
}

// ---------------------------------------------------------------- input
// Keys: the Godot game's (main.gd). E/A left push/pull, Q/D right push/pull, W/S lean back/front up, P reset.
const keys = new Set();
const KEYS = { push_left: 'KeyE', pull_left: 'KeyA', push_right: 'KeyQ', pull_right: 'KeyD', lift: 'KeyW', press: 'KeyS' };
const touchHand = { L: 0, R: 0 }, touchLean = { lift: false, press: false };
let tiltLean = { lift: false, press: false };
let testInput = null;   // set by the test hook
let paused = false;

function readInput() {
  if (testInput) return { ...testInput };
  const k = c => keys.has(c);
  const hand = (push, pull, t) => (k(push) || t > 0 ? 1 : 0) - (k(pull) || t < 0 ? 1 : 0);
  return {
    L: hand(KEYS.push_left, KEYS.pull_left, touchHand.L), R: hand(KEYS.push_right, KEYS.pull_right, touchHand.R),
    lift: k(KEYS.lift) || touchLean.lift || tiltLean.lift, press: k(KEYS.press) || touchLean.press || tiltLean.press,
  };
}

const GAME_KEYS = new Set([...Object.values(KEYS), 'KeyP']);
addEventListener('keydown', e => {
  if (consoleOpen()) return;
  if (e.code === 'Backquote') { e.preventDefault(); openConsole(); return; }
  if (!started) return;
  if (GAME_KEYS.has(e.code)) { e.preventDefault(); setMode('desk'); }
  keys.add(e.code);
  if (e.code === 'KeyP' && !e.repeat) respawn();
  if (e.code === 'F11' || (e.code === 'KeyF' && !e.repeat)) { if (e.code === 'F11') e.preventDefault(); toggleFullscreen(); }
});
addEventListener('keyup', e => keys.delete(e.code));
addEventListener('blur', () => { keys.clear(); releaseTouches(); });

// Mouse (computers): click to look around (pointer lock), Esc to let go, wheel to zoom. Same as main.gd.
canvas.addEventListener('mousedown', e => { if (started && mode === 'desk' && e.button === 0 && !document.pointerLockElement) canvas.requestPointerLock?.(); });
addEventListener('mousemove', e => {
  if (document.pointerLockElement !== canvas) return;
  cam.yaw -= e.movementX * 0.004;
  cam.pitch = clamp(cam.pitch + e.movementY * 0.003, 0.05, 1.3);
});
canvas.addEventListener('wheel', e => { cam.dist = e.deltaY < 0 ? Math.max(1.4, cam.dist * 0.9) : Math.min(9, cam.dist * 1.1); e.preventDefault(); }, { passive: false });

// Touch: each half of the screen is one hand. The rocker in that corner is the hand: thumb above its middle
// pushes, below pulls; slide across to switch. Touches near the top of the screen look around instead.
const touches = new Map();   // pointerId -> {kind: 'L'|'R'|'look', x, y}
const rockerMid = side => { const r = $('rock' + side).getBoundingClientRect(); return r.top + r.height / 2; };
function touchDir(side, y) { return y < rockerMid(side) ? 1 : -1; }
canvas.addEventListener('pointerdown', e => {
  if (e.pointerType === 'mouse') return;
  setMode('touch');
  if (!started) return;
  const kind = e.clientY < innerHeight * 0.28 ? 'look' : (e.clientX < innerWidth / 2 ? 'L' : 'R');
  if (kind !== 'look' && [...touches.values()].some(t => t.kind === kind)) return;
  touches.set(e.pointerId, { kind, x: e.clientX, y: e.clientY });
  canvas.setPointerCapture(e.pointerId);
  if (kind !== 'look') touchHand[kind] = touchDir(kind, e.clientY);
  e.preventDefault();
});
canvas.addEventListener('pointermove', e => {
  const t = touches.get(e.pointerId);
  if (!t) return;
  if (t.kind === 'look') {
    cam.yaw -= (e.clientX - t.x) * 0.008;
    cam.pitch = clamp(cam.pitch + (e.clientY - t.y) * 0.006, 0.05, 1.3);
  } else touchHand[t.kind] = touchDir(t.kind, e.clientY);
  t.x = e.clientX; t.y = e.clientY;
});
const endTouch = e => { const t = touches.get(e.pointerId); if (!t) return; if (t.kind !== 'look') touchHand[t.kind] = 0; touches.delete(e.pointerId); };
canvas.addEventListener('pointerup', endTouch);
canvas.addEventListener('pointercancel', endTouch);
function releaseTouches() { touches.clear(); touchHand.L = touchHand.R = 0; touchLean.lift = touchLean.press = false; }
// The two lean buttons hold W / S.
for (const [id, k] of [['leanBack', 'lift'], ['leanFront', 'press']]) {
  const b = $(id);
  b.addEventListener('pointerdown', e => { touchLean[k] = true; b.setPointerCapture(e.pointerId); e.preventDefault(); });
  for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture']) b.addEventListener(ev, () => { touchLean[k] = false; });
}

// Phone tilt as the lean keys: tip the top of the phone back for the front up (S), forward for the back up (W).
let tiltMode = localStorage.getItem('cart-tilt') || 'on', tiltRaw = null, tiltZero = null;
addEventListener('deviceorientation', e => {
  if (e.beta == null) return;
  const a = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
  tiltRaw = a === 90 ? e.gamma : (a === -90 || a === 270) ? -e.gamma : -e.beta;
  if (tiltZero == null) tiltZero = tiltRaw;
  if (tiltMode === 'off') { tiltLean = { lift: false, press: false }; return; }
  const d = (tiltRaw - tiltZero) * (tiltMode === 'flipped' ? -1 : 1);
  // 12 degrees to lean, back under 8 to let go, so it doesn't flicker on the edge.
  tiltLean = { press: tiltLean.press ? d > 8 : d > 12, lift: tiltLean.lift ? d < -8 : d < -12 };
});
const setLevelZero = () => { tiltZero = tiltRaw; };

// ---------------------------------------------------------------- mode: touch controls or keyboard + mouse
let mode = null;
function setMode(m) {
  if (m === mode) return;
  mode = m;
  document.body.classList.toggle('touch', m === 'touch');
  document.body.classList.toggle('desk', m === 'desk');
}
setMode(params.get('controls') || (touchFirst ? 'touch' : 'desk'));
addEventListener('pointerdown', e => { if (e.pointerType === 'touch') setMode('touch'); }, true);

// ---------------------------------------------------------------- follow camera (main.gd + cart_camera.gd)
// The camera trails behind the handle; the mouse or a look-drag orbits on top. A sphere is swept from the cart
// to where the camera wants to be: if something is in the way it rises over it (lift_step apart, up to
// max_lift), and under a low ceiling it pulls in until the sphere fits. In is instant, back out is eased.
const CAM = { probe: 0.25, max_lift: 2.0, lift_step: 0.5, rise_speed: 8.0, settle_speed: 2.5, out_speed: 3.0 };
const cam = { yaw: 0, pitch: 0.38, dist: 3.2, heading: 0, target: new THREE.Vector3(), lift: 0, reach: 1, avoid: true };
const probeShape = new RAPIER.Ball(CAM.probe);
const CAM_GROUPS = (1 << 16) | 1;   // like the Godot probe: collision mask 1 (the level)
function castFraction(from, offset) {
  const hit = world.castShape(from, { x: 0, y: 0, z: 0, w: 1 }, offset, probeShape, 0, 1, true, undefined, CAM_GROUPS);
  return hit ? hit.time_of_impact : 1;
}
function updateCamera(dt) {
  let dh = cart.heading() - cam.heading; dh = Math.atan2(Math.sin(dh), Math.cos(dh));
  cam.heading += dh * Math.min(1, 3 * dt);
  const com = cart.comWorld();
  cam.target.lerp(new THREE.Vector3(com.x, com.y + 0.25, com.z), Math.min(1, 9 * dt));
  const yaw = cam.heading + Math.PI + cam.yaw;
  const t = cam.target;
  const wanted = v3(t.x + Math.cos(yaw) * Math.cos(cam.pitch) * cam.dist, t.y + Math.sin(cam.pitch) * cam.dist, t.z - Math.sin(yaw) * Math.cos(cam.pitch) * cam.dist);
  const from = v3(t.x, t.y, t.z);
  let pos = wanted;
  if (cam.avoid) {
    let goal = 0, best = -1, first = 1;
    const steps = CAM.max_lift > 0 ? Math.ceil(CAM.max_lift / CAM.lift_step - 0.001) : 0;
    for (let i = 0; i <= steps; i++) {
      const lift = Math.min(i * CAM.lift_step, CAM.max_lift);
      const line = sub(add(wanted, v3(0, lift, 0)), from);
      const f = castFraction(from, line);
      if (i === 0) first = f;
      if (f >= 1) { goal = lift; break; }
      const L = Math.hypot(line.x, line.y, line.z);
      if (f * L > best + 0.05) { best = f * L; goal = lift; }
    }
    cam.lift += (goal - cam.lift) * Math.min(1, (goal > cam.lift ? CAM.rise_speed : CAM.settle_speed) * dt);
    if (cam.lift < 0.005) cam.lift = 0;
    const off = sub(add(wanted, v3(0, cam.lift, 0)), from);
    const fit = cam.lift === 0 ? first : castFraction(from, off);
    const L = Math.max(Math.hypot(off.x, off.y, off.z), 0.1);
    cam.reach = Math.min(fit, Math.min(1, cam.reach + CAM.out_speed * dt / L));
    pos = add(from, v3(off.x * cam.reach, off.y * cam.reach, off.z * cam.reach));
  }
  camera.position.set(pos.x, pos.y, pos.z);
  camera.lookAt(t);
}

// ---------------------------------------------------------------- HUD
const BAR_MAX = 400;   // N: the HUD bars' range (Godot hud.tscn max_value)
function hud() {
  const lv = cart.frame.linvel();
  $('sSpeed').textContent = (Math.hypot(lv.x, lv.z) * 3.6).toFixed(1);
  $('sTurn').textContent = Math.round(cart.frame.angvel().y * 57.2958);
  $('sWheels').textContent = cart.wheelsDown() + '/4';
  $('sCargo').textContent = cart.groceriesIn() + '/' + cart.groceries.length;
  for (const [s] of SIDES) {
    const p = cart.handPower[s];
    $('push' + s).style.height = (Math.min(1, Math.max(p, 0) / BAR_MAX) * 50) + '%';
    $('pull' + s).style.height = (Math.min(1, Math.max(-p, 0) / BAR_MAX) * 50) + '%';
    $('newtons' + s).textContent = Math.round(Math.abs(p)) + ' N';
    const inp = lastInput[s];
    $('rock' + s).dataset.dir = inp > 0 ? 'push' : inp < 0 ? 'pull' : '';
  }
  $('hands').textContent = `Left hand: ${cart.handState.L || '—'}\nRight hand: ${cart.handState.R || '—'}`;
  $('leanBack').classList.toggle('on', !!lastInput.lift); $('leanFront').classList.toggle('on', !!lastInput.press);
  for (const [a, code] of Object.entries(KEYS)) { const el = document.querySelector(`[data-key="${a}"]`); if (el) el.classList.toggle('on', keys.has(code)); }
  $('tiltRead').textContent = tiltMode === 'off' ? 'tilt off' : tiltRaw == null ? 'no tilt sensor' : lastInput.press ? 'front up' : lastInput.lift ? 'back up' : 'level';
}
let lastInput = { L: 0, R: 0, lift: false, press: false };

// ---------------------------------------------------------------- loop
function physicsStep(inp) {
  const all = [cart, ...others()];
  if (rig.nest) {
    regroup(all, rig.nest);
    const botCarts = new Set(bots.map(b => b.cart));
    catchNoses(ctx, all, rig.nest, c => botCarts.has(c));
  }
  // Every cart's keys first, so a stack wakes as one whichever of its carts is held.
  const botInputs = bots.map(b => b.update(STEP));
  cart.setKeys(inp);
  for (const s of spares) s.setKeys(null);
  bots.forEach((b, i) => b.cart.setKeys(botInputs[i]));
  cart.step(inp, STEP);
  for (const s of spares) s.step(null, STEP);
  bots.forEach((b, i) => b.cart.step(botInputs[i], STEP));
  stepTraffic(level, STEP);
  world.step(eventQueue);
  for (const c of all) if (c.nest) c.nest.update(world, STEP);
  cart.capWheelSpin(); for (const s of others()) if (!s.pinned) s.capWheelSpin();
  for (const c of [cart, ...others()]) if (c.sound) c.sound.tick(STEP);   // each wheel's sound from its physics
  eventQueue.drainCollisionEvents((h1, h2, began) => {
    if (!began) return;
    for (const c of [cart, ...others()]) {
      if (!c.guard) continue;
      const other = h1 === c.guard.handle ? h2 : h2 === c.guard.handle ? h1 : null;
      if (other !== null) c.guardHit(world.getCollider(other)?.parent());
    }
  });
}

let last = performance.now(), acc = 0, fpsT = 0, fpsN = 0, fps = 60;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.1, (now - last) / 1000); last = now;
  fpsT += dt; fpsN++; if (fpsT > 1) { fps = fpsN / fpsT; fpsT = fpsN = 0; $('fps').textContent = Math.round(fps) + ' fps'; }
  if (!world || !cart || loading) return;
  lastInput = readInput();
  if (!paused && started) {
    acc += Math.min(0.05, dt);
    let steps = 0;
    while (acc >= STEP && steps < 6) { physicsStep(lastInput); acc -= STEP; steps++; }
    if (steps === 6) acc = 0;   // running slow: drop time rather than spiral
  }
  if (streamer) streamer.update(cart.origin(), 1);
  for (const pr of level.props) if (pr.node && !pr.body.isSleeping()) { const t = pr.body.translation(), r = pr.body.rotation(); pr.node.position.set(t.x, t.y, t.z); pr.node.quaternion.set(r.x, r.y, r.z, r.w); }
  syncTraffic(level);
  // Off the edge of the world: a fresh cart back at the start (the Godot levels are walled in, the sandbox isn't).
  if (cart.origin().y < level.spawn.pos[1] - 30) spawn(v3(...level.spawn.pos), level.spawn.yaw);
  cart.sync(); for (const s of others()) s.sync();
  updateCamera(dt);
  // Wheel sounds: silent while paused (menu, console) or before Start.
  for (const k of [cart, ...others()]) if (k.sound) k.sound.update(dt, paused || !started);
  updateListener(camera);
  const c = cart.comWorld();
  if (sun.visible) { const d = sun.userData.dir; sun.position.set(c.x - d.x * 30, c.y - d.y * 30, c.z - d.z * 30); sun.target.position.set(c.x, c.y, c.z); }
  skyDome.position.copy(camera.position);
  level.lights.update(new THREE.Vector3(c.x, c.y, c.z), dt);
  hud();
  renderer.render(scene, camera);
}

// ---------------------------------------------------------------- start screen, chips, travel menu, console
let started = false;
const go = $('go');
function buildLevelButtons(container, onPick) {
  container.innerHTML = '';
  for (const l of levelList) {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'lvl'; b.textContent = l.name; b.dataset.key = l.key;
    b.addEventListener('click', () => onPick(l.key));
    container.append(b);
  }
}
const markLevel = el => el.querySelectorAll('.lvl').forEach(b => b.classList.toggle('on', b.dataset.key === levelKey));
buildLevelButtons($('startLevels'), async key => { if (key !== levelKey) await loadLevel(key); markLevel($('startLevels')); });
buildLevelButtons($('menuLevels'), key => { closeMenu(); travel(key); });

go.addEventListener('click', async () => {
  // iOS asks permission for motion sensors; it has to come from this tap.
  try { if (typeof DeviceOrientationEvent !== 'undefined' && DeviceOrientationEvent.requestPermission) await DeviceOrientationEvent.requestPermission(); } catch (e) { /* tilt stays off; the lean buttons still work */ }
  $('start').hidden = true;
  started = true;
  unlockAudio(rig.wheel_sound); startMusic();
  if (mode === 'touch' && document.documentElement.requestFullscreen) {
    document.documentElement.requestFullscreen({ navigationUI: 'hide' }).then(() => screen.orientation?.lock?.('landscape')).catch(() => {});
  }
  setTimeout(setLevelZero, 300);   // let a reading arrive, then call this "level"
});
function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen?.(); else document.documentElement.requestFullscreen?.().catch(() => {});
}
async function travel(key) { releaseTouches(); keys.clear(); await loadLevel(key); }

// Browsers only allow sound after a tap, click or key; Safari sometimes wants another after the Start tap.
for (const ev of ['pointerdown', 'keydown']) addEventListener(ev, () => { if (started) { unlockAudio(rig.wheel_sound); startMusic(); } }, { passive: true });

$('resetBtn').addEventListener('click', () => respawn());
$('levelBtn').addEventListener('click', () => { markLevel($('menuLevels')); $('menu').hidden = false; paused = true; });
const closeMenu = () => { $('menu').hidden = true; paused = false; };
$('menuClose').addEventListener('click', closeMenu);
const tiltBtn = $('tiltBtn');
const showTilt = () => { tiltBtn.innerHTML = 'Tilt: <b>' + tiltMode + '</b>'; };
tiltBtn.addEventListener('click', () => { tiltMode = { on: 'flipped', flipped: 'off', off: 'on' }[tiltMode]; localStorage.setItem('cart-tilt', tiltMode); showTilt(); setLevelZero(); });
showTilt();
$('zeroBtn').addEventListener('click', setLevelZero);
$('fullBtn').addEventListener('click', toggleFullscreen);

// The debug console (` / ~), as in Godot: help, clear, where, and one fast-travel command per level.
const conEl = $('console'), conOut = $('conOut'), conIn = $('conIn');
const history = []; let histPos = 0;
const consoleOpen = () => !conEl.hidden;
function logLine(html) { const d = document.createElement('div'); d.innerHTML = html; conOut.append(d); conOut.scrollTop = conOut.scrollHeight; }
function openConsole() { conEl.hidden = false; paused = true; keys.clear(); document.exitPointerLock?.(); conIn.value = ''; setTimeout(() => conIn.focus(), 0); }
function closeConsole() { conEl.hidden = true; paused = false; conIn.blur(); }
const COMMANDS = {
  help: ['list the commands', () => { logLine('Commands:'); for (const [n, [h]] of Object.entries(COMMANDS)) logLine(`&nbsp;&nbsp;<b>${n}</b>&nbsp;&nbsp;${h}`); }],
  clear: ['clear this window', () => { conOut.innerHTML = ''; }],
  where: ['show which level is loaded', () => logLine('Loaded: ' + (levelList.find(l => l.key === levelKey)?.scene || 'nothing'))],
};
for (const l of levelList) COMMANDS[l.key] = [`fast travel to ${l.scene.split('/').pop()}`, async () => { logLine(`Travelling to ${l.key}...`); closeConsole(); await travel(l.key); }];
function runCommand(line) {
  const words = line.trim().split(/\s+/).filter(Boolean);
  if (!words.length) return false;
  if (history.at(-1) !== line.trim()) history.push(line.trim());
  histPos = history.length;
  logLine(`<span class="ok">&gt;</span> ${line.trim().replace(/</g, '&lt;')}`);
  const c = COMMANDS[words[0].toLowerCase()];
  if (!c) { logLine(`<span class="bad">Unknown command '${words[0].replace(/</g, '&lt;')}'. Type help for the list.</span>`); return false; }
  c[1](words.slice(1));
  return true;
}
conIn.addEventListener('keydown', e => {
  if (e.code === 'Backquote' || e.key === 'Escape') { e.preventDefault(); closeConsole(); }
  else if (e.key === 'Enter') { const v = conIn.value; conIn.value = ''; runCommand(v); }
  else if ((e.key === 'ArrowUp' || e.key === 'ArrowDown') && history.length) {
    histPos = clamp(histPos + (e.key === 'ArrowUp' ? -1 : 1), 0, history.length);
    conIn.value = history[histPos] ?? ''; e.preventDefault();
  }
  e.stopPropagation();
});
logLine('<span class="dim">Console ready. Type <b>help</b> for commands.</span>');

// ---------------------------------------------------------------- go
const startKey = params.get('level') || localStorage.getItem('cart-level') || levelList[0].key;
await loadLevel(levelList.some(l => l.key === startKey) ? startKey : levelList[0].key);
markLevel($('startLevels'));
requestAnimationFrame(frame);
go.disabled = false; go.textContent = mode === 'touch' ? 'Tap to start' : 'Start';

// Test hook: scripted checks press the hands and keys and read the cart (mobile/test/drive_test.js).
window.__cart = {
  get cart() { return cart; }, get spares() { return spares; }, get bots() { return bots; }, get world() { return world; }, get level() { return level; }, get streamer() { return streamer; },
  get levelKey() { return levelKey; }, get started() { return started; }, get cam() { return cam; }, camera, renderer,
  RAPIER, v3, levels: levelList, loadLevel, loadedLoops, musicState, spawn, respawn, runCommand, setMode, get mode() { return mode; },
  /** {L, R: -1/0/1, lift, press} or null to give control back to the keys and screen. */
  setInput(inp) { testInput = inp ? { L: 0, R: 0, lift: false, press: false, ...inp } : null; },
  /** Steps the physics directly (no drawing) for `seconds`, calling sample() after each step. */
  simulate(seconds, sample, onStep) {
    paused = true;
    const n = Math.round(seconds / STEP);
    for (let i = 0; i < n; i++) {
      onStep && onStep(i * STEP); physicsStep(readInput()); sample && sample();
      if (streamer && i % 12 === 0) streamer.update(cart.origin(), 1);
    }
    paused = false;
  },
  renderOnce(dt = 1 / 60) { cart.sync(); for (const s of others()) s.sync(); for (const pr of level.props) if (pr.node) { const t = pr.body.translation(), r = pr.body.rotation(); pr.node.position.set(t.x, t.y, t.z); pr.node.quaternion.set(r.x, r.y, r.z, r.w); } syncTraffic(level); updateCamera(dt); const c = cart.comWorld(); level.lights.update(new THREE.Vector3(c.x, c.y, c.z), 1); if (sun.visible) { const d = sun.userData.dir; sun.position.set(c.x - d.x * 30, c.y - d.y * 30, c.z - d.z * 30); sun.target.position.set(c.x, c.y, c.z); } skyDome.position.copy(camera.position); hud(); renderer.render(scene, camera); },
  stats() { return { drawCalls: renderer.info.render.calls, triangles: renderer.info.render.triangles, meshes: level.drawn, fps }; },
};
