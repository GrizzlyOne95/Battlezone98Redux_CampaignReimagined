# Venus ground-haze prototype

`VenusDenseAtmosphere` is a development-only CRWeather preset inspired by the
stock `venusimg.png`: olive-yellow low haze, muted local contrast, a bright
yellow-white sun, and slow wind close to the surface.

This revision deliberately leaves the map's native fog RGB and start/end
distances untouched. Native linear fog is global and cannot pool spatially, so
the visible haze comes from one low-count `CR/VenusGroundHaze` ParticleFX
system. No compositor, volumetric rendering, soft particles, scheduling, or
OpenShim hooks are involved.

## Terrain pooling

Every 0.25 seconds CRWeather samples the ground under the camera plus eight
points on a 65-unit ring. It then:

- positions the emitter 2.5 units above the local ground;
- suppresses haze as the local terrain exceeds a 2-12 degree slope range;
- gives ordinary flat ground a 55% base weight;
- adds density when the ring average is above the local ground, reaching full
  weight in a ten-unit basin;
- drains the layer on local high points;
- smooths changes over 0.6 seconds.

If the camera or terrain query is unavailable, the system fails soft to its
authored particle weight rather than affecting mission execution.

## Runtime budget

At `CRWeather.Quality = 1`, intensity `1`, and full basin weight:

| Layer | Template | Quota | Maximum emission | Lifetime |
| --- | --- | ---: | ---: | ---: |
| terrain-pooled ground haze | `CR/VenusGroundHaze` | 96 | 7 cards/s | 10-18 s |

Flat ground normally emits at 3.85 cards/s because of its 55% pool weight.
ColourInterpolator alpha, Scaler rate, DirectionRandomiser strength, emission,
and lighting all follow the combined intensity/pool weight. LinearForce follows
the live wind.

## Live lcbench controls

Deploy `Tools/lcbench-venus.lua` as `addon/lcbench/lcbench.lua`. It initializes
`Environment` before `CRWeather`, preserving Environment as the only renderer
atmosphere writer.

| Key | Action |
| --- | --- |
| `F1` / `F2` | previous / next tuning control |
| Left / Right | decrease / increase selected value |
| Shift + Left / Right | five-times step |
| `F3` | transition between Venus weather and clear |
| Home | restore authored defaults |
| `F4` | print all current values to the game log |

The selectable values are intensity, haze RGB, emission, alpha, scale, wind
bearing/speed, flat-ground pool weight, basin depth for full density, sample
radius, and maximum pooling slope. The objective display also reports live pool
weight, basin depth, and slope.

## Smallest in-game check

1. Deploy Campaign Reimagined to GOG and copy `Tools/lcbench-venus.lua` over
   `addon/lcbench/lcbench.lua`.
2. Launch `battlezone98redux.exe lcbench.bzn`. Confirm the map's original
   distance fog remains while olive cards stay close to sampled ground.
3. Drive from the flat test area onto a berm and into a depression. The live
   `Pool` readout should fall on the slope/high point and rise in the low flat
   area. Press `F3`, wait one second, and confirm lighting returns and haze is
   destroyed without any fog-distance change.

Host regression coverage is in `Tools/Test-CRVenusDenseAtmosphere.lua`.
