// The navigation mesh the bot carts drive on, and a NavigationAgent3D stand-in that follows a path over it.
// The mesh is the one baked in the Godot level (its NavigationRegion3D, assets/navigation/<level>.tres), exported
// into the level JSON by tools/mobile_level_export.gd. Paths: A* over the polygons, then the funnel (string
// pulling) through the shared edges, as Godot's navigation server does.

const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
// Twice the signed area of the triangle a, b, c seen from above (x, z), the sign convention of Recast's funnel.
const triArea2 = (a, b, c) => (c.x - a.x) * (b.z - a.z) - (b.x - a.x) * (c.z - a.z);
const same = (a, b) => Math.abs(a.x - b.x) < 1e-6 && Math.abs(a.z - b.z) < 1e-6;

export class NavMesh {
  constructor({ vertices, polygons }) {
    this.v = [];
    for (let i = 0; i < vertices.length; i += 3) this.v.push({ x: vertices[i], y: vertices[i + 1], z: vertices[i + 2] });
    this.polys = polygons.map(idx => {
      const pts = idx.map(i => this.v[i]);
      const c = { x: 0, y: 0, z: 0 };
      for (const p of pts) { c.x += p.x / pts.length; c.y += p.y / pts.length; c.z += p.z / pts.length; }
      let area = 0;
      for (let k = 1; k + 1 < pts.length; k++) area += Math.abs(triArea2(pts[0], pts[k], pts[k + 1])) / 2;
      return { idx, pts, c, area, links: [] };
    });
    // Neighbours share an edge (the same two vertices, or two vertices at the same spot).
    const key = p => `${Math.round(p.x * 100)},${Math.round(p.y * 20)},${Math.round(p.z * 100)}`;
    const edges = new Map();
    this.polys.forEach((poly, pi) => {
      for (let k = 0; k < poly.pts.length; k++) {
        const a = poly.pts[k], b = poly.pts[(k + 1) % poly.pts.length];
        const ka = key(a), kb = key(b), ek = ka < kb ? ka + '|' + kb : kb + '|' + ka;
        const other = edges.get(ek);
        if (other) {
          this.polys[other.pi].links.push({ to: pi, a: other.a, b: other.b });
          poly.links.push({ to: other.pi, a, b });
        } else edges.set(ek, { pi, a, b });
      }
    });
    this.totalArea = this.polys.reduce((s, p) => s + p.area, 0);
  }

  /** The closest point on polygon `pi` to p. */
  _closestOn(pi, p) {
    const pts = this.polys[pi].pts;
    // Inside (seen from above): the point on the polygon's surface (its triangle fan) under or over p.
    for (let k = 1; k + 1 < pts.length; k++) {
      const a = pts[0], b = pts[k], c = pts[k + 1];
      const d = triArea2(a, b, c);
      if (Math.abs(d) < 1e-9) continue;
      const u = triArea2(p, b, c) / d, v = triArea2(a, p, c) / d, w = 1 - u - v;
      if (u >= -1e-6 && v >= -1e-6 && w >= -1e-6) return { x: p.x, y: u * a.y + v * b.y + w * c.y, z: p.z };
    }
    // Outside: the closest point on its edges.
    let best = null, bd = Infinity;
    for (let k = 0; k < pts.length; k++) {
      const a = pts[k], b = pts[(k + 1) % pts.length];
      const ab = { x: b.x - a.x, y: b.y - a.y, z: b.z - a.z };
      const l2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z;
      const t = l2 > 0 ? Math.max(0, Math.min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y + (p.z - a.z) * ab.z) / l2)) : 0;
      const q = { x: a.x + ab.x * t, y: a.y + ab.y * t, z: a.z + ab.z * t };
      const dd = dist(p, q);
      if (dd < bd) { bd = dd; best = q; }
    }
    return best;
  }

  /** {point, poly}: the closest point on the mesh to p (NavigationServer3D.map_get_closest_point). */
  closest(p) {
    let best = null, bd = Infinity, bp = -1;
    for (let i = 0; i < this.polys.length; i++) {
      const q = this._closestOn(i, p), d = dist(p, q);
      if (d < bd) { bd = d; best = q; bp = i; }
    }
    return { point: best, poly: bp };
  }

  /** A random point anywhere on the mesh, every square metre as likely (map_get_random_point, uniformly). */
  randomPoint(rand = Math.random) {
    let r = rand() * this.totalArea, poly = this.polys[this.polys.length - 1];
    for (const p of this.polys) { if (r < p.area) { poly = p; break; } r -= p.area; }
    const pts = poly.pts;
    let tr = rand() * poly.area, k = 1;
    for (; k + 2 < pts.length; k++) { const a = Math.abs(triArea2(pts[0], pts[k], pts[k + 1])) / 2; if (tr < a) break; tr -= a; }
    let u = rand(), v = rand();
    if (u + v > 1) { u = 1 - u; v = 1 - v; }
    const a = pts[0], b = pts[k], c = pts[k + 1];
    return { x: a.x + (b.x - a.x) * u + (c.x - a.x) * v, y: a.y + (b.y - a.y) * u + (c.y - a.y) * v, z: a.z + (b.z - a.z) * u + (c.z - a.z) * v };
  }

  /** Path of points from `from` to `to` (map_get_path, optimized). When `to` can't be reached, the path ends at the
   *  reachable point closest to it, as Godot's does. */
  path(from, to) {
    const s = this.closest(from), e = this.closest(to);
    if (s.poly < 0 || e.poly < 0) return [];
    // A* over the polygons, each reached at the middle of the edge it was entered by.
    const n = this.polys.length, g = new Float64Array(n).fill(Infinity), prev = new Int32Array(n).fill(-1);
    const open = [s.poly], closed = new Uint8Array(n), at = new Array(n);
    g[s.poly] = 0; at[s.poly] = s.point;
    const h = i => dist(at[i], e.point);
    let goal = -1, nearest = s.poly, nearestD = h(s.poly);
    while (open.length) {
      let bi = 0;
      for (let i = 1; i < open.length; i++) if (g[open[i]] + h(open[i]) < g[open[bi]] + h(open[bi])) bi = i;
      const cur = open.splice(bi, 1)[0];
      if (closed[cur]) continue;
      closed[cur] = 1;
      if (h(cur) < nearestD) { nearestD = h(cur); nearest = cur; }
      if (cur === e.poly) { goal = cur; break; }
      for (const l of this.polys[cur].links) {
        if (closed[l.to]) continue;
        const mid = { x: (l.a.x + l.b.x) / 2, y: (l.a.y + l.b.y) / 2, z: (l.a.z + l.b.z) / 2 };
        const ng = g[cur] + dist(at[cur], mid);
        if (ng < g[l.to]) { g[l.to] = ng; prev[l.to] = cur; at[l.to] = mid; open.push(l.to); }
      }
    }
    let end = e.point;
    if (goal < 0) { goal = nearest; end = this._closestOn(goal, to); }
    const chain = [];
    for (let i = goal; i !== -1; i = prev[i]) chain.unshift(i);
    // Portals: the shared edge between each pair, as (left, right) for the funnel.
    const portals = [{ l: s.point, r: s.point }];
    for (let k = 0; k + 1 < chain.length; k++) {
      const link = this.polys[chain[k]].links.find(l => l.to === chain[k + 1]);
      const c = this.polys[chain[k]].c, m = { x: (link.a.x + link.b.x) / 2, z: (link.a.z + link.b.z) / 2 };
      const aLeft = triArea2(c, m, link.a) < 0;
      portals.push(aLeft ? { l: link.a, r: link.b } : { l: link.b, r: link.a });
    }
    portals.push({ l: end, r: end });
    return funnel(portals);
  }
}

/** The simple stupid funnel algorithm (Mikko Mononen): the shortest path through the portals. */
function funnel(portals) {
  const pts = [portals[0].l];
  let apex = portals[0].l, left = portals[0].l, right = portals[0].r, ai = 0, li = 0, ri = 0;
  for (let i = 1; i < portals.length; i++) {
    const pl = portals[i].l, pr = portals[i].r;
    if (triArea2(apex, right, pr) <= 0) {
      if (same(apex, right) || triArea2(apex, left, pr) > 0) { right = pr; ri = i; }
      else {
        pts.push(left); apex = left; ai = li; left = right = apex; li = ri = ai; i = ai; continue;
      }
    }
    if (triArea2(apex, left, pl) >= 0) {
      if (same(apex, left) || triArea2(apex, right, pl) < 0) { left = pl; li = i; }
      else {
        pts.push(right); apex = right; ai = ri; left = right = apex; li = ri = ai; i = ai; continue;
      }
    }
  }
  const last = portals[portals.length - 1].l;
  if (!same(pts[pts.length - 1], last)) pts.push(last);
  return pts.map(p => ({ x: p.x, y: p.y, z: p.z }));
}

/** What NavigationAgent3D does for the bot: holds a target, plans a path there and hands out the next point. */
export class NavAgent {
  constructor(mesh, { pathDesired = 1, targetDesired = 1, maxDistance = 5 } = {}) {
    this.mesh = mesh; this.pathDesired = pathDesired; this.targetDesired = targetDesired; this.maxDistance = maxDistance;
    this.target = { x: 0, y: 0, z: 0 }; this.pathPts = []; this.i = 0; this.finished = true; this.pos = null;
  }
  /** Sets the target (even the same one again) and plans a fresh path from where the agent is. */
  setTarget(t) { this.target = { ...t }; this.finished = false; this._plan(); }
  _plan() { this.pathPts = this.pos ? this.mesh.path(this.pos, this.target) : []; this.i = 0; }
  /** Moves the agent to `pos` (the bot's nav point) and steps along the path. */
  update(pos) {
    this.pos = pos;
    if (this.finished || !this.pathPts.length) return;
    // Wandered far off the path: plan again (path_max_distance).
    const seg = this.pathPts[Math.max(0, this.i - 1)], nxt = this.pathPts[this.i];
    if (seg && nxt && Math.min(dist(pos, seg), dist(pos, nxt)) > this.maxDistance + dist(seg, nxt)) this._plan();
    while (this.i < this.pathPts.length - 1 && dist(pos, this.pathPts[this.i]) < this.pathDesired) this.i++;
    const end = this.pathPts[this.pathPts.length - 1];
    if (this.i >= this.pathPts.length - 1 && dist(pos, end) < this.targetDesired) this.finished = true;
  }
  nextPosition() { return this.pathPts.length ? this.pathPts[this.i] : this.pos; }
  distanceToTarget() { return this.pos ? dist(this.pos, this.target) : 0; }
  isFinished() { return this.finished; }
}

export function pathLength(p) { let l = 0; for (let k = 1; k < p.length; k++) l += dist(p[k], p[k - 1]); return l; }
export { dist };
