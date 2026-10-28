# Europa weather and atmosphere director

**Sensor policy update (15 October 2026):** Missions 12/13 now bind director severity to Environment sensors, including during the stealth mission. This deliberately supersedes the old visual-only mission policy below; the visual director itself still has no native sensor writes. See
`WEATHER_SENSOR_POLICY.md` for the current campaign policy.


`Scripts/CREuropaWeather.lua` is the Europa counterpart of `CRIoWeather`, `CRVenusWeather` and
`CRMarsWeather`, and it follows the Io architecture (seeded ladder, host-decided replicated
events, generated map data). It is reusable by any Europa mission; the first user is misn12
"Flying Solo", a stealth infiltration.

**It has no gameplay effect at all.** It never damages, shoves, scrambles, slows, spawns,
removes, retargets or re-teams anything. It does not touch radar, velocity jam, AI perception,
cloaks, stealth or objectives, and registers no Environment gameplay modifier. The only state it
writes is render state (a CRWeather preset, an Environment fog / light modifier, particle
systems), local 2D sounds, and the engine's earthquake shake. `Tools/Test-CREuropaWeather.lua`
audits this by wrapping every stubbed BZ and exu function and asserting the called set is a
subset of an allowlist (details under "Gameplay-effect statement").

| File | Role |
| --- | --- |
| `Scripts/CREuropaWeather.lua` | The director. Tunables are at the top of the file. |
| `Scripts/CRVenusMap.lua` | Shared pure half (seeded rng, ladder, vent merge, weighted pick). Reused as is. |
| `Scripts/CREuropaSites12.lua` | Generated map data for misn12 (16 geysers, 120 frost-haze anchors, bounds). |
| `Tools/Build-EuropaSites.py` | Regenerates a `CREuropaSites<NN>.lua` from a mission's `.trn`, `.mat`, `.bzn` (and optionally the map worker's geysers JSON). |
| `Materials/cr_europa.particle.payload` | Five particle templates on the `CREuropa/*` materials. Loaded through `CRParticleTemplates.EnsureExtra("cr_europa")`. |
| `Materials/crart_europa.material` | The `CREuropa/*` particle materials: existing `CR_FX` art on the RGBA-order `CRWX_FX` vertex program plus `CR_Effect_fragment`, so DX11 draws the pass natively. On the `CR_FX/*` originals DX11 swapped red and blue, so the cold blue-white plumes, ice and frost drew a warm peach. |
| `Materials/cr_weather.particle.payload` | `CR/Europa/Glitter`, the presets' ice glitter: `CR/Weather/SnowLight` on `CREuropa/Snow`. It lives in the base payload so the presets work without the opt-in `cr_europa` one. |
| `Tools/Test-CREuropaWeather.lua` | Isolated-peer tests against an exu / BZ mock. |

No shared file was edited for the feature. The five `Europa*` presets are registered into
`CRWeatherPresets.Presets` by the director at `Init` (idempotently), so `CRWeatherPresets.lua`
is untouched (this also keeps clear of open CR PR #180). The existing `EuropaBlizzard` preset is
**not** used: it is a wind-driven gale (26 units/s, gusts, a blizzard sky dome) which is exactly
what Europa does not have.

## Physics rationale

Europa has essentially no atmosphere: a tenuous oxygen exosphere, surface pressure around
10^-12 bar. So there is no wind, no cloud, no rain and no blizzard, and falling material follows
ballistic arcs under about 0.13 g. What does happen:

- **Cryovolcanic water-vapour plumes** (observed above Europa's southern terrain): vapour thrown
  up ballistically, freezing into fine ice crystals that fall back around the vent. Modelled as
  a rise-and-fall column (a `LinearForce` gravity on the particles) and a `CR/Europa/IceFall` footprint
  falling straight down, with a short local frost haze that thins the view near the vent.
- **Tidal flexing**: Jupiter squeezes the ice shell every 3.55 days, causing ice quakes and
  modulating how active the vents are. Modelled as rare gentle shakes and a seeded slow "tide"
  (`TidalPeriod` 540 s, +/-35 %) on the host's plume and quake pacing.
- **Jupiter's radiation belts**: Europa sits inside them. A surge is drawn as a brief auroral
  violet-green glow and a flicker in the light, **not** as sensor interference (see below).
- **Sublimation frost** hangs low over frosted ground between events.

## The ladder

Five activity rungs, a smoothed fractional position (`SeverityRate` 0.04 rungs/s) driving
everything continuous, and integer rungs selecting a CRWeather preset. Same machinery and API as
Io (`CRVenusMap.NewLadder`, including temporary intense **episodes** from rung 3 up).

| Rung | Preset | Plume rate | Max plumes at once | Quake rate | Surge rate | Frost haze | Ice glitter | Fog end |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 Quiescent | `EuropaQuiescent` | x0.45 | 1 | x0.50 | x0.40 | 0.60 | 0.15 | 290 |
| 2 Stirring | `EuropaStirring` | x0.80 | 2 | x0.80 | x0.80 | 0.80 | 0.30 | 275 |
| 3 Venting | `EuropaVenting` | x1.20 | 3 | x1.00 | x1.00 | 1.00 | 0.50 | 258 |
| 4 Flexing | `EuropaFlexing` | x1.70 | 4 | x1.60 | x1.10 | 1.20 | 0.72 | 242 |
| 5 Perijove | `EuropaPerijove` | x2.40 | 6 | x2.40 | x2.50 | 1.40 | 1.00 | 222 |

"Rate" multiplies how fast events happen (the gap between random quakes and surges is divided by
it; a vent's plume timer runs at it). Inside an episode plumes run a further x1.4. The tide
multiplies plume and quake pacing by `1 +/- 0.35` along a sine whose phase is derived from the seed.

Europa is airless. Its sky is the catalog star box (`CR_Sky/EuropaStars`), with Jupiter (12.2
degrees across, fixed in the sky) and Io, Ganymede and Callisto drawn on the TRN `[Stars]` quads of
misn12 and misn13. The light comes from Environment's `orbit` mode: the sun's real path, a short
eclipse behind Jupiter (about 3.5 % of the day), and a dimmer Jupiter-shine at night than Io's. The
presets therefore carry no ambient or diffuse (both `nil`), which leaves the light to the orbit.
`Scripts/CRWorldArt.lua` turns each TRN heading into Redux's render space (z mirrored, see
`Docs/TERRAIN_CLUTTER_PHASE_A_VALIDATION.md`) before any orbit maths. The sky shaders and the scene
light work in that space, and before this conversion Jupiter's phase (and Io's, on misn10/11) came
out mirrored.

The presets are cold and dark (fog `0.20-0.22 / 0.24-0.28 / 0.30-0.36`, so the horizon does not
glow against the black sky, and a weak sun), and
carry **one** precipitation layer (`CR/Europa/Glitter`, an ice glitter at 14-90 particles/s falling
1.0-2.2 units/s at a 5 degree cone) and no lightning, sky or gusts. Each preset has `wind = (0,-1,0)`,
`windSpeed = 1.0`; the director also pins `CRWeather.SetWindOverride({0,-1,0}, 1.0)`, so
CRWeather's wind-to-emitter-direction push is exactly vertical and its velocity scale is exactly 1.
(The test asserts the recorded emitter direction has zero horizontal component even at perijove.)

Europa has no snowfall, so that glitter is not weather everywhere: the director runs it at
`GlitterBase` (0.15, frost sparkling off the surface) through `CRWeather.SetPrecipitationScale`
and lifts it to the full preset rate under a plume's fallout where the player stands
(`GetFallout`, the same falloff as the frost boost, `FrostFallRange`). The fallout also adds up to
`GlassFallout` (0.5) to the cockpit-glass level. Shutdown puts the scale back to 1.

## Events

### 1. Plumes (host-decided, replicated)

- Every vent has its own timer, a jittered 400-800 s period at rate scale 1 (named landmark
  geysers x0.85), counted down at the rung rate x tide. The first plumes are spread evenly across
  one period in a seeded random order, none before 20 s.
- Two plumes never start closer than 6 s, and no more than the rung's allowance run at once; a
  blocked vent retries in 2-6 s.
- A plume lasts 18-40 s. The vapour column (`CR/Europa/Plume`, emitter 1) ramps up over 2.2 s and
  dies away over the last 40 % (max 9 s). **Ice fall** (`CR/Europa/IceFall`, up to 4 at once) starts
  4 s after the plume (the time to reach the ground), ramps over 5 s and keeps falling for 28 s after
  the column ends. A quiet ground-conducted rumble (`gquak00.wav`, volume <= 38, local 2D) plays
  when a plume starts within 1,200 units.
- **Local frost haze.** Within 320 units of a falling-out vent the Environment modifier pulls the fog
  end to x0.72 (start x0.55), tints it 35 % toward white-blue and lifts the ambient slightly. This is
  render fog only. The fog end never drops below 0.72 of the preset's at the vent itself.
  Frost-haze sheets near a falling-out plume also emit up to x2.5 as much.
- A strong quake (strength >= 0.55) opens one vent, weighted toward landmark geysers (x2), 1.2 s later.
- **Ground height.** Plumes, ice fall and frost sheets are positioned on `GetTerrainHeightAndNormal`,
  not on the BZN's y (stock misn12 has 10 of 16 geysers at y < 2, unsnapped); the data's y is only
  a fallback.

### 2. Tidal ice quakes (host-decided, replicated)

`Quake(strength, duration)` uses the same engine path as Io: `StartEarthquake` on the first frame,
`UpdateEarthQuake` every 0.05 s along a smooth envelope (rise 18 %, fall 40 %), `StopEarthquake`
at the end. Native magnitude = strength x `QuakeMagnitudeScale` (2.4; Io is 3.0), never below 0.05.
Frost shaken loose (`CR/Europa/QuakeIce`, camera-attached, 260 particles/s at full strength) rides the
envelope and lingers 3 s. A quake during a quake merges into it.

Random quakes: gap 150-420 s at quake scale 1 (so rare), strength 0.12-0.70, duration 2-7 s,
`QuakeStrengthBias` 1.8 at quiescent falling to 1.0 at perijove, 30 s minimum spacing. A guest's call is
ignored.

### 3. Jupiter radiation surges (host-decided, replicated, visual only)

`Surge(duration, strength)`: strength 0..1, duration 0.5-20 s (defaults 5 s at 0.8). An envelope
(rise 15 %, fall 45 %) drives:

- an ambient lift of up to `0.05 0.07 0.095` (violet-green auroral cast), scaled by a deterministic
  flicker (sum of two sines of the clock, no random draws, so it cannot desynchronise a stream);
- a +/-16 % sun brightness flicker;
- a 22 % tint of the fog colour toward `0.46 0.78 0.70` (never reducing fog distance);
- sparse additive motes (`CR/Europa/SurgeMotes`, camera-attached, <= 36 particles/s);
- one brief crackle (`lstart.wav`, volume <= 30, local 2D) when the surge begins.

Random surges: gap 200-520 s at surge scale 1, strength 0.30-1.00, duration 3-9 s, 40 s spacing.

**Why a surge is not radar static.** The Venus technique (`Environment.SetObjectScramble`, or a
gameplay modifier) multiplies a craft's radar range / period / velocity jam. Those are the units'
own sensor values: AI craft share them, so a radar flicker changes what is detected, which in
a stealth mission is gameplay, not decoration. The `exu` API also has no HUD-only static (it can only
resize the radar or change its state). So no radar, HUD or sensor effect is implemented; the surge is
purely an atmospheric light event. If a later design wants HUD static, it needs a renderer-side
overlay, not the sensor path.

### 4. Frost haze (local, from map data)

`CR/Europa/FrostHaze`: a low pale sheet (90 x 90 units, 2 above the ground) streamed in at up to 6
anchors within 360 units of the player. Anchors come from `Tools/Build-EuropaSites.py`: stock misn12
labels `0 Thin Ice, 1 Frozen Tundra, 2 Snowy Rock, 3 Glacial, 4 Base`. **Frozen Tundra (type 1)** is the
default because it is only 3 % of the map (1,916 cells of 65,536) and 12 of the 16 geysers stand on it, i.e.
it is the frost the vents deposit; Snowy Rock is 89 % of the map and cannot mark a place. Anchors are the
Io tool's deterministic greedy pass: densest 5x5 neighbourhood first, >= 70 units apart, inside the playable box
(120 anchors, 13 patches).

## Co-op model

Identical to Io. The mission runs only on the leader/host; events ride the same ordered stream as
other presentation events.

| What | Decided by | Why |
| --- | --- | --- |
| Activity ladder, episodes, tide phase | Pure function of a **seed** (every peer computes it) plus the host's rung as a correction | No traffic; a lost packet cannot freeze a guest's sky |
| Plumes: site, time, duration, power | **Host**, one event each | Keeps the column, ice, sound and haze in step |
| Quakes, surges: time, strength, duration | **Host**, one event each | Every peer shakes / glows at the same moment |
| Ice glitter, frost haze, tint, fog | Local, from static map data | Cosmetic; only has to look right on that screen |

The three random schedulers use independent seeded streams (`DeriveSeed` salts 13 plume, 16 quake, 17 surge), host-only.
The flicker takes no random draws and the tide is a function of the clock and seed, so a peer that
runs the director with a different frame rate or a different player position cannot drift: only the
host's rng is ever consumed, and the test asserts the host's events do not depend on the local
player's position.

**Wire protocol.** All arguments are numbers.

| Op | Arguments | When |
| --- | --- | --- |
| `EuropaState` | `seed, clock, level, episode(0/1), target, forcedLevel(0=none), forcedFor` | start, on change, every 30 s |
| `EuropaPlume` | `id, siteIndex, durationSeconds, power` | each plume |
| `EuropaQuake` | `id, strength, durationSeconds, kind(1 scripted, 2 random)` | each quake |
| `EuropaSurge` | `id, strength, durationSeconds, kind(1 scripted, 2 random)` | each surge |

`siteIndex` indexes `GetVentSites()` (the merged `vents` table, built deterministically on every peer).
Duplicate ids are ignored, strengths / durations / powers are clamped on receipt, an unknown site is
refused. A guest with no seed shows calm weather until `EuropaState` arrives, follows the host's rung for 45 s
after each message and then falls back to the seeded timeline it has been computing.

## Public API

Host / offline unless noted; a guest's call is ignored.

| Call | Notes |
| --- | --- |
| `Init{ authority, seed, send, sites, startLevel, targetLevel, enabled, debug, quality, baseSky, plumes, iceFall, frostHaze, ventHaze, quakes, randomQuakes, quakeIce, surges, randomSurges, aurora, episodes, sounds }` | `send(op, ...)` delivers an event to every guest. `seed = nil` on a guest waits for the host. |
| `Update(dt)` | every frame, every peer (real-clock dt like the other directors) |
| `Shutdown()` | stops the shake, destroys every system, unregisters the modifier |
| `Save()` / `Load(state)` | plain scalars; `Load` stops any quake the engine replays |
| `SetTargetLevel(n)` | 1..5, the level the timeline trends toward |
| `ForceLevel(n, seconds, transition)` / `ReleaseForcedLevel()` | pin a rung for a set piece |
| `Quake(strength, duration)` | 0..1, 0.5-30 s; returns true if a quake began |
| `TriggerPlume(siteIndex, power)` | alias `TriggerEruption`; `nil` index picks a vent from the seeded stream |
| `Surge(duration, strength)` | 0.5-20 s, 0..1 |
| `StopQuake()` | ends this peer's shake now |
| `AnnounceState()` | re-send `EuropaState` (host; call once the session is ready) |
| `ApplyNetEvent(op, ...)` | guest receive path, returns true when handled; ignored by the host |
| `GetNetState()` / `ApplyNetState(...)` / `SetNetwork{send, authority}` | custom transport |
| `OnObjectCreated(h)` | forwards to CRWeather |
| `RegisterPresets()`, `GetPresetNames()` | preset registration, idempotent |
| getters | `GetLevel GetLevelName GetTargetLevel IsEpisode GetSeverity GetVentSites GetFrostPools GetActivePlumes GetStats GetSystemCount IsQuaking GetQuake GetQuakeIntensity IsSurging GetSurge GetSurgeIntensity GetTidalPhase GetVentHaze Describe` |

Fields mirrored from Io: `Seed`, `IsAuthority`, `Synced`, `ForcedLevel`, `TemplateFailures`.

## How a mission wires it (the misn11 pattern)

misn11 wires the Io director in `-- CR Io weather` regions: `InitIoWeather` (called lazily on the first
frame), `UpdateIoWeather` (every frame on every peer, then `Environment.Update`), `ShutdownIoWeather`,
`UpdateIoBeats` (host only), an `IO_OPS` table routed in `ApplyPresentation` and accepted by
`ReceivePresentation`'s op test, and `M.ioSeed` / `M.weatherState` saved with the mission. Europa is
the same with different names; the recipe follows.

```lua
local CREuropaWeather = require("CREuropaWeather")
local EuropaSites = require("CREuropaSites12")
local EUROPA_OPS = { EuropaState = true, EuropaPlume = true, EuropaQuake = true, EuropaSurge = true }
-- ApplyPresentation: if EUROPA_OPS[op] then return CREuropaWeather.ApplyNetEvent(op, ...) end
-- ReceivePresentation accept test: (native[op] or EUROPA_OPS[op] or ...)

Environment.Init()
CREuropaWeather.Init({
    authority   = (not net) or CRCoop.IsAuthority(),
    seed        = M.europaSeed,       -- nil: host/offline pick one, guests wait
    sites       = EuropaSites,
    startLevel  = 1,
    targetLevel = 1,
    send        = net and function(op, ...) --[[ queue on the presentation stream ]] end or nil,
})
CREuropaWeather.Load(M.weatherState)  -- host/offline, after a load
-- ready (host): CREuropaWeather.AnnounceState()
-- every frame:  CREuropaWeather.Update(dt); Environment.Update(dt)
-- save:         M.weatherState = CREuropaWeather.Save(); M.europaSeed = CREuropaWeather.Seed
-- cleanup:      CREuropaWeather.Shutdown()
```

Do not also call `CRIoWeather`, `CRMarsWeather`, `CRVenusWeather` or `Environment.TriggerDustStorm` in the same
mission, and do not call the stock earthquake natives alongside the director.

Suggested stealth-friendly beats (host / offline only):

```lua
CREuropaWeather.SetTargetLevel(2)          -- once the player is moving (haze and glitter build gently)
CREuropaWeather.TriggerPlume(siteIndex)    -- optional scenery on a named geyser (labels in GetVentSites())
CREuropaWeather.Quake(0.4, 3.0)            -- optional, e.g. a story beat
CREuropaWeather.Surge(5.0, 0.8)            -- optional, e.g. when a comms message plays
CREuropaWeather.SetTargetLevel(1)          -- on the win
```

## Tunables (top of `CREuropaWeather.lua`)

| Group | Names |
| --- | --- |
| Switches | `AllowPlumes`, `AllowIceFall`, `AllowFrostHaze`, `AllowVentHaze`, `AllowQuakes`, `AllowRandomQuakes`, `AllowQuakeIce`, `AllowSurges`, `AllowRandomSurges`, `AllowAurora`, `AllowEpisodes`, `AllowSounds`, `AllowGlassSnow` (also `Init` options `plumes`, `iceFall`, ..., `glassSnow`) |
| Budgets | `MaxSystems` 28, `MaxLiveFrost` 6, `MaxLivePlumes` 8, `MaxLiveFall` 4, stream in/out distances |
| Ladder | `SeverityRate`, `EpisodeChance`, `EpisodePeak`, `EpisodeHold`, `EpisodeCooldown`, `EpisodeRateBoost`, the `Levels` table, `TidalPeriod`, `TidalDepth` |
| Plumes | `PlumePeriod`, `PlumeMajorPeriodScale`, `PlumeFirstDelay`, `PlumeSeconds`, `PlumePower`, `PlumeMinSpacing`, `PlumeBurstRate`, `FallDelay`, `FallLinger`, `FallRate`, `FallHeight`, `VentHaze*` |
| Quakes | `QuakeGap`, `QuakeStrength`, `QuakeDuration`, `QuakeStrengthBias`, `QuakeMinSpacing`, `QuakeScriptedDefault`, `QuakeDurationLimit`, `QuakeMagnitudeScale`, `QuakeMinNative`, `QuakeIceRate`, `QuakePlumeStrength` |
| Surges | `SurgeGap`, `SurgeStrength`, `SurgeDuration`, `SurgeAmbient`, `SurgeFogColor`, `SurgeFogTint`, `SurgeFlicker`, `SurgeMoteRate`, `SurgeSound` |
| Co-op | `NetHeartbeat` 30, `HostOverrideSeconds` 45 |

## Cockpit-glass snow

A few soft-white snow flakes land on the cockpit glass, melt away and return elsewhere (`CRWetGlass.Weather("snow", level)`,
see `Docs/CR_STORMFX_PORT.md`). Render only. The level is `(0.22 + 0.38 * GetSeverity()) * (0.85 + 0.15 * sin(2 pi clock / 170))`,
eased at 0.04 per second, so a quiescent Europa (misn12 opens there) carries about 0.2 and perijove about 0.5; the layer
opacity at that level is about 0.2-0.4 of a sparse sheet. Local to each peer (no wire traffic), off with `AllowGlassSnow` /
`Init{ glassSnow = false }`, with `CRWeather.Quality` 0, or when the director is disabled. `GetGlassSnow()` reports the
level; `Shutdown` clears it and calls `CRWetGlass.Stop()`. Misn12 and misn13 need no change.

## Gameplay-effect statement

**None.** Specifically, the director never calls: any damage / health / ammo function, `Set/Add/Kill`,
`SetVelocity`, `SetPosition`, `BuildObject`, `RemoveObject`, `SetTeamNum`, `SetPerceivedTeam`, `Attack` /
`Goto` / `SetCommand`, any objective call, `exu.SetRadarRange`, `exu.SetRadarPeriod`, `exu.SetVelocJam`,
`Environment.SetObjectScramble`, `Environment.RegisterGameplayModifier`, or any gravity / cloak call. What it does
call: `exu` particle functions, the CRWeather preset API, an Environment **environment** modifier (fog / ambient / diffuse
only), `StartSound` with no object handle (a local 2D sound that is not a game noise), and
`StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake` (view shake, no physics).

Two things a reviewer should know:

- **Fog is render-only but it is visible to the players.** The local vent haze can thin the view
  to roughly half the preset fog end for a few seconds beside an erupting vent. That is a visual
  effect on the player's own screen; no AI reads it. If the design wants strictly constant sight
  distance for the player, set `ventHaze = false` (the ice fall and the vapour column still draw).
- **Environment's own night pass rewrites craft sensors in every weather mission, with or without
  this director** (`RadarRangeNerf`, `RadarPeriodNerf`). The suite proves the director is not the source:
  after a busy run, the radar range, period and jam of every craft equal those of a control peer with
  no director at all, to 1e-9.

The suite's stealth audit (section 11) runs 40 minutes at perijove with a surge, a quake and a plume forced every
minute next to two craft on opposite teams, then asserts: no forbidden function recorded on any of the peers in
the whole suite, every global and `exu` function called is on an allowlist (or matches no forbidden
pattern), scales / scrambles / modifiers are identity, no craft moved, no team changed, sensors equal the
no-director control, and the source text does not even mention the dangerous names. A mutation check
(inserting `SetPerceivedTeam` and `exu.SetRadarRange` into `BeginSurge`) makes it fail six ways.

## Capabilities that do not exist (and what was done)

| Wanted | Reality | Workaround |
| --- | --- | --- |
| Radar / HUD static during a surge | The only levers are per-craft sensor values (`SetRadarRange`, `SetVelocJam`), which AI shares, and radar size / state | Not implemented; atmospheric light event only |
| Camera shake | None in EXU; the stock earthquake natives are the shake | `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake` on an envelope |
| A dynamic point light for the aurora or the vent | Only lights on existing objects | Ambient lift through the Environment modifier; additive mote particles |
| The terrain material under a point | None at run time | Offline `Build-EuropaSites.py` reads the `.mat` once |
| Soft particles / depth haze | OpenShim intent reports `not-implemented` | Not used |

## Shipping and admin notes (for the main session)

New files only (see the list below); nothing shared was edited except an additive paragraph in
`Docs/WEATHER_ENVIRONMENT_OWNERSHIP.md`. `Shipping/shipping.lock.json` needs the normal `-bless` at merge
time (not touched here). The payload is a shipped file like `cr_io.particle.payload`, so it needs its
lock entry. It is loaded through `EnsureExtra("cr_europa")`, not added to the base list, so a build without it
degrades (presets, glitter and quakes still work) instead of breaking weather. Add
`lua5.1 Tools/Test-CREuropaWeather.lua Scripts` to `campaign-validation.yml` next to the other weather suites.

Regenerate the data: `python -I Tools/Build-EuropaSites.py misn12 --source-dir Missions` (the converted map's
`.bzn` is used when present; the stock `.trn` / `.mat` come from Redux's `bzone.zfs` for any file missing in
the folder). `--geysers-json FILE` replaces the vents with a `[{label,x,y,z,odf}]` list. The output is
byte-reproducible; with the co-op map worker's `misn12.bzn` and its geysers JSON the output is identical
except for one header line.

New files:

```text
Scripts/CREuropaWeather.lua
Scripts/CREuropaSites12.lua
Materials/cr_europa.particle.payload
Tools/Build-EuropaSites.py
Tools/Test-CREuropaWeather.lua
Docs/EUROPA_WEATHER.md
```

## What must be judged live (not verified)

Everything visual and audible. No game was run.

- Do the five `CR/Europa/*` templates render as intended: vapour column height (emitter 1 velocity 38-62
  against a -5 `LinearForce`, apex around 150-190 units), the ice-fall footprint (110 x 110, 55 over the
  ground) and whether crystals visibly fall straight, the frost sheets' seams and alpha, quake ice, auroral motes
  (check Box axes: `direction` is the depth axis).
- `QuakeMagnitudeScale` 2.4 against the stock feel, and whether the stock loop rumble sounds right for a tidal
  quake; whether `StopEarthquake` ends cleanly.
- Whether `lstart.wav` and `gquak00.wav` suit a crackle / ground rumble (both reused from the Venus and Io
  directors; volumes are guesses), and whether 2D plays are quiet enough in a stealth scene.
- Fog end values (150-290) against misn12's real `VisibilityRange`; CRWeather clamps them to the real horizon.
- Whether the local vent haze reads as haze or as a visibility penalty (see the gameplay note).
- Whether plume cadence at rungs 1-2 (one every ~80 s and ~50 s across the whole map) suits a stealth mission.
- Total particle cost with every layer up; `MaxSystems` 28 and the per-layer caps are the knobs.
- Co-op with real link latency (the test uses 120 ms and requires shake starts within 0.3 s).
- The geysers in misn12 double as spawn / waypoint markers (`spawn_geyser`, `choke_geyser`, ...); a plume on top of a
  spawn point is scenery only, but confirm it reads well.
