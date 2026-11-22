"""Cuts the cart's metal scrape loops from zack's recording of a pipe scraped along concrete
(tools/audio/recordings/pipe_on_concrete.flac, 5.6 s: the scrape runs from 0.65 to 4.0 s).

The recording is the pipe's own ringing (peaks near 140, 220, 380, 800 and 920 Hz) over the grit of the concrete,
centroid about 1.5 kHz. One loop per thing on the cart that can scrape, made from it by what that thing is:
  scrape_tube.ogg   the frame's 25 mm steel tubes: the recording as it is (a pipe is a tube).
  scrape_wire.ogg   the basket cage, 5 mm steel wire: smaller and stiffer rings higher, so the same scrape played
                    1.4x faster, with the lows under 250 Hz thinned and the 2-6 kHz jangle lifted.
  scrape_seat.ogg   the gate and child seat (plastic-coated wire, plastic flap): plastic barely rings, so the
                    recording is cut into 30 ms grains and shuffled (the grit stays, the sustained ring goes),
                    played 0.85x and darkened above 2.5 kHz.
The wheels are polyurethane and keep their rubber scrubs (make_cart_rolling_loops.py).

Run from the repo root:  python3 tools/audio/make_scrape_loops.py   (needs numpy and ffmpeg)
"""
import os
import numpy as np
from make_cart_rolling_loops import RATE, FADE, REC, GODOT_OUT, decode, make_loop, write, shape, grains

SCRAPE = (1.0, 2.4)   # s: start and length of the steadiest stretch of the scrape


def resample(a: np.ndarray, rate: float) -> np.ndarray:
    return np.interp(np.arange(0, len(a) - 1, rate), np.arange(len(a)), a)


def main() -> None:
    pipe = decode(os.path.join(REC, "pipe_on_concrete.flac"))
    seg = pipe[int(0.65 * RATE):int(4.0 * RATE)]
    tube = make_loop(pipe, *SCRAPE)
    wire_src = shape(resample(seg, 1.4), [(0, 250, 0.35), (2000, 6000, 1.8)])
    wire = make_loop(wire_src, 0.1, (len(wire_src) / RATE) - FADE - 0.2)
    seat_src = shape(resample(grains(seg, 3.0, 0.03, 0.95, 1.05), 0.85), [(2500, 24000, 0.3)])
    seat = make_loop(seat_src, 0.0, 2.4)
    for name, loop in [("scrape_tube", tube), ("scrape_wire", wire), ("scrape_seat", seat)]:
        path = os.path.join(GODOT_OUT, name + ".ogg")
        write(loop, path, ["-c:a", "libvorbis", "-q:a", "5"])
        print("%s: %.2f s, %d KB" % (os.path.relpath(path), len(loop) / RATE, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
