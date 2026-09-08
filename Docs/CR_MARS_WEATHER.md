# Mars weather (CRMarsWeather)

Mars weather director for Campaign Reimagined, wired into **misn04**.

`CRWeather` is a renderer: hand it a preset and it draws that weather. It has no
opinion about *when* weather should happen, and its wind is one frozen vector per
preset. `CRMarsWeather` is the missing half — the thing that decides what the sky
is doing minute to minute and keeps the air moving while it does.

---

## The ladder

Weather is a continuous position on a five-rung ladder. Integer crossings swap
the `CRWeather` preset; the **fractional** position drives everything else, so
wind, sensors and visibility slide through a transition instead of stepping at
the moment the preset changes.

| # | Name | Preset | Wind | Visibility | Radar range | Dust devils |
|---|------|--------|-----:|-----------:|------------:|-------------|
| 1 | Calm | `MarsHaze` | 6 | 520 | ×1.00 | yes, up to 2 |
| 2 | Breezy | `MarsHaze` | 15 | 490 | ×0.96 | yes, up to 2 |
| 3 | Rising | `MarsDustRising` | 25 | 380 | ×0.82 | occasionally, 1 |
| 4 | Storm | `MarsDustStorm` | 38 | 320 | ×0.62 | no |
| 5 | Severe | `MarsDustStormSevere` | 58 | 130 | ×0.42 | no |

Rungs 1 and 2 share a preset on purpose: the difference between calm and breezy
on Mars is wind and dust devils, not a different sky.

The director moves **one rung at a time**, weighted toward a target the mission
sets. It never jumps, because a jump reads as a cut rather than as weather.

---

## Wind

Wind is live, not a preset constant:

- **Bearing** — a prevailing direction chosen at init, with a bounded random
  walk around it. Turning is rate limited to 0.055 rad/s (~3.2°/s), so dust
  never visibly snaps to a new heading.
- **Speed** — the ladder's base speed for the current fractional position, plus
  the live gust, smoothed.
- **Gusts** — discrete events with a real rise/hold/fall envelope, not a sine
  wave. A gust also veers the bearing while it passes. Stronger weather gusts
  harder and more abruptly.
- **Fall** — the downward component grows with speed. Hard wind drives dust down
  onto the deck instead of letting it hang, which is what gives a severe storm
  its weight.

The live wind is pushed into `CRWeather` via `SetWindOverride`, which steers
emitter direction **and** scales emitter velocity. That second part matters: if a
gust only changed how *many* particles there were, it would read as a density
flicker rather than as wind.

---

## Dust devils

Placed in the world (not camera-attached), upwind of the player by preference,
drifting downwind at 30% of wind speed, re-sampling terrain height as they go.
They spin up and spin down through their emission rate rather than popping in
and out.

They only occur on the **calmer half** of the ladder. That is physical, not a
budget dodge: a dust devil needs a convective boundary layer to form, and inside
a full storm there is neither one nor any way to see the result.

---

## What the weather does to the mission

Both couplings are individually switchable at init.

**Sensor degradation** — radar range and refresh, and velocity jamming, all
scale with severity. This goes through `Environment.RegisterGameplayModifier`,
*never* through a direct `exu.SetRadarRange`. See the ownership section below.

**Wind push** — a lateral component is added to gravity, proportional to wind
speed and capped at 1.2 units/s². It is deliberately small: this should read as
buffeting, not as being shoved. It also deflects unguided ordnance downwind,
which is intended — a mortar arc in a gale should not land where it does in
still air.

---

## Ownership

Three renderer/gameplay states in CR have exactly one writer each, and this
system routes around all of them rather than competing:

| State | Owner | How weather contributes |
|-------|-------|------------------------|
| Fog, ambient, sun diffuse/specular, sun power | `Environment.Update` | `CRWeather` registers an **environment modifier** |
| Radar range, radar period, velocity jamming | `Environment.ProcessObjectNightEffects` | `CRMarsWeather` registers a **gameplay modifier** |
| Gravity | nobody | `CRMarsWeather` takes it, and restores it on shutdown |

### Why the atmosphere is a stack of weighted layers

`CRWeather` keeps one weight per preset that still has any presence on screen —
`CRWeather.Layers`, oldest first — rather than a single incoming/outgoing pair.
`ApplyEnvironmentContribution` walks them in order, so the newest preset has the
last word and everything still fading contributes its remainder.

This is not bookkeeping for its own sake. A preset change only ever moves ramp
*targets*: the incoming layer climbs, the others fall, and no layer's current
weight is ever reassigned. The composite on the frame of a change is therefore
identical to the frame before it, by construction, for any number of changes.

The obvious alternative — read the incoming preset at `Blend`, and restart
`Blend` at 0 on a change — cuts the entire atmosphere back to the bare mission
baseline for a frame and then ramps the new preset in over the next 18-30
seconds. Adding a single "previous" slot does not rescue it either: a change part
way through a transition displaces a preset that was itself still fading, and
that residue is lost. `Tools/Test-CRMarsWeather.lua` asserts both cases directly,
measuring the largest single-channel move across a preset change; on the
single-slot model they step by 0.38 and 0.17 respectively.

A displaced preset keeps its particle systems while its layer is above zero, so
its dust fades rather than vanishing. Layers that reach zero are dropped and
their systems destroyed in the same pass, which is also what stops a preset
displaced mid-transition from stranding its systems in the scene.

### Why the clock is `GetTime()` and not the caller's `dt`

misn04 hands every module a fixed `1.0 / M.TPS` as its delta, but `Update` runs
once per rendered frame rather than TPS times a second. That number is a frame
count wearing seconds' clothing: at 120 fps the weather advanced six seconds per
real second, so rungs whose dwell is 35-160 s re-rolled every 6-25 s and gusts
fired several times a second. The ladder read as flapping rather than as weather,
and every one of those changes dragged the atmosphere through a transition.

`CRMarsWeather.Update` therefore takes its own delta from `GetTime()`, the same
clock the rest of the mission schedules against, and is framerate-independent. A
caller passing `0` still means "settle the scene, do not advance time". A
discontinuity — a load, a pause, a restart — yields `0` rather than a jump. When
`GetTime` is unavailable, as in the offline test harness, the caller's `dt` is
used unchanged.

The gameplay-modifier hook was added for this system and is new in
`Environment.lua`. It had to be a hook rather than a second writer for two
reasons, both of which are silent failures:

1. `ProcessObjectNightEffects` recomputes every value from the craft's captured
   original on each sync pass, so an outside writer is clobbered within the
   second.
2. It captures that original **lazily**. A storm that called `SetRadarRange`
   first would have its own degraded value recorded as the craft's baseline —
   and the degradation would then be permanent, surviving the storm, the night
   cycle, and the rest of the mission.

The capture and release conditions now consider night blend *and* the modifier
contribution together, so a daytime storm still captures a baseline (it would
otherwise never apply), and a storm's degradation is still released when it
passes (it would otherwise be stranded on every craft).

---

## Mission API

```lua
local CRMarsWeather = require("CRMarsWeather")

CRMarsWeather.Init({
    startLevel  = 1,        -- opening rung
    targetLevel = 2,        -- rung the director trends toward
    -- prevailingBearing = 1.0,   -- radians; omit for a random prevailing wind
    -- baseSky = { ... },         -- only if the map has a sky dome to restore
    -- dustDevils = false, sensorDegrade = false, windPush = false,
})

CRMarsWeather.Update(dt)          -- call BEFORE Environment.Update
CRMarsWeather.OnObjectCreated(h)
CRMarsWeather.Shutdown()

CRMarsWeather.SetTargetLevel(n)   -- move the target; the ladder walks there
CRMarsWeather.ForceLevel(n, seconds, transitionSeconds)  -- pin for a set piece
CRMarsWeather.ReleaseForcedLevel()
CRMarsWeather.SetAutomatic(bool)

CRMarsWeather.GetWind()           -- vector, direction * speed
CRMarsWeather.GetWindSpeed()
CRMarsWeather.GetVisibility()     -- approximate view distance in world units
CRMarsWeather.GetLevel() / GetLevelName() / GetSeverity()
CRMarsWeather.Describe()          -- one-line debug string

CRMarsWeather.Save() / CRMarsWeather.Load(state)
```

`Update` must run **before** `Environment.Update`, because `CRWeather`
contributes fog and sun through Environment's modifier hook and its blend has to
be settled for the frame before Environment resolves and writes them.

Prefer `SetTargetLevel` over `ForceLevel`. Setting a target lets the weather walk
there over a few minutes, which is the whole point of the ladder; forcing is for
set pieces that have to land on cue.

---

## misn04 wiring

misn04 has no `SkyTexture` in its `.trn`, so no base sky is supplied and the sky
layer correctly stays off. The storm reads through fog, light and particles,
which is where nearly all of it lives anyway.

Beats are recomputed from mission state every frame rather than latched on
transitions, so a save taken mid-mission lands on the right weather without
having to persist which beats had already fired:

| Mission state | Target |
|---|---|
| baseline | 2 — breezy |
| `wavenumber >= 3` | 3 — the CCA push builds, and so does the dust |
| relic discovered, not yet secured | 3 — the most exposed stretch of the mission |
| `wavenumber >= 5` | 4 |
| `fifthwave` | **forced to 5 for 110 s** — the last wave arrives inside a severe storm |
| relic secured, or mission won | 2 — the run home is readable |

The set piece is the one latched beat and carries its flag in `M.weatherSetPiece`
so it fires once per mission, not once per load.

---

## Save / load

Only the director's scalars persist; everything visual is rebuilt from them.

The load path deliberately calls `CRWeather.ResetSystems()` first. Loading a save
tears the Ogre scene down and rebuilds it, which takes the particle systems with
it — but `CRWeather.LiveSystems` still names them. Without the reset,
`CreateSystem` finds an "existing" entry, retargets a system that is no longer
there, and the weather silently never renders again for the rest of the session.

---

## Placeholder art

Everything renders today against textures CR already ships, so the system can be
profiled and tuned before any art exists. Each entry below is the asset the art
pass should supply.

### Particle textures (`Materials/CR_reactive.material`)

| Material | Wanted | Currently |
|---|---|---|
| `CR_FX/Haze` | `cr_haze.png` — very soft wide dust veil, almost pure falloff, ~128×128. The softest texture in the set. | `smoke.png` |
| `CR_FX/DustSheet` | `cr_dustsheet.png` — elongated horizontal dust streak, ~64×16 | `smoke.png` |
| `CR_FX/DustDevil` | `cr_devil.png` — ragged vertical dust wisp with a torn top, ~64×128 | `smoke.png` |
| `CR_FX/Dust` | `cr_dust.png` — soft irregular dust mote, heavy falloff, ~64×64 | `smoke.png` |
| `CR_FX/Grit` | `cr_grit.png` — small hard sand fleck, near-opaque centre, ~16×16 | `bpuff.png` |

### Skydomes

Only used if a mission supplies a base sky, which misn04 does not. 2048×2048
dome textures.

| Material | Wanted |
|---|---|
| `CR_Sky/MarsHaze` | thin ochre sky, sun disc still visible through it |
| `CR_Sky/MarsStorm` | heavy ochre, sun as a diffuse bright patch |
| `CR_Sky/MarsStormSevere` | featureless dark ochre, no sun disc at all |

### Audio

| Setting | Wanted |
|---|---|
| `CRMarsWeather.GustSound` | `cr_wind_gust.wav` — 2–4 s wind gust, no tail |

Left `nil` rather than pointed at a guessed stock filename, because a wrong
filename plays nothing and looks exactly like working code.

---

## Tuning

Everything is data. The ladder rows in `CRMarsWeather.Levels` carry wind speed,
gust shape, rung duration, devil rate, visibility and the three sensor scales.
The presets in `CRWeatherPresets.lua` carry fog, ambient, sun power, sky and the
particle emitter values. Neither file talks to `exu` directly.

To make the mission stormier overall, raise the targets in misn04's
`UpdateWeatherBeats`. To make storms *last* longer, raise `duration` on the upper
rungs. To make the ladder move faster between rungs, raise `SeverityRate` —
though note the preset crossfade time is separate and lives in the preset's own
`transitionIn` / `transitionOut`.
