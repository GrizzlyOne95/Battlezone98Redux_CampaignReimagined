"""Turn the Black Dog recycler's deployed-wall logo right way up.

bvrecy.mesh binds the right-hand wall panel to bone bre11bdc (index 5). The deploy
clip swings that panel 90 degrees about its hinge, so the dog logo painted on it
(UV island centred at texel 415,370 of bvrecy_D.dds) ends up rotated 180 degrees
while the recycler is deployed. Only bone-5 triangles use that island, so the fix
is a 180 degree rotation of the logo disc inside the diffuse map; UVs and the mesh
stay as they are.

The stock DXT1 map is not shipped by CR, so this reads it from the game install,
edits the disc, re-encodes with texconv, and splices only the re-encoded 4x4 blocks
that cover the disc into the stock bytes (every mip). The rest of the file stays
bit-identical to stock: same DXT1, same 11-mip chain.

    python Tools/UnitsAndBuildings/Fix-BvrecyLogo.py [--install "<BZR folder>"]
"""
import argparse
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bcdds  # noqa: E402

CX, CY, RADIUS = 415, 370, 20.5  # logo disc incl. its dark outline, in texels
DEFAULT_INSTALL = r'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux'
DEST = Path(__file__).resolve().parents[2] / 'Assets' / 'Textures' / 'bvrecy_D.dds'


def mip_layout(width, height, mips, block=8):
    offset, out = 128, []
    for i in range(mips):
        bw, bh = max(1, (width >> i) + 3 >> 2), max(1, (height >> i) + 3 >> 2)
        out.append((offset, bw, bh))
        offset += block * bw * bh
    return out


def rotate_disc(image):
    px = np.array(image.convert('RGBA'))
    yy, xx = np.mgrid[0:px.shape[0], 0:px.shape[1]]
    inside = (xx - CX) ** 2 + (yy - CY) ** 2 <= RADIUS ** 2
    out = px.copy()
    out[inside] = px[2 * CY - yy[inside], 2 * CX - xx[inside]]  # point reflection about (CX, CY)
    return Image.fromarray(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--install', default=DEFAULT_INSTALL)
    args = ap.parse_args()
    stock_path = Path(args.install) / 'BZ_ASSETS' / 'pc' / 'textures' / 'DIFF' / 'bvrecy_D.dds'
    stock = stock_path.read_bytes()
    problem = bcdds.bc_dds_problem(stock, 1024)
    if problem:
        raise SystemExit(f'unexpected stock texture: {problem}')
    mips = struct.unpack_from('<I', stock, 28)[0]
    with tempfile.TemporaryDirectory() as tmp:
        stock_png = Path(tmp) / 'stock.png'
        Image.open(stock_path).convert('RGBA').save(stock_png)
        new_dds = Path(tmp) / 'bvrecy_D.dds'
        bcdds.save_bc(rotate_disc(Image.open(stock_png)), new_dds)
        new = new_dds.read_bytes()
    problem = bcdds.bc_dds_problem(new, 1024)
    if problem:
        raise SystemExit(f're-encoded texture is wrong: {problem}')
    out = bytearray(stock)
    for i, (offset, bw, bh) in enumerate(mip_layout(1024, 1024, mips)):
        bx0, bx1 = int((CX - RADIUS) // 1) >> i >> 2, int((CX + RADIUS) // 1) >> i >> 2
        by0, by1 = int((CY - RADIUS) // 1) >> i >> 2, int((CY + RADIUS) // 1) >> i >> 2
        for by in range(by0, min(by1, bh - 1) + 1):
            for bx in range(bx0, min(bx1, bw - 1) + 1):
                o = offset + 8 * (by * bw + bx)
                out[o:o + 8] = new[o:o + 8]
    DEST.write_bytes(bytes(out))
    print(f'wrote {DEST} ({len(out)} bytes, {mips} mips)')


if __name__ == '__main__':
    main()
