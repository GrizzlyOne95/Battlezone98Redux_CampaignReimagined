"""'nsdfv' atlas: hull + trim painted in the style of the stock NSDF vehicles
(avrecy/avmuf/avslf _D). Those read as painted, not vector art: small bevelled panels with
lit top/left edges, dense recessed grilles, rivets and conduits, worn white slashes and
stars, chipped hazard paint, grime streaking down from every detail, rust, and small
recessed lamps rather than big glowing dots. Colours sampled from the stock DDS (median
teal ~ 50,66,60). The trim layout (texgen.TRIM / CELLS, glass window positions) is kept,
so meshes built against the texgen atlas map unchanged.
Writes tex/nsdfv*.png and out/nsdfv*.dds only; the nsdf/cca sets are untouched.
Run: python texgen_avstock.py"""
import glob
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths as P
import texgen as T

PAL = dict(
    base=(60, 80, 74), mottle=(42, 56, 52), darkpanel=(46, 61, 57),
    accent=(40, 54, 51), trim=(17, 21, 20), light=(255, 214, 120),
    red=(225, 45, 35), emblem=(214, 216, 206), emblem2=(34, 48, 46),
    stripe_a=(186, 146, 40), stripe_b=(22, 22, 20), glow=(120, 190, 255),
    window=(140, 205, 220), number="12", straight=True)
N = T.N
RUST = np.array((92, 62, 42), np.float32)
DIRT = np.array((26, 30, 26), np.float32)
METAL = np.array((112, 120, 114), np.float32)
c = T.col


# ---------------------------------------------------------------- periodic filters
def gblur(a, sigma):
    """Gaussian blur that wraps (keeps tiles seamless)."""
    h, w = a.shape
    fy, fx = np.fft.fftfreq(h)[:, None], np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)


def smear_down(a, length):
    """Smear a mask downwards (+v) with an exponential tail: grime runs."""
    h, w = a.shape
    k = np.zeros((h, w), np.float32)
    ys = np.arange(int(length * 3))
    for dx, wt in ((0, 1.0), (1, 0.5), (-1, 0.5)):
        k[ys, dx] = np.exp(-ys / length) * wt
    k /= k.sum()
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.fft.fft2(k))).astype(np.float32)


def noise(h, w, scale, seed):
    return T.periodic_noise(h, w, scale, seed).astype(np.float32)


# ---------------------------------------------------------------- detail painters
class Canvas:
    """rgb/height/spec plus masks the weathering pass reads."""

    def __init__(self, h, w):
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.height = np.full((h, w), 0.6, np.float32)
        self.spec = np.full((h, w), 50, np.float32)
        self.dirt = np.zeros((h, w), np.float32)      # sources of grime runs
        self.paint = np.zeros((h, w), np.float32)     # decal paint (wears off)
        self.seam = np.zeros((h, w), np.float32)

    def bevel(self, x0, y0, x1, y1, raised=True, w=3, k=1.0):
        hi, lo = (1 + 0.32 * k, 1 - 0.42 * k) if raised else (1 - 0.45 * k, 1 + 0.22 * k)
        r = self.rgb
        r[y0:y0 + w, x0:x1] *= hi
        r[y0:y1, x0:x0 + w] *= 1 + (hi - 1) * 0.75
        r[y1 - w:y1, x0:x1] *= lo
        r[y0:y1, x1 - w:x1] *= 1 + (lo - 1) * 0.8

    def recess(self, x0, y0, x1, y1, depth=0.6):
        self.rgb[y0:y1, x0:x1] *= depth
        self.bevel(x0, y0, x1, y1, raised=False)
        self.height[y0:y1, x0:x1] = 0.42
        self.dirt[y1 - 3:y1, x0:x1] = 1.0

    def plate(self, x0, y0, x1, y1, tone=1.08):
        self.rgb[y0:y1, x0:x1] *= tone
        self.bevel(x0, y0, x1, y1, raised=True)
        self.height[y0:y1, x0:x1] = 0.75
        self.dirt[y1 - 2:y1, x0:x1] = 0.6

    def rivets(self, x, y, n, step, vertical=False):
        for i in range(n):
            px, py = (x, y + i * step) if vertical else (x + i * step, y)
            self.rgb[py:py + 4, px:px + 4] *= 0.75
            self.rgb[py:py + 2, px:px + 2] *= 1.9
            self.height[py:py + 4, px:px + 4] = 0.8

    def grille(self, x0, y0, x1, y1, pitch=7):
        self.rgb[y0:y1, x0:x1] = c(PAL["trim"]) * 1.2
        for y in range(y0 + 3, y1 - 3, pitch):
            for k in range(pitch - 2):
                v = 0.55 + 0.9 * k / (pitch - 3)
                self.rgb[y + k, x0 + 3:x1 - 3] = c(PAL["base"]) * 0.75 * v
                self.height[y + k, x0 + 3:x1 - 3] = 0.25 + 0.4 * k / (pitch - 3)
        self.bevel(x0, y0, x1, y1, raised=False)
        self.dirt[y1 - 3:y1, x0:x1] = 1.0
        self.spec[y0:y1, x0:x1] = 30

    def pipe(self, x0, y0, length, width, vertical=False):
        for k in range(width):
            s = 0.45 + 0.85 * math.sin(math.pi * (k + 0.5) / width)
            col = np.array((66, 74, 70), np.float32) * s
            hv = 0.55 + 0.35 * math.sin(math.pi * (k + 0.5) / width)
            if vertical:
                self.rgb[y0:y0 + length, x0 + k] = col
                self.height[y0:y0 + length, x0 + k] = hv
            else:
                self.rgb[y0 + k, x0:x0 + length] = col
                self.height[y0 + k, x0:x0 + length] = hv
        for b in range(10, length - 10, 70):   # brackets
            if vertical:
                self.recess(x0 - 3, y0 + b, x0 + width + 3, y0 + b + 8, 0.7)
            else:
                self.recess(x0 + b, y0 - 3, x0 + b + 8, y0 + width + 3, 0.7)
        if vertical:
            self.dirt[y0 + length - 4:y0 + length, x0:x0 + width] = 1
        else:
            self.dirt[y0 + width - 2:y0 + width, x0:x0 + length] = 0.8

    def decal(self, mask, color, alpha=0.92):
        """Paint a 0..1 mask (full-canvas float array) in color; recorded for wear."""
        a = mask[..., None] * alpha
        lum = self.rgb.mean(-1, keepdims=True) / c(PAL["base"]).mean()
        tinted = c(color) * np.clip(0.75 + 0.25 * lum, 0.6, 1.15)
        self.rgb = self.rgb * (1 - a) + tinted * a
        self.paint = np.maximum(self.paint, mask)

    def shape_mask(self, draw_fn):
        h, w = self.height.shape
        m = Image.new("L", (w, h), 0)
        draw_fn(ImageDraw.Draw(m))
        return np.asarray(m, np.float32) / 255.0


def star_pts(cx, cy, R, rot=-math.pi / 2):
    return [(cx + (R if k % 2 == 0 else R * 0.4) * math.cos(rot + k * math.pi / 5),
             cy + (R if k % 2 == 0 else R * 0.4) * math.sin(rot + k * math.pi / 5)) for k in range(10)]


def slashes(d, x, y, n, w, h, gap, slant):
    for i in range(n):
        x0 = x + i * (w + gap)
        d.polygon([(x0 + slant, y), (x0 + slant + w, y), (x0 + w, y + h), (x0, y + h)], fill=255)


# ---------------------------------------------------------------- weathering
def weather(cv, seed, amount=1.0, chips=True, emit=None):
    h, w = cv.height.shape
    rgb = cv.rgb
    # broad tonal drift + fine paint grain
    drift = 1 + 0.10 * noise(h, w, 400, seed) + 0.05 * noise(h, w, 90, seed + 1)
    grain = 1 + 0.05 * noise(h, w, 2.5, seed + 2) * amount
    rgb *= (drift * grain)[..., None]
    # edge occlusion along seams
    if cv.seam.any():
        ao = np.clip(gblur(cv.seam, 5) * 3.0, 0, 1)
        rgb *= (1 - 0.22 * ao * amount)[..., None]
    # grime runs from every detail, broken up by noise
    runs = smear_down(cv.dirt, 60) * 9 + smear_down(cv.dirt, 18) * 3
    vstreak = np.kron(noise(h // 32, w, 4, seed + 3), np.ones((32, 1), np.float32))[:h]
    runs = gblur(runs, 1.5) * np.clip(0.7 + vstreak * 0.9, 0.1, 1.6)
    blot = np.clip(-T.mottle_field(h, w, seed + 4), 0, 1) * 0.35
    g = np.clip((runs + blot) * amount, 0, 0.7)[..., None]
    rgb[:] = rgb * (1 - g) + DIRT * g
    # rust: where grime pools and a rust noise agrees
    rn = noise(h, w, 18, seed + 5) + 0.5 * noise(h, w, 4, seed + 6)
    rust = np.clip((rn - 0.55) * 2.5, 0, 1) * np.clip(runs * 2 + 0.15, 0, 1) * 0.75 * amount
    rgb[:] = rgb * (1 - rust[..., None]) + RUST * rust[..., None]
    if chips:
        # chipped paint near edges and on decals: bare metal with a dark lip
        edge = np.clip(gblur(cv.seam, 2.5) * 6, 0, 1) if cv.seam.any() else 0
        cn = noise(h, w, 3, seed + 7) + 0.6 * noise(h, w, 12, seed + 8)
        chip = (cn > 1.05 - 0.55 * edge - 0.2 * cv.paint * amount) & (cn > 0.35)
        chip = chip.astype(np.float32) * amount
        lip = np.clip(gblur(chip, 1.2) * 2.2 - chip, 0, 1)
        rgb[:] = rgb * (1 - 0.35 * lip[..., None])
        bare = METAL * (0.8 + 0.3 * np.clip(noise(h, w, 2, seed + 9), -1, 1))[..., None]
        rgb[:] = rgb * (1 - chip[..., None] * 0.85) + bare * chip[..., None] * 0.85
        cv.spec += chip * 90
        # decals also scuff: lift paint where noise is high
        scuff = np.clip((noise(h, w, 5, seed + 10) - 0.3) * 3, 0, 1) * cv.paint * 0.45 * amount
        cv.spec -= scuff * 10
    if emit is not None:   # never grime the lamps themselves
        lit = emit.max(-1) > 20
        cv.rgb[lit] = cv.rgb_lit[lit]
    cv.spec[:] = np.clip(cv.spec + 25 * (rgb.mean(-1) / 255.0), 10, 220)


# ---------------------------------------------------------------- hull plating
def stock_plating(seed, size=N, details=620):
    r = np.random.default_rng(seed)
    cv = Canvas(size, size)
    cv.rgb[:] = c(PAL["base"])
    rects = []
    T.subdivide(0, 0, size, size, 72, 9, rects, r)
    hue = np.array((1.0, 1.0, 1.0), np.float32)
    for (x0, y0, x1, y1) in rects:
        tone = r.uniform(0.92, 1.05)
        tint = hue + np.array((0, r.uniform(-0.03, 0.03), r.uniform(-0.04, 0.04)), np.float32)
        grad = np.linspace(1.07, 0.9, y1 - y0, dtype=np.float32)[:, None, None]
        cv.rgb[y0:y1, x0:x1] *= tone * tint * grad
        if r.random() < 0.06:        # darker painted panel, as on avrecy
            cv.rgb[y0:y1, x0:x1] *= 0.8
        cv.bevel(x0, y0, x1, y1, raised=True, k=0.8)
        cv.seam[y0:y0 + 2, x0:x1] = 1
        cv.seam[y0:y1, x0:x0 + 2] = 1
        cv.dirt[max(y1 - 2, 0):y1, x0:x1] = np.maximum(cv.dirt[max(y1 - 2, 0):y1, x0:x1], 0.25)
    seam = cv.seam > 0
    cv.rgb[seam] = c(PAL["trim"]) * 1.3
    cv.height[seam] = 0.2
    cv.spec[seam] = 15

    # dense, small details; kept off the tile border so the tile still wraps
    M = 24
    occ = np.zeros((size // 8 + 40, size // 8 + 40), bool)
    tries = 0
    placed = 0
    while placed < details and tries < details * 25:
        tries += 1
        x, y = int(r.integers(M, size - 260)), int(r.integers(M, size - 200))
        k = r.random()
        # rough footprint for the overlap test (largest size of each kind)
        fw, fh = (72, 40) if k < 0.66 else (190, 14) if k < 0.74 else (110, 50)
        ox, oy = x // 8, y // 8
        if occ[oy:oy + fh // 8, ox:ox + fw // 8].any():
            continue
        occ[oy:oy + fh // 8, ox:ox + fw // 8] = True
        placed += 1
        if k < 0.20:
            w_, h_ = int(r.integers(30, 120)), int(r.integers(18, 64))
            cv.grille(x, y, x + w_, y + h_, pitch=int(r.choice((5, 7, 9))))
        elif k < 0.38:
            w_, h_ = int(r.integers(16, 110)), int(r.integers(12, 80))
            cv.recess(x, y, x + w_, y + h_, r.uniform(0.5, 0.75))
            if w_ > 40 and h_ > 30 and r.random() < 0.5:
                cv.plate(x + 6, y + 6, x + w_ - 6, y + h_ - 6, 0.95)
        elif k < 0.54:
            w_, h_ = int(r.integers(30, 160)), int(r.integers(24, 110))
            cv.plate(x, y, x + w_, y + h_, r.uniform(0.95, 1.12))
            if r.random() < 0.6:
                for (px, py) in ((x + 5, y + 5), (x + w_ - 9, y + 5), (x + 5, y + h_ - 9), (x + w_ - 9, y + h_ - 9)):
                    cv.rivets(px, py, 1, 1)
        elif k < 0.66:
            n = int(r.integers(5, 16))
            cv.rivets(x, y, n, int(r.integers(9, 15)), vertical=r.random() < 0.4)
        elif k < 0.74:
            if r.random() < 0.55:
                continue           # pipes read busy at hull scale: keep them rarer
            if r.random() < 0.5:
                cv.pipe(x, y, int(r.integers(80, 240)), int(r.integers(7, 13)))
            else:
                cv.pipe(x, y, int(r.integers(60, 180)), int(r.integers(7, 13)), vertical=True)
        elif k < 0.84:   # stencil marks: rows of little blocks
            n = int(r.integers(3, 9))
            m = cv.shape_mask(lambda d: [d.rectangle((x + i * 9, y, x + i * 9 + 5, y + 9), fill=255)
                                         for i in range(n) if r.random() < 0.8])
            cv.decal(m, PAL["emblem"], 0.7)
        elif k < 0.87:   # stock-style triple slash
            hh = int(r.integers(26, 70))
            ww = max(5, hh // 5)
            m = cv.shape_mask(lambda d: slashes(d, x, y, 3, ww, hh, ww, hh // 2))
            cv.decal(m, PAL["emblem"])
        elif k < 0.88:   # small star
            R = int(r.integers(10, 30))
            m = cv.shape_mask(lambda d: d.polygon(star_pts(x + R, y + R, R), fill=255))
            cv.decal(m, PAL["emblem"])
        elif k < 0.90:   # small hazard patch
            w_, h_ = int(r.integers(50, 170)), int(r.integers(12, 24))
            yy, xx = np.mgrid[y:y + h_, x:x + w_]
            band = (((xx + yy) // 12) % 2 == 0)
            cv.rgb[y:y + h_, x:x + w_] = np.where(band[..., None], c(PAL["stripe_a"]), c(PAL["stripe_b"]))
            cv.paint[y:y + h_, x:x + w_] = 1
            cv.bevel(x, y, x + w_, y + h_, raised=True, w=2)
        else:            # access hatch: recess + handle
            w_, h_ = int(r.integers(40, 90)), int(r.integers(40, 90))
            cv.recess(x, y, x + w_, y + h_, 0.82)
            cv.plate(x + 4, y + 4, x + w_ - 4, y + h_ - 4, 1.0)
            cv.recess(x + w_ // 2 - 10, y + h_ // 2 - 3, x + w_ // 2 + 10, y + h_ // 2 + 3, 0.5)
    weather(cv, seed + 100)
    return cv


# ---------------------------------------------------------------- trim sheet
def lamp(cv, emit, cx, cy, rx, ry, color, housing=(64, 34)):
    """Small recessed lamp in a bevelled housing (stock look), lens emits."""
    hw, hh = housing
    cv.plate(cx - hw // 2, cy - hh // 2, cx + hw // 2, cy + hh // 2, 0.85)
    cv.recess(cx - rx - 4, cy - ry - 4, cx + rx + 4, cy + ry + 4, 0.35)
    yy, xx = np.ogrid[cy - ry - 2:cy + ry + 2, cx - rx - 2:cx + rx + 2]
    e = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    core = e < 1.0
    hot = e < 0.35
    sl = (slice(cy - ry - 2, cy + ry + 2), slice(cx - rx - 2, cx + rx + 2))
    col = c(color)
    cv.rgb[sl][core] = col * 0.85
    cv.rgb[sl][hot] = np.minimum(col * 1.15 + 40, 255)
    emit[sl][core] = col * 0.8
    emit[sl][hot] = col
    cv.height[sl][core] = 0.7


def stock_trim(seed, prefix):
    cv = stock_plating(seed + 50, details=900)
    base = cv.rgb.copy()
    emit = np.zeros((N, N, 3), np.float32)
    S = T.TRIM

    def band(name, fill, height=0.4, frame=True):
        a, b = S[name]
        cv.rgb[a:b] = fill
        cv.height[a:b] = height
        cv.seam[a:b] = 0
        cv.paint[a:b] = 0
        cv.dirt[a:b] = 0
        cv.spec[a:b] = 40
        if frame:
            cv.rgb[a:a + 6] = c(PAL["trim"]) * 2.4
            cv.rgb[b - 6:b] = c(PAL["trim"]) * 0.7
            cv.height[a:a + 6] = cv.height[b - 6:b] = 0.85
        return a, b

    # running lights: dark plated channel, small amber lamps in housings
    a, b = band("lights", c(PAL["trim"]) * 1.6)
    for x in range(0, N, 128):
        cv.recess(x + 4, a + 14, x + 124, b - 14, 0.9)
        cv.rivets(x + 10, a + 20, 1, 1)
        cv.rivets(x + 112, b - 26, 1, 1)
    for x in range(64, N, 256):
        lamp(cv, emit, x, (a + b) // 2, 16, 9, PAL["light"])

    # red indicators: pairs of pin lamps in small boxes, sparse
    a, b = band("redlts", c(PAL["trim"]) * 1.8)
    for x in range(0, N, 256):
        cv.plate(x + 20, a + 26, x + 236, b - 26, 1.4)
        cv.grille(x + 34, a + 40, x + 84, b - 40, pitch=6)
        for dx in (150, 180):
            lamp(cv, emit, x + dx, (a + b) // 2, 6, 6, PAL["red"], housing=(22, 22))
        cv.dirt[b - 28:b - 26, x + 20:x + 236] = 1

    # greeble recess: stock-texgen greebles, tinted toward the hull teal and bevelled
    a, b = S["greeble"]
    g, gh = T.greeble_strip(b - a, N, PAL, seed + 3)
    cv.rgb[a:b] = g * np.array((0.9, 1.08, 1.02), np.float32)
    cv.height[a:b] = gh
    cv.seam[a:b] = cv.paint[a:b] = 0
    cv.dirt[a:b] = 0.15
    cv.spec[a:b] = 35

    # hazard: chipped, grimy stripes in a bevelled frame
    a, b = band("hazard", 0, frame=False)
    yy, xx = np.mgrid[a:b, 0:N]
    st = ((xx + yy) // 64) % 2 == 0
    cv.rgb[a:b] = np.where(st[..., None], c(PAL["stripe_a"]), c(PAL["stripe_b"]))
    cv.paint[a + 8:b - 8] = 1
    cv.rgb[a:a + 8] = cv.rgb[b - 8:b] = c(PAL["trim"]) * 1.5
    cv.bevel(0, a, N, b, raised=True, w=4)
    cv.dirt[b - 10:b - 8] = 0.6
    for x in range(0, N, 256):
        cv.rivets(x + 8, a + 2, 16, 15)

    # vent louvres, teal-dark, bevelled frames every 256
    a, b = band("vent", c(PAL["trim"]) * 1.4)
    for x in range(0, N, 256):
        cv.grille(x + 8, a + 10, x + 248, b - 10, pitch=11)
        cv.dirt[b - 12:b - 10, x + 8:x + 248] = 1

    # accent band: darker painted plating
    a, b = S["accent"]
    cv.rgb[a:b] = base[a:b] * (c(PAL["accent"]) / c(PAL["base"]))
    cv.rgb[a:a + 4] = cv.rgb[b - 4:b] = c(PAL["trim"])

    # nozzle: sooty ribbed metal, blue-hot toward the throat
    a, b = band("nozzle", 0, frame=False)
    yy = np.arange(a, b)[:, None]
    rib = 0.5 + 0.5 * np.cos((yy - a) / (b - a) * 2 * math.pi * 9)
    cv.rgb[a:b] = (np.array([44, 42, 40], np.float32) * (0.55 + 0.6 * rib))[:, None, :] * np.ones((1, N, 1))
    cv.rgb[a:b] *= (1 + 0.15 * noise(b - a, N, 8, seed + 11))[..., None]
    cv.height[a:b] = (0.3 + 0.5 * rib) * np.ones((1, N))
    heat = np.clip((yy - a) / (b - a), 0, 1) ** 3
    emit[a:b] = (c(PAL["glow"]) * heat[..., None] * 0.55) * np.ones((1, N, 1))
    cv.rgb[a:b] += c(PAL["glow"]) * heat[..., None] * 0.3
    cv.spec[a:b] = 90

    # hangar interior: dark worn plating, floor guide lamps, ceiling light strip
    a, b = S["hangar"]
    cv.rgb[a:b] = base[a:b] * 0.42
    for x in range(0, N, 128):
        cv.rgb[a:b, x:x + 8] = c(PAL["trim"]) * 2.4
        cv.bevel(x, a, x + 8, b, raised=True, w=2)
        cv.height[a:b, x:x + 8] = 0.8
    for x in range(48, N, 96):
        lamp(cv, emit, x, b - 55, 14, 7, PAL["light"], housing=(44, 24))
    cv.rgb[a + 16:a + 26] = (205, 214, 218)
    emit[a + 16:a + 26] = (140, 150, 156)
    cv.rgb[a:a + 8] = c(PAL["trim"]) * 2

    # decal cells (same slots as texgen.CELLS)
    a, b = S["cells"]
    for i, name in enumerate(T.CELLS):
        x0 = i * 256
        sl = (slice(a, b), slice(x0, x0 + 256))
        cv.seam[sl] = 0
        cv.dirt[sl] = 0
        cv.paint[sl] = 0

        def mask(fn):
            m = Image.new("L", (256, 256), 0)
            fn(ImageDraw.Draw(m))
            full = np.zeros((N, N), np.float32)
            full[sl] = np.asarray(m, np.float32) / 255.0
            return full

        if name == "star":
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 134, 110), fill=255)), PAL["emblem"])
        elif name == "roundel":
            cv.decal(mask(lambda d: d.ellipse((8, 8, 248, 248), fill=255)), PAL["emblem2"], 0.85)
            cv.decal(mask(lambda d: (d.ellipse((8, 8, 248, 248), outline=255, width=8))), PAL["emblem"], 0.8)
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 134, 96), fill=255)), PAL["emblem"])
        elif name == "hatch":
            cv.recess(x0 + 34, a + 16, x0 + 222, a + 250, 0.7)
            cv.plate(x0 + 42, a + 24, x0 + 214, a + 242, 0.95)
            cv.recess(x0 + 50, a + 134, x0 + 206, a + 140, 0.5)
            cv.recess(x0 + 104, a + 176, x0 + 152, a + 196, 0.45)
            for (px, py) in ((48, 30), (204, 30), (48, 230), (204, 230)):
                cv.rivets(x0 + px, a + py, 1, 1)
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 84, 34), fill=255)), PAL["emblem"])
        elif name == "glow":
            cv.rgb[sl] *= 0.8
            cv.plate(x0 + 10, a + 10, x0 + 246, a + 246, 0.75)
            yy, xx = np.ogrid[0:256, 0:256]
            d2 = np.sqrt((xx - 128.0) ** 2 + (yy - 128.0) ** 2)
            lens = d2 < 96
            fall = np.clip(1 - d2 / 96, 0, 1)[..., None]
            gl = c(PAL["glow"])
            col = gl * (0.55 + 0.45 * fall) + (255 - gl) * fall ** 2.5
            cv.rgb[sl][lens] = col[lens]
            emit[sl][lens] = (col * 0.9)[lens]
            ring = (d2 >= 96) & (d2 < 108)
            cv.rgb[sl][ring] = c(PAL["trim"]) * 1.2
        elif name == "glass":
            # keep texgen's window boxes: frame x..x+50, pane x+4..x+46, y 60..196
            cv.rgb[sl] = c(PAL["trim"]) * 1.3
            yy = np.arange(256, dtype=np.float32)[:, None]
            for k in range(4):
                x = 10 + k * 62
                cv.rgb[a + 60:a + 196, x0 + x:x0 + x + 50] = (34, 46, 48)
                v = (yy[64:192] - 64) / 128.0
                pane = (c(PAL["window"]) * (0.45 + 0.55 * (1 - v)))[:, None, :] * np.ones((1, 42, 1))
                xs = np.arange(42, dtype=np.float32)[None, :]
                glint = np.clip(1 - np.abs((xs - 6) - v * 40) / 5, 0, 1)[..., None]
                pane = pane + glint * 70
                cv.rgb[a + 64:a + 192, x0 + x + 4:x0 + x + 46] = pane
                emit[a + 64:a + 192, x0 + x + 4:x0 + x + 46] = pane * 0.75
                cv.bevel(x0 + x, a + 60, x0 + x + 50, a + 196, raised=False, w=4)
        elif name == "number":
            img = Image.new("L", (256, 256), 0)
            d = ImageDraw.Draw(img)
            segs = {"0": "abcdef", "1": "bc", "2": "abged", "7": "abc", "3": "abgcd", "4": "fgbc",
                    "5": "afgcd", "6": "afgedc", "8": "abcdefg", "9": "abcfgd"}
            for k, ch in enumerate(PAL["number"]):
                x, y, w_, h_, t = 40 + k * 96, 56, 72, 144, 16
                s = segs[ch]
                # stencil: segments drawn with gaps at the joints
                if "a" in s: d.rectangle((x + 4, y, x + w_ - 4, y + t), fill=255)
                if "g" in s: d.rectangle((x + 4, y + h_ // 2 - t // 2, x + w_ - 4, y + h_ // 2 + t // 2), fill=255)
                if "d" in s: d.rectangle((x + 4, y + h_ - t, x + w_ - 4, y + h_), fill=255)
                if "f" in s: d.rectangle((x, y + 4, x + t, y + h_ // 2 - 4), fill=255)
                if "e" in s: d.rectangle((x, y + h_ // 2 + 4, x + t, y + h_ - 4), fill=255)
                if "b" in s: d.rectangle((x + w_ - t, y + 4, x + w_, y + h_ // 2 - 4), fill=255)
                if "c" in s: d.rectangle((x + w_ - t, y + h_ // 2 + 4, x + w_, y + h_ - 4), fill=255)
            full = np.zeros((N, N), np.float32)
            full[sl] = np.asarray(img, np.float32) / 255.0
            cv.decal(full, PAL["emblem"], 0.85)
        elif name == "chevron":
            cv.decal(mask(lambda d: slashes(d, 20, 40, 3, 34, 176, 30, 70)), PAL["emblem"])
        elif name == "dish":
            yy, xx = np.ogrid[0:256, 0:256]
            d2 = np.sqrt((xx - 128.0) ** 2 + (yy - 128.0) ** 2)
            dish = d2 < 120
            shade = 0.55 + 0.55 * np.clip(((128 - xx) + (128 - yy)) / 240.0 * (d2 / 120), -1, 1)
            ringk = 0.85 + 0.15 * np.cos(d2 / 7.0)
            col = np.array((96, 104, 100), np.float32) * (shade * ringk)[..., None]
            cv.rgb[sl][dish] = col[dish]
            cv.rgb[sl][(d2 >= 120) & (d2 < 126)] = c(PAL["trim"])
            hub = d2 < 14
            cv.rgb[sl][hub] = c(PAL["red"])
            emit[sl][hub] = c(PAL["red"])
        cv.seam[a:a + 2, x0:x0 + 256] = 1
        cv.seam[a:b, x0:x0 + 2] = 1

    cv.rgb_lit = cv.rgb.copy()
    weather(cv, seed + 200, 0.85, emit=emit)
    T.finish_maps(cv.rgb, cv.height, cv.spec, emit, prefix)


def to_dds(paths):
    if not os.path.isdir(os.path.join(P.TOOLBOX, "bztoolbox")):
        sys.exit(f"DDS step needs the Battlezone98_Modding_Toolbox checkout; set BZ_TOOLBOX (looked in {P.TOOLBOX}). PNGs are in {P.TEX}.")
    sys.path.insert(0, P.TOOLBOX)
    from bztoolbox.modules.textures import bcpack
    out_dir = P.OUT
    os.makedirs(out_dir, exist_ok=True)
    for p in paths:
        a = np.asarray(Image.open(p).convert("RGBA"))
        hh, ww = a.shape[:2]
        chain, _ = bcpack.build_chain([a], ww, hh)
        o = os.path.join(out_dir, os.path.basename(p)[:-4] + ".dds")
        bcpack.write_dds(o, ww, hh, [bcpack.encode_level(lv, "DXT1") for lv in chain], "DXT1")
        print(os.path.basename(o), ww, len(chain))


def main():
    p = os.path.join(T.OUT, "nsdfv")
    cv = stock_plating(140)
    T.finish_maps(cv.rgb.copy(), cv.height, cv.spec, None, p + "hull")
    wrgb, wemit = T.add_windows(cv.rgb.copy(), PAL, 240)
    T.finish_maps(wrgb, None, None, wemit * 0.8, p + "hullw")
    stock_trim(340, p + "trim")
    to_dds(sorted(glob.glob(p + "*.png")))


if __name__ == "__main__":
    main()
