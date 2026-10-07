"""Generate Spectra Signer app icons: a spectrum-gradient signature stroke.

Usage: python scripts/make_icon.py  (requires Pillow)
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..")
S = 4096  # supersample canvas
OUT = 1024
u = S / 1024

SPECTRUM = [(255, 59, 120), (255, 149, 0), (255, 214, 10), (52, 199, 89), (10, 180, 255), (94, 92, 230), (191, 90, 242)]

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def spectrum_at(t):
    t = min(max(t, 0), 1) * (len(SPECTRUM) - 1)
    i = min(int(t), len(SPECTRUM) - 2)
    return lerp(SPECTRUM[i], SPECTRUM[i + 1], t - i)

def background(top, bottom):
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S) + (255,))
    return img

def signature_points():
    """A looping handwritten 'S'-like flourish followed by an underline swoosh."""
    pts = []
    rx, ry = 140, 105
    # top bowl: from upper-right, counter-clockwise over the top and left, to the middle
    for k in range(0, 241):
        a = math.radians(35 + k)
        pts.append((512 + rx * math.cos(a), 365 - ry * math.sin(a)))
    # bottom bowl: from the middle, clockwise around the right, to lower-left
    for k in range(1, 241):
        a = math.radians(90 - k)
        pts.append((512 + rx * math.cos(a), 575 - ry * math.sin(a)))
    # underline swoosh sweeping out to the right
    p0 = pts[-1]
    c, p2 = (470, 790), (840, 700)
    for k in range(1, 160):
        t = k / 159
        pts.append(tuple((1 - t) ** 2 * p0[i] + 2 * (1 - t) * t * c[i] + t * t * p2[i] for i in range(2)))
    return [(x * u, y * u) for x, y in pts]

def glyph(mono=None):
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    pts = signature_points()
    n = len(pts)
    for i in range(n - 1):
        w = 64 - 30 * (i / n)                    # pen pressure thinning
        d.line([pts[i], pts[i + 1]], fill=255, width=int(w * u))
        r = w * u / 2
        d.ellipse([pts[i][0] - r, pts[i][1] - r, pts[i][0] + r, pts[i][1] + r], fill=255)
    # sparkle "seal" dot at the end of the stroke
    ex, ey = pts[-1]
    r = 40 * u
    d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=255)

    if mono:
        color = Image.new("RGBA", (S, S), mono + (255,))
    else:
        color = Image.new("RGBA", (S, S))
        cd = ImageDraw.Draw(color)
        for x in range(S):  # diagonal-ish spectrum sweep
            cd.line([(x, 0), (x, S)], fill=spectrum_at((x / S - 0.22) / 0.62) + (255,))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(color, (0, 0), mask)
    glow = layer.filter(ImageFilter.GaussianBlur(36 * u))
    return Image.alpha_composite(glow, layer)

def save(img, path):
    img.resize((OUT, OUT), Image.LANCZOS).save(path)
    print("wrote", path)

appiconset = os.path.join(ROOT, "App/Assets.xcassets/AppIcon.appiconset")

g = glyph()
light = Image.alpha_composite(background((36, 28, 78), (10, 8, 28)), g).convert("RGB")
dark = Image.alpha_composite(background((18, 14, 40), (0, 0, 0)), g).convert("RGB")
tint = Image.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 255)), glyph(mono=(235, 235, 235))).convert("RGB")
save(light, os.path.join(appiconset, "spectra.png"))
save(dark, os.path.join(appiconset, "spectra_dark.png"))
save(tint, os.path.join(appiconset, "spectra_tint.png"))
save(light, os.path.join(ROOT, "App/Assets.xcassets/Logo.imageset/logo.png"))
