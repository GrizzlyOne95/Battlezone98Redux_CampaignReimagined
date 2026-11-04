# Elysium sky (CRSKYEL.MAP)

Elysium is the Black Dog world of the Chthonian ruins. The stock description (`elysium.des`) says volcanic
rock, -194 C and gravity 0.7; CR reads it as a dead, apocalyptic Earth-like world with a thin remnant
atmosphere. The sky is a cold, bruised violet-grey, never a saturated purple. There is no real Elysium to
match, so the look follows the TRNs and the stock `elysium.tga` dome and is otherwise free.

## What draws it

- `Materials/crart_elysium.material`: technique 0 is `CR_ElysiumSky` (DX11 and DX9); technique 1 keeps the
  stock `elysium.tga` dome through `CR_SkyDome` for OpenGL.
- `Shaders/CR_elysiumsky.hlsl` and `.program`: one HLSL source for SM4 and SM3. The program names are
  versioned by `Tools/Update-WorldSkyProgramVersions.py`.
- `Assets/Textures/crsky_elysium_clouds.png`: baked by `Tools/Build-ElysiumSky.py` (R torn high cloud, rank
  normalised; G dust and ash veils; B fine breakup, sampled twice, the second tap 11.3x finer so cloud edges fray below one
  texel). Every channel is rolled off well above texel scale, or the threshold shows stair steps where the
  dome magnifies the map overhead. Procedural, no third-party source
  (`Docs/SKY_ART_CREDITS.md`).
- `Scripts/CRWorldArt.lua`: `Art.SkyFrames.elysium`, a weather dome with no body, writes the frame every
  update: specular = (Enhanced flag, sun direction), emissive = (night, clarity, storm, dust front),
  diffuse = (lightning direction, flash). It hides `ACLOUD2.MAP` and `ACLOUD.MAP`, which it draws itself.
- `bdmisn07.trn` leaves `SunTexture` empty (bdmisn09 to 11, chmisn05 and chmisn06 already do): the dome draws the sun disc.

The look, coloured from the composed fog so the horizon always meets the terrain fog:

- a gradient from the cool grey-violet fog at the horizon to a bruised violet-grey overhead
  (`zenithTint 0.46 0.40 0.54`, a fixed hue scaled to the fog's brightness, so it stays desaturated);
- thin, torn high cloud, mostly open sky (32 % cover when calm, 85 % in a storm), racing with the wind;
- dust and ash veils with a warm-grey cast, thicker in a front;
- a small pale sun disc (radius 0.0075 rad, about 0.43 degrees) with a little glow, hidden by cloud, storm,
  dust front and night;
- a few faint stars at the zenith by day and the whole sky after dark (hash stars, no catalog);
- storms darken the sky and close the cloud; dry lightning lights the cloud from inside, round the strike;
  a dust front flattens the sky into murk.

## Fog

The TRNs keep `FogStart = 80`, `FogEnd = 250` (bdmisn07, 09 to 11; chmisn05 and chmisn06 take the same dome). The calm preset fog is `0.60 / 0.61 / 0.68`,
a cold grey-violet, and each rung darkens it toward `0.22 / 0.23 / 0.30` with the same hue.
`Docs/ELYSIUM_WEATHER.md` has the ladder.

## OpenGL

The unified programs have no GLSL delegate, so OpenGL keeps the stock dome and loses the clouds, stars and
lightning glow.
