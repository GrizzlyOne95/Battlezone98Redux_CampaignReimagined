"""Shared painter for the faction dropship atlases (texgen_svstock.py = CCA, texgen_cvstock.py = CRA).
Same atlas layout and maps as texgen_avstock.py (hull / hullw / trim, _D/_N/_S/_E), but the palette,
panel scale, detail mix and weathering come from a per-faction palette `pal` and style `st`
(measured from the stock Redux DDS, see README). Everything is generated in code: no pixels, stencils
or emblems are cropped or pasted from any existing texture or concept image. Digits, stars and
bolts are drawn from polygons/segments.
`hullw` = `hull` plus a worn star + serial marking (used on large flat side facets, UV'd at the facet corner).
"""
import copy
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texgen as T
from texgen_avstock import gblur, smear_down, noise, star_pts, to_dds

N = T.N
c = T.col
METAL = np.array((118, 122, 118), np.float32)
SEGS = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
        "7": "abc", "8": "abcdefg", "9": "abcfgd", "-": "g", "A": "abcefg", "I": "bc"}
MARK = (110, 1690, 460, 2010)      # hullw marking zone (px, tile corner = facet corner); kept free of details
STAR_C = (250, 1800, 90)


def digits(d, text, x, y, w, h, t, gap=0.55):
    """Stencil digits from segments (gaps at the joints, like the stock stencils); safe for tiny sizes."""
    def R(a, b, c, e):
        d.rectangle((a, b, max(a, c), max(b, e)), fill=255)
    for k, ch in enumerate(text):
        s = SEGS.get(ch, "")
        x0 = x + k * int(w * (1 + gap))
        g = max(1, t // 4)
        if "a" in s: R(x0 + g, y, x0 + w - g, y + t)
        if "g" in s: R(x0 + g, y + h // 2 - t // 2, x0 + w - g, y + h // 2 + t // 2)
        if "d" in s: R(x0 + g, y + h - t, x0 + w - g, y + h)
        if "f" in s: R(x0, y + g, x0 + t, y + h // 2 - g)
        if "e" in s: R(x0, y + h // 2 + g, x0 + t, y + h - g)
        if "b" in s: R(x0 + w - t, y + g, x0 + w, y + h // 2 - g)
        if "c" in s: R(x0 + w - t, y + h // 2 + g, x0 + w, y + h - g)


def bolt_pts(x, y, w, h):
    """Zigzag lightning bolt polygon in a w x h box."""
    return [(x + w * 0.55, y), (x + w * 0.1, y + h * 0.5), (x + w * 0.45, y + h * 0.5), (x + w * 0.2, y + h),
            (x + w * 0.9, y + h * 0.4), (x + w * 0.55, y + h * 0.4), (x + w * 0.85, y)]


def slashes(d, x, y, n, w, h, gap, slant):
    for i in range(n):
        x0 = x + i * (w + gap)
        d.polygon([(x0 + slant, y), (x0 + slant + w, y), (x0 + w, y + h), (x0, y + h)], fill=255)


# ---------------------------------------------------------------- canvas
class Canvas:
    """rgb/height/spec plus masks the weathering pass reads (palette-aware copy of texgen_avstock.Canvas)."""

    def __init__(self, pal, h, w):
        self.pal = pal
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.height = np.full((h, w), 0.6, np.float32)
        self.spec = np.full((h, w), 50, np.float32)
        self.dirt = np.zeros((h, w), np.float32)
        self.paint = np.zeros((h, w), np.float32)
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
        self.rgb[y0:y1, x0:x1] = c(self.pal["slot"])
        for y in range(y0 + 3, y1 - 3, pitch):
            for k in range(pitch - 2):
                v = 0.55 + 0.9 * k / (pitch - 3)
                self.rgb[y + k, x0 + 3:x1 - 3] = c(self.pal["slot"]) * 2.2 * v
                self.height[y + k, x0 + 3:x1 - 3] = 0.25 + 0.4 * k / (pitch - 3)
        self.bevel(x0, y0, x1, y1, raised=False)
        self.dirt[y1 - 3:y1, x0:x1] = 1.0
        self.spec[y0:y1, x0:x1] = 30

    def slab(self, x0, y0, x1, y1, ribs=True):
        """Black recessed slab with fine ribs (the stock vent/intake slabs)."""
        self.rgb[y0:y1, x0:x1] = c(self.pal["slot"]) * 0.9
        self.height[y0:y1, x0:x1] = 0.3
        if ribs:
            for y in range(y0 + 6, y1 - 4, 9):
                self.rgb[y:y + 2, x0 + 5:x1 - 5] = c(self.pal["slot"]) * 2.0
                self.height[y:y + 2, x0 + 5:x1 - 5] = 0.5
        self.bevel(x0, y0, x1, y1, raised=False, w=3)
        self.dirt[y1 - 3:y1, x0:x1] = 1.0
        self.spec[y0:y1, x0:x1] = 25

    def pipe(self, x0, y0, length, width, vertical=False):
        for k in range(width):
            s = 0.45 + 0.85 * math.sin(math.pi * (k + 0.5) / width)
            col = np.array((70, 72, 66), np.float32) * s
            hv = 0.55 + 0.35 * math.sin(math.pi * (k + 0.5) / width)
            if vertical:
                self.rgb[y0:y0 + length, x0 + k] = col
                self.height[y0:y0 + length, x0 + k] = hv
            else:
                self.rgb[y0 + k, x0:x0 + length] = col
                self.height[y0 + k, x0:x0 + length] = hv
        for b in range(10, length - 10, 70):
            if vertical:
                self.recess(x0 - 3, y0 + b, x0 + width + 3, y0 + b + 8, 0.7)
            else:
                self.recess(x0 + b, y0 - 3, x0 + b + 8, y0 + width + 3, 0.7)
        self.dirt[y0 + width - 2:y0 + width, x0:x0 + length] = 0.8

    def decal(self, mask, color, alpha=0.92):
        a = mask[..., None] * alpha
        lum = self.rgb.mean(-1, keepdims=True) / max(1.0, c(self.pal["paints"][0][1]).mean())
        tinted = c(color) * np.clip(0.8 + 0.2 * lum, 0.65, 1.15)
        self.rgb = self.rgb * (1 - a) + tinted * a
        self.paint = np.maximum(self.paint, mask)

    def shape_mask(self, draw_fn):
        h, w = self.height.shape
        m = Image.new("L", (w, h), 0)
        draw_fn(ImageDraw.Draw(m))
        return np.asarray(m, np.float32) / 255.0


# ---------------------------------------------------------------- weathering
def weather(cv, seed, wp, amount=1.0, emit=None):
    """wp: drift, grime, rust, chip, scratch, dirt (rgb), rustc (rgb). Grime/rust/chips as texgen_avstock,
    plus fine scratches that read as bare metal."""
    h, w = cv.height.shape
    rgb = cv.rgb
    drift = 1 + wp["drift"] * noise(h, w, 400, seed) + 0.05 * noise(h, w, 90, seed + 1)
    grain = 1 + wp["grain"] * noise(h, w, 2.5, seed + 2) * amount
    rgb *= (drift * grain)[..., None]
    if cv.seam.any():
        ao = np.clip(gblur(cv.seam, 5) * 3.0, 0, 1)
        rgb *= (1 - 0.22 * ao * amount)[..., None]
    runs = smear_down(cv.dirt, 60) * 9 + smear_down(cv.dirt, 18) * 3
    vstreak = np.kron(noise(h // 32, w, 4, seed + 3), np.ones((32, 1), np.float32))[:h]
    runs = gblur(runs, 1.5) * np.clip(0.7 + vstreak * 0.9, 0.1, 1.6)
    blot = np.clip(-T.mottle_field(h, w, seed + 4), 0, 1) * wp["blot"]
    g = np.clip((runs * wp["grime"] + blot) * amount, 0, 0.75)[..., None]
    dirt = np.array(wp["dirt"], np.float32)
    rgb[:] = rgb * (1 - g) + dirt * g
    rn = noise(h, w, 18, seed + 5) + 0.5 * noise(h, w, 4, seed + 6)
    rust = np.clip((rn - 0.55) * 2.5, 0, 1) * np.clip(runs * 2 + 0.15, 0, 1) * wp["rust"] * amount
    rustc = np.array(wp["rustc"], np.float32)
    rgb[:] = rgb * (1 - rust[..., None]) + rustc * rust[..., None]
    edge = np.clip(gblur(cv.seam, 2.5) * 6, 0, 1) if cv.seam.any() else 0
    cn = noise(h, w, 3, seed + 7) + 0.6 * noise(h, w, 12, seed + 8)
    chip = (cn > 1.05 - wp["chip"] * edge - 0.2 * cv.paint * amount) & (cn > 0.35)
    chip = chip.astype(np.float32) * amount
    lip = np.clip(gblur(chip, 1.2) * 2.2 - chip, 0, 1)
    rgb[:] = rgb * (1 - 0.35 * lip[..., None])
    bare = np.array(wp.get("bare", METAL), np.float32) * (0.8 + 0.3 * np.clip(noise(h, w, 2, seed + 9), -1, 1))[..., None]
    rgb[:] = rgb * (1 - chip[..., None] * 0.85) + bare * chip[..., None] * 0.85
    cv.spec += chip * 90
    scuff = np.clip((noise(h, w, 5, seed + 10) - 0.3) * 3, 0, 1) * cv.paint * 0.45 * amount
    cv.spec -= scuff * 10
    if wp["scratch"] > 0:      # fine bright scratches, mostly one direction (like the stock hull wear)
        r = np.random.default_rng(seed + 11)
        m = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(m)
        for _ in range(int(wp["scratch"] * amount)):
            x, y = r.uniform(0, w), r.uniform(0, h)
            L = r.uniform(8, 60)
            a = r.normal(0.5, 0.45)
            d.line((x, y, x + L * math.cos(a), y + L * math.sin(a)), fill=int(r.uniform(90, 255)), width=1)
        sm = np.asarray(m, np.float32) / 255.0
        sm = np.maximum(sm, np.roll(sm, 1, 0) * 0.35)
        sa = wp.get("scratch_a", 0.4)
        rgb[:] = rgb * (1 - sm[..., None] * sa) + np.array(wp.get("scratch_col", METAL * 1.25), np.float32) * sm[..., None] * sa
        cv.spec += sm * 40
    if emit is not None:
        lit = emit.max(-1) > 20
        cv.rgb[lit] = cv.rgb_lit[lit]
    cv.spec[:] = np.clip(cv.spec + 25 * (rgb.mean(-1) / 255.0), 10, 220)


# ---------------------------------------------------------------- hull plating
def pick_paint(r, paints):
    w = np.array([p[0] for p in paints], np.float64)
    return c(paints[int(r.choice(len(paints), p=w / w.sum()))][1])


def scatter(cv, pal, st, r, occ, bx0, by0, bx1, by1, n):
    """Place up to n small details inside the pixel box (kinds/weights from st['kinds']; occ is an 8 px overlap grid)."""
    kinds = list(st["kinds"])
    kw = np.array([st["kinds"][k] for k in kinds], np.float64)
    kw /= kw.sum()
    foot = dict(grille=(72, 40), recess=(110, 80), plate=(160, 110), rivets=(120, 14), pipe=(240, 14), stencil=(80, 14),
                slash=(100, 70), star=(60, 60), hazard=(170, 24), hatch=(90, 90), slab=(300, 60), stripe=(300, 18),
                bolt=(70, 90))
    tries = placed = 0
    while placed < n and tries < n * 25:
        tries += 1
        k = kinds[int(r.choice(len(kinds), p=kw))]
        fw, fh = foot[k]
        x, y = int(r.integers(bx0, max(bx0 + 1, bx1 - fw))), int(r.integers(by0, max(by0 + 1, by1 - fh)))
        ox, oy = x // 8, y // 8
        if occ[oy:oy + fh // 8 + 1, ox:ox + fw // 8 + 1].any():
            continue
        occ[oy:oy + fh // 8 + 1, ox:ox + fw // 8 + 1] = True
        placed += 1
        if k == "grille":
            cv.grille(x, y, x + int(r.integers(30, 72)), y + int(r.integers(18, 40)), pitch=int(r.choice((5, 7, 9))))
        elif k == "slab":
            cv.slab(x, y, x + int(r.integers(90, 300)), y + int(r.integers(22, 60)), ribs=r.random() < 0.7)
        elif k == "recess":
            w_, h_ = int(r.integers(30, 110)), int(r.integers(24, 80))
            cv.recess(x, y, x + w_, y + h_, r.uniform(0.45, 0.72))
            if w_ > 50 and h_ > 40 and r.random() < 0.5:
                cv.plate(x + 6, y + 6, x + w_ - 6, y + h_ - 6, 0.95)
        elif k == "plate":
            w_, h_ = int(r.integers(40, 160)), int(r.integers(30, 110))
            cv.plate(x, y, x + w_, y + h_, r.uniform(0.95, 1.12))
            if r.random() < 0.6:
                for (px, py) in ((x + 5, y + 5), (x + w_ - 9, y + 5), (x + 5, y + h_ - 9), (x + w_ - 9, y + h_ - 9)):
                    cv.rivets(px, py, 1, 1)
        elif k == "rivets":
            cv.rivets(x, y, int(r.integers(5, 13)), int(r.integers(9, 15)), vertical=r.random() < 0.4)
        elif k == "pipe":
            if r.random() < 0.5:
                cv.pipe(x, y, int(r.integers(80, 240)), int(r.integers(7, 13)))
        elif k == "stencil":
            n = int(r.integers(3, 8))
            m = cv.shape_mask(lambda d: [d.rectangle((x + i * 9, y, x + i * 9 + 5, y + 9), fill=255)
                                         for i in range(n) if r.random() < 0.8])
            cv.decal(m, pal["stencil"], 0.7)
        elif k == "slash":
            hh = int(r.integers(26, 70))
            ww = max(5, hh // 5)
            m = cv.shape_mask(lambda d: slashes(d, x, y, 3, ww, hh, ww, hh // 2))
            cv.decal(m, pal["mark"])
        elif k == "star":
            R = int(r.integers(10, 28))
            m = cv.shape_mask(lambda d: d.polygon(star_pts(x + R, y + R, R), fill=255))
            cv.decal(m, pal["star"])
        elif k == "bolt":
            hh = int(r.integers(40, 90))
            m = cv.shape_mask(lambda d: d.polygon(bolt_pts(x, y, hh * 0.7, hh), fill=255))
            cv.decal(m, pal["mark"])
        elif k == "stripe":
            w_, h_ = int(r.integers(120, 300)), int(r.integers(6, 16))
            cv.rgb[y:y + h_, x:x + w_] = c(pal["stripe"]) * r.uniform(0.9, 1.05)
            cv.paint[y:y + h_, x:x + w_] = 1
            cv.bevel(x, y, x + w_, y + h_, raised=True, w=2)
        elif k == "hazard":
            w_, h_ = int(r.integers(50, 170)), int(r.integers(12, 24))
            yy, xx = np.mgrid[y:y + h_, x:x + w_]
            band = (((xx + yy) // 12) % 2 == 0)
            cv.rgb[y:y + h_, x:x + w_] = np.where(band[..., None], c(pal["hazard_a"]), c(pal["hazard_b"]))
            cv.paint[y:y + h_, x:x + w_] = 1
            cv.bevel(x, y, x + w_, y + h_, raised=True, w=2)
        elif k == "hatch":
            w_, h_ = int(r.integers(40, 90)), int(r.integers(40, 90))
            cv.recess(x, y, x + w_, y + h_, 0.82)
            cv.plate(x + 4, y + 4, x + w_ - 4, y + h_ - 4, 1.0)
            cv.recess(x + w_ // 2 - 10, y + h_ // 2 - 3, x + w_ // 2 + 10, y + h_ // 2 + 3, 0.5)


def plating(pal, st, seed, size=N):
    """Pre-weather hull canvas: coloured bevelled panels on a dark chassis, then dense small details."""
    r = np.random.default_rng(seed)
    cv = Canvas(pal, size, size)
    cv.rgb[:] = c(pal["dark"])
    rects = []
    T.subdivide(0, 0, size, size, st["minsz"], st["depth"], rects, r)
    for (x0, y0, x1, y1) in rects:
        base = pick_paint(r, pal["paints"])
        tone = r.uniform(0.9, 1.08)
        grad = np.linspace(1.07, 0.88, y1 - y0, dtype=np.float32)[:, None, None]
        cv.rgb[y0:y1, x0:x1] = base * tone * grad
        cv.bevel(x0, y0, x1, y1, raised=True, k=0.8)
        cv.seam[y0:y0 + st["line"], x0:x1] = 1
        cv.seam[y0:y1, x0:x0 + st["line"]] = 1
        cv.dirt[max(y1 - 2, 0):y1, x0:x1] = np.maximum(cv.dirt[max(y1 - 2, 0):y1, x0:x1], 0.25)
    seam = cv.seam > 0
    cv.rgb[seam] = c(pal["line"])
    cv.height[seam] = 0.2
    cv.spec[seam] = 15

    M = 24
    occ = np.zeros((size // 8 + 40, size // 8 + 40), bool)
    zx0, zy0, zx1, zy1 = (v // 8 for v in MARK)
    occ[zy0:zy1 + 1, zx0:zx1 + 1] = True
    scatter(cv, pal, st, r, occ, M, M, size - M, size - M, st["details"])
    return cv


CELL = 512
DARK = (1856, 1856, 2040, 2040)       # near-black patch (x0, y0, x1, y1) that underside/frame islands are UV'd into


def plating_cells(pal, st, seed, size=N):
    """CCA hull: large coherent paint fields. The tile is 4 x 4 cells of 512 px (12 m); each cell is one paint value
    (within +-3 %) with a panel line on its left and bottom edge, so a facet UV'd from a cell origin gets its lines on
    its own mesh edges. A few details per cell; the marking zone and the dark patch are kept free."""
    r = np.random.default_rng(seed)
    cv = Canvas(pal, size, size)
    base = c(pal["paints"][0][1])
    occ = np.zeros((size // 8 + 40, size // 8 + 40), bool)
    zx0, zy0, zx1, zy1 = (v // 8 for v in MARK)
    occ[zy0:zy1 + 1, zx0:zx1 + 1] = True
    dx0, dy0, dx1, dy1 = (v // 8 for v in DARK)
    occ[dy0 - 2:dy1 + 3, dx0 - 2:dx1 + 3] = True
    ln = st["line"]
    for j in range(size // CELL):
        for i in range(size // CELL):
            x0, y0 = i * CELL, size - (j + 1) * CELL
            tone = 1 + r.uniform(-st["tone"], st["tone"])
            grad = np.linspace(1 + st["tone"] * 0.5, 1 - st["tone"] * 0.5, CELL, dtype=np.float32)[:, None, None]
            cv.rgb[y0:y0 + CELL, x0:x0 + CELL] = base * tone * grad
            cv.bevel(x0, y0, x0 + CELL, y0 + CELL, raised=True, w=3, k=0.4)
            cv.seam[y0:y0 + CELL, x0:x0 + ln] = 1                       # left edge line
            cv.seam[y0 + CELL - ln:y0 + CELL, x0:x0 + CELL] = 1         # bottom edge line
            cv.dirt[y0 + CELL - 3:y0 + CELL, x0:x0 + CELL] = 0.3
            scatter(cv, pal, st, r, occ, x0 + 40, y0 + 30, x0 + CELL - 30, y0 + CELL - 30, int(r.integers(3, 6)))
    seam = cv.seam > 0
    cv.rgb[seam] = c(pal["line"])
    cv.height[seam] = 0.2
    cv.spec[seam] = 15
    return cv


def paint_dark(cv, pal, seed):
    """Overwrite the dark patch with flat near-black chassis paint (fine grain only: islands are UV'd into it at a
    reduced scale, so it must not carry features)."""
    x0, y0, x1, y1 = DARK
    h, w = y1 - y0, x1 - x0
    g = 1 + 0.07 * noise(h, w, 3, seed)
    cv.rgb[y0:y1, x0:x1] = c(pal["dark_paint"]) * g[..., None]
    cv.height[y0:y1, x0:x1] = 0.5
    cv.spec[y0:y1, x0:x1] = 30
    cv.seam[y0:y1, x0:x1] = 0
    return cv


def add_markings(cv, pal):
    """hullw: unit star + serial at the facet corner (zone MARK)."""
    cx, cy, R = STAR_C
    cv.rgb[MARK[1]:MARK[3], MARK[0]:MARK[2]] *= 1.0
    m = cv.shape_mask(lambda d: d.polygon(star_pts(cx, cy, R), fill=255))
    ring = cv.shape_mask(lambda d: d.ellipse((cx - R - 16, cy - R - 16, cx + R + 16, cy + R + 16), outline=255, width=7))
    if pal.get("ring"):
        cv.decal(ring, pal["ring"], 0.85)
    if pal.get("star_edge"):
        edge = cv.shape_mask(lambda d: d.polygon(star_pts(cx, cy, R + 9), fill=255))
        cv.decal(edge, pal["star_edge"], 0.9)
    cv.decal(m, pal["star"], 0.95)
    sm = cv.shape_mask(lambda d: digits(d, pal["serial"], 135, 1935, 30, 58, 10, 0.5))
    cv.decal(sm, pal["serial_col"], 0.85)
    cv.dirt[MARK[3] - 6:MARK[3], MARK[0]:MARK[2]] = 0.5


# ---------------------------------------------------------------- trim sheet
def lamp(cv, emit, cx, cy, rx, ry, color, housing=(64, 34)):
    hw, hh = housing
    cv.plate(cx - hw // 2, cy - hh // 2, cx + hw // 2, cy + hh // 2, 0.85)
    cv.recess(cx - rx - 4, cy - ry - 4, cx + rx + 4, cy + ry + 4, 0.35)
    yy, xx = np.ogrid[cy - ry - 2:cy + ry + 2, cx - rx - 2:cx + rx + 2]
    e = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    core, hot = e < 1.0, e < 0.35
    sl = (slice(cy - ry - 2, cy + ry + 2), slice(cx - rx - 2, cx + rx + 2))
    col = c(color)
    cv.rgb[sl][core] = col * 0.85
    cv.rgb[sl][hot] = np.minimum(col * 1.15 + 40, 255)
    emit[sl][core] = col * 0.8
    emit[sl][hot] = col
    cv.height[sl][core] = 0.7


def trim_sheet(pal, st, wp, seed, prefix):
    cv = (plating_cells(pal, st, seed + 50) if st.get("cells")
          else plating(pal, dict(st, details=st["details"] + 200), seed + 50))
    base = cv.rgb.copy()
    emit = np.zeros((N, N, 3), np.float32)
    S = T.TRIM
    line = c(pal["line"])
    slot = c(pal["slot"])

    def band(name, fill, height=0.4, frame=True):
        a, b = S[name]
        cv.rgb[a:b] = fill
        cv.height[a:b] = height
        cv.seam[a:b] = cv.paint[a:b] = cv.dirt[a:b] = 0
        cv.spec[a:b] = 40
        if frame:
            cv.rgb[a:a + 6] = line * 2.4
            cv.rgb[b - 6:b] = line * 0.7
            cv.height[a:a + 6] = cv.height[b - 6:b] = 0.85
        return a, b

    a, b = band("lights", slot * 1.4)
    for x in range(0, N, 128):
        cv.recess(x + 4, a + 14, x + 124, b - 14, 0.9)
        cv.rivets(x + 10, a + 20, 1, 1)
        cv.rivets(x + 112, b - 26, 1, 1)
    for x in range(64, N, 256):
        lamp(cv, emit, x, (a + b) // 2, 16, 9, pal["light"])

    a, b = band("redlts", slot * 1.5)
    for x in range(0, N, 256):
        cv.plate(x + 20, a + 26, x + 236, b - 26, 1.4)
        cv.grille(x + 34, a + 40, x + 84, b - 40, pitch=6)
        for dx in (150, 180):
            lamp(cv, emit, x + dx, (a + b) // 2, 6, 6, pal["red"], housing=(22, 22))
        cv.dirt[b - 28:b - 26, x + 20:x + 236] = 1

    a, b = S["greeble"]
    g, gh = T.greeble_strip(b - a, N, {"trim": pal["slot"]}, seed + 3)
    cv.rgb[a:b] = g * np.array(pal["greeble_tint"], np.float32)
    cv.height[a:b] = gh
    cv.seam[a:b] = cv.paint[a:b] = 0
    cv.dirt[a:b] = 0.15
    cv.spec[a:b] = 35

    a, b = band("hazard", 0, frame=False)
    yy, xx = np.mgrid[a:b, 0:N]
    stp = ((xx + yy) // 64) % 2 == 0
    cv.rgb[a:b] = np.where(stp[..., None], c(pal["hazard_a"]), c(pal["hazard_b"]))
    cv.paint[a + 8:b - 8] = 1
    cv.rgb[a:a + 8] = cv.rgb[b - 8:b] = line * 1.5
    cv.bevel(0, a, N, b, raised=True, w=4)
    cv.dirt[b - 10:b - 8] = 0.6
    for x in range(0, N, 256):
        cv.rivets(x + 8, a + 2, 16, 15)

    a, b = band("vent", slot * 1.3)
    for x in range(0, N, 256):
        cv.grille(x + 8, a + 10, x + 248, b - 10, pitch=11)
        cv.dirt[b - 12:b - 10, x + 8:x + 248] = 1

    a, b = S["accent"]
    cv.rgb[a:b] = base[a:b] * (c(pal["accent"]) / c(pal["paints"][0][1]))
    cv.rgb[a:a + 4] = cv.rgb[b - 4:b] = line
    cv.rgb[(a + b) // 2 - 10:(a + b) // 2 + 10] = c(pal["stripe"])
    cv.paint[(a + b) // 2 - 10:(a + b) // 2 + 10] = 1

    a, b = band("nozzle", 0, frame=False)
    yy = np.arange(a, b)[:, None]
    rib = 0.5 + 0.5 * np.cos((yy - a) / (b - a) * 2 * math.pi * 9)
    cv.rgb[a:b] = (np.array([46, 44, 40], np.float32) * (0.55 + 0.6 * rib))[:, None, :] * np.ones((1, N, 1))
    cv.rgb[a:b] *= (1 + 0.15 * noise(b - a, N, 8, seed + 11))[..., None]
    cv.height[a:b] = (0.3 + 0.5 * rib) * np.ones((1, N))
    heat = np.clip((yy - a) / (b - a), 0, 1) ** 3
    emit[a:b] = (c(pal["glow"]) * heat[..., None] * 0.55) * np.ones((1, N, 1))
    cv.rgb[a:b] += c(pal["glow"]) * heat[..., None] * 0.3
    cv.spec[a:b] = 90

    # hold interior: dark floor plating with long tread ribs and grate grooves. Interior faces are UV'd with u metric
    # and v stretched over the whole strip, so everything here runs along v (constant in v) and nothing is a stencil.
    a, b = S["hangar"]
    hh = b - a
    row = noise(8, N, 24, seed + 21)[0]
    tone = (1 + 0.10 * row)[None, :, None]
    vgrad = np.linspace(1.08, 0.92, hh, dtype=np.float32)[:, None, None]
    cv.rgb[a:b] = c(pal["floor"]) * tone * vgrad
    cv.height[a:b] = 0.55
    cv.spec[a:b] = 45
    cv.seam[a:b] = cv.paint[a:b] = 0
    for x in range(0, N, 128):                       # plate joints
        cv.rgb[a:b, x:x + 3] = line * 0.9
        cv.rgb[a:b, x + 3:x + 5] *= 1.5
        cv.height[a:b, x:x + 3] = 0.2
    for x in range(20, N, 128):                      # anti-slip tread ribs
        for k in range(6):
            cv.rgb[a:b, x + k * 16:x + k * 16 + 6] *= 1.4
            cv.height[a:b, x + k * 16:x + k * 16 + 6] = 0.8
    for x in range(120, N, 256):                     # grate slot lines
        cv.rgb[a:b, x:x + 2] = slot * 0.8
        cv.rgb[a:b, x + 10:x + 12] = slot * 0.8
        cv.height[a:b, x:x + 12] = 0.3
    cv.dirt[a:b] = 0.15

    a, b = S["cells"]
    for i, name in enumerate(T.CELLS):
        x0 = i * 256
        sl = (slice(a, b), slice(x0, x0 + 256))
        cv.seam[sl] = cv.dirt[sl] = cv.paint[sl] = 0

        def mask(fn):
            m = Image.new("L", (256, 256), 0)
            fn(ImageDraw.Draw(m))
            full = np.zeros((N, N), np.float32)
            full[sl] = np.asarray(m, np.float32) / 255.0
            return full

        if name == "star":
            if pal.get("star_edge"):
                cv.decal(mask(lambda d: d.polygon(star_pts(128, 134, 118), fill=255)), pal["star_edge"])
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 134, 108), fill=255)), pal["star"])
        elif name == "roundel":
            cv.decal(mask(lambda d: d.ellipse((8, 8, 248, 248), fill=255)), pal["roundel"], 0.85)
            cv.decal(mask(lambda d: d.ellipse((8, 8, 248, 248), outline=255, width=8)), pal["ring"] or pal["star"], 0.8)
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 134, 96), fill=255)), pal["star"])
        elif name == "hatch":
            cv.recess(x0 + 34, a + 16, x0 + 222, a + 250, 0.7)
            cv.plate(x0 + 42, a + 24, x0 + 214, a + 242, 0.95)
            cv.recess(x0 + 50, a + 134, x0 + 206, a + 140, 0.5)
            cv.recess(x0 + 104, a + 176, x0 + 152, a + 196, 0.45)
            for (px, py) in ((48, 30), (204, 30), (48, 230), (204, 230)):
                cv.rivets(x0 + px, a + py, 1, 1)
            cv.decal(mask(lambda d: d.polygon(star_pts(128, 84, 34), fill=255)), pal["star"])
        elif name == "glow":
            cv.rgb[sl] *= 0.8
            cv.plate(x0 + 10, a + 10, x0 + 246, a + 246, 0.75)
            yy2, xx2 = np.ogrid[0:256, 0:256]
            d2 = np.sqrt((xx2 - 128.0) ** 2 + (yy2 - 128.0) ** 2)
            lens = d2 < 96
            fall = np.clip(1 - d2 / 96, 0, 1)[..., None]
            gl = c(pal["lamp"])
            col = gl * (0.55 + 0.45 * fall) + (255 - gl) * fall ** 2.5
            cv.rgb[sl][lens] = col[lens]
            emit[sl][lens] = (col * 0.9)[lens]
            cv.rgb[sl][(d2 >= 96) & (d2 < 108)] = line * 1.2
        elif name == "glass":
            cv.rgb[sl] = line * 1.3
            yy1 = np.arange(256, dtype=np.float32)[:, None]
            for k in range(4):
                x = 10 + k * 62
                cv.rgb[a + 60:a + 196, x0 + x:x0 + x + 50] = (30, 40, 44)
                v = (yy1[64:192] - 64) / 128.0
                pane = (c(pal["window"]) * (0.45 + 0.55 * (1 - v)))[:, None, :] * np.ones((1, 42, 1))
                xs = np.arange(42, dtype=np.float32)[None, :]
                pane = pane + np.clip(1 - np.abs((xs - 6) - v * 40) / 5, 0, 1)[..., None] * 70
                cv.rgb[a + 64:a + 192, x0 + x + 4:x0 + x + 46] = pane
                emit[a + 64:a + 192, x0 + x + 4:x0 + x + 46] = pane * pal["glass_emit"]
                cv.bevel(x0 + x, a + 60, x0 + x + 50, a + 196, raised=False, w=4)
        elif name == "number":
            img = Image.new("L", (256, 256), 0)
            digits(ImageDraw.Draw(img), pal["serial"], 16, 70, 30, 116, 12, 0.3)
            full = np.zeros((N, N), np.float32)
            full[sl] = np.asarray(img, np.float32) / 255.0
            cv.decal(full, pal["serial_col"], 0.85)
        elif name == "chevron":
            if pal["chevron"] == "bolt":
                cv.decal(mask(lambda d: (d.polygon(bolt_pts(20, 20, 100, 216), fill=255),
                                         d.polygon(bolt_pts(130, 20, 100, 216), fill=255))), pal["mark"])
            else:
                cv.decal(mask(lambda d: slashes(d, 20, 40, 3, 34, 176, 30, 70)), pal["mark"])
        elif name == "dish":
            # nozzle throat seen from outside: dark rim, ring line, ribbed bore, hot centre (radial, with depth)
            yy2, xx2 = np.ogrid[0:256, 0:256]
            d2 = np.sqrt((xx2 - 128.0) ** 2 + (yy2 - 128.0) ** 2)
            t = np.clip(d2 / 120.0, 0, 1.5)
            inside = d2 < 120
            heat = np.clip(1 - t, 0, 1) ** 1.8
            gl = c(pal["glow"])
            rib = 0.85 + 0.15 * np.cos(t * 2 * math.pi * 5)
            col = (np.array((24, 22, 20), np.float32) * ((0.5 + 0.5 * t) * rib)[..., None]
                   + gl * (heat * 0.9)[..., None])
            cv.rgb[sl][inside] = col[inside]
            ring = (d2 > 92) & (d2 < 100)
            cv.rgb[sl][ring] = np.array((84, 80, 74), np.float32)
            shadow = (d2 >= 82) & (d2 <= 92)
            cv.rgb[sl][shadow] *= 0.55
            cv.rgb[sl][(d2 >= 120) & (d2 < 127)] = line
            cv.rgb[sl][d2 >= 127] = np.array((20, 18, 16), np.float32)     # cell corners (rectangular floors map the whole cell)
            cv.height[sl][d2 >= 127] = 0.3
            emit[sl][inside] = (gl * (heat ** 1.4 * 0.85)[..., None])[inside]
            cv.height[sl][inside] = (0.8 - 0.55 * (1 - t))[inside]
            cv.dirt[sl] = 0
        cv.seam[a:a + 2, x0:x0 + 256] = 1
        cv.seam[a:b, x0:x0 + 2] = 1

    cv.rgb_lit = cv.rgb.copy()
    weather(cv, seed + 200, wp, 0.85, emit=emit)
    T.finish_maps(cv.rgb, cv.height, cv.spec, emit, prefix)


def build(fac, pal, st, wp, seed):
    os.makedirs(T.OUT, exist_ok=True)
    p = os.path.join(T.OUT, fac)
    cv = plating_cells(pal, st, seed) if st.get("cells") else plating(pal, st, seed)
    cvw = copy.deepcopy(cv)
    add_markings(cvw, pal)
    weather(cv, seed + 100, wp)
    weather(cvw, seed + 100, wp)
    if st.get("cells"):
        paint_dark(cv, pal, seed + 7)
        paint_dark(cvw, pal, seed + 7)
    T.finish_maps(cv.rgb.copy(), cv.height, cv.spec, None, p + "hull")
    T.finish_maps(cvw.rgb, None, None, np.zeros((N, N, 3), np.float32), p + "hullw")
    trim_sheet(pal, st, wp, seed + 240, p + "trim")
    import glob
    to_dds(sorted(glob.glob(p + "*.png")))
