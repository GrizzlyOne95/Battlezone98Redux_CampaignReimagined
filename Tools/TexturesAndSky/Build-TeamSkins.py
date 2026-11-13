"""Build the co-op team-skin masks and <unit>_tm materials (2026-11-07).

    python Tools/TexturesAndSky/Build-TeamSkins.py                 report what would be written
    python Tools/TexturesAndSky/Build-TeamSkins.py --write         write the files
    python Tools/TexturesAndSky/Build-TeamSkins.py --preview DIR   also write mask PNGs

For every av*/bv*/sv*/cv* vehicle material that inherits CR_BZBase this writes:

  Assets/Textures/crteam_<diffuse>.dds   RGBA DXT5, 512^2, full mips.
                                         A   = paint weight: the faction's
                                               hull paint, picked by hue, with
                                               lamps (emissive map) cut out.
                                         RGB = digital camo pattern (sRGB).
  Materials/CR_TeamSkins.material        "<unit>_tm : CR_BZBase", a copy of the
                                         unit's aliases and $variables plus
                                         set_texture_alias TeamMask <mask>.

Nothing is painted until Lua clones a _tm material and sets its teamPaint
uniform alpha above 1.5 (see openshim_enhanced_base-sm4.hlsl ose_team_paint and
Scripts/CRTeamSkins.lua). Only the en-high* techniques read the mask.

Paint hues per faction prefix: av/bv = teal-blue hull, sv = white hull,
cv = olive/yellow camo hull. Diffuse textures are read from Assets/Textures
first, then the game's BZ_ASSETS/pc/textures tree.
"""
import argparse
import glob
import io
import os
import re
import struct
import sys

import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GOG_GAME = r"C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"
MASK_SIZE = 512
OUT_MATERIAL = os.path.join("Materials", "CR_TeamSkins.material")
CAMO = os.path.join(ROOT, "Tools", "Assets", "cr_team_camo.png")
PREFIXES = ("av", "bv", "sv", "cv")


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx, mn = a.max(2), a.min(2)
    d = mx - mn
    safe = np.maximum(d, 1e-6)
    hue = np.where(mx == r, ((g - b) / safe) % 6, np.where(mx == g, (b - r) / safe + 2, (r - g) / safe + 4)) * 60
    sat = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return hue, sat, mx


def hue_dist(h, centre):
    return np.abs(((h - centre + 180.0) % 360.0) - 180.0)


def hull_band(h, s, v):
    """Dominant hue band of the texture = its hull paint (a fixed per-faction hue
    misses: stock av/bv/sv hulls are mostly brown-orange, CRA olive). Peak 10-degree
    bin of the coloured pixels, grown while neighbours stay above 20% of the peak,
    capped at +-60 degrees."""
    coloured = (s > 0.08) & (v > 0.12)
    hist = np.histogram(h[coloured], bins=36, range=(0, 360))[0].astype(np.float64)
    peak = int(hist.argmax())
    lo = hi = peak
    while hi - peak < 6 and hist[(hi + 1) % 36] > 0.2 * hist[peak]:
        hi += 1
    while peak - lo < 6 and hist[(lo - 1) % 36] > 0.2 * hist[peak]:
        lo -= 1
    return (lo + hi + 1) * 5.0, (hi - lo + 1) * 5.0  # centre, half width (degrees)


def paint_weight(a):
    h, s, v = hsv(a)
    centre, half = hull_band(h, s, v)
    return (1 - ss(half, half + 12, hue_dist(h, centre))) * ss(0.06, 0.14, s) * ss(0.10, 0.18, v)


def make_mask(diffuse_path, prefix, emissive_path):
    src = Image.open(diffuse_path).convert("RGB").resize((MASK_SIZE * 2, MASK_SIZE * 2), Image.Resampling.LANCZOS)
    # Hulls are low-saturation (s ~0.1): DXT noise and weathering make per-pixel hue
    # random, so classify a blurred copy (panel-sized decisions, not texel-sized).
    a = np.asarray(src.filter(ImageFilter.GaussianBlur(3)), dtype=np.float32) / 255.0
    m = paint_weight(a)
    mask = Image.fromarray((m * 255.0 + 0.5).astype(np.uint8), "L").filter(ImageFilter.MedianFilter(3))
    mask = mask.resize((MASK_SIZE, MASK_SIZE), Image.Resampling.LANCZOS)
    if emissive_path:
        light = Image.open(emissive_path).convert("RGB").resize(mask.size, Image.Resampling.LANCZOS)
        light = np.asarray(light, dtype=np.float32).max(axis=2) / 255.0
        lamps = Image.fromarray((ss(0.02, 0.08, light) * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))
        mask = ImageChops.multiply(mask, ImageChops.invert(lamps))
    return mask


def bc3_alpha_payload(image, payload):
    """Exact BC3 alpha endpoints (Pillow's alpha coarsens soft edges); keeps 0 at 0."""
    alpha = np.asarray(image.getchannel("A"), dtype=np.int32)
    height, width = alpha.shape
    alpha = np.pad(alpha, ((0, (-height) % 4), (0, (-width) % 4)), mode="edge")
    blocks = alpha.reshape(alpha.shape[0] // 4, 4, alpha.shape[1] // 4, 4).transpose(0, 2, 1, 3).reshape(-1, 16)
    high, low = blocks.max(axis=1), blocks.min(axis=1)
    palette = np.stack([high, low] + [((7 - i) * high + i * low) // 7 for i in range(1, 7)], axis=1)
    indices = np.abs(blocks[:, None, :] - palette[:, :, None]).argmin(axis=1).astype(np.uint64)
    bits = (indices << (np.arange(16, dtype=np.uint64) * 3)).sum(axis=1)
    data = np.frombuffer(payload, dtype=np.uint8).reshape(-1, 16).copy()
    data[:, 0], data[:, 1] = high, low
    for byte in range(6):
        data[:, byte + 2] = ((bits >> (byte * 8)) & 255).astype(np.uint8)
    return data.tobytes()


def dds_dxt5_mips(rgba):
    levels, img = [], rgba
    while True:
        buf = io.BytesIO()
        img.save(buf, "DDS", pixel_format="DXT5")
        levels.append(bc3_alpha_payload(img, buf.getvalue()[128:]))
        if img.size == (1, 1):
            break
        img = img.resize((max(1, img.size[0] // 2), max(1, img.size[1] // 2)), Image.Resampling.LANCZOS)
    first = io.BytesIO()
    rgba.save(first, "DDS", pixel_format="DXT5")
    head = bytearray(first.getvalue()[:128])
    struct.pack_into("<I", head, 8, struct.unpack_from("<I", head, 8)[0] | 0x20000)       # DDSD_MIPMAPCOUNT
    struct.pack_into("<I", head, 28, len(levels))
    struct.pack_into("<I", head, 108, struct.unpack_from("<I", head, 108)[0] | 0x400008)  # MIPMAP|COMPLEX
    return bytes(head) + b"".join(levels)


MATERIAL_RE = re.compile(r"^material\s+(\S+)\s*:\s*CR_BZBase\s*\n\{(.*?)\n\}", re.M | re.S)
ALIAS_RE = re.compile(r"set_texture_alias\s+(\w+)\s+(\S+)")


def unit_materials():
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Materials", "*.material"))):
        base = os.path.basename(path).lower()
        if not base.startswith(PREFIXES):
            continue
        text = open(path, encoding="utf-8", errors="replace", newline="").read().replace("\r\n", "\n")
        for name, body in MATERIAL_RE.findall(text):
            if not name.lower().startswith(PREFIXES) or "headlight" in name.lower():
                continue  # headlight lamp props are not hull paint
            aliases = dict(ALIAS_RE.findall(body))
            if "DiffuseMap" not in aliases:
                continue
            lines = [ln.strip() for ln in body.split("\n")
                     if ln.strip().startswith(("set_texture_alias", "set $"))]
            out.append((name, name[:2].lower(), aliases, lines))
    return out


def texture_index(game):
    index = {}
    dirs = [os.path.join(ROOT, "Assets", "Textures"), os.path.join(game, "BZ_ASSETS", "pc", "textures")]
    for d in dirs:
        for dirpath, _, files in os.walk(d):
            for f in files:
                index.setdefault(f.lower(), os.path.join(dirpath, f))
    return index


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--game", default=GOG_GAME)
    ap.add_argument("--preview")
    args = ap.parse_args()
    index = texture_index(args.game)
    camo = Image.open(CAMO).convert("RGB").resize((MASK_SIZE, MASK_SIZE), Image.Resampling.NEAREST)

    units, masks, missing = unit_materials(), {}, []
    blocks = ["// GENERATED by Tools/Build-TeamSkins.py -- do not edit.",
              "// Co-op team-skin twins: <unit>_tm = <unit> + TeamMask (Scripts/CRTeamSkins.lua).",
              'import * from "CR_BZBase.material"', ""]
    for name, prefix, aliases, lines in units:
        diffuse = aliases["DiffuseMap"]
        src = index.get(diffuse.lower())
        if not src:
            missing.append("%s: %s" % (name, diffuse))
            continue
        mask_name = "crteam_%s.dds" % os.path.splitext(diffuse)[0].lower()
        if mask_name not in masks:
            emissive = index.get(aliases.get("EmissiveMap", "").lower())
            masks[mask_name] = (src, prefix, emissive)
        body = "\n".join("\t" + ln for ln in lines + ["set_texture_alias TeamMask " + mask_name])
        blocks.append("material %s_tm : CR_BZBase\n{\n%s\n}\n" % (name, body))
    text = "\n".join(blocks).replace("\n", "\r\n")  # CR materials are CRLF

    binaries = {}
    for mask_name, (src, prefix, emissive) in sorted(masks.items()):
        mask = make_mask(src, prefix, emissive)
        r, g, b = camo.split()
        binaries[os.path.join("Assets", "Textures", mask_name)] = dds_dxt5_mips(Image.merge("RGBA", (r, g, b, mask)))
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            mask.save(os.path.join(args.preview, mask_name[:-4] + ".png"))

    def emit(rel, data):
        path = os.path.join(ROOT, rel)
        old = open(path, "rb").read() if os.path.exists(path) else None
        state = "unchanged" if old == data else ("new" if old is None else "changed")
        if args.write and state != "unchanged":
            with open(path, "wb") as f:
                f.write(data)
        return state

    print("%-40s %s (%d materials)" % (OUT_MATERIAL, emit(OUT_MATERIAL, text.encode("utf-8")), len(units) - len(missing)))
    states = [emit(rel, data) for rel, data in sorted(binaries.items())]
    print("%d masks: %s" % (len(binaries), {s: states.count(s) for s in set(states)}))
    for m in missing:
        print("MISSING diffuse, no team skin:", m)
    if not args.write:
        print("(dry run; pass --write)")


if __name__ == "__main__":
    sys.exit(main())
