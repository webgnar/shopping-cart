// The endless sandbox, as in Godot (shopping-cart/scripts/sandbox/chunk_streamer.gd): the ground is a grid of
// chunk_size squares, and the squares near the cart get a terrain chunk (levels/chunks/<name>.glb + .json, exported
// from scenes/sandbox/chunks/), built ahead of the cart and freed behind it. Which chunk, and which way it faces,
// comes from the same 32-bit hash of the square and the seed as in Godot, so both versions lay out the same world.
import * as THREE from 'three';
import { fetchLevel, buildLevel } from './level.js';
import { color } from './util.js';

/** lowbias32, as ChunkStreamer._mix. */
function mix(h) {
  h >>>= 0;
  h ^= h >>> 16; h = Math.imul(h, 0x7FEB352D) >>> 0;
  h ^= h >>> 15; h = Math.imul(h, 0x846CA68B) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}
export function cellHash(x, z, seed) {
  let h = ((seed & 0xFFFF) ^ 0x9E37) >>> 0;
  h = mix(h ^ (x >>> 0));
  h = mix(h ^ (z >>> 0));
  return h;
}

export class ChunkStreamer {
  /**
   * ctx: the level context (RAPIER, world, widen), level: what buildLevel returned for the sandbox (its lights,
   * props and surfaces are shared with the chunks), stream: the level JSON's "stream", base: the levels folder,
   * parent: the THREE group the chunks go in.
   */
  constructor(ctx, level, stream, base, parent, opts = {}) {
    Object.assign(this, { ctx, level, s: stream, base, parent, opts });
    this.origin = new THREE.Vector3(...stream.origin);
    this.size = stream.chunk_size;
    this.home = new Set(stream.home_cells.map(([i, j]) => `${i},${j}`));
    this.total = stream.weights.reduce((a, b) => a + b, 0);
    // Phones see a little less far (the fog hides it): fewer chunks to build and draw.
    this.loadDistance = stream.load_distance * (opts.reach ?? 1);
    this.unloadDistance = stream.unload_distance * (opts.reach ?? 1);
    this.loaded = new Map();      // "i,j" -> chunk {cell, root, fixed, props, lamps, handles}
    this.pending = new Map();     // chunk key -> Promise of its fetched data
    this.data = new Map();        // chunk key -> fetched {json, gltf}
    this.alive = true;
    const fg = stream.far_ground;
    if (fg) {
      this.far = new THREE.Mesh(new THREE.PlaneGeometry(fg.size, fg.size).rotateX(-Math.PI / 2),
        new THREE.MeshStandardMaterial({ color: color(fg.color), roughness: 0.95 }));
      this.far.position.y = fg.y; this.far.receiveShadow = true;
      parent.add(this.far);
    }
  }

  /** [chunk index, quarter turns] for square (i, j): ChunkStreamer.pick in Godot. */
  pick(i, j) {
    const h = cellHash(i, j, this.s.seed);
    let r = (h % 10000) / 10000 * this.total, idx = 0;
    for (let k = 0; k < this.s.weights.length; k++) { r -= this.s.weights[k]; idx = k; if (r < 0) break; }
    return [idx, this.s.turns === false ? 0 : (h >>> 20) & 3];
  }

  /** Same as Godot for every square of the exported check table. */
  selfCheck() {
    return this.s.check.every(([i, j, idx, turns]) => { const p = this.pick(i, j); return p[0] === idx && p[1] === turns; });
  }

  cellOf(p) { return [Math.floor((p.x - this.origin.x) / this.size), Math.floor((p.z - this.origin.z) / this.size)]; }

  distance(p, i, j) {
    const x0 = this.origin.x + i * this.size, z0 = this.origin.z + j * this.size;
    const dx = Math.max(x0 - p.x, p.x - (x0 + this.size), 0), dz = Math.max(z0 - p.z, p.z - (z0 + this.size), 0);
    return Math.hypot(dx, dz);
  }

  /** The squares to fill around `p`, nearest first. */
  wanted(p) {
    const [ci, cj] = this.cellOf(p), reach = Math.ceil(this.loadDistance / this.size), out = [];
    for (let i = ci - reach; i <= ci + reach; i++) for (let j = cj - reach; j <= cj + reach; j++) {
      const key = `${i},${j}`;
      if (this.loaded.has(key) || this.home.has(key)) continue;
      const d = this.distance(p, i, j);
      if (d < this.loadDistance) out.push([d, i, j]);
    }
    return out.sort((a, b) => a[0] - b[0]);
  }

  fetch(key) {
    if (!this.pending.has(key)) this.pending.set(key, fetchLevel(this.base, key).then(d => { this.data.set(key, d); return d; }));
    return this.pending.get(key);
  }

  /** Loads everything near `p` before going on (the start, or a jump). */
  async prime(p) {
    const w = this.wanted(p);
    await Promise.all(w.map(([, i, j]) => this.fetch(this.s.chunks[this.pick(i, j)[0]].key)));
    if (!this.alive) return;
    for (const [, i, j] of w) this.build(i, j);
  }

  /** Each frame: builds at most `budget` missing squares whose chunk has arrived, starts fetching the rest, frees far ones. */
  update(p, budget = 1) {
    for (const [, i, j] of this.wanted(p)) {
      const key = this.s.chunks[this.pick(i, j)[0]].key;
      if (!this.data.has(key)) { this.fetch(key); continue; }
      if (budget-- <= 0) break;
      this.build(i, j);
    }
    for (const [k, c] of this.loaded) if (this.distance(p, c.i, c.j) > this.unloadDistance) { this.free(c); this.loaded.delete(k); }
    if (this.far) this.far.position.set(Math.round(p.x / this.size) * this.size, this.far.position.y, Math.round(p.z / this.size) * this.size);
  }

  build(i, j) {
    const [idx, turns] = this.pick(i, j);
    const data = this.data.get(this.s.chunks[idx].key);
    const pose = new THREE.Matrix4().makeRotationY(turns * Math.PI / 2)
      .setPosition(this.origin.x + (i + 0.5) * this.size, this.origin.y, this.origin.z + (j + 0.5) * this.size);
    const root = new THREE.Group();
    root.matrixAutoUpdate = false; root.matrix.copy(pose);
    this.parent.add(root);
    const built = buildLevel(this.ctx, data, root, { pose, propRoot: this.parent, lights: this.level.lights,
      surfaces: this.level.surfaces, keepSource: true, noShadows: this.opts.noShadows });
    this.level.props.push(...built.props);
    this.loaded.set(`${i},${j}`, { i, j, root, fixed: built.fixed, props: built.props, lamps: built.ownLamps, handles: built.handles });
  }

  free(c) {
    const { world } = this.ctx;
    for (const pr of c.props) { world.removeRigidBody(pr.body); if (pr.node) pr.node.removeFromParent(); }
    const gone = new Set(c.props);
    this.level.props = this.level.props.filter(pr => !gone.has(pr));
    world.removeRigidBody(c.fixed);
    for (const h of c.handles) this.level.surfaces.delete(h);
    this.level.lights.remove(c.lamps);
    c.root.removeFromParent();
    // The merged meshes and labels are this chunk's own; the materials and textures are shared with the cached glTF.
    c.root.traverse(o => {
      if (o.geometry) o.geometry.dispose();
      if (o.userData.ownMaterial) { o.material.map?.dispose(); o.material.dispose(); }
    });
  }

  /** The level is going away (its world is freed with it): just stop. */
  dispose() {
    this.alive = false;
    if (this.far) { this.far.geometry.dispose(); this.far.material.dispose(); }
  }
}
