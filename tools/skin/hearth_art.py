#!/usr/bin/env python3
"""Draws the pictures of Gulli Hearth into Gulli-Toolkit/Media as white TGA files
with an alpha channel (the game tints them):
Grain (128 px, tiles without a seam): soft paper fibres and fine grain under every window.
Arc (256 px, Gulli-Toolkit/Art only): one mark of the Ready ring on the hub's home page.
Star (64 px, Gulli-Toolkit/Art only): the five-pointed star of the Recommended tweaks.
Mark (512 px, Gulli-Toolkit/Art only, not shared): the toolkit's satchel as a pale silhouette, the
dim emblem behind the hub's centre.
Needs Pillow for Mark. It reads docs/toolkit/emblem.png, the satchel cut out of the painted logo
with a clear background; a picture with its own background would show as a pale square. Run from the repository root, then
tools/skin/sync.sh copies them into every module."""
import math
import random
import struct

from PIL import Image

OUT = "Gulli-Toolkit/Media"
N = 128
MARK = 512


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
    src = Image.open("docs/toolkit/emblem.png").convert("RGBA")
    if src.getextrema()[3][0] > 0:
        raise SystemExit("docs/toolkit/emblem.png has no clear background")
    src = src.crop(src.getbbox())
    k = MARK / max(src.size)
    src = src.resize((max(1, round(src.width * k)), max(1, round(src.height * k))), Image.LANCZOS)
    # Fitted into the square, standing on its bottom edge and centred.
    im = Image.new("RGBA", (MARK, MARK), (0, 0, 0, 0))
    im.paste(src, ((MARK - src.width) // 2, MARK - src.height))
    out = []
    for r, g, b, a in list(im.getdata()):
        lum = min(1.0, 1.25 * (0.3 * r + 0.59 * g + 0.11 * b) / 255)
        out.append((a / 255) * (0.30 + 0.70 * lum))
    write_tga("Gulli-Toolkit/Art/Mark.tga", MARK, MARK, out)
    # The same picture as a PNG for tools/preview, which cannot read TGA, in the hub's tint.
    png = Image.new("RGBA", (MARK, MARK), (255, 219, 168, 0))
    png.putalpha(Image.frombytes("L", (MARK, MARK), bytes(int(round(v * 255)) for v in out)))
    png.save("tools/preview/mark.png", optimize=True)


ARC, ARC_DEG, ARC_OUT, ARC_IN = 256, 5.6, 0.97, 0.83


def arc():
    """One mark of the Ready ring (Gulli-Toolkit/Art only): a short piece of a ring at 12 o'clock.
    The hub turns 72 copies of it, 5 degrees apart, so each is a little wider than its step."""
    ss, half = 4, math.radians(ARC_DEG / 2)
    out = []
    for y in range(ARC):
        for x in range(ARC):
            hit = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = ((x + (sx + 0.5) / ss) / ARC) * 2 - 1
                    py = 1 - ((y + (sy + 0.5) / ss) / ARC) * 2
                    r = math.hypot(px, py)
                    if ARC_IN <= r <= ARC_OUT and abs(math.atan2(px, py)) <= half:
                        hit += 1
            out.append(hit / (ss * ss))
    write_tga("Gulli-Toolkit/Art/Arc.tga", ARC, ARC, out)


STAR = 64


def star():
    """A five-pointed star (Gulli-Toolkit/Art only), white, for the Recommended tweaks; the game
    tints it gold. The font has no star glyph, so it is a texture."""
    pts = []
    for i in range(10):
        r = 0.48 if i % 2 == 0 else 0.20
        a = math.radians(-90 + i * 36)
        pts.append((0.5 + r * math.cos(a), 0.53 + r * math.sin(a)))

    def inside(px, py):
        hit = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                hit = not hit
            j = i
        return hit

    ss, out = 4, []
    for y in range(STAR):
        for x in range(STAR):
            hit = sum(inside((x + (sx + 0.5) / ss) / STAR, (y + (sy + 0.5) / ss) / STAR)
                      for sy in range(ss) for sx in range(ss))
            out.append(hit / (ss * ss))
    write_tga("Gulli-Toolkit/Art/Star.tga", STAR, STAR, out)


if __name__ == "__main__":
    grain()
    mark()
    arc()
    star()
