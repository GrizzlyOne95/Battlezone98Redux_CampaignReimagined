"""Write Assets/Textures/cr_leaf.png, the sprite for the CR/LeafLitter particles.

A single pale leaf: pointed oval, darker midrib and side veins, soft alpha edge.
It is near-white on purpose: the particle colour (the emitter's green-to-brown
colour range) tints it, so one sprite covers fresh and dead leaves.

Usage: python Tools/Build-LeafTexture.py
"""
import math
from pathlib import Path

from PIL import Image

SIZE = 64
TARGET = Path(__file__).resolve().parent.parent / "Assets" / "Textures" / "cr_leaf.png"


def leaf_pixel(u, v):
    # u along the leaf (-1 stem .. 1 tip), v across it; the leaf is turned 35
    # degrees so a billboard's spin reads as tumbling rather than wiping.
    half_width = 0.42 * math.sin(math.pi * (u + 1.0) / 2.0) ** 0.8 if -1.0 < u < 1.0 else 0.0
    if half_width <= 0.0:
        return None
    edge = abs(v) / half_width
    if edge > 1.0:
        return None
    alpha = min(1.0, (1.0 - edge) * 6.0)
    shade = 0.82 + 0.18 * (1.0 - edge)
    if abs(v) < 0.035:
        shade *= 0.72                                   # midrib
    vein = math.fmod(u * 5.0 + abs(v) * 7.0 + 10.0, 1.0)
    if vein < 0.08 and edge < 0.85:
        shade *= 0.85                                   # side veins
    return shade, alpha


def main():
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    angle = math.radians(35.0)
    c, s = math.cos(angle), math.sin(angle)
    for y in range(SIZE):
        for x in range(SIZE):
            px = (x + 0.5) / SIZE * 2.0 - 1.0
            py = (y + 0.5) / SIZE * 2.0 - 1.0
            u = (px * c + py * s) / 0.9
            v = (-px * s + py * c) / 0.9
            hit = leaf_pixel(u, v)
            if hit is None:
                continue
            shade, alpha = hit
            # Faint yellow-green so an untinted particle still reads as a leaf.
            pixels[x, y] = (round(235 * shade), round(245 * shade), round(215 * shade), round(255 * alpha))
    image.save(TARGET)
    print(f"wrote {TARGET.name}")


if __name__ == "__main__":
    main()
