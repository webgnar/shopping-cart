// A race down a level: a port of scripts/race/race.gd (one player; the browser game has no multiplayer). Everyone
// lines up on the grid, the screen counts 3, 2, 1, GO! with every cart's hands off the bar (cart.locked), then the
// clock runs until each cart's frame is inside the finish box. The results come up once everyone is over the line,
// or finish_grace seconds after the winner. The level's race comes from the Godot scene in levels/<key>.json
// ("race": countdown, go_hold, bots_race, finish_grace, slots, finish {xf, size}, route, bot_goal).
import * as THREE from 'three';
import { v3, xfMatrix } from './util.js';

export const IDLE = 0, COUNTDOWN = 2, RACING = 3, DONE = 4;   // the Godot Race.Phase numbers (no WAITING here)

/** Race time as m:ss.cc. */
export function formatTime(t) {
  const cs = Math.round(Math.max(t, 0) * 100);
  return `${Math.floor(cs / 6000)}:${String(Math.floor(cs / 100) % 60).padStart(2, '0')}.${String(cs % 100).padStart(2, '0')}`;
}
export function ordinal(n) {
  const s = n % 100 >= 11 && n % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] || 'th');
  return n + s;
}

export class Race {
  /** data: the level's "race"; game: {cart() -> the player's cart, bots() -> Bot list, spawn(pos, yaw)}; el: HUD elements. */
  constructor(data, game, el) {
    this.D = data; this.game = game; this.el = el;
    this.phase = IDLE; this.clock = 0; this.sinceWinner = -1; this.racers = [];
    const m = xfMatrix(data.finish.xf);
    this.finishInv = m.clone().invert();
    this.half = new THREE.Vector3(...data.finish.size).multiplyScalar(0.5);
  }

  /** Lines everyone up and starts the count; again mid-race starts over. */
  start(withBots = this.D.bots_race) {
    for (const r of this.racers) if (r.bot) r.bot.stopRacing();
    this.racers = [{ id: 1, name: 'You', time: -1, bot: null }];
    if (withBots) this.game.bots().forEach((b, i) => this.racers.push({ id: -(i + 1), name: `Bot ${i + 1}`, time: -1, bot: b }));
    this.racers.length = Math.min(this.racers.length, this.D.slots.length);
    this.racers.forEach((r, i) => {
      const s = this.D.slots[i], pos = v3(...s.pos);
      if (r.bot) { r.bot.cart.place(pos, s.yaw); r.bot.lineUp(); } else this.game.spawn(pos, s.yaw);
    });
    this.phase = COUNTDOWN; this.clock = this.D.countdown; this.sinceWinner = -1;
    this.lockAll(true);
    this.el.results.hidden = true;
  }

  cartOf(r) { return r.bot ? r.bot.cart : this.game.cart(); }
  lockAll(on) { for (const r of this.racers) this.cartOf(r).locked = on; }

  /** One physics step (before the carts step). */
  step(dt) {
    if (this.phase === COUNTDOWN) {
      this.lockAll(true);   // every step: a cart reset during the count is a new cart
      this.clock -= dt;
      if (this.clock <= 0) this._go();
    } else if (this.phase === RACING) {
      this.clock += dt;
      for (const r of this.racers) if (r.time < 0 && this._inFinish(this.cartOf(r))) this._finish(r);
      if (this.phase === RACING && this.sinceWinner >= 0 && (this.sinceWinner += dt) >= this.D.finish_grace) this._end();
    }
  }

  _go() {
    this.phase = RACING; this.clock = 0;
    this.lockAll(false);
    const way = [...this.D.route, this.D.bot_goal].map(p => v3(...p));
    for (const r of this.racers) if (r.bot) r.bot.raceTo(way);
  }

  _inFinish(cart) {
    const t = cart.frame.translation(), p = new THREE.Vector3(t.x, t.y, t.z).applyMatrix4(this.finishInv);
    return Math.abs(p.x) <= this.half.x && Math.abs(p.y) <= this.half.y && Math.abs(p.z) <= this.half.z;
  }

  _finish(r) {
    r.time = this.clock;
    if (this.sinceWinner < 0) this.sinceWinner = 0;
    if (this.racers.every(x => x.time >= 0)) this._end();
  }

  _end() {
    this.phase = DONE;
    this.lockAll(false);
    for (const r of this.racers) if (r.bot) r.bot.stopRacing();
    this._showResults();
  }

  /** Racers in finishing order: those over the line by time, then the rest. */
  results() {
    return this.racers.map(r => ({ id: r.id, name: r.name, time: r.time }))
      .sort((a, b) => (a.time >= 0) !== (b.time >= 0) ? (a.time >= 0 ? -1 : 1) : (a.time >= 0 ? a.time - b.time : 0));
  }

  _showResults() {
    const rows = this.results(), w = Math.max(6, ...rows.map(r => r.name.length + (r.id === 1 ? 2 : 0)));
    this.el.table.textContent = rows.map((r, i) => {
      const name = r.name + (r.id === 1 ? ' ◀' : '');
      return `${(r.time >= 0 ? ordinal(i + 1) : '—').padEnd(4)} ${name.padEnd(w + 2)}${r.time >= 0 ? formatTime(r.time) : 'DNF'}`;
    }).join('\n');
    this.el.results.hidden = false;
  }

  /** The race HUD, every frame (race_hud.gd). */
  draw() {
    const el = this.el;
    el.root.hidden = this.phase === IDLE;
    if (this.phase === IDLE) return;
    const me = this.racers[0];
    let count = '', t = 0, clock = this.clock, status = '';
    if (this.phase === COUNTDOWN) {
      const n = Math.ceil(this.clock);
      count = n > 0 ? String(n) : 'GO!'; t = n > 0 ? n - this.clock : 0; clock = 0;
      status = 'Get ready: race down to the exit';
    } else if (this.phase === RACING) {
      if (this.clock < this.D.go_hold) { count = 'GO!'; t = this.clock / this.D.go_hold; }
      const done = this.racers.filter(x => x.time >= 0).length;
      status = 'Race down to the exit';
      if (me.time >= 0) status = `You finished ${ordinal(this.racers.filter(x => x.time >= 0 && x.time <= me.time).length)} in ${formatTime(me.time)}`;
      else if (done > 0) status = `${done} over the line · ${Math.ceil(Math.max(this.D.finish_grace - this.sinceWinner, 0))} s left`;
    } else status = 'Race over';
    if (me.time >= 0) clock = me.time;
    el.clock.textContent = formatTime(clock);
    el.status.textContent = status;
    el.count.hidden = !count;
    el.count.textContent = count;
    el.count.classList.toggle('go', count === 'GO!');
    // Each number pops in big and shrinks to size over its first quarter second; GO! fades out at the end.
    el.count.style.transform = `translate(-50%, -50%) scale(${1.6 + (1 - 1.6) * Math.min(1, t * 4)})`;
    el.count.style.opacity = count === 'GO!' ? String(1 - Math.min(Math.max(t - 0.6, 0), 0.4) / 0.4) : '1';
  }
}
