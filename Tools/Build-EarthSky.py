"""Bake the textures for the Moon's phase-lit Earth (CREARTH.MAP).

Shaders/CR_earth.hlsl draws the Earth as a sphere lit by the TRN sun, so it
needs the planet unlit, in plate carree (longitude -180 at the left edge,
north up), not the stock earth.dds disc with its terminator painted in.

  crsky_earth.png        RGB the surface by day, A cloud cover
  crsky_earth_night.png  R city lights, G ocean mask (for the sun glint)

Sources (not stored in the repository), all NASA Earth Observatory:
  --day     Blue Marble Next Generation, world.topo.bathy.200412.3x5400x2700.jpg
            (eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/)
  --clouds  cloud_combined_2048.jpg
            (eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/)
  --night   Black Marble 2016, BlackMarble_2016_01deg.jpg
            (eoimages.gsfc.nasa.gov/images/imagerecords/144000/144898/)
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
# Black Marble draws unlit land a dim blue-grey; lights are white to amber, so
# red over blue picks them out and red alone sets their brightness.
LIGHTS_WARMTH = (-4.0, 40.0)
LIGHTS_LEVEL = (25.0, 175.0)
# Blue Marble's sea is blue over its bathymetry shading; ice is white, so
# blue over red by this much is water.
OCEAN_EDGE = (4.0, 14.0)


def load(path, size, mode="RGB"):
    image = Image.open(path).convert(mode)
    if image.size != size:
        image = image.resize(size, Image.LANCZOS)
    return np.asarray(image).astype(np.float32)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--day", type=Path, required=True)
    parser.add_argument("--clouds", type=Path, required=True)
    parser.add_argument("--night", type=Path, required=True)
    parser.add_argument("--width", type=int, default=2048)
    parser.add_argument("--night-width", type=int, default=1024)
    parser.add_argument("--out", type=Path, default=ROOT / "Assets/Textures")
    args = parser.parse_args()
    Image.MAX_IMAGE_PIXELS = None

    size = (args.width, args.width // 2)
    day = load(args.day, size)
    clouds = load(args.clouds, size, "L")
    earth = np.dstack([day, clouds]).round().clip(0, 255).astype(np.uint8)
    Image.fromarray(earth, "RGBA").save(args.out / "crsky_earth.png", optimize=True)

    night_size = (args.night_width, args.night_width // 2)
    night = load(args.night, night_size)
    red, blue = night[..., 0], night[..., 2]
    lights = smoothstep(*LIGHTS_WARMTH, red - blue) * np.clip((red - LIGHTS_LEVEL[0]) / LIGHTS_LEVEL[1], 0.0, 1.0)
    small = load(args.day, night_size)
    ocean = smoothstep(*OCEAN_EDGE, small[..., 2] - small[..., 0])
    packed = np.dstack([lights * 255.0, ocean * 255.0, np.zeros_like(ocean)])
    Image.fromarray(packed.round().astype(np.uint8), "RGB").save(args.out / "crsky_earth_night.png", optimize=True)
    print("crsky_earth.png", size, "crsky_earth_night.png", night_size)


if __name__ == "__main__":
    main()
