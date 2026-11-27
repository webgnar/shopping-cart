"""Model 2 (thermal cracking) checked against its sources, before any code. See docs/ASPHALT_SCIENCE.md, Model 2.

    python3 thermal_cracking_chain.py            (from docs/asphalt_checks/; numpy only)

Sources (References/Asphalt):
  Mn/DOT 2007-43 (Marasteanu et al.): reference mix 64-22:U1:4:GR (12.5 mm, PG 64-22, granite, 6.0 % AC, 4 % air):
    Table 6.5 creep stiffness, Table 6.17 TSRST at 10 C/h, Table 6.19 dilatometry; Table 6.14 strength scatter;
    ch. 2 eqs. 24-32 (TCMODEL stress: master curve, relaxation, hereditary integral, Soules recursion).
  NCHRP 973 ch. 6: AMAC eq. 51 (c = 1.71) and eq. 37 (second-order log aT).
  Li & Marasteanu 2005: eq. 4 slip length, Table 4 inputs; Chen 2022 eqs. 14-15 (halving).
  FHWA-RD-97-103 eqs. 7, 8 and NCHRP 973's ageing (via binder_ageing_chain.py): T2's models.
  NOAA GHCN-Daily TMAX/TMIN 1991-2020 (data/): Burlington VT (default site), Minneapolis MN (next to MnROAD).
Assumptions are marked ASSUMPTION where they are made.
"""
import csv, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_argv, sys.argv = sys.argv, sys.argv[:1]
import binder_ageing_chain as t2          # T2's equations: t_high, t_low (FHWA-RD-97-103), F, teq (NCHRP 973)
sys.argv = _argv
rng = np.random.default_rng(1)

# ---------------------------------------------------------------- 1. the reference mix (Mn/DOT 2007-43)
S_DATA = {0.0: (3.17, 1.18), -12.0: (10.24, 5.55), -24.0: (23.87, 18.32)}   # Table 6.5, GPa at 60 / 500 s
TSRST = [(-26.8, 2.821, 0.209), (-25.0, 3.023, 0.206)]                      # Table 6.17: T_f C, sigma_f MPa, dS/dT
TG, A_G, A_L = -27.94, 10.95e-6, 33.20e-6                                   # Table 6.19, cooling
SIGMA_T = sum(s for _, s, _ in TSRST) / 2 * 1e6                             # 2.92 MPa: the strength proposed
CV_IDT = [5.2, 17.9, 3.4, 8.3, 5.7, 7.0, 4.8, 1.8, 18.6, 5.5, 7.6, 5.4, 13.9, 4.5, 2.3, 3.6, 38.2, 6.5, 6.4,
          6.2, 6.7, 11.5, 16.9, 6.9]                                         # Table 6.14 CVs, % (field cores)
CV = float(np.median(CV_IDT)) / 100
AMAC_C = 1.71                                                               # NCHRP 973 eq. 51, Level 2
TREF = -12.0


def fit_master():
    """D(xi) = D0 + D1 xi^m, xi = t / aT, log aT = a1 (T-Tref) + a2 (T-Tref)^2 (NCHRP 973 eq. 37 form).
    Six points, five unknowns: grid over m and the two shifts, linear least squares for D0, D1 (in 1/GPa)."""
    pts = [(T, t, 1.0 / s) for T, (s60, s500) in S_DATA.items() for t, s in ((60.0, s60), (500.0, s500))]
    best = None
    for m in np.linspace(0.05, 0.8, 76):
        for l0 in np.linspace(0.0, 4.0, 81):            # log aT at 0 C relative to -12 C: negative shift = faster
            for l24 in np.linspace(0.0, 4.0, 81):
                la = {0.0: -l0, -12.0: 0.0, -24.0: l24}
                A = np.array([[1.0, (t / 10 ** la[T]) ** m] for T, t, _ in pts])
                y = np.array([d for _, _, d in pts])
                c, *_ = np.linalg.lstsq(A, y, rcond=None)
                if c[0] <= 0 or c[1] <= 0:
                    continue
                r = float(np.sum((np.log(A @ c) - np.log(y)) ** 2))
                if best is None or r < best[0]:
                    best = (r, m, -l0, l24, c[0], c[1])
    r, m, la0, la24, d0, d1 = best
    # exact quadratic through log aT(0) = la0, log aT(-12) = 0, log aT(-24) = la24
    a2 = (la0 + la24) / (2 * 144.0); a1 = (la0 - la24) / 24.0
    return dict(m=m, D0=d0 * 1e-9, D1=d1 * 1e-9, a1=a1, a2=a2, rms=math.sqrt(r / 6), pts=pts)


MC = fit_master()


def log_aT(T):
    x = T - TREF
    return MC["a1"] * x + MC["a2"] * x * x


def D(xi):
    return MC["D0"] + MC["D1"] * np.power(xi, MC["m"])


ALPHA_CONST = None                                                          # set to test one constant alpha


def eps_th(T, R=1.0):
    """Thermal strain from the dilatometric curve (Mn/DOT 2007-43 ch. 6), linear coefficients, zero at 0 C.
    d eps/dT = a_g + (a_l - a_g) / (1 + exp(-(T - Tg)/R)). R is not tabulated for the mixes: ASSUMPTION, swept."""
    if ALPHA_CONST is not None:
        return ALPHA_CONST * np.asarray(T, float)

    def integ(x):
        return A_G * (x - TG) + R * (A_L - A_G) * np.logaddexp(0.0, (x - TG) / R)
    return integ(T) - integ(0.0)


# ---------------------------------------------------------------- 2. relaxation modulus, two ways
def relaxation_curve(ts):
    """E(xi) from D(xi): the stress after a unit strain step, solving sum_k D(t_n - tau_k) dsigma_k = 1."""
    ds = np.zeros(len(ts)); out = np.zeros(len(ts))
    ds[0] = 1.0 / MC["D0"]
    for n in range(1, len(ts)):
        tau = np.concatenate(([0.0], 0.5 * (ts[:n - 1] + ts[1:n]))) if n > 1 else np.array([0.0])
        acc = np.sum(D(ts[n] - tau[:n]) * ds[:n])
        tmid = 0.5 * (ts[n - 1] + ts[n])
        ds[n] = (1.0 - acc) / D(ts[n] - tmid)
        out[n] = np.sum(ds[:n + 1])
    out[0] = ds[0]
    return out


def fit_prony(ts, E):
    """Maxwell Prony series (Mn/DOT eq. 29), two relaxation times per decade, least squares in log E."""
    lam = 10.0 ** np.arange(-6, 13, 0.5)
    A = np.exp(-ts[:, None] / lam[None, :]) / E[:, None]
    w, *_ = np.linalg.lstsq(A, np.ones_like(ts), rcond=None)
    for _ in range(200):                                # crude projection to Ei >= 0
        if (w >= 0).all():
            break
        w = np.clip(w, 0, None)
        keep = w > 0
        w2, *_ = np.linalg.lstsq(A[:, keep], np.ones_like(ts), rcond=None)
        w = np.zeros_like(w); w[keep] = w2
    return lam, w


TS = np.concatenate(([1e-8], np.logspace(-6, 12, 600)))
E_CURVE = relaxation_curve(TS)
LAM, EI = fit_prony(TS, E_CURVE)


def E_prony(xi):
    return np.sum(EI[None, :] * np.exp(-np.asarray(xi)[:, None] / LAM[None, :]), axis=1)


# ---------------------------------------------------------------- 3. restrained stress
def stress_volterra(times, temps, log_aA=0.0, R=1.0):
    """Exact (to the quadrature) restrained stress from the compliance: sum D(xi_n - xi_k) dsigma_k = -eps_th."""
    xi = np.concatenate(([0.0], np.cumsum(np.diff(times) / 10 ** (log_aT(0.5 * (temps[1:] + temps[:-1])) + log_aA))))
    target = -(eps_th(temps, R) - eps_th(temps[0], R))
    ds = np.zeros(len(times)); sig = np.zeros(len(times))
    for n in range(1, len(times)):
        xm = 0.5 * (xi[1:n + 1] + xi[:n])
        acc = np.sum(D(xi[n] - xm[:n - 1]) * ds[1:n]) if n > 1 else 0.0
        ds[n] = (target[n] - acc) / D(xi[n] - xm[n - 1])
        sig[n] = sig[n - 1] + ds[n]
    return sig


class Soules:
    """Mn/DOT 2007-43 eq. 32: sigma_i(t) = e^(-dxi/l_i) sigma_i + d_eps E_i (l_i/dxi)(1 - e^(-dxi/l_i)).
    Vectorised over several depths at once."""
    def __init__(self, ndepth):
        self.s = np.zeros((ndepth, len(LAM)))

    def step(self, deps, dxi):
        dxi = np.maximum(dxi, 1e-30)[:, None]
        x = dxi / LAM[None, :]
        e = np.exp(-np.minimum(x, 700))
        f = np.where(x < 1e-8, 1.0 - x / 2, -np.expm1(-np.minimum(x, 700)) / np.maximum(x, 1e-300))
        self.s = e * self.s + deps[:, None] * EI[None, :] * f
        return self.s.sum(axis=1)


def tsrst(log_aA=0.0, R=1.0, rate=10.0, t0=5.0, method="soules", dt_min=1.0):
    """Restrained cooling from t0 at `rate` C/h. ASSUMPTION: start at +5 C (AASHTO TP10 practice; the report
    gives only the rate). Returns (fracture T at sigma_t, slope dS/dT there in MPa/C)."""
    n = int((t0 + 45) / rate * 60 / dt_min)
    times = np.arange(n + 1) * dt_min * 60.0
    temps = t0 - rate * times / 3600.0
    if method == "volterra":
        sig = stress_volterra(times, temps, log_aA, R)
    else:
        so = Soules(1); sig = np.zeros(n + 1)
        e = eps_th(temps, R)
        for k in range(1, n + 1):
            tm = 0.5 * (temps[k] + temps[k - 1])
            dxi = np.array([(times[k] - times[k - 1]) / 10 ** (log_aT(tm) + log_aA)])
            sig[k] = so.step(np.array([-(e[k] - e[k - 1])]), dxi)[0]
    k = int(np.argmax(sig >= SIGMA_T))
    if sig[k] < SIGMA_T:
        return None, None, temps, sig
    f = (SIGMA_T - sig[k - 1]) / (sig[k] - sig[k - 1])
    tf = temps[k - 1] + f * (temps[k] - temps[k - 1])
    slope = (sig[k] - sig[k - 1]) / (temps[k - 1] - temps[k]) / 1e6
    return tf, slope, temps, sig


# ---------------------------------------------------------------- 4. ageing (T2) and the shift aA (AMAC)
def daily(path):
    rows = list(csv.DictReader(open(path)))
    return [(r["DATE"], float(r["TMAX"]), float(r["TMIN"])) for r in rows]


def monthly_means(days):
    sx = [[] for _ in range(12)]; sn = [[] for _ in range(12)]
    for d, x, n in days:
        m = int(d[5:7]) - 1; sx[m].append(x); sn[m].append(n)
    return [sum(a) / len(a) for a in sx], [sum(a) / len(a) for a in sn]


def ageing_by_year(tx, tn, lat, years, HPG=64.0):
    """T2's chain (binder_ageing_chain.run) year by year: log|G*|(z) at the end of each year, z in cm."""
    g0 = 6.552 / (1 + (HPG / 107.167) ** -4.068); M = 0.94 / (1 + (HPG / 82.68) ** 7.96)
    mid = [15.2 + 30.4 * m for m in range(12)]

    def interp(arr, d):
        for m in range(12):
            a = mid[m]; dd = d if d >= mid[0] else d + 365
            if a <= dd < a + 30.4 or m == 11:
                return arr[m] + (arr[(m + 1) % 12] - arr[m]) * min(max((dd - a) / 30.4, 0), 1)
    x = 0.0; AP = {0: 0.0}
    for y in range(years):
        for d in range(365):
            hi = t2.t_high(interp(tx, d), lat, 0.0); lo = t2.t_low(interp(tn, d), lat, 0.0)
            for h in range(24):
                s = (1 - math.cos(math.pi * (h - 6) / 9)) / 2 if 6 <= h <= 15 else (1 + math.cos(math.pi * ((h - 15) % 24) / 15)) / 2
                T = lo + (hi - lo) * s + 273.15
                if T < 293.15:
                    continue
                x = t2.F(t2.teq(x, T, M) + 1 / 24.0, T, M)
        AP[y + 1] = x / M
    N = 0.477 * math.exp(-0.226 * AP[min(10, years)])
    APmax = (4.5 - g0) / M

    def dlogG(year, zcm):                         # NCHRP 973 eq. 22 minus log|G*|0: AMAC's Delta
        return M * ((0.916 * zcm + APmax) / (zcm + 1)) * (1 - math.exp(-N * AP[year]))
    return dlogG, g0, M


# ---------------------------------------------------------------- 5. the road through the winters
def hourly_temps(days, lat, depths_mm, normals=None):
    """T2's pavement temperature (FHWA-RD-97-103 eqs. 7, 8 at each depth) from each day's own TMAX/TMIN,
    T2's daily cycle (coldest 06:00, hottest 15:00). With normals=(tx, tn) the monthly normals are used instead."""
    H = np.array(depths_mm, float)
    out = []
    for i, (d, x, n) in enumerate(days):
        if normals:
            m = int(d[5:7]) - 1; x, n = normals[0][m], normals[1][m]
        nx = days[i + 1][2] if i + 1 < len(days) and not normals else n   # next morning's low for the evening
        hi = np.array([t2.t_high(x, lat, h) for h in H]); lo = np.array([t2.t_low(n, lat, h) for h in H])
        lo2 = np.array([t2.t_low(nx, lat, h) for h in H])
        for h in range(24):
            if h < 6:
                s = (1 + math.cos(math.pi * ((h + 24 - 15)) / 15)) / 2; T = lo + (hi - lo) * s   # tail of last night
            elif h <= 15:
                s = (1 - math.cos(math.pi * (h - 6) / 9)) / 2; T = lo + (hi - lo) * s
            else:
                s = (1 + math.cos(math.pi * (h - 15) / 15)) / 2; T = lo2 + (hi - lo2) * s
            out.append(T)
    return np.array(out)


def run_road(days, lat, h_m, C, tanphi, rho, dlogG, ageing=True, normals=None, line_m=1000.0, start_age=0,
             label=""):
    depths_cm = np.arange(0.0, h_m * 100 + 1e-9, 1.0)
    if depths_cm[-1] < h_m * 100 - 0.01:
        depths_cm = np.append(depths_cm, h_m * 100)
    T = hourly_temps(days, lat, depths_cm * 10, normals)
    e = eps_th(T)
    tau = C / h_m + rho * 9.81 * tanphi                     # Li & Marasteanu eq. 4 denominator, Pa/m
    so = Soules(len(depths_cm))
    segs = [[0.0, line_m, SIGMA_T * (1 + CV * rng.standard_normal())]]   # [start, end, strength at its weak point]
    cracks = {}                                              # position -> [depth cm, strength, year formed]
    yearly = []
    nh = len(T)
    first_year = int(days[0][0][:4])
    peak = np.zeros(len(depths_cm)); tmin = 99.0
    for k in range(1, nh):
        day = k // 24
        date = days[day][0]; yr = int(date[:4]); mo = int(date[5:7])
        age = yr - first_year + (1 if mo >= 7 else 0) + start_age      # ASSUMPTION: built July 1 of the first year
        la = np.array([AMAC_C * dlogG(min(age, 30), z) for z in depths_cm]) if ageing else np.zeros(len(depths_cm))
        tm = 0.5 * (T[k] + T[k - 1])
        dxi = 3600.0 / 10 ** (log_aT(tm) + la)
        sig = so.step(-(e[k] - e[k - 1]), dxi)
        peak = np.maximum(peak, sig); tmin = min(tmin, float(T[k][0]))
        s0 = sig[0]
        if s0 >= 0.8 * SIGMA_T:
            changed = True
            while changed:                                   # split every segment the stress can break
                changed = False
                for sg in list(segs):
                    a, b, st = sg; L = b - a
                    if min(s0, tau * L / 2) < st:
                        continue
                    xs = s0 / tau                            # distance from a free end to the stress plateau
                    pos = a + L / 2 if L <= 2 * xs else rng.uniform(a + xs, b - xs)   # Bohn: middle near threshold
                    segs.remove(sg)
                    segs += [[a, pos, SIGMA_T * (1 + CV * rng.standard_normal())],
                             [pos, b, SIGMA_T * (1 + CV * rng.standard_normal())]]
                    cracks[pos] = [0.0, st, yr if mo >= 7 else yr - 1]
                    changed = True
            for c in cracks.values():                        # depth: contiguous from the surface with sigma >= strength
                over = sig >= c[1]
                dz = depths_cm[np.argmin(over)] if not over.all() else depths_cm[-1]
                if over.all():
                    dz = h_m * 100
                c[0] = max(c[0], float(dz))
        if date[5:] == "06-30" and k % 24 == 23:
            n = len(cracks); full = sum(1 for c in cracks.values() if c[0] >= h_m * 100 - 1e-6)
            dps = [c[0] for c in cracks.values()] or [0.0]
            yearly.append((yr - 1, tmin, peak[0] / 1e6, n, full, max(dps), sum(dps) / len(dps)))
            peak[:] = 0; tmin = 99.0
    lens = np.diff(sorted([0.0] + list(cracks) + [line_m]))[1:-1] if len(cracks) > 1 else np.array([])
    return yearly, lens, tau


# ---------------------------------------------------------------- report
def main():
    print("1. Reference mix master curve (Mn/DOT 2007-43 Table 6.5, 64-22:U1:4:GR)")
    print(f"   D(xi) = {MC['D0']*1e9:.4f} + {MC['D1']*1e9:.4f} xi^{MC['m']:.3f}  (1/GPa, xi in s at -12 C); "
          f"log aT(0) = {log_aT(0):+.2f}, log aT(-24) = {log_aT(-24):+.2f}; rms log error {MC['rms']:.3f}")
    for T, t, d in MC["pts"]:
        print(f"     {T:+5.0f} C {t:4.0f} s: measured S {1/d:6.2f} GPa, fitted {1e-9/D(t/10**log_aT(T)):6.2f}")
    print(f"   glassy limit 1/D0 = {1e-9/MC['D0']:.1f} GPa (Hirsch's maximum for a mix is about 30 GPa: NCHRP 973 p. 82)")
    xi = np.logspace(-4, 10, 8)
    print("   relaxation: Prony fit against the interconverted curve: max rel. error "
          f"{np.max(np.abs(E_prony(TS[1:]) / E_CURVE[1:] - 1)):.3f}; E(1 s) = {E_prony(np.array([1.0]))[0]/1e9:.1f} GPa, "
          f"E(1 h) = {E_prony(np.array([3600.0]))[0]/1e9:.2f} GPa at -12 C")

    print("\n2. TSRST, 10 C/h from +5 C, fully restrained (measured: -26.8 C / 2.82 MPa, -25.0 C / 3.02 MPa; "
          "slope 0.21 MPa/C)")
    for R in (0.5, 1.0, 2.0, 4.0):
        tv, sv, _, _ = tsrst(R=R, method="volterra")
        tsl, ssl, _, _ = tsrst(R=R)
        print(f"   R {R:3.1f} C: fracture at sigma_t {SIGMA_T/1e6:.2f} MPa: compliance solve {tv:+.1f} C "
              f"(slope {sv:.2f}), Soules/Prony {tsl:+.1f} C (slope {ssl:.2f})")
    print("   what alpha does: one constant alpha = 33.2e-6 (alpha_l) vs 18.6e-6 (Li's Jones value):")
    global ALPHA_CONST
    for a in (A_L, 18.62e-6):
        ALPHA_CONST = a
        tf, sl, _, _ = tsrst()
        ALPHA_CONST = None
        print(f"     alpha {a*1e6:.1f}e-6: fracture {tf:+.1f} C" if tf else f"     alpha {a*1e6:.1f}e-6: no fracture by -40 C")

    print("\n3. Jones (Li eq. 3) for cell 18's wear course (VMA 15.3 %, V_agg 84.7 %, Mn/DOT 97-06), B_AC 3.45e-4:")
    b_ag = (1.862e-5 * 300 - 15.3 * 3.45e-4) / 84.7
    print(f"   binder term alone {15.3*3.45e-4/300*1e6:.1f}e-6; Li's 18.62e-6 would need B_agg = {b_ag*1e6:.1f}e-6 "
          f"volumetric ({b_ag/3*1e6:.1f}e-6 linear): too low for rock. Li's VMA or B_agg were other values (not given).")
    print(f"   measured mixes (Mn/DOT Table 6.19): alpha_l 29-41e-6 above Tg, alpha_g 6-16e-6 below; Chen Table 2: 15-22e-6")

    print("\n4. Li & Marasteanu Table 4: Xc = sigma_t / (C/h + rho g tan phi)")
    for cell, s, C, tp, sg, xc in ((18, 2270e3, 62.1e3, 1.299, 2289, 6.7), (21, 2400e3, 77.2e3, 0.787, 2303, 5.9),
                                   (22, 2390e3, 62.1e3, 1.299, 2287, 7.0)):
        print(f"   cell {cell}: {s/(C/0.2+sg*9.81*tp):.2f} m (Table 4: {xc} m)")
    tau_d = 62.1e3 / 0.0762 + 2289 * 9.81 * 1.299
    print(f"   default build-up (c620, h 76 mm): C/h {62.1e3/0.0762/1e3:.0f} and rho g tan phi {2289*9.81*1.299/1e3:.0f} kPa/m;"
          f" Xc {2.27e6/tau_d:.2f} m with 2.27 MPa, {SIGMA_T/tau_d:.2f} m with {SIGMA_T/1e6:.2f} MPa")

    print("\n5. Halving with strength scatter (CV %.1f %%, median of Mn/DOT Table 6.14), far-field stress raised slowly:" % (CV * 100))
    for s_far in (1.05, 1.5, 3.0):
        L = []
        for trial in range(40):
            segs = [[0.0, 300.0, SIGMA_T * (1 + CV * rng.standard_normal())]]
            for s in np.linspace(0.5, s_far, 200) * SIGMA_T:
                changed = True
                while changed:
                    changed = False
                    for sg in list(segs):
                        a, b, st = sg; Ls = b - a
                        if min(s, tau_d * Ls / 2) < st:
                            continue
                        xs = s / tau_d
                        pos = a + Ls / 2 if Ls <= 2 * xs else rng.uniform(a + xs, b - xs)
                        segs.remove(sg)
                        segs += [[a, pos, SIGMA_T * (1 + CV * rng.standard_normal())],
                                 [pos, b, SIGMA_T * (1 + CV * rng.standard_normal())]]
                        changed = True
            L += [b - a for a, b, _ in segs if a > 0 and b < 300]
        L = np.array(L); xc = SIGMA_T / tau_d
        print(f"   far field {s_far:.2f} x sigma_t: mean spacing {L.mean():.2f} m = {L.mean()/xc:.2f} Xc, "
              f"CV {L.std()/L.mean():.2f}, range {L.min()/xc:.2f}-{L.max()/xc:.2f} Xc")
    print("   Li Table 2, cell 18 driving lane: 15.8 +- 7.35 ft: CV 0.47")

    print("\n6. Ageing (T2 chain, Burlington normals from the daily record) -> AMAC shift -> TSRST fracture temperature")
    bur = daily(os.path.join(HERE, "data", "ghcnd_USW00014742_burlington_vt_1991-2020.csv"))
    msp = daily(os.path.join(HERE, "data", "ghcnd_USW00014922_minneapolis_mn_1991-2020.csv"))
    btx, btn = monthly_means(bur)
    tres_hi = [28.9, 31.5, 40.9, 55.3, 69.0, 77.6, 82.4, 80.7, 72.6, 58.9, 46.4, 35.0]
    tres_lo = [12.9, 14.3, 23.6, 35.9, 47.8, 57.3, 62.4, 60.7, 52.9, 41.8, 32.1, 21.3]
    dev = max(max(abs(a - (b - 32) / 1.8) for a, b in zip(btx, tres_hi)), max(abs(a - (b - 32) / 1.8) for a, b in zip(btn, tres_lo)))
    print(f"   daily-record monthly means vs the SiteClimate normals: largest difference {dev:.2f} C")
    dG_b, g0, M = ageing_by_year(btx, btn, 44.4683, 30)
    for yr in (0, 1, 2, 5, 10, 20, 30):
        row = []
        for z in (0, 2, 4, 7.6):
            la = AMAC_C * dG_b(yr, z)
            tf, _, _, _ = tsrst(log_aA=la)
            row.append(f"z {z:3.1f} cm: dlogG {dG_b(yr, z):.2f}, Tf {tf:+.1f}")
        print(f"   year {yr:2d}: " + "; ".join(row))

    print("   plausibility against aged field cores: MnROAD 19 (AC-20, about 12 years in Minnesota; Mn/DOT Table 6.13)")
    print("   measured creep stiffness, GPa, -12 C 60/500 s and -24 C 60/500 s: 13.95 / 9.89 and 20.47 / 19.08")
    for dl in (0.0, 0.25, 0.5, 1.0, 2.0):
        sv = [1e-9 / D(t / 10 ** (log_aT(T) + AMAC_C * dl)) for T in (-12.0, -24.0) for t in (60.0, 500.0)]
        print(f"   reference mix shifted by Delta log|G*| {dl:.2f}: " + " / ".join(f"{x:.1f}" for x in sv))
    print(f"   T2 at 12 years (Burlington): surface {dG_b(12, 0):.2f}, 2 cm {dG_b(12, 2):.2f}, 4 cm {dG_b(12, 4):.2f}")

    print("\n7. The road, 30 winters, default build-up (h 76 mm, C 62.1 kPa, tan phi 1.299), 1 km line, sigma_t 2.92 MPa")
    lat_b, lat_m = 44.4683, 44.8831
    mtx, mtn = monthly_means(msp)
    dG_m, _, _ = ageing_by_year(mtx, mtn, lat_m, 30)
    runs = [("Burlington, aged (default)", bur, lat_b, dG_b, True, None),
            ("Burlington, no ageing", bur, lat_b, dG_b, False, None),
            ("Burlington, monthly normals", bur, lat_b, dG_b, True, (btx, btn)),
            ("Minneapolis, aged", msp, lat_m, dG_m, True, None)]
    res = {}
    for name, days, lat, dG, ag, nm in runs:
        yearly, lens, tau = run_road(days, lat, 0.0762, 62.1e3, 1.299, 2289, dG, ageing=ag, normals=nm)
        res[name] = (yearly, lens)
        print(f"   {name}:")
        last = None
        for (y, tmin, pk, n, full, dmax, dmean) in yearly:
            if (n, round(dmax)) != last or y in (1991, 2020):
                print(f"     winter {y}-{(y+1)%100:02d}: surface min {tmin:+.1f} C, peak stress {pk:.2f} MPa, "
                      f"cracks {n} per km ({n*152.4/1000:.1f} per 500 ft), depth mean {dmean:.1f} / max {dmax:.1f} cm, "
                      f"{full} full depth")
            last = (n, round(dmax))
        if len(lens):
            print(f"     final spacing {lens.mean():.1f} +- {lens.std():.1f} m (Xc {SIGMA_T/tau:.2f} m)")

    print("\n8. Thickness: Burlington aged, h 152 mm (same base):")
    yearly, lens, tau = run_road(bur, lat_b, 0.152, 62.1e3, 1.299, 2289, dG_b)
    y, tmin, pk, n, full, dmax, dmean = yearly[-1]
    print(f"   after 30 winters: {n} cracks per km ({full} full depth, depth max {dmax:.1f} cm), spacing "
          f"{(lens.mean() if len(lens) else float('nan')):.1f} m, Xc {SIGMA_T/tau:.2f} m")

    print("\n9. MnROAD cell 18 timing (h 200 mm, Li Table 4 base; our reference mix, not cell 18's): Minneapolis from 1994")
    sub = [d for d in msp if "1994-07-01" <= d[0] <= "2003-06-30"]
    yearly, lens, tau = run_road(sub, lat_m, 0.200, 62.1e3, 1.299, 2289, dG_m)
    for (y, tmin, pk, n, full, dmax, dmean) in yearly:
        print(f"   winter {y}-{(y+1)%100:02d}: surface min {tmin:+.1f} C, peak {pk:.2f} MPa, cracks {n} per km, "
              f"depth max {dmax:.1f} cm ({full} full depth)")
    print(f"   field: most cracks in winter 1995-96 (-39 C), driving-lane spacing 4.8 m by 2003 (Li & Marasteanu); "
          f"Xc here {SIGMA_T/tau:.2f} m")


if __name__ == "__main__":
    main()
