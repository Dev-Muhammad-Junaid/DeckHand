#!/usr/bin/env python3
"""Generates the iOS launch screen's artwork from the hand's glyph data.

    python3 DeckHand/Scripts/make-launch-image.py

The launch screen (`06-Pixel-Identity.md` §8) is the icon's screen
full-bleed: navy (`LaunchBackground`, Brand.screen #060A2A), the dot hand
with its tap rays centred, and the mint pixel at the screen's top-trailing
corner, where the icon has it. `UILaunchScreen` can only centre one image,
so the image is the icon's screen area (transparent) with the hand and the
mint pixel placed inside it.

The hand is read from Core's `MenuBarHand.handRows` (the same art as
`PixelArt.hand`), so the launch, the icon, the menu bar and the app share
one bitmap. Dots follow the one rule: 78 % of the pitch, radius 30 % of the
dot. Needs Pillow.
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
CORE_HAND = os.path.join(APP, "Core/Sources/PixelHandCore/Design/MenuBarHand.swift")
OUT = os.path.join(APP, "DeckHandiOS/Assets.xcassets")

# Brand colours (Core `PaletteTokens.Brand`).
SCREEN = (0x06, 0x0A, 0x2A)
PHOSPHOR = (0xEF, 0xFF, 0xFC)
VIOLET = (0x8E, 0x70, 0xFF)
RAY = (0x9F, 0xF6, 0xFF)
GLOW = (0x3D, 0xE0, 0xE0)
MINT = (0x3D, 0xE0, 0xB0)

# Layout in points: the icon's screen proportions, hand pitch 5.
WIDTH, HEIGHT = 220, 168
PITCH = 5.0
DOT = 0.78
RADIUS = 0.30


def hand_rows():
    source = open(CORE_HAND, encoding="utf-8").read()
    block = re.search(r"handRows: \[String\] = \[(.*?)\]", source, re.S).group(1)
    rows = re.findall(r'"([.Xo]+)"', block)
    if len(rows) != 18:
        sys.exit(f"expected 18 hand rows in {CORE_HAND}, found {len(rows)}")
    return rows


def stage():
    """The hand on the 19 x 21 approval stage with its rays (PixelArt.handWithRays)."""
    cells = {}
    for y, row in enumerate(hand_rows()):
        for x, c in enumerate(row):
            if c == "X":
                cells[(x + 1, y + 3)] = "outline"
            elif c == "o":
                cells[(x + 1, y + 3)] = "fill"
    for p in [(6, 1), (7, 1), (4, 2), (9, 2)]:
        cells[p] = "ray"
    for p in [(6, 0), (7, 0), (3, 1), (10, 1)]:
        cells[p] = "far"
    return cells, 19, 21


def render(scale):
    w, h = int(WIDTH * scale), int(HEIGHT * scale)
    cells, sw, sh = stage()
    pitch = PITCH * scale
    ox = (w - sw * pitch) / 2
    oy = (h - sh * pitch) / 2
    dot = pitch * DOT
    inset = (pitch - dot) / 2
    radius = dot * RADIUS

    def rect(x, y, grow=0.0):
        left = ox + x * pitch + inset - grow
        top = oy + y * pitch + inset - grow
        return [left, top, left + dot + 2 * grow, top + dot + 2 * grow]

    # Bloom behind the lit dots.
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for (x, y), kind in cells.items():
        if kind != "fill":
            g.rounded_rectangle(rect(x, y, dot * 0.15), radius, fill=GLOW + (150,))
    mint_side = dot * 1.2
    mint_box = [w - 24 * scale - mint_side, 20 * scale, w - 24 * scale, 20 * scale + mint_side]
    g.rounded_rectangle(mint_box, mint_side * 0.3, fill=MINT + (170,))
    glow = glow.filter(ImageFilter.GaussianBlur(pitch * 0.45))

    art = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    a = ImageDraw.Draw(art)
    colours = {"outline": PHOSPHOR + (255,), "fill": VIOLET + (255,), "ray": RAY + (255,), "far": RAY + (178,)}
    for (x, y), kind in cells.items():
        a.rounded_rectangle(rect(x, y), radius, fill=colours[kind])
    a.rounded_rectangle(mint_box, mint_side * 0.3, fill=MINT + (255,))

    return Image.alpha_composite(glow, art)


def write_json(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    imageset = os.path.join(OUT, "LaunchHand.imageset")
    os.makedirs(imageset, exist_ok=True)
    for scale in (1, 2, 3):
        render(scale).save(os.path.join(imageset, f"LaunchHand@{scale}x.png"), optimize=True)
    write_json(os.path.join(imageset, "Contents.json"), """{
  "images" : [
    { "filename" : "LaunchHand@1x.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "LaunchHand@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "LaunchHand@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""")

    colorset = os.path.join(OUT, "LaunchBackground.colorset")
    os.makedirs(colorset, exist_ok=True)
    r, g, b = (f"0x{c:02X}" for c in SCREEN)
    write_json(os.path.join(colorset, "Contents.json"), f"""{{
  "colors" : [
    {{
      "color" : {{
        "color-space" : "srgb",
        "components" : {{ "alpha" : "1.000", "blue" : "{b}", "green" : "{g}", "red" : "{r}" }}
      }},
      "idiom" : "universal"
    }}
  ],
  "info" : {{ "author" : "xcode", "version" : 1 }}
}}
""")
    print(f"Wrote {imageset} and {colorset}")


if __name__ == "__main__":
    main()
