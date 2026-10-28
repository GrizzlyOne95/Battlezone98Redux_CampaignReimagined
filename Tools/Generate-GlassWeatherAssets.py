#!/usr/bin/env python3
"""Generate the cockpit-glass weather layers (frost and ice grains on Europa, dust grit on Mars, acid rain on Venus;
the snow flake layer stays available).

    python Tools/Generate-GlassWeatherAssets.py            # write every asset
    python Tools/Generate-GlassWeatherAssets.py --check    # exit 1 if a checked-in asset differs
    python Tools/Generate-GlassWeatherAssets.py --flake PATH   # another snowflake source

CRWetGlass.lua draws these two families beside the rain layers (see CRWetGlass.Weather):

  Assets/Textures/crwx_winsnow.png   1024 x 1024 tileable sheet of sparse, soft-white snow
        crystals and specks. The large crystals are the ISDF Chronicles snowflake sprite
        (snowflak.dds, the texture its giplume.odf uses; ISDFC has no snow-on-glass texture of
        its own), turned into alpha from its luminance and scattered at random sizes and
        angles. RGB is one constant pale blue-white; only alpha varies.
  Assets/Textures/crwx_wingrit.png   1024 x 1024 tileable sheet of fine tan-brown grit: many
        1-3 px specks, a few small clumps and a very faint dust film.
  Assets/Textures/crwx_acidbeads.png, crwx_acidrivulet.png, crwx_acidstreak.png   the rain
        textures (crwx_wetbeads/wetrivulet/wetstreak.png) with the same alpha and a faint
        yellow-green tint instead of their blue-grey, for Venus acid rain. Derived from the
        checked-in rain textures, so they need no outside source.
  Assets/Textures/crwx_winfrost.png  1024 x 512, NOT tileable: frost creeping in from the edges and corners
        of the view, feathery fern-like crystal growth dense at the borders and fully clear over the
        centre 55% (the layer maps once across the screen, u and v 0..1). RGB is one constant pale
        blue-white; only alpha varies.
  Assets/Textures/crwx_winice.png    1024 x 1024 tileable sheet of sparse fine frozen grains, small rimed
        pits and short ice scratch marks, pale blue-white and crisp.
  Assets/Textures/crwx_winetch.png   1024 x 1024 tileable etched-glass haze: a very faint pale
        yellow-green film with fine pits clustered in patches. Builds over long acid exposure.
  Materials/crwx_glassweather.material   CRWX_WinSnow_A1..A16, CRWX_WinGrit_A1..A16, CRWX_WinFrost_A1..A16, CRWX_WinIce_A1..A16, the three
        CRWX_Acid* rain families and CRWX_WinEtch_A1..A16, the overlay (F2/F3) materials, the
        same shape as the wrap families in crwx_wetglass.material.
        The cockpit-glass (F1) passes need no material of their own: CRWetGlass points a pass of
        CRWX_CockpitGlass_W<a>C<b> at the texture.

Deterministic (fixed seed). The flake source is read only when a texture is written; --check
compares the grit and the material, and the snow texture when the source is found.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "Assets", "Textures")
MAT = os.path.join(ROOT, "Materials", "crwx_glassweather.material")
DEFAULT_FLAKE = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\addon\ISDF Chronicles\snowflak.dds"
SIZE = 1024
STEPS = 16
FAMILIES = (("CRWX_WinSnow", "crwx_winsnow.png"), ("CRWX_WinGrit", "crwx_wingrit.png"),
            ("CRWX_AcidBeads", "crwx_acidbeads.png"), ("CRWX_AcidRivulet", "crwx_acidrivulet.png"),
            ("CRWX_AcidStreak", "crwx_acidstreak.png"), ("CRWX_WinEtch", "crwx_winetch.png"),
            ("CRWX_WinFrost", "crwx_winfrost.png"), ("CRWX_WinIce", "crwx_winice.png"))
# Acid rain textures: (rain texture, acid texture). Same alpha, new colour.
ACID_SOURCES = (("crwx_wetbeads.png", "crwx_acidbeads.png"), ("crwx_wetrivulet.png", "crwx_acidrivulet.png"),
                ("crwx_wetstreak.png", "crwx_acidstreak.png"))
# Faint sulphur yellow-green: the rain texture's luminance, lifted a little, multiplied by this.
ACID_TINT = np.array([0.90, 1.00, 0.46], np.float32)
ACID_LIFT = 1.45


def stamp(alpha, sprite, cx, cy, gain=1.0):
    """Max-composite a float sprite into a tileable alpha plane, wrapping at the edges."""
    h, w = sprite.shape
    ys = (np.arange(h) + int(cy) - h // 2) % SIZE
    xs = (np.arange(w) + int(cx) - w // 2) % SIZE
    sub = alpha[np.ix_(ys, xs)]
    alpha[np.ix_(ys, xs)] = np.maximum(sub, sprite * gain)


def disc(radius, softness):
    r = int(radius * 2 + 3)
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    d = np.sqrt(x * x + y * y)
    return np.clip((radius - d) / max(softness, 1e-3) + 0.5, 0, 1) ** 1.2


def build_snow(flake_path):
    rng = np.random.default_rng(1202)
    src = Image.open(flake_path).convert("RGB")
    lum = np.asarray(src, dtype=np.float32).max(axis=2) / 255.0
    lum = np.clip((lum - 0.06) / 0.8, 0, 1)
    base = Image.fromarray((lum * 255).astype(np.uint8), "L")
    alpha = np.zeros((SIZE, SIZE), np.float32)

    # Big crystals: few, varied size and angle, each a little soft (a flake sitting in a film of melt).
    for k in range(30):
        size = int(rng.choice([22, 28, 34, 42, 54, 70], p=[0.22, 0.22, 0.2, 0.18, 0.12, 0.06]))
        sp = base.resize((size, size), Image.LANCZOS).rotate(float(rng.uniform(0, 360)), Image.BICUBIC, expand=True)
        if rng.random() < 0.55:
            sp = sp.filter(ImageFilter.GaussianBlur(float(rng.uniform(0.4, 1.1))))
        arr = np.asarray(sp, dtype=np.float32) / 255.0
        stamp(alpha, arr, rng.integers(0, SIZE), rng.integers(0, SIZE), float(rng.uniform(0.75, 1.0)))
    # Specks and tiny frozen beads.
    for k in range(260):
        rad = float(rng.choice([1.2, 1.8, 2.6, 3.6], p=[0.45, 0.30, 0.18, 0.07]))
        stamp(alpha, disc(rad, 1.6), rng.integers(0, SIZE), rng.integers(0, SIZE), float(rng.uniform(0.35, 0.8)))
    out = np.zeros((SIZE, SIZE, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 236, 244, 255
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return out


def periodic_blur(field, sigma):
    """Gaussian blur that wraps, so the film tiles."""
    f = np.fft.fftfreq(SIZE)
    k = np.exp(-2 * (np.pi * sigma) ** 2 * (f[:, None] ** 2 + f[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(field) * k))


def build_grit():
    rng = np.random.default_rng(404)
    alpha = np.zeros((SIZE, SIZE), np.float32)
    shade = np.zeros((SIZE, SIZE), np.float32)  # 0 dark brown .. 1 pale tan, per speck
    for k in range(2600):
        rad = float(rng.choice([0.8, 1.2, 1.7, 2.4], p=[0.4, 0.32, 0.2, 0.08]))
        sp = disc(rad, 1.2) * float(rng.uniform(0.3, 0.9))
        cx, cy = rng.integers(0, SIZE), rng.integers(0, SIZE)
        stamp(alpha, sp, cx, cy)
        h = sp.shape[0]
        ys = (np.arange(h) + cy - h // 2) % SIZE
        xs = (np.arange(h) + cx - h // 2) % SIZE
        shade[np.ix_(ys, xs)] = np.where(sp > 0.05, float(rng.uniform(0.0, 1.0)), shade[np.ix_(ys, xs)])
    for k in range(70):  # small clumps: a few grains stuck together
        cx, cy = rng.integers(0, SIZE), rng.integers(0, SIZE)
        for g in range(int(rng.integers(3, 8))):
            dx, dy = rng.normal(0, 5), rng.normal(0, 5)
            stamp(alpha, disc(float(rng.uniform(1.4, 3.2)), 1.4), cx + dx, cy + dy, float(rng.uniform(0.45, 0.85)))
    film = periodic_blur(rng.random((SIZE, SIZE)).astype(np.float32), 18.0)
    film = (film - film.min()) / (film.max() - film.min())
    film = np.clip((film - 0.45) * 2.2, 0, 1) * 0.07          # a barely-there dust film
    alpha = np.maximum(alpha, film)
    dark, pale = np.array([92, 60, 38], np.float32), np.array([176, 128, 84], np.float32)
    out = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgb = dark[None, None, :] * (1 - shade[..., None]) + pale[None, None, :] * shade[..., None]
    rgb = np.where(alpha[..., None] > 0, rgb, pale[None, None, :])
    out[..., :3] = np.clip(rgb + 0.5, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return out


def build_acid(rain_path):
    """A rain texture with its alpha kept and its colour moved from blue-grey to faint yellow-green."""
    src = np.asarray(Image.open(rain_path).convert("RGBA"), dtype=np.float32)
    lum = src[..., :3].mean(axis=2, keepdims=True) * ACID_LIFT
    out = src.copy()
    out[..., :3] = np.clip(lum * ACID_TINT[None, None, :], 0, 255)
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def build_etch():
    """Etched-glass haze: a barely-there film plus fine pits that cluster where the acid sat longest."""
    rng = np.random.default_rng(1969)
    film = periodic_blur(rng.random((SIZE, SIZE)).astype(np.float32), 9.0)
    film = (film - film.min()) / (film.max() - film.min())
    patch = periodic_blur(rng.random((SIZE, SIZE)).astype(np.float32), 38.0)
    patch = (patch - patch.min()) / (patch.max() - patch.min())
    patch = np.clip((patch - 0.35) * 2.4, 0, 1)              # where pitting concentrates
    alpha = np.clip((film - 0.35) * 1.4, 0, 1) * (0.06 + 0.10 * patch)
    pits = np.zeros((SIZE, SIZE), np.float32)
    placed = 0
    while placed < 5200:
        cx, cy = int(rng.integers(0, SIZE)), int(rng.integers(0, SIZE))
        if rng.random() > 0.12 + 0.88 * patch[cy, cx]:
            continue
        placed += 1
        rad = float(rng.choice([0.8, 1.1, 1.6, 2.3], p=[0.42, 0.33, 0.18, 0.07]))
        stamp(pits, disc(rad, 1.1), cx, cy, float(rng.uniform(0.25, 0.7)))
    alpha = np.maximum(alpha, pits)
    out = np.zeros((SIZE, SIZE, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 214, 226, 128
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return out


FROST_W, FROST_H = 1024, 512     # one image across the whole view (16:9 is close enough at 2:1)
FROST_CLEAR = 0.45               # fraction of each half-extent, from the border, that frost may reach


def build_frost():
    """Frost creeping in from the borders and corners: ferns grown inward, a soft film at the very edge, clear centre."""
    rng = np.random.default_rng(1977)
    ss = 2                                                   # supersample the strokes for soft edges
    img = Image.new("L", (FROST_W * ss, FROST_H * ss), 0)
    draw = ImageDraw.Draw(img)

    def fern(x, y, ang, length, depth, bright):
        """A wavering trunk with side branches at about 60 degrees, each a smaller fern."""
        step = 5.0 * ss
        n = max(2, int(length * ss / step))
        for i in range(n):
            ang += rng.normal(0, 0.07)
            nx, ny = x + math.cos(ang) * step, y + math.sin(ang) * step
            fade = 1.0 - 0.55 * i / n
            draw.line([(x, y), (nx, ny)], fill=int(255 * bright * fade), width=ss + 1 if depth < 2 else ss)
            if depth < 3 and i % 2 == 1 and i < n - 1:
                for side in (-1, 1):
                    if rng.random() < 0.9:
                        fern(nx, ny, ang + side * rng.uniform(0.85, 1.15), (length - i * 5.0) * rng.uniform(0.28, 0.42),
                             depth + 1, bright * 0.85)
            x, y = nx, ny

    half_w, half_h = FROST_W / 2.0, FROST_H / 2.0
    for edge, count in ((0, 120), (1, 120), (2, 70), (3, 70)):     # top, bottom, left, right
        for _ in range(count):
            t = float(rng.random())
            if edge < 2:
                x, y = t * FROST_W, (0.0 if edge == 0 else float(FROST_H))
                inward = math.pi / 2 if edge == 0 else -math.pi / 2
                reach = half_h * FROST_CLEAR
            else:
                x, y = (0.0 if edge == 2 else float(FROST_W)), t * FROST_H
                inward = 0.0 if edge == 2 else math.pi
                reach = half_w * FROST_CLEAR
            corner = abs(2 * t - 1) ** 3                     # reach grows toward either end of the edge
            length = reach * rng.uniform(0.25, 0.75) * (1.0 + 0.35 * corner)
            fern(x * ss, y * ss, inward + rng.normal(0, 0.28), length, 0, float(rng.uniform(0.6, 1.0)))
    for cx, cy, base in ((0, 0, math.pi / 4), (FROST_W, 0, 3 * math.pi / 4), (0, FROST_H, -math.pi / 4),
                         (FROST_W, FROST_H, -3 * math.pi / 4)):    # extra growth straight out of each corner
        for _ in range(26):
            fern(cx * ss, cy * ss, base + rng.normal(0, 0.55), half_h * FROST_CLEAR * rng.uniform(0.7, 1.15), 0,
                 float(rng.uniform(0.7, 1.0)))
    crystals = np.asarray(img.resize((FROST_W, FROST_H), Image.LANCZOS), np.float32) / 255.0

    # Distance to the nearest border as a fraction of the half-extent, soft-minimum so corners fill in.
    ys, xs = np.mgrid[0:FROST_H, 0:FROST_W].astype(np.float32)
    dx = np.minimum(xs + 0.5, FROST_W - xs - 0.5) / half_w
    dy = np.minimum(ys + 0.5, FROST_H - ys - 0.5) / half_h
    soft = 0.05
    d = -soft * np.log(np.exp(-dx / soft) + np.exp(-dy / soft))
    t = np.clip(d / 0.40, 0, 1)
    env = 1.0 - t * t * (3 - 2 * t)                          # 1 at the border, 0 from 40% in

    # Thin film at the very border, broken up by noise.
    noise = rng.random((FROST_H, FROST_W)).astype(np.float32)
    grain = np.asarray(Image.fromarray((noise * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.6)), np.float32)
    grain = (grain - grain.min()) / (grain.max() - grain.min())
    film = np.clip(1.0 - d / 0.16, 0, 1) ** 1.4 * (0.30 + 0.45 * grain)
    alpha = np.maximum(crystals * (0.35 + 0.65 * env), film)
    alpha = np.clip(alpha * np.sqrt(env), 0, 1)
    alpha[np.minimum(dx, dy) > FROST_CLEAR] = 0.0            # the centre stays glass
    out = np.zeros((FROST_H, FROST_W, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 226, 238, 255
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return out


def build_ice():
    """Sparse fine frozen grains, small rimed pits and short ice scratch marks (tileable)."""
    rng = np.random.default_rng(2031)
    alpha = np.zeros((SIZE, SIZE), np.float32)
    for _ in range(620):                                     # frozen grains
        rad = float(rng.choice([0.7, 1.0, 1.5, 2.1], p=[0.4, 0.33, 0.20, 0.07]))
        stamp(alpha, disc(rad, 0.9), rng.integers(0, SIZE), rng.integers(0, SIZE), float(rng.uniform(0.55, 1.0)))
    for _ in range(85):                                      # rimed pits: a crisp ring round a fainter centre
        rad = float(rng.uniform(2.2, 4.4))
        ring = disc(rad, 1.0)
        inner = disc(rad - 1.3, 1.0)
        o = (ring.shape[0] - inner.shape[0]) // 2
        ring[o:o + inner.shape[0], o:o + inner.shape[1]] -= inner * 0.8
        stamp(alpha, np.clip(ring, 0, 1), rng.integers(0, SIZE), rng.integers(0, SIZE), float(rng.uniform(0.6, 0.95)))
    scratches = Image.new("L", (SIZE, SIZE), 0)
    sd = ImageDraw.Draw(scratches)
    for _ in range(70):                                      # short, slightly bent; drawn at 9 offsets so they wrap
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE)
        ang, length, bend = rng.uniform(0, math.pi), rng.uniform(8, 30), rng.normal(0, 0.05)
        pts = []
        for _ in range(8):
            pts.append((x, y))
            ang += bend
            x, y = x + math.cos(ang) * length / 7, y + math.sin(ang) * length / 7
        pts.append((x, y))
        fill = int(255 * rng.uniform(0.4, 0.85))
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                sd.line([(px + ox, py + oy) for px, py in pts], fill=fill, width=1)
    alpha = np.maximum(alpha, np.asarray(scratches, np.float32) / 255.0)
    out = np.zeros((SIZE, SIZE, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 214, 232, 255
    out[..., 3] = np.clip(alpha * 255 + 0.5, 0, 255).astype(np.uint8)
    return out


def block(family, tex, n):
    opacity = n / STEPS
    unit = ("\t\t\ttexture_unit\n\t\t\t{\n\t\t\t\ttexture %s\n\t\t\t\tfiltering linear linear linear\n%s\t\t\t}\n")
    mask = "\t\t\ttexture_unit\n\t\t\t{\n\t\t\t\ttexture crwx_wetmask_open.png\n\t\t\t\ttex_address_mode clamp\n\t\t\t\tfiltering linear linear none\n\t\t\t}\n"
    common = "\t\t\tscene_blend alpha_blend\n\t\t\tdepth_check off\n\t\t\tdepth_write off\n\t\t\tcull_hardware none\n\t\t\tcull_software none\n"
    clamp = "\t\t\t\ttex_address_mode clamp\n" if family == "CRWX_WinFrost" else ""  # frost maps once, never tiles
    s = "material %s_A%d\n{\n" % (family, n)
    s += "\t// Masked to the cockpit glass (crwx_wetglass.hlsl): SM4 for DX11, SM3 for\n"
    s += "\t// DX9. CRWetGlass.lua swaps texture unit 1 of both for the craft's mask.\n"
    for sm in ("SM4", "SM3"):
        s += "\ttechnique\n\t{\n\t\tpass\n\t\t{\n"
        s += "\t\t\tvertex_program_ref CRWX_WetGlass_vertex_%s\n\t\t\t{\n\t\t\t}\n" % sm
        s += "\t\t\tfragment_program_ref CRWX_WetGlass_fragment_%s\n\t\t\t{\n\t\t\t\tparam_named opacity float %s\n\t\t\t}\n" % (sm, repr(opacity))
        s += common + unit % (tex, clamp) + mask + "\t\t}\n\t}\n\n"
    s += "\t// Unmasked fixed-function fallback.\n\ttechnique\n\t{\n\t\tpass\n\t\t{\n"
    s += "\t\t\tlighting off\n\t\t\tfog_override true\n" + common
    s += unit % (tex, clamp + "\t\t\t\talpha_op_ex modulate src_texture src_manual %s\n" % repr(opacity))
    s += "\t\t}\n\t}\n}\n\n"
    return s


def build_material():
    head = ("// Generated by Tools/Generate-GlassWeatherAssets.py -- edit the generator, not this file.\n"
            "// Cockpit-glass weather layers drawn by CRWetGlass.lua on the screen overlay (F2/F3): snow flakes,\n"
            "// frost and ice grains (Europa), dust grit (Mars), acid rain and etch (Venus). A<n> is opacity n/16. Same shape as the wrap families of\n"
            "// crwx_wetglass.material; the cockpit glass (F1) draws the same textures through\n"
            "// CRWX_CockpitGlass_W<a>C<b> passes.\n\n")
    body = "".join(block(f, t, n) for f, t in FAMILIES for n in range(1, STEPS + 1))
    return (head + body).rstrip("\n") + "\n"


def png_bytes(arr):
    import io
    buf = io.BytesIO()
    Image.fromarray(arr, "RGBA").save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--flake", default=DEFAULT_FLAKE)
    args = ap.parse_args()
    outputs = {os.path.join(TEX, "crwx_wingrit.png"): png_bytes(build_grit()),
               os.path.join(TEX, "crwx_winetch.png"): png_bytes(build_etch()),
               os.path.join(TEX, "crwx_winfrost.png"): png_bytes(build_frost()),
               os.path.join(TEX, "crwx_winice.png"): png_bytes(build_ice()),
               MAT: build_material().replace("\n", "\r\n").encode("ascii")}
    for rain, acid in ACID_SOURCES:
        outputs[os.path.join(TEX, acid)] = png_bytes(build_acid(os.path.join(TEX, rain)))
    snow = os.path.join(TEX, "crwx_winsnow.png")
    if os.path.exists(args.flake):
        outputs[snow] = png_bytes(build_snow(args.flake))
    elif not args.check:
        print("snowflake source not found: " + args.flake, file=sys.stderr)
        return 2
    bad = 0
    for path, data in outputs.items():
        if args.check:
            same = os.path.exists(path) and open(path, "rb").read() == data
            if not same:
                bad += 1
                print("differs: " + os.path.relpath(path, ROOT))
        else:
            with open(path, "wb") as fh:
                fh.write(data)
            print("wrote " + os.path.relpath(path, ROOT))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
