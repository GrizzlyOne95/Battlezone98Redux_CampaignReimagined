"""Procedural trim-sheet texture generator for the BZ capital ships.

Style target: the BZTC CCA rocketship (sbcone) -- warm mottled plating,
thin bevelled panel seams, black tech-greeble recesses, dark bands with
oval running lights, small red indicators and faction emblems.

Outputs per faction (PNG, 2048^2):
  <p>hull_D/_N/_S      tileable plating (wraps in U and V)
  <p>hullw_D/_E        same plating with window light strips (sides)
  <p>trim_D/_N/_S/_E   trim sheet; strip layout in TRIM below
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

N = 2048
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tex")

# Trim sheet strips: name -> (top px, bottom px).  U always tiles.
TRIM = {
    "lights":   (0, 128),     # dark band, oval running lights
    "redlts":   (128, 256),   # dark band, paired red indicators
    "greeble":  (256, 512),   # black tech recess
    "hazard":   (512, 640),   # diagonal stripes
    "vent":     (640, 768),   # louvred grille
    "accent":   (768, 1024),  # faction accent plating band
    "nozzle":   (1024, 1280), # ribbed nozzle interior
    "cells":    (1280, 1536), # 8 x 256 non-tiling decal cells
    "hangar":   (1536, 2048), # hangar / bay interior
}
CELLS = ["star", "roundel", "hatch", "glow", "glass", "number", "chevron", "dish"]

PALETTES = {
    "cca": dict(
        base=(150, 142, 132), mottle=(112, 105, 97), darkpanel=(104, 100, 95),
        accent=(66, 82, 84), trim=(30, 29, 27), light=(255, 226, 70),
        red=(225, 38, 28), emblem=(205, 30, 25), emblem2=(52, 58, 58),
        stripe_a=(200, 36, 28), stripe_b=(205, 200, 190), glow=(255, 150, 40),
        window=(255, 214, 90), number="07"),
    "nsdf": dict(
        base=(98, 102, 110), mottle=(74, 77, 85), darkpanel=(70, 73, 80),
        accent=(32, 34, 39), trim=(22, 23, 26), light=(255, 222, 96),
        red=(225, 50, 40), emblem=(232, 232, 226), emblem2=(40, 70, 150),
        stripe_a=(230, 230, 224), stripe_b=(30, 32, 36), glow=(110, 185, 255),
        window=(255, 220, 110), number="12", straight=True),
}

rng = np.random.default_rng(1998)


# ---------------------------------------------------------------- helpers
def periodic_noise(h, w, scale, seed):
    """Band-limited periodic noise in [-1, 1] (FFT filtered -> wraps)."""
    r = np.random.default_rng(seed)
    white = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f0 = 1.0 / scale
    filt = np.exp(-((f - f0) ** 2) / (2 * (f0 * 0.6) ** 2))
    filt[0, 0] = 0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    out /= np.abs(out).max() + 1e-9
    return out


def mottle_field(h, w, seed):
    m = (0.55 * periodic_noise(h, w, 220, seed)
         + 0.30 * periodic_noise(h, w, 60, seed + 1)
         + 0.15 * periodic_noise(h, w, 14, seed + 2))
    # blotchy concrete-like thresholding like the reference paint
    return np.clip(m * 1.6, -1, 1)


def lerp(a, b, t):
    return a + (b - a) * t


def col(c):
    return np.array(c, dtype=np.float32)


def blank(h, w, c):
    return np.ones((h, w, 3), np.float32) * col(c)


def draw_wrap_rect(arr, x0, y0, x1, y1, value):
    """Fill rect on a U/V-wrapping canvas (arr HxWxC or HxW)."""
    h, w = arr.shape[:2]
    for dx in (0, -w, w):
        for dy in (0, -h, h):
            a0, a1 = max(0, x0 + dx), min(w, x1 + dx)
            b0, b1 = max(0, y0 + dy), min(h, y1 + dy)
            if a0 < a1 and b0 < b1:
                arr[b0:b1, a0:a1] = value


def subdivide(x0, y0, x1, y1, minsz, depth, out, r):
    w, h = x1 - x0, y1 - y0
    if depth <= 0 or (w < minsz * 2 and h < minsz * 2) or (depth < 4 and r.random() < 0.18):
        out.append((x0, y0, x1, y1))
        return
    if (w > h and w >= minsz * 2) or h < minsz * 2:
        s = int(x0 + w * r.uniform(0.3, 0.7))
        subdivide(x0, y0, s, y1, minsz, depth - 1, out, r)
        subdivide(s, y0, x1, y1, minsz, depth - 1, out, r)
    else:
        s = int(y0 + h * r.uniform(0.3, 0.7))
        subdivide(x0, y0, x1, s, minsz, depth - 1, out, r)
        subdivide(x0, s, x1, y1, minsz, depth - 1, out, r)


def finish_maps(rgb, height, spec, emit, prefix, normal_strength=3.0):
    rgb8 = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(rgb8).save(prefix + "_D.png")
    if height is not None:
        hgt = Image.fromarray((np.clip(height, 0, 1) * 255).astype(np.uint8))
        hgt = np.asarray(hgt.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
        gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * normal_strength
        gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * normal_strength
        nz = np.ones_like(gx)
        n = np.stack([-gx, gy, nz], -1)  # OpenGL-style (+Y up)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(prefix + "_N.png")
    if spec is not None:
        Image.fromarray(np.clip(spec, 0, 255).astype(np.uint8)).convert("RGB").save(prefix + "_S.png")
    if emit is not None:
        Image.fromarray(np.clip(emit, 0, 255).astype(np.uint8)).save(prefix + "_E.png")


# ---------------------------------------------------------------- plating
def plating(pal, seed, size=N):
    r = np.random.default_rng(seed)
    base = col(pal["base"])
    mot = mottle_field(size, size, seed)
    t = np.clip(-mot, 0, 1)[..., None]  # dark blotches only
    rgb = base * (1 - t * 0.8) + col(pal["mottle"]) * (t * 0.8)
    rgb *= (1 + 0.09 * periodic_noise(size, size, 3, seed + 9) + 0.05 * periodic_noise(size, size, 9, seed + 10))[..., None]
    height = np.full((size, size), 0.6, np.float32)

    rects = []
    subdivide(0, 0, size, size, 150, 7, rects, r)
    for (x0, y0, x1, y1) in rects:
        roll = r.random()
        if roll < 0.18:  # darker painted panel
            k = r.uniform(0.70, 0.82)
            rgb[y0:y1, x0:x1] *= k
            height[y0:y1, x0:x1] = 0.55
        elif roll < 0.26:  # inset access plate with its own outline
            m = int(min(x1 - x0, y1 - y0) * 0.22)
            if m > 12:
                ix0, iy0, ix1, iy1 = x0 + m, y0 + m, x1 - m, y1 - m
                rgb[iy0:iy1, ix0:ix1] *= 0.9
                height[iy0:iy1, ix0:ix1] = 0.5
                for (a, b, c, d) in ((ix0, iy0, ix1, iy0 + 2), (ix0, iy0, ix0 + 2, iy1),
                                     (ix0, iy1 - 2, ix1, iy1), (ix1 - 2, iy0, ix1, iy1)):
                    rgb[b:d, a:c] = col(pal["trim"]) * 1.3
                    height[b:d, a:c] = 0.35
    # bevelled seams (wrap-aware, grooves at rect tops/lefts cover tile edges)
    seam = np.zeros((size, size), bool)
    for (x0, y0, x1, y1) in rects:
        seam[y0:y0 + 2, x0:x1] = True
        seam[y0:y1, x0:x0 + 2] = True
    lit = np.roll(seam, 2, 0) | np.roll(seam, 2, 1)
    lit &= ~seam
    rgb[lit] = rgb[lit] * 1.18
    rgb[seam] = col(pal["trim"]) * 1.4
    height[seam] = 0.2

    # sparse small details: hatch outlines, rivet rows, stencil ticks
    for _ in range(40):
        x, y = int(r.integers(0, size)), int(r.integers(0, size))
        kind = r.random()
        if kind < 0.4:
            w_, h_ = int(r.integers(30, 90)), int(r.integers(20, 70))
            for (a, b, c, d) in ((x, y, x + w_, y + 2), (x, y, x + 2, y + h_),
                                 (x, y + h_, x + w_, y + h_ + 2), (x + w_, y, x + w_ + 2, y + h_ + 2)):
                draw_wrap_rect(rgb, a, b, c, d, col(pal["trim"]) * 1.6)
                draw_wrap_rect(height, a, b, c, d, 0.4)
        elif kind < 0.7:
            for i in range(int(r.integers(6, 14))):
                draw_wrap_rect(rgb, x + i * 14, y, x + i * 14 + 4, y + 4, col(pal["trim"]) * 2.0)
                draw_wrap_rect(height, x + i * 14, y, x + i * 14 + 4, y + 4, 0.75)
        else:
            for i in range(int(r.integers(3, 7))):
                draw_wrap_rect(rgb, x + i * 16, y, x + i * 16 + 9, y + 26, col(pal["trim"]) * 1.2)
    spec = 70 + 50 * (rgb.mean(-1) / 255.0) + 25 * periodic_noise(size, size, 30, seed + 4)
    spec[seam] = 20
    return rgb, height, spec, rects


def add_windows(rgb, pal, seed):
    r = np.random.default_rng(seed)
    size = rgb.shape[0]
    emit = np.zeros_like(rgb)
    rows = [int(size * f) for f in (0.12, 0.30, 0.47, 0.64, 0.83)]
    for y in rows:
        x = int(r.integers(0, 200))
        while x < size + 400:
            run = int(r.integers(2, 7))
            for i in range(run):
                w_ = int(r.integers(26, 46))
                lit = r.random() < 0.72
                draw_wrap_rect(rgb, x - 3, y - 3, x + w_ + 3, y + 13, col(pal["trim"]))
                c = col(pal["window"]) if lit else col(pal["trim"]) * 1.8
                draw_wrap_rect(rgb, x, y, x + w_, y + 10, c)
                if lit:
                    draw_wrap_rect(emit, x, y, x + w_, y + 10, col(pal["window"]))
                x += w_ + 14
            x += int(r.integers(120, 520))
    return rgb, emit


# ---------------------------------------------------------------- trim sheet
def greeble_strip(h, w, pal, seed):
    r = np.random.default_rng(seed)
    rgb = blank(h, w, (24, 23, 22))
    height = np.full((h, w), 0.15, np.float32)
    for _ in range(int(w * h / 900)):
        x, y = int(r.integers(0, w)), int(r.integers(0, h))
        bw, bh = int(r.integers(8, 70)), int(r.integers(6, 40))
        g = r.uniform(30, 82)
        draw_wrap_rect(rgb, x, y, x + bw, y + bh, (g, g * 0.98, g * 0.95))
        draw_wrap_rect(rgb, x, y, x + bw, y + 2, (g * 1.5,) * 3)
        draw_wrap_rect(rgb, x, y + bh - 2, x + bw, y + bh, (g * 0.45,) * 3)
        draw_wrap_rect(height, x, y, x + bw, y + bh, r.uniform(0.3, 0.8))
    for _ in range(int(w / 60)):  # pipes
        y = int(r.integers(4, h - 14))
        x = int(r.integers(0, w))
        L = int(r.integers(80, 400))
        for k in range(10):
            s = 0.55 + 0.6 * math.sin(math.pi * k / 9)
            draw_wrap_rect(rgb, x, y + k, x + L, y + k + 1, (48 * s,) * 3)
            draw_wrap_rect(height, x, y + k, x + L, y + k + 1, 0.5 + 0.4 * math.sin(math.pi * k / 9))
    # frame lip top/bottom
    rgb[:6] = col(pal["trim"]) * 1.8
    rgb[-6:] = col(pal["trim"]) * 0.8
    height[:6] = 0.9
    height[-6:] = 0.9
    return rgb, height


def trim_sheet(pal, seed, prefix):
    rgb = np.zeros((N, N, 3), np.float32)
    height = np.full((N, N), 0.6, np.float32)
    emit = np.zeros((N, N, 3), np.float32)
    spec = np.full((N, N), 60, np.float32)

    def strip(name):
        a, b = TRIM[name]
        return slice(a, b)

    # base plating everywhere first (used by accent band / cell backgrounds)
    prgb, ph, ps, _ = plating(pal, seed + 50)
    rgb[:] = prgb
    height[:] = ph
    spec[:] = ps

    # running-light band
    s = strip("lights")
    rgb[s] = col(pal["trim"])
    height[s] = 0.4
    a, b = TRIM["lights"]
    rgb[a:a + 8] = col(pal["trim"]) * 2.2
    rgb[b - 8:b] = col(pal["trim"]) * 0.7
    for x in range(40, N, 170):
        cy, cx = (a + b) // 2, x + 30
        yy, xx = np.ogrid[a:b, 0:N]
        e = ((xx - cx) / 30.0) ** 2 + ((yy - cy) / 13.0) ** 2
        ring = (e < 1.5) & (e >= 1.0)
        core = e < 1.0
        rgb[a:b][ring] = col(pal["light"]) * 0.55
        rgb[a:b][core] = col(pal["light"])
        emit[a:b][core] = col(pal["light"])
        emit[a:b][ring] = col(pal["light"]) * 0.4
        height[a:b][core] = 0.8

    # red indicator band
    a, b = TRIM["redlts"]
    rgb[a:b] = col(pal["trim"]) * 1.2
    for x in range(0, N, 256):
        rgb[a + 20:b - 20, x + 18:x + 200] = col(pal["trim"]) * 2.2
        rgb[a + 20:a + 22, x + 18:x + 200] = col(pal["trim"]) * 3.2
        for dx in (96, 126):
            yy, xx = np.ogrid[a:b, 0:N]
            d = (xx - (x + dx)) ** 2 + (yy - (a + b) // 2) ** 2
            m = d < 100
            rgb[a:b][m] = col(pal["red"])
            emit[a:b][m] = col(pal["red"])

    # greeble recess
    a, b = TRIM["greeble"]
    g, gh = greeble_strip(b - a, N, pal, seed + 3)
    rgb[a:b], height[a:b] = g, gh
    spec[a:b] = 35

    # hazard stripes
    a, b = TRIM["hazard"]
    yy, xx = np.mgrid[a:b, 0:N]
    band = ((xx + yy) // 64) % 2 == 0
    rgb[a:b] = np.where(band[..., None], col(pal["stripe_a"]), col(pal["stripe_b"]))
    rgb[a:b] *= (1 + 0.08 * periodic_noise(b - a, N, 20, seed + 7))[..., None]
    rgb[a:a + 4] = col(pal["trim"])
    rgb[b - 4:b] = col(pal["trim"])

    # vent louvres
    a, b = TRIM["vent"]
    rgb[a:b] = col(pal["trim"]) * 1.3
    for y in range(a + 10, b - 10, 14):
        for k in range(10):
            v = 40 + 70 * (k / 9.0)
            rgb[y + k, :] = (v, v, v * 0.97)
            height[y + k, :] = 0.2 + 0.6 * k / 9.0
    for x in range(0, N, 256):
        rgb[a:b, x:x + 6] = col(pal["trim"]) * 2.4
        height[a:b, x:x + 6] = 0.9

    # accent band: plating tinted to the faction accent
    a, b = TRIM["accent"]
    lum = rgb[a:b].mean(-1, keepdims=True) / col(pal["base"]).mean()
    rgb[a:b] = col(pal["accent"]) * lum
    rgb[a:a + 4] = col(pal["trim"])
    rgb[b - 4:b] = col(pal["trim"])

    # nozzle interior: ribbed dark rings (U wraps around the bell)
    a, b = TRIM["nozzle"]
    yy = np.arange(a, b)[:, None]
    rib = 0.5 + 0.5 * np.cos((yy - a) / (b - a) * 2 * math.pi * 9)
    rgb[a:b] = (np.array([38, 37, 36]) * (0.6 + 0.6 * rib))[:, None, :] * np.ones((1, N, 1))
    height[a:b] = (0.3 + 0.5 * rib) * np.ones((1, N))
    heat = np.clip((yy - a) / (b - a), 0, 1) ** 3
    emit[a:b] = (col(pal["glow"]) * heat[..., None] * 0.6) * np.ones((1, N, 1))
    rgb[a:b] += col(pal["glow"]) * heat[..., None] * 0.35
    spec[a:b] = 90

    # hangar interior
    a, b = TRIM["hangar"]
    rgb[a:b] = blank(b - a, N, (20, 20, 22))
    hy = b - a
    for x in range(0, N, 128):
        rgb[a:b, x:x + 10] = (52, 52, 54)
        height[a:b, x:x + 10] = 0.8
    for y in range(a + 40, b - 20, 90):
        rgb[y:y + 3] = (60, 60, 62)
    floor = slice(b - 70, b - 40)
    for x in range(30, N, 96):
        rgb[floor, x:x + 40] = col(pal["light"]) * 0.9
        emit[floor, x:x + 40] = col(pal["light"]) * 0.9
    ceil = slice(a + 16, a + 26)
    rgb[ceil, :] = (220, 228, 235)
    emit[ceil, :] = (150, 160, 170)
    rgb[a:a + 8] = col(pal["trim"]) * 2

    # decal cells
    a, b = TRIM["cells"]
    for i, cname in enumerate(CELLS):
        x0 = i * 256
        cell = Image.fromarray(np.clip(rgb[a:b, x0:x0 + 256], 0, 255).astype(np.uint8))
        ecell = Image.new("RGB", (256, 256), (0, 0, 0))
        d = ImageDraw.Draw(cell)
        de = ImageDraw.Draw(ecell)
        c, cc = 128, 128

        def star(dr, cx, cy, R, fill, rot=-math.pi / 2):
            pts = []
            for k in range(10):
                rr = R if k % 2 == 0 else R * 0.40
                ang = rot + k * math.pi / 5
                pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
            dr.polygon(pts, fill=fill)

        if cname == "star":
            star(d, c, cc + 6, 118, pal["trim"])
            star(d, c, cc + 6, 104, pal["emblem"])
        elif cname == "roundel":
            d.ellipse((6, 6, 250, 250), fill=pal["trim"])
            d.ellipse((16, 16, 240, 240), fill=pal["emblem2"])
            star(d, c, cc + 6, 104, pal["emblem"])
        elif cname == "hatch":
            d.rounded_rectangle((40, 20, 216, 250), 30, fill=tuple(int(v * 0.6) for v in pal["base"]),
                                outline=pal["trim"], width=6)
            d.line((40, 140, 216, 140), fill=pal["trim"], width=4)
            star(d, 128, 84, 40, pal["emblem"])
            d.ellipse((98, 166, 158, 226), outline=pal["trim"], width=4)
        elif cname == "glow":
            for k in range(60, 0, -1):
                t = k / 60.0
                g = tuple(int(lerp(255, v, t)) for v in pal["glow"])
                d.ellipse((128 - 2 * k, 128 - 2 * k, 128 + 2 * k, 128 + 2 * k), fill=g)
                de.ellipse((128 - 2 * k, 128 - 2 * k, 128 + 2 * k, 128 + 2 * k), fill=g)
            d.ellipse((2, 2, 254, 254), outline=pal["trim"], width=10)
        elif cname == "glass":
            d.rectangle((0, 0, 256, 256), fill=pal["trim"])
            for k in range(4):
                x = 10 + k * 62
                d.rectangle((x, 60, x + 50, 196), fill=(60, 90, 110))
                de.rectangle((x + 4, 64, x + 46, 192), fill=tuple(int(v * 0.8) for v in pal["window"]))
                d.rectangle((x + 4, 64, x + 46, 192), fill=pal["window"])
        elif cname == "number":
            # blocky stencil digits drawn from segments (no font dependency)
            segs = {"0": "abcdef", "1": "bc", "2": "abged", "7": "abc", "3": "abgcd", "4": "fgbc",
                    "5": "afgcd", "6": "afgedc", "8": "abcdefg", "9": "abcfgd"}

            def digit(dr, ch, x, y, w_, h_, t, fill):
                s = segs[ch]
                if "a" in s: dr.rectangle((x, y, x + w_, y + t), fill=fill)
                if "g" in s: dr.rectangle((x, y + h_ // 2 - t // 2, x + w_, y + h_ // 2 + t // 2), fill=fill)
                if "d" in s: dr.rectangle((x, y + h_ - t, x + w_, y + h_), fill=fill)
                if "f" in s: dr.rectangle((x, y, x + t, y + h_ // 2), fill=fill)
                if "e" in s: dr.rectangle((x, y + h_ // 2, x + t, y + h_), fill=fill)
                if "b" in s: dr.rectangle((x + w_ - t, y, x + w_, y + h_ // 2), fill=fill)
                if "c" in s: dr.rectangle((x + w_ - t, y + h_ // 2, x + w_, y + h_), fill=fill)

            for k, ch in enumerate(pal["number"]):
                digit(d, ch, 24 + k * 112, 40, 92, 176, 22, pal["emblem"])
        elif cname == "chevron" and pal.get("straight"):
            for k in range(4):
                d.rectangle((0, 22 + k * 56, 256, 50 + k * 56), fill=pal["stripe_a"])
        elif cname == "chevron":
            for k in range(3):
                y = 30 + k * 64
                d.polygon([(10, y + 40), (128, y), (246, y + 40), (246, y + 70), (128, y + 30), (10, y + 70)],
                          fill=pal["stripe_a"])
        elif cname == "dish":
            for k in range(8):
                rr = 124 - k * 15
                g = 80 + k * 18
                d.ellipse((128 - rr, 128 - rr, 128 + rr, 128 + rr), fill=(g, g, g), outline=pal["trim"], width=3)
            d.ellipse((116, 116, 140, 140), fill=pal["red"])
            de.ellipse((116, 116, 140, 140), fill=pal["red"])
        rgb[a:b, x0:x0 + 256] = np.asarray(cell, np.float32)
        emit[a:b, x0:x0 + 256] = np.maximum(emit[a:b, x0:x0 + 256], np.asarray(ecell, np.float32))
    finish_maps(rgb, height, spec, emit, prefix)


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (fac, pal) in enumerate(PALETTES.items()):
        p = os.path.join(OUT, fac)
        rgb, h, s, _ = plating(pal, 100 + i)
        finish_maps(rgb.copy(), h, s, None, p + "hull")
        wrgb, emit = add_windows(rgb.copy(), pal, 200 + i)
        finish_maps(wrgb, None, None, emit, p + "hullw")
        trim_sheet(pal, 300 + i, p + "trim")
        print("wrote", fac)
    with open(os.path.join(OUT, "trim_layout.json"), "w") as f:
        json.dump({"size": N, "strips": TRIM, "cells": CELLS}, f, indent=1)


if __name__ == "__main__":
    main()
