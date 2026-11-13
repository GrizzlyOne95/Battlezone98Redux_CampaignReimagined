"""Build the CR CCA cockpit atlas (crcca_cockpit_d/n/s/e.dds) from generated panel art.

The stock soviet_units_cockpit atlas is shared by every CCA cockpit, and their UVs
sample all of it (wrapping past 0..1), so the new sheet keeps the stock module
layout: each stock box gets a crop of one generated panel, cover-fitted with its
aspect ratio kept (dials stay round). Normal, specular and emissive maps are
derived from the diffuse. Units opt in by pointing their *01 material at
crcca_cockpit_*; the stock atlas stays untouched.

python Tools/Build-CCACockpitAtlas.py [--preview out.png]
Masters and prompts: References/TankCockpits/cca/atlas-src/ (see provenance.json).
"""
from pathlib import Path
import io, json, struct, sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'References/TankCockpits/cca/atlas-src'
OUT = ROOT / 'Assets/Textures'
SIZE = 2048            # diffuse/normal/specular; boxes below are in stock 1024 px
K = SIZE / 1024
SEAM = 2               # panel-gap line width at SIZE

# Panel modules cut from the generated masters (master, crop x0, y0, x1, y1).
POOL = [
    ('keypad', 1250, 330, 2280, 1135),
    ('racks', 60, 60, 600, 1070),
    ('lamps', 1480, 120, 2370, 1340),
    ('plate', 120, 380, 660, 1100),      # gauge + nameplate
    ('dial', 1330, 230, 2330, 1270),
    ('circuit', 1600, 150, 2620, 1410),
    ('switches', 360, 130, 1060, 1450),
    ('plate', 2200, 380, 2700, 1060),    # side column: toggle, knob
    ('racks', 1880, 120, 2560, 1450),
    ('pod', 1580, 600, 1925, 1440),
    ('plate', 680, 380, 1260, 1150),     # twin toggles
    ('racks', 1000, 280, 1640, 1460),
    ('plate', 1300, 120, 2200, 1000),    # welded plate, red stripe
    ('circuit', 2200, 150, 2560, 1410),
    ('plate', 700, 1130, 1260, 1440),    # hazard bracket
]
_next = [0]


def grid(box, cols, rows):
    """Split a stock box into cols x rows small panels, taking successive POOL
    modules (flipped on later passes), so each UV island reads as a dense bank
    of instruments instead of one oversized module. Mesh UVs are untouched."""
    x0, y0, x1, y1 = box
    xs = [round(x0 + (x1 - x0) * i / cols) for i in range(cols + 1)]
    ys = [round(y0 + (y1 - y0) * j / rows) for j in range(rows + 1)]
    out = []
    for j in range(rows):
        for i in range(cols):
            k = _next[0]; _next[0] += 1
            flip = (None, 'h', None, 'v')[(k // len(POOL)) % 4]
            out.append(((xs[i], ys[j], xs[i + 1], ys[j + 1]), POOL[k % len(POOL)] + (flip,)))
    return out


# box (x0, y0, x1, y1) in the stock 1024 atlas -> (master, crop, flip). The stock
# module boxes are kept (every CCA cockpit's UVs sample them); each is filled with
# a grid of small panels.
LAYOUT = [
    ((0, 0, 205, 1024),    ('hazard', 150, 150, 580, 1390, None)),
    *grid((205, 0, 372, 312), 2, 3),
    *grid((205, 318, 372, 704), 2, 3),
    *grid((205, 708, 372, 1016), 2, 3),
    *grid((372, 0, 570, 155), 2, 2),
    *grid((372, 160, 570, 430), 2, 3),
    *grid((372, 436, 570, 645), 2, 2),
    *grid((372, 645, 570, 1016), 2, 4),
    *grid((575, 0, 770, 341), 2, 3),
    *grid((575, 341, 770, 682), 2, 3),
    *grid((575, 682, 770, 1024), 2, 3),
    *grid((775, 0, 1024, 318), 3, 3),
    *grid((775, 318, 1024, 635), 3, 3),
    *grid((775, 635, 930, 1016), 2, 4),
    *grid((930, 635, 1024, 1016), 1, 4),
]
# Emissive: only lamp glass glows. Marked in master px so the glow follows each
# lamp module wherever the grid places it: circles (cx, cy, r), squares (cx, cy, half).
GLOW = {'lamps': {'circles': [(1759, 439, 121), (2163, 439, 121), (1759, 866, 121), (2163, 866, 121)]},
        'keypad': {'squares': [(1993, 766, 73)]}}


def glow_mask(name, size):
    """Lamp-glass falloff mask in master space (L image)."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    g = np.zeros((h, w), np.float32)
    for cx, cy, r in GLOW.get(name, {}).get('circles', []):
        g = np.maximum(g, np.clip(1 - np.hypot(xx - cx, yy - cy) / r, 0, 1) ** .35)
    for cx, cy, a in GLOW.get(name, {}).get('squares', []):
        g[cy - a:cy + a, cx - a:cx + a] = 1
    return Image.fromarray((g * 255).astype(np.uint8))


def cover(img, w, h):
    """Scale to cover w x h keeping aspect, centre crop."""
    s = max(w / img.width, h / img.height)
    img = img.resize((max(w, round(img.width * s)), max(h, round(img.height * s))), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def compose():
    masters = json.loads((SRC / 'provenance.json').read_text())['masters']
    cache, masks = {}, {}
    atlas = Image.new('RGB', (SIZE, SIZE))
    glow = Image.new('L', (SIZE, SIZE))
    seam = np.zeros((SIZE, SIZE), bool)
    for box, (name, x0, y0, x1, y1, flip) in LAYOUT:
        if name not in cache:
            cache[name] = Image.open(SRC / masters[name]['file']).convert('RGB')
            if name in GLOW: masks[name] = glow_mask(name, cache[name].size)
        b = [round(v * K) for v in box]
        for src, dst in ((cache[name], atlas), (masks.get(name), glow)):
            if src is None: continue
            tile = cover(src.crop((x0, y0, x1, y1)), b[2] - b[0], b[3] - b[1])
            if flip == 'v': tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
            if flip == 'h': tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
            dst.paste(tile, b[:2])
        seam[b[1]:b[3], b[0]:b[0] + SEAM] = seam[b[1]:b[3], b[2] - SEAM:b[2]] = True
        seam[b[1]:b[1] + SEAM, b[0]:b[2]] = seam[b[3] - SEAM:b[3], b[0]:b[2]] = True
    d = np.asarray(atlas, np.float32) / 255
    d[seam] *= .25
    g = np.asarray(glow, np.float32) / 255
    g[seam] = 0
    return d, seam, g


def derive(d, seam, glow):
    lum = d @ np.float32([.299, .587, .114])
    h = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    h[seam] -= .3
    # BZBase cotangent frame: encode (-dh/du, -dh/drow, 1) (v runs down the image).
    strength = 6.0
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5 * strength
    n = np.dstack([-gx, -gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    normal = (n * .5 + .5)
    mx, mn = d.max(2), d.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    spec = np.clip(.12 + .6 * lum ** 1.5 * (1 - .6 * sat), 0, 1)
    spec[seam] = 0
    glow = np.asarray(Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    emis = d * glow[..., None] * .6
    return normal, np.dstack([spec] * 3), emis


def dxt1_dds(img):
    """DXT1 with a full mip chain (same layout as the stock atlas)."""
    def blocks(im):
        buf = io.BytesIO(); im.save(buf, format='DDS', pixel_format='DXT1'); return buf.getvalue()[128:]
    data, levels, cur = b'', 0, img.convert('RGBA')
    while True:
        data += blocks(cur); levels += 1
        if cur.width == 1 and cur.height == 1: break
        cur = cur.resize((max(1, cur.width // 2), max(1, cur.height // 2)), Image.BOX)
    top = max(8, (img.width // 4) * (img.height // 4) * 8)
    head = struct.pack('<4sI', b'DDS ', 124)
    head += struct.pack('<6I', 0xA1007, img.height, img.width, top, 0, levels) + b'\0' * 44
    head += struct.pack('<2I4s5I', 32, 4, b'DXT1', 0, 0, 0, 0, 0)
    head += struct.pack('<5I', 0x401008, 0, 0, 0, 0)
    return head + data


def img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + .5).astype(np.uint8))


def main():
    d, seam, glow = compose()
    normal, spec, emis = derive(d, seam, glow)
    maps = {'d': img(d), 'n': img(normal), 's': img(spec), 'e': img(emis).resize((1024, 1024), Image.LANCZOS)}
    if '--preview' in sys.argv:
        out = Path(sys.argv[sys.argv.index('--preview') + 1])
        for k, v in maps.items(): v.save(out.with_name(out.stem + '_' + k + '.png'))
        return
    for k, v in maps.items():
        (OUT / f'crcca_cockpit_{k}.dds').write_bytes(dxt1_dds(v))
        print('wrote', OUT / f'crcca_cockpit_{k}.dds', v.size)


if __name__ == '__main__':
    main()
