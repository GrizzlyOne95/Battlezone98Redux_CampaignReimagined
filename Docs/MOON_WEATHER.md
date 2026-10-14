# Moon weather and atmosphere director

`Scripts/CRMoonWeather.lua` is the Moon counterpart of `CREuropaWeather`, `CRIoWeather`,
`CRVenusWeather` and `CRMarsWeather`. It is reusable by any Moon mission; the first users are
misn02b "Red Arrival" and misn03 "Eagle's Nest" (both `planet = "moon"` in `Config/crcampgn.ini`).

The target is the owner's concept art: a black starfield and a crisp Earth over a dark surface,
with **a pale grey-blue mist lying only along the ground** - knee to waist high on a soldier -
fading out over the surface, foreground rocks poking through it. The sky and the Earth are not
touched.

**It has no gameplay effect at all** (see "Gameplay-effect statement"). It is purely visual,
host-authoritative and peer-identical like the other directors.

| File | Role |
| --- | --- |
| `Scripts/CRMoonWeather.lua` | The director. Every tunable is at the top of the file. |
| `Scripts/CRVenusMap.lua` | Shared pure half (seeded rng, `DeriveSeed`, `SmoothStep`). Reused as is, not edited. |
| `Scripts/CRMoonSites02b.lua`, `Scripts/CRMoonSites03.lua` | Generated map data (mist anchors in low ground, playable bounds). |
| `Tools/Build-MoonSites.py` | Regenerates a `CRMoonSites<NN>.lua` from a mission's `.hg2`, `.trn` and `.bzn`. Pure Python, byte-reproducible. |
| `Materials/cr_moon.particle.payload` | Four particle templates, all on existing `CR_FX/*` materials. Loaded through `CRParticleTemplates.EnsureExtra("cr_moon")`. |
| `Tools/Test-CRMoonWeather.lua` | Isolated-peer tests against an exu / BZ mock, including the no-gameplay audit. |

The shared files are untouched except for appended, marked regions: `.github/workflows/campaign-validation.yml`
(one step, `# CR Moon weather >>`), `CHANGELOG.md` (one bullet), `Shipping/shipping.lock.json` (four entries,
inserted in place, `count` bumped), and the two mission scripts (`-- CR Moon weather >>` regions, see
"How the missions wire it"). `CRWeather`, `CRWeatherPresets`, `Environment` and every Venus file are
not edited, and no particle file other than the new payload is touched.

## Physics rationale

The Moon has no atmosphere, so there is no wind, no cloud, no rain, no storm and no sound. What is
real, and what the director draws:

- **Levitated dust.** Surveyor's cameras photographed a glow along the horizon after sunset, thought to
  be electrostatically levitated dust a few tens of centimetres to metres above the surface. That is the
  ground mist: thin, slow, very low, pooling in low ground and thinning over ridges.
- **Regolith kicked up in 1/6 g.** An impact or a thruster blast throws fine dust ballistically. With no
  air it does not billow; it travels in clean arcs, hangs for seconds and settles slowly. That is the impact
  dust and the hover dust.
- **Glow periods.** The levitated layer is not constant. Rarely, slowly, it thickens a little and
  catches more light for a minute or so, then fades.

## Why global fog is not touched

Both Moon missions keep the map's own atmosphere: `FogStart=175 FogEnd=250 VisibilityRange=250 Intensity=90
Ambient=0`, a black sky. In DX11 Enhanced the authored fog range scales terrain diffuse IBL
(`Docs/DX11_FOG_LUNAR_ART_DIRECTION_RECONSTRUCTION.md`), so raising global fog to get a mist would wash
the terrain and grey the black sky. The mist is therefore **ground-hugging particles only**.

Ownership (`Docs/WEATHER_ENVIRONMENT_OWNERSHIP.md`) is kept: the director never calls an exu fog, ambient,
sun or diffuse function, and does not use `CRWeather` at all (a CRWeather preset blends fog, ambient and
sun toward absolute values, and in a mission without Environment it writes the renderer itself every frame).
Where `Environment.lua` is loaded the director registers a modifier (`"CRMoonWeather"`) that adds a **tiny
ambient lift during a glow and nothing else**: fog, diffuse, specular and sun power pass through
unchanged (the suite asserts this by value).

**misn02b and misn03 do not load Environment**, deliberately: loading it would start its 15-minute
day/night cycle (and its night radar nerf) and replace the map's 175-250 fog with the moon preset's
420-1120 on maps that have neither today. So in those missions the glow is expressed in the mist itself:
more emission, brighter and slightly more opaque cards. A future Moon mission that does load Environment
gets the small ambient lift on top, with no code change.

## The layers

### 1. Ground mist (pools, from map data)

`CR/Moon/GroundMist`: flat cards (`billboard_type perpendicular_common`, `common_direction 0 1 0`, the
same trick as `CR/VenusGroundHaze`) from a 44 x 1.3 x 44 Box emitter lifted to `MistHeight` (0.85) above
the ground, so the sheets spread over 0.2-1.5 above it. Flat cards keep the mist a thin layer instead of a
column of camera-facing puffs. Cards are 34 units wide, live 18-28 s, drift at 0.04-0.26 units/s, and
fade in and out through a `ColourInterpolator` (peak alpha 0.11).

Pools are streamed like Europa's frost haze: the nearest of `sites.mist.pools` inside `PoolStreamIn` (330)
becomes a system, at most `MaxLivePools` (5) at once, destroyed beyond `PoolStreamOut` (430). Each is placed
on `GetTerrainHeightAndNormal` at its centre.

### 2. Local mist (follows the player)

`CR/Moon/LocalMist`: one system with 13 Box emitters (a centre cell, an inner ring of 6 at 40 units, an
outer ring of 6 at 92 units rotated 30 degrees). The system is parked on the player's ground height and
moved with them; twice a second each emitter is put on its own sampled terrain patch and given a weight:

```text
weight = flatness(slope) * clamp(LocalBaseWeight + (ground ring average - patch height) / LocalDepthForFull, 0, 1)
```

"Ground ring average" is the mean height of 8 samples on a ring of `LocalReferenceRadius` (170). A patch
**below** its surroundings (a bowl, a crater floor) gets more mist; a patch **above** them (a ridge, a hilltop)
gets less; steep ground (`LocalSlopeStart` 5 to `LocalSlopeEnd` 18 degrees) carries no sheet. (Comparing patches
only with each other would just move mist between them: their depths sum to zero by construction. The suite
pins bowl > level ground > hilltop and steep ground ~ 0.) Particles are left behind in world space, so a moving
player crosses a continuous blanket. Fog distance is 250, so the layer reaches ~95 units and the pools carry
the mist beyond that.

### 3. Glow

A seeded, slow timeline (`GlowFirst` 150-320 s, then `GlowGap` 240-600 s of calm between glows; each glow
rises over 18-32 s, holds 20-55 s, falls over 24-45 s, strength 0.45-1.0). Over two hours that is roughly
10-14 glows with the mist glowing under a quarter of the time (the suite measures it). While a glow runs:

- emission rises by up to `GlowRateBoost` (+45 %);
- the cards brighten toward `GlowColor` (`GlowColorMix` 0.7) and gain up to `GlowAlphaLift` (0.05) alpha, written
  through the template's `ColourInterpolator` (`colour1` / `colour2`, throttled by `GlowColorEpsilon`);
- if Environment is loaded, ambient rises by at most `GlowAmbient` (0.008 / 0.012 / 0.020).

`Glow(duration, strength)` (host) scripts one on cue; it rides the same envelope. There is also a slow
**breath** (`BreathDepth` +/-15 %, `BreathPeriod` 340 s) on the whole layer, a pure function of clock and
seed (no random draws), and `SetDensity(0..2)` to thin or thicken the mist for a set piece (eased at
`DensityRate`).

### 4. Impact dust

`exu.BulletHit` is a single global that `PhysicsImpact` and `CRReactive` also use, so the director **chains**:
whatever was installed runs first, unchanged, in a `pcall`; ours runs after. A strike whose position is within
`ImpactMaxHeight` (4.5) of the ground and within `ImpactRange` (420) of the player puts a pooled
`CR/Moon/KickDust` system (a Point burst for `ImpactBurstSeconds` 0.18 s at `ImpactRate` 150/s, particles
ejected in a 58 degree cone at 0.7-3.4 units/s with a gentle -0.45 force so they hang, 6-10 s lifetime) on the
ground at the strike. At most `MaxImpactSystems` (6) systems, `ImpactMinInterval` 0.12 s between puffs,
no second puff within 3 units / 0.4 s. On `Shutdown` the previous handler is restored if ours is still on top;
if something chained on top of us the wrapper goes inert instead of ripping their handler out.

**What the hooks cannot do.** BZ explosions (a craft dying) are not objects or callbacks the Lua layer can see,
so a destroyed craft raises no dust of its own; only the ordnance impacts that kill it do. `DeleteObject` fires
after the position is gone. If a later engine hook exposes explosion events, call `NotifyImpact(x, y, z)`.
Impact dust is local and per peer (each peer's own ordnance callbacks), like muzzle FX.

### 5. Hover dust

Every `HoverInterval` (0.25 s) the director looks at craft within `HoverTrackRange` (130) of the player and
tracks the nearest `MaxHoverSystems` (4) that qualify: below `HoverMaxHeight` (7) and moving faster than
`HoverMinSpeed` (2.5), or (for `HoverIdleGrace` 6 s after they last moved) hovering within
`HoverIdleMaxHeight` (3) at `HoverIdleShare` of the rate. A craft that has never moved (a gun tower that
counts as a craft) emits nothing. `CR/Moon/HoverDust` is parked on the ground under each, flat Box, low outward
cone, 4-8 s lifetime. The player's own craft counts. A craft that stops qualifying goes quiet and loses its
system after `HoverLinger` (4 s).

## Co-op model

Identical in shape to Europa's, with less on the wire. Weather is host-authoritative; only the host's
authority and seed matter.

| What | Decided by | Why |
| --- | --- | --- |
| Glow timeline, breath phase | A pure function of a **seed** (every peer computes it) | No traffic; frame rate and player position cannot change it (the suite checks 10 Hz vs 2 Hz and different players) |
| Seed, clock, density target | **Host**, `MoonState` at start, on change, every 30 s | A guest adopts the seed and snaps its clock when it drifts more than 2 s |
| A scripted glow | **Host**, one `MoonGlow` event | Every peer glows at the same moment |
| Mist pools, local layer, impact dust, hover dust | Local, from static map data and the peer's own terrain / craft | Cosmetic; only has to look right on that screen |

A guest with no seed yet shows the baseline mist and no seeded glow until `MoonState` arrives. The timeline uses
independent seeded streams (`DeriveSeed` salts 31 glow, 32 breath phase), never `math.random` (only the host's
initial seed pick uses it).

**Wire protocol.** All arguments are numbers.

| Op | Arguments | When |
| --- | --- | --- |
| `MoonState` | `seed, clock, density` | start, on change, every 30 s, `AnnounceState()` |
| `MoonGlow` | `id, strength, durationSeconds` | each scripted glow |

Duplicate ids are ignored, strength and duration are clamped on receipt, a state with no seed is refused, the host
ignores both ops. Both ops ride the mission's existing ordered, acknowledged presentation stream.

## How the missions wire it

Both missions follow the misn12 / Europa recipe, in marked `-- CR Moon weather >>` regions:

- `require("CRMoonWeather")`, `require("CRMoonSites02b" | "CRMoonSites03")` and `MOON_OPS = { MoonState, MoonGlow }`
  at the top; `MOON_OPS` is accepted by `ReceivePresentation`'s op test and routed first in `ApplyPresentation`.
- `InitMoonWeather` (lazy, first frame after the session is ready, host: seed from `M.moonSeed` or fresh;
  `send` queues onto the mission's `events` stream), `UpdateMoonWeather(dt)` (every frame on every peer; the host
  also calls `AnnounceState()` once when the session is ready), `ShutdownMoonWeather` (at `Start`).
- `Save` stores `M.moonWeatherState` (plain scalars, host / offline); the next `InitMoonWeather` calls `Load`.
- The mist keeps updating during the result countdown.
- **No Environment, no CRWeather, no beats.** The seeded timeline does the work; a mission that wants a set piece
  calls `CRMoonWeather.Glow(...)` / `SetDensity(...)`.

```lua
-- any other Moon mission
local CRMoonWeather = require("CRMoonWeather")
local MoonSites = require("CRMoonSites<NN>")     -- python -I Tools/Build-MoonSites.py misn<NN>
CRMoonWeather.Init{ authority = (not net) or CRCoop.IsAuthority(), seed = M.moonSeed, sites = MoonSites,
                    send = net and function(op, ...) --[[ queue on the presentation stream ]] end or nil }
-- ready (host): CRMoonWeather.AnnounceState()
-- every frame:  CRMoonWeather.Update(dt)
-- save / load:  M.moonWeatherState = CRMoonWeather.Save() / CRMoonWeather.Load(M.moonWeatherState)
-- cleanup:      CRMoonWeather.Shutdown()
```

## Public API

Host / offline unless noted; a guest's call is ignored.

| Call | Notes |
| --- | --- |
| `Init{ authority, seed, send, sites, density, enabled, debug, quality, groundMist, localMist, glow, randomGlow, impactDust, hoverDust, environmentGlow }` | `send(op, ...)` delivers an event to every guest. `seed = nil` on a guest waits for the host. `sites = false` is fine (local mist only). |
| `Update(dt)` | every frame, every peer (real-clock dt like the other directors) |
| `Shutdown()` | destroys every system, unregisters the modifier, restores `exu.BulletHit` |
| `Save()` / `Load(state)` | plain scalars and any glow in flight; systems do not survive a save |
| `SetDensity(scale)` | 0..2 (1 = authored), eased |
| `Glow(duration, strength)` | 4..300 s, 0..1 |
| `NotifyImpact(x, y, z)` | one puff of impact dust (every peer, local) - what the `BulletHit` hook calls |
| `AnnounceState()` | re-send `MoonState` (host; call once the session is ready) |
| `ApplyNetEvent(op, ...)` | guest receive path, returns true when handled; the host ignores both ops |
| `GetNetState()` / `ApplyNetState(...)` / `SetNetwork{send, authority}` | custom transport |
| `Tune(name, value)` | override a tunable by name at run time (type-checked), for live tuning |
| `OnObjectCreated(h)` | present for adapters that forward every object; does nothing |
| getters | `GetGlow IsGlowing GetDensity GetMistScale GetBreath GetPools GetLivePoolCount GetGlowWindows GetStats GetSystemCount GetLocalPatches GlowAt(t) Describe` |

## Tunables (top of `CRMoonWeather.lua`)

| Group | Names |
| --- | --- |
| Switches | `AllowGroundMist`, `AllowLocalMist`, `AllowGlow`, `AllowRandomGlow`, `AllowImpactDust`, `AllowHoverDust`, `AllowEnvironmentGlow` (also `Init` options), `Quality` |
| Budgets | `MaxSystems` 24, `MaxLivePools` 5, `MaxImpactSystems` 6, `MaxHoverSystems` 4, `PoolStreamIn/Out` 330 / 430 |
| Mist | `MistHeight`, `MistColor`, `MistAlphaA`, `MistAlphaB`, `PoolRate`, `PoolWeightPower`, `LocalRate`, `LocalInnerRadius`, `LocalOuterRadius`, `LocalOuterRateScale`, `LocalInterval`, `LocalBaseWeight`, `LocalReferenceRadius`, `LocalDepthForFull`, `LocalSlopeStart`, `LocalSlopeEnd` |
| Density | `DensityDefault`, `DensityLimit`, `DensityRate`, `BreathDepth`, `BreathPeriod` |
| Glow | `GlowFirst`, `GlowGap`, `GlowRise`, `GlowHold`, `GlowFall`, `GlowStrength`, `GlowLookahead`, `GlowRateBoost`, `GlowAlphaLift`, `GlowColor`, `GlowColorMix`, `GlowAmbient`, `GlowScriptedDefault`, `GlowDurationLimit` |
| Impact dust | `ImpactMaxHeight`, `ImpactRange`, `ImpactRate`, `ImpactBurstSeconds`, `ImpactMinInterval`, `ImpactSpotRadius`, `ImpactSpotSeconds`, `ImpactLift` |
| Hover dust | `HoverInterval`, `HoverTrackRange`, `HoverMaxHeight`, `HoverMinSpeed`, `HoverFullSpeed`, `HoverRate`, `HoverIdleShare`, `HoverIdleMaxHeight`, `HoverIdleGrace`, `HoverLinger` |
| Co-op | `NetHeartbeat` 30, `ClockSnapSeconds` 2 |

Lua is authoritative for mist colour and alpha: the director rewrites the template's `colour1` / `colour2` when a
system is created, so edit `MistColor` / `MistAlphaA` / `MistAlphaB`, not the payload's colours. Particle size,
thickness (Box `height`), lifetime and drift live in `Materials/cr_moon.particle.payload`.

## In-game tuning checklist

Nothing has been seen on screen. Use the same viewpoints as the concept art (a low third-person or
first-person view across level ground, Earth in frame, a rock in the foreground), then in this order:

1. **Is there any mist, and is it flat?** Stand on level ground in misn03 / misn02b. If nothing is visible, check
   `GetSystemCount()` is > 0 (templates loaded) and raise `MistAlphaA` (0.11) and `LocalRate` (0.8). If the sheets
   look like thin slivers or vanish at grazing angles, the flat cards are edge-on: switch `CR/Moon/LocalMist` and
   `GroundMist` to `billboard_type point` and reduce `particle_width` / `particle_height` to ~8-10 (puffier, camera
   facing), or raise `MistHeight` a little.
2. **Height.** The concept has the mist at knee to waist of a soldier. `MistHeight` (0.85) centres the layer; the
   band is +/- 0.65 (the Box thickness 1.3). Too tall: lower `MistHeight`, and shrink `height 1.3` in the payload.
   Too low (rocks and tanks stand clear of it): raise `MistHeight` to ~1.2.
3. **Density.** Thin overall: `SetDensity` / `DensityDefault`, then `PoolRate` (1.15) and `LocalRate` (0.8). Too
   heavy: reduce `MistAlphaA` / `MistAlphaB` first (the cards stack), then the rates. Too much like a wall: lower
   `LocalBaseWeight` (0.35) so only low ground carries it.
4. **Colour.** `MistColor` is pale grey-blue (0.64 / 0.72 / 0.84). The reference mist is cooler and darker toward the
   distance, lit by Earthshine; push toward blue-grey (lower `r`, keep `b`) or darker (all down together) as needed.
5. **Low ground vs ridges.** In a crater it should pool; on a crest it should thin. Tune `LocalDepthForFull` (6 m:
   smaller = more contrast) and `LocalBaseWeight`. On slopes, `LocalSlopeStart` / `LocalSlopeEnd` decide where sheets stop.
6. **Coverage.** If a mist edge is visible around the player, widen `LocalOuterRadius` (92) or raise
   `LocalOuterRateScale`; if the pools pop in, raise `PoolStreamIn` (330) (watch `MaxLivePools`).
7. **Glow.** Wait for one (first at 150-320 s) or call `CRMoonWeather.Glow(60, 1)`. It should be barely noticeable:
   the mist a little thicker and brighter. Adjust `GlowRateBoost`, `GlowAlphaLift`, `GlowColorMix`; to see more of it
   shorten `GlowFirst` / `GlowGap`.
8. **Sky and Earth untouched.** The sky must stay black and the Earth crisp: if either changes, something other than
   this director is at fault (it never writes fog or light).
9. **Impact and hover dust.** Fire at the ground, drive low. Puff too small / short-lived: payload `particle_width`
   (3.4), `ImpactRate`; too hangy or too ballistic: the `LinearForce` in the payload (-0.45; lunar gravity is -1.6).
   Hover dust too heavy: `HoverRate`; shown on idle craft you do not want: `HoverIdleShare` 0.
10. **Cost.** Watch the frame rate in the busiest scene: the caps are `MaxSystems`, `MaxLivePools`,
    `MaxHoverSystems`, `Quality`.

If the Lua console / harness can run code, `CRMoonWeather.Tune("MistHeight", 1.2)` takes effect within a second; the
rest are edits to the file's top block.

## Gameplay-effect statement

**None.** Specifically, the director never calls: any damage / health / ammo function, `Set/Add/Kill`,
`SetVelocity`, `SetPosition`, `BuildObject`, `RemoveObject`, `SetTeamNum`, `SetPerceivedTeam`, `Attack` / `Goto` /
`SetCommand`, any objective call, `StartSound`, any earthquake call, `exu.SetRadarRange`, `exu.SetRadarPeriod`,
`exu.SetVelocJam`, `Environment.SetObjectScramble`, `Environment.RegisterGameplayModifier`, any gravity / cloak
call, and any exu fog, ambient, sun or diffuse writer. What it calls: `exu` particle create / destroy / position /
rate / affector-parameter functions, and read-only BZ queries (`GetTime`, `GetPlayerHandle`, `IsValid`,
`GetPosition`, `GetVelocity`, `AllCraft`, `GetTerrainHeightAndNormal`, `SetVector`). It assigns `exu.BulletHit`
(chained, restored on `Shutdown`).

`Tools/Test-CRMoonWeather.lua` audits this by wrapping every stubbed BZ and exu function:

- every global called is in an allowlist of read-only queries; every exu call is in an allowlist of particle calls;
- 59 forbidden BZ names (damage, teams, perception, objectives, sound, earthquake, mission end ...) are stubbed to
  record any call, and none was made on the host, a guest, across a busy session with strikes, glows, a save and a
  load;
- the stubbed `exu.SetFog` / `SetAmbientLight` / `SetSunDiffuse` / `SetSunPowerScale` were never called, with and
  without an Environment mock; the Environment modifier changes only ambient and leaves fog, diffuse, specular and
  sun power identical to 1e-9;
- no craft moved and no team changed; the director's source (comments stripped) never mentions 24 dangerous names
  and never mentions `CRWeather`;
- a **mutation check** inserts a forbidden BZ call, an `exu.SetFog`, an `exu.SetRadarRange` and an unlisted global
  into the director and asserts the audit catches each.

## Capabilities that do not exist (and what was done)

| Wanted | Reality | Workaround |
| --- | --- | --- |
| Dust from a destroyed craft's explosion | No explosion event reaches Lua; `DeleteObject` fires after the position is gone | Only ordnance impacts (`exu.BulletHit`) kick dust; `NotifyImpact` is ready for a future hook |
| Soft particles / depth fade against rocks | OpenShim intent reports `not-implemented` | The cards are alpha-faded and thin; where a card meets a rock the intersection is hard. Raising `MistHeight` slightly, or lowering alpha, hides it |
| A dynamic point light for the glow | Only lights on existing objects | The mist itself brightens; an optional ambient lift only where Environment is loaded |
| The terrain material under a point | None at run time | Terrain height and slope are sampled (`GetTerrainHeightAndNormal`); anchors come offline from the heightfield |
| A real day/night + mist in these two missions | They do not load Environment; loading it would change fog and lighting | Not done on purpose (see above) |

## Shipping and admin notes (for the main session)

`Shipping/shipping.lock.json` has the four new entries, inserted in place with `count` bumped (2339 to 2343); the
normal `-bless` at merge time is still the authority. The payload is loaded through `EnsureExtra("cr_moon")`, not
added to the base list, so a build without it degrades (no mist, no dust, a log line) instead of breaking the
mission. `lua5.1 Tools/Test-CRMoonWeather.lua Scripts` and a generated-data drift check are one step in
`campaign-validation.yml`; `Tools/Test-Misn02bCoop.lua` / `Test-Misn03Coop.lua` pin the mission wiring (guests are
not authoritative, the host announces once, a glow reaches each guest exactly once, the state is saved).

Regenerate the data (the converted `.bzn` / `.hg2` / `.trn` are read from `Missions/`):

```text
python -I Tools/Build-MoonSites.py misn02b
python -I Tools/Build-MoonSites.py misn03 --depth-full 30     # misn03's craters are deep; the default 16 saturates
```

How the anchors are chosen (see the generator's docstring): average the heightfield into 20-unit cells; depth =
mean height within 180 units minus the cell's height; flatness falls from 4 to 14 degrees; score = clamp(depth /
`--depth-full`) x flatness; greedy pick, best first, >= 64 units apart, inside the playable box (objects and AI
paths, padded 420), at most 120. The height scale (0.1 per raw count) and sample spacing (5 units) were measured by
correlating the BZN's object heights against the field (r = 0.999 on misn03).

New files:

```text
Scripts/CRMoonWeather.lua
Scripts/CRMoonSites02b.lua
Scripts/CRMoonSites03.lua
Materials/cr_moon.particle.payload
Tools/Build-MoonSites.py
Tools/Test-CRMoonWeather.lua
Docs/MOON_WEATHER.md
```

## What must be judged live (not verified)

Everything visual. No game was run for this change.

- Whether the flat cards read as a ground mist from the player's eye height (and at the third-person angle), or sit
  edge-on and vanish; whether `CR_FX/Haze` at alpha 0.11 and 34 / 30 unit cards is the right softness and size.
- `MistHeight` / thickness against a soldier and against a tank; where the layer meets rocks (hard intersection).
- The colour of the mist against the black sky and the Earth, and the glow's strength (it is meant to be subtle).
- Whether the local layer's edge (about 95 units) and the pool pop-in are visible.
- The impact and hover dust: size, amount, the `-0.45` hang, and whether hover dust under idle craft is wanted.
- Particle cost in the busiest battle (misn03 defence waves), and `Quality`.
- That `exu.BulletHit` fires in these two missions (it is what `CRReactive` relies on in the weather missions; the Moon missions
  load neither it nor `PhysicsImpact`). If it does not, impact dust is simply absent; the rest is unaffected.
- Co-op with real link latency (the suite uses 120 ms).
