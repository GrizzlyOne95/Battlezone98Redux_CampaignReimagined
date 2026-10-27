# Achilles sky (CRSKYAC.MAP)

Achilles is Battlezone's fictional moon of Uranus: a small, cold, wooded world with a breathable blue sky,
rain off the forest and Uranus hanging huge overhead. There is no real Achilles to match, so the sky follows
what the game tells us (the TRNs, the stock `achilles.tga` dome, the `acloud` sprites and the `uranus.map`
quad) and is otherwise free to be cinematic.

## What draws it

- `Materials/crart_achilles.material`: technique 0 is `CR_AchillesSky` (DX11 and DX9); technique 1 keeps the
  stock `achilles.tga` dome through `CR_SkyDome` for OpenGL.
- `Shaders/CR_achillessky.hlsl` and `.program`: one HLSL source for SM4 and SM3. The program names are
  versioned by `Tools/Update-WorldSkyProgramVersions.py`.
- `Assets/Textures/crsky_achilles_clouds.png`, `crsky_uranus.png`, `crsky_uranus_rings.png`: baked by
  `Tools/Build-AchillesSky.py` (see `Docs/SKY_ART_CREDITS.md`).
- `Scripts/CRWorldArt.lua`: `Art.SkyFrames.achilles`, a weather and body dome, writes the frame every update:
  specular = (Enhanced flag, sun direction), emissive = (night, clarity, storm, rain),
  diffuse = (lightning direction, flash), ambient = (direction toward Uranus, 1).
  The dome hides `ACLOUD2.MAP`, `ACLOUD.MAP` and `URANUS.MAP`, which it draws itself;
  `Art.RestoreSkySprites` gives them back (`acloud2.tga`, `acloud.tga`, `uranus.dds`) while a mission hides it.
- `misn17.trn` and `misn18.trn` leave `SunTexture` empty: the dome draws the sun disc, and the engine's sprite
  would never follow a night `skySun`.

The look, coloured from the composed fog so the horizon always meets the terrain fog:

- a gradient from the fog at the horizon to a deeper blue overhead, and a small sun disc with a glow;
- scattered fair-weather cumulus that the storm grows into a closed, dark deck, with lit tops, grey bases and
  silver edges round the sun (and round Uranus at night);
- rain that flattens the sky into murk and hangs curtains on the horizon;
- lightning that lights the deck from inside, round the strike;
- from storm 0.8 up, the overloaded core lighting the cloud base red from below;
- Uranus where the TRN puts it (`[Stars]` heading 210, 30 degrees up, `Size00 = 450` at `Radius = 1000`): a
  pale cyan, faintly banded globe with a bright polar cap, lit by the sun with real phases, its narrow rings
  (epsilon brightest, the dusty nu and mu rings faint red and blue) and the globe's shadow on the rings. It
  shows where the cloud breaks and vanishes in rain, so a clearing reveals it.

## Cinematic licences

- **Uranus's size comes from the TRN.** 450 at radius 1000 is about 25 degrees across, which puts Achilles
  4.55 Uranus radii out: just beyond the mu ring, between Mab and Miranda. No real moon orbits there.
- **The rings are opened.** Uranus lies on its side and its moons orbit in the ring plane, so from Achilles the
  real rings would be a line. They are opened 0.20 rad (`uranusShape.z`; 0 gives the true view) and the pole
  is rolled 1.30 rad from straight up (`uranusShape.w`), so the rings stand nearly upright.
- **Uranus lights the night.** The real planet gets a 360th of Earth's sunlight. `CRWorldArt.Shine.achilles`
  gives it a cyan light of 0.24 at night and a faint tint by day, with a small bounce.
- **The core glows red.** The tempest's red cloud base has no source in the stock sky; it ties the sky to the
  converter overload and to misn18's red swirl.

## misn17: the jungle storm

`CRJungle17` publishes `J.SkyState()`, and `Environment.BindWeatherSensors` makes the director the dome's
weather source (`Environment.SkyWeatherSource`). While the CR dome owns the sky, the `CR17/StormCloud` sky plane
stays down (`Describe().clouds == "dome"`) and the dome draws the storm itself:

- `storm` eases toward level / 4 (time constant 8 s) and `bank` toward the rain intensity (5 s; 0 at level 0),
  starting at the current level after a load or a late join;
- each `bolt` packet lights the dome toward a bearing taken from the shared bolt age (18 degrees up), so every
  peer sees the strike in the same part of the sky, twice in quick succession like a return stroke.

On OpenGL the fallback dome draws no storm, and the deck stays down while the CR dome owns the sky, so OpenGL
loses the misn17 storm deck.

## misn18: night, then the swirl

misn18 opens at night: `Environment.Init({ nativeBaseline = true, lightingMode = "night", nightGameplay = false,
skySun = { azimuth = 55, elevation = -28 } })`. The sun is down behind the moon, Uranus is gibbous and is the
scene's cyan light. Sensors keep their day ranges, and the weather presets dim to 0.2 at night.

`CRStorm18` keeps the CR dome for opening, search and found (`TUNING.DOME_PHASES = 3`), so Uranus shows through
the gathering cloud before the storm gets worse. `S.SkyState()` returns `storm = level / 0.47` (`DOME_STORM`:
the found level closes the cloud and starts the red glow), `bank = level / 2`, and the flash toward the strike
(a seeded bearing for cloud flashes). At core1 the `CR18/StormSwirl` deck tears in: the director hides the dome
and calls `Environment.SetArtSkyVisible(false)` to give the stock sprites back, and `S.SkyState()` returns nil.
`Stop` restores the dome and hides the sprites again.

## Tests

- `Tools/Test-CRWorldArt.lua`: the Achilles frame (storm, rain, flash, Uranus direction), the hide and restore
  lists, and Uranus's night light.
- `Tools/Test-Misn17Jungle.lua`: the deck skip, `J.SkyState` easing and the shared bolt bearing.
- `Tools/Test-CRStorm18.lua`: the dome phases, the dome's lightning, the core1 hand-over and `Stop`.
- `Tools/Test-Misn18Coop.lua`: every peer opens misn18 at night with day sensors.
