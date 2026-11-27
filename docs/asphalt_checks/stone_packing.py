"""Stone packing prototype (ASPHALT_SCIENCE.md, Model 1b; roadmap T2 step 6b).

Packs the stones of a measured mix into a tile of the wear course and checks the result against the mix data.

    python3 stone_packing.py [out_dir]      (out_dir: optional PNGs of the plan, a section and the height map)

Method:
  - Stones: Xu et al. 2010 (J. Mechanics 26(2), References/Asphalt/xu_2010_3d_aggregate_generation_packing.pdf):
    a random acute triangle in a circle of the stone's size, extended point by point into a convex polyhedron
    (eq. 1: each new point on the outer side of the face it extends), at most 10 faces, sharpness S = Lmax / Lmin
    of its edges at most 5 (eq. 2; Superpave's flat-and-elongated limit is also 5:1). Scaled so its intermediate
    dimension is its sieve size, drawn log-uniform between the two sieves of its class.
  - Packing: Xu's order, largest first; each stone tries random positions and orientations; if none fits, a
    smaller stone is tried at that turn (Xu section 3). Positions are proposed only where a voxel map of the free
    space, shrunk by the stone's half size, says there is room (like the sim's cell grids); the exact
    separating-axis test still decides, so this changes the speed, not the result. No physics: the mix's stones fill only 38 % of the volume
    (cell 18), below any settled packing (~55-60 %), so they sit apart in the mastic.
  - Tile: periodic in x and y, bounded by the roller above (z = 0) and the lift below.
  - The roller: stones near the surface turn onto their most upward face and are pushed up against it, where they
    fit (a convex body pressed by a flat plate rests on a face).

Checks: the stone volume against the mix's (38.1 %); Delesse's principle on a horizontal and a vertical cut;
the stone counts per class against the mix; the mean profile depth of the surface against FHWA-HRT-25-100
(0.35 mm) and Virginia's measured 0.39-0.49 mm (VTRC 23-R15).
"""
import math, os, random, sys, time
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv, sys.argv = sys.argv, sys.argv[:1]
import surface_composition as mix   # MnROAD cell 18 wear course: gradation, volumetrics
sys.argv = _argv

TILE = 100.0          # mm, x and y (periodic)
DEPTH = 38.0          # mm: cell 18's wear course (4th lift)
TRIES = 60            # random positions per stone before a smaller one is tried
S_MAX = 5.0           # Xu eq. 2
MAX_FACES = 10        # Xu 2.1
A_MAX_FRACTION = 0.5  # Xu's Amax "depends on the graded aggregate size" (not given): faces above 0.5 (D/2)^2 extend
VOXEL = 0.5           # mm: free-space grid that proposes positions (speed only: the exact test decides)
GIVE_UP = 300         # failed stones in a row before a class is called jammed


# ---------------------------------------------------------------- stones (Xu 2010, section 2)

def hull(points):
    """Faces (i, j, k), outward, of the convex hull of a few points (brute force: fine for <= 7 points)."""
    n = len(points)
    faces = []
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                nrm = np.cross(points[j] - points[i], points[k] - points[i])
                if np.linalg.norm(nrm) < 1e-12:
                    continue
                s = (points - points[i]) @ nrm
                others = np.delete(s, [i, j, k])
                if np.all(others <= 1e-9):
                    faces.append((i, j, k))
                elif np.all(others >= -1e-9):
                    faces.append((i, k, j))
    return faces


def face_area(p, f):
    return 0.5 * np.linalg.norm(np.cross(p[f[1]] - p[f[0]], p[f[2]] - p[f[0]]))


def xu_stone(rnd, d):
    """One convex polyhedron of size ~d, by Xu's extension of a triangular fundament. Returns vertices or None."""
    r = d / 2
    while True:   # a random acute triangle in a circle of diameter d (all angle cosines > 0)
        ang = [rnd.uniform(0, 2 * math.pi) for _ in range(3)]
        tri = np.array([[r * math.cos(a), r * math.sin(a), 0.0] for a in ang])
        ok = True
        for k in range(3):
            u, v = tri[(k + 1) % 3] - tri[k], tri[(k + 2) % 3] - tri[k]
            if u @ v <= 0:
                ok = False
        if ok:
            break
    pts = list(tri)
    # first extension: a point off the plane, within r of it (Xu 2.1)
    c = tri.mean(axis=0)
    pts.append(c + np.array([rnd.uniform(-r, r) * 0.3, rnd.uniform(-r, r) * 0.3, rnd.choice([-1, 1]) * rnd.uniform(0.3 * r, r)]))
    p = np.array(pts)
    a_max = A_MAX_FRACTION * r * r
    for _ in range(20):
        faces = hull(p)
        if len(faces) > MAX_FACES:
            return None
        big = [f for f in faces if face_area(p, f) >= a_max]
        if not big:
            break
        if len(faces) + 2 > MAX_FACES:   # one more vertex adds two faces
            break
        f = rnd.choice(big)
        nrm = np.cross(p[f[1]] - p[f[0]], p[f[2]] - p[f[0]])
        nrm /= np.linalg.norm(nrm)
        w = np.array([rnd.random() for _ in range(3)]); w /= w.sum()
        q = w @ p[list(f)] + nrm * rnd.uniform(0.05 * r, r)   # eq. 1: on the outer side, within r of the face
        cand = np.vstack([p, q])
        used = {i for fc in hull(cand) for i in fc}
        if len(used) == len(cand):    # stays convex with every point a corner
            p = cand
    edges = {tuple(sorted((fc[a], fc[(a + 1) % 3]))) for fc in hull(p) for a in range(3)}
    lens = [np.linalg.norm(p[i] - p[j]) for i, j in edges]
    if max(lens) / min(lens) > S_MAX:                       # eq. 2: too sharp
        return None
    return p - p.mean(axis=0)


class Stone:
    def __init__(self, verts, cls):
        self.v0 = verts                     # local vertices, centroid at the origin
        self.faces = hull(verts)
        self.cls = cls
        self.vol = sum(np.dot(verts[a], np.cross(verts[b], verts[c])) for a, b, c in self.faces) / 6.0
        self.r = np.max(np.linalg.norm(verts, axis=1))
        e = {tuple(sorted((f[a], f[(a + 1) % 3]))) for f in self.faces for a in range(3)}
        self.edges = list(e)
        F = np.array(self.faces)
        self.n0 = np.cross(verts[F[:, 1]] - verts[F[:, 0]], verts[F[:, 2]] - verts[F[:, 0]])   # local, once
        E = np.array(self.edges)
        self.e0 = verts[E[:, 1]] - verts[E[:, 0]]


def sieve_scale(verts, size):
    """Scale so the intermediate principal dimension is `size` (the opening the stone just passes)."""
    _, _, vt = np.linalg.svd(verts - verts.mean(axis=0))
    ext = verts @ vt.T
    dims = np.sort(ext.max(axis=0) - ext.min(axis=0))[::-1]
    return verts * (size / dims[1])


def random_rotation(rnd):
    q = np.array([rnd.gauss(0, 1) for _ in range(4)]); q /= np.linalg.norm(q)
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


# ---------------------------------------------------------------- overlap (separating axes)

def placed(st, rot, pos):
    """World vertices, face normals and edge vectors: the local ones turned (no cross products per try)."""
    return st.v0 @ rot.T + pos, st.n0 @ rot.T, st.e0 @ rot.T


def overlap(A, B):
    va, na, ea = A
    vb, nb, eb = B
    a, b = ea[:, None, :], eb[None, :, :]
    cross = np.stack([a[..., 1] * b[..., 2] - a[..., 2] * b[..., 1], a[..., 2] * b[..., 0] - a[..., 0] * b[..., 2],
                      a[..., 0] * b[..., 1] - a[..., 1] * b[..., 0]], axis=-1).reshape(-1, 3)
    axes = np.vstack([na, nb, cross])
    axes = axes[np.einsum("ij,ij->i", axes, axes) > 1e-18]
    pa, pb = va @ axes.T, vb @ axes.T
    sep = (pa.max(axis=0) < pb.min(axis=0)) | (pb.max(axis=0) < pa.min(axis=0))
    return not sep.any()


# ---------------------------------------------------------------- packing

class FreeSpace:
    """Voxel map of the tile: True where no stone is. Periodic in x, y; walls at the top and bottom."""
    def __init__(self):
        self.nx = int(round(TILE / VOXEL)); self.nz = int(round(DEPTH / VOXEL))
        self.free = np.ones((self.nx, self.nx, self.nz), dtype=bool)
        c = (np.arange(self.nx) + 0.5) * VOXEL
        self.cx = c; self.cz = -(np.arange(self.nz) + 0.5) * VOXEL

    def mark(self, v, nrm, faces):
        lo, hi = v.min(axis=0), v.max(axis=0)
        ix = np.arange(int(math.floor(lo[0] / VOXEL)), int(math.ceil(hi[0] / VOXEL)) + 1)
        iy = np.arange(int(math.floor(lo[1] / VOXEL)), int(math.ceil(hi[1] / VOXEL)) + 1)
        iz = np.arange(max(0, int(math.floor(-hi[2] / VOXEL))), min(self.nz, int(math.ceil(-lo[2] / VOXEL)) + 1))
        if len(iz) == 0:
            return
        X, Y, Z = np.meshgrid((ix + 0.5) * VOXEL, (iy + 0.5) * VOXEL, -(iz + 0.5) * VOXEL, indexing="ij")
        P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
        ok = np.ones(len(P), dtype=bool)
        for (a, b, c), n in zip(faces, nrm):
            ok &= (P - v[a]) @ n <= 0
        I, J, K = np.meshgrid(ix % self.nx, iy % self.nx, iz, indexing="ij")
        self.free[I.ravel()[ok], J.ravel()[ok], K.ravel()[ok]] = False

    def room(self, clearance):
        """Voxels at least `clearance` mm from any stone or wall (6-neighbour erosion)."""
        m = self.free.copy()
        m[:, :, 0] = False; m[:, :, -1] = False
        for _ in range(int(math.ceil(clearance / VOXEL))):
            e = m.copy()
            for ax in (0, 1):
                e &= np.roll(m, 1, ax) & np.roll(m, -1, ax)
            e[:, :, 1:] &= m[:, :, :-1]; e[:, :, :-1] &= m[:, :, 1:]
            e[:, :, 0] = False; e[:, :, -1] = False
            m = e
        return np.argwhere(m)


def pack(seed=1, verbose=True):
    rnd = random.Random(seed)
    classes = mix.size_classes()                      # (d_low, d_high, d_mean, share of the aggregate)
    target = [mix.V_AGG * c[3] * TILE * TILE * DEPTH for c in classes]   # mm3 of stone per class
    stones, geo, centers, radii, cls_vol = [], [], [], [], [0.0] * len(classes)
    space = FreeSpace()
    tries_total, fallbacks = 0, 0
    t0 = time.time()
    for ci in range(len(classes)):
        failed = 0
        cand, cand_k, since = None, -1, 0
        while cls_vol[ci] < target[ci] and failed < GIVE_UP:
            k = ci
            done = False
            while k < len(classes) and not done:     # Xu: if it doesn't fit, a smaller stone at this turn
                lo_k, hi_k = classes[k][0], classes[k][1]
                if cand is None or cand_k != k or since > 40:
                    cand, cand_k, since = space.room(0.35 * lo_k), k, 0
                if len(cand) == 0:
                    k += 1
                    continue
                verts = None
                while verts is None:
                    verts = xu_stone(rnd, hi_k)
                st = Stone(sieve_scale(verts, lo_k * (hi_k / lo_k) ** rnd.random()), k)
                for _ in range(TRIES):
                    tries_total += 1
                    rot = random_rotation(rnd)
                    vz = st.v0 @ rot.T
                    zlo, zhi = -DEPTH - vz[:, 2].min(), -vz[:, 2].max()
                    if zlo > zhi:
                        break
                    i, j, kk = cand[rnd.randrange(len(cand))]
                    pos = np.array([space.cx[i] + rnd.uniform(-0.5, 0.5) * VOXEL, space.cx[j] + rnd.uniform(-0.5, 0.5) * VOXEL,
                                    min(max(space.cz[kk], zlo), zhi)])
                    if fits(st, rot, pos, stones, geo, centers, radii):
                        add(st, rot, pos, stones, geo, centers, radii)
                        space.mark(*geo[-1][:2], st.faces)
                        cls_vol[k] += st.vol
                        since += 1
                        done = True
                        if k != ci:
                            fallbacks += 1
                        break
                if not done:
                    since += 5
                k += 1
            failed = 0 if done else failed + 1
            if cand is not None and len(cand) == 0 and cand_k == len(classes) - 1:
                break
    press(stones, geo, centers, radii)
    if verbose:
        print("Packed %d stones in %.1f s (%d tries, %d smaller-stone fallbacks)" % (len(stones), time.time() - t0, tries_total, fallbacks))
    return classes, target, stones, geo, cls_vol


def images(pos):
    """The periodic copies of a point that can touch the tile."""
    out = []
    for dx in (-TILE, 0, TILE):
        for dy in (-TILE, 0, TILE):
            out.append(pos + np.array([dx, dy, 0.0]))
    return out


def fits(st, rot, pos, stones, geo, centers, radii, skip=-1):
    if not centers:
        return True
    C = np.array(centers)
    R = np.array(radii)
    d = C - pos
    d[:, :2] -= TILE * np.round(d[:, :2] / TILE)      # minimum image in x, y
    near = np.nonzero(np.linalg.norm(d, axis=1) < R + st.r)[0]
    if len(near) == 0:
        return True
    A = placed(st, rot, pos)
    for i in near:
        if i == skip:
            continue
        v, n, e = geo[i]
        Bs = (v + (pos + d[i] - C[i]), n, e)     # B's periodic image nearest A
        if overlap(A, Bs):
            return False
    return True


def add(st, rot, pos, stones, geo, centers, radii):
    stones.append((st, rot, pos))
    geo.append(placed(st, rot, pos))
    centers.append(pos)
    radii.append(st.r)


def face_up(st, rot):
    """The smallest turn that lays the stone's most upward-facing face flat (normal +z): a convex body pressed by
    a flat roller comes to rest on a face, not a corner."""
    v = st.v0 @ rot.T
    best, nb = None, -2.0
    for a, b, c in st.faces:
        n = np.cross(v[b] - v[a], v[c] - v[a]); n /= np.linalg.norm(n)
        if n[2] > nb:
            nb, best = n[2], n
    z = np.array([0.0, 0.0, 1.0])
    ax = np.cross(best, z); s_, c_ = np.linalg.norm(ax), best @ z
    if s_ < 1e-12:
        return rot
    ax /= s_
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    turn = np.eye(3) + s_ * K + (1 - c_) * K @ K
    return turn @ rot


def press(stones, geo, centers, radii):
    """The roller: stones whose top is within half their size of the surface turn onto a face and move up
    against it, where they fit (else they stay as they were)."""
    order = sorted(range(len(stones)), key=lambda i: -geo[i][0][:, 2].max())
    moved = 0
    for i in order:
        st, rot, pos = stones[i]
        gap = -geo[i][0][:, 2].max()
        if gap > st.r:
            continue
        for r2 in (face_up(st, rot), rot):
            v = st.v0 @ r2.T
            new = np.array([pos[0], pos[1], -v[:, 2].max()])
            if -DEPTH - v[:, 2].min() > new[2]:
                continue
            if fits(st, r2, new, stones, geo, centers, radii, skip=i):
                stones[i] = (st, r2, new)
                geo[i] = placed(st, r2, new)
                centers[i] = new
                moved += 1
                break
    print("Roller: %d stones laid against the surface" % moved)


# ---------------------------------------------------------------- measuring

def plane_coverage(geo, axis, value, px=0.25):
    """Share of a plane (z = value for axis 2, y = value for axis 1) inside stones, on a grid of `px` mm."""
    if axis == 2:
        n1, n2 = int(TILE / px), int(TILE / px)
        g1, g2 = np.meshgrid((np.arange(n1) + 0.5) * px, (np.arange(n2) + 0.5) * px, indexing="ij")
        P = np.stack([g1.ravel(), g2.ravel(), np.full(g1.size, value)], axis=1)
    else:
        n1, n2 = int(TILE / px), int(DEPTH / px)
        g1, g2 = np.meshgrid((np.arange(n1) + 0.5) * px, -(np.arange(n2) + 0.5) * px, indexing="ij")
        P = np.stack([g1.ravel(), np.full(g1.size, value), g2.ravel()], axis=1)
    inside = np.zeros(len(P), dtype=bool)
    owner = np.full(len(P), -1)
    for si, (v, n, _) in enumerate(geo):
        for img in images(np.zeros(3)):
            vv = v + img
            if axis == 2 and not (vv[:, 2].min() <= value <= vv[:, 2].max()):
                break
            if axis == 1 and not (vv[:, 1].min() <= value <= vv[:, 1].max()):
                continue
            lo, hi = vv.min(axis=0), vv.max(axis=0)
            m = np.all((P >= lo - 1e-9) & (P <= hi + 1e-9), axis=1)
            if not m.any():
                continue
            idx = np.nonzero(m)[0]
            Q = P[idx]
            ok = np.ones(len(idx), dtype=bool)
            for (a, b, c), nrm in zip(stone_faces(si), n):
                ok &= (Q - vv[a]) @ nrm <= 1e-9
            inside[idx[ok]] = True
            owner[idx[ok]] = si
    return inside.mean(), inside.reshape(n1, n2), owner.reshape(n1, n2)


_FACES = []
def stone_faces(i):
    return _FACES[i]


def height_field(geo, px=0.25):
    """Top of the stones at each (x, y), mm (-inf where no stone reaches)."""
    n = int(TILE / px)
    g1, g2 = np.meshgrid((np.arange(n) + 0.5) * px, (np.arange(n) + 0.5) * px, indexing="ij")
    X, Y = g1.ravel(), g2.ravel()
    H = np.full(X.size, -np.inf)
    for si, (v, nrm, _) in enumerate(geo):
        if v[:, 2].max() < -3.0:              # deeper than any mastic level tried
            continue
        for img in images(np.zeros(3)):
            vv = v + img
            lo, hi = vv.min(axis=0), vv.max(axis=0)
            m = (X >= lo[0]) & (X <= hi[0]) & (Y >= lo[1]) & (Y <= hi[1])
            if not m.any():
                continue
            idx = np.nonzero(m)[0]
            top = np.full(len(idx), np.inf)
            bot = np.full(len(idx), -np.inf)
            for (a, b, c), nn in zip(stone_faces(si), nrm):
                if abs(nn[2]) < 1e-12:
                    continue
                z = vv[a, 2] - (nn[0] * (X[idx] - vv[a, 0]) + nn[1] * (Y[idx] - vv[a, 1])) / nn[2]
                if nn[2] > 0:
                    top = np.minimum(top, z)
                else:
                    bot = np.maximum(bot, z)
            hit = top >= bot
            H[idx[hit]] = np.maximum(H[idx[hit]], top[hit])
    return H.reshape(n, n)


def mpd(surface, px=0.25):
    """Mean profile depth, ISO 13473-1: on each 100 mm profile along x, the mean of the two half-baseline peaks
    above the profile's mean level; averaged over the profiles."""
    n = surface.shape[0]
    vals = []
    for j in range(surface.shape[1]):
        prof = surface[:, j]
        prof = prof - prof.mean()
        vals.append(0.5 * (prof[: n // 2].max() + prof[n // 2:].max()))
    return float(np.mean(vals))


# ---------------------------------------------------------------- report

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else None
    if len(sys.argv) > 2:                     # optional tile size (mm) and seed, for the scale check
        TILE = float(sys.argv[2])
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    classes, target, stones, geo, cls_vol = pack(seed)
    _FACES.extend(st.faces for st, _, _ in stones)
    box = TILE * TILE * DEPTH
    phi_target = sum(target) / box
    phi = sum(cls_vol) / box
    print("Stone volume: %.1f %% of the wear course (mix: %.1f %%)" % (phi * 100, phi_target * 100))
    for (lo, hi, d, s), t, v in zip(classes, target, cls_vol):
        cnt = sum(1 for st, _, _ in stones if st.cls == classes.index((lo, hi, d, s)))
        print("  %5.2f-%5.2f mm: %5d stones, %6.0f of %6.0f mm3 (%3.0f %%)" % (lo, hi, cnt, v, t, 100 * v / t))
    faces = [len(st.faces) for st, _, _ in stones]
    print("Faces per stone: %d-%d, mean %.1f (Xu: at most 10)" % (min(faces), max(faces), sum(faces) / len(faces)))
    cys = [plane_coverage(geo, 1, y, px=0.5)[0] for y in np.arange(5, TILE, 10)]
    czs = [plane_coverage(geo, 2, z, px=0.5)[0] for z in np.arange(-1.9, -DEPTH, -3.8)]
    _, sec, sec_owner = plane_coverage(geo, 1, TILE / 2)
    print("Delesse: 10 vertical cuts show %.1f %% stone (sd %.1f), 10 horizontal %.1f %% (stone volume %.1f %%)"
          % (100 * np.mean(cys), 100 * np.std(cys), 100 * np.mean(czs), phi * 100))
    print("  stone share by depth (top to bottom, 3.8 mm steps): " + " ".join("%.0f" % (100 * c) for c in czs))
    H = height_field(geo)
    print("Surface (roller at 0): stones reach within 0.1 mm of it over %.1f %% of the plan" % (100 * np.mean(H > -0.1)))
    target_mpd = mix.mpd_fhwa()[0]
    print("Mean profile depth against the mastic level between the stones (FHWA-HRT-25-100: %.2f mm; Virginia 0.39-0.49):" % target_mpd)
    for hm in (0.25, 0.5, 0.75, 1.0, 1.5, 2.0):
        S = np.maximum(H, -hm)
        print("  mastic %.2f mm below the roller: MPD %.2f mm" % (hm, mpd(S)))
    if out:
        os.makedirs(out, exist_ok=True)
        np.savez_compressed(os.path.join(out, "packing.npz"), H=H,
                            verts=np.array([g[0] for g in geo], dtype=object), cls=np.array([st.cls for st, _, _ in stones]),
                            vol=np.array([st.vol for st, _, _ in stones]), tile=TILE, depth=DEPTH, allow_pickle=True)
        from PIL import Image
        os.makedirs(out, exist_ok=True)
        hm = 1.0
        S = np.maximum(H, -hm)
        img = ((S + hm) / hm * 255).clip(0, 255).astype(np.uint8)
        Image.fromarray(img.T[::-1]).resize((800, 800), Image.NEAREST).save(os.path.join(out, "packing_height.png"))
        rng = np.random.RandomState(3)
        shade = rng.randint(90, 200, size=len(stones) + 1).astype(np.uint8)
        secimg = np.where(sec_owner >= 0, shade[sec_owner], 30).astype(np.uint8)
        Image.fromarray(secimg.T).resize((800, int(800 * DEPTH / TILE)), Image.NEAREST).save(os.path.join(out, "packing_section.png"))
        _, plan, plan_owner = plane_coverage(geo, 2, -0.5)
        planimg = np.where(plan_owner >= 0, shade[plan_owner], 30).astype(np.uint8)
        Image.fromarray(planimg.T[::-1]).resize((800, 800), Image.NEAREST).save(os.path.join(out, "packing_plan_cut_0.5mm.png"))
        print("Images in", out)
