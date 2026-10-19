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
(`CRJungle17Sites.river`, the same polyline that cuts the river bed), lifted 1.1 m to the water plane;
everything else is grass, at a rate scaled by ground-cover instances (`layers`) in the 3x3 12 m cells
around the craft (0.4 on bare ground). The stream and pool water exists only as baked meshes with no
queryable data, so wading through them gets grass debris. Exporting pool/stream polygons from
`Tools/Build-Misn17Jungle.py` would close that gap.

## Validation

`lua5.1 Tools/Test-VehicleWakes.lua Scripts` (stubbed engine), plus the director tests. Owed live: an
lcbench particle smoke that the `cr_wake` templates parse in Ogre (Ogre skips malformed templates
silently) and an in-game look at each surface.
