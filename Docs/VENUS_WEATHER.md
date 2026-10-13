# Venus weather and atmosphere director

`Scripts/CRVenusWeather.lua` is the Venus counterpart of `CRMarsWeather`: it decides
what the sky does minute to minute, and it is reusable by every Venus mission. The
first user is misn07 "Behind Enemy Lines".

Venus is not Mars with a different palette. There is no wind worth the name, nothing
falls to the ground, and what the place has instead is a thick, dim, sulphurous
overcast, fog that pools in the lowlands, boiling sulphur, volcanoes, and lightning
that is the point of the setting.

| File | Role |
| --- | --- |
| `Scripts/CRVenusWeather.lua` | The director. Tunables are at the top of the file. |
| `Scripts/CRVenusMap.lua` | The pure half: seeded rng and severity ladder, basin detection, sulfur clustering, weighted picks. No engine calls. |
| `Scripts/CRVenusSites07.lua` | Generated map data for misn07 (playable box, sulfur cells, vents). |
| `Tools/Build-VenusSites.py` | Regenerates a `CRVenusSites<NN>.lua` from a mission's `.trn`, `.mat` and `.bzn`. |
| `Scripts/CRWeatherPresets.lua` | Adds the five ladder presets `VenusCalm` .. `VenusSevere` (fog, light, haze, grit; no lightning, no rain). |
| `Materials/cr_venus.particle.payload` | Eight particle templates, all on existing `CR_FX/*` materials. |
| `Scripts/CRParticleTemplates.lua` | New `EnsureExtra(name)` loads an opt-in payload without risking the base set. |
| `Scripts/Environment.lua` | New `SetObjectScramble` / `ClearObjectScramble` / `GetObjectScramble`: a per-craft, self-expiring sensor scale. |
| `Tools/Test-CRVenusWeather.lua` | Isolated-peer tests against an exu / BZ mock. |

## Ownership rules (same as Mars)

- Fog, ambient and sun belong to `Environment.lua`. The director sets a CRWeather
  preset and registers an Environment modifier; it never calls `exu.SetFog` and friends.
- Radar range and velocity jamming belong to `Environment.lua`. The director registers a
  gameplay modifier for the storm-wide degradation and uses `SetObjectScramble` for
  per-craft strike scrambles.
- The director never touches gravity, health, ammo or objects. The test suite traps every
  damaging function and asserts none is called across twenty-minute storms, strikes,
  eruptions and acid rain.

## The severity ladder

Five rungs, a smoothed fractional position (`SeverityRate` 0.05 rungs/s) driving everything
continuous, and integer rungs selecting a CRWeather preset.

| Rung | Preset | Strikes/min | Acid rain | Cloud deck | Gloom | Radar range |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 Calm | `VenusCalm` | 0 | 0 | 0.20 | 0 | 1.00 |
| 2 Haze | `VenusHaze` | 0 | 0 | 0.40 | 0.12 | 0.97 |
| 3 Rising | `VenusRising` | 3 | 0.30 | 0.65 | 0.38 | 0.88 |
| 4 Storm | `VenusStorm` | 9 | 0.70 | 0.88 | 0.72 | 0.72 |
| 5 Severe | `VenusSevere` | 18 | 1.00 | 1.00 | 1.00 | 0.55 |

The ladder moves one rung at a time, biased toward the mission's *target* rung
(`SetTargetLevel`), and `ForceLevel(rung, seconds, transition)` pins a set piece.

**Storm episodes.** When the rung is 3+ and the mission target is 3+, a rung change may
start an episode (`EpisodeChance` 0.30): the ladder climbs one rung at a time to a peak of
4 or 5, holds 35-80 s, and walks back down to where it started. Strike rate is multiplied
by `EpisodeStrikeBoost` (1.8). A 170 s cooldown follows. The whole thing is generated into
the seeded timeline, so it is identical on every peer.

**Lighting.** Colours live in the presets (warm, flat, dim orange-yellow at the bottom,
dark and sulphur-green at the top: sun power 0.40 -> 0.12). On top of them the director's
own Environment modifier adds continuous gloom (`GloomDim`, `GloomGreen`) so the light
slides between rungs instead of stepping with the preset crossfade, and the strike flash.
Fog ends are authored for the misn07 horizon (`VisibilityRange=100`) and CRWeather clamps
them to whatever horizon a map really has.

## 1. TRN lightning removed

`Missions/misn07.trn` no longer has a `[LightningBolt]` section (the file is otherwise
byte-identical, CRLF intact). All lightning comes from the director. misn07 is the only
Venus `.trn` in this repository. The stock Venus terrains in
`Battlezone_Source/BZ1/1.5/Battlezone_Install` that carry the same section are misn08,
misn09, misns1, misns2, mult01, multdm12, multdm29, multst02 and the `Edit/trn/venus.trn`
template; each needs the same one-block removal when it is ported to use the director.

## 2. Fog by altitude

`CRVenusMap.NewHeightScan` samples terrain height over the *playable* box (the BZN's
`edge_path` corners; `bounds` option overrides) on a 64x56 grid, inset 60 units so the
unreachable apron is never read. The scan is incremental (`ScanBudget` 160 queries per
frame, about 22 frames). `AnalyseBasins` then:

1. takes the lowest percentile of ground (22%, but never closer to the median than half of
   `minDepth`, so a map that is mostly one flat shelf does not fog the shelf);
2. keeps only cells that sit under their surroundings (the mean of a ring 220 units out
   must be 3+ higher), which separates enclosed lowland from open plain;
3. flood-fills the rest into clusters (8-connected, at least 6 cells);
4. places fog anchors greedily, lowest ground first, 110 units apart, with a share that
   grows with basin size and the list interleaved across basins by importance (cap 24).

At run time `StreamSites` keeps at most `MaxLiveFog` (6) `CR/Venus/FogPool` systems for the
anchors nearest the local player (create inside 520, destroy beyond 660, one creation per
second). Emission follows severity and basin depth, and the pool drifts and leans with the
wind.

Global fog follows altitude through the Environment modifier: `PoolFactor` is 1 at or below
the local pool level and falls to 0 over a band above it (taken from the map's own relief).
Fog end is scaled by up to `PoolFogEndScale` (0.62), start by `PoolFogStartScale` (0.55),
and the colour moves `PoolFogTint` (0.30) toward sulphur. The factor is smoothed
(`PoolResponse` 0.55/s) so a slope does not pop the fog.

Weather fog is clamped to the terrain horizon, so "clearer on the ridges" can only return
to the preset value, never exceed it.

**misn07 measurements** (from `Tools/Test-CRVenusWeather.lua`, real HG2): median ground
30.4 m, lowest 5.9 m, ridge (85th percentile) 71.5 m, **map pool level 20.5 m** (the
enclosed lowland floor sits at about 18-21 m), 21 enclosed basins, 24 anchors, 9 of them in
the central play area (x 1500-3700, z 98500-100500).

## 3. Lightning storms

A strike is a small state machine on every peer:

1. **Telegraph** (1.2-2.0 s): a `CR/Venus/StElmo` corona of cold sparks builds on the target.
2. **Impact**: `CR/Venus/Bolt` (a burst of leaning `CR_FX/Arc` cards, about 0.11 s) and
   `CR/Venus/BoltGlow` at the foot; the local scene flash; thunder after a distance delay;
   shove and radar scramble.
3. **Afterglow**: a struck generator keeps crackling for `PowerAfterglow` (3 s), as if it
   were harvesting the storm.

**Targets.** The host builds a weighted candidate list: each Lightning Power generator
`PowerWeight` 100, each exposed object (towers, turrets, comm masts by ODF name, anything
22+ m above the pool level) 2.5, and `GroundCandidates` (4) random ground points 35-210
units from a human player, 1 each. With three generators that is about 90% of strikes
(the test asserts at least 540 of 600), and the strike rate is also multiplied by
`PowerRateBoost` (1.6) while any generator exists. With no generators the other targets
are all that remains.

**Lightning Power ODFs** (all `classLabel = "powerplant"`, `unitName = "L-Power"`, in
`ODF/`): `ablpow`, `bblpow`, `cblpow`, `sblpow`, `sblpowa`, `sblpowb`. misn07 places three
`sblpow` (team 5). Edit `LightningPowerOdfs` to add more.

**Consequences, never damage.**

- Knockback within `KnockRadius` (70): a velocity impulse away from the strike, up to
  `KnockMaxSpeed` (16) at the epicentre with a quadratic falloff, `KnockLift` (22%) upward
  so hover craft are not driven into the deck, scaled by sqrt(1000 / mass) (heavy craft
  move less), and horizontal speed is never pushed past `KnockSpeedCap` (34) -- or past a
  craft's existing speed if it is already faster. Pilots on foot are skipped.
- Radar scramble within `ScrambleRadius` (110): `Environment.SetObjectScramble` for 3-5.5 s
  with radar range x0.10 and velocity jam x2.5, lapsing on its own. A second strike never
  shortens the first.
- The flash adds to ambient, diffuse and sun power for `FlashSeconds` (0.42) with a double
  flicker. Strength falls with the distance from the local player (full inside 160, 10% at
  1500+), so every peer sees its own flash.
- Thunder: the stock `lstart.wav` (verified in the Redux `StockODFFiles`; `thunder.wav` exists
  only in the ISDF Chronicles addon), delayed `distance / 340` seconds, heavier with
  playback rate 70%.

**Storm clouds.** Two camera-attached `CR/Venus/CloudDeck` layers at 38 and 62 units overhead
drift under slowly precessing, opposite forces and darken and green with `gloom`. They ride
the camera because the map's fog ends 56-100 units out: a deck at real cloud height would
be pure fog colour. Heat lightning (cosmetic sheet flashes, 0.14) fills the gaps between
strikes.

## 4. Sulfur

The terrain material under a point cannot be queried at run time, so
`Tools/Build-VenusSites.py` reads the `.mat` once (64x64 tiles per zone, zones row-major,
south first; base material bits 15-12, next material bits 11-8) and writes run-length
cells to `CRVenusSites07.lua`. The orientation was verified by correlating the zoned HG2
against BZN object elevations (r = 0.997 with `x = col*20`, `z = 97280 + row*20`).

misn07 `TextureType` labels: **0 Sulphur Deposits, 1 Liquid Sulphur, 2 Base, 3 Hardened
Sulphur, 4 Geyser.** Every one is "sulfur" in theme, but the cell census says:

| Index | Label | Cells (base) |
| ---: | --- | ---: |
| 0 | Sulphur Deposits | 65,201 (the whole map) |
| 1 | Liquid Sulphur | 335 solid, 734 including transition cells |
| 2, 3, 4 | Base, Hardened, Geyser | 0 |

Deposits are everywhere, so they cannot mark a place. **Index 1 (Liquid Sulphur)** is the
pool material: 335 solid cells plus 399 transition cells (weight 0.5) form two clusters
(centres about (3415, 99064) and (2443, 99992)), giving 12 emitter sites. Pass `--types 0,1`
or another list to the generator for a map that uses other indices.

At run time up to `MaxLiveSulfur` (8) `CR/Venus/SulfurPool` systems stream in inside 360 units
of the player: continuous steam plus a burp (`SulfurBurpRate` for 0.35 s) every 2.5-9 s,
more often in storms. A pool within 90 units of the player blurps audibly (`lburn1.wav`).

## 5. Volcanic vents

The converted `misn07.bzn` has 21 `eggeizr1` geyser objects. Several are clumps a few metres
apart (five of them around (2278, 99461)), so `MergeVents` (45 unit radius) folds them into
**16 sites**; two are named `volcano_geyz1` (2430, 99452, elevation 77) and `volcano_geyz2`
(2627, 99274) and are marked major. Up to `MaxLivePlumes` (6) `CR/Venus/Plume` systems
stream in inside 1000 units: a constant smoke column leaning with the wind.

Eruptions are scheduled by the host every 75-165 s (a major site is five times as likely to
be chosen) and last 14-26 s: an ash burst on the plume's second emitter, a short-lived
`CR/Venus/Embers` system, a rumble (`gquak00.wav`) and a blast (`r_exp3.wav`) scaled by
distance. Purely visual.

## 6. Acid rain

Visual only. A camera-attached `CR/Weather/Rain` (+ `RainSplash`) is driven by the smoothed
severity: rate = `RainMaxRate` (520) x the ladder's rain value, tinted sulphur-green, leaning
gently with the wind. Switch it off with `acidRain = false`. It is a director-owned layer
rather than part of the presets so it can follow severity continuously.

## 7. Render profiles

The director does not force a render profile (that is the player's `openshim.ini` choice,
`exu.RequestRenderProfile("inherit")` in PersistentConfig). It does write the
`depth_haze` render-effect intent (`exu.SetRenderEffectFloat`) every 2 s with a strength
that follows severity. OpenShim reports `not-implemented` for that effect today, so it is a
no-op until the renderer lands; `AllowRenderIntents = false` removes it.

## Co-op model

The mission runs only on the leader, and presentation events reach guests over misn06's
ordered, acknowledged stream (see `MISN06_COOP.md`). The director uses a **hybrid**, chosen
per thing by what it depends on:

| What | Decided by | Why |
| --- | --- | --- |
| Severity ladder, episodes, wind | Pure function of a **seed** (every peer computes it) plus the host's rung as a correction | Costs no traffic; a lost packet cannot freeze a guest's sky; frame-rate independent |
| Strikes: target, position, time | **Host**, sent as one event | The target depends on world state (which generators exist, where players are) that peers may not see identically |
| Eruptions: site, time, duration | **Host**, sent as one event | Same stream, same reason; keeps the sound and the plume in step |
| Knockback and radar scramble | **Every peer, for the craft it owns** | A craft is simulated on its owner's machine; a replica's velocity is overwritten by the owner and `Environment` refuses to write a replica's sensors |
| Fog pools, sulfur, rain, clouds, smoke, heat lightning | Local, from static map data | Cosmetic; only needs to look right on that screen |

Why not a pure seeded schedule for everything? Strike targets depend on the live object
list, and peers' mission clocks differ by the join delay. Why not pure host events for
everything? The ladder would then send a rung message on every change and a lost one would
leave a guest on the wrong weather until the next. The hybrid keeps the traffic to one small
event per strike (about one a second at the very worst) and still heals.

How the pieces fit:

- The host picks a seed in `Init` and announces `VenusState` (seven numbers) at start, on
  every rung / episode / target / forced-level change, and every 30 s as a heartbeat.
- A guest initialises with `authority = false` and **no seed**; it shows calm weather until
  the host's state arrives, rather than inventing a timeline that would diverge.
- A guest follows the host's rung for 45 s (1.5 heartbeats) after each state message and
  then falls back to the seeded timeline it has been computing all along. The test drops
  every state message after the first and the guest still agrees with the host to within a
  few seconds of the host's rung changes.
- `VenusStrike` carries the target position and the telegraph length. The guest starts its
  own telegraph on receipt, so impact lands a link-latency after the host's, well inside the
  1.2-2.0 s telegraph.
- The mission's target rung and forced level ride in `VenusState`, so `SetTargetLevel` and
  `ForceLevel` need no `Present` call of their own. They are no-ops on a guest.
- Offline solo is the host path with no sender: identical behaviour, nothing transmitted.

**Wire protocol.** All arguments are numbers (no tables, nothing larger than a few doubles;
a packet is well under the 244 byte guideline).

| Op | Arguments | When |
| --- | --- | --- |
| `VenusState` | `seed, clock, level, episode(0/1), target, forcedLevel(0=none), forcedFor` | start, on change, every 30 s |
| `VenusStrike` | `id, x, y, z, kind(1 power, 2 exposed, 3 ground), telegraphSeconds, power` | each strike |
| `VenusErupt` | `id, siteIndex, durationSeconds, power` | each eruption |

`siteIndex` indexes `GetVentSites()`, which is built deterministically from the same shipped
data on every peer. Late join still needs a restart, as in the other co-op missions;
`AnnounceState()` re-sends the state on demand for a guest that initialised after the first
announcement.

**Adapter hooks.**

| Hook | Use |
| --- | --- |
| `Init{ authority, seed, send, players, isLocal, sites, ... }` | `send(op, ...)` delivers an event to every guest; `players()` lists every human player's handle (strikes near players are chosen from all of them); `isLocal(h)` overrides the default `IsNetGame` / `IsLocal` ownership test |
| `ApplyNetEvent(op, ...)` | the guest receive path; returns true when handled; ignored on the host |
| `GetNetState()` / `ApplyNetState(...)` | the seven-number state, for a custom transport |
| `AnnounceState()` | host: re-send now |
| `SetNetwork{ send, authority, isLocal, players }` | change the above after `Init` |

## Integrating into misn07

`Scripts/misn07.lua` is being rewritten on `agent/misn07-coop`; this section is for whoever
wires it in. It follows `misn04.lua`'s weather lines and `misn06.lua`'s presentation
protocol.

```lua
-- 1. Requires
local CRVenusWeather = require("CRVenusWeather")
local VenusSites = require("CRVenusSites07")

-- 2. Presentation: let the stream carry the three Venus ops.
local VENUS_OPS = { VenusState = true, VenusStrike = true, VenusErupt = true }

local function ApplyPresentation(op, ...)
    ...
    elseif VENUS_OPS[op] then
        CRVenusWeather.ApplyNetEvent(op, ...)       -- ignored on the host
    ...
end

-- in ReceivePresentation, widen the accept test:
--   if seq == receivedEvent + 1 and (native[op] or VENUS_OPS[op] or op == "Resources") then

-- 3. Init (host, guest and offline). The host's own Present() would re-apply an event
--    locally, so the sender queues straight onto the stream instead.
local function InitVenusWeather()
    local net = CRCoop.IsNetworkGame()
    CRVenusWeather.Init({
        authority   = (not net) or CRCoop.IsAuthority(),
        seed        = M.venusSeed,                 -- nil: host/offline pick one, guests wait
        sites       = VenusSites,
        startLevel  = 1,
        targetLevel = 2,
        send = net and function(op, ...)
            events[#events + 1] = { op = op, args = { ... }, n = select("#", ...), expires = GetTime() + 5 }
        end or nil,
        players = net and function()
            local list = {}
            for h in AllCraft() do
                if CRCoop.IsHumanCraft(h) then list[#list + 1] = h end
            end
            return list
        end or nil,
    })
    if M.weatherState ~= nil and ((not net) or CRCoop.IsAuthority()) then
        CRVenusWeather.Load(M.weatherState)
        M.weatherState = nil
    end
    M.venusSeed = CRVenusWeather.Seed               -- survives a save (also inside Save())
end
-- Call it from the same place misn04 calls CRMarsWeather.Init, after Environment.Init
-- and after the presentation transport has been reset.

-- 4. Once the co-op session is ready (CRCoop.IsSessionReady() first true), on the host:
CRVenusWeather.AnnounceState()

-- 5. Per frame, where misn04 calls CRMarsWeather.Update
CRVenusWeather.Update(dt)

-- 6. Object creation hook (next to Environment.OnObjectCreated)
CRVenusWeather.OnObjectCreated(h)

-- 7. Save / cleanup
M.weatherState = CRVenusWeather.Save()             -- in the save path
CRVenusWeather.Shutdown()                          -- in mission cleanup

-- 8. Weather beats, host/offline only (guests no-op). No Present() needed.
CRVenusWeather.SetTargetLevel(3)                   -- e.g. once the alarm is raised
CRVenusWeather.ForceLevel(5, 100.0, 14.0)          -- set piece at the evacuation
```

Suggested misn07 beats from the stock port's state flags: target 2 on the approach, 3 when
`alarm_on` / `detected`, 4 at `start_evac`, `ForceLevel(5, 100, 14)` at the evacuation set
piece, back to 2 after `rendezvous`.

Do not also call `CRMarsWeather` or `Environment.TriggerDustStorm` in the same mission.

## Tunables (top of `CRVenusWeather.lua`)

| Group | Names |
| --- | --- |
| Switches | `AllowFogPools`, `AllowAltitudeFog`, `AllowLightning`, `AllowKnockback`, `AllowRadarScramble`, `AllowFlash`, `AllowClouds`, `AllowAcidRain`, `AllowSulfur`, `AllowVents`, `AllowEruptions`, `AllowSensorDegrade`, `AllowEpisodes` (also `Init` options `fogPools`, `lightning`, ...) |
| Budgets | `MaxSystems` 36, `MaxLiveFog` 6, `MaxLiveSulfur` 8, `MaxLivePlumes` 6, `MaxLiveStrikes` 3, stream in/out distances |
| Ladder | `SeverityRate`, `EpisodeChance`, `EpisodePeak`, `EpisodeHold`, `EpisodeCooldown`, `EpisodeStrikeBoost`, the `Levels` table |
| Fog | `ScanColumns/Rows/Budget/Inset`, `PoolFogEndScale`, `PoolFogStartScale`, `PoolFogTint`, `PoolFogColor`, `PoolBand`, `PoolResponse`, `FogDensity` |
| Lightning | `TelegraphSeconds`, `PowerWeight`, `ExposedWeight`, `GroundWeight`, `PowerRateBoost`, `LightningPowerOdfs`, `ThunderSound` / `ThunderSpeed` / `ThunderRate` |
| Consequences | `KnockRadius`, `KnockMaxSpeed`, `KnockLift`, `KnockSpeedCap`, `ScrambleRadius`, `ScrambleSeconds`, `ScrambleRadarRange`, `ScrambleVelocJam` |
| Flash / light | `FlashNear/Far/Floor`, `FlashAmbient`, `FlashDiffuse`, `FlashSunBoost`, `FlashSeconds`, `GloomDim`, `GloomGreen` |
| Co-op | `NetHeartbeat` 30, `HostOverrideSeconds` 45 |

## EXU capabilities that do not exist (and what was done)

Checked against `ExtraUtilities/Definitions/ExtraUtils.lua`:

| Wanted | Reality | Workaround |
| --- | --- | --- |
| A line / beam / ribbon / billboard chain for the bolt | `exu.DrawLine` and `DrawBox` are documented placeholders that draw nothing | A burst of leaning `oriented_self` `CR_FX/Arc` cards in a tall Box emitter |
| A dynamic point light for the flash | Only lights on existing objects (`SetLightPosition`, `SetLightPowerScale` ...) | Ambient + sun spike through the Environment modifier |
| The terrain material under a point | None | Offline `Build-VenusSites.py` reads the `.mat` once |
| Sky-plane alpha / a sky tint | `SetSkyPlane` needs a material that does not exist; the Venus sky material is an unlit shader (`Effect_fragment`), so pass colours would not darken it | Sky darkening comes from fog, light and the cloud deck. A `CR_Sky/VenusStorm` art asset (or an OpenShim sky-tint intent) would complete it |
| Positional thunder | `StartSound` without a handle is 2D | Delay by distance, volume by distance |
| Camera shake | None in EXU; stock `StartEarthquake` exists | Not used (the brief asked for visual-only vents) |
| Soft particles / depth haze | OpenShim intent ABI exists but reports `not-implemented` | Intent written; no effect yet |
| Per-craft radar scramble | The gameplay modifier is global | `Environment.SetObjectScramble` (added), on the existing sensor path so it cannot be clobbered or mis-captured |

## Shipping and admin notes (for the main session)

- New shipped file: `Materials/cr_venus.particle.payload`. Changed shipped files:
  `Missions/misn07.trn`, `Scripts/CRWeatherPresets.lua`, `Scripts/CRParticleTemplates.lua`,
  `Scripts/Environment.lua`. New scripts: `CRVenusWeather.lua`, `CRVenusMap.lua`,
  `CRVenusSites07.lua`. `Shipping/shipping.lock.json` needs the normal `-bless`; nothing was
  blessed, deployed or published here.
- The payload is loaded through `CRParticleTemplates.EnsureExtra("cr_venus")`, not added to
  the base list, so a build without it degrades (presets, flash, thunder, shove and
  scramble all still work) instead of breaking every weather mission.
- `python Tools/Validate-CampaignRepository.py` and `lua5.1 Tools/Test-CRVenusWeather.lua
  Scripts` pass; the Mars, haboob, volcano, Venus-dense, fog-horizon and parameter tests
  still pass.

## What must be judged live

- The bolt: whether leaning `CR_FX/Arc` cards read as lightning, their size and burst
  length (`CR/Venus/Bolt` `particle_width/height`, emitter `depth`, the 900 / 420 rates).
- Box-emitter axes: the templates assume `direction` is the depth axis (vertical when
  `direction 0 1 0`). If a column comes out sideways, swap `width/height/depth`.
- Affector parameter spellings used live (`force_vector`, `colour1`, `colour2` on the
  ColourInterpolator). `CRWeather.DescribeSystem(name)` prints what Ogre really exposes.
- The cloud deck at 38 / 62 units under 56-100 unit fog: visible or washed out.
- Fog pooling strength on misn07's flat 18-21 m floor, and `PoolBand`.
- Knockback feel against hover physics (`KnockMaxSpeed`, `KnockLift`), especially for the
  player's tank and heavy haulers, and in co-op for a guest's craft.
- Telegraph length versus real link latency; `TelegraphSeconds` can grow if guests see late
  telegraphs.
- Strike frequency and the generator share on the real mission, and flash intensity next to
  the preset ambient (the preset ambient is already dim, so the flash is additive).
- Whether `lstart.wav` (the stock lightning clip) reads as thunder at rate 70, and the
  volume against music.
- Eruption scale and the density of the minor vent plumes.
- Sulfur burp frequency and steam colour.
- Total particle cost with every layer up; `MaxSystems` and the per-layer caps are the knobs.
