"""Check of the surface composition model (ASPHALT_SCIENCE.md, Model 1b; roadmap T2 step 6b).

The surface is made of what the mix is made of: binder and aggregate, in the volumes the mix design measured, with
the stones sized by the measured gradation. Run with the same NOAA CSVs as binder_ageing_chain.py:

    python3 surface_composition.py burlington.csv concord.csv

Data (all in References/Asphalt):
  - Mix: MnROAD cell 18 wear course (Mn/DOT 97-06, Table 3.5): gradation, 3.2 % air voids, VMA 15.3 %, 5.8 % AC.
  - Albedos: Pomerantz et al. 2000, Table 1 (binder 0.05; aggregates; chip seal = 0.67 +- 0.11 of its aggregate)
    and fig. 1 (pavement albedo against age).
  - Ageing p: NCHRP 973 chain (binder_ageing_chain.py).
"""
import math, random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_argv, sys.argv = sys.argv, sys.argv[:1]
import binder_ageing_chain as chain   # its CLI loop runs over no files
sys.argv = _argv

# --- The mix: MnROAD cell 18, wear course (4th lift, 38 mm), as built (Mn/DOT 97-06, Table 3.5) ---
SIEVES = [19.0, 16.0, 12.5, 9.0, 4.75, 2.0, 1.0, 0.45, 0.25, 0.075]   # mm
PASSING = [100, 99, 93, 84, 67, 55, 43, 25, 9, 4.6]                    # %
AIR, VMA = 0.032, 0.153
V_AGG = 1.0 - VMA            # aggregate share of the mix volume
V_BINDER = VMA - AIR         # effective binder
STONE_MIN = 2.0              # mm: the sieve below which the aggregate is part of the mastic, not a drawn stone

# --- Albedos (Pomerantz 2000, Table 1) ---
A_BINDER = 0.05              # "asphalt emulsion only"
# Cell 18's aggregate: 90 % partially crushed Crow River gravel, 10 % crushed granite (Mn/DOT 97-06, Table 2.1).
# Stand-ins by rock type from Table 1: river pebbles ("Pamy pebbles") 0.21, granite ("Sierra White") 0.26-0.28.
A_AGG = 0.9 * 0.21 + 0.1 * 0.27
CHIP_RATIO, CHIP_SPREAD = 0.67, 0.11   # a fully exposed stone surface: chip seal albedo / aggregate albedo
A_MAX = CHIP_RATIO * A_AGG

# Pomerantz fig. 1, as read for Model 1 (Concord climate): albedo at 1, 3, 5, 10 years.
POMERANTZ = {1: 0.08, 3: 0.11, 5: 0.12, 10: 0.12}


def size_classes():
    """Stones between consecutive sieves at or above STONE_MIN: (d_low, d_high, d_mean, share of aggregate volume)."""
    out = []
    for k in range(len(SIEVES) - 1):
        lo, hi = SIEVES[k + 1], SIEVES[k]
        if lo < STONE_MIN:
            break
        share = (PASSING[k] - PASSING[k + 1]) / 100.0
        out.append((lo, hi, math.sqrt(lo * hi), share))
    return out


def boolean_intensities(classes):
    """Spheres placed at random (overlaps allowed: a Boolean model). Their union fills phi = V_AGG x stone share of
    the volume exactly when sum(lambda_i v_i) = -ln(1 - phi); each class keeps its share of the stones' volume."""
    phi = V_AGG * sum(c[3] for c in classes)
    total = -math.log(1.0 - phi)
    share = sum(c[3] for c in classes)
    lam = [total * (c[3] / share) / (math.pi / 6 * c[2] ** 3) for c in classes]   # per mm3
    return phi, lam


def slice_fraction(classes, lam, side_mm=500.0, px=0.25, seed=1):
    """A random plane through the field: lay the circles it cuts on a grid; returns the area fraction covered and the
    mean cut diameter per class. Any plane, horizontal (the plan) or vertical (the section), has the same statistics."""
    rnd = random.Random(seed)
    n = int(side_mm / px)
    grid = bytearray(n * n)
    cut = []
    for (lo, hi, d, _), l in zip(classes, lam):
        r = d / 2
        count = l * side_mm * side_mm * d        # spheres whose centre lies within r of the plane
        k = int(count) + (1 if rnd.random() < count - int(count) else 0)
        ds = []
        for _ in range(k):
            x, y, z = rnd.uniform(0, side_mm), rnd.uniform(0, side_mm), rnd.uniform(-r, r)
            rc = math.sqrt(r * r - z * z)
            ds.append(2 * rc)
            for iy in range(max(0, math.ceil((y - rc) / px)), min(n, math.floor((y + rc) / px) + 1)):
                dy = iy * px - y
                if abs(dy) > rc:
                    continue
                w = math.sqrt(rc * rc - dy * dy)
                a, b = max(0, math.ceil((x - w) / px)), min(n, math.floor((x + w) / px) + 1)   # pixel centres inside
                grid[iy * n + a:iy * n + b] = b"\x01" * (b - a)
        cut.append((d, sum(ds) / len(ds) if ds else 0.0, k))
    return sum(grid) / len(grid), cut


def surface_p(csv, years=10):
    """Surface ageing p = 1 - exp(-N AP) per year, from the NCHRP 973 chain (same loop as binder_ageing_chain.run)."""
    tx, tn, lat, name = chain.normals(csv)
    M = 0.94 / (1 + (64.0 / 82.68) ** 7.96)
    mid = [15.2 + 30.4 * m for m in range(12)]
    def interp(arr, d):
        for m in range(12):
            a = mid[m]; b = a + 30.4; dd = d if d >= mid[0] else d + 365
            if a <= dd < b or m == 11:
                return arr[m] + (arr[(m + 1) % 12] - arr[m]) * min(max((dd - a) / 30.4, 0), 1)
    x, ap = 0.0, {}
    for y in range(years):
        for d in range(365):
            hi = chain.t_high(interp(tx, d), lat, 0); lo = chain.t_low(interp(tn, d), lat, 0)
            for h in range(24):
                s = (1 - math.cos(math.pi * (h - 6) / 9)) / 2 if 6 <= h <= 15 else (1 + math.cos(math.pi * ((h - 15) % 24) / 15)) / 2
                T = lo + (hi - lo) * s + 273.15
                if T < 293.15:
                    continue
                x = chain.F(chain.teq(x, T, M) + 1 / 24.0, T, M)
        ap[y + 1] = x / M
    N = 0.477 * math.exp(-0.226 * ap[10])
    return name, {y: 1 - math.exp(-N * a) for y, a in ap.items()}


def passing_at(d):
    """% passing a sieve of d mm, straight line in log(size) between the measured sieves."""
    for k in range(len(SIEVES) - 1):
        hi, lo = SIEVES[k], SIEVES[k + 1]
        if lo <= d <= hi:
            f = math.log(d / lo) / math.log(hi / lo)
            return PASSING[k + 1] + f * (PASSING[k] - PASSING[k + 1])
    raise ValueError(d)


def size_at(pct):
    """mm at which pct % passes (inverse of passing_at)."""
    for k in range(len(SIEVES) - 1):
        if PASSING[k + 1] <= pct <= PASSING[k]:
            f = (pct - PASSING[k + 1]) / (PASSING[k] - PASSING[k + 1])
            return SIEVES[k + 1] * (SIEVES[k] / SIEVES[k + 1]) ** f
    raise ValueError(pct)


def mpd_fhwa():
    """Mean profile depth (mm) from FHWA-HRT-25-100 eq. 1 (dense-graded: Type 0):
    MPD = 1.03 + 0.224 Type + 0.0034 Cu - 0.0050 P8 - 0.0105 P200 - 0.0049 VFA."""
    cu = size_at(60) / size_at(10)
    p8, p200, vfa = passing_at(2.36), PASSING[-1], (VMA - AIR) / VMA * 100
    return 1.03 + 0.0034 * cu - 0.0050 * p8 - 0.0105 * p200 - 0.0049 * vfa, cu, p8, vfa


def albedo_ncat(age, clr):
    """NCAT 19-09 fig. 97 (recalibrated): albedo = (0.0001 CLR + 0.0033) ln(age) + (0.0001 CLR + 0.0812), with CLR the
    coarse aggregate's grayscale (0-255) and age in years; field data, central and eastern US."""
    return (0.0001 * clr + 0.0033) * math.log(age) + (0.0001 * clr + 0.0812)


def albedo(p, p0):
    """Mean albedo: binder, plus exposed aggregate rising to the chip-seal ceiling as the surface ages."""
    return A_BINDER + (A_MAX - A_BINDER) * (1 - math.exp(-p / p0))


if __name__ == "__main__":
    classes = size_classes()
    phi, lam = boolean_intensities(classes)
    print("Mix (MnROAD cell 18 wear course): aggregate %.1f %%, effective binder %.1f %%, air %.1f %% of the volume"
          % (V_AGG * 100, V_BINDER * 100, AIR * 100))
    print("  Pomerantz p. 3 gives about 85 / 15 aggregate / binder by volume.")
    print("Stones (>= %.1f mm): %.1f %% of the volume; classes:" % (STONE_MIN, phi * 100))
    for (lo, hi, d, s), l in zip(classes, lam):
        print("  %5.2f-%5.2f mm (d %.2f): %4.1f %% of the aggregate, %8.0f per litre" % (lo, hi, d, s * 100, l * 1e6))
    frac, cut = slice_fraction(classes, lam)
    print("Random plane: stones cover %.1f %% (Delesse: the volume fraction, %.1f %%)" % (frac * 100, phi * 100))
    for d, mean_cut, k in cut:
        print("  d %.2f mm: %5d circles, mean cut diameter %.2f mm (sphere theory pi/4 d = %.2f)" % (d, k, mean_cut, math.pi / 4 * d))
    per_cut = sum(l * c[2] for l, c in zip(lam, classes)) * 10000.0 * 76.0
    print("A 10 m section through 76 mm of asphalt cuts about %.0f stones." % per_cut)
    mpd, cu, p8, vfa = mpd_fhwa()
    print("Macrotexture target: MPD %.2f mm (FHWA-HRT-25-100 eq. 1; Cu %.1f, P8 %.1f %%, VFA %.1f %%); Virginia dense-graded"
          " surfaces measured 0.39-0.49 mm (VTRC 23-R15)" % (mpd, cu, p8, vfa))
    print("NCAT 19-09 albedo by coarse aggregate grayscale: " + "; ".join(
        "CLR %d: %s" % (c, " / ".join("%.3f" % albedo_ncat(y, c) for y in (1, 3, 5, 10))) for c in (60, 110, 160, 210))
        + " at 1 / 3 / 5 / 10 yr")
    print("Albedo: binder %.2f, aggregate %.3f (rock-type stand-in), ceiling 0.67 x aggregate = %.3f (+- %.3f)"
          % (A_BINDER, A_AGG, A_MAX, CHIP_SPREAD * A_AGG))
    files = sys.argv[1:]
    if not files:
        sys.exit(0)
    sites = [surface_p(f) for f in files]
    concord = [s for s in sites if "CONCORD" in s[0].upper()]
    if concord:
        p = concord[0][1]
        best = min((sum((albedo(p[y], p0 / 1000) - a) ** 2 for y, a in POMERANTZ.items()), p0 / 1000) for p0 in range(20, 1000))
        p0 = best[1]
        print("p0 fitted to Pomerantz fig. 1 in Concord: %.3f (rms %.4f)" % (p0, math.sqrt(best[0] / len(POMERANTZ))))
        for name, p in sites:
            print("  %s: " % name + ", ".join("%d yr %.3f" % (y, albedo(p[y], p0)) for y in (1, 3, 5, 10))
                  + "; exposed share of the stone area %.2f at 10 yr" % ((albedo(p[10], p0) - A_BINDER) / ((A_AGG - A_BINDER) * V_AGG)))
        print("  Pomerantz: " + ", ".join("%d yr %.2f" % (y, a) for y, a in POMERANTZ.items()) + "; over 5 years 0.12 +- 0.03, never over ~0.16")
