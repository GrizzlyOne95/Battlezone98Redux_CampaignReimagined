# Mission 18 storm (CRStorm18)

## Large hell fissures (2026-10-21 prototype)

Owner direction: occasional large ruptures, like a white-hot crack with red
light escaping upward, made more frightening. `CRStorm18Fissures.lua` layers
these over the ordinary small crack field once cores start dying. A rupture
opens over 2.8 seconds into a 44-60 m winding mouth, with a charred lip and a
searing interior, five uneven 24-36 m red shafts, rising embers and one actual
EXU point light at 2.5 m above the ground. The light is saturated red
`{r=4,g=.035,b=.008}`, range 48 m; its power breathes up to about 1.8. Point
lights are omnidirectional; upright additive billboards carry the upward shafts.

The first rupture follows core1 after a 9 s lead-in, then roughly every 45-50 s.
Collapse brings one forward to about a second after the crack density reaches
0.8; full density gives an 18-24 s cadence. Each lasts 22-28 s, with a 4 s fade.
At most two ruptures exist: two lights plus the tornado's one, and six particle
systems (304 total particle quota). Writes run at 10 Hz. They are cosmetic,
camera-local and seeded, like landslides; they add no network traffic or damage
and do not change the terrain heightmap or collision. Cosmetic transients are
rebuilt after load, rather than saved as game objects.

Placement tries up to 16 sites 45-95 m from the local camera, sampling the whole
decal footprint and its five shafts against the terrain plane. Reject water,
cliffs, rough relief above 0.35 m, map edges and overlapping active fissures.
Missing payloads/unsuitable ground retry after 5 s. A refused light leaves the
visual mouth and retries after 2 s. `Stop`, quality 0, zero crack density and
moving 180 m away destroy every owned system/light. Other EXU lights are untouched.

Art: `Assets/Textures/c18rift.png` is a newly generated transparent 2172x724
decal. `Docs/MISN18_FISSURE_ART_PROMPT.txt` records the built-in image generation
prompt; the owner's reference image is mood guidance and is not distributed.
The original RGBA alpha is preserved. `CR18/FissureMouth` uses alpha blending
so the dark lip survives; rays use CR's existing soft streak, embers its credited
`cr_ember.dds`. No shader changes. The inherited CRWX particle path keeps RGBA.

`Tools/Test-CRStorm18Fissures.lua` executes placement, phase cadence, seeded
repeatability, native vector/RGB shapes, bounded light power/resource counts,
stop/quality/distance cleanup, rejected terrain and refused capabilities. It is
wired into CI; `Test-CRStorm18.lua` also lints the new payload/material/texture.
An isolated Windows/GOG DX11 preview on 2026-10-21 loaded all three new templates
and the original RGBA texture, rendered the mouth/shafts/embers and red terrain
spill, then reported `FISSURE_LIGHTS_AFTER_STOP 0`. DLL hashes matched before
and after. Evidence: `C:\BZRCoop\hell-fissures-20261021\`. The first capture
exposed UV-only rotation on the long mouth: it now requests vertex rotation
with the corresponding -normal bearing. The UV-to-shaft geometry regression
protects that alignment. Ogre documents the distinction in its
[particle attribute reference](https://www.ogre3d.org/docs/manual18/manual_35.html).
This is a prototype pending visual acceptance, not a release qualification;
the complete storm/co-op run and DX9/Steam/Proton/Wine lanes remain unverified
for this addition. The generic bless refused to remove 50 absent generated UI
files, so only the new module/texture memberships were inserted in place per
the knowledge-base fallback. Existing shipping entries were preserved.

Weather, ground cover and environment FX for mission 18, where the player has
destroyed the Fury transport's cores and the moon tears itself apart. New files
only for the storm itself; nothing here edits `misn18.lua` or the map. The module is
wired into the co-op port by `CRMisn18.lua` exactly like `CRJungle17` in `CRMisn17`, plus
one leader-side call, `SetPhase`, and the quake routing below (see also
[`MISN18_COOP.md`](MISN18_COOP.md), which owns the mission-side contract). The
2026-10-19 one- and two-peer DX11 results and remaining horizon/capture gaps are
recorded there; the smoke list below remains the broader qualification checklist.

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
backward; `won` and `lost` hold the `final` look (and `lost` after `won` is refused). `extract`
and `ascent` (the extraction ending, see [`MISN18_COOP.md`](MISN18_COOP.md)) sit between `final`
and `won`: `extract` is the final look with the tornado's gameplay effect off while the dropships
load, `ascent` the most violent rung (strikes every 0.2-0.5 s with a 14 s burst on entry, hard
shake, a 1.7x gale driving the dust and ash past the camera, the red swirl overhead).

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
| 9 | extract | 1.00, as final, gameplay effect off | | 0.7-1.8 | 2.5-4.5, .90, rumble .45 | 6-11 | 1.0 | yes |
| 10 | ascent | 1.00, gale x1.7 | | 0.2-0.5 | 1.2-2.5, 1.0, rumble .70 | | 1.0 | yes, harmless |
| 11, 12 | won, lost | hold 8 | | | | | | |

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
| Sky | `SetSkyPlane("CR18/StormSwirl", ...)` fitted to 0.15 x far clip like `Weather.lua`; tiling 24. `cr18_swirl.program` samples the cloud alpha twice, turning in opposite directions about the zenith (spiral twist from pass specular), plus a third layer driven by `SetMaterialTextureScrollAnimation` / `SetMaterialTextureRotateAnimation`. Palette, density and glow-from-below ride the pass colours (`SetMaterialPassColors`: ambient = base, diffuse = cloud, emissive = pulsing glow, specular.r = twist). Reads POSITION and UV only (no COLOR0). The vertex stage pins depth just inside the far plane, so the deck is never far-clipped and runs to its own edge (under 1 degree up) instead of ending in a hard line about 9 degrees above the horizon; the fragment stage sinks into the fog colour as the view ray nears the horizon, matching the terrain's fog end. While the deck is up the map's stock dome is hidden (restored in `Stop`), so no pale sky shows in any gap. When the CR Achilles dome owns the sky (`Environment.ArtSkyOwned`, and `SkyWeatherSource` is this director), the deck waits: opening, search and found (`TUNING.DOME_PHASES = 3`) keep the dome's night sky with Uranus through the gathering cloud, fed by `S.SkyState()` (`storm = level / DOME_STORM`, `bank = level / 2`, the flash toward the strike), and the swirl tears in at core1. Hiding the dome calls `Environment.SetArtSkyVisible(false)`, which gives the stock `acloud` and `uranus.map` sprites back for the swirl phases; `Stop` hides them again. See `Docs/ACHILLES_SKY.md` | visual |
| Lightning | leader `bolt` events; each peer draws a channel near its own camera (`CRGroundFX.Bolt` / `BoltStroke` / `Event("strike")`, zero-damage `MakeExplosion("xbgndyl")` for light and scorch), delayed thunder by distance, sky and ambient flash, windshield dirt when close | visual |
| Quakes | leader `quake` events plus a per-phase rumble; stock `StartEarthquake` / `UpdateEarthQuake` / `StopEarthquake` at magnitude `strength x 3` (cap 3.5) | camera shake only |
| Ground cracks | `CR18/CrackA/B` flat decals (additive, ColourInterpolator pulse), `CR18/Soot` stain, `CR18/CrackPuff` dust burst. World grid of 20 m cells; a cell holds a crack when `hash(seed, cell) < density x 0.55`, so raising density only adds cracks and every peer agrees | visual |
| Landslides | leader `slide` events; each peer picks the steepest of ten spots 50-160 m from its camera and slides `CR18/SlideDust` + `SlideRock` downhill for 4-8 s with a rumble. No rock objects: gameplay objects would need `BuildSyncObject` and offer little a particle spray does not | visual |
| Giant tornado | 8 stacked local-space bands (`CR18/Tornado*`), each node moved to the funnel and turned with `SetParticleSystemDirection` at its own rate so the column shears; dust skirt, debris, core, glow and embers, plus one EXU point light. Track from `CRStorm18Tornado` (below) | visual + optional effect |
| Windshield | `CRWetGlass.Splat` on close strikes and slides, `SetCrack` from collapse | visual |
| Water | baked pools, streams and a cascade (below): muddy and faster with the level, mist thickens, wakes | visual |
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

## Water and landscaping

Pools, streams and one cascade on the Achilles terrain, modelled on misn17's water
(`Tools/Build-Misn17Jungle.py`: priority-flood pools, D8 stream routing on a blurred
surface, the same ribbon and pool-quad bakes; its `water_mask` is imported, not copied)
by `Tools/Build-Misn18Water.py`, which `Build-Misn18Storm.py` runs last. It reads
`Missions/misn18.hg2` (5 m grid) and **never writes it: nothing is carved**. Misn17 cuts
its channel beds; here every pool fills an existing closed basin and every stream follows
the existing gradient, so a stream's ribbon floats 0.15 m over the ground and its banks
tuck it in. The manifest pins the heightmap hash, and `--check` fails if it changes.

Chosen water (stock map, x 0..2560, z 97280..102400):

| What | Where | Why |
|------|-------|-----|
| Pool A | (1247, 102047), surface 97.8 m, 175 cells | the largest candidate basin that clears every zone (about 1.2 km north of the transport) |
| Pool B | (787, 101631), 101.0 m, 136 cells | north-west of the transport basin, outside the discovery circle |
| Pool C | (747, 98213), 100.9 m, 115 cells | south-west flank (about 1.1 km from the start) |
| Pool D | (1839, 101341), 106.4 m, 73 cells | 0.5 km north-east of the transport, on the cascade's stream |
| Streams | 6 ribbons (303 points), half-width 1.3-3 m | inflows (at most two per pool) and one outflow per pool, from the D8 channels (>= 600 drained cells, >= 90 m) |
| Cascade | foot (1715, 84.1, 101180), 21.9 m drop over 22 m of stream | the steepest 22 m of any kept stream (the fall is cut out of the stream mesh and drawn as its own, faster sheet; mist sits at its foot) |

Selection: closed basins deeper than 0.6 m (fill minus ground), at least 60 cells wet at
the surface (lowest cell + 2 m, 1500 cells at most) and 1.3 m deep, between 330 and
1400 m of the start or the transport (near enough to be seen, outside the zones), at
least 260 m apart, best score first. Pools render as 5 m quads at one level;
the surface may stand up to 2 m over the bed (misn17's rule).

**Kept clear** (every one is an exclusion mask; a pool touching it is rejected, a stream ends 10 m
before it, and the build asserts no mask cell is inside): the 24 tornado keep-clear circles
(`Build-Misn18Storm.keep_clear`: recycler and start r 300, transport and thrusters r 300, the
discovery point, every wave spawn, the dontgo ambush column, which also covers the dropship ring
of `CRDrop18`) plus 30 m, the polylines of the spawn, return, dontgo and transfound paths
(the Fury arrivals) plus 45 m, every stock object plus 28 m, and a 5-cell edge margin.
`Test-CRStorm18.lua` re-checks every mask cell, pool and the cascade against `Sites.zones`.

Generated outputs: `Assets/Models/cr18_pools.mesh` (70 KB), `cr18_streams.mesh` (23 KB),
`cr18_cascade.mesh` (0.6 KB), and in `CRStorm18Sites.lua` the `watermask` (same run-length
format as `CRJungle17Sites`; 1,242 cells), `water` (mesh, position and material per sheet,
`pools_info`) and `cascade` (`x, y, z` at the foot, `drop`, `top`). Deterministic;
`python -I Tools/Build-Misn18Water.py --check` is the CI check, `--report [--preview png]`
prints the selection and writes a review image.

### Materials and shader

`Materials/cr18_water.material`: `CR18/Water` and children `CR18/Pools`, `CR18/Streams`,
`CR18/Cascade` (CR17's textures and scroll/colour presets; the cascade is faster, whiter and
more opaque). They use `CR18_Water_v1_fragment` (`Shaders/cr18_water.program`), the CR17 water
kind built with `STORMWATER`, a variant added to `cr17_surface.hlsl` / `-fragment.glsl` (nothing
changes without the define, so misn17 is untouched). It reads two pass colours:

| Pass colour | Uniform | Meaning |
|-------------|---------|---------|
| diffuse (`surface_diffuse_colour`) | `stormMud` | rgb = mud colour, a = mud amount: the albedo blends to mud, alpha toward 0.92 |
| specular (`surface_specular_colour`) | `stormFlow` | x = extra scroll phase added to both scroll layers |

Pass colours multiply Ogre's `derived_light_*` autos, so the program binds the power-scaled
light colours instead. The phase is integrated in Lua (a speed change never makes the water
jump) and wraps at 1000, which every material's scroll rates divide into whole turns. `fxc`
compiles the ps_4_0 and ps_3_0 variants. Bump `_v1` in the program and material on a shader edit.

### Storm coupling (`CRStorm18Water`)

Peer-local and render-only: each peer drives the water from its own smoothed storm level
(`lvl`, which follows the replicated phase), so there are no events. `Water.Params(level, wind)`:

| | calm (opening .14) | core2 (.68) | collapse (.96) | final (1.0) | ascent (1.0, gale 1.7) |
|--|--:|--:|--:|--:|--:|
| mud amount | 0.06 | 0.67 | 0.96 | 1.00 | 1.00 |
| streams scroll x | 1.3 | 2.5 | 3.8 | 4.2 | 5.5 |
| pools chop x | 2.3 | 7.1 | 12.2 | 14.0 | 18.4 |
| cascade scroll x | 1.2 | 1.8 | 2.7 | 3.0 | 3.9 |
| mist rate /s | 24 | 53 | 87 | 100 | 135 |

Collapse, final, extract and ascent are the most violent (the extra `violent` term switches
on from level 0.9; the ascent adds the gale). Writes run at 12 Hz while the water is changing
and 1 Hz when calm. `Stop` writes calm back (mud 0, phase 0), destroys the sheets and the
mist, and `Reset` rebuilds them (materials outlive the Lua state). A missing material skips
only that sheet (retry every 30 s); no EXU means no water.

### Vehicle debris

`CRStorm18` initialises the shared `CRWake` with the resolver `water.WakeSurface(x, z)`:
`water` (lift 0.5 m, a compromise: streams sit 0.15 m over the ground, pools up to 2 m) on a
mask cell, else `mud` (rate 0.6 + 0.4 x mud amount): dark wet dirt and clods
(`CRWake/MudClods`, in `cr_wake.particle.payload`, material `CR_FX/Grit`). It respects
CRWake's load budget (4 systems, 4 scans a second, 140 m); `vehicleWakes = false` on the
`CRStorm18.Create` api turns it off. See [`VEHICLE_WAKES.md`](VEHICLE_WAKES.md).

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
| `phase` | idx, age, seed | phase index 1-12, leader storm clock, seed. Sent on change and every 15 s (late joiners, drift) |
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
The stacked forest extension adds bounded solid trees (see `MISN18_TREES.md`).
Particles: weather about 6 systems (quota 7,100,
most idle at low phases), tornado about 850 live at peak, decals bounded by 120-quota systems
and 3 new cracks per 0.35 s. One sky plane, three samples per pixel. Up to three
EXU lights of its eight: one tornado and two rare large fissures. The large
fissures add at most six systems (304 quota), with writes at 10 Hz. Other
guarded EXU writes are throttled to 4-20 Hz.

## Regenerating assets

`python Tools/Build-Misn18Storm.py --stock <Battlezone_Source>/BZ1/1.5/Battlezone_Install/stock`
rewrites `Scripts/CRStorm18Sites.lua` (water keys included, see Water), the three `cr18_*.mesh` water meshes, `Assets/Textures/cr18_foliage.dds` (DXT5 with mips,
colour-bled; Pillow's DXT1 encoder speckles cutout atlases), `cr18_crack_a/b.png` and
`References/Misn18Storm/source-assets.json`. CI runs `--check` (outputs match the manifest).
Shader edits: bump the `_v1` suffix in `cr18_swirl.program` and the material (Ogre's
microcode cache keys on the program name).

## Tests

`lua5.1 Tools/Test-CRStorm18.lua` (1,165 checks): payload/material/program lint (every
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
entry points (vs/ps 4_0 and 3_0) and the `STORMWATER` water variant. Water: payload/material/program lint, placement
against every keep-clear circle, mask hits and near misses, the resolver (water vs mud), mud/speed/mist rising up the
ladder and peaking in the ascent, throttled writes, seamless phase wrap, calm on Stop, a missing material.

## Live smoke (lcbench / in-game) must check

Broader qualification remains incomplete; see the dated live evidence in
`MISN18_COOP.md` and the large-fissure prototype section above. In order of risk:

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
10. Water: `CR18/Pools|Streams|Cascade` compile (SM4 and SM3, zero vertex-declaration exceptions) and lie on the ground without
    z-fighting or floating banks; the cascade reads as a fall and its mist sits at the foot; the mud tint and scroll speed rise
    visibly with the phase and `Stop` leaves the next mission's water clear; the mud wake looks like dirt, the water wake lift
    (0.5 m) is right on pools and streams, and nothing in the water breaks a Fury path or the dropship ring.
9. The ascent (`ascent`): strikes close to the climbing dropship, shake and gale tolerable, ash and cloud streaks
   rush past, and nothing in the 330 m camera ring is hurt by the funnel during `extract`.
