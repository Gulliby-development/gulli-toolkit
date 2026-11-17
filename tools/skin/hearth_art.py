#!/usr/bin/env python3
"""Draws the two background pictures of Gulli Hearth into Gulli-Toolkit/Media as white TGA files
with an alpha channel (the game tints them):
Grain (128 px, tiles without a seam): soft paper fibres and fine grain under every window.
Mark (256 px, Gulli-Toolkit/Art only, not shared): the toolkit logo as a pale silhouette, the
dim emblem behind the hub's home page.
Needs Pillow for Mark (it reads docs/toolkit/icon.png). Run from the repository root, then
tools/skin/sync.sh copies them into every module."""
import math
import random
import struct

from PIL import Image

OUT = "Gulli-Toolkit/Media"
N = 128
MARK = 256


def write_tga(path, w, h, alpha):
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    px = bytearray()
    for a in alpha:
        px += bytes((255, 255, 255, max(0, min(255, int(round(a * 255))))))
    with open(path, "wb") as f:
        f.write(head + px)


def value_noise(cells, rnd):
    """Tileable smooth noise on an N x N grid with `cells` lattice cells per side."""
    lat = [[rnd.random() for _ in range(cells)] for _ in range(cells)]
    out = [0.0] * (N * N)
    for y in range(N):
        fy = y * cells / N
        y0 = int(fy)
        ty = fy - y0
        ty = ty * ty * (3 - 2 * ty)
        for x in range(N):
            fx = x * cells / N
            x0 = int(fx)
            tx = fx - x0
            tx = tx * tx * (3 - 2 * tx)
            a = lat[y0 % cells][x0 % cells]
            b = lat[y0 % cells][(x0 + 1) % cells]
            c = lat[(y0 + 1) % cells][x0 % cells]
            d = lat[(y0 + 1) % cells][(x0 + 1) % cells]
            out[y * N + x] = (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
    return out


def grain():
    rnd = random.Random(1717)
    layers = [(4, 0.45), (8, 0.25), (16, 0.18), (64, 0.12)]
    acc = [0.0] * (N * N)
    for cells, w in layers:
        for i, v in enumerate(value_noise(cells, rnd)):
            acc[i] += v * w
    # Fibres: short faint strokes, wrapped at the edges so the tile has no seam.
    fib = [0.0] * (N * N)
    for _ in range(110):
        x, y = rnd.uniform(0, N), rnd.uniform(0, N)
        ang = rnd.uniform(-0.5, 0.5) + (math.pi / 2 if rnd.random() < 0.3 else 0)
        ln, s = rnd.uniform(6, 22), rnd.uniform(0.15, 0.45)
        for t in range(int(ln)):
            px = int(x + math.cos(ang) * t) % N
            py = int(y + math.sin(ang) * t) % N
            fib[py * N + px] = max(fib[py * N + px], s)
    lo, hi = min(acc), max(acc)
    out = []
    for i in range(N * N):
        v = (acc[i] - lo) / (hi - lo)
        out.append(min(1.0, 0.15 + 0.7 * v + fib[i] + rnd.uniform(-0.06, 0.06)))
    write_tga(OUT + "/Grain.tga", N, N, out)


def mark():
    im = Image.open("docs/toolkit/icon.png").convert("RGBA").resize((MARK, MARK), Image.LANCZOS)
    out = []
    for r, g, b, a in list(im.getdata()):
        lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255
        out.append((a / 255) * (0.35 + 0.65 * lum))
    write_tga("Gulli-Toolkit/Art/Mark.tga", MARK, MARK, out)


if __name__ == "__main__":
    grain()
    mark()
