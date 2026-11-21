"""Cuts the cart's wheel sounds from zack's shopping cart recordings (tools/audio/recordings/).

Rolling loops (one per kind of ground), scrub loops (a wheel sliding sideways) and knocks (a wheel landing or
hitting a kerb). There is no recording of a cart scrubbing, so the scrubs are made from the recordings: the
rough scrub is the asphalt roll cut into short grains and shuffled (the texture of the ground without the roll's
rhythm), brightened, with stick-slip chatter; the tile squeak is rubber stick-slip (a wavering tone of about
1.4 kHz in bursts) over grains of the tile roll. The knocks are the slab-joint clacks of the sidewalk recording; the landing (lifted wheels set back down) is the
second half of the drop recording.

Each rolling loop is a steady stretch of one recording, mixed to mono (3D sounds in Godot are mono), crossfaded tail
into head so it loops without a click, and levelled to the same loudness so the scene sets each surface's
volume. Writes:
  shopping-cart/assets/audio/cart/roll_<surface>.ogg, scrub_<kind>.ogg   (Godot, imported with loop on)
  shopping-cart/assets/audio/cart/knock_<n>.wav, land.wav               (Godot one-shots)
  mobile/audio/<same names>.wav                  (browser: 16-bit WAV loops gaplessly on every browser)

Run from the repo root:  python3 tools/audio/make_cart_rolling_loops.py   (needs numpy and ffmpeg)
"""
import os
import subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REC = os.path.join(ROOT, "tools", "audio", "recordings")
GODOT_OUT = os.path.join(ROOT, "shopping-cart", "assets", "audio", "cart")
WEB_OUT = os.path.join(ROOT, "mobile", "audio")
RATE = 44100
WEB_RATE = 22050
FADE = 0.5          # s of crossfade at the loop point
TARGET_RMS = -20.0  # dBFS every loop is levelled to

# surface: (recording, start s, loop length s). Starts and lengths picked from a 0.25 s loudness and crest scan
# of each file: the steady rolling, away from the pick-up and the stop at the ends.
LOOPS = {
    "asphalt": ("cart_asphalt.flac", 1.5, 12.0),    # parking lot: coarse, gritty roll
    "tile": ("cart_rolling.flac", 3.0, 12.0),       # the quieter, smoother roll: supermarket floor
    "concrete": ("cart_sidewalk.flac", 0.3, 7.5),   # slabs with joints that clack: garage decks, pavements
}


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def make_loop(a: np.ndarray, start: float, length: float, rate: int = RATE) -> np.ndarray:
    s, n, x = int(start * RATE), int(length * RATE), int(FADE * RATE)
    seg = a[s:s + n + x]
    assert len(seg) == n + x, "recording too short for that loop"
    seg = seg - seg.mean()
    out = seg[:n].copy()
    t = np.linspace(0.0, 1.0, x, endpoint=False)
    # Equal-power crossfade: the loop's head blends in from the audio that follows its tail, so tail -> head
    # continues exactly where the recording would have gone.
    out[:x] = seg[n:n + x] * np.cos(t * np.pi / 2) + seg[:x] * np.sin(t * np.pi / 2)
    rms = np.sqrt(np.mean(out ** 2))
    out *= 10 ** (TARGET_RMS / 20) / rms
    peak = np.abs(out).max()
    if peak > 0.95:
        out *= 0.95 / peak
    return out


def write(samples: np.ndarray, path: str, args: list) -> None:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-"] + args
                   + [path], input=samples.astype(np.float32).tobytes(), check=True)


SCRUB_LENGTH = 4.0   # s, scrub loops
# Knocks: the sidewalk recording's slab-joint clacks (s, found from 10 ms loudness peaks against the roll).
KNOCKS = [0.64, 1.61, 3.15, 4.85]
# Landing: zack's fourth recording (cart_drop.flac, 3.2 s) is a rattling roll (0.14 to 0.8 s) and then the
# wheels coming down: a hard hit at 0.86 s, a bounce at 1.18 s and a settle at 1.56 s. The landing sound is that
# second part, from just before the hit until the settle has died away.
LAND = (0.83, 1.85)
rng = np.random.default_rng(7)   # fixed seed: the builder makes the same files every run


def shape(a: np.ndarray, bands: list) -> np.ndarray:
    """Gain per frequency band: [(lo Hz, hi Hz, gain), ...], smooth enough for noise-like sounds."""
    f = np.fft.rfftfreq(len(a), 1 / RATE)
    g = np.ones_like(f)
    for lo, hi, gain in bands:
        g[(f >= lo) & (f < hi)] *= gain
    g = np.convolve(g, np.ones(401) / 401, "same")
    return np.fft.irfft(np.fft.rfft(a) * g, len(a))


def grains(src: np.ndarray, length: float, grain: float, rate_lo: float, rate_hi: float) -> np.ndarray:
    """Overlap-adds short Hann-windowed grains from random places in src, each at a random playback rate."""
    n, g = int((length + FADE) * RATE), int(grain * RATE)
    out = np.zeros(n + 2 * g)
    win = np.hanning(g)
    for pos in range(0, n + g, g // 2):
        rate = rng.uniform(rate_lo, rate_hi)
        start = rng.integers(0, len(src) - int(g * rate) - 1)
        idx = start + np.arange(g) * rate
        out[pos:pos + g] += np.interp(idx, np.arange(len(src)), src) * win
    return out[:n]


def chatter(n: int, hz: float, depth: float) -> np.ndarray:
    """Random stick-slip amplitude wobble around hz."""
    noise = rng.standard_normal(n)
    f = np.fft.rfftfreq(n, 1 / RATE)
    env = np.abs(np.fft.irfft(np.fft.rfft(noise) * ((f > hz * 0.5) & (f < hz * 1.5)), n))
    return (1 - depth) + depth * env / env.max() * 2.5


def loop_of(seg: np.ndarray, length: float) -> np.ndarray:
    return make_loop(seg, 0.0, length, rate=RATE)


def scrub_rough(asphalt: np.ndarray) -> np.ndarray:
    a = grains(asphalt, SCRUB_LENGTH, 0.035, 0.8, 1.3)
    a *= chatter(len(a), 30.0, 0.5)
    a = shape(a, [(0, 250, 0.2), (1500, 6000, 2.0)])
    return loop_of(a, SCRUB_LENGTH)


def scrub_squeak(tile: np.ndarray) -> np.ndarray:
    n = int((SCRUB_LENGTH + FADE) * RATE)
    t = np.arange(n) / RATE
    wander = np.cumsum(rng.standard_normal(n)) / np.sqrt(RATE) * 0.6
    wander = np.convolve(wander, np.ones(2000) / 2000, "same")
    f0 = 1400 * (1 + 0.12 * np.tanh(wander) + 0.01 * rng.standard_normal(n))
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    tone = sum(np.sin(k * phase) / k ** 1.3 for k in range(1, 7))
    bursts = np.clip(chatter(n, 9.0, 1.0) - 0.4, 0, None) ** 1.5   # it grips and lets go a few times a second
    bursts = np.convolve(bursts, np.ones(300) / 300, "same")
    bed = grains(tile, SCRUB_LENGTH, 0.03, 0.9, 1.2)[:n]
    a = tone * bursts / np.abs(tone * bursts).max() + 0.5 * bed / np.abs(bed).max()
    a = shape(a, [(0, 300, 0.2), (2000, 5000, 1.5)])
    return loop_of(a, SCRUB_LENGTH)


def knock(sidewalk: np.ndarray, at: float) -> np.ndarray:
    s = int((at - 0.015) * RATE)
    n = int(0.3 * RATE)
    a = sidewalk[s:s + n].copy()
    a -= a.mean()
    env = np.exp(-np.arange(n) / (0.07 * RATE))   # keep the clack, let the roll under it die away
    env[:int(0.003 * RATE)] *= np.linspace(0, 1, int(0.003 * RATE))
    a *= env
    return a * 0.8 / np.abs(a).max()


def main() -> None:
    os.makedirs(GODOT_OUT, exist_ok=True)
    os.makedirs(WEB_OUT, exist_ok=True)
    for surface, (file, start, length) in LOOPS.items():
        loop = make_loop(decode(os.path.join(REC, file)), start, length)
        ogg = os.path.join(GODOT_OUT, "roll_%s.ogg" % surface)
        wav = os.path.join(WEB_OUT, "roll_%s.wav" % surface)
        write(loop, ogg, ["-c:a", "libvorbis", "-q:a", "5"])
        write(loop, wav, ["-ar", str(WEB_RATE), "-c:a", "pcm_s16le"])
        print("%-9s %s %.1f-%.1f s -> %s (%d KB), %s (%d KB)" % (surface, file, start, start + length,
              os.path.relpath(ogg, ROOT), os.path.getsize(ogg) // 1024, os.path.relpath(wav, ROOT),
              os.path.getsize(wav) // 1024))


def extras() -> None:
    asphalt = decode(os.path.join(REC, "cart_asphalt.flac"))
    tile = decode(os.path.join(REC, "cart_rolling.flac"))
    sidewalk = decode(os.path.join(REC, "cart_sidewalk.flac"))
    sounds = {"scrub_rough": scrub_rough(asphalt[int(1.5 * RATE):int(40 * RATE)]),
              "scrub_squeak": scrub_squeak(tile[int(3 * RATE):int(15 * RATE)])}
    for name, loop in sounds.items():
        write(loop, os.path.join(GODOT_OUT, name + ".ogg"), ["-c:a", "libvorbis", "-q:a", "5"])
        write(loop, os.path.join(WEB_OUT, name + ".wav"), ["-ar", str(WEB_RATE), "-c:a", "pcm_s16le"])
        print("%-12s %.1f s loop" % (name, len(loop) / RATE))
    drop = decode(os.path.join(REC, "cart_drop.flac"))
    land = drop[int(LAND[0] * RATE):int(LAND[1] * RATE)].copy()
    land -= land.mean()
    land[:int(0.005 * RATE)] *= np.linspace(0, 1, int(0.005 * RATE))
    land[-int(0.15 * RATE):] *= np.linspace(1, 0, int(0.15 * RATE))
    land *= 0.85 / np.abs(land).max()
    for path in [os.path.join(GODOT_OUT, "land.wav"), os.path.join(WEB_OUT, "land.wav")]:
        write(land, path, ["-ar", str(WEB_RATE), "-c:a", "pcm_s16le"])
    print("land        %.2f-%.2f s of cart_drop.flac" % LAND)
    for i, at in enumerate(KNOCKS):
        k = knock(sidewalk, at)
        for path in [os.path.join(GODOT_OUT, "knock_%d.wav" % (i + 1)), os.path.join(WEB_OUT, "knock_%d.wav" % (i + 1))]:
            write(k, path, ["-ar", str(WEB_RATE), "-c:a", "pcm_s16le"])
        print("knock_%d     clack at %.2f s of the sidewalk recording" % (i + 1, at))


if __name__ == "__main__":
    main()
    extras()
