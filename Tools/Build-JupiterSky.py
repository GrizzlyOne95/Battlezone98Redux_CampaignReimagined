"""Bake the textures for Io's sky: Jupiter (CRJOVIAN.MAP) and the other
Galilean moons (CREUROPA.MAP, CRGANYME.MAP, CRCALLIS.MAP).

Shaders/CR_jovian.hlsl draws each body as a sphere lit by the TRN sun, so it
needs the surface unlit, in plate carree (north up, the map's own longitude
origin at the left edge). The shader turns the sphere about its pole, so where
longitude 0 sits only changes which face is towards Io at the start.

  crsky_jupiter.png   RGB Jupiter's cloud tops
  crsky_europa.png    RGB Europa      (only with --europa)
  crsky_ganymede.png  RGB Ganymede    (only with --ganymede)
  crsky_callisto.png  RGB Callisto    (only with --callisto)

Sources (not stored in the repository):
  --map       PIA07782, Cassini's Best Maps of Jupiter (Cylindrical Map),
              NASA/JPL/Space Science Institute
              (photojournal.jpl.nasa.gov/catalog/PIA07782)
  --europa    Europa Voyager/Galileo SSI Global Mosaic 500m, 1024 px preview
  --ganymede  Ganymede Voyager-Galileo SSI Color Global Mosaic 1.4km, 1024 px
  --callisto  Callisto Galileo/Voyager Global Mosaic 1km, 1024 px preview
              all USGS Astrogeology Science Center (astrogeology.usgs.gov);
              see Docs/SKY_ART_CREDITS.md

Europa and Callisto have no public-domain colour mosaic, so their greyscale
maps are tinted: Europa's ice white with its rust-brown lineae and terrain,
Callisto a dusky grey-brown with bright crater ice. Each map's no-data areas
(black) are filled with the mean of the valid pixels in the same row.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
# Cassini's colour map is a little grey and blue next to Jupiter as the eye
# sees it: cream zones and tan-to-rust belts. Warm it and lift the saturation.
JUPITER_GAIN = (1.05, 1.0, 0.88)
JUPITER_SATURATION = 1.25
MOON_WIDTH = 512
# Greyscale moons: tint = lerp(dark, light, grey), applied to the grey.
MOON_TINTS = {
    "europa": ((1.10, 0.90, 0.74), (1.0, 0.99, 0.96)),
    "callisto": ((1.10, 0.96, 0.80), (1.0, 1.0, 1.0)),
}
NO_DATA = 6.0


def load(path, size):
    image = Image.open(path).convert("RGB")
    if image.size != size:
        image = image.resize(size, Image.LANCZOS)
    return np.asarray(image).astype(np.float32)


def fill_no_data(rgb):
    valid = rgb.max(axis=2) > NO_DATA
    mean = rgb[valid].mean(axis=0)
    for y in range(rgb.shape[0]):
        row = valid[y]
        fill = rgb[y][row].mean(axis=0) if row.sum() > rgb.shape[1] // 4 else mean
        rgb[y][~row] = fill
    return rgb


def tint(rgb, dark, light):
    grey = rgb.mean(axis=2, keepdims=True) / 255.0
    return rgb.mean(axis=2, keepdims=True) * (np.asarray(dark, np.float32) * (1 - grey) + np.asarray(light, np.float32) * grey)


def grade(rgb, gain, saturation):
    rgb = rgb * np.asarray(gain, np.float32)
    grey = rgb.mean(axis=2, keepdims=True)
    return grey + (rgb - grey) * saturation


def save(rgb, name, out):
    Image.fromarray(rgb.round().clip(0, 255).astype(np.uint8), "RGB").save(out / name, optimize=True)
    print(name, rgb.shape[1], "x", rgb.shape[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--europa", type=Path)
    parser.add_argument("--ganymede", type=Path)
    parser.add_argument("--callisto", type=Path)
    parser.add_argument("--width", type=int, default=2048)
    parser.add_argument("--out", type=Path, default=ROOT / "Assets/Textures")
    args = parser.parse_args()
    Image.MAX_IMAGE_PIXELS = None

    jupiter = load(args.map, (args.width, args.width // 2))
    save(grade(jupiter, JUPITER_GAIN, JUPITER_SATURATION), "crsky_jupiter.png", args.out)
    for name in ("europa", "ganymede", "callisto"):
        path = getattr(args, name)
        if path:
            moon = fill_no_data(load(path, (MOON_WIDTH, MOON_WIDTH // 2)))
            if name in MOON_TINTS:
                moon = tint(moon, *MOON_TINTS[name])
            save(moon, "crsky_%s.png" % name, args.out)


if __name__ == "__main__":
    main()
