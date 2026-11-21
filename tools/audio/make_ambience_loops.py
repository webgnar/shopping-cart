"""Cuts the parking lot background loop from zack's field recording ("parking lot back ground.wav", 9:15 of
stereo 24-bit 48 kHz, recorded in REAPER 2023-01-11). The recording is too big for the repo (160 MB); it lives in
the project's shared files. Pass its path, or it is looked for at /mnt/project-files/.

The recording clips (peaks at 0 dBFS) at 4 s, 70 s and 323-328 s (something loud right by the mic), so the loop
skips those: it is 75-320.5 s spliced to 332-553.5 s (both splice points sit in quiet stretches), with an
equal-power crossfade at the splice and another from the end back into the start. Levelled to peak at -1 dBFS;
the scene sets how loud it plays. Writes:
  shopping-cart/assets/audio/ambience/parking_lot.ogg   (Godot: seamless loop, imported with loop on)
  mobile/audio/parking_lot.mp3                          (browser: the loop plus XFADE s of what follows it,
                                                         unfaded; mobile/game/music.js overlaps the copies itself
                                                         so MP3 encoder padding can't leave a gap)

Run from the repo root:  python3 tools/audio/make_ambience_loops.py [path/to/recording.wav]   (numpy, ffmpeg)
"""
import os
import subprocess
import sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_SRC = "/mnt/project-files/parking lot back ground.wav"
GODOT_OUT = os.path.join(ROOT, "shopping-cart", "assets", "audio", "ambience", "parking_lot.ogg")
WEB_OUT = os.path.join(ROOT, "mobile", "audio", "parking_lot.mp3")
RATE = 44100
XFADE = 4.0                            # s of crossfade at the splice and at the loop point
PIECES = [(75.0, 320.5), (332.0, 553.5)]  # kept stretches of the recording, s
PEAK = -1.0                            # dBFS


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "2", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64).reshape(-1, 2)


def fades(n: int):
    t = (np.arange(n) / n)[:, None]
    return np.cos(t * np.pi / 2), np.sin(t * np.pi / 2)   # out, in (equal power: uncorrelated ambience)


def build(a: np.ndarray):
    """Returns (loop, web): the seamless loop, and the loop followed by XFADE s of unfaded continuation."""
    x = int(XFADE * RATE)
    fo, fi = fades(x)
    pieces = [a[int(s * RATE):int(e * RATE)] for s, e in PIECES]
    # Splice: the first piece's last XFADE s fade out over the second piece's first XFADE s.
    body = np.concatenate([pieces[0][:-x], pieces[0][-x:] * fo + pieces[1][:x] * fi, pieces[1][x:]])
    body -= body.mean(axis=0)
    n = len(body) - x                   # loop length; the last x samples are what plays after the loop's end
    loop = body[:n].copy()
    loop[:x] = body[n:] * fo + body[:x] * fi   # tail -> head
    g = 10 ** (PEAK / 20) / max(np.abs(loop).max(), np.abs(body).max())
    return loop * g, body * g


def write(samples: np.ndarray, path: str, args: list) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-"] + args
                   + [path], input=samples.astype(np.float32).tobytes(), check=True)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    loop, web = build(decode(src))
    write(loop, GODOT_OUT, ["-c:a", "libvorbis", "-q:a", "2"])
    write(web, WEB_OUT, ["-c:a", "libmp3lame", "-b:a", "64k"])
    rms = 20 * np.log10(np.sqrt(np.mean(loop ** 2)))
    print("loop %.3f s (%d samples at %d Hz), RMS %.1f dBFS" % (len(loop) / RATE, len(loop), RATE, rms))
    for p in (GODOT_OUT, WEB_OUT):
        print("  %s (%d KB)" % (os.path.relpath(p, ROOT), os.path.getsize(p) // 1024))


if __name__ == "__main__":
    main()
