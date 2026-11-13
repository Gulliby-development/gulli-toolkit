#!/usr/bin/env python3
"""Draws the round shapes of the Gulli look into Gulli-Toolkit/Media as white TGA files with
an alpha channel (the game tints them): Round (a disc), RoundSq (a
rounded square, the mask of HUD icons), Glow (a soft halo) and Ring<R> (a
1 pixel ring for a corner of radius R, as S.Box draws it). Standard library only.
Run from the repository root, then tools/skin/sync.sh copies them into every module."""
import math
import os
import struct

OUT = "Gulli-Toolkit/Media"
# Corner radii S.Box knows; keep in step with RADII in Skin.lua.
RADII = (2, 3, 4, 6, 8, 9, 10, 11, 14)
SS = 4  # supersampling per axis


def write_tga(path, size, alpha):
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    px = bytearray()
    for a in alpha:
        px += bytes((255, 255, 255, max(0, min(255, int(round(a * 255))))))
    with open(path, "wb") as f:
        f.write(head + px)


def shape(size, inside):
    """alpha per texel of `inside(x, y)` (coordinates in 0..1, centre 0.5), supersampled."""
    out = []
    for y in range(size):
        for x in range(size):
            hit = 0
            for sy in range(SS):
                for sx in range(SS):
                    hit += inside((x + (sx + 0.5) / SS) / size, (y + (sy + 0.5) / SS) / size)
            out.append(hit / (SS * SS))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    dist = lambda x, y: math.hypot(x - 0.5, y - 0.5) * 2  # 0 centre .. 1 edge
    write_tga(f"{OUT}/Round.tga", 64, shape(64, lambda x, y: dist(x, y) <= 1))
    def squircle(x, y, r=0.2):
        dx, dy = max(abs(x - 0.5) - (0.5 - r), 0), max(abs(y - 0.5) - (0.5 - r), 0)
        return math.hypot(dx, dy) <= r
    write_tga(f"{OUT}/RoundSq.tga", 64, shape(64, squircle))
    glow = []
    for y in range(64):
        for x in range(64):
            d = dist((x + 0.5) / 64, (y + 0.5) / 64)
            glow.append(0 if d >= 1 else (1 if d < 0.55 else ((1 - d) / 0.45) ** 1.6))
    write_tga(f"{OUT}/Glow.tga", 64, glow)
    for r in RADII:
        size = 64 if r >= 6 else 32
        inner = (r - 1.15) / r
        write_tga(f"{OUT}/Ring{r}.tga", size, shape(size, lambda x, y, i=inner: i <= dist(x, y) <= 1))


if __name__ == "__main__":
    main()
