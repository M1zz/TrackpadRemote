#!/usr/bin/env python3
"""Build the App Store screenshots, iOS and macOS as separate sets.

    python3 Tools/make_screenshots.py capture   # 1. real iOS screens from the simulator
    python3 Tools/make_screenshots.py           # 2. compose -> Screenshots/iOS, Screenshots/macOS

The iOS pages frame genuine captures of the app. The Debug build stages each
screen from a launch argument (`-screenshotState`, `-screenshotSettings`), so no
Mac has to be on the network. Captures land in Screenshots/captures and are
kept, so step 2 alone re-renders captions and layout without a simulator.

The Mac app is a menu bar extra: there is no window to capture and an NSMenu
can't be rendered offscreen, so its menu is redrawn here from the strings in
macOS/TrackpadServerApp.swift. Keep MAC_MENUS in step when that menu changes.

Requires Pillow and Xcode (SF Symbols come from Tools/render_symbols.swift).
"""

import json
import math
import os
import plistlib
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_app_icons import BLUE_BOTTOM, BLUE_TOP, cursor_polygon, linear_gradient

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Screenshots")
CAPTURES = os.path.join(OUT, "captures")

# App Store Connect sizes.
IOS_SIZE = (1242, 2688)     # 6.5" iPhone, portrait
IOS_DEVICE_TOP = 700        # same spot on every page, so they flip past cleanly
MAC_SIZE = (2880, 1800)     # 16:10 Retina

SIM_DEVICE = "iPhone 17 Pro Max"
CAPTURE_STATES = {
    "connected": ["-screenshotState", "connected"],
    "searching": ["-screenshotState", "searching"],
    "settings": ["-screenshotState", "connected", "-screenshotSettings", "YES"],
}

SS = 3                          # supersample factor for shapes
WHITE = (255, 255, 255)
BG_TOP = (48, 112, 226)         # the icon's blues, deepened so white captions read
BG_BOTTOM = (12, 30, 84)
TINT = (10, 132, 255)           # systemBlue (dark) — the app's accent, which its ripples use
PAD_FILL = (28, 28, 30)         # secondarySystemBackground (dark), the pad surface

GOTHIC = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
GOTHIC_INDEX = {"regular": 0, "medium": 2, "semibold": 4, "bold": 6}
SF = "/System/Library/Fonts/SFNS.ttf"
SF_WEIGHT = {"regular": 400, "medium": 510, "semibold": 590, "bold": 700}


# ---------------------------------------------------------------------------
# Capture


def run(cmd, **kw):
    print("+", " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def simulator_udid(name):
    """Newest iOS runtime's device called `name`, booted and ready."""
    data = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtimes = sorted((r for r in data["devices"] if ".iOS-" in r), reverse=True)
    for runtime in runtimes:
        for device in data["devices"][runtime]:
            if device["name"] == name:
                run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"],
                    stdout=subprocess.DEVNULL)
                return device["udid"]
    sys.exit(f"no simulator named {name!r}")


def capture():
    udid = simulator_udid(SIM_DEVICE)
    derived = os.path.join(tempfile.gettempdir(), "TrackpadRemote-screenshots")
    run(["xcodebuild", "-project", os.path.join(ROOT, "TrackpadRemote.xcodeproj"),
         "-scheme", "TrackpadRemote", "-configuration", "Debug",
         "-destination", f"id={udid}", "-derivedDataPath", derived, "-quiet", "build"])
    app = os.path.join(derived, "Build/Products/Debug-iphonesimulator/TrackpadRemote.app")
    with open(os.path.join(app, "Info.plist"), "rb") as f:
        bundle_id = plistlib.load(f)["CFBundleIdentifier"]

    run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
         "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
         "--cellularMode", "active", "--cellularBars", "4",
         "--batteryState", "charged", "--batteryLevel", "100"])
    run(["xcrun", "simctl", "install", udid, app])

    os.makedirs(CAPTURES, exist_ok=True)
    for name, args in CAPTURE_STATES.items():
        # Relaunch per state: the stage is read once, at launch.
        subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id],
                       stderr=subprocess.DEVNULL)
        run(["xcrun", "simctl", "launch", udid, bundle_id, *args])
        time.sleep(4)   # launch + sheet animation
        path = os.path.join(CAPTURES, f"{name}.png")
        run(["xcrun", "simctl", "io", udid, "screenshot", path], stderr=subprocess.DEVNULL)

        # The simulator's framebuffer stays portrait; the landscape UI is drawn
        # into it with its top edge on the right.
        shot = Image.open(path)
        if shot.height > shot.width:
            shot.transpose(Image.ROTATE_90).save(path)
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], stderr=subprocess.DEVNULL)


# ---------------------------------------------------------------------------
# Drawing primitives


def is_hangul(ch):
    return 0x1100 <= ord(ch) <= 0x11FF or 0x3130 <= ord(ch) <= 0x318F or 0xAC00 <= ord(ch) <= 0xD7AF


class Face:
    """A size and weight, set the way the system sets it: SF for Latin, Apple SD
    Gothic Neo for Hangul. Neither covers both — Gothic has no "é" in Exposé."""

    def __init__(self, px, weight="regular"):
        self.hangul = ImageFont.truetype(GOTHIC, round(px), index=GOTHIC_INDEX[weight])
        self.latin = ImageFont.truetype(SF, round(px))
        # Axes: width, optical size, grade, weight. Small sizes get the Text cut.
        self.latin.set_variation_by_axes([100, min(96, max(17, px / 2.5)), 400, SF_WEIGHT[weight]])
        metrics = [self.hangul.getmetrics(), self.latin.getmetrics()]
        self.ascent = max(a for a, _ in metrics)
        self.descent = max(d for _, d in metrics)

    def runs(self, s):
        out = []
        for ch in s:
            # Spaces stay with the run they follow rather than splitting it.
            font = self.hangul if is_hangul(ch) else (
                out[-1][0] if ch == " " and out else self.latin)
            if out and out[-1][0] is font:
                out[-1][1] += ch
            else:
                out.append([font, ch])
        return out

    def getlength(self, s):
        return sum(font.getlength(run) for font, run in self.runs(s))

    def height(self, s, spacing=0):
        lines = s.count("\n") + 1
        return lines * (self.ascent + self.descent) + (lines - 1) * spacing


_symbol_dir = os.path.join(tempfile.gettempdir(), "TrackpadRemote-symbols")


def symbol(name, px, weight="regular", color=WHITE):
    spec = f"{name}@{round(px)}@{weight}@{color[0]:02X}{color[1]:02X}{color[2]:02X}"
    path = os.path.join(_symbol_dir, spec + ".png")
    if not os.path.exists(path):
        os.makedirs(_symbol_dir, exist_ok=True)
        run(["swift", os.path.join(ROOT, "Tools/render_symbols.swift"), _symbol_dir, spec])
    return Image.open(path).convert("RGBA")


def over(canvas, layer, x, y):
    """alpha_composite that tolerates a layer hanging off any edge."""
    x, y = int(round(x)), int(round(y))
    left, top = max(0, -x), max(0, -y)
    right = min(layer.width, canvas.width - x)
    bottom = min(layer.height, canvas.height - y)
    if right > left and bottom > top:
        canvas.alpha_composite(layer.crop((left, top, right, bottom)), (x + left, y + top))


def stamp(canvas, box, paint):
    """Paint shapes inside `box` at SS× and composite them down, antialiased.

    `paint(draw, T, k)` gets T(x, y) mapping canvas coordinates into the
    supersampled layer, and k to scale lengths.
    """
    x0, y0 = math.floor(box[0]), math.floor(box[1])
    w, h = math.ceil(box[2]) - x0, math.ceil(box[3]) - y0
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    paint(ImageDraw.Draw(big), lambda x, y: ((x - x0) * SS, (y - y0) * SS), SS)
    over(canvas, big.resize((w, h), Image.LANCZOS), x0, y0)


def rrect_mask(w, h, r):
    big = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, w * SS - 1, h * SS - 1], radius=r * SS, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def text(canvas, xy, s, face, fill=WHITE, anchor="la", spacing=0):
    """Text blended over whatever is beneath it; returns its line box.

    `anchor` is horizontal l/m/r then vertical a (top) / m (middle) / s
    (baseline), as in Pillow. Lines align within the block the same way.
    Drawn as a coverage mask under a flat colour, because ImageDraw writes
    translucent ink straight into the alpha channel instead of blending.
    """
    lines = s.split("\n")
    widths = [face.getlength(line) for line in lines]
    w, h = max(widths), face.height(s, spacing)
    x0 = xy[0] - {"l": 0, "m": w / 2, "r": w}[anchor[0]]
    y0 = xy[1] - {"a": 0, "m": h / 2, "s": face.ascent}[anchor[1]]

    pad = face.descent + 4      # glyphs may overshoot the line box
    ox, oy = math.floor(x0) - pad, math.floor(y0) - pad
    mask = Image.new("L", (math.ceil(w) + 2 * pad + 1, math.ceil(h) + 2 * pad + 1), 0)
    d = ImageDraw.Draw(mask)
    for i, (line, lw) in enumerate(zip(lines, widths)):
        x = x0 - ox + {"l": 0, "m": (w - lw) / 2, "r": w - lw}[anchor[0]]
        baseline = y0 - oy + face.ascent + i * (face.ascent + face.descent + spacing)
        for font, run in face.runs(line):
            d.text((x, baseline), run, font=font, fill=255, anchor="ls")
            x += font.getlength(run)

    alpha = fill[3] if len(fill) == 4 else 255
    layer = Image.new("RGBA", mask.size, tuple(fill[:3]) + (0,))
    layer.putalpha(mask.point(lambda v: v * alpha // 255))
    over(canvas, layer, ox, oy)
    return (x0, y0, x0 + w, y0 + h)


def fit(s, max_w, px, face):
    """Largest size <= px at which every line of `s` fits in max_w."""
    while px > 10 and max(face(px).getlength(line) for line in s.split("\n")) > max_w:
        px -= 2
    return face(px)


def with_shadow(canvas, layer, x, y, blur, dy, opacity):
    pad = blur * 3
    alpha = Image.new("L", (layer.width + 2 * pad, layer.height + 2 * pad), 0)
    alpha.paste(layer.getchannel("A"), (pad, pad))
    alpha = alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda a: int(a * opacity))
    shadow = Image.new("RGBA", alpha.size, (0, 10, 30, 0))
    shadow.putalpha(alpha)
    over(canvas, shadow, x - pad, y - pad + dy)
    over(canvas, layer, x, y)


def backdrop(size):
    """Brand-blue ground with a soft light top-left, like the app icon."""
    w, h = size
    bg = linear_gradient(BG_TOP, BG_BOTTOM, size).convert("RGBA")
    sw, sh = w // 8, h // 8
    glow = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(glow).ellipse([-sw * 0.25, -sh * 0.7, sw * 0.6, sh * 0.55], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(sw * 0.08)).resize(size, Image.BICUBIC)
    bg.paste(Image.new("RGBA", size, WHITE + (255,)), (0, 0), glow)
    return bg


def caption(canvas, title, subtitle, top, title_px, sub_px):
    """Centred title and subtitle; either may break lines with "\\n", and
    shrinks rather than running past the canvas margins."""
    cx, max_w = canvas.width / 2, canvas.width - 160
    title_face = fit(title, max_w, title_px, lambda p: Face(p, "bold"))
    box = text(canvas, (cx, top), title, title_face, anchor="ma", spacing=round(title_px * 0.1))
    sub_face = fit(subtitle, max_w, sub_px, lambda p: Face(p, "medium"))
    text(canvas, (cx, box[3] + sub_px * 0.55), subtitle, sub_face,
         fill=WHITE + (215,), anchor="ma", spacing=round(sub_px * 0.25))


def catmull_rom(points, steps=24):
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for j in range(steps):
            t = j / steps
            out.append(tuple(
                0.5 * (2 * p1[a] + (p2[a] - p0[a]) * t
                       + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t * t
                       + (3 * p1[a] - p0[a] - 3 * p2[a] + p3[a]) * t ** 3)
                for a in (0, 1)))
    out.append(tuple(points[-1]))
    return out


def trail(canvas, points, pt, color=WHITE, width=16, strength=150):
    """A stroke that fades in towards its last point: motion, finger at the end."""
    path = catmull_rom(points)
    lengths = [0.0]
    for a, b in zip(path, path[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = lengths[-1]
    r_max = width / 2 * pt
    xs, ys = [p[0] for p in path], [p[1] for p in path]
    box = (min(xs) - r_max - 2, min(ys) - r_max - 2, max(xs) + r_max + 2, max(ys) + r_max + 2)

    def paint(d, T, k):
        n = max(2, int(total / 1.5))
        seg = 0
        for i in range(n + 1):
            s = total * i / n
            while seg < len(path) - 2 and lengths[seg + 1] < s:
                seg += 1
            span = (lengths[seg + 1] - lengths[seg]) or 1
            u = min(1.0, (s - lengths[seg]) / span)
            x = path[seg][0] + (path[seg + 1][0] - path[seg][0]) * u
            y = path[seg][1] + (path[seg + 1][1] - path[seg][1]) * u
            t = i / n
            r = (0.15 + 0.85 * t) * r_max * k
            cx, cy = T(x, y)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (int(strength * t ** 1.3),))

    stamp(canvas, box, paint)


def ripple(canvas, c, pt):
    """The app's own touch ring (TrackpadUIView.showRipple), caught mid-expand."""
    r, R = 26 * pt, 38 * pt
    line = 1.5 * pt

    def paint(d, T, k):
        x, y = T(*c)
        d.ellipse([x - R * k, y - R * k, x + R * k, y + R * k],
                  outline=TINT + (80,), width=round(line * k))
        d.ellipse([x - r * k, y - r * k, x + r * k, y + r * k],
                  fill=TINT + (60,), outline=TINT + (235,), width=round(line * k))
        f = 15 * pt * k
        d.ellipse([x - f, y - f, x + f, y + f], fill=WHITE + (70,))

    stamp(canvas, (c[0] - R - 4, c[1] - R - 4, c[0] + R + 4, c[1] + R + 4), paint)


# ---------------------------------------------------------------------------
# iOS


def pad_rect(shot):
    """Bounds of the trackpad surface in a capture, found by its fill colour."""
    rgb = shot.convert("RGB")
    ref = Image.new("RGB", rgb.size, PAD_FILL)
    from PIL import ImageChops
    diff = ImageChops.difference(rgb, ref).convert("L").point(lambda v: 255 if v < 4 else 0)
    return diff.getbbox()


def staged(name, trails=(), taps=()):
    """A capture with touches drawn on its pad; coordinates are pad fractions."""
    shot = Image.open(os.path.join(CAPTURES, f"{name}.png")).convert("RGBA")
    if not (trails or taps):
        return shot
    x0, y0, x1, y1 = pad_rect(shot)
    pt = shot.height / 440      # 6.9" iPhone: 440pt tall in landscape

    def P(u, v):
        return (x0 + u * (x1 - x0), y0 + v * (y1 - y0))

    for path in trails:
        trail(shot, [P(*p) for p in path], pt, color=(120, 180, 255))
    for path in trails:
        ripple(shot, P(*path[-1]), pt)
    for tap in taps:
        ripple(shot, P(*tap), pt)
    return shot


def iphone(screen, width):
    """Frame a landscape capture in a generic iPhone body `width` px wide."""
    bezel = max(6, round(width * 0.016))
    rim = max(2, round(width * 0.0028))
    sw = width - 2 * bezel
    sh = round(sw * screen.height / screen.width)
    w, h = width, sh + 2 * bezel
    r_screen = round(sh * 0.141)
    r_body = r_screen + bezel

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(linear_gradient((118, 120, 128), (52, 53, 58), (w, h)).convert("RGBA"),
              (0, 0), rrect_mask(w, h, r_body))
    out.paste(Image.new("RGBA", (w - 2 * rim, h - 2 * rim), (6, 6, 8, 255)),
              (rim, rim), rrect_mask(w - 2 * rim, h - 2 * rim, r_body - rim))
    out.paste(screen.resize((sw, sh), Image.LANCZOS), (bezel, bezel),
              rrect_mask(sw, sh, r_screen))

    # Dynamic Island, on the left: the capture's top-of-portrait edge ends up there.
    # The simulator already paints a black pill into the capture; these match it
    # so the frame's island covers it exactly instead of leaving a sliver.
    iw, ih = round(sh * 0.084), round(sh * 0.286)
    out.paste(Image.new("RGBA", (iw, ih), (0, 0, 0, 255)),
              (bezel + round(sh * 0.031), bezel + (sh - ih) // 2), rrect_mask(iw, ih, iw // 2))
    return out


# Pad fractions: (0, 0) is the pad's top-left corner.
IOS_PAGES = [
    dict(file="01-trackpad", capture="connected",
         title="iPhone을\nMac의 트랙패드로",
         subtitle="책상 위에 내려놓고 쓸어 보세요.\n커서가 손끝을 그대로 따라옵니다.",
         trails=[[(0.20, 0.80), (0.36, 0.60), (0.52, 0.50), (0.64, 0.40)]]),
    dict(file="02-click", capture="connected",
         title="탭은 클릭,\n두 손가락 탭은 우클릭",
         subtitle="빠르게 두 번 탭하면 더블클릭,\n두 번 탭한 채로 끌면 드래그",
         taps=[(0.30, 0.52), (0.62, 0.46), (0.73, 0.56)]),
    dict(file="03-scroll-zoom", capture="connected",
         title="두 손가락으로\n스크롤과 확대",
         subtitle="자연스러운 방향의 스크롤,\n오므리고 벌려서 확대·축소",
         trails=[[(0.46, 0.50), (0.40, 0.42), (0.32, 0.32)],
                 [(0.56, 0.60), (0.62, 0.68), (0.70, 0.78)]]),
    dict(file="04-three-finger", capture="connected",
         title="세 손가락으로\nMission Control",
         subtitle="위로 Mission Control, 아래로 App Exposé,\n좌우로 데스크탑 전환",
         trails=[[(0.38, 0.80), (0.38, 0.36)],
                 [(0.50, 0.76), (0.50, 0.30)],
                 [(0.62, 0.80), (0.62, 0.36)]]),
    dict(file="05-auto-connect", capture="searching",
         title="IP 입력 없이\n알아서 연결",
         subtitle="Mac에서 TrackpadServer를 켜 두면\niPhone이 바로 찾아냅니다"),
    dict(file="06-settings", capture="settings",
         title="내 손에 맞는\n감도로",
         subtitle="포인터 속도와 가속,\n스크롤 방향, 제스처 민감도까지"),
]


def compose_ios():
    out_dir = os.path.join(OUT, "iOS")
    os.makedirs(out_dir, exist_ok=True)
    for page in IOS_PAGES:
        canvas = backdrop(IOS_SIZE)
        caption(canvas, page["title"], page["subtitle"], top=170, title_px=100, sub_px=48)
        # The app is landscape-only but the page is portrait, so the phone stands
        # upright with its UI sideways — Dynamic Island on top, the way the
        # device's own framebuffer is oriented — rather than shrinking to a strip.
        device = iphone(staged(page["capture"], page.get("trails", ()), page.get("taps", ())),
                        canvas.height - IOS_DEVICE_TOP - 88).transpose(Image.ROTATE_270)
        with_shadow(canvas, device, (canvas.width - device.width) // 2, IOS_DEVICE_TOP,
                    blur=40, dy=24, opacity=0.5)
        save(canvas, out_dir, page["file"])


# ---------------------------------------------------------------------------
# macOS

# Mirrors the MenuBarExtra in macOS/TrackpadServerApp.swift. `None` is a Divider;
# a label with no shortcut and disabled=True is one of its plain `Text` rows.
MAC_MENUS = {
    "connected": [("Connected: iPhone", True, None), ("Disconnect", False, None),
                  None, ("Quit", False, "⌘Q")],
    "waiting": [("Waiting for iPhone…", True, None), ("Get the iPhone App…", False, None),
                None, ("Quit", False, "⌘Q")],
}


def wallpaper(size):
    w, h = size
    sw, sh = max(8, w // 10), max(8, h // 10)
    base = linear_gradient((24, 36, 92), (6, 8, 24), (sw, sh)).convert("RGB")
    for (cx, cy), r, col in [((0.12, 0.85), 0.42, (84, 64, 196)),
                             ((0.82, 0.28), 0.48, (28, 108, 226)),
                             ((0.62, 1.00), 0.34, (150, 62, 176))]:
        blob = Image.new("L", (sw, sh), 0)
        ImageDraw.Draw(blob).ellipse(
            [(cx - r) * sw, cy * sh - r * sw * 0.8, (cx + r) * sw, cy * sh + r * sw * 0.8], fill=150)
        blob = blob.filter(ImageFilter.GaussianBlur(r * sw * 0.35))
        base.paste(Image.new("RGB", (sw, sh), col), (0, 0), blob)
    return base.resize(size, Image.BICUBIC).convert("RGBA")


def mac_menu(desk, items, left, top, k):
    font = Face(13 * k)
    row, sep, pad_y, inset = 24 * k, 11 * k, 5 * k, 14 * k
    width = max(font.getlength(label) + (font.getlength(key) + 34 * k if key else 0)
                for label, _, key in filter(None, items))
    w = round(max(width + 2 * inset, 190 * k))
    h = round(2 * pad_y + sum(row if item else sep for item in items))
    left = min(left, desk.width - w - 8 * k)

    # Menus are a material: the desktop, blurred and darkened, shows through.
    region = (round(left), round(top), round(left) + w, round(top) + h)
    panel = desk.crop(region).filter(ImageFilter.GaussianBlur(22 * k))
    panel.alpha_composite(Image.new("RGBA", panel.size, (36, 36, 40, 178)))
    panel.putalpha(rrect_mask(w, h, round(11 * k)))
    stamp(panel, (0, 0, w, h), lambda d, T, s: d.rounded_rectangle(
        [0, 0, w * s - 1, h * s - 1], radius=11 * k * s,
        outline=WHITE + (40,), width=round(1 * k * s)))
    with_shadow(desk, panel, left, top, blur=round(16 * k), dy=round(8 * k), opacity=0.55)

    y = top + pad_y
    for item in items:
        if item is None:
            desk.alpha_composite(Image.new("RGBA", (round(w - 2 * 10 * k), max(1, round(k))),
                                           WHITE + (36,)),
                                 (round(left + 10 * k), round(y + sep / 2)))
            y += sep
            continue
        label, disabled, key = item
        text(desk, (left + inset, y + row / 2), label, font,
             fill=WHITE + ((105,) if disabled else (240,)), anchor="lm")
        if key:
            text(desk, (left + w - inset, y + row / 2), key, font,
                 fill=WHITE + (120,), anchor="rm")
        y += row


def mac_cursor(canvas, tip, height):
    pad = round(height * 0.4)
    layer = Image.new("RGBA", (round(height * 0.6) + 2 * pad, height + 2 * pad), (0, 0, 0, 0))

    def paint(d, T, k):
        pts = [T(pad + x, pad + y) for x, y in cursor_polygon(0, 0, height)]
        d.polygon(pts, fill=(0, 0, 0, 255), outline=WHITE + (255,), width=round(height * 0.055 * k))

    stamp(layer, (0, 0, layer.width, layer.height), paint)
    with_shadow(canvas, layer, tip[0] - pad, tip[1] - pad,
                blur=max(2, round(height * 0.08)), dy=round(height * 0.06), opacity=0.45)


def mac_desktop(size, k, menu=None, cursor=None, cursor_trail=None):
    """Dark-mode desktop, UI at `k` px per point, TrackpadServer's menu open.

    `cursor` and `cursor_trail` are fractions of the desktop.
    """
    w, h = size
    desk = wallpaper(size)
    bar = round(30 * k)
    mid = bar / 2
    desk.alpha_composite(Image.new("RGBA", (w, bar), (0, 0, 0, 60)))

    face = Face(13.5 * k, "medium")

    # Status items first, right to left. On a narrow display the app menus give
    # way to them rather than running underneath, as on a real Mac.
    x = w - 20 * k
    clock = "6월 9일 (화) 오전 9:41"
    text(desk, (x, mid), clock, face, anchor="rm")
    x -= face.getlength(clock) + 22 * k
    for name in ["switch.2", "wifi", "battery.100percent"]:
        icon = symbol(name, 14 * k)
        over(desk, icon, x - icon.width, mid - icon.height / 2)
        x -= icon.width + 22 * k

    ours = symbol("rectangle.and.hand.point.up.left.fill" if menu == "connected"
                  else "rectangle.and.hand.point.up.left", 14 * k)
    hw, hh = ours.width + 18 * k, 23 * k
    hx = x - ours.width / 2 - hw / 2
    if menu:
        stamp(desk, (hx, mid - hh / 2, hx + hw, mid + hh / 2), lambda d, T, s: d.rounded_rectangle(
            [*T(hx, mid - hh / 2), *T(hx + hw, mid + hh / 2)], radius=7 * k * s, fill=WHITE + (56,)))
    over(desk, ours, x - ours.width, mid - ours.height / 2)

    x = 20 * k
    apple = symbol("apple.logo", 15 * k)
    over(desk, apple, x, mid - apple.height / 2)
    x += apple.width + 20 * k
    for title in ["Finder", "파일", "편집", "보기", "이동", "윈도우", "도움말"]:
        f = Face(13 * k, "bold") if title == "Finder" else face
        if x + f.getlength(title) > hx - 24 * k:
            break
        text(desk, (x, mid), title, f, anchor="lm")
        x += f.getlength(title) + 19 * k

    if cursor_trail:
        trail(desk, [(u * w, v * h) for u, v in cursor_trail], k, width=10, strength=110)
    if menu:
        mac_menu(desk, MAC_MENUS[menu], hx, bar + 5 * k, k)
    if cursor:
        mac_cursor(desk, (cursor[0] * w, cursor[1] * h), round(26 * k))
    return desk


def mac_display(size, k, **desktop):
    """A black-bezelled display around a desktop."""
    w, h = size
    bezel, radius = round(w * 0.012), round(w * 0.02)
    frame = Image.new("RGBA", size, (0, 0, 0, 0))
    frame.paste(Image.new("RGBA", size, (70, 72, 78, 255)), (0, 0), rrect_mask(w, h, radius))
    frame.paste(Image.new("RGBA", (w - 4, h - 4), (10, 10, 12, 255)), (2, 2),
                rrect_mask(w - 4, h - 4, radius - 2))
    sw, sh = w - 2 * bezel, h - 2 * bezel
    frame.paste(mac_desktop((sw, sh), k, **desktop), (bezel, bezel),
                rrect_mask(sw, sh, radius - bezel))
    return frame


HERO_TRAIL = [[(0.20, 0.80), (0.36, 0.60), (0.52, 0.50), (0.64, 0.40)]]


def mac_hero():
    c = backdrop(MAC_SIZE)
    caption(c, "iPhone으로 Mac을 조작하세요",
            "메뉴 막대 앱 하나면 iPhone이 무선 트랙패드가 됩니다",
            top=120, title_px=124, sub_px=58)
    display = mac_display((2300, 1500), 2.3, menu="connected", cursor=(0.60, 0.44),
                          cursor_trail=[(0.36, 0.74), (0.46, 0.56), (0.60, 0.44)])
    with_shadow(c, display, (c.width - display.width) // 2 + 60, 440, blur=50, dy=30, opacity=0.5)
    phone = iphone(staged("connected", HERO_TRAIL), 1180)
    with_shadow(c, phone, 150, c.height - phone.height - 80, blur=44, dy=28, opacity=0.6)
    return c


def mac_menubar():
    c = backdrop(MAC_SIZE)
    title, sub = "메뉴 막대에서\n조용히 기다립니다", "Dock을 차지하지 않고,\niPhone이 연결될 때까지\n아무것도 하지 않습니다."
    title_face, sub_face = Face(130, "bold"), Face(62, "medium")
    th, sh = title_face.height(title, 20), sub_face.height(sub, 14)
    top = (c.height - (th + 80 + sh)) / 2
    text(c, (230, top), title, title_face, spacing=20)
    text(c, (230, top + th + 80), sub, sub_face, fill=WHITE + (215,), spacing=14)

    display = mac_display((1520, 1560), 3.3, menu="waiting")
    with_shadow(c, display, 1220, 300, blur=50, dy=30, opacity=0.5)
    return c


GESTURES = [
    ("cursorarrow.motionlines", "한 손가락으로 이동", "가속이 붙는 부드러운 커서"),
    ("cursorarrow.click.2", "탭 · 두 손가락 탭", "클릭, 더블클릭, 우클릭"),
    ("hand.draw", "두 번 탭하고 끌기", "창과 파일을 그대로 드래그"),
    ("hand.pinch", "두 손가락", "스크롤과 핀치 확대·축소"),
    ("rectangle.3.group", "세 손가락 위 · 아래", "Mission Control · App Exposé"),
    ("rectangle.2.swap", "세 손가락 좌 · 우", "데스크탑 사이를 전환"),
]


def mac_gestures():
    c = backdrop(MAC_SIZE)
    caption(c, "익숙한 트랙패드 제스처 그대로",
            "클릭부터 Mission Control까지, 손이 기억하는 대로",
            top=140, title_px=124, sub_px=58)
    cols, gap, left, top = 3, 64, 220, 560
    cw = (c.width - 2 * left - gap * (cols - 1)) // cols
    ch = 500
    for i, (name, title, desc) in enumerate(GESTURES):
        x, y = left + (i % cols) * (cw + gap), top + (i // cols) * (ch + gap)
        stamp(c, (x, y, x + cw, y + ch), lambda d, T, s, x=x, y=y: d.rounded_rectangle(
            [*T(x, y), *T(x + cw, y + ch)], radius=48 * s,
            fill=WHITE + (26,), outline=WHITE + (52,), width=2 * s))
        badge = 168
        stamp(c, (x + 72, y + 72, x + 72 + badge, y + 72 + badge), lambda d, T, s, x=x, y=y: d.ellipse(
            [*T(x + 72, y + 72), *T(x + 72 + badge, y + 72 + badge)], fill=WHITE + (235,)))
        icon = symbol(name, 78, "medium", BLUE_BOTTOM)
        over(c, icon, x + 72 + (badge - icon.width) / 2, y + 72 + (badge - icon.height) / 2)
        text(c, (x + 72, y + 300), title, fit(title, cw - 144, 64, lambda p: Face(p, "bold")))
        text(c, (x + 72, y + 392), desc, fit(desc, cw - 144, 46, lambda p: Face(p, "medium")),
             fill=WHITE + (205,))
    return c


def mac_pairing():
    c = backdrop(MAC_SIZE)
    caption(c, "암호화된 1:1 연결",
            "근처의 iPhone을 자동으로 찾고, 한 번에 한 대만 커서를 움직일 수 있습니다",
            top=140, title_px=124, sub_px=58)
    cy = 1060
    phone = iphone(staged("connected", taps=[(0.5, 0.55)]), 980)
    px = 160
    with_shadow(c, phone, px, cy - phone.height // 2, blur=44, dy=28, opacity=0.55)

    display = mac_display((1120, 820), 2.5, menu="connected")
    dx = c.width - display.width - 160
    with_shadow(c, display, dx, cy - display.height // 2, blur=50, dy=30, opacity=0.5)

    # The link: dots from phone to display, a lock riding in the middle.
    x0, x1 = px + phone.width + 50, dx - 50
    mx, r = (x0 + x1) / 2, 96

    def dots(d, T, s):
        n = 12
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            if abs(x - mx) < r + 20:
                continue
            X, Y = T(x, cy)
            d.ellipse([X - 9 * s, Y - 9 * s, X + 9 * s, Y + 9 * s], fill=WHITE + (200,))
        X, Y = T(mx, cy)
        d.ellipse([X - r * s, Y - r * s, X + r * s, Y + r * s], fill=WHITE + (255,))

    stamp(c, (x0 - 12, cy - r - 4, x1 + 12, cy + r + 4), dots)
    lock = symbol("lock.fill", 84, "semibold", BLUE_BOTTOM)
    over(c, lock, mx - lock.width / 2, cy - lock.height / 2)
    text(c, (mx, cy + r + 50), "Wi-Fi · Bluetooth", Face(44, "semibold"),
         fill=WHITE + (220,), anchor="ma")
    return c


MAC_PAGES = [
    ("01-hero", mac_hero),
    ("02-menu-bar", mac_menubar),
    ("03-gestures", mac_gestures),
    ("04-pairing", mac_pairing),
]


def compose_mac():
    out_dir = os.path.join(OUT, "macOS")
    os.makedirs(out_dir, exist_ok=True)
    for name, draw in MAC_PAGES:
        save(draw(), out_dir, name)


def save(canvas, out_dir, name):
    # App Store Connect rejects screenshots with an alpha channel.
    path = os.path.join(out_dir, f"{name}.png")
    canvas.convert("RGB").save(path, "PNG")
    print(f"wrote {os.path.relpath(path, ROOT)} {canvas.size[0]}x{canvas.size[1]}")


def main():
    if sys.argv[1:] == ["capture"]:
        capture()
        return
    if not os.path.exists(os.path.join(CAPTURES, "connected.png")):
        sys.exit("no captures yet — run `python3 Tools/make_screenshots.py capture` first")
    only = sys.argv[1:]
    if not only or "ios" in only:
        compose_ios()
    if not only or "mac" in only:
        compose_mac()


if __name__ == "__main__":
    main()
