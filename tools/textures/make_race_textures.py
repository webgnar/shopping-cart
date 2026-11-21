"""Paints the race's finish line: a black and white chequer, 0.5 m squares, two squares across and 45 along.

    python3 tools/textures/make_race_textures.py

Writes shopping-cart/assets/textures/race/finish_checker.png (64 x 1440 px: 32 px a square). The finish line in
scenes/race/race.tscn is a 1 x 22.5 m PlaneMesh, so the texture maps onto it 1:1 with no uv1_scale. The white is
a worn road-paint white and the black a dark grey, with a little speckle so it reads as paint on concrete.
"""
import os
import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "shopping-cart", "assets", "textures", "race")
SQUARE = 32          # px per 0.5 m square
ACROSS, ALONG = 2, 45


def main():
    rng = np.random.default_rng(7)
    h, w = ALONG * SQUARE, ACROSS * SQUARE
    y, x = np.mgrid[0:h, 0:w]
    white = ((y // SQUARE) + (x // SQUARE)) % 2 == 0
    img = np.where(white[..., None], np.array([226, 224, 216]), np.array([28, 28, 30])).astype(np.float32)
    img += rng.normal(0, 6, (h, w, 1))           # speckle, the same on all three channels
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "finish_checker.png")
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
