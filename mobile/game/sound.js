// The cart's wheel sounds: a port of scripts/cart/wheel_sound.gd (scenes/cart/wheel_sound.tscn, one under each
// wheel of scenes/cart/cart.tscn). Settings and files come from levels/cart.json ("wheel_sound"); the sounds are
// audio/*.wav, cut from zack's recordings by tools/audio/make_cart_rolling_loops.py.
// Each wheel, from its own physics: rolls (the loop for the floor under it, volume and pitch from its own spin),
// scrubs (sliding along its axle, or skidding), lands (set back down after being off the ground) and knocks
// (jolted upward while on the ground).
import * as THREE from 'three';
import { v3, rot, dot, len, sub, scale, cross, norm, clamp, moveToward } from './util.js';

let audio = null;          // AudioContext, made on the first tap/click (browsers only allow sound after one)
const buffers = {};        // file -> AudioBuffer
const _fwd = new THREE.Vector3();

function files(ws) {
  return [...new Set([...ws.floors.flatMap(f => [f.roll, f.scrub]), ...ws.knock.files, ...ws.land.files])];
}

/** Call from a tap or click: creates (or resumes) the audio and loads the sounds. */
export async function unlockAudio(ws) {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC || !ws) return;
  if (!audio) audio = new AC();
  if (audio.state === 'suspended') audio.resume().catch(() => {});
  await Promise.all(files(ws).map(async f => {
    if (buffers[f]) return;
    buffers[f] = 'loading';
    try { buffers[f] = await audio.decodeAudioData(await (await fetch(f)).arrayBuffer()); }
    catch (e) { console.warn('Cart sound did not load', f, e); delete buffers[f]; }
  }));
}

/** The AudioContext, once a tap has allowed sound (else null). music.js plays through it too. */
export const audioContext = () => audio;

/** The sounds decoded so far (for the test). */
export const loadedLoops = () => Object.keys(buffers).filter(k => buffers[k] instanceof AudioBuffer);

/** Places the listener at the camera (a THREE.PerspectiveCamera). */
export function updateListener(camera) {
  if (!audio) return;
  const l = audio.listener, p = camera.position, f = camera.getWorldDirection(_fwd), u = camera.up;
  if (l.positionX) {
    const t = audio.currentTime;
    l.positionX.setTargetAtTime(p.x, t, 0.02); l.positionY.setTargetAtTime(p.y, t, 0.02); l.positionZ.setTargetAtTime(p.z, t, 0.02);
    l.forwardX.setTargetAtTime(f.x, t, 0.02); l.forwardY.setTargetAtTime(f.y, t, 0.02); l.forwardZ.setTargetAtTime(f.z, t, 0.02);
    l.upX.setTargetAtTime(u.x, t, 0.02); l.upY.setTargetAtTime(u.y, t, 0.02); l.upZ.setTargetAtTime(u.z, t, 0.02);
  } else {
    l.setPosition(p.x, p.y, p.z); l.setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
  }
}

const dbToGain = db => Math.pow(10, db / 20);
const ready = f => audio && buffers[f] instanceof AudioBuffer;

function panner(ws) {
  return new PannerNode(audio, { panningModel: 'equalpower', distanceModel: 'inverse', refDistance: ws.unit_size,
    maxDistance: ws.max_distance, rolloffFactor: 1 });
}
function place(pan, p) {
  const t = audio.currentTime;
  if (pan.positionX) { pan.positionX.setTargetAtTime(p.x, t, 0.02); pan.positionY.setTargetAtTime(p.y, t, 0.02); pan.positionZ.setTargetAtTime(p.z, t, 0.02); }
  else pan.setPosition(p.x, p.y, p.z);
}

/** One looping voice (a wheel's roll or scrub): plays while its gain is above zero. */
class Loop {
  constructor(ws) { this.ws = ws; this.gain = 0; this.floor = null; this.src = null; }
  apply(file, db, pitch, pos, muted) {
    const g = muted ? 0 : this.gain;
    if (g > 0 && !this.src && ready(file)) {
      const buf = buffers[file];
      this.pan = panner(this.ws); this.out = new GainNode(audio, { gain: 0 });
      this.src = new AudioBufferSourceNode(audio, { buffer: buf, loop: true });
      this.src.connect(this.out).connect(this.pan).connect(audio.destination);
      this.src.start(0, Math.random() * buf.duration);   // each wheel starts somewhere else in the loop
      this.file = file;
    } else if ((g <= 0 || file !== this.file) && this.src) { this.stop(); return; }
    if (!this.src) return;
    const t = audio.currentTime;
    this.out.gain.setTargetAtTime(dbToGain(db) * g, t, 0.02);
    this.src.playbackRate.setTargetAtTime(pitch, t, 0.02);
    place(this.pan, pos);
  }
  stop() {
    if (!this.src) return;
    try { this.src.stop(); } catch (e) { /* already stopped */ }
    this.src.disconnect(); this.out.disconnect(); this.pan.disconnect();
    this.src = this.out = this.pan = null;
  }
}

/** Plays one of `shot.files` once at `pos`, `db` loud, at a random pitch within random_pitch. */
function oneShot(ws, shot, db, pos) {
  const f = shot.files[Math.floor(Math.random() * shot.files.length)];
  if (!ready(f)) return;
  const r = shot.random_pitch, rate = Math.pow(r, Math.random() * 2 - 1);
  const pan = panner(ws), out = new GainNode(audio, { gain: dbToGain(db) });
  const src = new AudioBufferSourceNode(audio, { buffer: buffers[f], playbackRate: rate });
  src.connect(out).connect(pan).connect(audio.destination);
  place(pan, pos);
  src.onended = () => { src.disconnect(); out.disconnect(); pan.disconnect(); };
  src.start();
}

/** One wheel's sound state, as WheelSound in Godot. */
class Wheel {
  constructor(ws, body) {
    this.ws = ws; this.body = body;
    this.roll = new Loop(ws); this.scrub = new Loop(ws);
    this.grounded = false; this.floor = null; this.rollSpeed = 0; this.slide = 0;
    this.knocks = 0; this.landings = 0;
    this.prevVy = 0; this.sinceKnock = 1; this.airTime = 0; this.fallSpeed = 0;
  }
}

export class WheelSounds {
  /** @param cart a Cart; @param ws cart.json's wheel_sound; @param surfaces level.surfaces (collider handle -> name) */
  constructor(cart, ws, surfaces) {
    this.cart = cart; this.ws = ws; this.surfaces = surfaces;
    this.fallback = ws.floors.find(f => f.name === ws.fallback) || null;
    this.wheels = {};
    for (const k of Object.keys(cart.wheels)) this.wheels[k] = new Wheel(ws, cart.wheels[k]);
    this.muted = false;
  }

  /** Once per physics step: reads each wheel's motion and contact, sets the gains, fires landings and knocks. */
  tick(dt) {
    const ws = this.ws, r = this.cart.wheelRadius;
    for (const w of Object.values(this.wheels)) {
      const b = w.body, v = b.linvel(), q = b.rotation();
      const hit = this.cart._groundHit(b, ws.contact_gap);
      w.grounded = !!hit; w.floor = null; w.rollSpeed = 0; w.slide = 0;
      if (hit) {
        const name = this.surfaces.get(hit.collider.handle);
        w.floor = ws.floors.find(f => f.floors.includes(name)) || this.fallback;
        const n = hit.normal, axle = norm(rot(q, v3(0, 0, 1)));
        let side = sub(axle, scale(n, dot(axle, n)));
        if (len(side) > 0.1) {   // a wheel lying flat has no axle along the ground
          side = norm(side);
          const ahead = norm(cross(side, n)), vg = sub(v, scale(n, dot(v, n)));
          w.rollSpeed = Math.abs(dot(b.angvel(), axle)) * r;
          const over = Math.abs(dot(vg, ahead)), sideways = dot(vg, side);
          const skid = Math.max(0, Math.abs(over - w.rollSpeed) - ws.skid_tolerance * Math.max(over, w.rollSpeed));
          w.slide = Math.hypot(sideways, skid);
        }
      }
      // Landing: back on the ground after a moment in the air. Knock: jolted upward while on the ground.
      w.sinceKnock += dt;
      const jolt = v.y - w.prevVy; w.prevVy = v.y;
      const at = b.translation();
      if (!w.grounded) { w.airTime += dt; w.fallSpeed = -v.y; }
      else {
        if (w.airTime >= ws.land_air_time) {
          if (w.fallSpeed > ws.land_start && w.sinceKnock >= ws.knock_gap) {
            w.sinceKnock = 0; w.landings++;
            if (!this.muted) oneShot(ws, ws.land, ws.land_db + 20 * Math.log10(clamp((w.fallSpeed - ws.land_start) / (ws.land_full - ws.land_start), 0.15, 1)), at);
          }
        } else if (jolt > ws.knock_start && w.sinceKnock >= ws.knock_gap) {
          w.sinceKnock = 0; w.knocks++;
          if (!this.muted) oneShot(ws, ws.knock, ws.knock_db + 20 * Math.log10(clamp((jolt - ws.knock_start) / (ws.knock_full - ws.knock_start), 0.1, 1)), at);
        }
        w.airTime = 0;
      }
      const step = dt / ws.fade_time;
      const rollT = w.rollSpeed > ws.silent_speed ? Math.pow(clamp(w.rollSpeed / ws.full_volume_speed, 0, 1), ws.volume_curve) : 0;
      const scrubT = clamp((w.slide - ws.scrub_start) / (ws.scrub_full - ws.scrub_start), 0, 1);
      this._drive(w.roll, w.floor, rollT, step);
      this._drive(w.scrub, w.floor, scrubT, step);
    }
  }

  // A new floor fades the old loop out first, then swaps.
  _drive(loop, floor, target, step) {
    if (floor && floor !== loop.floor) {
      if (loop.gain > 0) target = 0;
      else loop.floor = floor;
    }
    loop.gain = loop.floor ? moveToward(loop.gain, target, step) : 0;
  }

  /** Once per drawn frame: pushes the gains and pitches to the audio. `muted`: the game is paused. */
  update(dt, muted = false) {
    this.muted = muted;
    if (!audio) return;
    const ws = this.ws;
    for (const w of Object.values(this.wheels)) {
      const pos = w.body.translation();
      const pitch = clamp(1 + (w.rollSpeed - ws.recorded_speed) * ws.pitch_per_speed, ws.min_pitch, ws.max_pitch);
      const sp = clamp(ws.scrub_pitch_low + (w.slide - ws.scrub_start) * ws.scrub_pitch_per_speed, ws.scrub_pitch_low, ws.scrub_max_pitch);
      const rf = w.roll.floor, sf = w.scrub.floor;
      if (rf) w.roll.apply(rf.roll, rf.roll_db + ws.wheel_db, pitch, pos, muted);
      if (sf) w.scrub.apply(sf.scrub, sf.scrub_db + ws.wheel_db, sp, pos, muted);
    }
  }

  /** Silences it for good (the cart or the level is going away). */
  remove() { for (const w of Object.values(this.wheels)) { w.roll.gain = w.scrub.gain = 0; w.roll.stop(); w.scrub.stop(); } }

  /** Which loops are sounding right now, as "RL roll" (for the test). */
  playing() {
    const out = [];
    for (const [k, w] of Object.entries(this.wheels)) {
      if (w.roll.gain > 0) out.push(k + ' roll');
      if (w.scrub.gain > 0) out.push(k + ' scrub');
    }
    return out;
  }
}
