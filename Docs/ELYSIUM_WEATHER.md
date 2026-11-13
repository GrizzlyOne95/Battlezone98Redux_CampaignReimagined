# Elysium weather

`Scripts/CRElysiumWeather.lua` is CRVenusWeather's engine (seeded severity ladder, strikes, cloud deck, fog
banks, co-op wire protocol) dressed for Elysium. Init swaps in the Elysium values and switches the sulphur and
volcano layers off; Shutdown puts the Venus values back. The module inherits every other function. It drives
bdmisn07, 09, 10 and 11 and the Chinese campaign's chmisn05 and chmisn06 through `Scripts/CRCCARuntime.lua` (`weather = { module = "CRElysiumWeather", ... }`).

Elysium is a dead, Earth-like world with a thin remnant atmosphere (see `Docs/ELYSIUM_SKY.md`). Its weather is
wind, dust and ash, dry-lightning fronts and ground mist in the ruins. There is little rain.

| Rung | Preset | Wind | Strikes/min | Rain | Fog (rgb, start, end) |
| --- | --- | --- | --- | --- | --- |
| 1 | ElysiumCalm | 4 | 0 | 0 | 0.60 0.61 0.68, 80, 250 |
| 2 | ElysiumHaze | 7 | 0 | 0 | 0.52 0.53 0.60, 72, 215 |
| 3 | ElysiumRising | 11 | 3 | 0.08 | 0.42 0.43 0.50, 60, 180 |
| 4 | ElysiumStorm | 16 | 7 | 0.22 | 0.32 0.33 0.40, 45, 140 |
| 5 | ElysiumSevere | 22 | 12 | 0.45 | 0.22 0.23 0.30, 32, 100 |

- **Wind and dust.** The wind is stronger than before and drifts the mist. The dust front (the engine's fog
  bank) is a warm grey-violet murk with a haze at the ground, and it flattens the CR dome the same way.
- **Dry lightning.** The strike rate rises (rung 3: 1.5 to 3, rung 4: 5 to 7 a minute) while rain falls to a trace, so most
  fronts are dry: a flash, thunder and the scene flash, no downpour. The flash colour is a cold white-violet.
- **Rain.** Light and ash-grey: `RainMaxRate` 210 (Venus 520), `RainSplashRate` 20, tint `0.62 / 0.60 / 0.64`.
  Only the severe rung is above 0.25.
- **Ground mist.** The `CR/Elysium/FogPool` sheets fill the low basins and the ruins with grey-violet mist
  (`Materials/cr_elysium.particle.payload`).
- **Sky.** The dome (`CR_elysiumsky`) takes the storm, dust front and flash through `V.SkyState()`: it closes
  its cloud, darkens and lights the flash round the strike.

Sensors, damage and net ops are the Venus ones, unchanged: visual only, with the radar and veloc-jam scales of
`LEVEL_FIELDS` through Environment. Tests: `lua5.1 Tools/TexturesAndSky/Test-CRElysiumWeather.lua Scripts`,
`Tools/TexturesAndSky/Test-AtmosphereIntegration.lua` (dome feed) and `Tools/TexturesAndSky/Test-CRWorldArt.lua`.
