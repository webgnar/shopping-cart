// Small shared helpers: Rapier-style {x,y,z} vectors, Godot transforms and colours, collision groups.
import * as THREE from 'three';

export const v3 = (x, y, z) => ({ x, y, z });
export const add = (a, b) => v3(a.x + b.x, a.y + b.y, a.z + b.z);
export const sub = (a, b) => v3(a.x - b.x, a.y - b.y, a.z - b.z);
export const scale = (a, s) => v3(a.x * s, a.y * s, a.z * s);
export const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
export const cross = (a, b) => v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
export const len = a => Math.hypot(a.x, a.y, a.z);
export const norm = a => { const l = len(a) || 1; return v3(a.x / l, a.y / l, a.z / l); };
export const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
export const moveToward = (x, to, d) => (Math.abs(to - x) <= d ? to : x + Math.sign(to - x) * d);
export const arr = a => v3(a[0], a[1], a[2]);

const _q = new THREE.Quaternion(), _v = new THREE.Vector3();
/** Rotates vector a by quaternion q (both plain objects). */
export const rot = (q, a) => { _v.set(a.x, a.y, a.z).applyQuaternion(_q.set(q.x, q.y, q.z, q.w)); return v3(_v.x, _v.y, _v.z); };
export const qinv = q => ({ x: -q.x, y: -q.y, z: -q.z, w: q.w });

/** Godot transform as exported ([basis x, basis y, basis z, origin], 12 numbers) -> THREE.Matrix4. */
export function xfMatrix(a) {
  return new THREE.Matrix4().set(a[0], a[3], a[6], a[9], a[1], a[4], a[7], a[10], a[2], a[5], a[8], a[11], 0, 0, 0, 1);
}
/** -> {p: {x,y,z}, q: {x,y,z,w}} (scale dropped). */
export function xfPose(m) {
  const p = new THREE.Vector3(), q = new THREE.Quaternion(), s = new THREE.Vector3();
  m.decompose(p, q, s);
  return { p: v3(p.x, p.y, p.z), q: { x: q.x, y: q.y, z: q.z, w: q.w } };
}
/** Godot colours are sRGB. */
export const color = c => new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace);

export const bodyMatrix = b => {
  const t = b.translation(), r = b.rotation();
  return new THREE.Matrix4().compose(new THREE.Vector3(t.x, t.y, t.z), new THREE.Quaternion(r.x, r.y, r.z, r.w), new THREE.Vector3(1, 1, 1));
};

// ---------------------------------------------------------------- collision groups
// Godot layers 1 (world), 2 (carts) and 4 (cargo) keep their bits. Godot keeps a cart's own parts from touching
// each other with collision exceptions; here every cart gets its own bit (CART_BITS) instead, so parts of one
// cart never collide while different carts do. Godot collides two bodies when either one's mask has the other's
// layer; Rapier needs both, so each body's filter is widened with the layers of everything that wants to hit it.
export const CART_BITS = 0xfff0;
export const groups = (member, filter) => ((member & 0xffff) << 16) | (filter & 0xffff);
export function widenMask(layer, mask, all) {
  let m = mask;
  for (const [l, k] of all) if (k & layer) m |= l;
  return m;
}
/** Rapier groups for a Godot layer/mask; `own` = the cart's bit for cart parts (layer 2). `touchOwn`: this part
 *  also collides with the cart's other touchOwn parts (Godot's ShoppingCart.TOUCHING_PARTS). */
export function godotGroups(layer, mask, own = 0, touchOwn = false) {
  const expand = bits => (bits & 0xd) | ((bits & 2) ? (touchOwn ? CART_BITS : CART_BITS & ~own) : 0);
  const member = own && (layer & 2) ? own : (layer & 0xd);
  return groups(member, expand(mask));
}
