"""T4 loads chain check (ASPHALT_SCIENCE.md, Model 3). Run: python3 docs/asphalt_checks/loads_chain.py

Every constant is from the source named next to it; "derived" marks our own algebra; "assumption" a choice
with no source. Sections:
  1. Layered elastic solver (Pan, Alkasawneh & Chen 2007, FHWA/OH-2007/12, ch. 7; propagator derived)
     1a. one layer against Boussinesq (Pan Table 1.1, integrated over the loaded circle)
     1b. three layers against Pan's ODOT example beside Everstress 5.0 (Pan figs. 6.5-6.7, read off the plots)
  2. Transfer functions and unbound rutting constants (MOP 2008; NCHRP 1-37A Part 3 ch. 3)
  3. Mix modulus: Mn/DOT 97-06 Table 5.1 (AC-20, 50-blow Marshall) master curve, AMAC shift (Model 2)
  4. The default road: c620 Table 3B, Burlington, 500 ESAL/yr (assumption), 20 years: fatigue and rutting
  5. Wander: NCHRP's five-point average against the full expectation
  6. c620 Table 5 rows at their own traffic; thicker / more traffic trends
  7. 2008 against 2015 constants
"""
import math, os, sys, importlib.util
import numpy as np
from scipy.special import j0, j1
from scipy.optimize import curve_fit

IN = 0.0254; PSI = 6894.757; FT = 0.3048

# ---------------------------------------------------------------- 1. layered elastic solver
# Pan 2007 eqs. 7.12-7.13, state E = [U_L, lam U_M, T_L/lam, T_M] (eq. 7.14a): dE/dz = lam * M E (derived
# from 7.12a, 7.12b, 7.13a, 7.13b). Each layer's propagator is exp(lam z M); M has eigenvalues +1 and -1, each
# twice, so exp(tM) = e^t (I + t(M-I)) P+ + e^-t (I + t(M+I)) P- on the two generalised eigenspaces (derived).
# Writing each layer's solution with e^(lam (z - z_bottom)) and e^(-lam (z - z_top)) keeps every term <= 1:
# Pan's "factor out the exponentially growing factor".

def layer_matrix(E, nu):
    c11 = E*(1-nu)/((1+nu)*(1-2*nu)); c12 = E*nu/((1+nu)*(1-2*nu)); c44 = E/(2*(1+nu))   # Pan eq. 7.3
    M = np.array([[0, c12/c11, 1/c11, 0],
                  [-1, 0, 0, 1/c44],
                  [0, 0, 0, 1],
                  [0, c11 - c12*c12/c11, -c12/c11, 0]], float)
    I = np.eye(4)
    def null(A):
        u, s, vt = np.linalg.svd(A); return vt[-2:].T          # 2-dim generalised eigenspace
    Bp = null((M - I) @ (M - I)); Bm = null((M + I) @ (M + I))
    return M, Bp, Bm, c11, c12

class Structure:
    """layers: list of (thickness m, E Pa, nu); the last thickness is ignored (half-space)."""
    def __init__(self, layers):
        self.h = [l[0] for l in layers[:-1]]
        self.zt = np.concatenate([[0.0], np.cumsum(self.h)])           # top of each layer
        self.mats = [layer_matrix(l[1]/1e6, l[2]) for l in layers]     # work in MPa
        self.n = len(layers)

    def solve(self, lam, q, a):
        """Coefficients for a circular load q (Pa) of radius a (m), for each lam (1/m). Returns (N, 4n-2)."""
        n = self.n; N = len(lam); I = np.eye(4)
        nu = 4*n - 2
        A = np.zeros((N, nu, nu)); rhs = np.zeros((N, nu))
        L = lam[:, None, None]
        def plus(k, s):    # e^(lam s)(I + lam s (M - I)) B+, s = z - z_bottom <= 0
            M, Bp, Bm = self.mats[k][:3]
            return np.exp(lam*s)[:, None, None]*((I + (L*s)*(M - I)) @ Bp)
        def minus(k, s):   # e^(-lam s)(I + lam s (M + I)) B-, s = z - z_top >= 0
            M, Bp, Bm = self.mats[k][:3]
            return np.exp(-lam*s)[:, None, None]*((I + (L*s)*(M + I)) @ Bm)
        col = lambda k: 4*k
        # surface: y3 = T_L/lam = -q a J1(lam a)/lam^2, y4 = T_M = 0 (Pan eqs. 7.17-7.18, our Hankel weighting)
        if n == 1:
            blk = minus(0, 0.0); A[:, 0:2, 0:2] = blk[:, 2:4, :]
        else:
            A[:, 0:2, 0:2] = plus(0, -self.h[0])[:, 2:4, :]; A[:, 0:2, 2:4] = minus(0, 0.0)[:, 2:4, :]
        rhs[:, 0] = -q/1e6*a*j1(lam*a)/lam**2
        row = 2
        for k in range(n - 1):                        # continuity of the state at the bottom of layer k
            hk = self.h[k]
            A[:, row:row+4, col(k):col(k)+2] = plus(k, 0.0)
            A[:, row:row+4, col(k)+2:col(k)+4] = minus(k, hk)
            if k + 1 < n - 1:
                A[:, row:row+4, col(k+1):col(k+1)+2] = -plus(k+1, -self.h[k+1])
                A[:, row:row+4, col(k+1)+2:col(k+1)+4] = -minus(k+1, 0.0)
            else:
                A[:, row:row+4, col(k+1):col(k+1)+2] = -minus(k+1, 0.0)
            row += 4
        return np.linalg.solve(A, rhs[..., None])[..., 0]

    def state(self, lam, coef, z):
        """y(lam) at depth z; z exactly on an interface is taken in the layer above."""
        k = int(np.searchsorted(self.zt[1:], z, side='left')) if self.n > 1 else 0
        k = min(k, self.n - 1)
        M, Bp, Bm, c11, c12 = self.mats[k]; I = np.eye(4); L = lam[:, None, None]
        s_t = z - self.zt[k]
        if k < self.n - 1:
            s_b = z - self.zt[k+1]
            a_ = coef[:, 4*k:4*k+2]; b_ = coef[:, 4*k+2:4*k+4]
            y = (np.exp(lam*s_b)[:, None, None]*((I + (L*s_b)*(M - I)) @ Bp)) @ a_[..., None]
            y = y + (np.exp(-lam*s_t)[:, None, None]*((I + (L*s_t)*(M + I)) @ Bm)) @ b_[..., None]
        else:
            b_ = coef[:, 4*k:4*k+2]
            y = (np.exp(-lam*s_t)[:, None, None]*((I + (L*s_t)*(M + I)) @ Bm)) @ b_[..., None]
        return y[..., 0], c11, c12

def lam_grid(lmax, seg):
    """Composite Gauss-Legendre nodes and weights on [0, lmax], segments of width seg."""
    x, w = np.polynomial.legendre.leggauss(8)
    edges = np.arange(0.0, lmax + seg, seg)
    a_, b_ = edges[:-1], edges[1:]
    lam = (0.5*(b_ - a_)[:, None]*x[None] + 0.5*(b_ + a_)[:, None]).ravel()
    wt = (0.5*(b_ - a_)[:, None]*w[None]).ravel()
    return lam, wt

class Kernel:
    """Bessel tables for fixed radii, reused for every structure."""
    def __init__(self, lam, wt, r):
        self.lam, self.wt, self.r = lam, wt, np.asarray(r, float)
        lr = np.outer(lam, self.r)
        self.J0 = j0(lr); J1 = j1(lr)
        with np.errstate(divide='ignore', invalid='ignore'):
            self.J1r = np.where(self.r[None] > 0, J1/self.r[None], lam[:, None]/2)   # J1(lam r)/r -> lam/2
        self.J1 = J1

    def fields(self, st, coef, z):
        """uz, sigma_zz, eps_zz, eps_rr, eps_tt (SI) at depth z, at each radius, for one circular load."""
        lam, wt = self.lam, self.wt
        y, c11, c12 = st.state(lam, coef, z)
        w = (wt*lam)[:, None]
        uz = (w*y[:, 0:1]*self.J0).sum(0)
        szz = (w*(lam*y[:, 2])[:, None]*self.J0).sum(0)*1e6
        ezz = (w*(lam*(c12*y[:, 1] + y[:, 2])/c11)[:, None]*self.J0).sum(0)
        ett = -(w*y[:, 1:2]*self.J1r).sum(0)
        err = -(w*y[:, 1:2]*(lam[:, None]*self.J0 - self.J1r)).sum(0)
        return uz, szz, ezz, err, ett

def check_boussinesq():
    print("1a. One layer (half-space) against Boussinesq (Pan Table 1.1, point load, integrated over the circle)")
    E, nu, q, a = 100e6, 0.35, 827e3, 0.0877
    st = Structure([(None, E, nu)])
    lam, wt = lam_grid(3000.0, 2.0)
    coef = st.solve(lam, q, a)
    pts = [(0.0, 0.05), (0.0, 0.1), (0.0, 0.3), (0.1, 0.1), (0.2, 0.15)]
    ker = Kernel(lam, wt, [p[0] for p in pts])
    # Boussinesq: Pan eq. 1.1 sigma_z and Table 1.1 eps_z, summed over a polar grid on the disk (derived)
    nr, nt = 120, 180
    rho = (np.arange(nr) + 0.5)/nr*a; th = (np.arange(nt) + 0.5)/nt*2*math.pi
    RHO, TH = np.meshgrid(rho, th, indexing='ij'); dA = (a/nr)*RHO*(2*math.pi/nt); P = q*dA
    worst = 0.0
    for i, (r, z) in enumerate(pts):
        uz, szz, ezz, err, ett = ker.fields(st, coef, z)
        d = np.sqrt((r - RHO*np.cos(TH))**2 + (RHO*np.sin(TH))**2)
        R2 = d*d + z*z; c = z/np.sqrt(R2)
        sz_b = -(3*P*z**3/(2*math.pi*R2**2.5)).sum()
        ez_b = -((1 + nu)*P*c/(2*math.pi*E*R2)*(3*c*c - 2*nu)).sum()
        e1 = abs(szz[i]/sz_b - 1); e2 = abs(ezz[i]/ez_b - 1); worst = max(worst, e1, e2)
        print(f"   r {r:.2f} z {z:.2f} m: sigma_z {szz[i]/1e3:8.1f} kPa (Boussinesq {sz_b/1e3:8.1f}), "
              f"eps_z {ezz[i]*1e6:8.1f} ue ({ez_b*1e6:8.1f})")
    # surface deflection at the centre, closed form 2(1-nu^2) q a / E (integral of Boussinesq, derived)
    ker0 = Kernel(lam, wt, [0.0]); uz0 = ker0.fields(st, coef, 1e-4)[0][0]
    print(f"   centre deflection {uz0*1e3:.3f} mm against 2(1-nu^2)qa/E = {2*(1-nu*nu)*q*a/E*1e3:.3f} mm")
    print(f"   worst stress/strain difference {worst*100:.2f} %")
    return worst

# Pan's text says a circle 4.072 in in diameter; read as the radius the example matches Everstress (a
# 1,628 lb tire would be implausibly light for the class 14-15 truck described): a misprint, by arithmetic.
A_ODOT = 4.072*IN
def check_odot():
    print("1b. Three layers: Pan's ODOT example (Table 6.1-6.2) against Everstress 5.0 read off Pan figs. 6.5-6.7")
    layers = [(18*IN, 350e3*PSI, 0.35), (6*IN, 30e3*PSI, 0.35), (None, 4.8e3*PSI, 0.44)]
    st = Structure(layers); q = 125*PSI; a = A_ODOT
    loads = [(4.5,59),(14,59),(34,59),(43.5,59),(75,59),(84.5,59),(104.5,59),(114.5,59),(134,59),(143.5,59),
             (163.5,59),(173,59),(204.5,59),(214,59),(234,59),(243.5,59),(75,118),(84.5,118),(104.5,118),(114,118)]
    px, py = 43.5, 59.0
    vec = [((px - lx)*IN, (py - ly)*IN) for lx, ly in loads]
    r = [math.hypot(*v) for v in vec]
    lam, wt = lam_grid(1500.0, 0.25)
    coef = st.solve(lam, q, a); ker = Kernel(lam, wt, r)
    read = {0.0: (-145, -30, 0.107), 17.999: (45, -80, None), 18.2: (0, -210, None), 21.0: (0, -210, None),
            24.0: (-3, -235, None)}
    for zin, (sxx_r, ezz_r, uz_r) in read.items():
        uz, szz, ezz, err, ett = ker.fields(st, coef, max(zin, 0.02)*IN)
        k = int(np.searchsorted(st.zt[1:], zin*IN, side='left')); k = min(k, 2)
        E, nu = layers[k][1], layers[k][2]
        c11 = E*(1-nu)/((1+nu)*(1-2*nu)); c12 = E*nu/((1+nu)*(1-2*nu))
        sxx = 0.0
        for (vx, vy), ri, er, et, ez in zip(vec, r, err, ett, ezz):
            cs = vx/ri if ri > 0 else 1.0; sn = vy/ri if ri > 0 else 0.0
            exx = er*cs*cs + et*sn*sn; eyy = er*sn*sn + et*cs*cs
            sxx += c11*exx + c12*(eyy + ez)
        line = f"   z {zin:6.3f} in: sigma_xx {sxx/PSI:7.1f} psi (read {sxx_r:5.0f}), eps_zz {ezz.sum()*1e6:7.1f} ue (read {ezz_r:5.0f})"
        if uz_r: line += f", uz {uz.sum()/IN:.4f} in (read {uz_r})"
        print(line)

# ---------------------------------------------------------------- 2. transfer functions, unbound constants
def CH_bottom(H): return 1/(0.000398 + 0.003602/(1 + math.exp(11.02 - 3.49*H)))        # MOP 5-4d, H in in
def C2s(H): return -2.40874 - 39.748*(1 + H)**-2.856                                     # MOP 5-6c
def FC_2008(DI, H):                                                                       # MOP 5-6a
    c2 = C2s(H); c1 = -2*c2
    return 6000/(1 + math.exp(c1 + c2*math.log10(max(DI, 1e-12)*100)))/60
def FC_2015(DI, H, percent_twice=False):                                                  # MassDOT eq. 24
    c2 = C2s(H); c1 = -2*c2; C2 = 2.1585 if H < 5 else (0.867 + 0.867*H if H <= 12 else 3.9666)
    x = max(DI, 1e-12)*100*(100 if percent_twice else 1)
    return 6000/(1 + math.exp(1.31*c1 + C2*c2*math.log10(x)))/60

def unbound_consts(Wc):
    """1-37A eqs. 3.3.10a-d: beta, rho, eps0/epsr (read as a ratio, see Model 3)."""
    beta = 10**(-0.61119 - 0.017638*Wc)
    Co = math.log(0.15/20.0)
    rho = 1e9*(Co/(1 - (1e9)**beta))**(1/beta)
    t1 = math.exp(rho**beta)*0.15; t2 = math.exp((rho/1e9)**beta)*20.0
    return beta, rho, (t1 + t2)/2, t1, t2
def water_content(Mr_psi, GWT_ft): return 51.712*((Mr_psi/2555.0)**(1/0.64))**(-0.3586*GWT_ft**0.1192)   # 3.3.10e

def check_transfer():
    print("2. Transfer functions (3 in asphalt) and unbound constants")
    H = 3.0
    print(f"   CH {CH_bottom(H):.1f}, C2* {C2s(H):.4f}, C1* {-2*C2s(H):.4f}")
    print("   DI      FC 2008  FC 2015 (fraction)  FC 2015 (MassDOT's x100 twice)")
    for DI in (0.001, 0.01, 0.1, 0.164, 1.0):
        print(f"   {DI:<7} {FC_2008(DI,H):7.2f}  {FC_2015(DI,H):7.2f}             {FC_2015(DI,H,True):7.2f}")
    for Wc in (7, 10, 18):
        b, rho, r, t1, t2 = unbound_consts(Wc)
        print(f"   Wc {Wc:2d} %: beta {b:.4f}, rho {rho:.4g}, eps0/epsr {r:.2f} (terms {t1:.2f}, {t2:.2f})")
    print(f"   Wc: subgrade CBR 9 (Mr {2555*9**0.64:.0f} psi) at GWT 10 ft {water_content(2555*9**0.64,10):.1f} %; "
          f"base 40,000 psi {water_content(40000,10):.1f} %")

# ---------------------------------------------------------------- 3. mix modulus (97-06 Table 5.1) and AMAC
# Mn/DOT 97-06 Table 5.1, AC 20, 50-blow Marshall, resilient modulus MPa (ASTM D4123). Columns: load duration
# 0.1 s at 0.33/0.5/1.0 Hz; load duration 1.0 s at 0.33/0.5 and 0.033/0.05/0.1 Hz.
T51 = {-18: ([12062, 13372, 15145], [13641, 14000, 9662, 11683, 12186]),
       1:   ([6648, 7021, 7662],    [6159, 6276, 4193, 4821, 6235]),
       25:  ([2193, 2441, 2614],    [1366, 1483, 1372, 1393, 1389]),
       40:  ([703, 800, 717],       [366, 338, 345, 345, 345])}
TREF = 25.0
def sigmoid(X, d, al, be, ga, a1, a2):
    t, T = X
    ltr = np.log10(t) - (a1*(T - TREF) + a2*(T - TREF)**2)
    return d + al/(1 + np.exp(be + ga*ltr))
def fit_mix():
    t, T, y = [], [], []
    for TT, (s01, s10) in T51.items():
        for v in s01: t.append(0.1); T.append(TT); y.append(math.log10(v*1e6))
        for v in s10: t.append(1.0); T.append(TT); y.append(math.log10(v*1e6))
    X = (np.array(t), np.array(T, float)); y = np.array(y)
    # The free six-parameter fit degenerates (asymptotes run off to +-1000): -18 to 40 C and 0.1 to 1 s don't fix
    # the sigmoid's ends. Bounded (assumption): lower end 1 MPa or more, upper 25 GPa or less (10^10.4 Pa). The
    # result barely moves with these bounds (printed in main: about 5 % at the largest AMAC shift).
    def fit(lo, cap):
        lb = [lo, 0.5, -5, 0.05, -0.5, -0.01]; ub = [8.5, cap - lo, 5, 3, 0, 0.01]
        q_, _ = curve_fit(sigmoid, X, y, p0=[lo + 0.5, cap - lo - 0.6, -0.5, 0.5, -0.12, 0.0], bounds=(lb, ub), maxfev=100000)
        return q_
    p = fit(6.0, 10.4); res = y - sigmoid(X, *p)
    alt = [fit(lo, cap) for lo, cap in ((7.0, 10.2), (7.0, 10.6), (6.0, 10.2))]
    return p, res, alt
def mix_E(p, T, t=0.1, log_aA=0.0):
    """Pa. Model 2's AMAC: the aged mix at reduced time t/(aT aA) (NCHRP 973 eq. 51, c = 1.71)."""
    d, al, be, ga, a1, a2 = p
    ltr = math.log10(t) - (a1*(T - TREF) + a2*(T - TREF)**2) - log_aA
    return 10**(d + al/(1 + math.exp(be + ga*ltr)))

# ---------------------------------------------------------------- T2 pieces (binder_ageing_chain.py)
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bac", os.path.join(here, "binder_ageing_chain.py"))
_argv = sys.argv; sys.argv = [sys.argv[0]]; bac = importlib.util.module_from_spec(spec); spec.loader.exec_module(bac); sys.argv = _argv
BURL_HI_F = [28.9, 31.5, 40.9, 55.3, 69.0, 77.6, 82.4, 80.7, 72.6, 58.9, 46.4, 35.0]   # SiteClimate burlington_vt
BURL_LO_F = [12.9, 14.3, 23.6, 35.9, 47.8, 57.3, 62.4, 60.7, 52.9, 41.8, 32.1, 21.3]
BURL_LAT = 44.4683
def monthly_quintiles(H_mm):
    """C, 12 x 5: the month's hourly pavement temperature at depth H (T2's daily cycle on FHWA-RD-97-103 eqs. 7, 8),
    as normal deviates -1.2816, -0.5244, 0, 0.5244, 1.2816 (1-37A fig. 3.3.18)."""
    tx = [(f - 32)/1.8 for f in BURL_HI_F]; tn = [(f - 32)/1.8 for f in BURL_LO_F]
    out = []
    for m in range(12):
        hi = bac.t_high(tx[m], BURL_LAT, H_mm); lo = bac.t_low(tn[m], BURL_LAT, H_mm)
        hrs = []
        for h in range(24):
            s = (1 - math.cos(math.pi*(h - 6)/9))/2 if 6 <= h <= 15 else (1 + math.cos(math.pi*((h - 15) % 24)/15))/2
            hrs.append(lo + (hi - lo)*s)
        mu, sd = np.mean(hrs), np.std(hrs)
        out.append([mu + zq*sd for zq in (-1.2816, -0.5244, 0.0, 0.5244, 1.2816)])
    return np.array(out)
def binder_ap(years=20, HPG=64.0):
    """Surface ageing AP(t) by year, Burlington (bac.run's kinetics, without printing)."""
    tx = [(f - 32)/1.8 for f in BURL_HI_F]; tn = [(f - 32)/1.8 for f in BURL_LO_F]
    M = 0.94/(1 + (HPG/82.68)**7.96)
    mid = [15.2 + 30.4*m for m in range(12)]
    def interp(arr, d):
        for m in range(12):
            a_ = mid[m]; dd = d if d >= mid[0] else d + 365
            if a_ <= dd < a_ + 30.4 or m == 11: return arr[m] + (arr[(m+1) % 12] - arr[m])*min(max((dd - a_)/30.4, 0), 1)
    x = 0.0; out = {}
    for y in range(years):
        for d in range(365):
            hi = bac.t_high(interp(tx, d), BURL_LAT, 0); lo = bac.t_low(interp(tn, d), BURL_LAT, 0)
            for h in range(24):
                s = (1 - math.cos(math.pi*(h - 6)/9))/2 if 6 <= h <= 15 else (1 + math.cos(math.pi*((h - 15) % 24)/15))/2
                T = lo + (hi - lo)*s + 273.15
                if T < 293.15: continue
                x = bac.F(bac.teq(x, T, M) + 1/24.0, T, M)
        out[y + 1] = x/M
    return out
def delta_log_g(AP, z_cm, HPG=64.0):
    """NCHRP 973 eq. 22: log|G*|(z, t) - log|G*|0."""
    g0 = 6.552/(1 + (HPG/107.167)**-4.068); M = 0.94/(1 + (HPG/82.68)**7.96)
    N = 0.477*math.exp(-0.226*AP[10]); APmax = (4.5 - g0)/M
    return lambda yr: M*((0.916*z_cm + APmax)/(z_cm + 1))*(1 - math.exp(-N*AP[yr]))

# ---------------------------------------------------------------- 4-7. the chain
KF = dict(y2008=dict(kf1=0.007566, kf2=-3.9492, kf3=-1.281, k1r=-3.35412, kN=0.4791, kT=1.5606, b1r=1.0,
                     ks_gran=1.673, ks_fine=1.35),
          y2015=dict(kf1=3.75*0.02054, kf2=-2.87*1.38, kf3=-1.46*0.88, k1r=-2.45, kN=0.22*1.36, kT=3.01*0.52,
                     b1r=0.40, ks_gran=0.965, ks_fine=0.675))     # 2015: 5 in or less (MassDOT figs. 1, 2, 36)

class Road:
    def __init__(self, H_in, base_in, cbr, esal_yr, years=20, mixp=None, AP=None, GWT_ft=10.0,
                 subgrade='fine', base_mr_psi=40000.0, nu=0.35, sample_years=(1, 5, 10, 20)):
        self.H, self.base, self.cbr, self.esal, self.years = H_in, base_in, cbr, esal_yr, years
        self.mixp, self.AP, self.GWT, self.sub, self.nu = mixp, AP, GWT_ft, subgrade, nu
        self.Ebase = base_mr_psi*PSI; self.Esub = 2555*cbr**0.64*PSI                     # MOP Table 11-10; 1-37A L2
        # asphalt sublayers, 1-37A fig. 3.3.9: 0.5, 0.5, then 1 in to 4 in, 4 in to 8 in, the rest
        hs, z = [], 0.0
        for step in [0.5, 0.5] + [1.0]*3 + [4.0] + [100]:
            if z >= H_in - 1e-9: break
            d = min(step, H_in - z); hs.append(d); z += d
        self.hs = hs
        self.zmid = np.cumsum(hs) - np.array(hs)/2
        self.samples = sample_years
        self.Tq = [monthly_quintiles(zm*IN*1000) for zm in self.zmid]                       # per sublayer, 12 x 5
        self.dlg = [delta_log_g(AP, zm*IN*100) for zm in self.zmid]
        # unbound evaluation depths (in): base middle; subgrade top, 6 in, then middles of >= 12 in sublayers to 8 ft
        top_sg = H_in + base_in
        self.zb = [H_in + base_in/2]
        n_sg = max(1, int((96 - top_sg)//12)); hsg = (96 - top_sg)/n_sg
        self.sg_mid = [top_sg + hsg*(i + 0.5) for i in range(n_sg)]; self.hsg = hsg
        self.zsg = [top_sg + 1e-3, top_sg + 6.0] + self.sg_mid + [96.0]
        bw = water_content(base_mr_psi, GWT_ft); sw = water_content(2555*cbr**0.64, GWT_ft)
        self.ub_base = unbound_consts(bw); self.ub_sg = unbound_consts(sw); self.Wc = (bw, sw)

    def structure(self, yr, m, qi):
        layers, Es = [], []
        for k, h in enumerate(self.hs):
            E = mix_E(self.mixp, self.Tq[k][m][qi], 0.1, 1.71*self.dlg[k](yr))
            layers.append((h*IN, E, self.nu)); Es.append(E)
        layers.append((self.base*IN, self.Ebase, self.nu)); layers.append((None, self.Esub, self.nu))
        return Structure(layers), Es

def responses(road, ker, xs, tires, yr, m, qi):
    st, Es = road.structure(yr, m, qi)
    coef = st.solve(ker.lam, 827.4e3, 0.0877)
    nx = len(xs); nt = len(tires)
    def at(z_in):
        uz, szz, ezz, err, ett = ker.fields(st, coef, z_in*IN)
        ezz = ezz.reshape(nt, nx).sum(0); exx = err.reshape(nt, nx).sum(0); eyy = ett.reshape(nt, nx).sum(0)
        return exx, eyy, ezz
    out = {}
    exx, eyy, _ = at(road.H - 1e-4)
    out['et'] = np.maximum(np.maximum(exx, eyy), 0.0); out['Ebot'] = Es[-1]
    a02 = 0.2*0.0877/IN                                             # 1-37A p. 3.3.63: shallow sublayers interpolated
    ez_s = at(0.05*0.0877/IN)[2]; ez_02 = at(a02)[2]
    er = []
    for k, zm in enumerate(road.zmid):
        if zm < a02: e = ez_s + (ez_02 - ez_s)*(zm - 0.05*0.0877/IN)/(a02 - 0.05*0.0877/IN)
        else: e = at(zm)[2]
        er.append(np.maximum(-e, 0.0))
    out['er'] = er
    out['eb'] = [np.maximum(-at(z)[2], 0.0) for z in road.zb]
    out['esg'] = [np.maximum(-at(z)[2], 0.0) for z in road.zsg]
    return out

def run_road(road, xs, consts='y2008', verbose=False, cache=None):
    """Fatigue damage per pass profile g(x) and rut profiles, year by year (strain hardening per point)."""
    K = KF[consts]
    tires = [-0.1525, 0.1525]                                  # duals 12 in apart (MOP p. 82); other wheel set ignored
    r = np.abs(np.subtract.outer(np.array(tires), xs)).ravel()
    if cache is None or 'ker' not in cache:
        lam, wt = lam_grid(30/(0.05*0.0877), 3.0)
        ker = Kernel(lam, wt, r)
        if cache is not None: cache['ker'] = ker
    ker = cache['ker'] if cache else ker
    # responses at sample years, interpolated in log between them (check approximation)
    R = {}
    for yr in road.samples:
        R[yr] = [[responses(road, ker, xs, tires, yr, m, qi) for qi in range(5)] for m in range(12)]
    def resp(yr):
        ys = road.samples
        if yr in R: return R[yr]
        lo = max(y for y in ys if y < yr); hi = min(y for y in ys if y > yr); f = (yr - lo)/(hi - lo)
        mix = lambda A, B: A*(1 - f) + B*f
        out = []
        for m in range(12):
            row = []
            for qi in range(5):
                a_, b_ = R[lo][m][qi], R[hi][m][qi]
                row.append(dict(et=mix(a_['et'], b_['et']), Ebot=a_['Ebot']**(1-f)*b_['Ebot']**f,
                                er=[mix(u, v) for u, v in zip(a_['er'], b_['er'])],
                                eb=[mix(u, v) for u, v in zip(a_['eb'], b_['eb'])],
                                esg=[mix(u, v) for u, v in zip(a_['esg'], b_['esg'])]))
            out.append(row)
        return out
    C = 10**(4.84*(12.1/(3.2 + 12.1) - 0.69))                  # cell 18 wear course: Va 3.2, Vbe 12.1 (Mn/DOT 97-06 Table 3.5)
    CH = CH_bottom(road.H)
    n_sub = road.esal/12/5                                     # passes per month-quintile
    g = np.zeros(len(xs))                                      # damage per year without wander, accumulated
    nsl = len(road.hs)
    ep_ac = np.zeros((nsl, len(xs))); ep_b = np.zeros((len(road.zb), len(xs))); ep_sg = np.zeros((len(road.zsg), len(xs)))
    ks_sg = K['ks_fine'] if road.sub == 'fine' else K['ks_gran']
    hist = {}
    for yr in range(1, road.years + 1):
        Ryr = resp(yr)
        for m in range(12):
            for qi in range(5):
                rr = Ryr[m][qi]
                et = np.maximum(rr['et'], 1e-9)
                Nf = K['kf1']*C*CH*et**K['kf2']*(rr['Ebot']/PSI)**K['kf3']
                g += n_sub/Nf
                # asphalt rutting, MOP 5-1a with strain hardening (1-37A fig. 3.3.19)
                for k in range(nsl):
                    TF = road.Tq[k][m][qi]*1.8 + 32
                    if TF <= 0: continue                         # T^1.56 undefined at or below 0 F (gap)
                    D = road.zmid[k]; H = road.H
                    c1 = -0.1039*H*H + 2.4868*H - 17.342; c2 = 0.0172*H*H - 1.7331*H + 27.428
                    kz = (c1 + c2*D)*0.328196**D
                    er = np.maximum(rr['er'][k], 1e-12)
                    A = K['b1r']*kz*10**K['k1r']*TF**K['kT']*er
                    Neq = (ep_ac[k]/A)**(1/K['kN'])
                    ep_ac[k] = A*(Neq + n_sub)**K['kN']
                # unbound: 1-37A eq. 3.3.9 with strain hardening
                for arr, ev_list, ub, ks in ((ep_b, rr['eb'], road.ub_base, K['ks_gran']), (ep_sg, rr['esg'], road.ub_sg, ks_sg)):
                    beta, rho, e0r = ub[0], ub[1], ub[2]
                    for k, ev in enumerate(ev_list):
                        A = ks*np.maximum(ev, 1e-12)*e0r
                        with np.errstate(divide='ignore'):
                            ratio = np.clip(arr[k]/A, 1e-300, 1 - 1e-12)
                            Neq = np.where(arr[k] > 0, rho/(-np.log(ratio))**(1/beta), 0.0)
                        arr[k] = A*np.exp(-(rho/(Neq + n_sub))**beta)
        # rut depths (in) without wander
        rd_ac = (ep_ac*np.array(road.hs)[:, None]).sum(0)
        rd_b = ep_b[0]*road.base
        # subgrade: sublayers to 8 ft, then the half-space below 8 ft (1-37A eqs. 3.3.18-3.3.23, no bedrock)
        rd_sg = sum(ep_sg[2 + i]*road.hsg for i in range(len(road.sg_mid)))
        # 1-37A eq. 3.3.20 takes k from the top of the subgrade and 6 in down and floors it at 1e-6; away from the
        # wheels the strain grows with depth there, k hits the floor and, with no bedrock, eq. 3.3.23 is unbounded
        # (here up to metres). Derived replacement: k from the two deepest computed points (89.6 and 96 in, where the
        # strain falls everywhere); 1-37A's k kept for comparison (printed).
        k137 = np.log(np.maximum(ep_sg[0], 1e-15)/np.maximum(ep_sg[1], 1e-15))/6.0
        kk = np.log(np.maximum(ep_sg[-2], 1e-15)/np.maximum(ep_sg[-1], 1e-15))/(road.zsg[-1] - road.zsg[-2])
        kk = np.maximum(kk, 1e-3)
        deep = ep_sg[-1]/kk
        rd_sg = rd_sg + deep
        hist[yr] = dict(g=g.copy(), ac=rd_ac, b=rd_b, sg=rd_sg, deep=deep, k137=k137)
    return hist

def wander(profile, xs, sd=0.254):
    """Expectation over N(0, sd) of a profile on xs (ICT-20-010 fig. 27, no truncation)."""
    dx = xs[1] - xs[0]; k = np.arange(-int(4*sd/dx), int(4*sd/dx) + 1)*dx
    w = np.exp(-0.5*(k/sd)**2); w /= w.sum()
    return np.convolve(profile, w, mode='same')
def five_point(profile, xs, sd=0.254):
    """NCHRP 2004 (1-37A eq. 3.3.2): average of the profile shifted to the five quintile offsets."""
    out = np.zeros_like(profile)
    for z in (-1.28155, -0.5244, 0.0, 0.5244, 1.28155):
        out += 0.2*np.interp(xs - z*sd, xs, profile)
    return out

def main():
    w1 = check_boussinesq(); print(); check_odot(); print(); check_transfer(); print()
    p, res, alt = fit_mix()
    print("3. Mix modulus: sigmoid fit to Mn/DOT 97-06 Table 5.1 (AC-20, 50 blow), 0.1 s and 1.0 s, -18 to 40 C")
    print(f"   delta {p[0]:.3f}, alpha {p[1]:.3f}, beta {p[2]:.3f}, gamma {p[3]:.3f}, a1 {p[4]:.4f}, a2 {p[5]:.6f}; "
          f"rms residual {np.sqrt((res**2).mean()):.3f} log units; limits {10**p[0]/1e6:.0f} to {10**(p[0]+p[1])/1e6:.0f} MPa")
    spread = [mix_E(q_, 25, 0.1, 4.6)/mix_E(p, 25, 0.1, 4.6) - 1 for q_ in alt]
    print(f"   other bounds change E(25 C, log aA 4.6) by {min(spread)*100:+.1f} to {max(spread)*100:+.1f} %")
    for T in (-18, 1, 10, 25, 40, 50):
        m01 = np.mean(T51[T][0]) if T in T51 else float('nan')
        print(f"   {T:4d} C: E(0.1 s) {mix_E(p, T)/1e6:7.0f} MPa (measured mean {m01:7.0f})")
    print("   AMAC with T2's ageing (Burlington, PG 64-22), E at 25 C, 0.1 s:")
    AP = binder_ap(20)
    for z in (0.0, 1.27, 3.8, 7.0):
        f = delta_log_g(AP, z)
        row = []
        for yr in (1, 5, 10, 20):
            la = 1.71*f(yr); row.append(f"{yr} yr: dlogG {f(yr):.2f}, log aA {la:.2f}, E {mix_E(p, 25, 0.1, la)/1e6:5.0f}")
        print(f"   z {z:4.2f} cm: " + "; ".join(row))
    print()
    xs = np.arange(-0.9, 0.9001, 0.03) + 0.003               # across the wheel path, centred on the duals
    cache = {}
    print("4. Default road: c620 Table 3B (3.0 in on 4.0 in, CBR 9), Burlington, 500 ESAL/yr (assumption), 2008 constants")
    road = Road(3.0, 4.0, 9, 500, mixp=p, AP=AP)
    print(f"   asphalt sublayers {road.hs} in; Wc base {road.Wc[0]:.1f} %, subgrade {road.Wc[1]:.1f} % (GWT 10 ft, assumption); "
          f"subgrade Mr {road.Esub/1e6:.0f} MPa, fine-grained (assumption)")
    st, Es = road.structure(10, 6, 2)
    print("   July median, year 10, sublayer E (MPa): " + ", ".join(f"{E/1e6:.0f}" for E in Es))
    h = run_road(road, xs, cache=cache)
    for yr in (1, 5, 10, 15, 20):
        d = h[yr]; DI = wander(d['g'], xs).max(); DI0 = d['g'].max()
        tot = wander(d['ac'] + d['b'] + d['sg'], xs)
        i = tot.argmax()
        print(f"   year {yr:2d}: DI {DI:.3g} (no wander {DI0:.3g}), FC {FC_2008(DI, 3.0):5.1f} % lane; deep subgrade term {wander(d['deep'],xs)[tot.argmax()]*25.4:.2f} mm (1-37A k {d['k137'][len(xs)//2]:.3f}/in under the duals, {d['k137'].min():.3f} at worst); rut "
              f"{tot.max()*25.4:5.1f} mm = asphalt {wander(d['ac'],xs)[i]*25.4:4.1f} + base {wander(d['b'],xs)[i]*25.4:4.1f} "
              f"+ subgrade {wander(d['sg'],xs)[i]*25.4:4.1f}")
    d = h[20]
    print("5. Wander, year 20, at the peak: fatigue DI full expectation {:.3g}, five-point {:.3g}; rut (expectation of the "
          "profile) {:.1f} mm, five-point {:.1f} mm".format(wander(d['g'], xs).max(), five_point(d['g'], xs).max(),
          wander(d['ac']+d['b']+d['sg'], xs).max()*25.4, five_point(d['ac']+d['b']+d['sg'], xs).max()*25.4))
    prof = wander(d['ac'] + d['b'] + d['sg'], xs)*25.4
    print("   rut profile across the wheel path (mm), every 0.1 m from -0.9: " + " ".join(f"{v:.1f}" for v in prof[::5]))
    print()
    print("6. Trends and c620 Table 5 rows (20 years, Burlington; Fair CBR 6-9 taken as 9); 7. 2015 constants")
    specs = [("trend", 3.0, 4.0, 5000, 'y2008'), ("trend", 4.0, 4.0, 5000, 'y2008'), ("trend", 3.0, 8.0, 5000, 'y2008')]
    specs += [("t5", H, B, tot/20, 'y2008') for H, B, tot in ((2.5, 8.5, 10000), (3.5, 11.0, 50000), (4.0, 12.0, 100000),
                                                               (4.5, 13.0, 250000), (5.5, 9.5, 500000), (6.0, 15.5, 1000000))]
    specs += [("y2015", 3.0, 4.0, 500, 'y2015')]
    from multiprocessing import Pool
    with Pool(4) as pool:
        outs = pool.map(_run_spec, [(sp, p, AP, xs) for sp in specs])
    for (kind, H, B, E_, c), (FC, FCx, rut, parts) in zip(specs, outs):
        if kind == "trend":
            print(f"   {H} in on {B} in, {E_:>6.0f} ESAL/yr: FC {FC:5.1f} %, rut {rut:5.1f} mm ({parts})")
        elif kind == "t5":
            print(f"   Table 5 {H}/{B} in at {E_*20:>7.0f} ESAL: FC {FC:5.1f} % (MOP limit 35 % for 'others'), rut {rut:5.1f} mm "
                  f"(limit 16.5 mm) ({parts})")
        else:
            print(f"   2015 constants, default road, year 20: FC {FC:.1f} % (fraction) / {FCx:.1f} % (x100 twice); rut {rut:.1f} mm ({parts})")

def _run_spec(args):
    (kind, H, B, E_, consts), p, AP, xs = args
    rd = Road(H, B, 9, E_, mixp=p, AP=AP)
    d = run_road(rd, xs, consts=consts, cache={})[20]
    DI = wander(d['g'], xs).max(); tot = wander(d['ac'] + d['b'] + d['sg'], xs); i = tot.argmax()
    parts = f"asphalt {wander(d['ac'], xs)[i]*25.4:.1f}, base {wander(d['b'], xs)[i]*25.4:.1f}, subgrade {wander(d['sg'], xs)[i]*25.4:.1f}"
    if consts == 'y2015':
        return FC_2015(DI, H), FC_2015(DI, H, True), tot.max()*25.4, parts
    return FC_2008(DI, H), None, tot.max()*25.4, parts

if __name__ == "__main__":
    main()
