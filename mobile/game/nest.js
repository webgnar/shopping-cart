// Stacked carts: one cart's nose tucked into the back of the one ahead, as the Godot game does it
// (scripts/cart/cart_nest.gd, scripts/cart/cart_nest_mouth.gd). The settings come from cart.json "nest", exported
// from scenes/cart/nest_joint.tscn and the cart's Frame/NestMouth.
// Rapier's prismatic joint stands in for Godot's Generic6DOFJoint3D: the same slide (limits) and grip (a velocity
// motor), but no yaw or pitch play, so a stack here bends less than in Godot.
import * as THREE from 'three';
import { v3, add, sub, scale, dot, len, rot, qinv, arr } from './util.js';

const _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();

export class Nest {
  /** Joins `behind` onto `ahead` where it stands now; it still has `stillToGo` m to slide before it is fully in. */
  constructor(ctx, ahead, behind, N, stillToGo = 0) {
    const { RAPIER, world } = ctx;
    this.ctx = ctx; this.ahead = ahead; this.behind = behind; this.N = N;
    this.anchorB = arr(N.pivot);
    const pw = add(behind.frame.translation(), rot(behind.frame.rotation(), this.anchorB));
    this.anchorA = rot(qinv(ahead.frame.rotation()), sub(pw, ahead.frame.translation()));
    this.lower = N.slide[0] + stillToGo; this.upper = N.slide[1] + stillToGo;
    const data = RAPIER.JointData.prismatic(this.anchorA, this.anchorB, v3(1, 0, 0));
    data.limitsEnabled = true; data.limits = [this.lower, this.upper];
    this.joint = world.createImpulseJoint(data, ahead.frame, behind.frame, true);
    this.joint.setContactsEnabled(false);
    if (N.grip > 0) this.joint.configureMotorVelocity(0, N.grip / 0.5);   // the baskets' grip on each other
    this.momentum = []; this.hits = [];
    ahead.nestedBehind = behind; behind.nestedIn = ahead; behind.nest = this;
    const carts = behind.stack();
    for (const a of carts) for (const b of carts) if (a !== b) { a.ghosts.add(b); b.ghosts.add(a); }
    this.setGate(true);
    behind.wake();
  }

  /** The gate of the cart ahead swings up into its basket (its hinge motor), or hangs again. */
  setGate(up) {
    const hinge = this.ahead.joints && this.ahead.joints.GateHinge;
    if (!hinge) return;
    // Rapier measures the hinge the other way round from Godot (cart.js), so up is + here.
    if (up) hinge.configureMotorVelocity(this.N.gate_speed, this.N.gate_impulse * 60);
    else hinge.configureMotorVelocity(0, 0);
  }

  /** m the cart behind has slid along the cart ahead since the joint was made (+ = further in). */
  slide() {
    const a = this.ahead.frame, b = this.behind.frame;
    const pa = add(a.translation(), rot(a.rotation(), this.anchorA));
    const pb = add(b.translation(), rot(b.rotation(), this.anchorB));
    return dot(sub(pb, pa), rot(a.rotation(), v3(1, 0, 0)));
  }

  /** One step, after world.step. Pulled all the way out, or knocked hard sideways: it comes apart. */
  update(world, dt) {
    if (this.apart) return;
    if (this.slide() <= this.lower + this.N.release_margin) { this.comeApart(); return; }
    const side = rot(this.ahead.frame.rotation(), v3(0, 0, 1));
    let pa = 0, pb = 0, ha = 0, hb = 0, back = false;
    for (const c of this.behind.stack()) {
      if (c === this.behind) back = true;
      const m = dot(c.frame.linvel(), side) * c.rigMass(), hit = touched(world, c) ? 1 : 0;
      if (back) { pb += m; hb = Math.max(hb, hit); } else { pa += m; ha = Math.max(ha, hit); }
    }
    this.momentum.push([pa, pb]); this.hits.push([ha, hb]);
    const steps = Math.max(2, Math.round(this.N.impulse_window / dt));
    while (this.momentum.length > steps) { this.momentum.shift(); this.hits.shift(); }
    const f = this.momentum[0], l = this.momentum[this.momentum.length - 1];
    const da = Math.abs(l[0] - f[0]), db = Math.abs(l[1] - f[1]);
    let hA = 0, hB = 0;
    for (const h of this.hits) { hA = Math.max(hA, h[0]); hB = Math.max(hB, h[1]); }
    // A knock on one side reaches the other only through this joint, so that side's change is the joint's load.
    let load = Math.min(da, db);
    if (hA && !hB) load = db; else if (hB && !hA) load = da;
    if (load > this.N.break_impulse) this.comeApart();
  }

  /** Lets go. The carts keep passing through each other until they are clear (dropClearGhosts). */
  comeApart() {
    if (this.apart) return;
    this.apart = true;
    this.ahead.nestedBehind = null; this.setGate(false);
    this.behind.nestedIn = null;
    if (this.behind.nest === this) this.behind.nest = null;
    try { this.ctx.world.removeImpulseJoint(this.joint, true); } catch (e) { /* the world was freed with its level */ }
  }
}

/** Whether something solid (not a cart it passes through, not its own groceries) touches the cart's frame. */
function touched(world, cart) {
  let hit = false;
  const frame = cart.frame;
  for (let i = 0; i < frame.numColliders() && !hit; i++) {
    const col = frame.collider(i);
    world.contactPairsWith(col, other => {
      if (hit) return;
      const body = other.parent();
      if (body && (cart.partSet.has(body.handle) || cart.grocerySet.has(body.handle))) return;
      if (body && [...cart.ghosts].some(g => g.partSet.has(body.handle))) return;
      world.contactPair(col, other, m => { if (m.numContacts() > 0) hit = true; });
    });
  }
  return hit;
}

/**
 * Each step, before the carts step: carts push their noses into the open backs of others and are caught.
 * `carts`: every cart in the level (the player's, spares, bots). Bot carts never nest.
 */
export function catchNoses(ctx, carts, N, isBot) {
  for (const a of carts) {
    if (a.nestedBehind || isBot(a)) continue;
    const qa = a.frame.rotation(), pa = a.frame.translation(), qia = qinv(qa);
    for (const b of carts) {
      if (b === a || b.nestedIn || isBot(b) || b.fallen || a.fallen) continue;
      if (b.stack().includes(a)) continue;
      const tipW = add(b.frame.translation(), rot(b.frame.rotation(), arr(N.nose)));
      const tip = rot(qia, sub(tipW, pa));
      if (tip.x < N.capture_depth || tip.x > N.capture_depth + 0.3 || Math.abs(tip.z) > N.capture_offset) continue;
      if (Math.abs(tip.y - N.nose[1]) > 0.25) continue;
      _q.set(qia.x, qia.y, qia.z, qia.w).multiply(_q2.set(...Object.values(b.frame.rotation())));
      const e = new THREE.Euler().setFromQuaternion(_q, 'YXZ');
      if (Math.abs(e.y) > N.capture_angle || Math.abs(e.x) > N.capture_tilt || Math.abs(e.z) > N.capture_tilt) continue;
      const nose = rot(qa, v3(1, 0, 0));
      const closing = dot(sub(b.frame.linvel(), a.frame.linvel()), nose);
      if (closing <= N.capture_speed) continue;
      take(ctx, a, b, N);
      break;
    }
  }
}

/** Lines `b` (and the carts behind it) up straight behind `a`, then joins it on. */
function take(ctx, a, b, N) {
  const qa = a.frame.rotation(), pa = a.frame.translation();
  const fa = rot(qa, v3(1, 0, 0)), fb = rot(b.frame.rotation(), v3(1, 0, 0));
  const turn = Math.atan2(fb.x * fa.z - fb.z * fa.x, fb.x * fa.x + fb.z * fa.z) * -1;   // about +Y, from b's heading to a's
  const o = b.frame.translation();
  const qTurn = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), turn);
  const turnQ = { x: qTurn.x, y: qTurn.y, z: qTurn.z, w: qTurn.w };
  // Sideways onto a's centre line.
  const local = rot(qinv(qa), sub(o, pa));
  const sideShift = scale(rot(qa, v3(0, 0, 1)), -local.z);
  for (const c of b.stack()) for (const body of [...c.parts, ...c.groceries]) {
    const p = add(add(o, rot(turnQ, sub(body.translation(), o))), sideShift);
    const r = body.rotation();
    _q.set(turnQ.x, turnQ.y, turnQ.z, turnQ.w).multiply(_q2.set(r.x, r.y, r.z, r.w));
    body.setTranslation(p, true); body.setRotation({ x: _q.x, y: _q.y, z: _q.z, w: _q.w }, true);
    body.setLinvel(rot(turnQ, body.linvel()), true);
  }
  const x = rot(qinv(qa), sub(b.frame.translation(), pa)).x;
  const stillToGo = -N.spacing - x;
  return new Nest(ctx, a, b, N, stillToGo);
}

/**
 * Each step: carts that pass through each other share one collision bit (Cart.setBit), so their parts don't
 * touch; once a cart that came apart is clear (basket centres ghost_clearance apart), it gets its own bit back.
 */
export function regroup(carts, N) {
  const centre = c => add(c.frame.translation(), rot(c.frame.rotation(), v3(0.47, 0.5, 0)));
  for (const c of carts) {
    const mine = c.stack();
    for (const o of [...c.ghosts]) {
      if (!carts.includes(o)) { c.ghosts.delete(o); continue; }
      if (mine.includes(o)) continue;
      const d = sub(centre(o), centre(c));
      if (Math.hypot(d.x, d.z) > N.ghost_clearance) { c.ghosts.delete(o); o.ghosts.delete(c); }
    }
  }
  // Groups: carts linked by ghosting, each with the lowest own bit among them.
  const seen = new Set();
  for (const c of carts) {
    if (seen.has(c)) continue;
    const group = [], todo = [c];
    while (todo.length) {
      const x = todo.pop();
      if (seen.has(x)) continue;
      seen.add(x); group.push(x);
      for (const g of x.ghosts) if (carts.includes(g)) todo.push(g);
    }
    const bit = Math.min(...group.map(g => g.ownBit));
    for (const g of group) g.setBit(group.length > 1 ? bit : g.ownBit);
  }
}

/** Builds a level's stacks: spare carts that name the spare they are nested in. */
export function buildStacks(ctx, spares, entries, N) {
  entries.forEach((e, i) => {
    if (e.nested_in === undefined || !spares[i] || !spares[e.nested_in]) return;
    new Nest(ctx, spares[e.nested_in], spares[i], N, 0);
  });
}
