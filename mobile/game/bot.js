// A bot cart: a line-for-line port of scripts/cart_bot.gd. It drives its cart only through the keys a player
// presses (the same {L, R, lift, press} input the keyboard and touch rockers give cart.step), wandering between
// random spots on the level's navigation mesh. Its settings are the CartBot exports, exported from
// scenes/cart/bot_cart.tscn into levels/cart.json ("bot").
import { v3, add, rot, clamp } from './util.js';
import { NavAgent, pathLength, dist } from './nav.js';

const PAUSE = 0, DRIVE = 1, BACK_OFF = 2, GET_UP = 3;
const wrap = a => { a = (a + Math.PI) % (2 * Math.PI); if (a < 0) a += 2 * Math.PI; return a - Math.PI; };
const lerp = (a, b, t) => a + (b - a) * t;

export class Bot {
  constructor(cart, mesh, S, rand = Math.random) {
    this.cart = cart; this.mesh = mesh; this.S = S; this.rand = rand;
    this.agent = new NavAgent(mesh, { pathDesired: S.path_desired_distance, targetDesired: S.target_desired_distance });
    this.state = PAUSE; this.timer = this._range(S.pause_min, S.pause_max);
    this.tripTime = 0; this.tripLimit = 0; this.stuck = 0; this.backoffs = 0;
    this.stats = { trips: 0, gave_up: 0, backed_off: 0, fell: 0 };
    this.controls = {};
  }

  _range(a, b) { return a + (b - a) * this.rand(); }
  /** Where the agent sits: the NavPoint marker on the frame (the middle of the basket). */
  navPoint() { const f = this.cart.frame; return add(f.translation(), rot(f.rotation(), v3(...this.S.nav_point))); }

  /** Picks a random reachable spot between min_trip and max_trip of path away (CartBot.pick_target). */
  pickTarget() {
    const S = this.S, from = this.mesh.closest(this.navPoint()).point;
    let best = from, bestLen = 0;
    for (let i = 0; i < 12; i++) {
      const p = this.mesh.randomPoint(this.rand);
      const path = this.mesh.path(from, p);
      if (!path.length || dist(path[path.length - 1], p) > 0.3) continue;
      const length = pathLength(path);
      if (length > S.max_trip) continue;
      if (length > bestLen) { best = p; bestLen = length; }
      if (length >= S.min_trip) break;
    }
    if (bestLen < 1.5) return false;
    this.agent.setTarget(best);
    this.tripTime = 0;
    this.tripLimit = S.give_up_slack + bestLen / (0.5 * S.cruise_speed);
    this.stuck = 0; this.backoffs = 0;
    return true;
  }

  /** One physics step: returns the cart input {L, R, lift, press} for cart.step. */
  update(dt) {
    const S = this.S;
    this.agent.update(this.navPoint());
    let c = {};
    if (this.cart.fallen) {
      // Lying over: let go once, then hold both hands to haul it back onto its wheels (the cart's own rule).
      if (this.state !== GET_UP) { this.stats.fell++; this.state = GET_UP; this.timer = 0.3; }
      this.timer -= dt;
      if (this.timer <= 0) c = { push_left: true, push_right: true };
      return this._press(c);
    }
    if (this.state === GET_UP) { this.state = PAUSE; this.timer = 1.0; }
    if (this.state === PAUSE) {
      // Standing still, as a player would: hold the cart against rolling away (down a ramp, or coasting in).
      c = this._hands(-S.speed_gain * this._speed(), 0);
      this.timer -= dt;
      if (this.timer <= 0 && this.pickTarget()) this.state = DRIVE;
    } else if (this.state === DRIVE) {
      this.tripTime += dt;
      const done = this.agent.isFinished();
      if (done || this.tripTime > this.tripLimit || this.backoffs >= S.max_back_offs) {
        this.stats[done ? 'trips' : 'gave_up']++;
        this.state = PAUSE; this.timer = this._range(S.pause_min, S.pause_max);
      } else c = this._drive(dt);
    } else if (this.state === BACK_OFF) {
      this.timer -= dt;
      c = this._hands(-S.max_power * 0.6, this._steerErr() * -S.steer_gain * 0.5);
      if (this.timer <= 0) { this.state = DRIVE; this.stuck = 0; this.agent.setTarget(this.agent.target); }
    }
    return this._press(c);
  }

  _steerErr() {
    const at = this.navPoint(), next = this.agent.nextPosition();
    const tx = next.x - at.x, tz = next.z - at.z;
    if (Math.hypot(tx, tz) < 0.01) return 0;
    return wrap(Math.atan2(-tz, tx) - this.cart.heading());
  }

  _speed() {
    const n = rot(this.cart.frame.rotation(), v3(1, 0, 0)), l = Math.hypot(n.x, n.z), v = this.cart.frame.linvel();
    return (v.x * n.x + v.z * n.z) / l;
  }

  _drive(dt) {
    const S = this.S, speed = this._speed(), yawRate = this.cart.frame.angvel().y, err = this._steerErr();
    // Slow down for corners and for the end of the trip.
    const left = this.agent.distanceToTarget();
    let want = lerp(S.cruise_speed, S.corner_speed, clamp(Math.abs(err) / S.spin_angle, 0, 1));
    want = Math.min(want, Math.max(0.4, left * 0.6));
    const forward = Math.abs(err) > S.spin_angle ? 0 : clamp(S.speed_gain * (want - speed), -S.max_power, S.max_power);
    const steer = S.steer_gain * err - S.steer_damping * yawRate;
    // Not getting anywhere while pushing: pull back a little, then try again.
    if (forward > 0 && speed < 0.15 && Math.abs(yawRate) < 0.3) {
      this.stuck += dt;
      if (this.stuck > S.stuck_time) { this.state = BACK_OFF; this.stats.backed_off++; this.backoffs++; this.timer = S.back_off_time; }
    } else this.stuck = Math.max(0, this.stuck - dt);
    return this._hands(forward, steer);
  }

  /** The keys for a forward force and a steering force (+ = turn left: the right hand pushes harder). */
  _hands(forward, steer) {
    const S = this.S, c = {};
    const want = { L: clamp(forward - steer, -S.max_power, S.max_power), R: clamp(forward + steer, -S.max_power, S.max_power) };
    for (const [side, suffix] of [['L', 'left'], ['R', 'right']]) {
      const w = want[side], p = this.cart.handPower[side];
      if (w > 3 && p < w) c['push_' + suffix] = true;
      else if (w < -3 && p > w) c['pull_' + suffix] = true;
    }
    return c;
  }

  /** The held keys as the cart's input, as the keyboard would give them. */
  _press(c) {
    this.controls = c;
    return {
      L: (c.push_left ? 1 : 0) - (c.pull_left ? 1 : 0), R: (c.push_right ? 1 : 0) - (c.pull_right ? 1 : 0),
      lift: !!c.lift, press: !!c.press,
    };
  }
}
