"""A road from a few packed tiles, without repeats: corner tiles (Lagae 2007, ch. on corner tiles;
References/Asphalt/lagae_2007_tile_based_methods_thesis.pdf), packed with the stones of stone_packing.py.

    python3 corner_tiles.py <out_dir> [tile_mm]

Each lattice point of the road gets one of two corner colours at random; a tile is set by its four corner colours,
so 2^4 = 16 tiles cover every case and any colouring is a valid road (no edge matching to search). The stones are
shared between tiles by where their centre lies, and each shared part is packed once:
  - a corner patch per colour: centres within R of the lattice point (R = the largest stone's reach);
  - an edge strip per (end colour, end colour) and direction: centres within R of the edge, between the patches;
  - each tile's interior: the rest.
Size classes go largest first across the whole set (each class in every part, then the next), as in one packing.
Within a class, a part is packed after the parts it touches, checking every way they can meet (an edge strip against both colours
of the strips that share its end corners), so any assembly is free of overlaps. Each part fills its own region to
the mix's share by the stone volume actually inside it, stones spilling in from parts packed earlier included
(counting by stone centres instead left the seams thin and the interiors full: 36-38 % against 43 %); a class
stops when less than half a stone is left (no systematic overshoot).

Checks on a random 4 x 4 assembly: no point inside two stones; stone volume per tile and overall against the
mix's 38.1 %; Delesse on long cuts that cross the seams.
"""
import math, os, pickle, random, sys, time
from multiprocessing import Pool
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv, sys.argv = sys.argv, sys.argv[:1]
import stone_packing as sp
import surface_composition as mix
sys.argv = _argv

TILE = 100.0
DEPTH = sp.DEPTH
VOXEL = sp.VOXEL
CLASSES = mix.size_classes()
R_SEAM = 22.0       # mm: corner patch half-size and strip half-width. A stone reaching further is redrawn: 4.5 % of
                    # the 16-19 mm class (1 % of the aggregate) and 0.5 % of the 12.5-16 mm class, the most elongated
R = R_SEAM


# ---------------------------------------------------------------- packing a region against fixed stones

class Space:
    """Voxel map over a rectangle (non-periodic; outside counts as free): which size class fills each voxel (-1 free).
    It also measures each class's volume inside the part's own region, stones from neighbouring parts included."""
    def __init__(self, x0, y0, x1, y1, region):
        self.x0, self.y0 = x0, y0
        self.nx, self.ny = int(math.ceil((x1 - x0) / VOXEL)), int(math.ceil((y1 - y0) / VOXEL))
        self.nz = int(round(DEPTH / VOXEL))
        self.owner = np.full((self.nx, self.ny, self.nz), -1, dtype=np.int8)
        cx = self.x0 + (np.arange(self.nx) + 0.5) * VOXEL
        cy = self.y0 + (np.arange(self.ny) + 0.5) * VOXEL
        X, Y = np.meshgrid(cx, cy, indexing="ij")
        self.inreg = region(np.stack([X.ravel(), Y.ravel()], axis=1)).reshape(self.nx, self.ny)
        self.vox = VOXEL ** 3

    @property
    def free(self):
        return self.owner < 0

    def class_volume(self, cls):
        return np.count_nonzero((self.owner == cls) & self.inreg[:, :, None]) * self.vox

    def mark(self, v, nrm, faces, cls):
        lo, hi = v.min(axis=0), v.max(axis=0)
        ix = np.arange(max(0, int((lo[0] - self.x0) / VOXEL)), min(self.nx, int((hi[0] - self.x0) / VOXEL) + 1))
        iy = np.arange(max(0, int((lo[1] - self.y0) / VOXEL)), min(self.ny, int((hi[1] - self.y0) / VOXEL) + 1))
        iz = np.arange(max(0, int(-hi[2] / VOXEL)), min(self.nz, int(-lo[2] / VOXEL) + 1))
        if not len(ix) or not len(iy) or not len(iz):
            return
        X, Y, Z = np.meshgrid(self.x0 + (ix + 0.5) * VOXEL, self.y0 + (iy + 0.5) * VOXEL, -(iz + 0.5) * VOXEL, indexing="ij")
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
        ok = np.ones(len(P), dtype=bool)
        for (a, b, c), n in zip(faces, nrm):
            ok &= (P - v[a]) @ n <= 0
        I, J, K = np.meshgrid(ix, iy, iz, indexing="ij")
        I, J, K = I.ravel()[ok], J.ravel()[ok], K.ravel()[ok]
        new = self.owner[I, J, K] < 0
        self.owner[I[new], J[new], K[new]] = cls
        return np.count_nonzero(self.inreg[I[new], J[new]]) * self.vox

    def room(self, clearance, region):
        m = self.free.copy()
        m[:, :, 0] = False; m[:, :, -1] = False
        for _ in range(int(math.ceil(clearance / VOXEL))):
            p = np.pad(m, 1, constant_values=True)
            p[:, :, 0] = False; p[:, :, -1] = False
            m = m & p[2:, 1:-1, 1:-1] & p[:-2, 1:-1, 1:-1] & p[1:-1, 2:, 1:-1] & p[1:-1, :-2, 1:-1] & p[1:-1, 1:-1, 2:] & p[1:-1, 1:-1, :-2]
        idx = np.argwhere(m)
        xy = np.stack([self.x0 + (idx[:, 0] + 0.5) * VOXEL, self.y0 + (idx[:, 1] + 0.5) * VOXEL], axis=1)
        return idx[region(xy)]


class Placed:
    """A stone in place: vertices, face normals, edges, faces, centre, reach, class, volume."""
    def __init__(self, st, rot, pos):
        self.v, self.n, self.e = sp.placed(st, rot, pos)
        self.faces, self.c, self.r, self.cls, self.vol = st.faces, pos, st.r, st.cls, st.vol

    def moved(self, d):
        q = Placed.__new__(Placed)
        q.v, q.n, q.e, q.faces, q.c, q.r, q.cls, q.vol = self.v + d, self.n, self.e, self.faces, self.c + d, self.r, self.cls, self.vol
        return q


class Near:
    """Centres and reaches of a list of stones as arrays, so a candidate tests only the stones within reach."""
    def __init__(self, stones):
        self.s = list(stones)
        self.C = np.array([o.c for o in self.s]) if self.s else np.zeros((0, 3))
        self.R = np.array([o.r for o in self.s]) if self.s else np.zeros(0)

    def add(self, o):
        self.s.append(o)
        self.C = np.vstack([self.C, o.c]); self.R = np.append(self.R, o.r)

    def clear(self, A, r, c, skip=-1):
        if not len(self.s):
            return True
        near = np.nonzero(np.linalg.norm(self.C - c, axis=1) < self.R + r)[0]
        for i in near:
            if i != skip and sp.overlap(A, (self.s[i].v, self.s[i].n, self.s[i].e)):
                return False
        return True


def clear(A, r, c, others):
    return Near(others).clear(A, r, c)


def pack_region(seed, box, region, area, fixed, ci):
    """Stones of size class `ci` with centres where region(xy) is true (`area` mm2 of plan), against `fixed` stones
    (world coords: neighbouring parts and this part's larger classes). Classes go largest first across the whole
    set, as in one packing: packing a part to the end before its neighbour left the later part's large stones no
    room near the shared border, so they crowded into its middle."""
    rnd = random.Random(seed)
    space = Space(*box, region)
    for o in fixed:
        space.mark(o.v, o.n, o.faces, o.cls)
    target = mix.V_AGG * CLASSES[ci][3] * area * DEPTH
    got = space.class_volume(ci)              # what neighbouring parts already put here
    out = []
    near_fixed, near_out = Near(fixed), Near([])
    lo, hi = CLASSES[ci][0], CLASSES[ci][1]
    failed, cand, since = 0, None, 99
    while got < target and failed < sp.GIVE_UP:
        if since > 40:
            cand, since = space.room(0.35 * lo, region), 0
        if len(cand) == 0:
            break
        verts = None
        while verts is None:
            verts = sp.xu_stone(rnd, hi)
        st = sp.Stone(sp.sieve_scale(verts, lo * (hi / lo) ** rnd.random()), ci)
        if st.r > R:          # a stone reaching past the strips could cross a part it was not checked against
            continue
        if got + 0.5 * st.vol > target:      # less than half a stone left: stopping here is unbiased
            break
        done = False
        for _ in range(sp.TRIES):
            rot = sp.random_rotation(rnd)
            vz = st.v0 @ rot.T
            zlo, zhi = -DEPTH - vz[:, 2].min(), -vz[:, 2].max()
            if zlo > zhi:
                break
            i, j, k = cand[rnd.randrange(len(cand))]
            pos = np.array([box[0] + (i + rnd.random()) * VOXEL, box[1] + (j + rnd.random()) * VOXEL,
                            min(max(-(k + 0.5) * VOXEL, zlo), zhi)])
            if not region(pos[None, :2])[0]:
                continue
            A = sp.placed(st, rot, pos)
            if near_fixed.clear(A, st.r, pos) and near_out.clear(A, st.r, pos):
                p = Placed(st, rot, pos)
                out.append(p); near_out.add(p)
                got += space.mark(p.v, p.n, p.faces, ci); since += 1; done = True
                break
        failed = 0 if done else failed + 1
        since += 0 if done else 5
    return out


def press(own, fixed):
    """The roller, after every class is in: this part's stones near the surface turn onto a face and move up, where
    they fit among `fixed` (neighbouring parts, already pressed) and the part's own stones."""
    out = list(own)
    near_fixed, near_out = Near(fixed), Near(out)
    for i in sorted(range(len(out)), key=lambda i: -out[i].v[:, 2].max()):
        p = out[i]
        if -p.v[:, 2].max() > p.r:
            continue
        local = p.v - p.c
        st = sp.Stone.__new__(sp.Stone)
        st.v0, st.faces, st.r = local, p.faces, p.r
        F = np.array(p.faces); st.n0 = np.cross(local[F[:, 1]] - local[F[:, 0]], local[F[:, 2]] - local[F[:, 0]])
        E = np.array(sorted({tuple(sorted((f[a], f[(a + 1) % 3]))) for f in p.faces for a in range(3)}))
        st.e0 = local[E[:, 1]] - local[E[:, 0]]
        for rot in (sp.face_up(st, np.eye(3)), np.eye(3)):
            v = local @ rot.T
            new = np.array([p.c[0], p.c[1], -v[:, 2].max()])
            if -DEPTH - v[:, 2].min() > new[2]:
                continue
            A = (v + new, st.n0 @ rot.T, st.e0 @ rot.T)
            if near_fixed.clear(A, p.r, new) and near_out.clear(A, p.r, new, skip=i):
                q = Placed.__new__(Placed)
                q.v, q.n, q.e, q.faces, q.c, q.r, q.cls, q.vol = A[0], A[1], A[2], p.faces, new, p.r, p.cls, p.vol
                out[i] = q
                near_out.s[i] = q; near_out.C[i] = q.c
                break
    return out


# ---------------------------------------------------------------- the parts of a corner-tile set
# Each part: its region, its plan box (region plus the reach of its neighbours), and the neighbouring stones it is
# checked against, given the set so far (P: corner patches by colour; H, V: strips by end colours; T: interiors).

PATCH_REGION = lambda xy: (np.abs(xy[:, 0]) <= R) & (np.abs(xy[:, 1]) <= R)
H_REGION = lambda xy: (xy[:, 0] > R) & (xy[:, 0] < TILE - R) & (np.abs(xy[:, 1]) <= R)
V_REGION = lambda xy: (xy[:, 1] > R) & (xy[:, 1] < TILE - R) & (np.abs(xy[:, 0]) <= R)
T_REGION = lambda xy: (xy[:, 0] > R) & (xy[:, 0] < TILE - R) & (xy[:, 1] > R) & (xy[:, 1] < TILE - R)


def patch_nb(col, P, H, V, T):
    """Around a corner of colour `col`: the strips leaving it (east, north) and arriving (from west, south), both
    colours at their far ends, and every interior that has this corner (four positions)."""
    f = []
    for other in (0, 1):
        f += H[(col, other)] + [o.moved(np.array([-TILE, 0, 0.0])) for o in H[(other, col)]]
        f += V[(col, other)] + [o.moved(np.array([0, -TILE, 0.0])) for o in V[(other, col)]]
    for code, st in T.items():
        for k, (dx, dy) in enumerate(((0, 0), (-TILE, 0), (-TILE, -TILE), (0, -TILE))):   # this corner as bl, br, tr, tl
            if code[k] == col:
                f += [o.moved(np.array([dx, dy, 0.0])) for o in st]
    return f


def h_nb(a, b, P, H, V, T):
    f = list(P[a]) + [o.moved(np.array([TILE, 0, 0.0])) for o in P[b]]
    for cx, col in ((0.0, a), (TILE, b)):                       # vertical strips through its end corners
        for other in (0, 1):
            f += [o.moved(np.array([cx, 0, 0.0])) for o in V[(col, other)]]
            f += [o.moved(np.array([cx, -TILE, 0.0])) for o in V[(other, col)]]
    for code, st in T.items():                                  # interiors above (its bottom edge) and below (top)
        if (code[0], code[1]) == (a, b):
            f += st
        if (code[3], code[2]) == (a, b):
            f += [o.moved(np.array([0, -TILE, 0.0])) for o in st]
    return f


def v_nb(a, b, P, H, V, T):
    f = list(P[a]) + [o.moved(np.array([0, TILE, 0.0])) for o in P[b]]
    for cy, col in ((0.0, a), (TILE, b)):
        for other in (0, 1):
            f += [o.moved(np.array([0, cy, 0.0])) for o in H[(col, other)]]
            f += [o.moved(np.array([-TILE, cy, 0.0])) for o in H[(other, col)]]
    for code, st in T.items():                                  # interiors to the east (left edge) and west (right)
        if (code[0], code[3]) == (a, b):
            f += st
        if (code[1], code[2]) == (a, b):
            f += [o.moved(np.array([-TILE, 0, 0.0])) for o in st]
    return f


def tile_fixed(code, P, H, V):
    """The shared stones of tile `code` = (bottom-left, bottom-right, top-right, top-left) corner colours."""
    bl, br, tr, tl = code
    f = []
    for (x, y), col in (((0, 0), bl), ((TILE, 0), br), ((TILE, TILE), tr), ((0, TILE), tl)):
        f += [o.moved(np.array([x, y, 0.0])) for o in P[col]]
    f += [o.moved(np.array([0, 0, 0.0])) for o in H[(bl, br)]] + [o.moved(np.array([0, TILE, 0.0])) for o in H[(tl, tr)]]
    f += [o.moved(np.array([0, 0, 0.0])) for o in V[(bl, tl)]] + [o.moved(np.array([TILE, 0, 0.0])) for o in V[(br, tr)]]
    return f


def job(args):
    """One part, one size class (or the roller when ci is None)."""
    kind, key, ci, seed, own, nb = args
    box = {"P": (-2 * R, -2 * R, 2 * R, 2 * R), "H": (-R, -2 * R, TILE + R, 2 * R),
           "V": (-2 * R, -R, 2 * R, TILE + R), "T": (-R, -R, TILE + R, TILE + R)}[kind]
    region = {"P": PATCH_REGION, "H": H_REGION, "V": V_REGION, "T": T_REGION}[kind]
    area = {"P": (2 * R) ** 2, "H": (TILE - 2 * R) * 2 * R, "V": (TILE - 2 * R) * 2 * R, "T": (TILE - 2 * R) ** 2}[kind]
    if ci is None:
        return kind, key, press(own, nb)
    return kind, key, own + pack_region(seed, box, region, area, nb + own, ci)


# ---------------------------------------------------------------- assembly and checks

def assemble(n, tiles, P, H, V, seed=11):
    """A random n x n road: corner colours at the (n+1)^2 lattice points; each part placed once."""
    rnd = random.Random(seed)
    col = [[rnd.randrange(2) for _ in range(n + 1)] for _ in range(n + 1)]
    out = []
    for i in range(n + 1):
        for j in range(n + 1):
            out += [o.moved(np.array([i * TILE, j * TILE, 0.0])) for o in P[col[i][j]]]
    for i in range(n):
        for j in range(n + 1):
            out += [o.moved(np.array([i * TILE, j * TILE, 0.0])) for o in H[(col[i][j], col[i + 1][j])]]
    for i in range(n + 1):
        for j in range(n):
            out += [o.moved(np.array([i * TILE, j * TILE, 0.0])) for o in V[(col[i][j], col[i][j + 1])]]
    for i in range(n):
        for j in range(n):
            code = (col[i][j], col[i + 1][j], col[i + 1][j + 1], col[i][j + 1])
            out += [o.moved(np.array([i * TILE, j * TILE, 0.0])) for o in tiles[code]]
    return out, col


def inside_counts(stones, P, cell=5.0):
    """How many stones each point is inside; points binned on a plan grid so each stone tests only its own cells."""
    cnt = np.zeros(len(P), int)
    ci = np.floor(P[:, :2] / cell).astype(int)
    key = ci[:, 0] * 100000 + ci[:, 1]
    order = np.argsort(key, kind="stable")
    ks = key[order]
    for o in stones:
        lo, hi = o.v.min(axis=0), o.v.max(axis=0)
        cand = []
        for gx in range(int(math.floor(lo[0] / cell)), int(math.floor(hi[0] / cell)) + 1):
            for gy in range(int(math.floor(lo[1] / cell)), int(math.floor(hi[1] / cell)) + 1):
                k = gx * 100000 + gy
                a, b = np.searchsorted(ks, k), np.searchsorted(ks, k, side="right")
                if b > a:
                    cand.append(order[a:b])
        if not cand:
            continue
        idx = np.concatenate(cand)
        Q = P[idx]
        m = np.all((Q >= lo) & (Q <= hi), axis=1)
        idx, Q = idx[m], Q[m]
        ok = np.ones(len(idx), bool)
        for (a, b, c), nn in zip(o.faces, o.n):
            ok &= (Q - o.v[a]) @ nn <= 0
        cnt[idx[ok]] += 1
    return cnt


if __name__ == "__main__":
    out = sys.argv[1]
    if len(sys.argv) > 2:
        TILE = float(sys.argv[2])
    os.makedirs(out, exist_ok=True)
    rnd = random.Random(3)
    reach = sorted(sp.Stone(sp.sieve_scale(v, CLASSES[0][1]), 0).r for v in
                   [v for v in (sp.xu_stone(rnd, CLASSES[0][1]) for _ in range(2000)) if v is not None])
    R = R_SEAM
    print("Tile %.0f mm; 19 mm stones' reach: median %.1f, max %.1f mm; seams R = %.1f mm (%.1f %% of those stones,"
          " the most elongated, are redrawn)" % (TILE, reach[len(reach) // 2], reach[-1], R, 100 * np.mean(np.array(reach) > R)))
    t0 = time.time()
    keys = [(a, b) for a in (0, 1) for b in (0, 1)]
    codes = [(a, b, c, d) for a in (0, 1) for b in (0, 1) for c in (0, 1) for d in (0, 1)]
    P = {0: [], 1: []}; H = {k: [] for k in keys}; V = {k: [] for k in keys}; tiles = {c: [] for c in codes}
    stores = {"P": P, "H": H, "V": V, "T": tiles}
    with Pool(4) as pool:
        for ci in list(range(len(CLASSES))) + [None]:          # largest class first everywhere; then the roller
            stages = [("P", list(P), lambda k: patch_nb(k, P, H, V, tiles)),
                      ("H", keys, lambda k: h_nb(*k, P, H, V, tiles)),
                      ("V", keys, lambda k: v_nb(*k, P, H, V, tiles)),
                      ("T", codes, lambda k: tile_fixed(k, P, H, V))]
            for si, (kind, ks, nb) in enumerate(stages):
                args = [(kind, k, ci, 1000 * (ci if ci is not None else 9) + 100 * si + i, stores[kind][k], nb(k))
                        for i, k in enumerate(ks)]
                for kind_, k, st in pool.map(job, args):
                    stores[kind_][k] = st
            print("  %s: %d stones so far (%.0f s)" % ("class %.2f-%.2f mm" % CLASSES[ci][:2] if ci is not None else "roller",
                  sum(len(x) for st in stores.values() for x in st.values()), time.time() - t0))
    print("  2 corner patches %d, 8 strips %d, 16 interiors %d stones" % (sum(len(x) for x in P.values()),
          sum(len(x) for x in H.values()) + sum(len(x) for x in V.values()), sum(len(x) for x in tiles.values())))
    with open(os.path.join(out, "corner_tiles.pkl"), "wb") as f:
        pickle.dump({"tile": TILE, "depth": DEPTH, "R": R, "P": P, "H": H, "V": V, "tiles": tiles}, f)

    n = 4
    road, col = assemble(n, tiles, P, H, V)
    L = n * TILE
    print("Assembly: %d x %d tiles (%.0f x %.0f mm), corner colours:" % (n, n, L, L))
    for j in reversed(range(n + 1)):
        print("   " + " ".join(str(col[i][j]) for i in range(n + 1)))
    pts = np.random.RandomState(5).uniform([0, 0, -DEPTH], [L, L, 0], size=(400000, 3))
    cnt = inside_counts(road, pts)
    print("  points inside a stone %.1f %% (mix 38.1 %%), inside two: %d of %d" % (100 * np.mean(cnt >= 1), int(np.sum(cnt >= 2)), len(pts)))
    per = []
    for i in range(n):
        for j in range(n):
            m = (pts[:, 0] // TILE == i) & (pts[:, 1] // TILE == j)
            per.append(np.mean(cnt[m] >= 1))
    print("  per tile: %.1f-%.1f %%, mean %.1f %%" % (100 * min(per), 100 * max(per), 100 * np.mean(per)))
    for y in (0.0, 0.5 * TILE, 1.0 * TILE):    # a cut along a seam, through interiors, along the next seam
        g = np.stack(np.meshgrid(np.arange(0.25, L, 0.5), [y + 0.01], -np.arange(0.25, DEPTH, 0.5), indexing="ij"), -1).reshape(-1, 3)
        c = inside_counts(road, g)
        print("  vertical cut %.0f mm long at y = %.0f mm: %.1f %% stone, %d points in two stones" % (L, y, 100 * np.mean(c >= 1), int(np.sum(c >= 2))))
        if y == 0.5 * TILE:
            from PIL import Image
            img = np.where(c.reshape(len(np.arange(0.25, L, 0.5)), -1) >= 1, 170, 30).astype(np.uint8)
            for k in range(1, n):
                img[int(k * TILE / 0.5), :] = 255           # tile seams marked white
            Image.fromarray(img.T).resize((1600, int(1600 * DEPTH / L)), Image.NEAREST).save(os.path.join(out, "road_section.png"))
    print("Done in %.0f s" % (time.time() - t0))
