#!/usr/bin/env python3
"""Build the tileable RGBA scorch map used by CR_BZBaseCockpit's mesh pass.

The texture's RGB carries charcoal and singe colour. Its alpha describes where
the soot lies; CRSurfaceEffects controls overall opacity from player hull health.
Only the F1 cockpit material clones receive a nonzero alpha.
"""
from __future__ import annotations

import random
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Assets" / "Textures" / "cr_cockpit_charred.png"
SIZE = 512
LAYERS = ((8, 0.38), (16, 0.27), (32, 0.18), (64, 0.11), (128, 0.06))


def ease(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def sample(grid: list[list[float]], cells: int, x: int, y: int) -> float:
    gx = x * cells / SIZE
    gy = y * cells / SIZE
    ix, iy = int(gx), int(gy)
    fx, fy = ease(gx - ix), ease(gy - iy)
    x0, x1 = ix % cells, (ix + 1) % cells
    y0, y1 = iy % cells, (iy + 1) % cells
    a = grid[y0][x0] * (1.0 - fx) + grid[y0][x1] * fx
    b = grid[y1][x0] * (1.0 - fx) + grid[y1][x1] * fx
    return a * (1.0 - fy) + b * fy


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    return ease((value - edge0) / (edge1 - edge0))


def chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def build_png() -> bytes:
    rng = random.Random(20261110)
    grids = {
        cells: [[rng.random() for _ in range(cells)] for _ in range(cells)]
        for cells, _ in LAYERS
    }
    weights = tuple(weight for _, weight in LAYERS)
    total_weight = sum(weights)
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)  # PNG filter: None
        for x in range(SIZE):
            n = sum(
                weight * sample(grids[cells], cells, x, y)
                for (cells, weight) in LAYERS
            ) / total_weight

            # Irregular soot islands with soft singed rims and darker centres.
            coverage = smoothstep(0.525, 0.675, n)
            core = smoothstep(0.575, 0.705, n)
            rim = smoothstep(0.525, 0.565, n) * (1.0 - smoothstep(0.625, 0.675, n))
            grain = sample(grids[128], 128, x, y) - 0.5
            char = (22 + 12 * grain, 19 + 9 * grain, 18 + 8 * grain)
            burnt = (68 + 28 * grain, 31 + 15 * grain, 18 + 10 * grain)
            # A restrained rusty edge reads as heat staining without looking emissive.
            edge = min(1.0, rim * 0.36)
            rgb = tuple(
                max(0, min(255, round(
                    (burnt[i] * (1.0 - core) + char[i] * core) * (1.0 - edge)
                    + (96, 39, 20)[i] * edge
                )))
                for i in range(3)
            )
            raw.extend((*rgb, round(255 * coverage)))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # RGBA, 8 bits/channel
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(build_png())
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({SIZE}x{SIZE}, tileable RGBA)")


if __name__ == "__main__":
    main()
