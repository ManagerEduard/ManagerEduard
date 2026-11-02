"""Draws the Lamp app icon (1024x1024 PNG). Usage: python3 make_icon.py OUTPUT.png"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 3  # supersampling
W = S * SS

# Background: warm diagonal gradient.
y, x = np.mgrid[0:W, 0:W].astype(np.float32) / W
t = np.clip(0.6 * y + 0.4 * x, 0, 1)[..., None]
top = np.array([255, 196, 70], np.float32)
bottom = np.array([235, 92, 30], np.float32)
bg = top * (1 - t) + bottom * t
# soft radial highlight behind the bulb
d = np.sqrt((x - 0.5) ** 2 + (y - 0.42) ** 2)[..., None]
glow = np.clip(1 - d / 0.55, 0, 1) ** 2
bg = bg + (np.array([255, 245, 210], np.float32) - bg) * glow * 0.55
img = Image.fromarray(bg.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")

def s(v):
    return int(v * SS)

# Bulb geometry (in 1024 space)
cx, cy, r = 512, 430, 230
neck_top, neck_bottom = 600, 720
neck_half_top, neck_half_bottom = 120, 95

# Outer glow
def soft_layer(color, alpha_mask, blur):
    """Solid colour with a blurred alpha mask (avoids dark fringes)."""
    mask = alpha_mask.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", (W, W), color + (0,))
    layer.putalpha(mask)
    return layer

mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).ellipse([s(cx - r - 60), s(cy - r - 60), s(cx + r + 60), s(cy + r + 60)], fill=170)
img = Image.alpha_composite(img, soft_layer((255, 248, 215), mask, s(70)))

# Glass: circle + tapered neck
bulb = Image.new("RGBA", (W, W), (0, 0, 0, 0))
b = ImageDraw.Draw(bulb)
glass = (255, 253, 240, 255)
b.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=glass)
b.polygon([
    (s(cx - 175), s(cy + 150)), (s(cx + 175), s(cy + 150)),
    (s(cx + neck_half_bottom), s(neck_bottom)), (s(cx - neck_half_bottom), s(neck_bottom)),
], fill=glass)
img = Image.alpha_composite(img, bulb)

d = ImageDraw.Draw(img)
# Filament
fil = (245, 150, 40, 255)
lw = s(18)
d.line([(s(cx - 70), s(neck_bottom - 10)), (s(cx - 55), s(cy + 40))], fill=fil, width=lw)
d.line([(s(cx + 70), s(neck_bottom - 10)), (s(cx + 55), s(cy + 40))], fill=fil, width=lw)
d.arc([s(cx - 70), s(cy - 30), s(cx + 70), s(cy + 110)], start=200, end=340, fill=fil, width=lw)

# Base (screw) — dark rounded bands
base = (70, 50, 45, 255)
for i, (yy, half) in enumerate([(735, 105), (790, 98), (845, 90)]):
    d.rounded_rectangle([s(cx - half), s(yy), s(cx + half), s(yy + 42)], radius=s(21), fill=base)
d.rounded_rectangle([s(cx - 45), s(895), s(cx + 45), s(930)], radius=s(17), fill=base)

# Glass highlight
hl_mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(hl_mask).arc([s(cx - r + 45), s(cy - r + 45), s(cx + r - 45), s(cy + r - 45)], start=195, end=255, fill=255, width=s(26))
img = Image.alpha_composite(img, soft_layer((255, 205, 120), hl_mask, s(4)))

img = img.resize((S, S), Image.LANCZOS).convert("RGB")
img.save(sys.argv[1])
