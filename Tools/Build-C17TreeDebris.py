"""Debris sprites and explosion ODFs for the misn17 trees (c17frst1-4, c17tree1-2).

    python Tools/Build-C17TreeDebris.py [--preview DIR]

Same method as ISDF Chronicles' tools/plant_debris_sprites.py (its xpltrhit /
xpltree): every sprite is cut from the texture the tree already wears, so the
debris matches the model.

- Jungle trees (c17tree1/2, cr17_foliage + cr17_bark, which are byte-identical
  to ISDFC's FoliageAtlas_Mire + motrnk01): the same cuts as ISDFC's pdleafr,
  pdkelp and pdbark, under cr17 names.
- Firs (c17frst1-3, cr17_fbranch1 + cr17_ftrunk1): a needle sprig and fir bark.
- Birch (c17frst4, cr17_fbranch2 + cr17_ftrunk2): a gold-leaf sprig and birch bark.
  The sprigs come from the generated sheets the branch atlases were built from
  (Tools/Prep-Misn17GenTextures.py), toned to the atlas.

Writes 128x128 DXT5 sprites to Assets/Textures and the six zero-damage
explosion ODFs (xc17?hit = ordnance hit, xc17?die = death) to ODF/.
Sounds: c17crack.wav / c17fell.wav are ISDFC's crckt01.wav / xcollapse.wav.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
TEX = ROOT / "Assets" / "Textures"
ODF = ROOT / "ODF"
SIZE = 128


def load(name: str) -> Image.Image:
    return Image.open(TEX / name).convert("RGBA")


def fit(im: Image.Image, pad: int = 6) -> Image.Image:
    """Trim to the alpha bbox and centre in a SIZE square (aspect kept)."""
    bbox = im.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    s = (SIZE - 2 * pad) / max(im.size)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(im, ((SIZE - im.width) // 2, (SIZE - im.height) // 2), im)
    return out


def atlas_cut(atlas: Image.Image, box, layout: int | None = None) -> Image.Image:
    """A cutout from a foliage atlas; its own alpha is the shape (largest piece only).
    `layout`: the atlas width the box was measured at (the box scales with the atlas)."""
    from scipy import ndimage
    if layout:
        box = tuple(round(v * atlas.width / layout) for v in box)
    a = np.array(atlas.crop(box))
    solid = a[..., 3] > 40
    lab, n = ndimage.label(ndimage.binary_dilation(solid, iterations=2))
    if n:
        keep = np.argmax(ndimage.sum(solid, lab, range(1, n + 1))) + 1
        solid &= lab == keep
    a[..., 3] = np.where(solid, a[..., 3], 0)
    return fit(Image.fromarray(a))


def sheet_sprig(sheet: str, atlas: Image.Image, pick: int) -> Image.Image:
    """One whole sprig from the owner-generated sprig sheet the branch atlas was
    built from (References/TextureRevamp/raw), keyed off white and toned to the
    atlas's mean brightness. pick: index into the sprigs sorted small to large."""
    from scipy import ndimage
    rgb = np.asarray(Image.open(ROOT / "References/TextureRevamp/raw" / sheet).convert("RGB"), np.float32)
    alpha = np.clip((255 - rgb.min(-1) - 30) / 45, 0, 1)
    _, (iy, ix) = ndimage.distance_transform_edt(alpha < 0.95, return_indices=True)
    colour = rgb[iy, ix]
    lab, n = ndimage.label(ndimage.binary_closing(alpha > 0.3, iterations=3))
    sizes = ndimage.sum(alpha > 0.5, lab, range(1, n + 1))
    order = [i + 1 for i in np.argsort(sizes) if sizes[i] >= 2000]
    k = order[pick]
    sl = ndimage.find_objects(lab)[k - 1]
    a = np.array(atlas).astype(np.float32)
    lum = np.array([.299, .587, .114], np.float32)
    target = (a[..., :3][a[..., 3] > 128] @ lum).mean()
    piece = colour[sl]
    solid = (lab[sl] == k) & (alpha[sl] > 0.5)
    piece = piece * min(1.0, target / (piece[solid] @ lum).mean())
    rgba = np.concatenate([np.clip(piece, 0, 255), (alpha[sl] * (lab[sl] == k) * 255)[..., None]], -1)
    return fit(Image.fromarray(rgba.round().astype(np.uint8), "RGBA"))


def chip(src: Image.Image, box, seed: int, points: int = 8, roundness: float = 0.35,
         elongate: float = 1.0, rim: float = 0.45) -> Image.Image:
    """A jagged chip of an opaque texture, with a darkened rim."""
    rng = np.random.default_rng(seed)
    tex = src.crop(box).resize((SIZE, SIZE), Image.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    c = SIZE / 2
    angles = np.sort(rng.uniform(0, 2 * math.pi, points))
    radii = c * 0.9 * (1 - roundness + roundness * rng.uniform(0.4, 1.0, points))
    poly = [(c + r * math.cos(t) * elongate, c + r * math.sin(t) / elongate) for r, t in zip(radii, angles)]
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    inner = mask.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(3))
    t = np.array(tex).astype(float)
    shade = 1 - rim * (1 - np.array(inner, float) / 255)
    t[..., :3] *= shade[..., None]
    t[..., 3] = np.array(mask)
    return Image.fromarray(np.clip(t, 0, 255).astype(np.uint8))


def sprites() -> dict[str, Image.Image]:
    foliage = load("cr17_foliage.dds")     # 2048^2, = ISDFC FoliageAtlas_Mire
    bark = load("cr17_bark.dds")           # = ISDFC motrnk01
    needles = load("cr17_fbranch1.dds")    # fir branch cards (pack layout, 512 or 2048)
    gold = load("cr17_fbranch2.dds")       # birch branch cards (pack layout, 512 or 2048)
    fir = load("cr17_ftrunk1.dds")         # 1024x2048
    birch = load("cr17_ftrunk2.dds")       # 512x2048
    return {
        # jungle: ISDFC's own cuts (pdleafr, pdkelp, pdbark)
        "cr17_dleaf": atlas_cut(foliage, (370, 395, 440, 490)),
        "cr17_dkelp": atlas_cut(foliage, (300, 815, 512, 892)),
        "cr17_dbark": chip(bark, (300, 300, 560, 560), seed=11, points=7, elongate=1.5, roundness=0.45),
        # fir: the smallest whole sprig from the generated sheet, fir bark
        "cr17_dneedl": sheet_sprig("cr17_fbranch1_gen.jpg", needles, 0),
        "cr17_dfbark": chip(fir, (380, 900, 640, 1160), seed=21, points=7, elongate=1.6, roundness=0.45),
        # birch: the smallest whole sprig from the generated sheet, birch bark
        "cr17_dgleaf": sheet_sprig("cr17_fbranch2_gen.jpg", gold, 0),
        "cr17_dbbark": chip(birch, (130, 900, 390, 1160), seed=22, points=7, elongate=1.6, roundness=0.45),
    }


# ----- explosion ODFs ------------------------------------------------------

DAMAGE = """damageRadius = 0.0
damageBallistic = 0
damageConcussion = 0
damageFlame = 0
damageImpact = 0
"""


def particle(name, sim, life, tex, color, r0, r1, spin):
    rgb = color
    return f"""[{name}]
simulateBase = "{sim}"
lifeTime = {life}
renderBase = "draw_twirl"
textureName = "{tex}"
textureBlend = "srcalpha invsrcalpha modulatealpha"
startColor = "{rgb} {255 if tex != 'smokeb.tga' else (200 if sim == 'sim_smoke' else 180)}"
finishColor = "{rgb} 0"
startRadius = {r0}
finishRadius = {r1}
animateTime = {life}
rotationRate = {spin}
"""


def explosion(odf, parts, sound):
    """parts: (section, count, veloc, bias, particle-args)."""
    head = ['[ExplosionClass]', 'classLabel = "explosion"', '', f'particleTypes = {len(parts)}', '']
    for i, (sec, count, veloc, bias, _) in enumerate(parts, 1):
        head += [f'particleClass{i} = "{odf}.{sec}"', f'particleCount{i} = {count}',
                 f'particleVeloc{i} = "{veloc}"', f'particleBias{i} = "{bias}"', '']
    head += [f'explSound = "{sound}"']
    body = "\n".join(particle(sec, *args) for sec, _, _, _, args in parts)
    return "\n".join(head) + "\n" + DAMAGE + "\n" + body


def explosions() -> dict[str, str]:
    """Hit = xpltrhit, death = xpltree (ISDFC), with each kind's own debris and dust colour."""
    kinds = {
        # tag: (leaf, leaf2 or None, bark, dust rgb, spatter rgb)
        "j": ("cr17_dleaf.dds", "cr17_dkelp.dds", "cr17_dbark.dds", "90 85 50", "63 127 15"),
        "f": ("cr17_dneedl.dds", None, "cr17_dfbark.dds", "70 75 55", "45 80 35"),
        "b": ("cr17_dgleaf.dds", None, "cr17_dbbark.dds", "105 95 60", "150 120 40"),
    }
    out = {}
    for tag, (leaf, leaf2, bark, dust, spatter) in kinds.items():
        hit = f"xc17{tag}hit"
        out[hit] = explosion(hit, [
            ("puff", 1, "0 0 0", "0 1 0", ("sim_smoke", 0.8, "smokeb.tga", dust, 0.6, 3.0, 1.0)),
            ("bark", 4, "6 5 6", "0 6 0", ("sim_chunk", 1.8, bark, "255 255 255", 0.3, 0.27, 14.0)),
            ("leaf", 3, "5 4 5", "0 5 0", ("sim_ember", 3.0, leaf, "255 255 255", 0.7, 0.63, 4.0)),
        ], "c17crack.wav")
        die = f"xc17{tag}die"
        parts = [
            ("core", 1, "0 0 0", "0 2 0", ("sim_smoke", 2.0, "smokeb.tga", dust, 3.0, 18.0, 1.0)),
            ("leaf", 14 if leaf2 else 22, "12 8 12", "0 9 0",
             ("sim_ember", 4.5, leaf, "255 255 255", 0.9, 0.81, 4.0)),
        ]
        if leaf2:
            parts.append(("kelp", 10, "12 8 12", "0 9 0", ("sim_ember", 4.5, leaf2, "255 255 255", 1.0, 0.9, 3.0)))
        parts += [
            ("bark", 12, "10 6 10", "0 10 0", ("sim_chunk", 3.0, bark, "255 255 255", 0.45, 0.405, 12.0)),
            ("spatter", 8, "14 10 14", "0 4 0", ("sim_ember", 2.5, "smokeb.tga", spatter, 1.0, 2.5, 1.0)),
        ]
        out[die] = explosion(die, parts, "c17fell.wav")
    return out


# tree ODF -> (hitExplosion, explosionName); Build-Misn17Forest/Jungle write the same keys
TREES = {
    "c17frst1": ("xc17fhit", "xc17fdie"),
    "c17frst2": ("xc17fhit", "xc17fdie"),
    "c17frst3": ("xc17fhit", "xc17fdie"),
    "c17frst4": ("xc17bhit", "xc17bdie"),
    "c17tree1": ("xc17jhit", "xc17jdie"),
    "c17tree2": ("xc17jhit", "xc17jdie"),
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", type=Path, help="also write PNGs and a contact sheet here")
    args = ap.parse_args()
    out = sprites()
    for name, im in out.items():
        if im.getchannel("A").getbbox() is None:
            raise SystemExit(f"{name}: blank sprite")
        im.save(TEX / f"{name}.dds", pixel_format="DXT5")
    for name, text in explosions().items():
        (ODF / f"{name}.odf").write_text(text, encoding="ascii", newline="\n")
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        sheet = Image.new("RGBA", (SIZE * len(out), SIZE + 4), (70, 80, 60, 255))
        for i, (name, im) in enumerate(out.items()):
            im.save(args.preview / f"{name}.png")
            sheet.alpha_composite(im, (SIZE * i, 2))
        sheet.save(args.preview / "debris_sheet.png")
    print("wrote", ", ".join(out), "and", ", ".join(explosions()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
