"""Exports app assets from the work dir produced by prep_objects.py and hourglass_layers.py.

Usage (from the repository root):
    python3 Tools/objects/prep_objects.py Tools/objects/source Resources/tomato.png /tmp/objects
    python3 Tools/objects/hourglass_layers.py /tmp/objects
    python3 Tools/objects/export_assets.py Tools/objects/source /tmp/objects
Writes hero images and hourglass layers to Resources/Assets.xcassets, 40 pt Live Activity minis
(@2x/@3x) to Widget/Assets.xcassets, and 240 px settings thumbnails to the app catalog."""
import json, os, sys
from PIL import Image
SRC, WORK = sys.argv[1], sys.argv[2]
APP, WID, TOMATO = 'Resources/Assets.xcassets', 'Widget/Assets.xcassets', 'Resources/tomato.png'
HERO = 960

def clean(im):
    im.putalpha(im.getchannel('A').point(lambda v: 0 if v < 24 else v)); return im

def normalize(im, frame):
    """Same proportions as prep_objects.py, so geometry measured in 680 units still applies."""
    bb = im.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox(); obj = im.crop(bb)
    w, h = obj.size; s = min(0.97 * frame / w, 0.985 * frame / h)
    obj = obj.resize((round(w * s), round(h * s)), Image.LANCZOS)
    c = Image.new('RGBA', (frame, frame), (0, 0, 0, 0))
    c.alpha_composite(obj, ((frame - obj.width) // 2, round(0.99 * frame) - obj.height)); return c

def imageset(root, name, im):
    d = f'{root}/{name}.imageset'; os.makedirs(d, exist_ok=True)
    im.save(f'{d}/{name}.png', optimize=True)
    json.dump({'images': [{'filename': f'{name}.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, open(f'{d}/Contents.json', 'w'))

heroes = {n: normalize(clean(Image.open(f'{SRC}/{n}.webp').convert('RGBA')), HERO) for n in ['apple', 'egg', 'lemon', 'alarmClock']}
for n, im in heroes.items(): imageset(APP, f'object-{n}', im)
for layer, asset in [('base', 'hourglass-base'), ('sandTop', 'hourglass-sand-top'), ('pile', 'hourglass-pile'), ('stream', 'hourglass-stream'), ('bottomMask', 'hourglass-bottom-mask')]:
    imageset(APP, asset, Image.open(f'{WORK}/hourglass-{layer}.png').convert('RGBA'))
os.makedirs(WID, exist_ok=True)
json.dump({'info': {'author': 'xcode', 'version': 1}}, open(f'{WID}/Contents.json', 'w'))
L = {k: Image.open(f'{WORK}/hourglass-{k}.png').convert('RGBA') for k in ['base', 'sandTop', 'pile', 'stream']}
hourglass = Image.new('RGBA', (680, 680), (0, 0, 0, 0))
for k in ['base', 'sandTop', 'pile', 'stream']: hourglass.alpha_composite(L[k])
for name, im in {'tomato': Image.open(TOMATO).convert('RGBA'), 'hourglass': hourglass, **heroes}.items():
    bb = im.getchannel('A').point(lambda v: 255 if v > 60 else 0).getbbox(); obj = im.crop(bb)
    s = 240 / max(obj.size); obj = obj.resize((max(1, round(obj.width * s)), max(1, round(obj.height * s))), Image.LANCZOS)
    mini = Image.new('RGBA', (240, 240), (0, 0, 0, 0)); mini.alpha_composite(obj, ((240 - obj.width) // 2, (240 - obj.height) // 2))
    imageset(APP, f'thumb-{name}', mini)
    # Live Activity images must not exceed their presentation size or the activity may fail to start.
    # The largest use is ~38 pt (64 pt dial minus padding), so ship a 40 pt image at @2x and @3x.
    d = f'{WID}/mini-{name}.imageset'; os.makedirs(d, exist_ok=True)
    for f in os.listdir(d): os.remove(f'{d}/{f}')
    images = []
    for scale, px in (('2x', 80), ('3x', 120)):
        mini.resize((px, px), Image.LANCZOS).save(f'{d}/mini-{name}@{scale}.png', optimize=True)
        images.append({'filename': f'mini-{name}@{scale}.png', 'idiom': 'universal', 'scale': scale})
    json.dump({'images': images, 'info': {'author': 'xcode', 'version': 1}}, open(f'{d}/Contents.json', 'w'))
print('exported')
