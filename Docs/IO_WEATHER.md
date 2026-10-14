# Io weather and atmosphere director

`Scripts/CRIoWeather.lua` is the Io counterpart of `CRVenusWeather`: it decides what the
sky, the lava and the ground do minute to minute, and it is reusable by every Io mission.
The first user is misn10 "The Race is On". **Everything it does is cosmetic.** It never
damages, shoves, scrambles, slows, spawns or removes anything, registers no gameplay
modifier and writes no velocity. The test suite traps every such function and asserts none
is called across hours of simulated eruptions and quakes.

Io is not Venus. There is no storm and no lightning. What the place has is a sulphur haze
lit by a huge warm Jupiter, red-hot lava that fills a third of the map, a geyser field that
keeps throwing ash columns, a steady fall of ash, and ground that shakes.

| File | Role |
| --- | --- |
| `Scripts/CRIoWeather.lua` | The director. Tunables are at the top of the file. |
| `Scripts/CRVenusMap.lua` | Shared pure half (seeded rng, severity ladder, terrain scan and basins, run expansion, vent merge, weighted pick). Reused as is; no copy. |
| `Scripts/CRIoSites11.lua` | Generated map data for misn11 (painted lava, one vent; see `MISN11_COOP.md`). |
| `Scripts/CRIoSites10.lua` | Generated map data for misn10 (playable box, lava cells, 322 lava fog anchors, 21 vents). |
| `Tools/Build-IoSites.py` | Regenerates a `CRIoSites<NN>.lua` from a mission's `.trn`, `.mat` and `.bzn`, read straight out of Redux's `bzone.zfs`. |
| `Materials/cr_io.particle.payload` | Six particle templates, all on existing `CR_FX/*` materials. Loaded through `CRParticleTemplates.EnsureExtra("cr_io")`. |
| `Tools/Test-CRIoWeather.lua` | Isolated-peer tests against an exu / BZ mock. |

Nothing shared was edited. The five `Io*` presets are registered into
`CRWeatherPresets.Presets` by the director at `Init` (idempotently), so
`CRWeatherPresets.lua` is untouched, and ash fall reuses `CR/Weather/AshFall` from the base
weather payload.

## Ownership rules (same as Venus and Mars)

- Fog, ambient and sun belong to `Environment.lua`. The director sets a CRWeather preset
  and registers an Environment modifier; it never calls `exu.SetFog` and friends.
- Radar and velocity jamming are not touched at all. Venus registered a gameplay modifier
  for storm degradation and used `SetObjectScramble`; Io registers neither.
- Quakes use the stock natives `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake`
  (exact spelling is part of the API, see `BZR_LUA_AGENT_REFERENCE.md`). There is no
  camera shake in EXU (`Docs/lua-definitions/ExtraUtils.lua` has none).

## The ladder

Five rungs, a smoothed fractional position (`SeverityRate` 0.05 rungs/s) driving everything
continuous, and integer rungs selecting a CRWeather preset. Same machinery and the same
`SetTargetLevel` / `ForceLevel` API as Venus (`CRVenusMap.NewLadder`, including temporary
intense **episodes** from rung 3 up). The brief's "calm / active / intense" are rungs
1, 3 and 4; rung 2 sits between calm and active and rung 5 is the burst.

| Rung | Preset | Ash fall | Vent speed | Max erupting | Lava fog | Gloom | Fog end | Sun |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 Calm | `IoCalm` | 0.10 | x0.60 | 2 | x0.60 | 0.00 | 250 | 0.85 |
| 2 Restless | `IoRestless` | 0.25 | x0.90 | 3 | x0.80 | 0.15 | 240 | 0.75 |
| 3 Active | `IoActive` | 0.50 | x1.25 | 4 | x1.00 | 0.40 | 215 | 0.62 |
| 4 Intense | `IoIntense` | 0.78 | x1.80 | 6 | x1.30 | 0.70 | 185 | 0.48 |
| 5 Paroxysm | `IoParoxysm` | 1.00 | x2.60 | 8 | x1.60 | 1.00 | 150 | 0.36 |

Inside an episode eruptions run a further x1.5 faster (`EpisodeEruptBoost`).

## 1. Sulphur haze lit by Jupiter

The global retune is the five presets plus the director's own Environment modifier. Calm is
a bright amber haze (sulphur-yellow fog `0.50 0.37 0.15`, warm tan Jupiter-lit diffuse
`0.74 0.55 0.33`, sun power 0.85). Each rung thickens the haze, drops the sun and pulls the
whole palette from sulphur-yellow toward red-brown, until a paroxysm is a dim, ember-coloured
gloom (fog `0.31 0.13 0.05` closing to 150, sun power 0.36). A `MarsHaze` particle layer
carries the haze and, from rung 2, a ground-level `DustGrit` layer. Presets keep the map's own
`[Sky] SkyTexture=jupiter.map` (`sky = nil`), carry no lightning, and are authored for
misn10's `VisibilityRange=250`; CRWeather clamps fog ends to the real horizon.

`Environment` modifier additions on top of the presets: gloom (`GloomDim` 0.16,
`GloomRed` 0.08, scaled by the rung's gloom value, so the light slides between rungs instead
of stepping with the preset crossfade), the lava tint (below), the eruption light (below) and
a mild fog-by-altitude term.

## 2. Lava: what is lava, how it was found, red fog over it

misn10's `[TextureTypeN]` labels, with the palette colour of each type's `FlatColor` in
`io.ACT` and the mean emissive value of its tile in the shipped `IO_ATLAS_E.dds` (the
`io_detail_atlas` emissive map; tile order from `io_detail_atlas.csv`):

| Index | `.trn` label | FlatColor RGB | Tile | Emissive (r) | Cells (base) | Verdict |
| ---: | --- | --- | --- | ---: | ---: | --- |
| 0 | Lava | 165,73,17 | `IO00SA0/SB0/SC0` | 11-35 | 38,063 (58 %) | Cooled crust with faint glowing cracks; the whole map, so it cannot mark a place (same reason as Venus's Sulphur Deposits) |
| **1** | **Lava Pool** | **227,54,0** | `IO11SA0` | **91** | **18,944 (29 %)** | **Molten lava, the strongest emitter: the lava tile** |
| 3 | Sulphur Deposits | 139,4,0 | `IO33*` | 0 | 6,312 | Yellow-tan, no glow; 18 of the 21 geysers stand on it |
| 4 | Hardened Lava | 53,6,0 | `IO44SA0` | 0 | 2,217 | Dark, no glow |
| 5 | Base | 4 | - | - | 0 | unused |

Transition cells (`(0,1)` 1,272 cells: Lava capping into Lava Pool) get weight 0.5, the same
convention as Venus. So **`Build-IoSites.py misn10 --types 1`** gives 18,944 molten cells
plus 1,272 transition cells in 1,525 run-length runs and 6 connected expanses (the biggest is
16,811 cells). Pass `--types 0,1` for a map where type 0 is a minority. The `.mat` is Redux's
own, read out of `bzone.zfs`; orientation uses the Venus rule (zones row-major south first,
base material in bits 15-12, next in 11-8), which this map confirms independently: 18 of 21
geysers land on Sulphur Deposits tiles and none stands in the pool, where a flipped or
swapped grid scatters them (5 and 10 of 21 on sulphur, with 8 and 7 in the pool).

**Pools are placed by the generator, not at run time.** Venus clusters a few hundred cells
in Lua at launch; misn10 has twenty thousand, so flood-filling and thinning in Lua would hitch
the load frame. The deterministic greedy pass scores each molten cell by the lava fraction
of its 7x7 neighbourhood, takes the densest first, keeps a candidate only if it is 110
units from every pool already kept and at least 0.55 dense, and keeps pools 40 units inside
the playable box. Result for misn10: 322 pools, every one on a molten tile, none closer
than 110 units, and 99.9 % of the 11,636 molten cells inside the playable box within 130 units of one (the rest of the 18,944 lie on the unreachable apron). `Tools/Test-CRIoWeather.lua`
asserts all of that against the shipped data.

At run time (`StreamSites`, the Venus streamer) at most `MaxLiveLava` (6) `CR/Io/LavaFog`
systems stream in inside `LavaStreamIn` (380) of the player, with one `CR/Io/LavaGlow` bloom
(additive, pulsing every 9 s) on up to `MaxLiveGlow` (4) of them. They sit 2 units above the
ground: a low red sheet, 110 x 110 units, rate scaled by the rung's lava-fog value and the
pool's lava fraction, leaning with the wind.

**The global tint.** `LavaDensityAt(x, z)` is the mean lava weight of the 7x7 cells around
the local player, sampled 4 times a second and smoothed (`LavaResponse` 0.45/s). Over a full
molten expanse the fog end closes to 72 % (start 62 %), the fog colour moves 55 % toward red
`0.46 0.12 0.05` and the lava lifts ambient and sun by `0.13 0.034 0.004` / `0.07 0.018 0`.
It falls away off the lava. Switch off with `lavaFog` / `lavaGlow` / `lavaTint`.

**Fog by altitude** is the Venus terrain scan (`NewHeightScan`, `AnalyseBasins`,
`PoolFactor`) run over the playable box, kept gentle (fog end x0.80 in an enclosed basin):
Io's haze belongs to the lava, not the lowlands. No fog particles are placed from it.

## 3. Geysers, vents and eruptions

The BZN has 21 `eggeizr1` objects and none merge at the 45-unit radius, so there are
**21 vent sites**. The seven named `geyser1` .. `geyser7` (the relic sites, which misn10's
targeting also uses) are marked `major`. Up to `MaxLivePlumes` (8) `CR/Io/Plume` systems
stream in inside 1,100 units: a steady sulphur-grey wisp leaning with the wind, and a second
emitter for the eruption column.

Eruptions are **periodic and staggered**, scheduled by the host:

- every vent has its own timer, a jittered 100-200 s period (relic geysers x0.75), counted
  down at the rung's vent speed (calm x0.60 .. paroxysm x2.60, x1.5 more in an episode);
- the first eruptions are spread evenly across one period in a seeded random order, none
  before 12 s, so the field is staggered from the first minute rather than going off on one beat;
- two eruptions never start closer than 3 s, and no more than the rung's allowance (2 .. 8)
  run at once; a vent that is blocked retries in 1-3 s;
- an eruption lasts 10-22 s: the column emitter ramps up over 1.6 s, an additive glowing core
  (`CR/Io/PlumeGlow`) and lava spatter (`CR/Io/Spatter`, gravity-arced) are created on up to
  `MaxLiveEruptFx` (4) plumes, a rumble (`gquak00.wav`) and a blast (`r_exp3.wav`) scale with
  distance, and the **ambient light near the vent lifts red** (up to `0.10 0.034 0.004`,
  falling off over 900 units) so the glow is felt on the ground, not just seen. Relic geysers
  erupt a little bigger (power 1.0-1.35 against 0.75-1.0).

## 4. Ash fall

One camera-attached `CR/Weather/AshFall` (the base weather payload's template, 2,000
particle quota, 44 units overhead), emission = 150/s x the rung's ash value, tinted
sulphur-grey and leaning with the wind. Quakes add up to x1.6 more while they last. `ashFall
= false` switches it off.

## 5. Earthquakes

### Scripted

```lua
CRIoWeather.Quake(strength, duration)    -- host / offline; returns true if a quake began
```

`strength` is clamped to 0..1 (default 0.8) and `duration` to 0.5-30 s (default 6). A
guest's call is ignored: the host's event is the authority. misn10 calls it **once**, when
the relic is first picked up.

### What a quake does

- **The engine shake.** `StartEarthquake(mag)` on the first frame, `UpdateEarthQuake(mag)`
  every `QuakeUpdateInterval` (0.05 s) along a smooth envelope (rise over 18 % of the
  duration, hold, fall over the last 40 %), `StopEarthquake()` at the end. `mag = strength x
  QuakeMagnitudeScale` (3.0; stock `misn18` uses 2.0 baseline and 6.0 spikes, `misn10`'s own
  cut quake used 2.0), never below `QuakeMinNative` (0.05). The native also plays the stock
  looping rumble.
- **Dust.** A camera-attached `CR/Io/QuakeDust` rides the same envelope (380 particles/s at
  full strength) and lingers 3 s after.
- **Ash.** The ash rate rises by up to x1.6 with the quake intensity and settles after.
- **Vents.** A quake of strength 0.55 or more (host decides, replicated as ordinary eruption
  events) sets off `round(3 x strength)` vents, picked weighted toward relic geysers, 0.9 s
  apart.
- **Merging.** A quake during a quake merges into it (the stronger strength, the later end);
  the native shake is never started twice and never cut short.

### Random

The host schedules unscripted quakes: **a gap of 90-240 s, strength 0.2-1.0, duration 2-10 s**.
All are named tunables (`QuakeGap`, `QuakeStrength`, `QuakeDuration`), plus
`QuakeStrengthBias` (strength = low + range x u^bias, bias 1.6 at calm falling to 0.8 at
paroxysm, so calm skies favour small tremors without leaving the range), `QuakeMinSpacing`
(20 s after any quake), `AllowRandomQuakes` (`randomQuakes = false` at `Init`).

### Replicated

Quakes are decided by the host only and sent as one small event (`IoQuake`). Every peer calls
the engine natives on receipt, so all of them shake together to within the link latency
(the test uses 120 ms and requires the starts to be within 0.3 s). Nothing about a quake
depends on the receiving peer's world, so unlike strikes and the Venus knock there is no
per-peer ownership question. The guest never schedules one of its own.

`StopQuake()` ends a shake on this peer at once; `Shutdown()` and `Load()` stop the engine's
quake too (OpenShim replays a persisted quake after a load, then fades it out; stopping it
ourselves means a loaded mission never keeps shaking).

## Co-op model

The mission runs only on the leader, and presentation events reach guests over the same
ordered, acknowledged stream as Venus lightning (see `MISN06_COOP.md`). The hybrid is the
Venus one, chosen per thing by what it depends on:

| What | Decided by | Why |
| --- | --- | --- |
| Severity ladder, episodes, wind | Pure function of a **seed** (every peer computes it) plus the host's rung as a correction | No traffic; a lost packet cannot freeze a guest's sky |
| Eruptions: site, time, duration, power | **Host**, one event each | Keeps the plume, glow, sound and light in step |
| Quakes: time, strength, duration | **Host**, one event each | Every peer shakes at the same moment |
| Lava fog, ash, haze, plume smoke, altitude fog | Local, from static map data | Cosmetic; only has to look right on that screen |

**Wire protocol.** All arguments are numbers.

| Op | Arguments | When |
| --- | --- | --- |
| `IoState` | `seed, clock, level, episode(0/1), target, forcedLevel(0=none), forcedFor` | start, on change, every 30 s |
| `IoErupt` | `id, siteIndex, durationSeconds, power` | each eruption |
| `IoQuake` | `id, strength, durationSeconds, kind(1 scripted, 2 random)` | each quake |

`siteIndex` indexes `GetVentSites()`, built deterministically from the shipped data on every
peer. Duplicate event ids are ignored, strengths and durations are clamped on receipt.
A guest with no seed shows calm weather until `IoState` arrives, follows the host's rung for
45 s after each message and then falls back to the seeded timeline it has been computing.

| Hook | Use |
| --- | --- |
| `Init{ authority, seed, send, sites, bounds, startLevel, targetLevel, ... }` | `send(op, ...)` delivers an event to every guest |
| `ApplyNetEvent(op, ...)` | the guest receive path; returns true when handled; ignored on the host |
| `GetNetState()` / `ApplyNetState(...)` | the seven-number state, for a custom transport |
| `AnnounceState()` | host: re-send now |
| `SetNetwork{ send, authority }` | change the above after `Init` |

## Integrating into misn10

`Scripts/misn10.lua` wires it (`-- CR Io weather` regions); see `MISN10_COOP.md` for the beats. The snippet below is the generic recipe.

```lua
local CRIoWeather = require("CRIoWeather")
local IoSites = require("CRIoSites10")
local IO_OPS = { IoState = true, IoErupt = true, IoQuake = true }
-- ApplyPresentation: elseif IO_OPS[op] then return CRIoWeather.ApplyNetEvent(op, ...) end
-- ReceivePresentation accept test: (native[op] or IO_OPS[op] or ...)

CRIoWeather.Init({
    authority   = (not net) or CRCoop.IsAuthority(),
    seed        = M.ioSeed,            -- nil: host/offline pick one, guests wait
    sites       = IoSites,
    startLevel  = 1,
    targetLevel = 2,
    send        = net and function(op, ...) --[[ queue on the presentation stream ]] end or nil,
})
CRIoWeather.Load(M.weatherState)       -- host/offline, after a load
-- once the session is ready, on the host:   CRIoWeather.AnnounceState()
-- every frame:                              CRIoWeather.Update(dt)
-- object creation hook:                     CRIoWeather.OnObjectCreated(h)
-- save: M.weatherState = CRIoWeather.Save();  M.ioSeed = CRIoWeather.Seed
-- cleanup:                                  CRIoWeather.Shutdown()
```

Beats (host / offline only; guests no-op and follow `IoState`):

```lua
CRIoWeather.SetTargetLevel(2)             -- opening: restless
CRIoWeather.SetTargetLevel(3)             -- when the 180 s bombardment begins
CRIoWeather.Quake(0.85, 6.0)              -- ONCE, on the first relic pickup
CRIoWeather.ForceLevel(4, 90.0, 10.0)     -- the race with the relic
CRIoWeather.ForceLevel(5, 40.0, 6.0)      -- a burst, e.g. the CCA seizing the relic
CRIoWeather.TriggerEruption(siteIndex)    -- optional: erupt the geyser the artillery hits
CRIoWeather.SetTargetLevel(2)             -- after delivery
```

`TriggerEruption(siteIndex [, power])` takes an index into `CRIoWeather.GetVentSites()`,
which is the BZN's `eggeizr1` order; match `label` (`geyser1` .. `geyser7`) to find a relic
geyser. Do not also call `CRMarsWeather`, `CRVenusWeather` or `Environment.TriggerDustStorm`
in the same mission, and do not call the stock earthquake natives alongside the director.

## Tunables (top of `CRIoWeather.lua`)

| Group | Names |
| --- | --- |
| Switches | `AllowLavaFog`, `AllowLavaGlow`, `AllowLavaTint`, `AllowAltitudeFog`, `AllowAshFall`, `AllowVents`, `AllowEruptions`, `AllowEruptLight`, `AllowQuakes`, `AllowRandomQuakes`, `AllowQuakeDust`, `AllowEpisodes` (also `Init` options `lavaFog`, `ashFall`, `quakes`, `randomQuakes`, ...) |
| Budgets | `MaxSystems` 40, `MaxLiveLava` 6, `MaxLiveGlow` 4, `MaxLivePlumes` 8, `MaxLiveEruptFx` 4, stream in/out distances |
| Ladder | `SeverityRate`, `EpisodeChance`, `EpisodePeak`, `EpisodeHold`, `EpisodeCooldown`, `EpisodeEruptBoost`, the `Levels` table |
| Lava | `LavaFogRate`, `LavaGlowRate`, `LavaGlowPulse`, `LavaSampleWindow`, `LavaResponse`, `LavaFogEndScale`, `LavaFogStartScale`, `LavaFogTint`, `LavaFogColor`, `LavaGlowAmbient`, `LavaGlowDiffuse` |
| Altitude fog | `ScanColumns/Rows/Budget/Inset`, `PoolFogEndScale`, `PoolFogStartScale`, `PoolFogTint`, `PoolFogColor`, `PoolBand`, `PoolResponse` |
| Light | `GloomDim`, `GloomRed`, `EruptLightRange`, `EruptLightColor` |
| Ash | `AshMaxRate`, `AshMaxQuota`, `AshOffset`, `AshTint`, `QuakeAshBoost` |
| Vents | `EruptionPeriod`, `EruptionMajorPeriodScale`, `EruptionFirstDelay`, `EruptionSeconds`, `EruptionPower`, `EruptionMajorPower`, `EruptionMinSpacing`, `Eruption*Rate`, sounds |
| Quakes | `QuakeGap`, `QuakeStrength`, `QuakeDuration`, `QuakeStrengthBias`, `QuakeMinSpacing`, `QuakeScriptedDefault`, `QuakeScriptedRange`, `QuakeDurationLimit`, `QuakeMagnitudeScale`, `QuakeMinNative`, `QuakeRise`, `QuakeFall`, `QuakeUpdateInterval`, `QuakeDustRate`, `QuakeDustLinger`, `QuakeEruptStrength`, `QuakeEruptCount`, `QuakeEruptSpread` |
| Co-op | `NetHeartbeat` 30, `HostOverrideSeconds` 45 |

## Capabilities that do not exist (and what was done)

| Wanted | Reality | Workaround |
| --- | --- | --- |
| Camera shake | None in EXU; the stock earthquake natives are the shake | `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake` on an envelope |
| A dynamic point light for the lava and the eruptions | Only lights on existing objects | Ambient and sun lift through the Environment modifier; additive bloom particles |
| The terrain material under a point | None at run time | Offline `Build-IoSites.py` reads the `.mat` once |
| Resizing a Box emitter per pool | No exu call used by the Venus module either | Fixed 110 x 110 sheet; pools are spaced 110 apart |
| Soft particles / depth haze | OpenShim intent reports `not-implemented` | Intent written (`depth_haze`), no effect yet |

## Shipping and admin notes (for the main session)

- New files only: `Scripts/CRIoWeather.lua`, `Scripts/CRIoSites10.lua`,
  `Materials/cr_io.particle.payload`, `Tools/Build-IoSites.py`, `Tools/Test-CRIoWeather.lua`,
  `Docs/IO_WEATHER.md`. `Shipping/shipping.lock.json` needs the normal `-bless` at merge
  time (the lock was not touched, nothing was blessed, deployed or published). The payload
  is a shipped file like `cr_venus.particle.payload`, so it needs its lock entry too.
- The payload is loaded through `EnsureExtra("cr_io")`, not added to the base list, so a
  build without it degrades (presets, ash and quakes still work) instead of breaking weather.
- Regenerate the data: `python -I Tools/Build-IoSites.py misn10` (reads Redux's
  `bzone.zfs` through the Modding Toolbox's `ZFSArchive`; `--source-dir` takes extracted
  files instead). The output is byte-reproducible.
- `lua5.1 Tools/Test-CRIoWeather.lua Scripts` passes, and so do the Venus, Mars, haboob,
  volcano, Venus-dense, fog-horizon and parameter tests and
  `python Tools/Validate-CampaignRepository.py`.

## What must be judged live

- **The shake.** `QuakeMagnitudeScale` (3.0) against the stock feel: is strength 1.0 too much
  or too little, does 0.2 register at all, does the stock looping rumble sound right at 20 Hz
  updates, and does `UpdateEarthQuake` tracking the envelope sound smooth or stepped.
- Whether the quake stops cleanly: no residual shake or looping sound after `StopEarthquake`.
- Lava fog colour, density and height over the actual lava textures; whether the additive
  glow reads or washes out; the 110-unit sheet seams between pools; `LavaStreamIn`.
- The lava tint strength (`LavaFogEndScale`, `LavaFogTint`, `LavaGlowAmbient`) driving a tank
  across the pools, and whether the ground light is too orange next to the preset ambient.
- The five presets in the Jupiter light: amber calm to ember paroxysm, against the map's own
  `Ambient=10`, `Intensity=90` and fog 175-250.
- Box-emitter axes: the templates assume `direction` is the depth axis. If a lava sheet or
  the dust slab comes out sideways, swap `width/height/depth`.
- Plume scale, column height (`Plume` emitter 1 velocity 28-48), glow core and spatter, and
  the density of the minor vents; relic-geyser prominence.
- Eruption cadence at each rung with 21 vents, and `MaxLiveEruptFx` against frame cost.
- Ash density and tint, and the extra quake ash.
- Total particle cost with every layer up; `MaxSystems` and the per-layer caps are the knobs.
- Co-op: a guest's quake against the host's, with real link latency.
