// The cart's rolling sound: a port of scripts/cart/cart_rolling_sound.gd (Frame/RollingSound in
// scenes/cart/cart.tscn). Settings and loops come from levels/cart.json ("rolling_sound"); the loops are
// audio/roll_<surface>.wav, cut from zack's recordings by tools/audio/make_cart_rolling_loops.py.
// A ray down through the wheelbase finds the floor; its physics material (asphalt, tile, concrete) picks the loop,
// anything else plays the fallback. Volume and pitch follow the frame's speed along the floor.
import * as THREE from 'three';
import { v3, add, rot, dot, len, sub, scale, clamp, moveToward } from './util.js';

let audio = null;          // AudioContext, made on the first tap/click (browsers only allow sound after one)
const buffers = {};        // file -> AudioBuffer
const _fwd = new THREE.Vector3();

/** Call from a tap or click: creates (or resumes) the audio and loads the loops. */
export async function unlockAudio(rs) {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC || !rs) return;
  if (!audio) audio = new AC();
  if (audio.state === 'suspended') audio.resume().catch(() => {});
  await Promise.all(rs.sounds.map(async s => {
    if (buffers[s.file]) return;
    buffers[s.file] = 'loading';
    try { buffers[s.file] = await audio.decodeAudioData(await (await fetch(s.file)).arrayBuffer()); }
    catch (e) { console.warn('Rolling sound did not load', s.file, e); delete buffers[s.file]; }
  }));
}

/** The loops decoded so far (for the test). */
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

export class RollingSound {
  /** @param cart a Cart; @param rs cart.json's rolling_sound; @param surfaces level.surfaces (collider handle -> name) */
  constructor(cart, rs, surfaces) {
    this.cart = cart; this.rs = rs; this.surfaces = surfaces;
    this.probe = v3(rs.probe[9], rs.probe[10], rs.probe[11]);
    this.reach = len(v3(...rs.probe_target));
    this.down = scale(v3(...rs.probe_target), 1 / this.reach);
    this.sounds = rs.sounds.map(s => ({ ...s, gain: 0, src: null, out: null, pan: null }));
    this.fallback = this.sounds.find(s => s.name === rs.fallback) || null;
    this.speed = 0; this.surface = null;
  }

  /** Once per drawn frame, after the physics. `muted`: fade everything out (game paused). */
  update(dt, muted = false) {
    const { RAPIER, world } = this.cart.ctx, f = this.cart.frame, q = f.rotation(), rs = this.rs;
    const from = add(f.translation(), rot(q, this.probe)), dir = rot(q, this.down);
    const hit = world.castRayAndGetNormal(new RAPIER.Ray(from, dir), this.reach, true, undefined, (1 << 16) | 1);
    this.surface = null; this.speed = 0;
    if (hit) {
      const name = this.surfaces.get(hit.collider.handle);
      this.surface = this.sounds.find(s => s.floors.includes(name)) || this.fallback;
      const v = this.cart.pinned ? v3(0, 0, 0) : f.linvel(), n = hit.normal;
      this.speed = len(sub(v, scale(n, dot(v, n))));
    }
    const target = muted ? 0 : this.speed > rs.silent_speed ? Math.pow(clamp(this.speed / rs.full_volume_speed, 0, 1), rs.volume_curve) : 0;
    const pitch = clamp(1 + (this.speed - rs.recorded_speed) * rs.pitch_per_speed, rs.min_pitch, rs.max_pitch);
    const step = dt / rs.fade_time, pos = from;
    for (const s of this.sounds) {
      s.gain = moveToward(s.gain, s === this.surface ? target : 0, step);
      this._drive(s, pos, pitch);
    }
  }

  _drive(s, pos, pitch) {
    const buf = buffers[s.file];
    if (!audio || !(buf instanceof AudioBuffer)) return;
    if (s.gain > 0 && !s.src) {
      s.pan = new PannerNode(audio, { panningModel: 'equalpower', distanceModel: 'inverse', refDistance: s.unit_size,
        maxDistance: s.max_distance, rolloffFactor: 1 });
      s.out = new GainNode(audio, { gain: 0 });
      s.src = new AudioBufferSourceNode(audio, { buffer: buf, loop: true });
      s.src.connect(s.out).connect(s.pan).connect(audio.destination);
      s.src.start(0, Math.random() * buf.duration);   // carts side by side don't sound in step
    } else if (s.gain <= 0 && s.src) {
      this._stop(s);
      return;
    }
    if (!s.src) return;
    const t = audio.currentTime;
    s.out.gain.setTargetAtTime(dbToGain(s.loudness_db) * s.gain, t, 0.02);
    s.src.playbackRate.setTargetAtTime(pitch, t, 0.02);
    if (s.pan.positionX) { s.pan.positionX.setTargetAtTime(pos.x, t, 0.02); s.pan.positionY.setTargetAtTime(pos.y, t, 0.02); s.pan.positionZ.setTargetAtTime(pos.z, t, 0.02); }
    else s.pan.setPosition(pos.x, pos.y, pos.z);
  }

  _stop(s) {
    try { s.src.stop(); } catch (e) { /* already stopped */ }
    s.src.disconnect(); s.out.disconnect(); s.pan.disconnect();
    s.src = s.out = s.pan = null;
  }

  /** Silences it for good (the cart or the level is going away). */
  remove() { for (const s of this.sounds) { s.gain = 0; if (s.src) this._stop(s); } }

  /** Which loops are playing right now (for the test). */
  playing() { return this.sounds.filter(s => s.gain > 0).map(s => s.name); }
}
