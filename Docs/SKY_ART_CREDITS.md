# Sky art credits

## Uranus (misn17, misn18)

Uranus image: NASA/JPL-Caltech (Voyager 2, PIA18182)

- Source: NASA Photojournal PIA18182, "Uranus as seen by NASA's Voyager 2",
  <https://photojournal.jpl.nasa.gov/catalog/PIA18182>. NASA/JPL-Caltech imagery is
  generally not copyrighted (public domain); credit is given as requested.
- Used as: `Assets/Textures/uranus.dds`, selected by `Materials/uranus.material`
  (`URANUS.MAP`) and placed by the `[Stars]` section of `Missions/misn17.trn` and
  `Missions/misn18.trn`.
- Processing: cropped to the disc with a small margin, alpha derived from the black
  background with a soft limb, resized from 1720x1720 to 1024x1024, written as uncompressed
  BGRA DDS with an 11-level mip chain; limb colour edge-extended so alpha blending does not pull in black. No colour correction (the Voyager colour is already pale cyan).
- In game the disc is seen through the overcast: `Materials/uranus.material` uses `CR_SkyHaze_fragment` (`Shaders/CR_sky.program`) to thin it (opacity 0.5), tint it toward the fog colour and fade it with a drifting mask from `acloud2.tga`'s alpha.
- The source TIFF is not stored in the repository.

## Catalog star sky (Moon)

Star positions, magnitudes and spectral types: the Yale Bright Star Catalogue, 5th revised
edition (Hoffleit and Warren, 1991), binary distribution from the Harvard/Smithsonian
Telescope Data Center, <http://tdc-www.harvard.edu/catalogs/bsc5.html>.

- Used as: `Assets/Textures/crsky_stars.png`, a star index baked by `Tools/Build-CatalogSky.py --bsc5`
  (9096 stars to magnitude 8, B-V estimated from the spectral class) and drawn by
  `Shaders/CR_catalogsky*.hlsl`/`.glsl` through `Materials/cr_catalogsky.material`.

Milky Way background: NASA/Goddard Space Flight Center Scientific Visualization Studio.
Gaia DR2: ESA/Gaia/DPAC.

- Source: SVS 4851, "Deep Star Maps 2020", `milkyway_2020_4k.exr` (celestial coordinates,
  plate carree, RA 0h at the centre increasing to the left, bright Hipparcos/Tycho stars omitted),
  <https://svs.gsfc.nasa.gov/4851>. Credit given as the page requests.
- Used as: `Assets/Textures/crsky_milkyway.png`: box-filtered to 2048x1024, sRGB-encoded at
  exposure 1 by `Tools/Build-CatalogSky.py --milkyway` after converting the EXR to a float
  `.npy` (Blender's bundled Python reads EXR). The material's `milkyParams` (-1, 0.5) encode
  the map's RA direction and origin.
- Neither source file is stored in the repository.
