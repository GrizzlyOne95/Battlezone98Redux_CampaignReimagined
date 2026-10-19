# Mission 18 storm (CRStorm18)

Weather, ground cover and environment FX for mission 18, where the player has
destroyed the Fury transport's cores and the moon tears itself apart. New files
only for the storm itself; nothing here edits `misn18.lua` or the map. The module is
wired into the co-op port by `CRMisn18.lua` exactly like `CRJungle17` in `CRMisn17`, plus
one leader-side call, `SetPhase`, and the quake routing below (see also
[`MISN18_COOP.md`](MISN18_COOP.md), which owns the mission-side contract). **Nothing has been rendered yet**: every visual claim below is
host-tested for its logic and unverified on screen (see the smoke list at the end).

## The world

The stock `misn18.trn` is the **Achilles** world, the same one misn17 paints:
`SkyTexture = achilles.map`, `ACHILLES.ACT/LUM/TBL/ALB`, `ac*` ground tiles
(type 0 grass, 1 trees, 2 rock, 3 river, 5 base), cloud art `acloud2.map`,
`VisibilityRange = FogEnd = 250`. The map is x 0..2560, z 97280..102400; terrain
type 1 covers 92 % of it. Positions come from the stock `misn18.bzn` and its paths:
player start and recycler near (1900, 98050); the stranded transport and its four
thrusters at (1533, 100892) in a basin 90 m below the start plateau. The terrain is
green and wooded, so the storm turns it into a dying world rather than assuming a
barren one: the ground cover is dead scrub, the sky red.

## Phase table

`Storm.SetPhase(name)` is called on the leader only, in mission order. It never steps
backward; `won` and `lost` hold the `final` look (and `lost` after `won` is refused).

| # | Phase | Level | Wind m/s | Lightning (s) | Quake pulses (s, strength) | Landslides (s) | Cracks | Tornado |
|---|-------|------:|---------:|---------------|----------------------------|----------------|-------:|---------|
| 1 | opening | .14 | 6-12 | 26-48, 80 % dry | 50-85, .10 | | 0 | |
| 2 | search | .26 | 16 | 16-30, 65 % dry | 32-58, .14 | | 0 | |
| 3 | found | .40 | 22 | 10-19, 45 % dry | 22-40, .22, rumble .03 | | 0 | |
| 4 | core1 | .54 | 28 | 7-13 | 16-28, .30, rumble .06 | 70-100 | .12 | |
| 5 | core2 | .68 | 33 | 4.5-9 | 11-20, .40, rumble .10 | 45-70 | .32 | |
| 6 | core3 | .82 | 39 | 2.8-5.5 | 7-13, .52, rumble .16 | 28-45 | .58 | |
| 7 | collapse | .96 | 44 (+30 % spike) | 1.4-3 (0.5-1.1 for 9 s) | 3.5-7, .70, rumble .30 | 12-20 | .85 | yes |
| 8 | final | 1.00 | 46 | 0.7-1.8 | 2.5-4.5, .90, rumble .45 | 6-11 | 1.0 | yes |
| 9, 10 | won, lost | hold 8 | | | | | | |

Wind is `6 + 40 * level` with a slow swing in bearing (255 degrees +-40) and gusts.
"Dry" lightning is a cloud flash and distant thunder with no ground strike.

### Collapse is the cinematic entry

The co-op branch plays the `transdestroyedcam` cinematic (6-10 s, every peer) when the
fourth thruster dies, and calls `SetPhase("collapse")` at its start; the 180 s countdown
starts when it ends. Collapse therefore ramps hard inside the shot: the weather blends in
over 4 s, the level eases at `trans / 3`, the leader sends an immediate hard quake, a
strike within 0.3 s, a 9 s burst of a strike every 0.5-1.1 s, a landslide within 2.5 s
and the funnel spawns and grows over 10 s. Wind spikes 30 % for the burst. Cracks and
slides are built around each peer's camera, which is at the transport during the shot.
`final` (countdown <= 30 s) is the peak on top of that.

## Effects and how they are built

All guarded; no EXU means less storm, never an error.

| Effect | Implementation | Authority |
|--------|----------------|-----------|
| Palette, fog, light | 8 presets `Misn18Storm1..8` built at load into `CRWeatherPresets.Presets`; `Weather.SetPreset(name, trans)`. Fog capped at the 250 m horizon and kept mild (heavy global fog greys DX11 Enhanced); the near-field dark-red haze system carries the gloom | visual, peer-local |
| Wind, dust, ash, cinders, debris, streaks | CRWeather camera volumes from `CR18/*` templates (`cr18_storm.particle.payload`); `SetWindOverride` | visual |
| Sky | `SetSkyPlane("CR18/StormSwirl", ...)` fitted to 0.15 x far clip like `Weather.lua`; tiling 24. `cr18_swirl.program` samples the cloud alpha twice, turning in opposite directions about the zenith (spiral twist from pass specular), plus a third layer driven by `SetMaterialTextureScrollAnimation` / `SetMaterialTextureRotateAnimation`. Palette, density and glow-from-below ride the pass colours (`SetMaterialPassColors`: ambient = base, diffuse = cloud, emissive = pulsing glow, specular.r = twist). Reads POSITION and UV only (no COLOR0) | visual |
| Lightning | leader `bolt` events; each peer draws a channel near its own camera (`CRGroundFX.Bolt` / `BoltStroke` / `Event("strike")`, zero-damage `MakeExplosion("xbgndyl")` for light and scorch), delayed thunder by distance, sky and ambient flash, windshield dirt when close | visual |
| Quakes | leader `quake` events plus a per-phase rumble; stock `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake` at magnitude `strength x 3` (cap 3.5) | camera shake only |
| Ground cracks | `CR18/CrackA/B` flat decals (additive, ColourInterpolator pulse), `CR18/Soot` stain, `CR18/CrackPuff` dust burst. World grid of 20 m cells; a cell holds a crack when `hash(seed, cell) < density x 0.55`, so raising density only adds cracks and every peer agrees | visual |
| Landslides | leader `slide` events; each peer picks the steepest of ten spots 50-160 m from its camera and slides `CR18/SlideDust` + `SlideRock` downhill for 4-8 s with a rumble. No rock objects: gameplay objects would need `BuildSyncObject` and offer little a particle spray does not | visual |
| Giant tornado | 8 stacked local-space bands (`CR18/Tornado*`), each node moved to the funnel and turned with `SetParticleSystemDirection` at its own rate so the column shears; dust skirt, debris, core, glow and embers, plus one EXU point light. Track from `CRStorm18Tornado` (below) | visual + optional effect |
| Windshield | `CRWetGlass.Splat` on close strikes and slides, `SetCrack` from collapse | visual |
| Scorched scrub | the baked misn17 `cr17_mire_*` meshes (wind-sway stream kept) with the `CR18/GroundWind` override material on `cr18_foliage.dds`; registered with `CRFoliageWind`; leaf litter from every placement | visual |

### Tornado track and effect

`CRStorm18Tornado` steers to a waypoint (9.5 m/s, 2.6 m/s^2) and is pushed out of the
keep-clear circles in `CRStorm18Sites.zones` plus a 40 m pad and kept 140 m inside the
map edge. The 24 circles (generated from the stock `.bzn`) cover the recycler and start
(r 300), the transport (r 300), the discovery point, every wave spawn and the "dontgo"
ambush column. The leader picks each waypoint 150-250 m from a random human, rejecting
any whose straight track crosses a circle, every 9 s; the full state (n, x, z, v, waypoint,
age) is an event, and peers dead-reckon the same arithmetic between events. Tested for 4 h
of simulated play with the humans standing on the objectives: never inside a circle.

The optional gameplay effect (`Tornado.EFFECT`, default ON, low): inside 45 m **every
peer** pulls, spins and lifts the craft it owns (`IsLocal` in a net game: its own player
and anything it built; the leader also owns the AI and enemy craft; buildings never) by
7 / 9 / 4 m/s^2 at the core, capped at 55 m/s, and damages 6 hull/s at the core. It runs
from the replicated funnel (events plus identical dead reckoning), so a craft is moved
only by its owner and never twice, and guests are pulled as fairly as the host. Offline
everything is local. Set `ENABLED = false` for a purely visual storm.

## Interface contract (what CRMisn18 does)

Match `CRMisn17`'s Jungle wiring exactly:

```lua
local ok, mod = pcall(require, "CRStorm18")
local Storm = ok and mod.Create({exu = exu, state = function() return M end,
    players = function()               -- optional but recommended: leader targeting
        local t = {}
        CRCoop.ForEachPlayerHandle(function(h) if Valid(h) then t[#t+1] = GetPosition(h) end end)
        return t
    end}) or nil
-- R.Start / R.Load:     Storm.Reset(State().storm); Environment.BindWeatherSensors("Achilles", Storm)
-- ApplyPresentation:    if op == "Storm" then return Storm.Apply(...) end      -- every peer
-- ReceivePresentation:  accept op == "Storm" like op == "Jungle"
-- R.Update:             Storm.Update(dt, CRCoop.IsAuthority(), function(...) Present("Storm", ...) end)
--                       M.cr18Storm = Storm.Describe()
-- R.Save:               State().storm = Storm.Save()
-- SucceedMission / FailMission presentation: Storm.Stop()
-- leader only:          Storm.SetPhase("opening" | "search" | "found" | "core1" | "core2" | "core3"
--                                       | "collapse" | "final" | "won" | "lost")
```

Aliases: `Init = Load = Reset`, `Receive = Apply`. Guard every call with `if Storm`. `Update`
returns at once after `Stop` until `Reset`; `SetPhase` before `Reset` is held and applied.

**Quake ownership.** The storm owns `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake`
while it runs. The mission does not call them: `CRMisn18` hands every mission quake request
(the stock `StartEarthquake(2.0)` at discovery and the restored, capped-at-12 pulse) to
`Storm.Quake(magnitude, seconds)` on each peer. The storm envelopes each request (rise
and fall like its own pulses, default hold 3.5 s, magnitude clamped to 0..12, at most 12
live) and shakes the engine with the maximum of its own shake and every live request, so
nothing fights and the restored pulse is preserved (it is not subject to `QUAKE_MAX`, which
bounds only the storm's own shake). `Quake` returns false once the storm is stopped,
disabled or not built, and the mission then shakes the native itself. `Stop` calls
`StopEarthquake` only if the storm started one. Requests are peer-local: the mission
already replicates its own quake calls, so every peer receives the same ones and the
storm adds no event for them.

`api.players` (optional) is the list of human positions used for the tornado's targeting;
`Describe()` is read each frame into `M.cr18Storm` by the mission.

### Events (`Present("Storm", kind, ...)`, numbers only)

| kind | args | meaning |
|------|------|---------|
| `phase` | idx, age, seed | phase index 1-10, leader storm clock, seed. Sent on change and every 15 s (late joiners, drift) |
| `bolt` | n, power, ground | serial n (deduped), 0..1, 1 = ground strike. Geometry is `hash(seed, n)` relative to each camera |
| `quake` | n, strength, seconds | merged into a running quake |
| `slide` | n, power | |
| `tornado` | n, x, z, vx, vz, wx, wz, t | waypoint serial n; sent on spawn, each waypoint and every 15 s |

About 150 events in a 180 s collapse, under 900 in a full run; the co-op log is append-only,
so cadence is deliberately modest. A `phase` with an age more than 5 s behind (the leader
loaded an older save) resets the duplicate counters. Malformed packets are ignored.

## Tunables

`Storm.PROFILE` (the table above), `Storm.TUNING` (quake scale/cap, mission quake hold,
waypoint and resync intervals, sky plane), `Tornado.EFFECT` / `SPEED` / `PAD` / `GROW`, `Ground.BUILD` (520) /
`DROP` (700) / `RENDER` (260) / `CRACK_*` / `SLIDES`.

## Performance budget

Held to misn17's. Scrub is the same meshes, cull distance 260 and one layer per mesh per
384 m tile, but is **streamed**: a tile builds when its centre is within 520 m of the camera
(one per 0.25 s) and is destroyed beyond 700 m, so about 25 layers / 2-3k plants are resident
against misn17's 31k built up front. All 31,355 placements still seed the leaf litter grid.
No solid trees (gameplay objects) are added. Particles: weather about 6 systems (quota 7,100,
most idle at low phases), tornado about 850 live at peak, decals bounded by 120-quota systems
and 3 new cracks per 0.35 s. One sky plane, three samples per pixel. Two point lights at
most (tornado) of EXU's 8. Per frame: a handful of guarded EXU writes throttled to 4-20 Hz.

## Regenerating assets

`python Tools/Build-Misn18Storm.py --stock <Battlezone_Source>/BZ1/1.5/Battlezone_Install/stock`
rewrites `Scripts/CRStorm18Sites.lua`, `Assets/Textures/cr18_foliage.dds` (DXT5 with mips,
colour-bled; Pillow's DXT1 encoder speckles cutout atlases), `cr18_crack_a/b.png` and
`References/Misn18Storm/source-assets.json`. CI runs `--check` (outputs match the manifest).
Shader edits: bump the `_v1` suffix in `cr18_swirl.program` and the material (Ogre's
microcode cache keys on the program name).

## Tests

`lua5.1 Tools/Test-CRStorm18.lua` (957 checks): payload/material/program lint (every
template parses, materials and textures exist, ColourInterpolator has all six stages, no
name clashes, program references and delegates in order, shaders agree on their uniforms);
rng determinism; preset escalation and template indices; phase ladder (events per phase,
severity, no regression); leader to guest replication, identical strike geometry,
late-join convergence, malformed packets, rollback, dedupe; determinism and save/load
continuing the same schedule; tornado routing against the real zones for 4 h with players
parked on the objectives (plus Resolve and SegmentClear unit checks); the effect's
leader-only/IsLocal/off switch; streaming, failure back-off and material fallbacks;
landslides; mission quake routing (max-merge, clamp, one native owner, refusal after Stop); every peer pulling only
its own craft; collapse burst; Stop writing calm to the sky, wind foliage, quake, lights,
systems and geometry; no-EXU and no-payload degradation. `fxc` compiles all four HLSL
entry points (vs/ps 4_0 and 3_0).

## Live smoke (lcbench / in-game) must check

Everything rendered is unverified. In order of risk:

1. `cr18_storm.particle.payload` parses (Ogre skips a bad block silently): every
   `CreateParticleSystem` returns true; `CRWeather.DescribeSystem` on `cr18_wx_*` shows the
   emitter/affector indices the presets address; `BZOgreLogfile.log` clean.
2. The sky shader compiles on SM4 and SM3, the plane covers the sky, swirls visibly, turns
   red, pulses, and the 24-unit tiling and `plane` centre put the spiral overhead;
   `CR17_Cloud`-style zero vertex-declaration exceptions.
3. `Materials` import chain: `CR18/GroundWind` resolves (imports of `cr17_wind.material`
   and `crwx_precip.material`); ground cover draws brown, sways, and the material override
   argument of `CreateStaticGeometry` is accepted.
4. Tornado: the column reads as a funnel, the bands visibly shear through
   `SetParticleSystemDirection`, scale is right at 150-250 m, the light is warm, nothing
   draws past 250 m fog oddly, and the gameplay pull is mild.
5. Cracks lie flat, glow and pulse (perpendicular billboards honour the random Rotator;
   the colour channel order of the CRWX sprite path), soot and puffs appear.
6. Landslides ride the slope; thunder, quake rumble, strikes and flashes; windshield dirt.
7. Quake magnitude feel at 3.0 x strength; the mission's discovery quake and restored pulses now shake through
   `Storm.Quake`: no stutter or double shake. Tornado: a guest's own ship is pulled and the damage is mild.
8. Collapse entry reads inside the thruster cinematic; frame time at final (aim: no worse
   than misn17's storm); co-op: guest and host see the same phase, strikes near each
   camera, tornado in the same place; save/load mid-storm; mission end leaves the next
   mission's sky, wind foliage and quake calm (sensors: `GetSeverity` is the phase level).
