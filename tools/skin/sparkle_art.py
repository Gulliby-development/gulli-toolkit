#!/usr/bin/env python3
"""Draws the light of the Quest item sparkle tweak into Gulli-Toolkit/Art/Sparkle as white TGA
files with an alpha channel. The game tints each one and lays them over each other with the ADD
blend, so every picture is light on its own and a mark is made of several of them:
Soft (128 px): a round soft light, brightest in the middle; also the dark veil under the light.
Halo (256 px): a cloudy band of light round a ring.
Wisp (256 px): thin threads of light along the same ring; two copies turn against each other.
Ring (256 px): a thin sharp ring with a faint glow, for the waves and the ground rings.
Comet (256 px): a piece of the ring with a bright head and a tail that fades.
Flare (128 px): a four-pointed star with a hot middle, the glint in the centre of every mark.
Beam (64 x 256 px): a column of light that fades out upwards.
Every ring sits at RING of the picture's half width, so the pictures line up at one size.
Needs numpy. Run from the repository root; also writes tools/preview/sparkle.png, the styles at
rest on a dark ground, for a quick look without the game."""
import math
import struct

import numpy as np

OUT = "Gulli-Toolkit/Art/Sparkle/"
RING = 0.74  # the ring's radius as a share of the half width (0.37 of the width)


def write_tga(path, alpha):
    h, w = alpha.shape
    a = np.clip(np.round(alpha * 255), 0, 255).astype(np.uint8)
    px = np.empty((h, w, 4), np.uint8)
    px[..., :3] = 255
    px[..., 3] = a
    head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    with open(path, "wb") as f:
        f.write(head + px.tobytes())


def grid(w, h=None, ss=3):
    """Supersampled coordinates from -1 to 1 (y up), shape (h*ss, w*ss)."""
    h = h or w
    xs = (np.arange(w * ss) + 0.5) / (w * ss) * 2 - 1
    ys = 1 - (np.arange(h * ss) + 0.5) / (h * ss) * 2
    return np.meshgrid(xs, ys)


def down(img, ss=3):
    h, w = img.shape
    return img.reshape(h // ss, ss, w // ss, ss).mean(axis=(1, 3))


def smooth_noise(angle, radius, cells, seed, octaves=3):
    """Noise that wraps round the circle: lattice in (angle, radius)."""
    rnd = np.random.default_rng(seed)
    out = np.zeros_like(angle)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = cells * (2 ** o)
        lat = rnd.random((n + 1, n))
        u = (angle / (2 * math.pi) % 1) * n
        v = np.clip(radius, 0, 0.999) * n
        i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
        fu, fv = u - i0, v - j0
        fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
        i1 = (i0 + 1) % n
        a = lat[j0, i0 % n]
        b = lat[j0, i1]
        c = lat[j0 + 1, i0 % n]
        d = lat[j0 + 1, i1]
        out += amp * ((a + (b - a) * fu) * (1 - fv) + (c + (d - c) * fu) * fv)
        total += amp
        amp *= 0.5
    return out / total


def vanish(r, start=0.86, end=0.99):
    t = np.clip((r - start) / (end - start), 0, 1)
    return 1 - t * t * (3 - 2 * t)


def soft():
    x, y = grid(128)
    r = np.hypot(x, y)
    img = np.exp(-(r / 0.42) ** 2) * vanish(r, 0.7, 0.99)
    return down(img)


def halo():
    x, y = grid(256)
    r, ang = np.hypot(x, y), np.arctan2(y, x)
    band = np.exp(-((r - RING) / 0.16) ** 2)
    cloud = smooth_noise(ang, r, 6, 11)
    img = band * (0.55 + 0.6 * cloud) + 0.18 * np.exp(-((r - RING) / 0.34) ** 2)
    return down(np.clip(img, 0, 1) * vanish(r))


def wisp():
    x, y = grid(256)
    r, ang = np.hypot(x, y), np.arctan2(y, x)
    img = np.zeros_like(r)
    rnd = np.random.default_rng(23)
    # threads: each a thin curve that drifts in and out of the ring over part of the circle
    for _ in range(14):
        a0, span = rnd.uniform(0, 2 * math.pi), rnd.uniform(1.2, 3.2)
        rr, drift, waves = RING + rnd.uniform(-0.08, 0.08), rnd.uniform(0.03, 0.09), rnd.uniform(1.5, 4)
        d = (ang - a0) % (2 * math.pi)
        along = np.clip(d / span, 0, 1)
        on = (d < span).astype(float) * np.sin(math.pi * along)
        path = rr + drift * np.sin(along * waves * math.pi)
        width = rnd.uniform(0.008, 0.02)
        img = np.maximum(img, on * np.exp(-((r - path) / width) ** 2) * rnd.uniform(0.5, 1))
    return down(np.clip(img, 0, 1) * vanish(r))


def ring():
    x, y = grid(256)
    r = np.hypot(x, y)
    img = np.exp(-((r - RING) / 0.022) ** 2) + 0.35 * np.exp(-((r - RING) / 0.09) ** 2)
    return down(np.clip(img, 0, 1) * vanish(r))


def comet():
    x, y = grid(256)
    r, ang = np.hypot(x, y), np.arctan2(y, x)
    head, span = math.pi / 2, math.radians(150)
    # the tail runs behind the head, clockwise from 12 o'clock
    d = (ang - head) % (2 * math.pi)
    along = np.where(d < span, 1 - d / span, 0)
    line = np.exp(-((r - RING) / (0.012 + 0.02 * along)) ** 2) * along ** 1.6
    glow = 0.4 * np.exp(-((r - RING) / 0.07) ** 2) * along ** 2.5
    hx, hy = 0, RING
    dot = np.exp(-(np.hypot(x - hx, y - hy) / 0.045) ** 2)
    return down(np.clip(line + glow + dot, 0, 1) * vanish(r))


def flare():
    x, y = grid(128)
    r = np.hypot(x, y)
    core = np.exp(-(r / 0.10) ** 2) + 0.45 * np.exp(-(r / 0.32) ** 2)
    ray = lambda a, b, w, ln: np.exp(-(np.abs(a) / w) ** 2) * np.exp(-np.abs(b) / ln)
    rays = ray(y, x, 0.025, 0.32) + ray(x, y, 0.025, 0.32)
    u, v = (x + y) / math.sqrt(2), (x - y) / math.sqrt(2)
    rays += 0.35 * (ray(u, v, 0.02, 0.14) + ray(v, u, 0.02, 0.14))
    return down(np.clip(core + rays, 0, 1) * vanish(r, 0.8, 0.99))


def beam():
    x, y = grid(64, 256)
    across = np.exp(-(x / 0.42) ** 2) * 0.7 + 0.5 * np.exp(-(x / 0.14) ** 2)
    up = (y + 1) / 2  # 0 at the bottom, 1 at the top
    fade = (1 - up) ** 1.4 * np.clip(up / 0.06, 0, 1)
    side = vanish(np.abs(x), 0.8, 0.99)
    return down(np.clip(across * fade * side, 0, 1))


ALL = {"Soft": soft, "Halo": halo, "Wisp": wisp, "Ring": ring, "Comet": comet, "Flare": flare,
       "Beam": beam}


def preview(pics):
    """The styles at rest as the game would add them, for the eye only."""
    from PIL import Image
    gold, size, cell = (1, 0.84, 0.25), 150, 260
    w, h = 5 * cell, cell
    canvas = np.zeros((h, w, 3))
    canvas[:] = (0.20, 0.22, 0.18)

    def mix(t):
        return tuple(c + (1 - c) * t for c in gold)

    def put(name, cx, cy, sw, sh, col, a, rot=0.0, dark=False):
        from PIL import Image as I
        src = I.fromarray((pics[name] * 255).astype(np.uint8))
        if rot:
            src = src.rotate(math.degrees(rot), resample=I.BICUBIC)
        src = np.asarray(src.resize((max(1, int(sw)), max(1, int(sh))), I.BICUBIC)) / 255.0
        x0, y0 = int(cx - sw / 2), int(cy - sh / 2)
        xs, ys = max(0, x0), max(0, y0)
        xe, ye = min(w, x0 + src.shape[1]), min(h, y0 + src.shape[0])
        part = src[ys - y0:ye - y0, xs - x0:xe - x0, None] * a
        if dark:
            canvas[ys:ye, xs:xe] *= 1 - part
        else:
            canvas[ys:ye, xs:xe] += part * np.array(col)

    ground = 0.36
    for i, style in enumerate(["glow", "ring", "beam", "arrow", "stars"]):
        cx, cy = cell * i + cell / 2, h / 2 + 10
        s = size
        if style == "glow":
            put("Soft", cx, cy, s * 1.1, s * 1.1, None, 0.3, dark=True)
            put("Halo", cx, cy, s, s, gold, 0.6)
            put("Wisp", cx, cy, s * 1.03, s * 1.03, mix(0.55), 0.4, 0.4)
            put("Wisp", cx, cy, s * 0.93, s * 0.93, mix(0.55), 0.32, 2.1)
            put("Ring", cx, cy, s, s, mix(0.55), 0.6)
            put("Comet", cx, cy, s, s, mix(0.55), 0.85, -0.7)
            put("Flare", cx, cy, s * 0.42, s * 0.42, mix(0.75), 0.9)
        elif style == "ring":
            foot = cy + s * 0.12
            put("Soft", cx, foot, s * 2.4, s * 2.4 * ground * 1.3, None, 0.3, dark=True)
            put("Soft", cx, foot, s * 1.2, s * 1.2 * ground * 1.3, gold, 0.8)
            for k, sp in enumerate([0.25, 0.6, 0.9]):
                wd = s * (0.3 + 1.4 * (1 - (1 - sp) ** 2))
                put("Ring", cx, foot, wd, wd * ground, mix(0.55), 0.9 * (1 - sp) ** 1.3)
            put("Flare", cx, foot, s * 0.32, s * 0.32, mix(0.75), 0.8)
        elif style == "beam":
            foot = cy + s * 0.45
            ht = s * 1.9
            put("Soft", cx, foot - ht * 0.4, s * 1.4, ht * 1.4, None, 0.22, dark=True)
            put("Soft", cx, foot, s * 1.1, s * 1.1 * ground * 1.3, gold, 0.85)
            put("Beam", cx, foot - ht / 2, s * 0.66, ht, gold, 0.8)
            put("Beam", cx, foot - ht * 0.47, s * 0.3, ht * 0.94, mix(0.75), 0.9)
            for k in range(4):
                put("Soft", cx + math.sin(k * 1.9) * s * 0.06, foot - (k + 0.5) / 4 * ht * 0.8,
                    s * 0.12, s * 0.12, mix(0.55), math.sin(math.pi * (k + 0.5) / 4))
            put("Flare", cx, foot, s * 0.36, s * 0.36, mix(0.75), 0.9)
        elif style == "arrow":
            foot = cy + s * 0.25
            put("Soft", cx, foot, s * 1.6, s * 1.6 * ground * 1.3, None, 0.3, dark=True)
            put("Soft", cx, foot, s, s * ground * 1.3, gold, 0.8)
            put("Ring", cx, foot, s * 1.1, s * 1.1 * ground, mix(0.55), 0.5)
            put("Soft", cx, foot - s * 0.75, s * 0.9, s * 0.9, gold, 0.55)
            put("Flare", cx, foot - s * 0.75, s * 0.4, s * 0.4, mix(0.75), 0.8)
        else:
            put("Soft", cx, cy, s * 1.9, s * 1.9, None, 0.28, dark=True)
            put("Soft", cx, cy, s * 1.55, s * 1.55, gold, 0.5)
            for k, (px, py, sc) in enumerate([(-0.2, -0.15, 1), (0.25, 0.1, 0.7), (0.05, 0.3, 0.55),
                                              (-0.3, 0.2, 0.5), (0.3, -0.25, 0.6)]):
                put("Flare", cx + px * s, cy + py * s, s * 0.55 * sc, s * 0.55 * sc, mix(0.75), 0.9)
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8))
    img.save("tools/preview/sparkle.png", optimize=True)


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    pics = {}
    for name, fn in ALL.items():
        pics[name] = fn()
        write_tga(OUT + name + ".tga", pics[name])
    preview(pics)
