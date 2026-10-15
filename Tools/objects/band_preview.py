import sys, json, math
from PIL import Image, ImageDraw, ImageFont
A = sys.argv[1]
geo = json.load(open(f'{A}/geometry.json'))
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 34)
except Exception:
    font = ImageFont.load_default()
def draw_band(im, band, minutes):
    """Python port of DialMarkings.body (TomatoView.swift) with a BandGeometry."""
    cx, cy, rx, ry, k = band['cx'], band['cy'], band['rx'], band['ry'], band['scale']
    INKC = (255, 255, 255) if band.get('ink') != 'dark' else (38, 34, 30)
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    rho = minutes / 60 * math.tau
    for m in range(60):
        ang = m / 60 * math.tau
        cos_ = math.cos(ang) * math.cos(rho) + math.sin(ang) * math.sin(rho)
        if cos_ < 0.06: continue
        sin_ = math.sin(ang) * math.cos(rho) - math.cos(ang) * math.sin(rho)
        major = m % 5 == 0
        x = cx + rx * sin_; y = cy + ry * cos_
        length = (19 if major else 13) * k; width = (5.2 if major else 3.6) * max(0.3, cos_) * k
        t = min(1, max(0, (cos_ - 0.06) / 0.36)); alpha = int(255 * 0.95 * t * t * (3 - 2 * t))
        d.rectangle([x - width / 2, y - 8 * k - length, x + width / 2, y - 8 * k], fill=(INKC[0], INKC[1], INKC[2], alpha))
        if major:
            tx = cx + rx * 0.985 * sin_; ty = cy + ry * 0.985 * cos_ - 50 * k
            d.text((tx, ty), str(m), font=font, fill=(INKC[0], INKC[1], INKC[2], alpha), anchor='mm')
    out = im.copy(); out.alpha_composite(layer); return out
tiles = []
for name in ['tomato', 'apple', 'egg', 'lemon']:
    im = Image.open(f'{A}/{name}-680.png').convert('RGBA')
    bg = Image.new('RGBA', im.size, (7, 8, 11, 255)); bg.alpha_composite(im)
    tiles.append(draw_band(bg, geo[name]['band'], 25))
sheet = Image.new('RGBA', (680 * 2, 680 * 2), (7, 8, 11, 255))
for i, t in enumerate(tiles): sheet.alpha_composite(t, ((i % 2) * 680, (i // 2) * 680))
sheet.convert('RGB').resize((1020, 1020), Image.LANCZOS).save(f'{A}/band-preview.png')
print('ok')
