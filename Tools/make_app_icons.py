#!/usr/bin/env python3
"""Render the TrackpadRemote app icons for both platforms.

The artwork is drawn once at 4x and downsampled, so every size in the asset
catalogs comes from the same source and stays crisp at 16pt. Run it after
editing the design:

    python3 Tools/make_app_icons.py

Requires Pillow (`python3 -m pip install Pillow`).
"""

import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4                      # supersample factor
BASE = 1024                 # logical canvas
C = BASE * SS               # rendered canvas

# The pad is white on the app's accent blue: two shapes, maximum contrast, so
# the icon still reads as a trackpad at a 16pt Finder size.
BLUE_TOP = (94, 164, 255)
BLUE_BOTTOM = (26, 62, 143)
PAD_TOP = (255, 255, 255)
PAD_BOTTOM = (223, 231, 242)
CURSOR = (23, 34, 54)


def s(v):
    """Logical units -> rendered pixels."""
    return int(round(v * SS))


def linear_gradient(top, bottom, size):
    """Vertical gradient, drawn small and scaled up (cheap and smooth)."""
    small = Image.new("RGB", (2, 256))
    px = small.load()
    for y in range(256):
        t = y / 255.0
        col = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3))
        px[0, y] = col
        px[1, y] = col
    return small.resize(size, Image.BICUBIC)


def superellipse(cx, cy, half, n=5.0, steps=720):
    """Apple-style squircle outline as a polygon."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2.0 / n), ct)
        y = math.copysign(abs(st) ** (2.0 / n), st)
        pts.append((cx + x * half, cy + y * half))
    return pts


def drop_shadow(mask, blur, offset, opacity, color=(0, 0, 0)):
    """An RGBA layer holding `mask`'s silhouette as a blurred shadow."""
    shadow = Image.new("RGBA", mask.size, color + (0,))
    alpha = mask.filter(ImageFilter.GaussianBlur(blur)).point(
        lambda a: int(a * opacity)
    )
    shadow.putalpha(alpha)
    return shadow.transform(
        shadow.size, Image.AFFINE, (1, 0, -offset[0], 0, 1, -offset[1]),
        resample=Image.BILINEAR,
    )


def cursor_polygon(x, y, height):
    """Classic pointer arrow, tip at (x, y), scaled to `height`."""
    unit = [
        (0.00, 0.00), (0.00, 0.75), (0.19, 0.58), (0.31, 0.87),
        (0.45, 0.81), (0.33, 0.53), (0.56, 0.53),
    ]
    return [(x + ux * height, y + uy * height) for ux, uy in unit]


def draw_artwork():
    """The icon's content, on a transparent square canvas of side C."""
    art = Image.new("RGBA", (C, C), (0, 0, 0, 0))

    # Background: accent-blue gradient with a soft light source top-left, so a
    # flat fill doesn't read as dead space behind the pad.
    art.paste(linear_gradient(BLUE_TOP, BLUE_BOTTOM, (C, C)), (0, 0))
    glow = Image.new("L", (C, C), 0)
    ImageDraw.Draw(glow).ellipse(
        [s(-180), s(-320), s(760), s(560)], fill=110
    )
    glow = glow.filter(ImageFilter.GaussianBlur(s(90)))
    art.paste(Image.new("RGBA", (C, C), (255, 255, 255, 255)), (0, 0), glow)
    art.putalpha(255)

    # Trackpad surface: landscape, like the real pad and like the app's
    # landscape-only capture view.
    pad = [s(196), s(286), s(828), s(738)]
    radius = s(74)

    pad_mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(pad_mask).rounded_rectangle(pad, radius=radius, fill=255)

    art.alpha_composite(drop_shadow(pad_mask, s(26), (0, s(18)), 0.32))

    pad_fill = linear_gradient(PAD_TOP, PAD_BOTTOM, (C, C)).convert("RGBA")
    art.paste(pad_fill, (0, 0), pad_mask)

    # A hairline of the background colour keeps the pad from bleeding into the
    # blue at small sizes.
    ImageDraw.Draw(art).rounded_rectangle(
        pad, radius=radius, outline=(255, 255, 255, 90), width=s(3)
    )

    # Second finger: the touch that makes it a *multi-touch* pad, not a button.
    touch = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    ImageDraw.Draw(touch).ellipse(
        [s(636), s(536), s(772), s(672)], fill=BLUE_TOP + (70,)
    )
    ImageDraw.Draw(touch).ellipse(
        [s(636), s(536), s(772), s(672)], outline=BLUE_BOTTOM + (120,), width=s(7)
    )
    art.alpha_composite(Image.composite(
        touch, Image.new("RGBA", (C, C), (0, 0, 0, 0)), pad_mask
    ))

    # Pointer, sitting on the pad with a shadow so it floats above the surface.
    arrow = cursor_polygon(s(392), s(360), s(330))
    arrow_mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(arrow_mask).polygon(arrow, fill=255)
    art.alpha_composite(drop_shadow(arrow_mask, s(14), (0, s(10)), 0.30))
    ImageDraw.Draw(art).polygon(arrow, fill=CURSOR + (255,))

    return art


def ios_master(art):
    """iOS icons are full-bleed squares; the system applies the mask."""
    return art.convert("RGB")


def macos_master(art):
    """macOS icons sit in a squircle inset in a transparent 1024 canvas."""
    canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))

    inset, side = s(100), s(824)
    shape = Image.new("L", (C, C), 0)
    ImageDraw.Draw(shape).polygon(
        superellipse(inset + side / 2, inset + side / 2, side / 2), fill=255
    )

    canvas.alpha_composite(drop_shadow(shape, s(16), (0, s(10)), 0.35))
    body = art.resize((side, side), Image.LANCZOS)
    placed = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    placed.paste(body, (inset, inset))
    canvas.paste(placed, (0, 0), shape)
    return canvas


def write_catalog(path, master, entries, contents):
    os.makedirs(path, exist_ok=True)
    for name, px in entries:
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(path, name), "PNG"
        )
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")
    print(f"wrote {len(entries)} images -> {os.path.relpath(path, ROOT)}")


def main():
    art = draw_artwork()

    # --- iOS: one 1024 universal image (Xcode 14+ derives the rest) ---
    ios_dir = os.path.join(ROOT, "Resources/Assets-iOS.xcassets/AppIcon.appiconset")
    write_catalog(
        ios_dir,
        ios_master(art),
        [("AppIcon-1024.png", 1024)],
        {
            "images": [{
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }],
            "info": {"author": "xcode", "version": 1},
        },
    )

    # --- macOS: the full 16..512@2x ladder ---
    mac_sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                 (256, 1), (256, 2), (512, 1), (512, 2)]
    mac_entries, mac_images = [], []
    for pt, scale in mac_sizes:
        px = pt * scale
        name = f"AppIcon-{pt}@{scale}x.png"
        mac_entries.append((name, px))
        mac_images.append({
            "filename": name,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{pt}x{pt}",
        })
    write_catalog(
        os.path.join(ROOT, "Resources/Assets-macOS.xcassets/AppIcon.appiconset"),
        macos_master(art),
        mac_entries,
        {"images": mac_images, "info": {"author": "xcode", "version": 1}},
    )

    for cat in ("Resources/Assets-iOS.xcassets", "Resources/Assets-macOS.xcassets"):
        with open(os.path.join(ROOT, cat, "Contents.json"), "w") as f:
            json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
            f.write("\n")


if __name__ == "__main__":
    main()
