// A supermarket sweep: a port of scripts/sweep/sweep.gd (one player and the level's bots; the browser game has no
// multiplayer). Everyone lines up at the entrance, 3, 2, 1, GO!, then each shopper has the round's seconds to fill
// their cart: roll slowly past a display and its items drop into the basket one at a time (at most item_limit of
// any one product), bump a giant inflatable first to claim its bonus, stand still in a bonus station's box to earn
// its bonus. When time's up a cart's score is what's in its basket at that moment plus its bonuses. The level's
// sweep comes from the Godot scene in levels/<key>.json ("sweep"); the products and inflatables are its loose props.
import * as THREE from 'three';
import { v3, add, sub, rot, qinv, xfMatrix } from './util.js';
import { labelObject, labelTexture } from './level.js';

export const IDLE = 0, COUNTDOWN = 2, SWEEPING = 3, DONE = 4;   // the Godot Sweep.Phase numbers (no WAITING here)

/** Cents as dollars: $123.45 (SweepHUD.money). */
export function money(c) { return `${c < 0 ? '-' : ''}$${Math.floor(Math.abs(c) / 100)}.${String(Math.abs(c) % 100).padStart(2, '0')}`; }
/** Time left as m:ss. */
export function formatLeft(t) { const s = Math.ceil(Math.max(t, 0)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; }
const ordinal = n => n + (n % 100 >= 11 && n % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] || 'th'));
// Points on the frame (cart-local) that stand in for its collision shapes when testing a zone: handle, basket, nose.
const FRAME_POINTS = [v3(0.1, 0.5, 0), v3(0.5, 0.6, 0), v3(0.9, 0.5, 0)];

class Box {
  constructor(z) { this.inv = xfMatrix(z.xf).invert(); this.half = new THREE.Vector3(...z.size).multiplyScalar(0.5); }
  has(p) { const q = new THREE.Vector3(p.x, p.y, p.z).applyMatrix4(this.inv); return Math.abs(q.x) <= this.half.x && Math.abs(q.y) <= this.half.y && Math.abs(q.z) <= this.half.z; }
  hasCart(cart) { const f = cart.frame, t = f.translation(), r = f.rotation(); return FRAME_POINTS.some(p => this.has(add(t, rot(r, p)))); }
}

export class Sweep {
  /** data: the level's "sweep"; game: {cart(), bots(), spawn(pos, yaw), props, root, RAPIER, world}; el: HUD elements. */
  constructor(data, game, el) {
    this.D = data; this.game = game; this.el = el;
    this.phase = IDLE; this.clock = 0; this.roundTime = data.duration; this.shoppers = []; this.toasts = []; this.lastBasket = -1;
    const byId = new Map(game.props.map(p => [p.id, p]));
    const pose = b => ({ p: { ...b.translation() }, q: { ...b.rotation() } });
    this.displays = data.displays.map(d => {
      const items = d.items.map(id => byId.get(id)).filter(Boolean).map(pr => ({ ...pr, rest: pose(pr.body), onDisplay: true, name: d.name, cents: Math.round(d.price * 100) }));
      const disp = { ...d, items, zone: new Box(d.zone), cents: Math.round(d.price * 100), shown: '' };
      disp.label = labelObject(d.left_label); disp.label.renderOrder = 1; game.root.add(disp.label);
      return disp;
    });
    this.products = this.displays.flatMap(d => d.items);
    this.bonuses = data.bonuses.map(b => {
      const pr = byId.get(b.node);
      const out = { ...b, prop: pr, rest: pr ? pose(pr.body) : null, claimed: false, cents: Math.round(b.bonus * 100) };
      if (b.label && pr) { out.sprite = labelObject(b.label); out.sprite.renderOrder = 1; game.root.add(out.sprite); }
      return out;
    }).filter(b => b.prop);
    this.stations = data.stations.map(s => ({ ...s, zone: new Box(s.zone), cents: Math.round(s.bonus * 100) }));
    this._drawLabels();
  }

  left(d) { return d.items.filter(p => p.onDisplay).length; }

  /** Restocks the store, lines everyone up and starts the count; again mid-sweep starts over. seconds > 0 sets
   *  the round's length (else the scene's duration). */
  start(withBots = this.D.bots_shop, seconds = 0) {
    this.roundTime = seconds > 0 ? seconds : this.D.duration;
    for (const s of this.shoppers) if (s.bot) s.bot.stopErrand();
    for (const p of this.products) this._restock(p);
    for (const b of this.bonuses) { b.claimed = false; this._putBack(b.prop, b.rest, false); }
    this.shoppers = [this._shopper(1, 'You', null)];
    if (withBots) this.game.bots().forEach((b, i) => this.shoppers.push(this._shopper(-(i + 1), `Bot ${i + 1}`, b)));
    this.shoppers.length = Math.min(this.shoppers.length, this.D.slots.length);
    this.shoppers.forEach((s, i) => {
      const sl = this.D.slots[i], pos = v3(...sl.pos);
      if (s.bot) { s.bot.cart.place(pos, sl.yaw); s.bot.stopErrand(); s.bot.driveTo(pos); } else this.game.spawn(pos, sl.yaw);
    });
    this.phase = COUNTDOWN; this.clock = this.D.countdown; this.lastBasket = -1; this.toasts = [];
    this.lockAll(true);
    this.el.results.hidden = true;
  }

  _shopper(id, name, bot) {
    return { id, name, bot, cents: 0, items: 0, bonus: 0, grabWait: 0, warned: new Set(), stationTime: new Map(), stationsDone: new Set(), target: null, linger: 0, visited: null };
  }
  cartOf(s) { return s.bot ? s.bot.cart : this.game.cart(); }
  lockAll(on) { for (const s of this.shoppers) this.cartOf(s).locked = on; }

  _putBack(pr, rest, fixed) {
    const { RAPIER } = this.game;
    pr.body.setBodyType(fixed ? RAPIER.RigidBodyType.Fixed : RAPIER.RigidBodyType.Dynamic, false);
    pr.body.setTranslation(rest.p, false); pr.body.setRotation(rest.q, false);
    if (!fixed) { pr.body.setLinvel(v3(0, 0, 0), false); pr.body.setAngvel(v3(0, 0, 0), false); pr.body.sleep(); }
    if (pr.node) { pr.node.position.set(rest.p.x, rest.p.y, rest.p.z); pr.node.quaternion.set(rest.q.x, rest.q.y, rest.q.z, rest.q.w); }
  }
  _restock(p) { p.onDisplay = true; this._putBack(p, p.rest, true); }

  /** Product.drop_into: off the display and into the cart's basket at slot (cart-local), moving with the cart. */
  _drop(p, cart) {
    const { RAPIER } = this.game, f = cart.frame, fq = f.rotation();
    const slot = v3(0.55 + 0.2 * (Math.random() * 2 - 1), 1.08, 0.15 * (Math.random() * 2 - 1));   // ShoppingCart.basket_drop
    const at = add(f.translation(), rot(fq, slot));
    const q = new THREE.Quaternion(fq.x, fq.y, fq.z, fq.w).multiply(new THREE.Quaternion(p.rest.q.x, p.rest.q.y, p.rest.q.z, p.rest.q.w));
    p.onDisplay = false;
    p.body.setBodyType(RAPIER.RigidBodyType.Dynamic, true);
    p.body.setTranslation(at, true); p.body.setRotation({ x: q.x, y: q.y, z: q.z, w: q.w }, true);
    p.body.setLinvel(f.linvel(), true); p.body.setAngvel(v3(0, 0, 0), true);
  }

  inBasket(cart, p) {
    const f = cart.frame, l = rot(qinv(f.rotation()), sub(p.body.translation(), f.translation()));
    return l.x > 0.05 && l.x < 1.0 && Math.abs(l.z) < 0.33 && l.y > 0.4 && l.y < 1.2;
  }
  countOf(cart, name) { return this.products.filter(p => !p.onDisplay && p.name === name && this.inBasket(cart, p)).length; }

  /** One physics step (before the carts step). */
  step(dt) {
    if (this.phase === IDLE) return;
    for (const s of this.shoppers) { const c = this.cartOf(s); if (c.groceries.length) c.dropGroceries(); }
    if (this.phase === COUNTDOWN) {
      this.lockAll(true);   // every step: a cart reset during the count is a new cart
      this.clock -= dt;
      if (this.clock <= 0) { this.phase = SWEEPING; this.clock = this.roundTime; this.lockAll(false); }
    } else if (this.phase === SWEEPING) {
      this.clock -= dt;
      this._shop(dt);
      if (this.clock <= 0) { this.clock = 0; this._end(); }
    }
  }

  _shop(dt) {
    const L = this.D.item_limit;
    for (const s of this.shoppers) {
      const c = this.cartOf(s), v = c.frame.linvel(), speed = Math.hypot(v.x, v.y, v.z);
      s.grabWait = Math.max(0, s.grabWait - dt);
      if (s.grabWait <= 0 && speed < this.D.grab_speed && !c.fallen) {
        for (const d of this.displays) {
          if (!d.zone.hasCart(c)) continue;
          const item = [...d.items].reverse().find(p => p.onDisplay);   // the top of the stack
          if (!item) continue;
          if (this.countOf(c, d.name) >= L) {
            if (!s.warned.has(d.name)) { s.warned.add(d.name); this._event(s, `Limit ${L} of ${d.name}`); }
            continue;
          }
          this._drop(item, c);
          s.grabWait = this.D.grab_interval;
          this._event(s, `+${money(item.cents)}  ${d.name}`);
          break;
        }
      }
      for (const [k, st] of this.stations.entries()) {
        if (s.stationsDone.has(k)) continue;
        if (st.zone.hasCart(c) && speed < st.still_speed) {
          const t = (s.stationTime.get(k) || 0) + dt;
          s.stationTime.set(k, t);
          if (t >= st.hold_time) { s.stationsDone.add(k); s.bonus += st.cents; this._event(s, `BONUS +${money(st.cents)}  ${st.title.toLowerCase().replace(/\b\w/g, m => m.toUpperCase())}`); }
        } else s.stationTime.delete(k);
      }
    }
    // Inflatables: the first shopper's cart to touch one claims it.
    for (const b of this.bonuses) {
      if (b.claimed) continue;
      const who = this.shoppers.find(s => this._touching(this.cartOf(s).frame, b.prop.body));
      if (!who) continue;
      b.claimed = true; who.bonus += b.cents;
      const r = b.rest;
      this._putBack(b.prop, { p: add(r.p, v3(...b.stash)), q: r.q }, true);
      this._event(who, `BONUS +${money(b.cents)}  ${b.name}!`);
    }
    for (const s of this.shoppers) if (s.bot) this._steerBot(s, dt);
    this._tally();
  }

  _touching(a, b) {
    const { world } = this.game;
    for (let i = 0; i < a.numColliders(); i++) for (let j = 0; j < b.numColliders(); j++) {
      let hit = false;
      world.contactPair(a.collider(i), b.collider(j), m => { if (m.numContacts() > 0) hit = true; });
      if (hit) return true;
    }
    return false;
  }

  _tally() {
    const loose = this.products.filter(p => !p.onDisplay);
    for (const p of loose) if (p.body.isSleeping()) p.body.wakeUp();   // Godot's products have can_sleep off
    for (const s of this.shoppers) {
      const c = this.cartOf(s), per = new Map();
      let cents = 0, items = 0;
      for (const p of loose) {
        if (!this.inBasket(c, p)) continue;
        const n = per.get(p.name) || 0;
        if (n < this.D.item_limit) { per.set(p.name, n + 1); cents += p.cents; items++; }
      }
      s.cents = cents + s.bonus; s.items = items;
    }
  }

  _steerBot(s, dt) {
    const bot = s.bot;
    if (bot.cart.fallen) return;
    const d = s.target;
    if (d && bot.atErrand()) {
      s.linger += dt;
      if (this.left(d) === 0 || this.countOf(bot.cart, d.name) >= this.D.item_limit || s.linger > this.D.bot_linger) { s.visited = d; s.target = null; }
    }
    if (s.target) return;
    const at = bot.cart.origin(), taken = this.shoppers.filter(o => o.bot && o !== s).map(o => o.target);
    let best = null, bestV = 0;
    for (const c of this.displays) {
      if (c === s.visited) continue;
      const can = Math.min(this.left(c), this.D.item_limit - this.countOf(bot.cart, c.name));
      if (can <= 0) continue;
      const st = c.stop;
      let v = c.price * can / (Math.hypot(st[0] - at.x, st[1] - at.y, st[2] - at.z) + 6);
      if (taken.includes(c)) v *= 0.3;   // another bot is headed there: spread out
      if (v > bestV) { bestV = v; best = c; }
    }
    if (best) { s.target = best; s.linger = 0; bot.driveTo(v3(...best.stop)); }
  }

  _event(s, text) { if (s.id === 1) { this.toasts.unshift([text, 1.6]); this.toasts.length = Math.min(this.toasts.length, 3); } }

  _end() {
    this._tally();
    this.phase = DONE;
    for (const s of this.shoppers) if (s.bot) s.bot.stopErrand();
    this._showResults();
  }

  /** Best first: by score, then fewer items, then name. */
  results() {
    return this.shoppers.map(s => ({ id: s.id, name: s.name, cents: s.cents, items: s.items, bonus: s.bonus }))
      .sort((a, b) => b.cents - a.cents || a.items - b.items || a.name.localeCompare(b.name));
  }

  _showResults() {
    const rows = this.results(), w = Math.max(6, ...rows.map(r => r.name.length + 2));
    this.el.table.textContent = rows.map((r, i) => {
      const name = r.name + (r.id === 1 ? ' ◀' : '');
      return `${ordinal(i + 1).padEnd(4)} ${name.padEnd(w)} ${money(r.cents).padStart(9)}  ${String(r.items).padStart(2)} items${r.bonus > 0 ? `  (bonus ${money(r.bonus)})` : ''}`;
    }).join('\n');
    this.el.results.hidden = false;
  }

  /** Display signs ("8 left") and the inflatables' price tags, which follow their inflatable. */
  _drawLabels() {
    for (const d of this.displays) {
      const n = this.left(d), text = n === 0 ? 'SOLD OUT' : `${n} left`;
      if (text === d.shown) continue;
      d.shown = text;
      const old = d.label.material.map;
      d.label.material.map = labelTexture({ ...d.left_label, text });
      const t = d.label.material.map.userData;
      d.label.geometry.dispose(); d.label.geometry = new THREE.PlaneGeometry(t.w * d.left_label.pixel_size, t.h * d.left_label.pixel_size);
      d.label.material.needsUpdate = true;
      old.dispose();
    }
    for (const b of this.bonuses) {
      if (!b.sprite) continue;
      const t = b.prop.body.translation(), r = b.prop.body.rotation(), p = add(t, rot(r, v3(...b.label_offset)));
      b.sprite.position.set(p.x, p.y, p.z);
      b.sprite.visible = !b.claimed;
    }
  }

  /** The sweep HUD, every frame (sweep_hud.gd). */
  draw(dt) {
    this._drawLabels();
    const el = this.el;
    el.root.hidden = this.phase === IDLE;
    if (this.phase === IDLE) return;
    const me = this.shoppers[0];
    let count = '', t = 0, left = this.roundTime, status = '';
    if (this.phase === COUNTDOWN) {
      const n = Math.ceil(this.clock);
      count = n > 0 ? String(n) : 'GO!'; t = n > 0 ? n - this.clock : 0;
      status = `Get ready to shop! ${this.D.item_limit} of any one item counts`;
    } else if (this.phase === SWEEPING) {
      const since = this.roundTime - this.clock;
      if (since < this.D.go_hold) { count = 'GO!'; t = since / this.D.go_hold; }
      left = this.clock;
      if (since < 8) status = 'Roll slowly past a display to grab · don’t spill!';
    } else { left = 0; status = 'Time’s up!'; }
    // What's in the basket went down: something fell out.
    const basket = me.cents - me.bonus;
    if (this.phase === SWEEPING && this.lastBasket >= 0 && basket < this.lastBasket) this._event(me, `Spilled! -${money(this.lastBasket - basket)}`);
    this.lastBasket = basket;
    el.clock.textContent = formatLeft(left);
    el.clock.classList.toggle('hurry', left <= 10 && left > 0);
    el.status.textContent = status;
    el.total.textContent = money(me.cents);
    el.detail.textContent = `${me.items} item${me.items === 1 ? '' : 's'}${me.bonus > 0 ? `  ·  bonus ${money(me.bonus)}` : ''}`;
    for (const x of this.toasts) x[1] -= dt;
    this.toasts = this.toasts.filter(x => x[1] > 0);
    el.toasts.textContent = this.toasts.map(x => x[0]).join('\n');
    el.toasts.style.opacity = this.toasts.length ? String(Math.min(1, this.toasts[0][1] / 0.3)) : '0';
    el.standings.hidden = this.shoppers.length < 2;
    el.standings.textContent = this.results().map(r => `${r.id === 1 ? '▶ ' : ''}${r.name}  ${money(r.cents)}`).join('\n');
    el.count.hidden = !count;
    el.count.textContent = count;
    el.count.classList.toggle('go', count === 'GO!');
    el.count.style.transform = `translate(-50%, -50%) scale(${1.6 + (1 - 1.6) * Math.min(1, t * 4)})`;
    el.count.style.opacity = count === 'GO!' ? String(1 - Math.min(Math.max(t - 0.6, 0), 0.4) / 0.4) : '1';
  }
}
