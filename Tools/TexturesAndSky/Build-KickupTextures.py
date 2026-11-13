#!/usr/bin/env python3
"""Convert the ground-kickup sprite art for CRWake to DDS.

    python Tools/TexturesAndSky/Build-KickupTextures.py SOURCE_DIR

SOURCE_DIR holds cr_kick_regolith.png, cr_kick_ice.png, cr_kick_clod.png and
cr_kick_puff.png: 256x256 RGBA cut-outs (alpha from brightness, transparent
edges). Each becomes Assets/Textures/<name>.dds, DXT5 with a full mip chain,
the same layout as the shipped cr_*.dds weather art. Needs Pillow.
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


def main():
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
