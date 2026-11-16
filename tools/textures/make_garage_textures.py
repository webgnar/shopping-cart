"""Paints the parking garage's tileable textures: colour, OpenGL normal and roughness maps, 1024 px JPGs.

    python3 tools/textures/make_garage_textures.py [name ...]

Writes shopping-cart/assets/textures/garage/<name>_{color,normal,rough}.jpg. Every map tiles seamlessly: all
noise is made in the frequency domain (so it wraps), and stains, cracks and chips are drawn with wrap-around.
The materials in shopping-cart/assets/materials/garage/ use them with triplanar mapping (world-aligned for the
building, object-aligned for props), so no UVs are needed. Each texture's real size in metres is in TILE_M
and is what the material's uv1_scale is set from (scale = 1 / metres).

Why painted here and not TextureCan / ambientCG: those sites aren't reachable from the cloud builds, and a
script keeps the look editable and in git. Same seed, same pixels.
"""
import os, sys
import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "shopping-cart", "assets", "textures", "garage")
N = 1024

TILE_M = {   # metres one texture tile covers
    "concrete_deck": 4.0, "concrete_wall": 2.4, "concrete_pillar": 1.6, "asphalt": 3.0,
    "paint_yellow": 2.0, "paint_white": 2.0, "rubber": 0.5, "dark_metal": 1.0, "brushed_metal": 0.6,
    "galvanized": 1.0, "sign_paint": 0.8, "seat_fabric": 0.3, "car_paint": 2.0, "red_paint": 0.8,
    "drum_paint": 1.2,
}


def rng(name):
    return np.random.default_rng(sum(map(ord, name)) * 7919)


def noise(r, scale, aniso=(1.0, 1.0), octave_falloff=1.0):
    """Tileable fractal noise in [0, 1]: white noise filtered in the frequency domain. `scale` = feature size
    in pixels; `aniso` stretches features along (y, x)."""
    w = r.standard_normal((N, N))
    fy = np.fft.fftfreq(N)[:, None] * aniso[0]
    fx = np.fft.fftfreq(N)[None, :] * aniso[1]
    f = np.sqrt(fx ** 2 + fy ** 2) * scale
    amp = 1.0 / (1.0 + f ** (2.0 * octave_falloff))
    amp[0, 0] = 0
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    n -= n.min()
    return n / n.max()


def blobs(r, count, rmin, rmax, soft=0.5):
    """Tileable soft round spots (stains, pores), 0..1, stamped with wrap-around."""
    out = np.zeros((N, N))
    for _ in range(count):
        cy, cx = r.uniform(0, N, 2)
        rad = r.uniform(rmin, rmax)
        sq = r.uniform(0.6, 1.4)
        k = int(np.ceil(rad / min(sq, 1.0))) + 2
        oy = np.arange(-k, k + 1)
        ys = (np.floor(cy).astype(int) + oy) % N
        xs = (np.floor(cx).astype(int) + oy) % N
        dy = (np.floor(cy) + oy - cy)[:, None]
        dx = (np.floor(cx) + oy - cx)[None, :]
        d = np.sqrt(dx ** 2 + (dy * sq) ** 2) / rad
        v = np.clip((1 - d) / soft, 0, 1)
        sub = out[np.ix_(ys, xs)]
        out[np.ix_(ys, xs)] = np.maximum(sub, v)
    return out


def cracks(r, count, length, width=1.2):
    """Tileable hairline cracks: wandering random walks drawn with wrap-around, 0..1."""
    out = np.zeros((N, N))
    for _ in range(count):
        y, x = r.uniform(0, N, 2)
        ang = r.uniform(0, 2 * np.pi)
        for _ in range(int(length)):
            ang += r.normal(0, 0.25)
            y += np.sin(ang)
            x += np.cos(ang)
            for oy in range(-1, 2):
                for ox in range(-1, 2):
                    d = np.hypot(oy, ox)
                    v = max(0.0, 1 - d / width)
                    iy, ix = int(y + oy) % N, int(x + ox) % N
                    out[iy, ix] = max(out[iy, ix], v)
            if r.random() < 0.004:   # branch
                ang += r.choice([-1, 1]) * 0.9
    return out


def normal_from_height(h, strength):
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    n = np.dstack([-gx, gy, np.ones_like(h)])   # OpenGL convention (green up)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, color, height, rough, strength):
    os.makedirs(OUT, exist_ok=True)
    c = np.clip(color, 0, 1)
    Image.fromarray((c * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_color.jpg"), quality=90)
    Image.fromarray(normal_from_height(height, strength)).save(os.path.join(OUT, name + "_normal.jpg"), quality=92)
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_rough.jpg"), quality=90)
    print("TEXTURE %-16s %.1f m tile" % (name, TILE_M[name]))


def tint(gray, rgb):
    return gray[..., None] * np.array(rgb)[None, None, :]


# ------------------------------------------------------------------ textures

def concrete_deck():
    r = rng("concrete_deck")
    mott = noise(r, 120)
    mid = noise(r, 18)
    grain = r.random((N, N))
    # oil drips: a few large soft patches broken up by noise, so they read as stains rather than dots
    stains = np.clip(blobs(r, 7, 40, 110, 1.0) * (noise(r, 14) * 1.6 - 0.3), 0, 1) * 0.8
    tyre = noise(r, 60, aniso=(0.08, 1.0))            # long smears along the drive direction
    crk = cracks(r, 5, 380)
    g = 0.56 + 0.10 * (mott - 0.5) + 0.05 * (mid - 0.5) + 0.05 * (grain - 0.5)
    g = g * (1 - 0.45 * stains) * (1 - 0.10 * np.clip(tyre - 0.55, 0, 1) * 4) * (1 - 0.5 * crk)
    color = tint(g, (1.0, 0.985, 0.95))
    h = 0.5 * mid + 0.25 * grain - 1.2 * crk
    rough = 0.88 + 0.06 * (mid - 0.5) - 0.45 * stains
    save("concrete_deck", color, h, rough, 2.5)


def concrete_wall():
    r = rng("concrete_wall")
    mott = noise(r, 140)
    pores = blobs(r, 900, 1.0, 2.6, 0.9)
    grain = r.random((N, N))
    streak = noise(r, 30, aniso=(0.04, 1.0)) * noise(r, 200)   # water streaks running down
    yy, xx = np.mgrid[0:N, 0:N]
    plank = np.minimum(1.0, np.abs(((yy / (N / 4.0)) % 1.0) - 0.0) * 160) * np.minimum(1.0, np.abs(1 - (yy / (N / 4.0)) % 1.0) * 160)
    cy = (yy % (N // 4)) - N / 8
    cx = (xx % (N // 4)) - N / 8
    tie = np.clip(1 - np.hypot(cy, cx) / 7.0, 0, 1)   # form-tie holes on a 0.6 m grid
    g = 0.68 + 0.08 * (mott - 0.5) + 0.04 * (grain - 0.5) - 0.18 * np.clip(streak - 0.45, 0, 1) * 2
    g = g * (0.82 + 0.18 * plank) * (1 - 0.5 * pores) * (1 - 0.6 * tie)
    color = tint(g, (1.0, 0.99, 0.965))
    h = 0.3 * grain + 0.6 * plank - 0.8 * pores - 1.0 * tie
    rough = 0.9 - 0.08 * streak
    save("concrete_wall", color, h, rough, 2.0)


def concrete_pillar():
    r = rng("concrete_pillar")
    mott = noise(r, 90)
    pores = blobs(r, 500, 0.8, 2.0, 0.9)
    streak = noise(r, 20, aniso=(0.05, 1.0))
    grime = noise(r, 60, aniso=(0.2, 1.0))
    grain = r.random((N, N))
    g = 0.78 + 0.06 * (mott - 0.5) + 0.03 * (grain - 0.5) - 0.12 * np.clip(streak - 0.5, 0, 1) * 2 - 0.06 * grime
    g *= 1 - 0.45 * pores
    color = tint(g, (1.0, 0.99, 0.97))
    save("concrete_pillar", color, 0.3 * grain - 0.8 * pores, 0.85 - 0.05 * streak, 1.6)


def asphalt():
    r = rng("asphalt")
    stones = blobs(r, 5000, 1.5, 4.0, 0.7)
    light = blobs(r, 1500, 1.0, 3.0, 0.6)
    mott = noise(r, 150)
    crk = cracks(r, 4, 300, 1.5)
    patch = np.clip((noise(r, 220) - 0.72) * 8, 0, 1)
    g = 0.17 + 0.05 * (mott - 0.5) + 0.06 * stones + 0.12 * light
    g = g * (1 - 0.25 * patch) * (1 - 0.6 * crk)
    color = tint(g, (1.0, 1.0, 1.03))
    save("asphalt", color, 0.7 * stones + 0.4 * light - 1.0 * crk, 0.93 - 0.05 * light, 3.0)


def _paint(name, rgb):
    r = rng(name)
    wear = noise(r, 26)
    chips = np.clip((wear - 0.70) * 9, 0, 1)            # worn through to the concrete
    dirt = noise(r, 70)
    grain = r.random((N, N))
    base = tint(0.92 + 0.05 * (grain - 0.5) - 0.12 * dirt, rgb)
    under = tint(0.55 + 0.05 * (grain - 0.5), (1.0, 0.985, 0.95))
    color = base * (1 - chips[..., None]) + under * chips[..., None]
    save(name, color, 0.4 * (1 - chips) + 0.1 * grain, 0.55 + 0.3 * chips + 0.1 * dirt, 2.0)


def paint_yellow():
    _paint("paint_yellow", (0.93, 0.73, 0.16))


def paint_white():
    _paint("paint_white", (0.93, 0.92, 0.88))


def rubber():
    r = rng("rubber")
    grain = noise(r, 3)
    dust = noise(r, 40)
    g = 0.11 + 0.03 * (grain - 0.5) + 0.05 * np.clip(dust - 0.6, 0, 1)
    save("rubber", tint(g, (1, 1, 1)), grain, 0.9 + 0.05 * dust, 1.2)


def _metal(name, base, brushed, rust):
    r = rng(name)
    br = noise(r, 2, aniso=(0.01, 1.0)) if brushed else noise(r, 6)
    scratches = cracks(r, 40, 60, 0.9)
    rs = np.clip((noise(r, 40) - (1 - rust)) * 6, 0, 1) if rust else np.zeros((N, N))
    g = base + 0.06 * (br - 0.5) + 0.12 * scratches
    color = tint(g, (1, 1, 1.02)) * (1 - rs[..., None]) + tint(0.32 + 0.1 * noise(r, 8), (0.55, 0.3, 0.15)) * rs[..., None]
    rough = 0.45 + 0.15 * (br - 0.5) - 0.15 * scratches + 0.4 * rs
    save(name, color, 0.3 * br + 0.4 * scratches - 0.5 * rs, rough, 1.0)


def dark_metal():
    _metal("dark_metal", 0.22, False, 0.12)


def brushed_metal():
    _metal("brushed_metal", 0.72, True, 0.0)


def galvanized():
    r = rng("galvanized")
    spangle = noise(r, 14)
    _ = r.random()
    g = 0.62 + 0.18 * (spangle - 0.5) + 0.06 * (noise(r, 3) - 0.5)
    save("galvanized", tint(g, (1, 1, 1.03)), spangle, 0.4 + 0.25 * spangle, 0.8)


def sign_paint():
    r = rng("sign_paint")
    speck = r.random((N, N))
    dirt = noise(r, 80)
    g = 0.95 + 0.04 * (speck - 0.5) - 0.12 * dirt   # multiplied by the sign's colour in the material
    save("sign_paint", tint(g, (1, 1, 1)), 0.3 * speck, 0.5 + 0.15 * dirt, 0.8)


def seat_fabric():
    yy, xx = np.mgrid[0:N, 0:N]
    weave = (np.sin(xx * 2 * np.pi / 16) * np.sin(yy * 2 * np.pi / 16) + 1) / 2
    r = rng("seat_fabric")
    g = 0.22 + 0.05 * weave + 0.03 * (noise(r, 4) - 0.5)
    save("seat_fabric", tint(g, (0.9, 0.92, 1.0)), weave, 0.95 + 0 * weave, 1.5)


def car_paint():
    """Near-white so the per-car Paint Color (albedo colour) shows through; road dust low on the panels
    comes from the fine noise, plus a few bird-dropping-free water spots."""
    r = rng("car_paint")
    dust = noise(r, 50)
    spots = blobs(r, 120, 2, 6, 0.9)
    g = 0.97 - 0.10 * np.clip(dust - 0.55, 0, 1) * 2 - 0.05 * spots
    save("car_paint", tint(g, (1, 1, 1)), 0.05 * dust, 0.25 + 0.25 * dust + 0.2 * spots, 0.3)


def red_paint():
    _paint("red_paint", (0.70, 0.08, 0.07))


def drum_paint():
    _paint("drum_paint", (0.13, 0.26, 0.48))


TEXTURES = {f.__name__: f for f in (concrete_deck, concrete_wall, concrete_pillar, asphalt, paint_yellow, paint_white,
                                    rubber, dark_metal, brushed_metal, galvanized, sign_paint, seat_fabric,
                                    car_paint, red_paint, drum_paint)}

if __name__ == "__main__":
    for n in (sys.argv[1:] or TEXTURES):
        TEXTURES[n]()
