#!/usr/bin/env python3
from pathlib import Path
import math
import shutil
import subprocess

from PIL import Image, ImageDraw


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


def wave_points(left, right, center_y, amplitude, cycles, count):
    points = []
    for index in range(count):
        t = index / (count - 1)
        x = left + (right - left) * t
        y = center_y - math.sin(t * math.pi * 2 * cycles) * amplitude
        points.append((round(x), round(y)))
    return points


def draw_round_line(draw, points, fill, width):
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def make_base():
    scale = 4
    size = 1024
    canvas = size * scale
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    bg = Image.new("RGBA", (canvas, canvas))
    pixels = bg.load()
    start = (32, 42, 49)
    end = (18, 26, 32)

    for y in range(canvas):
        for x in range(canvas):
            t = (x * 0.34 + y * 0.66) / canvas
            color = tuple(mix(start[i], end[i], t) for i in range(3))
            pixels[x, y] = (*color, 255)

    image.alpha_composite(bg)
    image.putalpha(rounded_mask(canvas, 224 * scale))

    def s(value):
        return round(value * scale)

    draw = ImageDraw.Draw(image)
    points = wave_points(s(238), s(786), s(512), s(116), 3, 220)
    draw_round_line(draw, points, (141, 216, 200, 255), s(74))

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
