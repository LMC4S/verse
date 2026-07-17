#!/usr/bin/env python3
"""Generate menu bar (tray) icons into src/assets/.

Idle is a Didot closing quotation mark (speech, set in type), busy is an
ellipsis — template images, black-with-alpha, so macOS tints them for
light/dark menu bars. The recording icon is a red dot and stays colored.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

DIDOT = "/System/Library/Fonts/Supplemental/Didot.ttc"
DIDOT_BOLD_INDEX = 1

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src" / "assets"

SCALE = 8  # supersampling factor
BLACK = (0, 0, 0, 255)
RED = (255, 69, 58, 255)  # macOS systemRed (dark)


def canvas(points):
    size = points * SCALE
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image), lambda v: round(v * SCALE)


def finish(image, points, name):
    for factor, suffix in ((1, ""), (2, "@2x")):
        out = image.resize((points * factor, points * factor), Image.Resampling.LANCZOS)
        out.save(ASSETS / f"{name}{suffix}.png")


def quote_ink():
    """Rasterize a Didot closing double quote and crop to its ink box."""
    font = ImageFont.truetype(DIDOT, 400, index=DIDOT_BOLD_INDEX)
    image = Image.new("L", (600, 700), 0)
    ImageDraw.Draw(image).text((80, 60), "”", font=font, fill=255)
    return image.crop(image.getbbox())


def make_quote():
    points = 18
    ink = quote_ink()
    for factor, suffix in ((1, ""), (2, "@2x")):
        size = points * factor
        ink_height = round(10.5 * factor)
        ink_width = max(1, round(ink.width * ink_height / ink.height))
        scaled = ink.resize((ink_width, ink_height), Image.Resampling.LANCZOS)
        mark = Image.new("RGBA", scaled.size, BLACK)
        mark.putalpha(scaled)
        cell = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        cell.alpha_composite(mark, ((size - ink_width) // 2, (size - ink_height) // 2))
        cell.save(ASSETS / f"quoteTemplate{suffix}.png")


def make_recording():
    points = 18
    image, draw, s = canvas(points)
    draw.ellipse((s(4.6), s(4.6), s(13.4), s(13.4)), fill=RED)
    finish(image, points, "recording")


def make_busy():
    points = 18
    image, draw, s = canvas(points)
    radius = s(1.7)
    for cx in (4.0, 9.0, 14.0):
        draw.ellipse(
            (s(cx) - radius, s(9.0) - radius, s(cx) + radius, s(9.0) + radius),
            fill=BLACK,
        )
    finish(image, points, "busyTemplate")


if __name__ == "__main__":
    ASSETS.mkdir(parents=True, exist_ok=True)
    make_quote()
    make_recording()
    make_busy()
    print(f"Wrote tray icons to {ASSETS}")
