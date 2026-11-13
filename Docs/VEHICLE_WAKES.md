# Ground kickup (CRWake)

Render-only debris under low, moving craft and under pilots on foot, shared by every CR weather director.
`Scripts/CRWake.lua` is the one implementation; directors own it (`Init` /
`Update(dt)` / `Stop`) and pass a surface. No gameplay, no networking: each client
computes its own local view, so co-op needs no replication.

| Surface | Director | Template (payload) |
| --- | --- | --- |
| `regolith` | Moon (`CRMoonWeather`, was its hover dust) | `CR/Moon/HoverDust` (cr_moon) |
| `mars` | `CRMarsWeather` | `CRWake/MarsDust` (cr_wake) |
| `ice` | `CREuropaWeather` (Europa) | `CRWake/IceSpray` |
| `ganymede` | `CREuropaWeather` on Ganymede (`wakeSurface`) | `CRWake/GanymedeSpray` |
| `water` + `grass` | `CRJungle17` (Achilles) | `CRWake/WaterSpray` + `CRWake/WaterRing`, `CRWake/GrassBits` |
| `water` + `mud` | `CRStorm18` (mission 18) | `CRWake/WaterSpray` + `CRWake/WaterRing`, `CRWake/MudClods` |
| `sulfur` | `CRIoWeather` | `CRWake/SulfurDust` |
| `ash` | `CRVenusWeather` | `CRWake/AshDust` |

Titan keeps its own methane splash (`CRTitanWeather`); it is not routed through CRWake.

Ganymede missions run `CREuropaWeather`; `CRCCARuntime` passes `wakeSurface = "ganymede"` for any weather whose
sites module is named `CRGanymedeSites*` (or the mission's `weather.wakeSurface`), otherwise Europa keeps `ice`.

## Physics, aim and pilots

| Surface | g (m/s^2) | Vacuum | Sprite | TTL |
| --- | --- | --- | --- | --- |
| `regolith` (Moon) | 1.62 | yes | `CR_FX/KickRegolith` 0.8 m | ballistic |
| `ganymede` | 1.43 | yes | `CR_FX/KickIce` 0.7 m (dirty dust sheet + bright ice chips) | ballistic |
| `ice` (Europa) | 1.31 | yes | `CR_FX/KickIce` 0.7 m (whiter) | ballistic |
| `sulfur` (Io) | 1.80 | yes | `CR_FX/KickRegolith` 0.8 m | ballistic |
| `mars` | 3.71 | no (thin air, modest billow) | `CR_FX/KickPuff` 0.9 m | template |
| `ash` (Venus) | 8.87 | no (dense air, drag-softened fall 2.4) | `CR_FX/KickPuff` 1.0 m | template |
| `grass` / `mud` | 9.81 | no | `CR_FX/KickClod` 0.7 m | template |
| `water` | 9.81 | no | `CR_FX/RainSplash` 1.1 m (not re-aimed) | template |

- Vacuum templates have no Scaler growth, `LinearForce` = the real g, alpha held until the last 0.6 s (`ColourFader2`),
  and a `Rotator` with a random start angle. Air templates keep a modest Scaler and a `Rotator`. Keep each
  template's `LinearForce` equal to the profile's `g` (or its `fall`); the tests check it.
- Each scan, a tracked mover's emitters are aimed (exu direction / velocity / TTL setters, silent no-ops without the
  API): emitter 0 (sheet) leaves along `back + up * 0.35` at `clamp(2 + 0.35 v, 2, 12)`, emitter 1 (chips) along
  `back * 0.6 + up` at `clamp(2.5 + 0.25 v, 2.5, 9)`, +/- 30 %. In a vacuum the TTL is `2 v sin(el) / g` clamped 0.6-4 s
  (set +/- 20 %). Setters run only after a heading change over ~10 degrees or a speed change of 15 % (min 1 m/s).
- Pilots on foot (`IsPerson`) use a separate "foot" system mode on every surface: only while moving at 1 m/s or more
  and within 1.2 m of the terrain (pilot origin height), no idle emission, 12 % of the profile rate, 0.3 m sprites, a 0.5 m emitter, and a
  launch speed capped so the apex stays under 0.6 m (`sqrt(2 g 0.6)`). The local player's pilot ranks first for the
  system cap. A pooled system is only reused for the same template and mode.
- Known limits (Ogre 1.10): one particle size per system (dust and chips share it) and one `Rotator` per system.
- Sprites are CR's own art (cr_kick_regolith / ice / clod / puff, 256 px DXT5) converted by `Tools/TexturesAndSky/Build-KickupTextures.py`; the clod art is already brown with grass blades, so mud and grass tint it near neutral.

## Load budget

- Scan at most 4 times a second (0.25 s), from the real clock.
- Only craft within 140 m (`trackRange`, clamped 20..300) of the viewpoint: the EXU camera
  (`GetCameraTransformMatrix`) when it reports one and it is within 600 m of the player, else the
  local player's craft. Craft behind the camera (cosine < -0.25, further than 25 m) are skipped when
  the camera reports a facing (`cullBehind`).
- At most 4 particle systems across all surfaces (`maxSystems`, hard max 6), nearest craft first.
  A water craft's flat ring is an accent that only exists when a slot is spare.
- A silent system lingers 4 s and is reused by the next craft of the same template before anything is
  created; otherwise destroyed. Emission fades over the outer 35 % of the range and scales with quality.
- Templates have quotas of 24..100.

## Options

Every director accepts `vehicleWakes = false` in its `Init` options (Achilles: `vehicleWakes` on the
`CRJungle17.Create` api table). The Moon keeps `hoverDust` and its `V.Hover*` tuning; they are forwarded.

## Achilles surface test

`CRJungle17.WakeSurface(x, z)`: water when within 7.5 m of the authored river route
(`CRJungle17Sites.river`), lifted 1.1 m to the water plane, or when the craft is on a cell of the generated
stream/pool mask (`CRJungle17Sites.watermask`), lifted 0.8 m; everything else is grass, at a rate scaled by
ground-cover instances (`layers`) in the 3x3 12 m cells around the craft (0.4 on bare ground).

The mask is the 5 m heightmap grid (x = col * 5, z = row * 5 + 97280) as run-length rows
(`rows[i]` = grid row `firstRow + i - 1`, `{startCol, length, ...}`), 30,339 cells in about 24.8 KB. Pool
cells are as baked into `cr17_pools.mesh`; stream cells are those whose centre lies within the drawn half-width
plus half a cell of a stream point, so the mask covers the strip that is drawn. `Tools/MissionBuild/Build-Misn17Jungle.py`
emits it with the rest of the sites; `Tools/MissionBuild/Export-Misn17WaterMask.py` regenerates only the mask (no ISDFC
checkout needed) by executing the builder's WATER-MODEL slice on the original heightmap, and refuses to write
unless it reproduces the pool cell, stream path and stream point counts of `source-assets.json`.
`--check` verifies the file is current. The lift for mask water is a compromise (stream surface is 0.6 m above
the carved bed; pools sit up to 2 m above it).

## Mission 18 surface test (mud)

`CRStorm18Water.WakeSurface(x, z)`: `water` (lift 0.5 m) on a cell of the generated misn18 water mask
(`CRStorm18Sites.watermask`, same format as above, built by `Tools/MissionBuild/Build-Misn18Water.py`), otherwise `mud`, at
a rate of 0.6 + 0.4 x the storm's mud amount. `CRWake/MudClods` is two emitters of `CR_FX/KickClod`: dark wet dirt and
heavier clods (gravity -9.81), quota 56, a four-stage ColourInterpolator, silent until driven.
See `MISN18_STORM.md` (Water and landscaping).

## Validation

`lua5.1 Tools/TexturesAndSky/Test-VehicleWakes.lua Scripts` (stubbed engine), plus the director tests. Owed live: an
lcbench particle smoke that the `cr_wake` templates parse in Ogre (Ogre skips malformed templates
silently) and an in-game look at each surface.


## Live results 2026-10-19

Mission 18 (`CRStorm18`, DX11, one peer, `misn18-wakes-1p-a20261019-104453` and `-b20261019-104733`): `CRWake` initialised
with `mud` and `water` available, no template failures, zero errors; 7 systems were created over the water lane and 10 over
the mud lane (the four-system cap held). The scripted captures did not frame the shuttling craft, so how the wakes look
is **unverified**; the surfaces still need an in-game look (Moon, Mars, Achilles river/pool/grass were not run).
