#!/usr/bin/env python3
"""Generate the cockpit-glass weather layers (snow flakes on Europa, dust grit on Mars).

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
  Materials/crwx_glassweather.material   CRWX_WinSnow_A1..A16 and CRWX_WinGrit_A1..A16, the
        overlay (F2/F3) materials, the same shape as the wrap families in crwx_wetglass.material.
        The cockpit-glass (F1) passes need no material of their own: CRWetGlass points a pass of
        CRWX_CockpitGlass_W<a>C<b> at the texture.

Deterministic (fixed seed). The flake source is read only when a texture is written; --check
compares the grit and the material, and the snow texture when the source is found.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "Assets", "Textures")
MAT = os.path.join(ROOT, "Materials", "crwx_glassweather.material")
DEFAULT_FLAKE = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\addon\ISDF Chronicles\snowflak.dds"
SIZE = 1024
STEPS = 16
FAMILIES = (("CRWX_WinSnow", "crwx_winsnow.png"), ("CRWX_WinGrit", "crwx_wingrit.png"))


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


def block(family, tex, n):
    opacity = n / STEPS
    unit = ("\t\t\ttexture_unit\n\t\t\t{\n\t\t\t\ttexture %s\n\t\t\t\tfiltering linear linear linear\n%s\t\t\t}\n")
    mask = "\t\t\ttexture_unit\n\t\t\t{\n\t\t\t\ttexture crwx_wetmask_open.png\n\t\t\t\ttex_address_mode clamp\n\t\t\t\tfiltering linear linear none\n\t\t\t}\n"
    common = "\t\t\tscene_blend alpha_blend\n\t\t\tdepth_check off\n\t\t\tdepth_write off\n\t\t\tcull_hardware none\n\t\t\tcull_software none\n"
    s = "material %s_A%d\n{\n" % (family, n)
    s += "\t// Masked to the cockpit glass (crwx_wetglass.hlsl): SM4 for DX11, SM3 for\n"
    s += "\t// DX9. CRWetGlass.lua swaps texture unit 1 of both for the craft's mask.\n"
    for sm in ("SM4", "SM3"):
        s += "\ttechnique\n\t{\n\t\tpass\n\t\t{\n"
        s += "\t\t\tvertex_program_ref CRWX_WetGlass_vertex_%s\n\t\t\t{\n\t\t\t}\n" % sm
        s += "\t\t\tfragment_program_ref CRWX_WetGlass_fragment_%s\n\t\t\t{\n\t\t\t\tparam_named opacity float %s\n\t\t\t}\n" % (sm, repr(opacity))
        s += common + unit % (tex, "") + mask + "\t\t}\n\t}\n\n"
    s += "\t// Unmasked fixed-function fallback.\n\ttechnique\n\t{\n\t\tpass\n\t\t{\n"
    s += "\t\t\tlighting off\n\t\t\tfog_override true\n" + common
    s += unit % (tex, "\t\t\t\talpha_op_ex modulate src_texture src_manual %s\n" % repr(opacity))
    s += "\t\t}\n\t}\n}\n\n"
    return s


def build_material():
    head = ("// Generated by Tools/Generate-GlassWeatherAssets.py -- edit the generator, not this file.\n"
            "// Cockpit-glass weather layers drawn by CRWetGlass.lua on the screen overlay (F2/F3): snow flakes\n"
            "// (Europa) and dust grit (Mars). A<n> is opacity n/16. Same shape as the wrap families of\n"
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
               MAT: build_material().replace("\n", "\r\n").encode("ascii")}
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
