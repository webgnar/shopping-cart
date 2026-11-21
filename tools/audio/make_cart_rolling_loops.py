"""Cuts the cart rolling loops from zack's shopping cart recordings (tools/audio/recordings/).

Each loop is a steady stretch of one recording, mixed to mono (3D sounds in Godot are mono), crossfaded tail
into head so it loops without a click, and levelled to the same loudness so the scene sets each surface's
volume. Writes:
  shopping-cart/assets/audio/cart/roll_<surface>.ogg   (Godot, imported with loop on)
  mobile/audio/roll_<surface>.wav                      (browser: 16-bit WAV loops gaplessly on every browser)

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


def make_loop(a: np.ndarray, start: float, length: float) -> np.ndarray:
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


if __name__ == "__main__":
    main()
