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
