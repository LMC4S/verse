#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

DIDOT = "/System/Library/Fonts/Supplemental/Didot.ttc"
DIDOT_BOLD_INDEX = 1


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
ICONSET = BUILD / "icon.iconset"
BASE = BUILD / "icon.png"
ICNS = BUILD / "icon.icns"


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def mix(a, b, t):
    return round(a * (1 - t) + b * t)


def quote_ink():
    """Rasterize a Didot closing double quote and crop to its ink box."""
    font = ImageFont.truetype(DIDOT, 1600, index=DIDOT_BOLD_INDEX)
    image = Image.new("L", (2400, 2800), 0)
    ImageDraw.Draw(image).text((300, 240), "”", font=font, fill=255)
    return image.crop(image.getbbox())


def make_base():
    scale = 2
    size = 1024
    canvas = size * scale
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    bg = Image.new("RGBA", (canvas, canvas))
    pixels = bg.load()
    start = (28, 28, 30)
    end = (8, 8, 10)

    # Graphite vertical gradient — black & white, no color.
    for y in range(canvas):
        t = y / (canvas - 1)
        color = tuple(mix(start[i], end[i], t) for i in range(3))
        for x in range(canvas):
            pixels[x, y] = (*color, 255)

    image.alpha_composite(bg)

    # The Verse mark: a Didot closing quote in white, optically centered.
    ink = quote_ink()
    ink_height = round(canvas * 0.44)
    ink_width = max(1, round(ink.width * ink_height / ink.height))
    scaled = ink.resize((ink_width, ink_height), Image.Resampling.LANCZOS)
    mark = Image.new("RGBA", scaled.size, (255, 255, 255, 255))
    mark.putalpha(scaled)
    image.alpha_composite(
        mark,
        ((canvas - ink_width) // 2, (canvas - ink_height) // 2),
    )

    # Whisper-thin edge highlight (composited so the alpha blends).
    border = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (3 * scale, 3 * scale, canvas - 4 * scale, canvas - 4 * scale),
        radius=224 * scale,
        outline=(255, 255, 255, 45),
        width=4 * scale,
    )
    image.alpha_composite(border)

    image.putalpha(rounded_mask(canvas, 224 * scale))

    image = image.resize((size, size), Image.Resampling.LANCZOS)
    BUILD.mkdir(exist_ok=True)
    image.save(BASE)
    return image


def make_iconset(base):
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for filename, size in sizes:
        base.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / filename)


def make_icns():
    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)


if __name__ == "__main__":
    base = make_base()
    make_iconset(base)
    make_icns()
    print(ICNS)
