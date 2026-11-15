#!/usr/bin/env python3
"""Convert the ground-kickup sprite art for CRWake to DDS.

    python Tools/TexturesAndSky/Build-KickupTextures.py SOURCE_DIR

SOURCE_DIR holds cr_kick_regolith.png, cr_kick_ice.png, cr_kick_clod.png and
cr_kick_puff.png: 256x256 RGBA cut-outs (alpha from brightness, transparent
edges). Each becomes Assets/Textures/<name>.dds, DXT5 with a full mip chain,
the same layout as the shipped cr_*.dds weather art. Needs Pillow.

    python Tools/TexturesAndSky/Build-KickupTextures.py --cut-ice

Cuts four single shards out of the SHIPPED Assets/Textures/cr_kick_ice.dds (alpha connected
components) and writes cr_kick_ice_a..d.dds: 128x128, one shard centred on a transparent canvas
with room to rotate, soft alpha edges kept. Deterministic; the CRWake/*Chips_A..D systems use them
(Ogre particles cannot pick a sheet cell). Needs Pillow, numpy and scipy.
"""
import io
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "Assets" / "Textures"
NAMES = ("cr_kick_regolith", "cr_kick_ice", "cr_kick_clod", "cr_kick_puff")


def dxt5_blocks(img):
    """Pillow's DXT5 encoder, without its 128 byte header."""
    buf = io.BytesIO()
    img.save(buf, format="DDS", pixel_format="DXT5")
    return buf.getvalue()[128:]


def write_dds(path, img):
    levels, data, cur = 0, b"", img
    while True:
        data += dxt5_blocks(cur)
        levels += 1
        if cur.width == 1 and cur.height == 1:
            break
        cur = cur.resize((max(1, cur.width // 2), max(1, cur.height // 2)), Image.BOX)
    top = max(16, (img.width // 4) * (img.height // 4) * 16)
    header = struct.pack("<4sI", b"DDS ", 124)
    header += struct.pack("<6I", 0xA1007, img.height, img.width, top, 0, levels)
    header += b"\0" * 44
    header += struct.pack("<2I4s5I", 32, 4, b"DXT5", 0, 0, 0, 0, 0)
    header += struct.pack("<5I", 0x401008, 0, 0, 0, 0)
    path.write_bytes(header + data)


CUT_THRESHOLD = 64      # alpha that separates one shard from its neighbours
CUT_MIN_AREA = 700      # px of a shard at that threshold worth cutting
CUT_GROW = 3            # px of soft edge taken around a shard
CUT_CANVAS = 128        # shard <= ~64 px, so a 45 degree turn still fits


def cut_ice():
    import numpy as np
    from scipy import ndimage

    sheet = np.array(Image.open(OUT / "cr_kick_ice.dds").convert("RGBA"))
    alpha = sheet[:, :, 3]
    labels, count = ndimage.label(alpha > CUT_THRESHOLD, structure=np.ones((3, 3)))
    shards = []
    for index in range(1, count + 1):
        mask = labels == index
        area = int(mask.sum())
        if area < CUT_MIN_AREA:
            continue
        ys, xs = np.nonzero(mask)
        eig = np.linalg.eigvalsh(np.cov(np.stack([xs, ys])))
        shards.append({"mask": mask, "area": area, "elong": float(np.sqrt(eig[1] / max(eig[0], 1e-6))),
                       "key": (int(ys.min()), int(xs.min()))})
    assert len(shards) >= 4, f"only {len(shards)} shards found"
    # Four distinct shapes: the biggest, the most elongated, the most compact, then the next biggest.
    picked = []
    for pick in (lambda s: -s["area"], lambda s: -s["elong"], lambda s: s["elong"], lambda s: -s["area"]):
        best = min((s for s in shards if all(s is not p for p in picked)), key=lambda s: (pick(s), s["key"]))
        picked.append(best)
    solid = labels > 0
    for letter, shard in zip("abcd", picked):
        others = solid & ~shard["mask"]
        keep = ndimage.binary_dilation(shard["mask"], iterations=CUT_GROW) & ~others & (alpha > 0)
        ys, xs = np.nonzero(keep)
        crop = sheet[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        crop[~keep[ys.min():ys.max() + 1, xs.min():xs.max() + 1]] = 0
        h, w = crop.shape[:2]
        assert max(h, w) <= CUT_CANVAS * 0.72, (letter, w, h)
        canvas = np.zeros((CUT_CANVAS, CUT_CANVAS, 4), np.uint8)
        y0, x0 = (CUT_CANVAS - h) // 2, (CUT_CANVAS - w) // 2
        canvas[y0:y0 + h, x0:x0 + w] = crop
        write_dds(OUT / f"cr_kick_ice_{letter}.dds", Image.fromarray(canvas, "RGBA"))
        print("wrote", OUT / f"cr_kick_ice_{letter}.dds", f"{w}x{h} area {shard['area']} elong {shard['elong']:.2f}")


def main():
    if sys.argv[1:] == ["--cut-ice"]:
        cut_ice()
        return
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    for name in NAMES:
        img = Image.open(src / f"{name}.png").convert("RGBA")
        assert img.size == (256, 256), (name, img.size)
        write_dds(OUT / f"{name}.dds", img)
        print("wrote", OUT / f"{name}.dds")


if __name__ == "__main__":
    main()
