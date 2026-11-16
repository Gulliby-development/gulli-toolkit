"""Turns the drawn dungeon pictures in tools/dungeonprep/banners/<KEY>.jpg into the
addon's Gulli-DungeonPrep/Banners/<KEY>.tga: the middle 2:1 band, 512 x 256,
24-bit uncompressed (the game reads TGA, not PNG, and wants powers of two).

Needs Pillow. Run from the repository root: python3 tools/dungeonprep/banners.py
"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tools" / "dungeonprep" / "banners"
OUT = ROOT / "Gulli-DungeonPrep" / "Banners"
W, H = 512, 256


def convert(src, out):
    img = Image.open(src).convert("RGB")
    w, h = img.size
    if w / h > W / H:
        cw, ch = int(h * W / H), h
    else:
        cw, ch = w, int(w * H / W)
    left, top = (w - cw) // 2, (h - ch) // 2
    img = img.crop((left, top, left + cw, top + ch)).resize((W, H), Image.LANCZOS)
    img.save(out, format="TGA", rle=False)


def main():
    pictures = sorted(SRC.glob("*.jpg")) + sorted(SRC.glob("*.png"))
    if not pictures:
        sys.exit("no pictures in " + str(SRC))
    for src in pictures:
        out = OUT / (src.stem + ".tga")
        convert(src, out)
        print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
