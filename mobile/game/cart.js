// The shopping cart: the same multi-body rig and the same hands as the Godot cart (scripts/cart.gd).
// The rig (bodies, masses, shapes, hinges, limits) comes from mobile/levels/cart.json and the feel from
// cart_tuning.js; both are exported from the Godot cart scene, which is the source of truth.
import * as THREE from 'three';
import { v3, add, sub, scale, dot, cross, len, norm, clamp, moveToward, arr, rot, qinv, xfMatrix, xfPose, color,
  bodyMatrix, godotGroups, groups } from './util.js';

// Cart settings Godot keeps as exports but the tuning file may not have yet (defaults = the Godot defaults).
const DEFAULTS = { arm_relax_rate: 1.0, settle_brake: 40.0, stop_delay: 0.25, power_base: 25, power_ramp: 120,
  power_relax: 400, sprint_speed: 5, wrist_lever: 0.3, lift_pitch: -0.2, press_pitch: 0.3, side_roll: 0.22,
  tilt_kp: 1400, tilt_kd: 80, tilt_max: 200, tip_delay: 0.6, tip_rate: 0.7, let_go_pitch: 0.95, fallen_upright: 0.3, fallen_still: 1.0, stood_upright: 0.95,
  settle_max_slope: 0.04, max_angular_velocity: 0.25 * Math.PI * 60 };
const PROJECT_LINEAR_DAMP = 0.02, PROJECT_ANGULAR_DAMP = 0.05;   // Godot project settings
// Visual model pivots (mobile/models/cart.glb, same names as the Godot model) for each physics body.
const PIVOTS = { Frame: 'Frame', Gate: 'Gate_Hinge', ChildSeat: 'ChildSeat_Hinge', SeatFlap: 'SeatFlap_Hinge',
  Fork_FL: 'Caster_FL_Swivel', Fork_FR: 'Caster_FR_Swivel', Wheel_FL: 'Wheel_FL_Axle', Wheel_FR: 'Wheel_FR_Axle',
  Wheel_RL: 'Wheel_RL_Axle', Wheel_RR: 'Wheel_RR_Axle' };
export const SIDES = [['L', -1], ['R', 1]];

/** Rapier collider description for an exported shape (local transform kept). */
export function shapeDesc(RAPIER, s) {
  let d;
  switch (s.type) {
    case 'box': d = RAPIER.ColliderDesc.cuboid(s.size[0] / 2, s.size[1] / 2, s.size[2] / 2); break;
    // A world boundary: an endless floor. The vendored Rapier (0.14) has no half-space collider, so it is a slab
    // 40 km across with its top on the plane.
    case 'plane': d = RAPIER.ColliderDesc.cuboid(20000, 1, 20000); break;
    case 'sphere': d = RAPIER.ColliderDesc.ball(s.radius); break;
    case 'cylinder': d = RAPIER.ColliderDesc.cylinder(s.height / 2, s.radius); break;
    case 'capsule': d = RAPIER.ColliderDesc.capsule(Math.max(0.001, s.height / 2 - s.radius), s.radius); break;
    case 'convex': d = RAPIER.ColliderDesc.convexHull(new Float32Array(s.points)); break;
    case 'mesh': {
      // Godot's faces wind clockwise; Rapier's counter-clockwise. With them turned round, Rapier can fix internal edges:
      // without that, a wheel rolling over the edge between two triangles (every 4 m on the coast highway's deck) can
      // catch on it and hop. Jolt doesn't.
      const v = new Float32Array(s.faces), idx = new Uint32Array(v.length / 3);
      for (let i = 0; i < idx.length; i += 3) { idx[i] = i; idx[i + 1] = i + 2; idx[i + 2] = i + 1; }
      d = RAPIER.ColliderDesc.trimesh(v, idx, RAPIER.TriMeshFlags.FIX_INTERNAL_EDGES); break;
    }
  }
  if (!d) return null;
  const { p, q } = xfPose(xfMatrix(s.xf));
  if (s.type === 'plane') {   // sink the slab 1 m along the plane's normal (local +Y)
    p.x -= 2 * (q.x * q.y - q.w * q.z); p.y -= 1 - 2 * (q.x * q.x + q.z * q.z); p.z -= 2 * (q.y * q.z + q.w * q.x);
  }
  return d.setTranslation(p.x, p.y, p.z).setRotation(q);
}

const shapeVolume = s => s.type === 'box' ? s.size[0] * s.size[1] * s.size[2]
  : s.type === 'sphere' ? 4 / 3 * Math.PI * s.radius ** 3
  : s.type === 'cylinder' || s.type === 'capsule' ? Math.PI * s.radius ** 2 * s.height : 0.001;
const shapeExtents = s => s.type === 'box' ? s.size : s.type === 'sphere' ? [2 * s.radius, 2 * s.radius, 2 * s.radius]
  : [2 * (s.radius || 0.1), s.height || 0.2, 2 * (s.radius || 0.1)];

/** Mass properties as Jolt works them out: centre of mass from the shapes (or the custom one), inertia of solid shapes. */
export function massProps(mass, shapes, customCom) {
  let vol = 0, c = v3(0, 0, 0);
  for (const s of shapes) { const w = shapeVolume(s); vol += w; c = add(c, scale(v3(s.xf[9], s.xf[10], s.xf[11]), w)); }
  const com = customCom ? arr(customCom) : vol > 0 ? scale(c, 1 / vol) : v3(0, 0, 0);
  const I = v3(0, 0, 0);
  for (const s of shapes) {
    const m = vol > 0 ? mass * shapeVolume(s) / vol : mass, [x, y, z] = shapeExtents(s);
    const d = sub(v3(s.xf[9], s.xf[10], s.xf[11]), com);
    const k = s.type === 'sphere' ? 0.4 * s.radius * s.radius : 0;
    I.x += k ? m * k : m / 12 * (y * y + z * z); I.y += k ? m * k : m / 12 * (x * x + z * z); I.z += k ? m * k : m / 12 * (x * x + y * y);
    I.x += m * (d.y * d.y + d.z * d.z); I.y += m * (d.x * d.x + d.z * d.z); I.z += m * (d.x * d.x + d.y * d.y);
  }
  return { com, inertia: v3(Math.max(I.x, 1e-4), Math.max(I.y, 1e-4), Math.max(I.z, 1e-4)) };
}

export class Cart {
  /**
   * @param ctx {RAPIER, world, scene, rig (cart.json), tune, model (THREE.Object3D or null), layers ([layer, mask] list)}
   * @param opts {pos, yaw, player, empty, bit}
   */
  constructor(ctx, { pos, yaw, player = true, empty = false, bit }) {
    const { RAPIER, world, rig } = ctx;
    this.ctx = ctx; this.player = player; this.bit = bit; this.ownBit = bit;
    // Nesting (nest.js): the cart this one's nose is in, the cart in this one's back, the joint, carts it passes through.
    this.nestedIn = null; this.nestedBehind = null; this.nest = null; this.ghosts = new Set(); this.keysHeld = false;
    this.cartColliders = [];   // [collider, layer, mask] of every cart part, to regroup when carts pass through each other
    this.T = Object.assign({}, DEFAULTS, ctx.tune);
    this.handPower = { L: 0, R: 0 }; this.armExt = { L: 0, R: 0 }; this.handState = { L: '', R: '' };
    this.fallen = false; this.waitRelease = false; this.tiltDir = 0; this.tiltTime = 0; this.letGo = false; this.pinned = false; this.restTime = 0; this.restAnchor = null;
    this.handPos = arr(rig.hand_position || [0, 1, 0.2]);
    this.wheelRadius = rig.wheel_radius;
    const q0 = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0));
    const qq = { x: q0.x, y: q0.y, z: q0.z, w: q0.w };
    this.q0 = qq;
    const origin = v3(pos.x, pos.y + 0.005, pos.z);
    const at = p => add(origin, rot(qq, p));
    const MIN = RAPIER.CoefficientCombineRule.Min;

    this.b = {}; this.local = {}; this.bodyMass = {};
    for (const bd of rig.bodies) {
      const lp = v3(bd.xf[9], bd.xf[10], bd.xf[11]), wp = at(lp);
      const { com, inertia } = massProps(bd.mass, bd.shapes, bd.com);
      const angDamp = bd.angular_damp_mode === 1 ? bd.angular_damp : PROJECT_ANGULAR_DAMP + bd.angular_damp;
      const linDamp = bd.linear_damp >= 0 ? bd.linear_damp : PROJECT_LINEAR_DAMP;
      const body = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(wp.x, wp.y, wp.z).setRotation(qq)
        .setAdditionalMassProperties(bd.mass, com, inertia, { x: 0, y: 0, z: 0, w: 1 })
        .setCanSleep(!player).setLinearDamping(linDamp).setAngularDamping(angDamp));
      const g = godotGroups(bd.layer, ctx.widen(bd.layer, bd.mask), bit);
      for (const s of bd.shapes) {
        const d = shapeDesc(RAPIER, s);
        if (d) this.cartColliders.push([world.createCollider(d.setDensity(0).setFriction(bd.friction).setFrictionCombineRule(MIN).setCollisionGroups(g), body), bd.layer, bd.mask]);
      }
      this.b[bd.name] = body; this.local[bd.name] = lp; this.bodyMass[bd.name] = bd.mass;
      if (bd.name === 'Frame') this.com = com;
    }
    this.frame = this.b.Frame; this.gate = this.b.Gate;
    this.wheels = {}; this.forks = {};
    for (const k of ['FL', 'FR', 'RL', 'RR']) this.wheels[k] = this.b['Wheel_' + k];
    for (const k of ['FL', 'FR']) if (this.b['Fork_' + k]) this.forks[k] = this.b['Fork_' + k];
    this.totalMass = Object.values(this.bodyMass).reduce((a, b) => a + b, 0);

    // Hinges: Godot's HingeJoint3D turns about the joint's Z axis. Rapier measures the angle the other way round,
    // so Godot's [lower, upper] becomes [-upper, -lower]. All bodies start unrotated in the cart's frame.
    this.joints = {};
    for (const j of rig.joints) {
      const a = this.b[j.a], b = this.b[j.b];
      if (!a || !b) continue;
      const o = v3(j.xf[9], j.xf[10], j.xf[11]), axis = norm(v3(j.xf[6], j.xf[7], j.xf[8]));
      const joint = world.createImpulseJoint(RAPIER.JointData.revolute(sub(o, this.local[j.a]), sub(o, this.local[j.b]), axis), a, b, true);
      joint.setContactsEnabled(false);
      if (j.limit) joint.setLimits(-j.limit[1], -j.limit[0]);
      this.joints[j.name] = joint;
    }
    // Guard zone: a loose object or another cart entering it releases a pinned cart before it hits.
    if (rig.guard) {
      const d = shapeDesc(RAPIER, rig.guard);
      this.guard = world.createCollider(d.setSensor(true).setDensity(0).setCollisionGroups(godotGroups(2, 3, bit))
        .setActiveEvents(RAPIER.ActiveEvents.COLLISION_EVENTS)
        .setActiveCollisionTypes(RAPIER.ActiveCollisionTypes.DEFAULT | RAPIER.ActiveCollisionTypes.KINEMATIC_KINEMATIC), this.frame);
    }
    this.parts = Object.values(this.b);
    this.partSet = new Set(this.parts.map(p => p.handle));

    // Groceries: loose boxes in the basket.
    this.groceries = []; this.meshes = [];
    if (!empty) for (const gd of rig.groceries) {
      const wp = at(v3(gd.xf[9], gd.xf[10], gd.xf[11]));
      const { com, inertia } = massProps(gd.mass, gd.shapes, gd.com);
      const body = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(wp.x, wp.y, wp.z).setRotation(qq)
        .setAdditionalMassProperties(gd.mass, com, inertia, { x: 0, y: 0, z: 0, w: 1 }).setCanSleep(true)
        .setLinearDamping(PROJECT_LINEAR_DAMP).setAngularDamping(PROJECT_ANGULAR_DAMP));
      const g = godotGroups(gd.layer, ctx.widen(gd.layer, gd.mask), 0);
      const grp = new THREE.Group();
      for (const s of gd.shapes) {
        world.createCollider(shapeDesc(RAPIER, s).setDensity(0).setFriction(gd.friction).setFrictionCombineRule(MIN).setCollisionGroups(g), body);
        if (s.type === 'box') {
          const m = new THREE.Mesh(new THREE.BoxGeometry(...s.size), new THREE.MeshStandardMaterial({ color: gd.color ? color(gd.color) : 0xffffff, roughness: gd.roughness ?? 0.7 }));
          m.applyMatrix4(xfMatrix(s.xf)); m.castShadow = m.receiveShadow = true; grp.add(m);
        }
      }
      ctx.scene.add(grp);
      this.groceries.push(body); this.meshes.push([body, grp]);
    }
    this.grocerySet = new Set(this.groceries.map(g => g.handle));
    this._linkModel(ctx.model);
  }

  // ---------------------------------------------------------------- visuals
  _linkModel(model) {
    this.links = [];
    if (!model) return;
    this.root = new THREE.Group();
    this.root.matrixAutoUpdate = false;
    this.root.add(model);
    this.ctx.scene.add(this.root);
    this.root.matrix.copy(bodyMatrix(this.frame)); this.root.updateMatrixWorld(true);
    for (const [body, pivot] of Object.entries(PIVOTS)) {
      if (body === 'Frame' || !this.b[body]) continue;
      const node = model.getObjectByName(pivot);
      if (!node) continue;
      this.links.push([node, this.b[body], bodyMatrix(this.b[body]).invert().multiply(node.matrixWorld.clone())]);
    }
    // Parents before children, so each pivot's parent is already in place.
    const depth = n => { let d = 0; while (n.parent) { n = n.parent; d++; } return d; };
    this.links.sort((a, b) => depth(a[0]) - depth(b[0]));
  }

  sync() {
    for (const [body, grp] of this.meshes) {
      const t = body.translation(), r = body.rotation();
      grp.position.set(t.x, t.y, t.z); grp.quaternion.set(r.x, r.y, r.z, r.w);
    }
    if (!this.root) return;
    this.root.matrix.copy(bodyMatrix(this.frame)); this.root.updateMatrixWorld(true);
    const m = new THREE.Matrix4(), pinv = new THREE.Matrix4();
    for (const [node, body, offset] of this.links) {
      m.multiplyMatrices(bodyMatrix(body), offset);
      pinv.copy(node.parent.matrixWorld).invert();
      node.matrix.multiplyMatrices(pinv, m);
      node.matrix.decompose(node.position, node.quaternion, node.scale);
      node.updateMatrixWorld(true);
    }
  }

  remove() {
    const { world, scene } = this.ctx;
    for (const b of [...this.parts, ...this.groceries]) world.removeRigidBody(b);
    for (const [, grp] of this.meshes) { scene.remove(grp); grp.traverse(o => { if (o.isMesh) { o.geometry.dispose(); o.material.dispose(); } }); }
    if (this.root) scene.remove(this.root);
  }

  // ---------------------------------------------------------------- state
  heading() { const n = rot(this.frame.rotation(), v3(1, 0, 0)); return Math.atan2(-n.z, n.x); }
  origin() { return this.frame.translation(); }
  comWorld() { return add(this.frame.translation(), rot(this.frame.rotation(), this.com)); }
  upright() { return rot(this.frame.rotation(), v3(0, 1, 0)).y; }

  /** A wheel touches the floor when something solid is right under it (works on every floor of the garage). */
  wheelDown(w) { return !!this._groundHit(w); }
  _groundHit(w, gap = 0.02) {
    const { RAPIER, world } = this.ctx, p = w.translation(), r = this.wheelRadius;
    return world.castRayAndGetNormal(new RAPIER.Ray(p, { x: 0, y: -1, z: 0 }), r + gap, true, undefined,
      groups(this.bit, 0x000f));   // the cart's own parts carry only its own bit, so they never match
  }
  /** Rise per run of the ground under the wheels (0 unless at least three are down), as Cart.ground_slope(). */
  groundSlope() {
    let nx = 0, ny = 0, nz = 0, down = 0;
    for (const w of Object.values(this.wheels)) {
      const hit = this._groundHit(w);
      if (hit) { nx += hit.normal.x; ny += hit.normal.y; nz += hit.normal.z; down++; }
    }
    if (down < 3) return 0;
    const l = Math.hypot(nx, ny, nz), y = ny / l;
    return Math.sqrt(Math.max(0, 1 - y * y)) / Math.max(y, 0.01);
  }
  wheelsDown() { let n = 0; for (const w of Object.values(this.wheels)) if (this.wheelDown(w)) n++; return n; }

  groceriesIn() {
    const qi = qinv(this.frame.rotation()), p = this.frame.translation();
    let n = 0;
    for (const g of this.groceries) {
      const l = rot(qi, sub(g.translation(), p));
      if (l.x > 0.05 && l.x < 1.0 && Math.abs(l.z) < 0.33 && l.y > 0.4 && l.y < 1.2) n++;
    }
    return n;
  }

  // ---------------------------------------------------------------- one physics step (before world.step)
  /** Whether this cart's own keys are held (set before any cart steps, so a stack can wake as one). */
  setKeys(inp) { this.keysHeld = !!inp && (inp.L !== 0 || inp.R !== 0 || !!inp.lift || !!inp.press); }

  /** inp: {L, R: -1 pull / 0 / +1 push, lift, press} for the player's cart; null for a spare cart. */
  step(inp, dt) {
    for (const b of this.parts) { b.resetForces(false); b.resetTorques(false); }
    // A stack is one herd: a key held on any of its carts keeps them all awake and rolling.
    const anyInput = this.stack().some(c => c.keysHeld);
    if (anyInput && this.pinned) this.wake();
    if (this.pinned) return;
    if (inp) this._applyHands(inp, dt);
    this._applyRollingResistance(dt);
    if (!anyInput) this._settle(dt); else { this.restTime = 0; this.restAnchor = null; }
  }

  _applyHands(inp, dt) {
    const T = this.T, f = this.frame, q = f.rotation(), p = f.translation();
    const nose = norm(rot(q, v3(1, 0, 0))), sideAxis = norm(rot(q, v3(0, 0, 1))), upAxis = norm(rot(q, v3(0, 1, 0)));
    const fwd = norm(v3(nose.x, 0, nose.z));
    const comG = add(p, rot(q, this.com));
    const lin = f.linvel(), ang = f.angvel();
    const upright = upAxis.y;
    const anyKey = inp.L !== 0 || inp.R !== 0 || inp.lift || inp.press;
    if (!this.fallen && upright < T.fallen_upright && len(ang) < T.fallen_still) {
      this.fallen = true; this.waitRelease = anyKey;
    } else if (this.fallen && upright > T.stood_upright) {
      // Back on its wheels: the hands rest until the keys are let go, so the haul doesn't throw it over again.
      this.fallen = false; this.waitRelease = anyKey; this.handPower = { L: 0, R: 0 };
    }
    if (!anyKey) this.waitRelease = false;
    // The push and pull only drive the cart while it stands: they fade out as it tips past 45 degrees.
    const driveScale = this.fallen ? 0 : clamp((upright - T.fallen_upright) / (0.7 - T.fallen_upright), 0, 1);
    // Stopping is pulling back with no hand pushing while the cart still rolls forward; push one hand and pull
    // the other and it's a spin, not a stop.
    const pushingAny = inp.L > 0 || inp.R > 0;
    const cartAlong = dot(lin, fwd);
    const yawRate = ang.y;   // + = turning left (counter-clockwise from above)
    const dirs = {}, handYaw = {};
    for (const [h, s] of SIDES) { dirs[h] = this.waitRelease ? 0 : inp[h]; handYaw[h] = s * dirs[h]; }
    const yawCmd = handYaw.L + handYaw.R;

    for (const [h, s] of SIDES) {
      const dir = dirs[h];
      // The hand's power: power_base the moment it goes on, growing while it's held; letting go relaxes it.
      let pw = this.handPower[h];
      pw = dir === 0 ? moveToward(pw, 0, T.power_relax * dt) : Math.max(pw * dir, T.power_base) * dir + dir * T.power_ramp * dt;
      this.handPower[h] = pw;
      const strength = Math.abs(pw);
      const handG = add(p, rot(q, v3(this.handPos.x, this.handPos.y, s * this.handPos.z)));
      const driveG = add(p, rot(q, v3(this.handPos.x, this.com.y, s * this.handPos.z)));   // where the push acts
      const r = sub(handG, comG);
      const along = dot(add(lin, cross(ang, r)), fwd);
      let st = '';
      if (dir < 0 && !pushingAny && cartAlong > 0.05 && along > 0) {
        // Stopping a rolling cart: the body plants its feet and the arms straighten as the cart carries on,
        // holding harder the further they stretch, up to leaning back with full body weight.
        this.armExt[h] = Math.min(T.arm_reach, this.armExt[h] + along * dt);
        let F = Math.min(T.brake_max, T.brake_spring * this.armExt[h] + T.brake_damping * along);
        if (this.armExt[h] >= T.arm_reach) F = T.brake_max;
        f.addForceAtPoint(scale(fwd, -Math.max(F, strength) * driveScale), driveG, true);
        st = `braking ${Math.round(Math.max(F, strength))} N (arm ${Math.round(100 * this.armExt[h] / T.arm_reach)}%)`;
      } else {
        this.armExt[h] = Math.max(0, this.armExt[h] - T.arm_relax_rate * dt);
        if (dir !== 0) {
          const k = clamp(1 - dir * along / T.sprint_speed, 0, 1);   // a running person tops out at sprint_speed
          f.addForceAtPoint(scale(fwd, dir * strength * k * driveScale), driveG, true);
          st = `${dir > 0 ? 'pushing' : 'pulling'} ${Math.round(strength)} N`;
        }
      }
      // Countering a spin: a hand working against the spin grabs the bar and braces it, like a planted arm.
      if (handYaw[h] * yawRate < 0 && yawCmd * yawRate < 0 && Math.abs(yawRate) > T.spin_grip_min) {
        const lever = Math.hypot(r.x, r.z);
        const t = Math.min(T.brake_max * lever, T.spin_grip * lever * lever * Math.abs(yawRate));
        f.addTorque(v3(0, -Math.sign(yawRate) * t, 0), true);
        st = (st ? st + ' + ' : '') + 'holding the spin';
      }
      if (this.fallen) {
        // Lying over: a held hand hauls the cart back toward upright, whichever way it fell, damped so it settles.
        if (dir !== 0) {
          let axis = cross(upAxis, v3(0, 1, 0));
          if (len(axis) < 0.05) axis = sideAxis;
          axis = norm(axis);
          f.addTorque(scale(axis, strength * T.wrist_lever - T.tilt_kd * dot(ang, axis)), true);
          st = 'hauling it upright';
        } else if (this.waitRelease) st = 'let go, then hold to haul it up';
      } else if (dir !== 0) {
        // The wrists lever the bar by the hand's full power: a push raises the nose, a pull drops it. Each wrist
        // also damps the pitching (half of tilt_kd), so a wheelie grows steadily instead of flipping the cart.
        const pAxis = norm(sideAxis);
        f.addTorque(scale(pAxis, dir * strength * T.wrist_lever - 0.5 * T.tilt_kd * dot(ang, pAxis)), true);
      }
      this.handState[h] = st;
    }
    // Grip: both hands the same way resist the cart twisting (keeps it tracking).
    if (dirs.L !== 0 && dirs.L === dirs.R) f.addTorque(v3(0, -T.grip_yaw_damping * yawRate, 0), true);

    // Lean keys: lift tips the back up, press the front, toward a lean with capped torque. Held on, the lean grows
    // (tip_rate) until the cart passes its balance point and the hands slip off (let_go_pitch). With one hand held
    // as well, only that side leans (lift raises it, press drops it). On a fallen cart they haul it back up.
    const tiltDir = inp.lift === inp.press ? 0 : (inp.press ? 1 : -1);
    if (tiltDir !== this.tiltDir) { this.tiltDir = tiltDir; this.tiltTime = 0; this.letGo = false; }
    if (tiltDir !== 0) {
      this.tiltTime += dt;
      if (Math.abs(Math.asin(clamp(nose.y, -1, 1))) > T.let_go_pitch || upright < 0) this.letGo = true;
    }
    if (tiltDir !== 0 && this.fallen && !this.waitRelease) {
      let axis = cross(upAxis, v3(0, 1, 0));
      if (len(axis) < 0.05) axis = sideAxis;
      axis = norm(axis);
      f.addTorque(scale(axis, T.tilt_max - T.tilt_kd * dot(ang, axis)), true);
      for (const [h] of SIDES) this.handState[h] = 'hauling it upright';
    } else if (tiltDir !== 0 && !this.fallen && !this.waitRelease && !this.letGo) {
      const pitch = Math.asin(clamp(nose.y, -1, 1)), roll = Math.asin(clamp(sideAxis.y, -1, 1));
      let sides = 0;
      if ((dirs.L !== 0) !== (dirs.R !== 0)) sides = dirs.R !== 0 ? 1 : -1;
      const pitchT = (inp.lift ? T.lift_pitch : T.press_pitch) * (sides ? 0.6 : 1) + tiltDir * T.tip_rate * Math.max(0, this.tiltTime - T.tip_delay);
      const rollT = sides * (inp.lift ? 1 : -1) * T.side_roll;
      const tp = clamp(T.tilt_kp * (pitchT - pitch) - T.tilt_kd * dot(ang, sideAxis), -T.tilt_max, T.tilt_max);
      const tr = clamp(T.tilt_kp * (rollT - roll) + T.tilt_kd * dot(ang, nose), -T.tilt_max, T.tilt_max);
      f.addTorque(sub(scale(sideAxis, tp), scale(nose, tr)), true);
      for (const [h] of SIDES) this.handState[h] = (this.handState[h] ? this.handState[h] + ' + ' : '') + (inp.lift ? 'leaning back up' : 'leaning front up');
    }
  }

  /** Each wheel on the floor resists rolling with a small torque, as real casters do. */
  _applyRollingResistance(dt) {
    const r = this.wheelRadius, maxT = this.T.rolling_resistance * this.totalMass * 9.81 / 4 * r;
    for (const [k, w] of Object.entries(this.wheels)) {
      if (!this.wheelDown(w)) continue;
      const axle = norm(rot(w.rotation(), v3(0, 0, 1)));
      const spin = dot(w.angvel(), axle);
      const inertia = 0.5 * this.bodyMass['Wheel_' + k] * r * r;
      const t = Math.min(maxT, Math.abs(spin) * inertia / dt);   // never reverse the spin within one step
      w.addTorque(scale(axle, -Math.sign(spin) * t), true);
    }
  }

  /** Nearly stopped with no hands on: brake gently, then pin the frame so it can't creep. */
  _settle(dt) {
    const T = this.T, f = this.frame;
    // On a hill a cart left alone on its wheels rolls away, as a real one does: no braking, no pinning.
    if (this.groundSlope() > T.settle_max_slope) { this.restTime = 0; this.restAnchor = null; return; }
    const v = len(f.linvel()), w = len(f.angvel());
    if (v < T.settle_speed && w < T.settle_spin) {
      f.addForce(scale(f.linvel(), -this.bodyMass.Frame * T.settle_brake), true);
      f.addTorque(scale(f.angvel(), -T.settle_brake), true);
    }
    // Rapier leaves a little joint-solver velocity on a cart standing still, so rest is judged by how far the
    // frame actually moved over the last stop_delay seconds rather than by its reported velocity.
    const pos = f.translation(), q = f.rotation(), a = this.restAnchor, W = T.stop_delay;
    const drift = a ? len(sub(pos, a.pos)) : Infinity;
    const twist = a ? 2 * Math.acos(clamp(Math.abs(q.x * a.q.x + q.y * a.q.y + q.z * a.q.z + q.w * a.q.w), 0, 1)) : Infinity;
    if (drift < T.stop_speed * W && twist < T.stop_spin * W && len(this.gate.angvel()) < 0.5) {
      this.restTime += dt;
      // In a stack, only once every cart of it has come to rest.
      if (this.restTime >= W && this.stack().every(c => c === this || c.pinned || c.restTime >= W)) for (const c of this.stack()) c.pin();
    } else {
      this.restAnchor = { pos: { ...pos }, q: { ...q } };
      this.restTime = 0;
    }
  }

  /**
   * Jolt (the Godot game's physics) caps every body's spin at its max_angular_velocity project setting (exported
   * as T.max_angular_velocity, 120 rad/s: a 6.35 cm wheel reaches it at about 7.6 m/s). Above that the Godot
   * cart's wheels skid and drag, so the same cap applies here, after each physics step.
   */
  capWheelSpin() {
    const cap = this.T.max_angular_velocity;
    for (const w of Object.values(this.wheels)) {
      const a = w.angvel(), l = len(a);
      if (l > cap) w.setAngvel(scale(a, cap / l), false);
    }
  }

  pin() {
    if (this.pinned) return;
    const { RAPIER } = this.ctx;
    for (const b of [this.frame, ...Object.values(this.wheels), ...Object.values(this.forks)]) { b.setLinvel(v3(0, 0, 0), false); b.setAngvel(v3(0, 0, 0), false); }
    this.frame.setBodyType(RAPIER.RigidBodyType.KinematicPositionBased, true);
    this.pinned = true;
  }

  wake() {
    const { RAPIER } = this.ctx;
    for (const c of this.stack()) {
      if (c.pinned) c.frame.setBodyType(RAPIER.RigidBodyType.Dynamic, true);
      for (const b of c.parts) b.wakeUp();
      c.pinned = false; c.restTime = 0; c.restAnchor = null;
    }
  }

  // ---------------------------------------------------------------- stacks (nest.js)
  /** The carts of this cart's stack, front to back (just this cart when it stands alone). */
  stack() {
    let f = this;
    while (f.nestedIn) f = f.nestedIn;
    const list = [];
    for (let c = f; c; c = c.nestedBehind) list.push(c);
    return list;
  }

  /** Every part collides as a member of `bit`: carts sharing a bit pass through each other (a nose in a basket). */
  setBit(bit) {
    if (bit === this.bit) return;
    this.bit = bit;
    for (const [c, layer, mask] of this.cartColliders) c.setCollisionGroups(godotGroups(layer, this.ctx.widen(layer, mask), bit));
    if (this.guard) this.guard.setCollisionGroups(godotGroups(2, 3, bit));
  }

  /** Mass of the whole rig (groceries left out). */
  rigMass() { return this.totalMass; }

  /** Something hit the guard zone of this pinned cart: let physics take it again (not its own parts or groceries). */
  guardHit(otherBody) {
    if (!this.pinned || !otherBody || !(otherBody.isDynamic() || otherBody.isKinematic())) return;   // props, carts, traffic
    if (this.partSet.has(otherBody.handle) || this.grocerySet.has(otherBody.handle)) return;
    if (this.stack().some(c => c.partSet.has(otherBody.handle))) return;
    this.wake();
  }
}
