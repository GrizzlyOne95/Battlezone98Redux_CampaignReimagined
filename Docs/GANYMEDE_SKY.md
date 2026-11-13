# Ganymede sky

Ganymede is the ice-and-rock world of the Black Dog and Chinese campaigns of the Jupiter system: airless, so a black sky, no
cloud and almost no fog, with Jupiter huge overhead. It is Europa's sky (`Docs/EUROPA_WEATHER.md`) one moon
further out.

## What draws it

- `CR_Sky/GanymedeStars` (`Materials/cr_catalogsky.material`), a catalog star box named for Ganymede so
  `Scripts/CRWorldArt.lua` can write the world's orbit pole and sun into it without touching Io's or
  Europa's. `Art.StarBoxes.ganymede` hides `STARS.MAP`; the TRN's sun sprite is dropped (`SunTexture=`).
- Jupiter and the other Galilean moons are the existing `CR_jovian` bodies (`Materials/cr_jovian.material`,
  `Shaders/CR_jovian.hlsl`) on TRN `[Stars]` quads at `Radius = 1000`: `crjovian.map`, then `crio.map`,
  `creuropa.map` and `crcallis.map`. The textures are the ones Io and Europa already use
  (`crsky_jupiter.png`, `crsky_io.png`, `crsky_europa.png`, `crsky_callisto.png`, baked by
  `Tools/TexturesAndSky/Build-JupiterSky.py`; nothing new is generated, see `Docs/SKY_ART_CREDITS.md`).
- The TRNs: `bdmisn01` to `06`, `08`, `12` to `15` and `chmisn01` to `04`, `08`. The Elysium and Europa maps
  are not touched.
- The light is Environment's `orbit` mode, which the Ganymede missions already select
  (`{ lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } }`): the sun's real path, a short
  eclipse behind Jupiter, and Jupiter-shine at night.

## Jupiter's size

Jupiter's equatorial radius is 71,492 km and Ganymede orbits at 1,070,400 km, so Jupiter's angular radius is
`asin(71492 / 1070400)` = 3.83 degrees, 7.66 degrees across: 0.63 times Europa's 12.2 and 0.40 times Io's.
`Art.Orbits.ganymede.radius` holds it (the eclipse, about 2 % of the day, follows from it). A body quad shows its
disc over 0.86 of the UV square, so `Size = 2 * 1000 * tan(radius / 0.86)` = 156 at `Radius = 1000`; the
tests check every Ganymede TRN against that. Jupiter turns 16.3 times in a Ganymede day (synodic 10.53 h in
171.7 h) and `Art.Shine.ganymede` is a weak, warm 0.16 night light (Io 0.36, Europa 0.22).

## The moons

Following `Docs/EUROPA_WEATHER.md`, the moons are drawn at three times their true size so they read as discs
at 4K. They sit on Jupiter's equatorial plane (within 1.5 degrees) at plausible separations, at the
elongations and distances below, which the Ganymede TRNs fix (Jupiter is heading 180, 25 degrees up):

| Body | Heading | Elevation | Distance assumed | `Size` |
| --- | --- | --- | --- | --- |
| Io | 164.6 | 24.2 | 700,000 km | 18 |
| Europa | 213.5 | 21.2 | 750,000 km | 15 |
| Callisto | 115.7 | 11.4 | 1,000,000 km | 17 |

Io's separation from Jupiter is 14 degrees (its greatest elongation from Ganymede is 23.2) and Europa's 31 (38.8).
The moons' positions do not move with the orbit; only their phases do.

## Fog and weather

Black sky, no cloud, minimal fog: the TRNs keep `FogStart = 175`, `FogEnd = 250`, and the Europa presets
(`CREuropaWeather`, reused for Ganymede) carry a faint cold frost haze and no ambient or diffuse of their own, so
the light is the orbit's. The frost haze and vents are unchanged.

OpenGL has no GLSL twin for `CR_jovian`, so it draws no bodies (technique 1 is invisible); the star box
itself is the shared one.
