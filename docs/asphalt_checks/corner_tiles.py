"""A road from a few packed tiles, without repeats: corner tiles (Lagae 2007, ch. on corner tiles;
References/Asphalt/lagae_2007_tile_based_methods_thesis.pdf), packed with the stones of stone_packing.py.

    python3 corner_tiles.py <out_dir> [tile_mm]

Each lattice point of the road gets one of two corner colours at random; a tile is set by its four corner colours,
so 2^4 = 16 tiles cover every case and any colouring is a valid road (no edge matching to search). The stones are
shared between tiles by where their centre lies, and each shared part is packed once:
  - a corner patch per colour: centres within R of the lattice point (R = the largest stone's reach);
  - an edge strip per (end colour, end colour) and direction: centres within R of the edge, between the patches;
  - each tile's interior: the rest.
A part is packed after the parts it touches, checking every way they can meet (an edge strip against both colours
of the strips that share its end corners), so any assembly is free of overlaps. The parts tile the plane, so
each holds its share of the mix's stone volume.

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
    """Voxel map of free space over a rectangle (non-periodic); outside the rectangle counts as free."""
    def __init__(self, x0, y0, x1, y1):
        self.x0, self.y0 = x0, y0
        self.nx, self.ny = int(math.ceil((x1 - x0) / VOXEL)), int(math.ceil((y1 - y0) / VOXEL))
        self.nz = int(round(DEPTH / VOXEL))
        self.free = np.ones((self.nx, self.ny, self.nz), dtype=bool)

    def mark(self, v, nrm, faces):
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
        self.free[I.ravel()[ok], J.ravel()[ok], K.ravel()[ok]] = False

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


def pack_region(seed, box, region, area, fixed):
    """Stones with centres where region(xy) is true, `area` mm2 of plan, against `fixed` stones (world coords)."""
    rnd = random.Random(seed)
    space = Space(*box)
    for o in fixed:
        space.mark(o.v, o.n, o.faces)
    target = [mix.V_AGG * c[3] * area * DEPTH for c in CLASSES]
    got = [0.0] * len(CLASSES)
    out = []
    near_fixed, near_out = Near(fixed), Near([])
    for ci in range(len(CLASSES)):
        failed, cand, since = 0, None, 99
        while got[ci] < target[ci] and failed < sp.GIVE_UP:
            lo, hi = CLASSES[ci][0], CLASSES[ci][1]
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
                    out.append(p); near_out.add(p); space.mark(p.v, p.n, p.faces)
                    got[ci] += st.vol; since += 1; done = True
                    break
            failed = 0 if done else failed + 1
            since += 0 if done else 5
    # the roller: stones of this part near the surface turn onto a face and move up, where they fit
    for i in sorted(range(len(out)), key=lambda i: -out[i].v[:, 2].max()):
        p = out[i]
        if -p.v[:, 2].max() > p.r:
            continue
        # recover the stone's rotation-free shape: vertices relative to centre
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

def corner_patch(seed):
    region = lambda xy: (np.abs(xy[:, 0]) <= R) & (np.abs(xy[:, 1]) <= R)
    return pack_region(seed, (-2 * R, -2 * R, 2 * R, 2 * R), region, (2 * R) ** 2, [])


def h_strip(args):
    """Edge along x from corner (0, 0) of colour a to (TILE, 0) of colour b; centres R < x < TILE - R, |y| <= R."""
    seed, a, b, P = args
    fixed = [o for o in P[a]] + [o.moved(np.array([TILE, 0, 0])) for o in P[b]]
    region = lambda xy: (xy[:, 0] > R) & (xy[:, 0] < TILE - R) & (np.abs(xy[:, 1]) <= R)
    return pack_region(seed, (-R, -2 * R, TILE + R, 2 * R), region, (TILE - 2 * R) * 2 * R, fixed)


def v_strip(args):
    """Edge along y from corner (0, 0) of colour a to (0, TILE) of colour b, against the corner patches and every
    horizontal strip that can end at either corner (both colours on the far side, west and east)."""
    seed, a, b, P, H = args
    fixed = [o for o in P[a]] + [o.moved(np.array([0, TILE, 0])) for o in P[b]]
    for cy, col in ((0.0, a), (TILE, b)):
        for other in (0, 1):
            fixed += [o.moved(np.array([0, cy, 0])) for o in H[(col, other)]]                 # strip going east
            fixed += [o.moved(np.array([-TILE, cy, 0])) for o in H[(other, col)]]             # strip coming from west
    region = lambda xy: (xy[:, 1] > R) & (xy[:, 1] < TILE - R) & (np.abs(xy[:, 0]) <= R)
    return pack_region(seed, (-2 * R, -R, 2 * R, TILE + R), region, (TILE - 2 * R) * 2 * R, fixed)


def tile_fixed(code, P, H, V):
    """The shared stones of tile `code` = (bottom-left, bottom-right, top-right, top-left) corner colours."""
    bl, br, tr, tl = code
    f = []
    for (x, y), col in (((0, 0), bl), ((TILE, 0), br), ((TILE, TILE), tr), ((0, TILE), tl)):
        f += [o.moved(np.array([x, y, 0.0])) for o in P[col]]
    f += [o.moved(np.array([0, 0, 0.0])) for o in H[(bl, br)]] + [o.moved(np.array([0, TILE, 0.0])) for o in H[(tl, tr)]]
    f += [o.moved(np.array([0, 0, 0.0])) for o in V[(bl, tl)]] + [o.moved(np.array([TILE, 0, 0.0])) for o in V[(br, tr)]]
    return f


def interior(args):
    seed, code, fixed = args
    region = lambda xy: (xy[:, 0] > R) & (xy[:, 0] < TILE - R) & (xy[:, 1] > R) & (xy[:, 1] < TILE - R)
    return code, pack_region(seed, (-R, -R, TILE + R, TILE + R), region, (TILE - 2 * R) ** 2, fixed)


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
    with Pool(4) as pool:
        P = dict(enumerate(pool.map(corner_patch, [101, 202])))
        print("  2 corner patches: %d stones (%.0f s)" % (sum(len(p) for p in P.values()), time.time() - t0))
        pickle.dump(P, open(os.path.join(out, "stage_P.pkl"), "wb"))
        keys = [(a, b) for a in (0, 1) for b in (0, 1)]
        H = dict(zip(keys, pool.map(h_strip, [(300 + i, a, b, P) for i, (a, b) in enumerate(keys)])))
        print("  4 horizontal strips: %d stones (%.0f s)" % (sum(len(h) for h in H.values()), time.time() - t0))
        pickle.dump(H, open(os.path.join(out, "stage_H.pkl"), "wb"))
        V = dict(zip(keys, pool.map(v_strip, [(400 + i, a, b, P, H) for i, (a, b) in enumerate(keys)])))
        print("  4 vertical strips: %d stones (%.0f s)" % (sum(len(v) for v in V.values()), time.time() - t0))
        pickle.dump(V, open(os.path.join(out, "stage_V.pkl"), "wb"))
        codes = [(a, b, c, d) for a in (0, 1) for b in (0, 1) for c in (0, 1) for d in (0, 1)]
        res = pool.map(interior, [(500 + i, code, tile_fixed(code, P, H, V)) for i, code in enumerate(codes)])
    tiles = dict(res)
    print("  16 interiors: %d stones (%.0f s)" % (sum(len(t) for t in tiles.values()), time.time() - t0))
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
