# Venus dense atmosphere prototype

`VenusDenseAtmosphere` is a development-only CRWeather preset inspired by the
stock `venusimg.png`: opaque olive-yellow distance extinction, muted local
contrast, a bright yellow-white sun, and a subtle low moving veil.

The effect deliberately gets its density from native linear fog. It creates one
camera-local `EXU/WeatherMist` system and does not add a CR ground-haze template,
compositor fog, volumetrics, soft particles, weather scheduling, or renderer
hooks.

## Runtime budget

At `CRWeather.Quality = 1` and intensity `1`:

| Layer | Template | Quota | Emission | Expected live population |
| --- | --- | ---: | ---: | ---: |
| camera-local veil | `EXU/WeatherMist` | 72 | 6 cards/s | about 45 (5-10 s lifetime) |

Intensity scales emission, ColourInterpolator alpha, Scaler rate, fog, ambient,
sun diffuse, and sun power from the same `0..1` value. At intensity `0.5`, for
example, mist emits at `3/s` and the primary alpha stop is `0.055`.

## Live lcbench controls

Deploy `Tools/lcbench-venus.lua` as `addon/lcbench/lcbench.lua`. It initializes
`Environment` first and then `CRWeather`, so all fog and lighting still flow
through the existing Environment modifier path.

| Key | Action |
| --- | --- |
| `F1` / `F2` | previous / next tuning control |
| Left / Right | decrease / increase selected value |
| Shift + Left / Right | five-times step |
| `F3` | transition between Venus weather and clear |
| Home | restore authored defaults |
| `F4` | print all current values to the game log |

The selectable values are intensity, fog RGB, fog start/end, mist emission,
mist alpha, mist scale rate, wind bearing, and wind speed. The current control
is also shown in one objective slot.

## Smallest in-game check

1. Deploy Campaign Reimagined to GOG, then back up the existing
   `addon/lcbench/lcbench.lua` and copy `Tools/lcbench-venus.lua` over it. Keep
   EXU's `exu_weather.particle`, material, and mist texture in the mounted
   lcbench/EXU resource set.
2. Launch `battlezone98redux.exe lcbench.bzn`. Confirm distant terrain is lost
   in native olive fog while only a few large haze cards move near the camera.
3. Press `F3`, wait one second, and confirm the map's original fog and lighting
   return and the mist stops. Press `F3` again, then use `F1`/`F2` and the arrow
   keys to tune. Press `F4` to capture the chosen values in the log.

Host regression coverage is in `Tools/Test-CRVenusDenseAtmosphere.lua`.
