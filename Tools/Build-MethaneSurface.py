#!/usr/bin/env python3
"""Generate the assets of the Titan liquid-methane surface (Docs/TITAN_WEATHER.md section 5).

    python -I Tools/Build-MethaneSurface.py            # write every asset
    python -I Tools/Build-MethaneSurface.py --check    # exit 1 if a checked-in asset differs

CRTitanWeather lays one flat sheet over a Titan map's methane sea through EXU
StaticGeometry and shades it with Materials/cr_methane.material
(Shaders/cr_methane.hlsl). This tool writes what that needs:

  Assets/ModelFixes/cr_methane_plane.mesh
      A unit sheet: a 16 x 16 grid over local x, z in [-0.5, 0.5] at y = 0, normal
      +y, u = x + 0.5 and v = z + 0.5. The director scales it to the terrain
      (width, 1, depth) and centres it on the map. POSITION / NORMAL / TEXCOORD0
      only, which is all the shader reads (D3D11 rejects a shader input the vertex
      data lacks). Ogre binary mesh, serializer v1.100, the layout stock Redux
      meshes use.

  Assets/Textures/cr_methane_ripple.png
      A tileable 256 x 256 ripple normal map (RGB = slope * 0.5 + 0.5 in x, y and the
      normal's z): a sum of sine waves on integer wave vectors, so it tiles exactly.

  Assets/Textures/cr_titan<NN>_wet.png
      The per-map wet mask, from the wet rows of Scripts/CRTitanSites<NN>.lua (the
      MAT/HG2 rule of Tools/Build-TitanSites.py, so the liquid sits exactly where the
      splashes and pools already do). Each 20-unit material cell becomes 2 x 2
      texels (512 x 512 for a 256-cell map), blurred (Gaussian, sigma 1 texel) so
      the shader's smoothstep draws a rounded shore instead of the cell grid. Row 0
      is the NORTH edge (largest z) and column 0 the west edge: the director's sheet
      is not mirrored, and Redux's render space mirrors z, so v runs south.

The mesh is written by the shared Ogre serializer (Tools/bzmodellibs.py: BZ98RBlenderToolKit and
numpy); the textures are pure Python (zlib, struct). CI runs --check with the pinned toolkit, not the game.
"""

from __future__ import annotations

import argparse
import io
import math
import random
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MESH_OUT = ROOT / "Assets" / "ModelFixes" / "cr_methane_plane.mesh"
RIPPLE_OUT = ROOT / "Assets" / "Textures" / "cr_methane_ripple.png"
MASK_MISSIONS = ("14", "15", "16")       # Each map uses its own MAT/HG2 wet mask.
GRID = 16
RIPPLE_SIZE = 256
MASK_UPSAMPLE = 2
MASK_SIGMA = 1.0


# ---------------------------------------------------------------------------------------
# PNG (8-bit RGB, filter 0) -- deterministic writer, and a reader for --check
# ---------------------------------------------------------------------------------------

def png_bytes(width: int, height: int, rows: list[bytes]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def png_pixels(data: bytes) -> tuple[int, int, bytes] | None:
    """(width, height, raw RGB rows) of a PNG this tool wrote (filter 0 only), else None."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour != 2:
                return None
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * 3 + 1
    if len(raw) != stride * height or any(raw[r * stride] != 0 for r in range(height)):
        return None
    return width, height, b"".join(raw[r * stride + 1:(r + 1) * stride] for r in range(height))


# ---------------------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------------------

def mesh_bytes() -> bytes:
    # Written by BZ98RBlenderToolKit's Ogre serializer (AGENTS.md, "Model tooling"), not by hand.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import numpy as np
    from bzmodellibs import ogremesh as om, ogremesh_serializer as oms

    n = GRID
    verts = np.zeros(((n + 1) * (n + 1), 8), dtype="<f4")
    for j in range(n + 1):
        for i in range(n + 1):
            u, v = i / n, j / n
            verts[j * (n + 1) + i] = (u - 0.5, 0.0, v - 0.5, 0.0, 1.0, 0.0, u, v)
    indices = []
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            b, c, d = a + 1, a + (n + 1), a + (n + 1) + 1
            # Counter-clockwise seen from +y (the material is two-sided anyway).
            indices += [a, c, b, b, c, d]

    mesh = om.Mesh()
    mesh.skeleton_name = None
    sub = mesh.create_submesh()
    sub.material_name = "CR/Titan/Methane"
    sub.index_count = len(indices)
    sub.set_index_buffer(np.array(indices, dtype="<u2").tobytes())
    data = sub.create_vertex_data(len(verts))
    for semantic_type, semantic, offset in ((om.VET.FLOAT3, om.VES.POSITION, 0),
                                            (om.VET.FLOAT3, om.VES.NORMAL, 12),
                                            (om.VET.FLOAT2, om.VES.TEXTURE_COORDINATES, 24)):
        data.vertex_declaration.create_vertex_element(0, semantic_type, semantic, offset, 0)
    data.create_vertex_buffer(verts.tobytes(), 0, 32)
    mesh.aabb = om.AxisAlignedBoundingBox(-0.5, -0.01, -0.5, 0.5, 0.01, 0.5)
    mesh.bound_radius = math.sqrt(0.5)
    out = io.BytesIO()
    oms.MeshSerializer(out).write(mesh)
    return out.getvalue()


# ---------------------------------------------------------------------------------------
# Ripple normal map
# ---------------------------------------------------------------------------------------

def ripple_rows() -> list[bytes]:
    rng = random.Random(14_0294)
    waves = []
    while len(waves) < 28:
        kx, ky = rng.randint(-14, 14), rng.randint(-14, 14)
        k = math.hypot(kx, ky)
        if k < 2.5 or k > 14.5:
            continue
        amp = 1.0 / (k ** 1.15)          # a gentle, mostly mid-frequency chop
        waves.append((kx, ky, amp, rng.uniform(0.0, 2.0 * math.pi)))
    size = RIPPLE_SIZE
    two_pi = 2.0 * math.pi
    slopes = []
    peak = 0.0
    for y in range(size):
        row = []
        for x in range(size):
            sx = sy = 0.0
            for kx, ky, amp, phase in waves:
                c = math.cos(two_pi * (kx * x + ky * y) / size + phase) * amp
                sx += c * kx
                sy += c * ky
            row.append((sx, sy))
            peak = max(peak, abs(sx), abs(sy))
        slopes.append(row)
    scale = 0.85 / peak                     # the steepest slope maps to 0.85
    rows = []
    for row in slopes:
        out = bytearray()
        for sx, sy in row:
            nx, ny = -sx * scale, -sy * scale
            nz = math.sqrt(max(0.0, 1.0 - min(1.0, nx * nx + ny * ny)))
            out += bytes(int(round((c * 0.5 + 0.5) * 255.0)) for c in (nx, ny, nz))
        rows.append(bytes(out))
    return rows


# ---------------------------------------------------------------------------------------
# Wet mask
# ---------------------------------------------------------------------------------------

def read_sites(path: Path) -> dict:
    text = path.read_text(encoding="ascii")
    sea = re.search(r"sea\s*=\s*\{(.*?)\n\s*\},", text, re.S)
    if not sea:
        raise ValueError(f"{path}: no sea table")
    fields = dict(re.findall(r"(\w+)\s*=\s*(-?[\d.]+)", sea.group(1)))
    wet_rows = {}
    block = re.search(r"wet\s*=\s*\{.*?rows\s*=\s*\{(.*?)\n\s*\},\s*\n\s*\},", text, re.S)
    if not block:
        raise ValueError(f"{path}: no wet rows")
    for row, runs in re.findall(r"\[(\d+)\]\s*=\s*\{([^}]*)\}", block.group(1)):
        values = [int(v) for v in runs.replace(" ", "").split(",") if v]
        wet_rows[int(row)] = list(zip(values[0::2], values[1::2]))
    return {"cols": int(fields["cols"]), "rows": int(fields["rows"]), "rowsData": wet_rows}


def gaussian_kernel(sigma: float) -> list[float]:
    radius = int(math.ceil(sigma * 3.0))
    weights = [math.exp(-(i * i) / (2.0 * sigma * sigma)) for i in range(-radius, radius + 1)]
    total = sum(weights)
    return [w / total for w in weights]


def mask_rows(sites: dict) -> tuple[int, list[bytes]]:
    cols, cells = sites["cols"], sites["rows"]
    up = MASK_UPSAMPLE
    size = cols * up
    if cells != cols:
        raise ValueError("non-square material grid")
    grid = [[0.0] * size for _ in range(size)]
    for r, runs in sites["rowsData"].items():
        y0 = (cells - 1 - r) * up            # row 0 of the image is the north edge
        for start, length in runs:
            for c in range(start, start + length):
                for dy in range(up):
                    row = grid[y0 + dy]
                    for dx in range(up):
                        row[c * up + dx] = 1.0
    kernel = gaussian_kernel(MASK_SIGMA)
    radius = len(kernel) // 2

    def blur_line(line: list[float]) -> list[float]:
        n = len(line)
        return [sum(kernel[k] * line[min(n - 1, max(0, i + k - radius))] for k in range(len(kernel)))
                for i in range(n)]

    grid = [blur_line(row) for row in grid]
    columns = [blur_line([grid[y][x] for y in range(size)]) for x in range(size)]
    rows = []
    for y in range(size):
        out = bytearray()
        for x in range(size):
            v = int(round(columns[x][y] * 255.0))
            out += bytes((v, v, v))
        rows.append(bytes(out))
    return size, rows


# ---------------------------------------------------------------------------------------

def outputs() -> dict[Path, bytes]:
    files = {MESH_OUT: mesh_bytes(), RIPPLE_OUT: png_bytes(RIPPLE_SIZE, RIPPLE_SIZE, ripple_rows())}
    for digits in MASK_MISSIONS:
        sites = read_sites(ROOT / "Scripts" / f"CRTitanSites{digits}.lua")
        size, rows = mask_rows(sites)
        files[ROOT / "Assets" / "Textures" / f"cr_titan{digits}_wet.png"] = png_bytes(size, size, rows)
    return files


def same(path: Path, expected: bytes) -> bool:
    if not path.is_file():
        return False
    current = path.read_bytes()
    if path.suffix == ".png":
        # Compare pixels, not bytes: zlib builds may compress differently.
        return png_pixels(current) == png_pixels(expected) and png_pixels(expected) is not None
    return current == expected


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="compare with the checked-in assets instead of writing")
    args = ap.parse_args()
    stale = 0
    for path, data in outputs().items():
        rel = path.relative_to(ROOT)
        if args.check:
            if same(path, data):
                print(f"{rel} is current")
            else:
                print(f"{rel} is stale; rerun Tools/Build-MethaneSurface.py", file=sys.stderr)
                stale += 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f"wrote {rel} ({len(data)} bytes)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
