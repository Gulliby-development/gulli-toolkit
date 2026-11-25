#!/usr/bin/env python3
"""Draws Gulli-Fishing/Art/Mouse.tga: a mouse with its right button lit, for the "How to fish"
card (step 2: the right button, twice). Also writes tools/preview/fishing-mouse.png for the
window previews. Standard library only. Run from the repository root:

    python3 tools/fishing/art.py
"""
import struct
import zlib

SIZE, SS = 64, 4
BODY = (0.17, 0.13, 0.09)      # the mouse
EDGE = (0.62, 0.50, 0.24)      # its outline and the lines between the buttons
LIT = (1.0, 0.82, 0.0)         # the right button
X0, X1, Y0, Y1, RAD = 15.0, 49.0, 4.0, 60.0, 17.0
SPLIT = 28.0                   # the buttons end here
LINE = 1.6


def inside(x, y, grow=0.0):
    """Is the point in the rounded body, grown (or shrunk) by `grow` pixels?"""
    x0, x1, y0, y1, r = X0 - grow, X1 + grow, Y0 - grow, Y1 + grow, RAD + grow
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def sample(x, y):
    if not inside(x, y):
        return None
    if not inside(x, y, -LINE):
        return EDGE
    mid = (X0 + X1) / 2
    if y < SPLIT and abs(x - mid) < LINE / 2:
        return EDGE
    if abs(y - SPLIT) < LINE / 2:
        return EDGE
    if y < SPLIT and x > mid:
        return LIT
    return BODY


def pixels():
    out = []
    for py in range(SIZE):
        for px in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    c = sample(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    if c:
                        r, g, b, a = r + c[0], g + c[1], b + c[2], a + 1
            n = SS * SS
            if a:
                out.append((int(r / a * 255), int(g / a * 255), int(b / a * 255), int(a / n * 255)))
            else:
                out.append((0, 0, 0, 0))
    return out


def write_tga(path, px):
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with open(path, "wb") as f:
        f.write(head + b"".join(bytes((b, g, r, a)) for r, g, b, a in px))


def write_png(path, px):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in px[y * SIZE:(y + 1) * SIZE]) for y in range(SIZE))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    px = pixels()
    write_tga("Gulli-Fishing/Art/Mouse.tga", px)
    write_png("tools/preview/fishing-mouse.png", px)
