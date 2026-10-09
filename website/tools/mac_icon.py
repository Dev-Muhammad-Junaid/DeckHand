#!/usr/bin/env python3
"""Shapes full-bleed iOS App Store artwork into a macOS-style app icon.

Keynote, Pages and Numbers are no longer listed on the Mac App Store, so their
artwork comes from the iOS listings, which is a plain square. This puts it on
the macOS icon grid (an 824 px rounded square on a 1024 px canvas, with a soft
drop shadow) so it matches the other Mac icons, and writes a 256 px PNG.

    python3 website/tools/mac_icon.py <ios artwork>.png <out>.png

Needs Pillow (pip3 install pillow).
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

CANVAS, BODY = 1024, 824
OUT_SIZE = 256


def squircle(size, body):
    """A superellipse (n=5), close to Apple's continuous-corner rounded square."""
    mask = Image.new('L', (size, size), 0)
    c, r, n = size / 2, body / 2, 5
    pts = []
    for i in range(2000):
        t = 2 * math.pi * i / 2000
        ct, st = math.cos(t), math.sin(t)
        pts.append((c + r * math.copysign(abs(ct) ** (2 / n), ct),
                    c + r * math.copysign(abs(st) ** (2 / n), st)))
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def main():
    src, dst = sys.argv[1], sys.argv[2]
    mask = squircle(CANVAS, BODY)
    off = (CANVAS - BODY) // 2
    art = Image.open(src).convert('RGBA').resize((BODY, BODY), Image.LANCZOS)
    icon = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.paste(art, (off, off))
    icon.putalpha(mask)
    shadow = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda v: v * 0.3)
                    .transform((CANVAS, CANVAS), Image.AFFINE, (1, 0, 0, 0, 1, -10))
                    .filter(ImageFilter.GaussianBlur(10)))
    out = Image.alpha_composite(shadow, icon)
    out.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS).save(dst, optimize=True)


if __name__ == '__main__':
    main()
