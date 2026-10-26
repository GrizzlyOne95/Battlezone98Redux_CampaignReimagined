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

## Mars sky (CRSKYMA.MAP)

- `Assets/Textures/crsky_mars_clouds.png` is original, procedural art: `Tools/Build-MarsSkyClouds.py`
  synthesises it from seeded spectral noise (R water-ice cirrus, G dust veils, B breakup), so it
  tiles exactly and can be rebaked at any size. No third-party source.
- `Shaders/CR_marssky.hlsl` draws the dome from it, coloured from the composed fog: a darker
  zenith, the aureole (blue round a low sun, as Mars sunsets are), a small sun disc, and at night
  the catalog stars and Milky Way above (credited under "Catalog star sky").
  `Scripts/CRWorldArt.lua` feeds it the Environment sun direction, night blend and weather
  clarity, and hides the TRN's stock `ACLOUD`/`ACLOUD2` sprites. OpenGL keeps the stock
  `mars.tga` dome (technique 1).

## Venus sky (CRSKYVE.MAP)

- `Assets/Textures/crsky_venus_clouds.png` is original, procedural art: `Tools/Build-VenusSkyClouds.py`
  synthesises it from seeded spectral noise (R long warped cloud bands, G billowed convective
  cells, B breakup), so it tiles exactly and can be rebaked at any size. No third-party source.
- `Shaders/CR_venussky.hlsl` draws the underside of the cloud deck from it, coloured from the
  composed fog: a brighter, yellower deck overhead, fast-drifting bands and cells, a sun glow
  with no disc, a storm that darkens and greens the deck and adds scud, lightning that lights
  the deck round the strike, and fog banks that flatten it all into bright murk.
  `Scripts/CRWorldArt.lua` feeds it the sun, night blend, clarity and `CRVenusWeather`'s sky
  state. OpenGL keeps the stock `venus.tga` dome (technique 1).

## Earth over the Moon (CREARTH.MAP)

Imagery: NASA Earth Observatory. NASA imagery is generally not copyrighted (public domain);
credit is given as the pages request.

- Surface: Blue Marble Next Generation, December 2004, `world.topo.bathy.200412.3x5400x2700.jpg`
  (Reto Stockli, NASA Earth Observatory),
  <https://earthobservatory.nasa.gov/images/73909>.
- Clouds: `cloud_combined_2048.jpg`, <https://earthobservatory.nasa.gov/images/57747>.
- City lights: Black Marble 2016, `BlackMarble_2016_01deg.jpg` (Suomi NPP VIIRS),
  <https://earthobservatory.nasa.gov/images/144898>.
- Used as: `Assets/Textures/crsky_earth.png` (2048x1024; RGB the surface, A the clouds) and
  `Assets/Textures/crsky_earth_night.png` (1024x512; R city lights picked out of Black Marble
  by warmth, G an ocean mask from Blue Marble's sea colour), baked by `Tools/Build-EarthSky.py`.
  `Shaders/CR_earth.hlsl` draws them as a sphere on the TRN's `[Stars]` Earth quad, lit from the
  TRN sun (`Scripts/CRWorldArt.lua`) so the phase is the one seen from the Moon.
  OpenGL keeps the stock `earth.dds` (technique 1).
- None of the source files is stored in the repository.

## Jupiter and the Galilean moons over Io and Europa (CRJOVIAN.MAP, CRIO.MAP, CREUROPA.MAP, CRGANYME.MAP, CRCALLIS.MAP)

Imagery: NASA/JPL and the USGS Astrogeology Science Center. NASA and USGS imagery is generally
not copyrighted (public domain); credit is given as the pages request.

- Jupiter: PIA07782, "Cassini's Best Maps of Jupiter" (cylindrical map),
  NASA/JPL/Space Science Institute, <https://photojournal.jpl.nasa.gov/catalog/PIA07782>.
- Io: "Io Galileo SSI / Voyager Color Merged Global Mosaic 1km", USGS Astrogeology Science Center,
  <https://astrogeology.usgs.gov/search/map/io_galileo_ssi_voyager_color_merged_global_mosaic_1km>
  (the 1024 px preview).
- Europa: "Europa Voyager/Galileo SSI Global Mosaic 500m", USGS Astrogeology Science Center
  (T. Becker, 2010), <https://astrogeology.usgs.gov/search/map/europa_voyager_galileo_ssi_global_mosaic_500m>.
- Ganymede: "Ganymede Voyager-Galileo SSI Color Global Mosaic 1.4km", USGS Astrogeology Science
  Center, <https://astrogeology.usgs.gov/search/map/ganymede_voyager_galileo_ssi_color_global_mosaic_1_4km>.
- Callisto: "Callisto Galileo/Voyager Global Mosaic 1km", USGS Astrogeology Science Center,
  <https://astrogeology.usgs.gov/search/map/callisto_galileo_voyager_global_mosaic_1km>.
- Used as: `Assets/Textures/crsky_jupiter.png` (2048x1024, warmed and a little more saturated,
  closer to Jupiter as the eye sees it) and `crsky_io.png`, `crsky_europa.png`, `crsky_ganymede.png`,
  `crsky_callisto.png` (512x256), baked by `Tools/Build-JupiterSky.py`. Io's mosaic is false colour
  from violet, green and near-infrared filters, so it is graded toward Io's pale yellow and ochre. Europa and Callisto have
  no public-domain colour mosaic, so their greyscale mosaics are tinted (Europa's ice white with
  rust-brown terrain, Callisto a dusky grey-brown); missing-data areas are filled from the row.
- `Shaders/CR_jovian.hlsl` draws each one as a sphere on its TRN `[Stars]` quad (Io: misn10,
  misn11; Europa: misn12, misn13), lit from the orbit's sun so every phase is the one seen from
  that moon: Minnaert limb darkening, a
  thin haze at Jupiter's limb that brightens as the sun goes behind it, and while it is behind,
  a red ring of sunlight bent through Jupiter's upper air. Jupiter turns with the orbit.
  `Scripts/CRWorldArt.lua` and Environment's `orbit` lighting mode drive it; the catalog star box
  (`CR_Sky/IoStars`, `CR_Sky/EuropaStars`) turns its stars with the same sun and hides its sun
  disc in eclipse.
  OpenGL has no GLSL twin yet and draws no bodies (technique 1 is invisible).
- None of the source files is stored in the repository.
