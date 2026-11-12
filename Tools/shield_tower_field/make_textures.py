"""Generate the shield-tower field textures: two pre-tinted hex lattices + a shimmer band.

DX11 constraint: OpenShim's compat path (BZR-OpenShim dx11_legacy_material_compat.cpp,
IsSupportedTwoStageCombo) only accepts single-pass materials with up to 2 texture units
using plain colour_op (modulate/add/alpha_blend); multi-pass and colour_op_ex src_manual
are suppressed. So the colour is baked into the lattice textures (RGB, not greyscale) and
the band texture carries a floor so the lattice stays visible between sweeps.
Output in Assets/Textures: cr_shieldfield_hex_amber.dds, cr_shieldfield_hex_green.dds,
cr_shieldfield_band.dds (BC1 + full mips).
With --preview DIR, also writes PNG previews into DIR.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Tools'))
from bcdds import save_bc  # noqa: E402

SIZE = 512
TINTS = {'amber': (1.0, 0.75, 0.2), 'green': (0.25, 1.0, 0.45)}
BAND_FLOOR = 0.45


def hex_texture(tint):
    # Tile = 2 pointy-top hexes across (flat width SIZE/2). The hex grid's true vertical
    # period is 3R = 0.866*SIZE, so v is stretched by 1/0.866 here; the material's
    # v repeat is 1.1547x the u repeat to put regular hexes back on the surface.
    a = SIZE / 2.0
    R = a / np.sqrt(3.0)
    y_period = 3.0 * R
    xs = (np.arange(SIZE) + 0.5)
    ys = (np.arange(SIZE) + 0.5) * (y_period / SIZE)
    X, Y = np.meshgrid(xs, ys)
    apo = a / 2.0              # hex apothem (centre to edge)
    dmin = None
    for cx0, cy0 in ((0.0, 0.0), (a / 2.0, 1.5 * R)):
        dx = (X - cx0 + a / 2.0) % a - a / 2.0
        dy = (Y - cy0 + 1.5 * R) % y_period - 1.5 * R
        # pointy-top hexagon: edge normals at 0, 60, 120 degrees
        d = np.maximum.reduce([np.abs(dx * np.cos(t) + dy * np.sin(t))
                               for t in (0.0, np.pi / 3, 2 * np.pi / 3)])
        dmin = d if dmin is None else np.minimum(dmin, d)
    edge = apo - dmin          # >0 inside nearest cell; ~0 on an edge
    w = 3.0                    # line half-width, px (tile space)
    core = np.exp(-(edge / w) ** 2)
    glow = np.exp(-(edge / (w * 4.0)) ** 2) * 0.25
    img = np.clip(core + glow, 0, 1) * 0.94 + 0.04
    rgb = np.clip(img, 0, 1)[:, :, None] * np.array(tint, dtype=np.float64)[None, None, :]
    return Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), 'RGB')


def band_texture():
    h = 256
    v = (np.arange(h) + 0.5) / h
    # soft gaussian band centred mid-tile, baked floor so the lattice stays visible between sweeps
    g = np.exp(-(np.abs(v - 0.5) / 0.12) ** 2)
    col = np.clip(BAND_FLOOR + (1.0 - BAND_FLOOR) * g, 0, 1)
    arr = np.tile((col * 255).astype(np.uint8)[:, None], (1, 16))
    return Image.fromarray(arr, 'L').convert('RGB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview', type=Path)
    args = ap.parse_args()
    band = band_texture()
    out = ROOT / 'Assets' / 'Textures'
    save_bc(band, out / 'cr_shieldfield_band.dds')
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        band.resize((64, 256)).save(args.preview / 'cr_shieldfield_band.png')
    for name, tint in TINTS.items():
        hexim = hex_texture(tint)
        save_bc(hexim, out / f'cr_shieldfield_hex_{name}.dds')
        if args.preview:
            t = Image.new('RGB', (SIZE * 2, SIZE * 2))
            for i in range(4):
                t.paste(hexim, ((i % 2) * SIZE, (i // 2) * SIZE))
            t.save(args.preview / f'cr_shieldfield_hex_{name}_2x2.png')


if __name__ == '__main__':
    main()
