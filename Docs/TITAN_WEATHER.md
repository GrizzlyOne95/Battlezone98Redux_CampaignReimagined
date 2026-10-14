# Titan weather and atmosphere director

`Scripts/CRTitanWeather.lua` is the Titan counterpart of `CREuropaWeather`, `CRIoWeather`,
`CRVenusWeather` and `CRMarsWeather`, and follows the same architecture (seeded ladder, host-decided
replicated events, generated map data). It is reusable by any Titan mission; the first user is misn14
"The Three Beacons", which is being reworked on `agent/misn14-fury-rework` and wires the director
through its own guarded hook (see "How misn14 calls it"). This change does **not** edit any mission script.

**It has no gameplay effect at all.** It never damages, shoves, scrambles, slows, spawns, removes,
retargets or re-teams anything. It does not touch radar, velocity jam, AI perception, cloaks, stealth or
objectives, registers no Environment modifier of either kind, and calls no exu fog / light setter. The only
state it writes is render state: a CRWeather preset (fog and light go through CRWeather, which contributes
through `Environment.lua` when the mission loads it and owns the renderer when it does not), particle
systems, and one render-only StaticGeometry sheet for the liquid surface (not a game object: no collision,
radar, AI path or targeting). Reading craft positions is the only thing it asks of the simulation.
`Tools/Test-CRTitanWeather.lua` audits this by wrapping every stubbed BZ and exu function.

| File | Role |
| --- | --- |
| `Scripts/CRTitanWeather.lua` | The director. Tunables are at the top of the file. |
| `Scripts/CRVenusMap.lua` | Shared pure half (seeded rng, ladder). Reused as is. |
| `Scripts/CRTitanSites14.lua` | Generated map data for misn14 (wet mask, 160 pool anchors, bounds). |
| `Tools/Build-TitanSites.py` | Regenerates a `CRTitanSites<NN>.lua` from a mission's `.trn`, `.mat`, `.hg2`, `.bzn`. |
| `Materials/cr_titan.particle.payload` | Six particle templates on existing `CR_FX/*` materials, loaded through `CRParticleTemplates.EnsureExtra("cr_titan")`. |
| `Shaders/cr_methane.hlsl`, `Shaders/cr_methane.program`, `Materials/cr_methane.material` | The liquid-methane surface shader (SM4 / SM3) and its per-map materials (section 5). |
| `Tools/Build-MethaneSurface.py` | Writes the surface sheet mesh, the ripple normal map and each map's wet-mask texture (`--check` in CI). |
| `Assets/ModelFixes/cr_methane_plane.mesh`, `Assets/Textures/cr_methane_ripple.png`, `Assets/Textures/cr_titan14_wet.png` | Its generated assets. |
| `Tools/Test-MethaneShader.ps1` | Compiles every shader delegate with fxc and cross-checks the program and material parameters. |
| `Scripts/Environment.lua` | Now detects Titan and has a `titan` world preset (below). |
| `Tools/Test-CRTitanWeather.lua` | Isolated-peer tests against an exu / BZ mock (934 assertions). |

## 1. The Environment fix

**What was wrong.** `DetectWorldPreset` only knew `moon` (palette / `.trn` / mission-name hints
`moon luna europa io selene apollo misn02b misn03`) and returned `earth` for everything else. Every stock
Titan `.trn` (misn14, misn15, misn15b, misn16, misn16b, misns5-8 and six multiplayer maps) names
`Palette=TITAN.ACT`, `[Atlases] MaterialName = ti_detail_atlas` and `SkyTexture = titan.map`; none of those
contains a moon hint, so a Titan map that loaded Environment got the **earth** preset: the stock
`Intensity=50` / `Ambient=0` as flat grey light, Environment's default fog colour, and a full 15-minute day /
dusk / night cycle with the night sensor nerf.

**What it does now.**

- `DetectWorldPreset` checks Titan first: palette or sky texture containing `titan`, an atlas starting `ti_`,
  a `.trn` or mission filename containing `titan`, or (fallback for a converted map whose `.trn` lost them) a
  stock Titan mission name `misn14 misn15 misn16 misns5-8`. Earth and moon detection are unchanged (tested).
- `ApplyWorldPreset("titan")`: warm haze-scattered light with floors under the stock zero ambient
  (ambient >= `0.34 0.23 0.11`, diffuse >= `0.86 0.60 0.30`, orange specular), a low sun
  (`DaySunDirection 0.78 -0.36 -0.51`, glaring in from just above the horizon), `DaySunPowerScale 0.95`,
  `DayShadowFarDistance 700`, an amber day fog (`0.60 0.35 0.11`, the stock Titan palette fog `0.573 0.314 0.090` measured live, a touch lighter, at 85 %) that **keeps the `.trn`'s own fog
  range** (misn14: 50-175 under a 250 horizon), and dimmer, never-black dusk / night keyframes.
- **The cycle is held at day** (`Environment.LockDaylight`, set by the titan preset). Titan's day is sixteen
  Earth days long, so a fifteen-minute night has no business there; and no night means no night sensor nerf,
  so a Titan mission that starts loading Environment for weather does not quietly gain a gameplay change.
  `Environment.TitanAllowNight = true` before `Init` restores the ordinary cycle. `LockDaylight` is a public
  field any mission may set for any world.

No Titan mission on `main` loads Environment today (misn14-16 and misns5-8 do not), so this changes nothing
in shipped play until a mission opts in. The director does not need Environment (it runs on CRWeather's
standalone path), and misn14 should not load Environment just for the director.

## 2. Physics rationale

Titan has a 1.5 bar nitrogen atmosphere at about 94 K under a thick orange photochemical haze, gravity of
0.14 g, very weak surface winds, and an active methane cycle: rain falls rarely, as large drops at walking
pace, and liquid methane lies in lakes and soaks the lowlands. What the director draws:

- **Haze.** Amber fog and warm, dim, flat light; the sky is the brightest thing in view. Haze thickens and
  thins slowly (the ladder) and occasionally a thicker bank rolls over (rolls).
- **Methane drizzle.** Sparse, fat, slow streaks (11-16 units/s), only on the Drizzle and Shroud rungs.
- **Wet methane.** The sea floor and the ponds between the islands are liquid: a reflective surface
  (section 5) mirrors the haze and glares toward the low sun, low evaporation mist hangs over it, drizzle
  rings it, and craft crossing it throw a slow, hanging spray.

## 3. The ladder

Four rungs, a smoothed fractional position (`SeverityRate` 0.035 rungs/s) driving every continuous rate, and
integer rungs selecting a CRWeather preset. Same machinery as Europa / Io (`CRVenusMap.NewLadder`, with
temporary **episodes** from rung 3 up to rung 4).

| Rung | Preset | Fog (colour, start-end) | Diffuse / sun | Drizzle | Haze bank | Sheen | Mist | Ripples | Roll scale |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 Still | `TitanStill` | `0.60 0.35 0.11`, 52-190 | `0.86 0.60 0.30` / 1.00 | - | x0.50 | x1.00 | x0.80 | 0 | x0.60 |
| 2 Hazy | `TitanHazy` | `0.59 0.34 0.11`, 46-178 | `0.78 0.54 0.27` / 0.92 | - | x0.90 | x0.90 | x1.00 | 0 | x1.00 |
| 3 Drizzle | `TitanDrizzle` | `0.56 0.33 0.11`, 40-165 | `0.64 0.45 0.24` / 0.80 | 55/s | x1.00 | x0.75 | x1.20 | 1.00 | x0.80 |
| 4 Shroud | `TitanShroud` | `0.54 0.31 0.10`, 28-150 | `0.56 0.38 0.20` / 0.72 | 30/s | x1.50 | x0.60 | x1.40 | 0.55 | x1.40 |

Each rung has a **Roll variant** (`TitanStillRoll` ...): the same layers with fog pulled in (start x0.55,
end x0.70), deepened 30 % toward `0.66 0.38 0.12`, and the light dimmed (diffuse and sun x0.80, ambient
x0.90). All eight presets are registered into `CRWeatherPresets.Presets` at `Init`, idempotently; the shared
`CRWeatherPresets.lua` is not edited. No preset sets a sky (the map's own `titan.map` dome, Saturn and the
`acloud2` deck stay), lightning or gusts. Wind is `0.10 -1 0.04` at speed 2: the drizzle leans only slightly.

**Fog and DX11 Enhanced.** The Enhanced terrain shader scales terrain diffuse IBL by
`saturate(160 / (fogEnd - fogStart))` (`OSE_TERRAIN_IBL_REFERENCE_FOG_RANGE`, `openshim_enhanced_terrain`).
Every Titan preset keeps `fogEnd - fogStart <= 160` (138, 132, 125, 122; the roll variants are shorter still),
so terrain IBL stays saturated exactly as with stock misn14 (range 125). The test asserts it. CRWeather also
clamps every fog end to the map's terrain horizon (`VisibilityRange` 250). Mood comes from colour, light and
particles, not from cranking fog distance.

## 4. Events and layers

### Haze rolls (host-decided, replicated)

`Roll(duration, strength)`: 5-240 s, 0..1 (defaults 60 s at 0.8). An envelope (rise 25 %, fall 35 %) of
strength drives the haze-bank rate (up to x2.6) and pool mist (up to x2); while the envelope is at least
`RollPresetThreshold` (0.2) the rung's preset is swapped for its Roll variant with a 10 s crossfade, so the
fog pulls in and the light dims smoothly and comes back. A roll during a roll extends it. Random rolls: gap
170-380 s divided by the rung's roll scale, duration 40-95 s, strength 0.45-1.0, at least 45 s apart.

### Haze bank (local)

`CR/Titan/HazeBank`, camera-attached 1 unit up: large (20-unit) faint amber cards drifting slowly with the
weak wind across a 360 x 14 x 360 box (kept low: cards overhead read as tiles). `HazeRate` 10/s x the rung's haze x (1 + 1.6 x roll).

### Methane pools (local, from map data)

Up to `MaxLivePools` (6) anchors within 380 units of the local player (out at 500), each three systems:

| Template | What | Rate |
| --- | --- | --- |
| `CR/Titan/PoolSheen` | flat (`perpendicular_common`, normal up) 38-unit pale-gold cards 0.45 over the liquid, alpha 0.26-0.30 | `PoolSheenRate` 1.3 x pool weight x rung sheen, x `SurfaceSheenScale` (0.30) while the surface is up |
| `CR/Titan/PoolMist` | low (2 units) faint evaporation haze | `PoolMistRate` 1.4 x weight x rung mist x (1 + roll) |
| `CR/Titan/PoolRipple` | small flat additive rings | `PoolRippleRate` 55 x rung drizzle (0 when dry) |

Rates are re-sent once a second and only when they change.

### Splashes (local)

Five times a second, every craft (and the local player) within 230 units of the local player is checked:
speed from position deltas (no velocity query), the generated wet mask (`IsWet`), and height above the liquid
(<= 7 units, so a flyer does not splash). Up to `MaxSplashes` (4) of the fastest get a `CR/Titan/Splash`
system that is moved under the craft every frame (`SetParticleSystemPosition`); `local_space false` leaves
the droplets already thrown behind, so the spray trails as a wake. Droplets rise 3-7 units/s, hang under a
`-6` force (thick air, 0.14 g) and fade. Rate 90/s x (0.25 + 0.75 x speed factor), speed 3-24 units/s. A
slot whose craft stops or dies is silenced, and destroyed after 8 idle seconds.

## 5. Wet methane "tied to the MAT painting"

### What the misn14 data actually says

Investigated with the stock files from `bzone.zfs` and the zone-major `.mat` / `.hg2` readers the Io /
Europa / Misn11 tools already use (Base in the high nibble; height = low 13 bits x 0.1, 5 units per sample):

- Titan `.trn` labels: `TextureType0 // Methane Ocean` (atlas tiles `TI00SA0`, `TI00SB0`, orange ground),
  `TextureType1 // Base` (misnamed `ti00s*` in stock; the real panels are `TI11*`, never painted on misn14),
  `TextureType3 // Rock` (`TI33*`). Transitions `TI01*` / `TI03*`.
- **Type 0 covers 95 % of misn14** (62,303 of 65,536 cells; 58,956 pure). So the tile type alone cannot
  mark a lake: the raised orange ground around the bases is the same `TI00` tile.
- The variant / rotation nibbles are uniformly random (the usual anti-tiling scatter), and only `*A0` / `*B0`
  exist in `ti_detail_atlas.csv`, so nothing about a lake is encoded per tile.
- **The heightfield is the key.** The median *and* the minimum height of the map is 5.0 (raw 50): misn14 is a
  dead-flat methane sea floor with rock islands rising out of it. 57,233 of the 58,956 pure methane cells
  lie exactly on it; the rest is raised methane ground. The flat floor forms one open sea plus 15 small
  enclosed ponds / channels between the islands (74 cells).

So the MAT painting does mark the liquid, in combination: **a wet cell is a pure Methane Ocean cell (Base and
Next nibble both type 0, so a methane-to-rock shore tile is never wet) whose four HG2 samples lie on the sea
floor** (within 0.3 units of the most common type-0 height). That is exactly what `Tools/Build-TitanSites.py`
writes into `CRTitanSites14.lua`: the wet mask as run-length rows for the rows near the playable box
(26,509 cells), and 160 pool anchors on wet ground inside the box, scored by the wet fraction of their 5x5
neighbourhood and by closeness to a shore (lakes weighted x1.35), greedy best-first at least 80 units apart.

### The liquid surface (built)

The liquid is a real surface now: one flat sheet laid over the sea through EXU StaticGeometry and shaded by
a CR shader ported from the WATER kind of ISDF Chronicles' `isdfc_surface.hlsl`. The particle sheen
stays as a faint layer over it (x0.30), with the mist, drizzle ripples and splashes.

| Piece | What |
| --- | --- |
| Placement | `exu.CreateStaticGeometry("cr_titan_methane", "cr_methane_plane.mesh", "CR/Titan/Methane<NN>", ...)`: one instance of a unit 16 x 16 grid, centred on the terrain and scaled to it (misn14: 5120 x 5120), at sea level + `SurfaceLift` (0.35; wet cells lie within the generator's 0.3 tolerance, and at 0.06 the floor's relief poked through in patches live). Not a game object: no collision, radar, AI path or targeting; no shadow cast. Every peer lays the same sheet from the same static data, so nothing is sent. EXU converts the position to Redux's render space (z mirrored), so the sheet's `v` runs south. |
| Coverage | The shader clips the sheet to a wet-mask texture (`cr_titan14_wet.png`, 512 x 512: each 20-unit cell of the `CRTitanSites14` wet rows becomes 2 x 2 texels, Gaussian-blurred, row 0 north) through a smoothstep, so the shore is rounded rather than the cell grid; terrain standing above the liquid hides it by depth, so dry raised ground and islands stay opaque terrain. |
| Look | Premultiplied blend (`one one_minus_src_alpha`): the floor shows through the liquid, darkened along the view path (longer at grazing angles); Fresnel (F0 0.02, n ~ 1.29) mirrors a sky that is the fog colour at the horizon rising to an amber zenith; a wide glare lobe and a brighter core round the low sun; warm glints on the ripples; two scrolling layers of a tileable ripple normal map for wind chop; procedural expanding rings for drizzle; bumps fade with distance. Stock lighting loop and stock depth fog (the DX11 validator keeps distance-based fog to the two Enhanced world shaders); the layer also fades with fog so the floor's own fog carries the distance. |
| Controls | The ladder drives four floats through `exu.SetMaterialPassColors(material, { diffuse = {drizzle, glare, wetness, chop}, specular = hazeSun })` on technique 0 pass 0, once a second and only on change: drizzle rings = the rung's drizzle; glare = the rung's `glare` (1.00 / 0.85 / 0.60 / 0.45) x (1 - 0.55 x roll); chop 0.45-0.85 with severity. The pass colours are not colours here, so the shader reads the raw (power-scaled) light colours, not Ogre's `derived_*` ones, which multiply by them. |
| Low sun | misn14 does not load Environment, and its stock sun stands almost overhead (`GetSunDirection` -0.17 -0.98 0 live), which would put every reflection of it under the camera. The glare and the sun's glint therefore follow a "haze sun" the director names (`SurfaceHazeSun`, Environment's titan `DaySunDirection` 0.78 -0.36 -0.51, Ogre space) sent in the pass specular colour; the material bakes the same value. It changes no light: shading and shadows still use the scene's sun. |
| Degrade | No `exu.CreateStaticGeometry`, no `exu.MaterialExists` or the material not loaded (never risked: a missing material would draw the sheet flat white), no terrain extent, or a create that raises: the surface stays off, the reason is printed once and kept in `GetSurface().reason`, and the full particle sheen stays. A create that fails as "too early" (no render origin yet) is retried every 5 s up to 3 attempts. Without `SetMaterialPassColors` the sheet keeps the material's calm defaults. DX9 runs the SM3 delegate; OpenGL has no delegate (no GLSL twin), so the material falls through to an invisible technique and only the particles show. The glow scheme draws nothing. |
| Lifecycle | Laid at `Init`, rebuilt on `Load` (the scene is rebuilt; EXU replaces a stale record by name), removed by `Shutdown` and by the fault stand-down. |

Cost: one draw of a 512-triangle sheet; fragments outside the mask are clipped, and the pixel shader is
about 380 SM3 instruction slots (8 lights).

### What remains native (OpenShim)

| Gap | Why it is not in CR |
| --- | --- |
| Wetness inside the terrain shader (darkened, glossy wet ground on shores, maps whose lakes are not one flat level) | The DX11 Enhanced terrain shader is OpenShim's (`Docs/ENHANCED_SHADER_OWNERSHIP.md`), and its roughness floor (`OSE_TERRAIN_PBR_MIN_ROUGHNESS` 0.56) blocks a reflective term from CR material constants. The flat sheet covers misn14 because its sea is dead flat; a sloped or multi-level lake needs either several sheets or the terrain term: a per-map wet mask bound to the terrain material as a new alias and sampled by world `xz`, a per-pixel roughness floor near 0.08 and F0 0.02 where wet with the static-IBL specular let through, edge feathering over one cell, and an `exu.SetRenderEffectFloat("terrain_wet", "strength", ...)` intent so the director can scale it. |
| Shadows on the liquid | The sheet is a transparent pass and does not sample the PSSM maps; craft shadows fall on the floor under it and read through the liquid. A receiving variant would need the stock PSSM inputs (units 4-6) and testing on both backends. |
| Real sky / Saturn in the reflection | No sky or IBL texture of the map is reachable from a CR material (Enhanced's IBL cubemaps are a neutral studio); the reflection is the fog-to-zenith gradient plus the sun glow. |
| Screen-space sun glare (bloom) | Not reachable from Lua (no lens / bloom API; a camera-attached particle cannot hold a world direction). A `sun_glare` render intent (bloom round the projected sun, tinted by fog colour, strength from the director) is the follow-up; the liquid's glare covers the near term. |
| OpenGL | No GLSL twin was written (no validator on this machine); add one with glslang validation if GL matters. |

## 6. Co-op model

| What | Decided by | Why |
| --- | --- | --- |
| Haze ladder, episodes | Pure function of a **seed** (every peer computes it) plus the host's rung as a correction | No traffic; a lost packet cannot freeze a guest's sky |
| Haze rolls: time, duration, strength | **Host**, one event each | Every peer's fog pulls in together |
| Haze bank, pools, ripples, splashes | Local, from static map data and replicated craft positions | Cosmetic; at most a frame apart between peers |

**Wire protocol.** All arguments are numbers.

| Op | Arguments | When |
| --- | --- | --- |
| `TitanState` | `seed, clock, level, episode(0/1), target, forcedLevel(0=none), forcedFor` | start, on change, every 30 s |
| `TitanRoll` | `id, strength, durationSeconds` | each roll |

Duplicate roll ids are ignored, values are clamped on receipt, the host ignores an echoed roll, and a
malformed event is dropped with a log line rather than raised. A guest with no seed shows the calm rung until
`TitanState` arrives, follows the host's rung for 45 s after each message, then falls back to the seeded
timeline it has been computing. The roll scheduler uses its own seeded stream (`DeriveSeed` salt 21), host-only.

**Fault containment.** `Init`, `Update`, `Load` and `ApplyNetEvent` run under `pcall`. A caught error is
logged; after `MaxFaults` (3) the director destroys its systems and stands down for the rest of the mission
(the test feeds it a corrupt site table and asserts it never raises). This matters because a Lua error can
alert-close an MP host.

## 7. Public API

Host / offline unless noted; a guest's call is ignored.

| Call | Notes |
| --- | --- |
| `Start(seed, sites, options)` | Shorthand for an offline / host `Init`; `seed = nil` picks one. Returns the seed. |
| `Init{ authority, seed, send, sites, startLevel, targetLevel, enabled, debug, quality, baseSky, drizzle, hazeBank, rolls, randomRolls, pools, poolMist, ripples, splashes, episodes, surface, surfaceMaterial }` | `send(op, ...)` delivers an event to every guest. `seed = nil` on a guest waits for the host. |
| `Update(dt)` | every frame, every peer (real-clock dt like the other directors) |
| `Shutdown()` | destroys every system and shuts CRWeather down (it restores the captured baseline fog / light) |
| `Save()` / `Load(state)` | plain scalars |
| `SetTargetLevel(n)` | 1..4, the rung the timeline trends toward |
| `ForceLevel(n, seconds, transition)` / `ReleaseForcedLevel()` | pin a rung for a set piece |
| `Roll(duration, strength)` | one haze roll now; returns true if it began |
| `AnnounceState()` | re-send `TitanState` (host; call once the session is ready) |
| `ApplyNetEvent(op, ...)` | guest receive path; true when handled |
| `GetNetState()` / `ApplyNetState(...)` / `SetNetwork{send, authority}` | custom transport |
| `OnObjectCreated(h)` | forwards to CRWeather |
| `IsWet(x, z)` | static-data query, any peer |
| `GetSurface()` | `{ up, reason, material, controls = { drizzle, glare, wetness, chop } }` |
| `RegisterPresets()`, `GetPresetNames()` | preset registration, idempotent |
| getters | `GetLevel GetLevelName GetTargetLevel IsEpisode GetSeverity GetRollIntensity IsRolling GetRoll GetPools GetLivePoolCount GetSplashCount GetStats GetSystemCount Describe` |

## 8. How misn14 calls it

misn14 does not load Environment and should not start to for this. Single-player (today's misn14):

```lua
-- CR Titan weather >>
local CRTitanWeather = require("CRTitanWeather")
local TitanSites = require("CRTitanSites14")
local titanStarted = false

local function UpdateTitanWeather(dt)
    if not titanStarted then
        titanStarted = true
        M.titanSeed = CRTitanWeather.Start(M.titanSeed, TitanSites, { startLevel = 1, targetLevel = 2 })
        if M.weatherState ~= nil then CRTitanWeather.Load(M.weatherState); M.weatherState = nil end
    end
    CRTitanWeather.Update(dt)
end
-- Update():  UpdateTitanWeather(dt)
-- Save():    M.weatherState = CRTitanWeather.Save()
-- cleanup:   CRTitanWeather.Shutdown()
-- CR Titan weather <<
```

Co-op (the misn12 / misn13 Europa pattern, with Titan names):

```lua
local TITAN_OPS = { TitanState = true, TitanRoll = true }
-- ApplyPresentation: if TITAN_OPS[op] then return CRTitanWeather.ApplyNetEvent(op, ...) end
-- ReceivePresentation accept test: (native[op] or TITAN_OPS[op] or ...)

CRTitanWeather.Init({
    authority   = (not net) or CRCoop.IsAuthority(),
    seed        = M.titanSeed,         -- nil: host/offline pick one, guests wait for TitanState
    sites       = TitanSites,
    startLevel  = 1,
    targetLevel = 2,
    send        = net and function(op, ...) --[[ queue on the presentation stream, no handles ]] end or nil,
})
-- host, once the session is ready: CRTitanWeather.AnnounceState()
-- every peer, every frame:         CRTitanWeather.Update(dt)
-- host save:                       M.weatherState = CRTitanWeather.Save(); M.titanSeed = CRTitanWeather.Seed
```

Suggested beats (host / offline only; all optional):

```lua
CRTitanWeather.SetTargetLevel(2)      -- once the player is moving
CRTitanWeather.Roll(70, 0.9)          -- a haze bank rolling in as the Furies first appear
CRTitanWeather.ForceLevel(3, 120, 15) -- drizzle over a set piece
CRTitanWeather.SetTargetLevel(1)      -- on the win
```

Do not also run another planet director or `Environment.TriggerDustStorm` in the same mission. misn16b,
misn15 and misns5-8 can use the director the same way once their sites file is generated (below).

## 9. Tunables (top of `CRTitanWeather.lua`)

| Group | Names |
| --- | --- |
| Switches | `AllowDrizzle`, `AllowHazeBank`, `AllowRolls`, `AllowRandomRolls`, `AllowPools`, `AllowPoolMist`, `AllowRipples`, `AllowSplashes`, `AllowEpisodes`, `AllowSurface` (also `Init` options `drizzle`, `hazeBank`, ..., `surface`) |
| Surface | `SurfaceLift`, `SurfaceSheenScale`, `SurfaceChop`, `SurfaceWetness`, `SurfaceRollGlareCut`, `SurfaceHazeSun`, `SurfaceMaterialPrefix`, `SurfaceRetrySeconds`, `SurfaceMaxAttempts`, the rung `glare`; look values in `Materials/cr_methane.material` (`$body`, `$sky`, `$surface`, `$waves`, `$glare`, `$glint`, `$extent`) |
| Budgets | `MaxSystems` 26, `MaxLivePools` 6, `MaxSplashes` 4, `PoolStreamIn/Out` 380 / 500 |
| Ladder | the `Levels` table (haze / sheen / mist / drizzle / rollScale / duration per rung), `SeverityRate`, `Episode*` |
| Presets | `PRESET_ROWS` (fog colour and range, ambient, diffuse, sun, drizzle rate, transitions), `ROLL_FOG_*`, `ROLL_LIGHT` |
| Rolls | `RollGap`, `RollSeconds`, `RollStrength`, `RollMinSpacing`, `RollRise`, `RollFall`, `RollPresetThreshold`, `RollTransition`, `HazeRollBoost`, `PoolMistRollBoost` |
| Haze bank | `HazeRate`, `HazeOffset` |
| Pools | `PoolSheenRate`, `PoolMistRate`, `PoolRippleRate`, `PoolSheenHeight`, `PoolMistHeight`, `PoolRippleHeight` |
| Splashes | `SplashRange`, `SplashMinSpeed`, `SplashFullSpeed`, `SplashRate`, `SplashMaxClearance`, `SplashHeight`, `SplashIdleSeconds` |
| Templates | colours, sizes and alphas in `Materials/cr_titan.particle.payload` |
| Environment | the `ApplyTitanPreset` / `BuildTitanFogKeyframes` values in `Environment.lua`, `TitanAllowNight`, `LockDaylight` |

## 10. Tests

`lua5.1 Tools/Test-CRTitanWeather.lua Scripts` (in `campaign-validation.yml`, "Test weather"):

1. misn14 data: labels, sea level 5, 58,956 methane cells, wet < methane, lakes exist, every anchor wet and
   inside the box, sorted, at least 80 apart.
2. Environment: a stock misn14 `.trn` selects `titan`, warm non-black light, amber fog keeping 50-175, IBL
   range, low sun, no night over a full cycle; `TitanAllowNight` restores the cycle; Mars stays earth, moon
   stays moon, `misn16b` name fallback works.
3. Presets: eight, idempotent, amber, IBL range <= 160, fog end >= 100, drizzle only on rungs 3-4 and sparse
   and slow, roll variants pull fog in and dim the sun.
4. Determinism: same seed gives identical rungs, presets and roll events over 40 minutes; another seed differs.
5. Co-op: a seedless guest waits, follows the host's seed, schedules no rolls, receives every roll exactly once,
   drops duplicates and echoes, ignores its own `Roll()`, survives malformed events.
6. Pools stream in near the player within budget, sit on the liquid, ripple only when drizzling, stream out.
7. Splashes: only a moving craft on wet ground gets a wake (parked, flying-over-liquid and dry-ground movers
   do not); the wake sits on the liquid, silences when the craft stops, is destroyed when idle, survives the
   craft dying.
8. Standalone (no Environment): CRWeather owns the renderer and the fog is amber and horizon-clamped.
9. Save / load continues the same timeline.
10. No payload: presets still run. Corrupt data: the director never raises and stands down.
11. Payload: every template exists, uses a material declared in `CR_reactive.material`, has one emitter.
12. Audit on every peer of the run: no forbidden BZ call, only allowlisted globals, no sensor / gravity / team
    exu call, gameplay scales identity, no gameplay modifier, no per-craft scramble, no Environment modifier
    from the director, radar values written back unchanged.
13. Surface: one sheet with the right mesh, material, centre, height and scale, no shadow; controls on
    technique 0 pass 0 (no rings when dry, rings and less glare in drizzle, a roll dims the glare, unchanged
    values not re-sent, the haze sun in the specular colour); the sheen scaled by `SurfaceSheenScale`;
    `surface = false`; each missing piece (no StaticGeometry, material not loaded, a raising create) leaves the
    full particle sheen and sends no controls, and an unloaded material never reaches `CreateStaticGeometry`;
    no `SetMaterialPassColors` keeps the sheet; a too-early create retries, a failing one stops after three;
    no terrain extent lays nothing; load rebuilds, shutdown and stand-down remove; host and guest lay
    identical sheets.
14. Surface assets: the base and misn14 materials, wet-mask alias, every referenced program declared, three
    techniques (liquid, glow, fallback), mesh / textures / shader present, every `param_named` declared in the
    shader, every file in the shipping lock.

`powershell -File Tools/Test-MethaneShader.ps1` (in `dx11-shader-validation.yml`) compiles every delegate with
fxc (`vs_4_0`/`ps_4_0` with `SM4=1`, `vs_3_0`/`ps_3_0`, warnings as errors) and fails when a default param
names a constant a delegate strips, when a kept constant has no default and no material value, or when the
material sets an undeclared parameter (checked against a deliberately broken program and material).
`python -I Tools/Build-MethaneSurface.py --check` (in "Test weather") regenerates the mesh, ripple map and
wet mask in memory and compares them (PNG pixels, not bytes).

Mutation checks run while writing it: an always-true `IsWet`, a missing clearance test, a removed host echo
guard, and an unlocked Titan cycle each make it fail.

Regenerate / check the data (needs the toolbox and a Redux `bzone.zfs`; not run in CI because the stock map
files are not in the repository):

```text
python -I Tools/Build-TitanSites.py misn14 --zfs "<Redux>\bzone.zfs"
python -I Tools/Build-TitanSites.py misn14 --zfs "<Redux>\bzone.zfs" --check
```

## 11. Live validation

Run 2026-10-14 on a scratch instance (`C:\BZRCoop\titanwx`, a copy of the GOG install with this branch's
`CRTitanWeather`, `CRTitanSites14`, `Environment`, `CRWeather*`, `CRVenusMap`, `CRParticleTemplates` and the
payload staged into its `mods\3686673790`), DX11 Enhanced, windowed 1920x1080 (the RDP client area captured at
1268x513). The stock `misn14.bzn` was converted to text and listed as a temporary `instant_action` mission
`tiwx.bzn` with `msn_filename = tiwx.bzn` and `[AiMission] name = LuaMission` (with the stock
`Misn14Mission` name the native misn14 logic runs instead of the Lua). A fixture script moved the player to the
westmost pool anchor, built camera pods and a wading tank, and stepped the director through every rung. Nothing
was added to the GOG install.

Confirmed in game:

- `cr_titan.particle.payload` parses; every template instantiates (19-20 systems live: haze bank, 6 pools x 3,
  one wake); no particle or material error in `BZOgreLogfile.log`; no Lua error.
- Sea level: `GetTerrainHeightAndNormal` at the anchor returns 5.00, the generated `sea.level`.
- Environment on the real `misn14.trn`: `preset=titan palette=titan.act lockDaylight=true`.
- Stock misn14 fog is `0.573 0.314 0.090`, start 50; the presets apply as authored (`TitanStill` 0.600/0.350/0.110
  from 52, `TitanDrizzle` 40, the `DrizzleRoll` variant pulled to 22, `TitanShroud` 28).
- Pools stream nearest-first (42, 103, 114, 170, 184, 190 m) and hold at the cap of 6; the drizzle, roll and
  shroud transitions run; a tank driven across the liquid gets a wake that trails behind it.
- **Bug found and fixed by the run:** `GetPosition` returns a `VECTOR_3D` userdata, not a table. The first run's
  `type(p) == "table"` check (copied from the Europa / Io / Moon directors) made every position nil, so no pool
  ever streamed and no craft could splash. `PositionOf` now reads the fields under `pcall`, and the test mocks
  positions as userdata (the old code fails it). The other directors carry the same check; that is flagged as a
  separate task, not changed here.

Screenshots (outside the repository, in the session scratchpad `titanwx\shots\`): `before_*` (stock, no
director), `still_*`, `drizzle_*`, `roll_*`, `splash_1..3`, `shroud_*`, `env_*` (Environment titan preset alone).

Judged from the captures, for the owner to tune:

- The haze and roll read as intended (`roll_*`); the sheen reads as a faint, slightly cool pale patch on the
  liquid rather than gold (Enhanced lighting desaturates it) and could take a warmer colour or higher alpha.
- The `.trn` backdrop strip (`BackdropDistance 400`) shows as a flat darker-orange band above the fogged ground in
  every capture, stock included; fog colour cannot hide it because the backdrop is drawn past the terrain fog.
- The wake is small at 14 units/s and reads better with more droplets (`SplashRate`) or larger cards.
- The olive square in `drizzle_low_east` is the camera pod mesh (the fixture camera sat 2.5 units over a pod), not
  a weather artifact.
- Not covered: co-op with real latency, cost in a busy battle, save / load in game, other Titan maps.

## 12. Shipping notes

`Shipping/shipping.lock.json` gains three entries, inserted in place with `count` bumped (the normal
`-bless` at merge time is still the authority): `Materials\cr_titan.particle.payload`,
`Scripts\CRTitanSites14.lua`, `Scripts\CRTitanWeather.lua`. The payload loads through
`EnsureExtra("cr_titan")`, not the base list, so a build without it degrades to presets only. The
templates owe the usual in-game smoke before a release (Ogre skips a malformed particle script silently);
section 11 covers the one live run.
