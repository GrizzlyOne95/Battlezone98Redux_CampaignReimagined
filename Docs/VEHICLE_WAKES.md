# Vehicle wakes (CRWake)

Render-only debris under low, moving craft, shared by every CR weather director.
`Scripts/CRWake.lua` is the one implementation; directors own it (`Init` /
`Update(dt)` / `Stop`) and pass a surface. No gameplay, no networking: each client
computes its own local view, so co-op needs no replication.

| Surface | Director | Template (payload) |
| --- | --- | --- |
| `regolith` | Moon (`CRMoonWeather`, was its hover dust) | `CR/Moon/HoverDust` (cr_moon) |
| `mars` | `CRMarsWeather` | `CRWake/MarsDust` (cr_wake) |
| `ice` | `CREuropaWeather` | `CRWake/IceSpray` |
| `water` + `grass` | `CRJungle17` (Achilles) | `CRWake/WaterSpray` + `CRWake/WaterRing`, `CRWake/GrassBits` |
| `sulfur` | `CRIoWeather` | `CRWake/SulfurDust` |
| `ash` | `CRVenusWeather` | `CRWake/AshDust` |

Titan keeps its own methane splash (`CRTitanWeather`); it is not routed through CRWake.

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
- Templates have quotas of 24..72.

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
plus half a cell of a stream point, so the mask covers the strip that is drawn. `Tools/Build-Misn17Jungle.py`
emits it with the rest of the sites; `Tools/Export-Misn17WaterMask.py` regenerates only the mask (no ISDFC
checkout needed) by executing the builder's WATER-MODEL slice on the original heightmap, and refuses to write
unless it reproduces the pool cell, stream path and stream point counts of `source-assets.json`.
`--check` verifies the file is current. The lift for mask water is a compromise (stream surface is 0.6 m above
the carved bed; pools sit up to 2 m above it).

## Validation

`lua5.1 Tools/Test-VehicleWakes.lua Scripts` (stubbed engine), plus the director tests. Owed live: an
lcbench particle smoke that the `cr_wake` templates parse in Ogre (Ogre skips malformed templates
silently) and an in-game look at each surface.
