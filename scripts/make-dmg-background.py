#!/usr/bin/env python3
"""Draws the disk image background (assets/dmg-background@2x.png, 1320x800 px, shown at 660x400 points).

Needs Pillow and the Inter font. Run it only when the artwork changes; the PNG is committed.
Icon positions the DMG script uses: Bango.app at (180, 190), Applications at (480, 190), in points.
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, S = 1320, 800, 2          # output size and supersampling
FONT_DIR = "/usr/share/fonts/opentype/inter/"
ACCENT = (59, 109, 240)
INK = (18, 19, 26)
MUTED = (110, 116, 135)


def font(name, size):
    return ImageFont.truetype(FONT_DIR + name, size * S)


import numpy as np

# Soft vertical gradient, computed in floats so it has no visible steps.
top = np.array((248, 249, 253), dtype=np.float64)
bottom = np.array((226, 232, 246), dtype=np.float64)
t = np.linspace(0, 1, H * S)[:, None, None]
rows = top + (bottom - top) * t
noise = np.random.default_rng(3).uniform(-0.6, 0.6, (H * S, W * S, 1))  # dithering against banding
arr = np.clip(rows + noise, 0, 255).astype(np.uint8)
img = Image.fromarray(np.broadcast_to(arr, (H * S, W * S, 3)).copy(), "RGB")

# Dot grid.
grid = Image.new("RGBA", img.size, (0, 0, 0, 0))
gd = ImageDraw.Draw(grid)
step = 40 * S
for gy in range(step, H * S, step):
    for gx in range(step, W * S, step):
        gd.ellipse((gx - 2, gy - 2, gx + 2, gy + 2), fill=(90, 110, 170, 38))
img = Image.alpha_composite(img.convert("RGBA"), grid)

# Glow behind the arrow.
# The transparent base carries the accent colour, so blurring it does not pull in black.
glow = Image.new("RGBA", img.size, ACCENT + (0,))
ImageDraw.Draw(glow).ellipse(((W // 2 - 330) * S, (380 - 150) * S, (W // 2 + 330) * S, (380 + 150) * S), fill=ACCENT + (52,))
glow = glow.filter(ImageFilter.GaussianBlur(70 * S))
img = Image.alpha_composite(img, glow)

d = ImageDraw.Draw(img)

# Title and subtitle.
title = "Drag Bango into Applications"
tf = font("InterDisplay-SemiBold.otf", 46)
tw = d.textlength(title, font=tf)
d.text(((W * S - tw) / 2, 92 * S), title, font=tf, fill=INK)
sub = "Then open it from Launchpad or the Applications folder"
sf = font("Inter-Regular.otf", 24)
sw = d.textlength(sub, font=sf)
d.text(((W * S - sw) / 2, 160 * S), sub, font=sf, fill=MUTED)

# Arrow between the two icons (icon centres at 360 px and 960 px, y 380 px).
y0 = 380 * S
x_start, x_end = 520 * S, 800 * S
amp, segments = 0, 40
d.line([(x_start, y0), (x_end - 34 * S, y0)], fill=ACCENT + (255,), width=10 * S, joint="curve")
for cx in (x_start, x_end - 34 * S):
    d.ellipse((cx - 5 * S, y0 - 5 * S, cx + 5 * S, y0 + 5 * S), fill=ACCENT + (255,))
head = [(x_end, y0), (x_end - 46 * S, y0 - 34 * S), (x_end - 46 * S, y0 + 34 * S)]
d.polygon(head, fill=ACCENT + (255,))

# Footer.
foot = "Tap your MacBook to control it"
ff = font("Inter-Medium.otf", 22)
fw = d.textlength(foot, font=ff)
d.text(((W * S - fw) / 2, 716 * S), foot, font=ff, fill=MUTED)

img = img.convert("RGB").resize((W, H), Image.LANCZOS)
out = sys.argv[1] if len(sys.argv) > 1 else "assets/dmg-background@2x.png"
img.save(out, optimize=True)
print("wrote", out, img.size)
