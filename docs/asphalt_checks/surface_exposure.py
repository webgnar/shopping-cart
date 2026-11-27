"""Exposure of the stones as the surface wears, from a packed tile (stone_packing.py's packing.npz).

    python3 surface_exposure.py <dir with packing.npz>

Mechanism (TRR 2676, 2022): oxidation leaves the binder's albedo at about 0.05; abrasion removes the surface
binder and the aggregate shows. Here the surface wears down to a depth w below the roller level: the binder film
goes first, so the stones laid against the surface show at once; then the mastic between the stones wears and
more stones show. A stone shows where its top is above the worn level and it still reaches below it (a stone
entirely above the worn level has ravelled out). The albedo is then the area-weighted mean of what shows:
    albedo(w) = a_binder + (a_agg - a_binder) x A(w),   A(w) = share of the plan where a stone shows.
No fitted number in A(w): it comes from the packed stones of the measured mix. Only w(t), how deep the surface
has worn after t years, is calibrated, against the measured albedo (Pomerantz fig. 1; NCAT 19-09).
"""
import math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv, sys.argv = sys.argv, sys.argv[:1]
import stone_packing as sp
import surface_composition as mix
sys.argv = _argv

PX = 0.25   # mm


def columns(verts, tile, w_max):
    """Per plan point, the stones' top and bottom along each vertical line, for stones reaching above -w_max."""
    n = int(tile / PX)
    g1, g2 = np.meshgrid((np.arange(n) + 0.5) * PX, (np.arange(n) + 0.5) * PX, indexing="ij")
    X, Y = g1.ravel(), g2.ravel()
    tops, bots, deep = [], [], []
    for v in verts:
        if v[:, 2].max() < -w_max:
            continue
        faces = sp.hull(v)
        nrm = [np.cross(v[b] - v[a], v[c] - v[a]) for a, b, c in faces]
        for dx in (-tile, 0, tile):
            for dy in (-tile, 0, tile):
                vv = v + np.array([dx, dy, 0.0])
                lo, hi = vv.min(axis=0), vv.max(axis=0)
                m = (X >= lo[0]) & (X <= hi[0]) & (Y >= lo[1]) & (Y <= hi[1])
                if not m.any():
                    continue
                idx = np.nonzero(m)[0]
                top = np.full(len(idx), np.inf); bot = np.full(len(idx), -np.inf)
                for (a, b, c), nn in zip(faces, nrm):
                    if abs(nn[2]) < 1e-12:
                        continue
                    z = vv[a, 2] - (nn[0] * (X[idx] - vv[a, 0]) + nn[1] * (Y[idx] - vv[a, 1])) / nn[2]
                    if nn[2] > 0:
                        top = np.minimum(top, z)
                    else:
                        bot = np.maximum(bot, z)
                hit = top >= bot
                tops.append((idx[hit], top[hit])); bots.append(bot[hit]); deep.append(np.full(hit.sum(), vv[:, 2].min()))
    return n * n, tops, bots, deep


def exposed_share(npts, tops, bots, deep, w):
    shown = np.zeros(npts, dtype=bool)
    for (idx, top), bot, low in zip(tops, bots, deep):
        ok = (top >= -w) & (low < -w)        # shows above the worn level and still held below it
        shown[idx[ok]] = True
    return shown.mean()


if __name__ == "__main__":
    d = np.load(os.path.join(sys.argv[1], "packing.npz"), allow_pickle=True)
    verts, tile = list(d["verts"]), float(d["tile"])
    a_b, a_agg = mix.A_BINDER, mix.A_AGG
    W = [0.0, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
    npts, tops, bots, deep = columns(verts, tile, max(W))
    A = {w: exposed_share(npts, tops, bots, deep, w) for w in W}
    print("Worn depth w (mm): stone showing A(w), albedo = %.2f + (%.3f - %.2f) A" % (a_b, a_agg, a_b))
    for w in W:
        print("  %4.2f: %5.1f %%  albedo %.3f" % (w, 100 * A[w], a_b + (a_agg - a_b) * A[w]))
    print("Targets: Pomerantz fig. 1 (Concord) 0.08 / 0.11 / 0.12 / 0.12 at 1 / 3 / 5 / 10 yr, over 5 yr 0.12 +- 0.03;"
          " NCAT 19-09 mid-grey aggregates 0.09-0.10 at 1 yr, 0.12-0.14 at 10 yr")
    # worn depth that each Pomerantz point needs
    ws = np.linspace(0, 4, 161)
    Aw = np.array([exposed_share(npts, tops, bots, deep, w) for w in ws])
    alb = a_b + (a_agg - a_b) * Aw
    for yr, target in mix.POMERANTZ.items():
        i = int(np.argmin(abs(alb - target)))
        print("  %2d yr, albedo %.2f: worn %.2f mm (A %.1f %%)" % (yr, target, ws[i], 100 * Aw[i]))
