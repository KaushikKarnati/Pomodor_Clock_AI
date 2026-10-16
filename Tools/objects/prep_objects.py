"""Normalize generated object art to the tomato's 680-unit frame and measure twist seams.

Usage: python3 prep_objects.py Tools/objects/source Resources/tomato.png <work dir>
Writes <name>-680.png and geometry.json (band numbers copied into Core/TimerTheme.swift)."""
import sys, json, math, os
from PIL import Image
IMG, TOMATO, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
SRC = {'tomato': TOMATO, **{k: f'{IMG}/{k}.webp' for k in ['apple', 'egg', 'lemon', 'hourglass', 'alarmClock']}}
TWIST = ['tomato', 'apple', 'egg', 'lemon']
FRAME = 680

def clean(im):
    a = im.getchannel('A').point(lambda v: 0 if v < 24 else v)
    im.putalpha(a)
    return im

def normalize(name, im):
    if name == 'tomato':
        return im  # already the reference frame
    bb = im.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    obj = im.crop(bb)
    w, h = obj.size
    scale = min(0.97 * FRAME / w, 0.985 * FRAME / h)
    obj = obj.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    canvas = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    x = (FRAME - obj.width) // 2
    y = round(0.99 * FRAME) - obj.height
    canvas.alpha_composite(obj, (x, y))
    return canvas

def seam(im):
    """Fit the dark twist seam as the front half of an ellipse: y = cy + ry*sqrt(1-((x-cx)/rx)^2)."""
    a = im.getchannel('A'); L = im.convert('L')
    bb = a.point(lambda v: 255 if v > 200 else 0).getbbox()
    x0, y0, x1, y1 = bb; h = y1 - y0
    pts = []
    cxg = (x0 + x1) / 2
    for x in range(int(cxg - 0.30 * (x1 - x0)), int(cxg + 0.30 * (x1 - x0)), 3):
        best = None
        for y in range(y0 + int(0.40 * h), y0 + int(0.80 * h)):
            if a.getpixel((x, y)) < 250: continue
            v = L.getpixel((x, y)); up = L.getpixel((x, y - 4)); dn = L.getpixel((x, y + 4))
            score = (up + dn) / 2 - v  # dark thin line
            if best is None or score > best[0]: best = (score, y)
        if best and best[0] > 6: pts.append((x, best[1]))
    # robust: median filter on y
    pts.sort()
    ys = [p[1] for p in pts]
    med = sorted(ys)[len(ys) // 2]
    pts = [p for p in pts if abs(p[1] - med) < 0.08 * h]
    # half-width of the object at the seam row
    row = med
    xs = [x for x in range(im.width) if a.getpixel((x, row)) > 128]
    rx = (xs[-1] - xs[0]) / 2; cx = (xs[-1] + xs[0]) / 2
    # least squares for cy, ry with s = sqrt(1-((x-cx)/rx)^2)
    S = [math.sqrt(max(0, 1 - ((x - cx) / rx) ** 2)) for x, _ in pts]
    Y = [y for _, y in pts]
    n = len(S); ss = sum(s * s for s in S); s1 = sum(S); sy = sum(s * y for s, y in zip(S, Y)); y1s = sum(Y)
    det = n * ss - s1 * s1
    ry = (n * sy - s1 * y1s) / det; cy = (y1s - ry * s1) / n
    return dict(cx=cx, cy=cy, rx=rx, ry=ry, n=len(pts), front=cy + ry)

out = {}
norm = {}
for name, path in SRC.items():
    im = clean(Image.open(path).convert('RGBA'))
    im = normalize(name, im)
    norm[name] = im
    info = {}
    if name in TWIST:
        info['seam'] = seam(im)
    out[name] = info
t = out['tomato']['seam']
TOM_BAND = dict(cx=341.5, cy=361.8, rx=282.0, ry=83.1)
# Fraction of the seam half-width the band may span (eggs and lemons narrow above the seam),
# and dark ink where white markings are not legible.
FIT = {'apple': 0.99, 'egg': 0.93, 'lemon': 0.93}
INK = {'tomato': 'white', 'apple': 'white', 'egg': 'dark', 'lemon': 'dark'}
for name in TWIST:
    s = out[name]['seam']
    if name == 'tomato':
        band = dict(TOM_BAND, scale=1.0)
    else:
        rx = s['rx'] * FIT[name]; k = rx / TOM_BAND['rx']
        band = dict(cx=round(s['cx'], 1), rx=round(rx, 1),
                    ry=round(TOM_BAND['ry'] * (s['ry'] / t['ry']), 1),
                    cy=round(s['cy'] + (TOM_BAND['cy'] - t['cy']) * k, 1), scale=round(k, 3))
    band['ink'] = INK[name]
    out[name]['band'] = band
for name, im in norm.items():
    im.save(f'{OUT}/{name}-680.png')
json.dump(out, open(f'{OUT}/geometry.json', 'w'), indent=1)
print(json.dumps(out, indent=1))
