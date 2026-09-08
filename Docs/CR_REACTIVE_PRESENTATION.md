# CR Reactive Presentation and Dynamic Weather — implementation notes

First implementation pass over `CR_Reactive_Presentation_Dynamic_Weather_Design.docx`.
This note records what now exists, how a mission turns it on, what is
deliberately not built yet, and what art the systems are waiting on.

## What shipped in this pass

**EXU (native)** — the P0/P1 API additions the design note asked for, in
`src/Game/Environment.cpp`:

| API | Purpose |
| --- | --- |
| `exu.AttachParticleSystemToCamera(name, offset)` | Camera-centred weather volume with no per-frame Lua positioning. |
| `exu.AttachParticleSystemToObject(name, h, offset)` | Damage smoke and engine VFX that ride a craft's own scene node. |
| `exu.AttachParticleSystemToBone(name, h, bone, offset)` | Muzzle and component VFX on a skeleton bone. |
| `exu.DetachParticleSystem(name)` | Returns a system to its own EXU-owned node under the scene root. |
| `exu.UpdateParticleFollowers()` | One call per frame; drives the camera fallback path only. |
| `exu.GetParticleSystemEmitterCount(name)` | Emitter count for a system. |
| `exu.GetParticleEmitterEmissionRate(name, i)` | Current emission rate. |
| `exu.SetParticleEmitterEnabled/EmissionRate/Direction/Position` | Live emitter control. |
| `exu.SetParticleEmitterVelocity/Angle/TimeToLive/Color` | Live emitter control. |
| `exu.SetParticleSystemNonVisibleUpdateTimeout(name, s)` | Stops off-screen storms costing CPU. |

Attachment goes through the Ogre scene graph: the EXU-owned particle node is
reparented under the camera's, the craft's, or a bone's node, so the transform
is carried by the renderer rather than chased from Lua. Camera attachment has a
fallback, because an engine is free to drive its Ogre camera without a scene
node; in that case the system registers as a native follower and
`UpdateParticleFollowers` snaps it to the camera's derived position. That call
returns the number of systems it actually had to move, so it is self-reporting:
**a non-zero return means the fallback is in use on this build.**

**Campaign Reimagined (Lua)**

| File | Role |
| --- | --- |
| `Scripts/CRWeather.lua` | Weather controller: precipitation, sky, fog, lighting, wind, lightning, transitions, save/load, teardown. |
| `Scripts/CRWeatherPresets.lua` | Preset data. Six storms plus `Clear`. |
| `Scripts/CRReactive.lua` | Reactive presentation: impact response, damage bands, emissive failure, damage VFX, weapon heat, cockpit reaction. |
| `Scripts/CRReactiveProfiles.lua` | Profile data: ordnance families, hit profiles, damage profiles, heat profiles, vehicle profiles, cockpit profiles. |
| `Materials/cr_weather.particle` | Weather particle templates. |
| `Materials/cr_reactive.particle` | Impact and damage-state particle templates. |
| `Materials/CR_reactive.material` | Particle billboard materials and weather skydomes. |
| `Scripts/Environment.lua` | Gains an environment-modifier hook (see below). |

## Ownership: one writer for fog and sun

`Environment.lua` writes fog, ambient, sun diffuse/specular and sun power once
per frame at the end of `Environment.Update`. Two modules writing the same
renderer state on the same frame produces flicker that reads as a renderer bug,
so weather does not write any of it directly when `Environment` is loaded.

`Environment` now exposes:

```lua
Environment.RegisterEnvironmentModifier(name, fn)
Environment.UnregisterEnvironmentModifier(name)
Environment.ClearEnvironmentModifiers()
```

A modifier receives `{ ambient, diffuse, specular, fog, sunPowerScale,
nightBlend, phase, timestep }` and edits it in place, just before the writes.
Modifiers run in registration order, are `pcall` guarded, and a modifier that
throws is unregistered rather than allowed to take the environment down with it.

`CRWeather.Init` registers itself as `"CRWeather"` when the hook is present. When
it is not — a mission that does not load `Environment.lua` — CRWeather captures
the fog/light baseline at init, writes the blended result itself, and restores
the baseline on `Shutdown`.

## Wiring a mission

```lua
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})

local exu        = require("exu")
local Environment = require("Environment")   -- optional but preferred
local CRWeather  = require("CRWeather")
local CRReactive = require("CRReactive")

function Start()
    Environment.Init()
    CRWeather.Init({ quality = 1.0 })
    CRReactive.Init()

    -- Only needed if this map wants the sky layer; see the limitation below.
    -- CRWeather.SetBaseSky({ type = "dome", material = "mars", curvature = 10,
    --                        tiling = 8, distance = 4000 })

    CRWeather.SetPreset("MarsDustStorm")      -- transitions in over 25s
end

function AddObject(h)
    Environment.OnObjectCreated(h)
    CRReactive.OnObjectCreated(h)
end

function Update(dt)
    Environment.Update(dt)
    CRWeather.Update(dt)
    CRReactive.Update(dt)
end

function DeleteObject(h)
    CRReactive.Unregister(h)
end
```

`CRReactive.Init` chains onto `exu.BulletHit` and `exu.BulletInit` rather than
replacing them, because `PhysicsImpact.lua` already owns both globals. Whichever
module loads second must not silently delete the first one's physics. The
previous handlers are restored on `Shutdown`.

Mission-driven environment arcs use the same two calls:

```lua
CRWeather.SetPreset("MarsDustStorm", 40.0)   -- storm rolls in over 40 seconds
CRWeather.SetIntensity(0.4)                  -- storm phase, no preset change
CRWeather.SetPreset(nil, 30.0)               -- clears after the objective
```

`CRWeather.GetWind()` returns the live wind vector scaled by the current storm
weight, so props and mission logic can consume the same storm state the
particles do.

## Budgets

The design note's performance rule is enforced in code, not by convention.

- Precipitation is a bounded camera-centred volume. Nothing simulates map-wide;
  distance is sold by fog and sky.
- Every weather system sets a 2 second non-visible update timeout, so an
  off-screen storm stops simulating.
- `CRReactive.MaxDamageSystems` (12) caps concurrent per-craft damage VFX. Past
  the cap a craft still gets its damage material state — the plume is the part
  that gets dropped, not the readability.
- `CRReactive.MaxImpactSystems` (8) is a reused pool. Impacts never create and
  destroy a particle system per hit; in a firefight that costs far more than
  reusing eight of them.
- `CRReactive.ParticleRange` (260 units) gates damage particles and emissive
  work on distance from the player.
- Health is polled on a rotating slice of 8 registered objects every 0.25s, so a
  60-unit battle costs the same per frame as a 6-unit one.
- `CRWeather.Quality` scales emitter rate and particle quota for a low-end
  profile without editing any preset.

## Lifecycle

Both modules have a `Shutdown` that must be called on mission teardown. It
destroys every EXU-owned particle system, returns every overridden sub-entity
material to the craft's own, releases per-craft emissive clones, restores the
sky, removes the environment modifier, and unchains the ordnance callbacks. An
EXU particle system that survives a mission change is a leak into the next
mission's scene, and its name then blocks that mission from creating its own.

`CRWeather.Save()` / `CRWeather.Load(state)` persist only the scalar storm
state. Particle systems are rebuilt from the preset on load, because Ogre
objects do not survive a save. A load snaps to the saved blend rather than
replaying the fade-in, so a player who saved mid-storm loads back into it.

## Known limitations

**Sky restoration.** Ogre exposes the skydome's *generation parameters* but not
its material name, so once the sky is swapped there is no way to discover what
to swap back to. The sky layer therefore stays off until a mission calls
`CRWeather.SetBaseSky(...)` with its own base sky. Weather still reads as a full
storm without it — particles, fog and lighting carry it. Making this automatic
needs an EXU addition (`GetSkyDomeMaterialName` / `GetSkyBoxMaterialName`), which
means reading `SceneManager::mSkyDomeMaterial` directly, since Ogre 1.10 has no
getter for it.

**Hit localisation.** `exu.BulletHit` reports the hit transform but not the
struck sub-entity, material or bone. Impact response is therefore object level:
the whole hull reacts, not the specific panel. The cockpit reaction derives a
coarse front/rear/left/right from the hit transform against the craft's own
forward axis, which is enough to choose a directional animation. Per-panel
response is the remaining P0 item and needs the damage/BulletHit event payload
extended in EXU/OpenShim.

**Damage-state materials are not authored yet.** `CRReactive` checks
`exu.MaterialExists` before assigning any of them, so the states named in
`CRReactiveProfiles.lua` are skipped until the art lands. Everything else —
impact particles, damage particles, emissive failure, weapon heat, cockpit
reaction — works without them. See the asset list below.

**Cockpit animations are not authored yet.** `exu.animation.Play` returns false
when the local first-person entity has no animation by that name, so the calls
are inert until the viewmodels carry them. `exu.animation` also needs OpenShim's
`OpenShimResolveLocalFirstPersonEntity` bridge to resolve the first-person
target at all.

**Sub-entity indices are a guess.** `materialGroups` in
`CRReactiveProfiles.lua` assumes index 0 is the hull on every stock craft, which
holds, and guesses `weapon` at 1 and `lamps` at 2, which needs confirming per
mesh with `exu.GetSubEntityCount` / `exu.GetSubEntityMaterial`. An index a mesh
does not have is skipped, so an over-long list is harmless.

**Weapon heat has no visual yet.** Heat accumulates and decays correctly and is
readable through `CRReactive.GetWeaponHeat(profileName)`, but nothing draws it:
that needs either an authored per-weapon emissive material group or the HUD
widget from section 10 of the design note. It is presentation only either way —
it never gates firing.

**Not yet started from the design note:** facility/world-object states
(section 7), the reactive HUD layer (section 10), and weather cover detection.

## Asset list

Nothing below blocks the systems from running — every reference currently points
at an asset Campaign Reimagined already ships, and the material file names the
substitute in a comment beside each block. This is the list that replaces the
placeholders.

### Particle billboard textures

Small alpha-blended or additive sprites. Power-of-two, alpha channel required.

| File | Used by | What it is | Current placeholder |
| --- | --- | --- | --- |
| `cr_rain.png` | `CR_FX/Rain` | Soft vertical rain streak, ~16×64 | `white.png` |
| `cr_splash.png` | `CR_FX/RainSplash` | Small expanding ground splash ring, ~32×32 | `wpuff_0.png` |
| `cr_snow.png` | `CR_FX/Snow` | Crystalline flake with a bright core, ~32×32 | `wpuff_0.png` |
| `cr_dust.png` | `CR_FX/Dust` | Soft irregular dust mote, heavy falloff, ~64×64 | `smoke.png` |
| `cr_grit.png` | `CR_FX/Grit` | Hard sand fleck, near-opaque centre, ~16×16 | `bpuff.png` |
| `cr_ash.png` | `CR_FX/Ash` | Ragged dark ash flake, ~32×32 | `smoke.png` |
| `cr_ember.png` | `CR_FX/Ember` | Hot ember point with a bloom halo, ~32×32 | `flare.png` |
| `cr_spore.png` | `CR_FX/Spore` | Luminous alien spore, soft ring structure, ~64×64 | `flare.png` |
| `cr_spark.png` | `CR_FX/Spark` | Short bright metal spark streak, ~32×8 | `bulhit.png` |
| `cr_bloom.png` | `CR_FX/Bloom` | Hot impact bloom, white core to orange edge, ~64×64 | `blast.png` |
| `cr_debris.png` | `CR_FX/Debris` | Dark debris fleck, ~32×32 | `smoke.png` |
| `cr_ion.png` | `CR_FX/Ion` | Ionised discharge, cyan filaments, ~64×64 | `shock.png` |
| `cr_bioburst.png` | `CR_FX/BioBurst` | Biological rupture, cyan-violet, ~64×64 | `shock.png` |
| `cr_smoke_thin.png` | `CR_FX/SmokeThin` | Wispy grey smoke puff, ~64×64 | `smoke.png` |
| `cr_smoke_heavy.png` | `CR_FX/SmokeHeavy` | Dense dark smoke puff, ~128×128 | `smoke.png` |
| `cr_arc.png` | `CR_FX/Arc` | Electrical arc filament, ~64×32 | `shock.png` |
| `cr_bioleak.png` | `CR_FX/BioLeak` | Luminous plasma leakage, ~64×64 | `flare.png` |

### Damage-state material sets

Each is a child of `CR_BZBase` with its own texture set (`_D`, `_N`, `_S`, `_E`).
These are shared states, not per-craft: one set covers every craft in that
faction's visual language, and sub-entity assignment picks the state per craft.
Until they exist the reactive layer skips them.

| Material | What it is |
| --- | --- |
| `CR_Hit/Ionized` | Transient: brief blue-white emissive flash over the hull |
| `CR_Hit/Scorch` | Transient: soot and heat discoloration at the impact area |
| `CR_Hit/BioSurge` | Transient: cyan luminescence propagating through a Fury hull |
| `CR_Dmg/Scarred` | Persistent, 70–40%: scoring, scuffed paint, no structural loss |
| `CR_Dmg/Failing` | Persistent, 40–20%: panel loss, exposed structure, soot |
| `CR_Dmg/Critical` | Persistent, <20%: blackened, buckled, glowing stress fractures |
| `CR_Dmg/BioScarred` | Fury equivalent: luminescence instability |
| `CR_Dmg/BioFailing` | Fury equivalent: dimmed channels, localised dark intervals |
| `CR_Dmg/BioCritical` | Fury equivalent: severe pulsing, dark intervals, bright surges |

### Weather skydome textures

2048×2048, authored for a skydome (not a cubemap). Only needed once a mission
uses `CRWeather.SetBaseSky`.

| Material | Storm |
| --- | --- |
| `CR_Sky/MarsStorm` | Orange-brown dust ceiling, visible motion |
| `CR_Sky/Blizzard` | Blue-grey overcast, dense |
| `CR_Sky/AshFall` | Dark ceiling with an orange horizon glow |
| `CR_Sky/Spore` | Cyan-violet alien haze, non-Earth structure |
| `CR_Sky/Storm` | Conventional dark storm cloud |

### Cockpit animations

Animation clips on the first-person viewmodel meshes, named exactly as listed.
Each craft family in `CRReactiveProfiles.CockpitProfiles` wants the same set.
Missing clips are simply not played.

| Clip | When it plays |
| --- | --- |
| `hit_front`, `hit_rear`, `hit_left`, `hit_right` | Directional impact on the player's craft |
| `hit_heavy` | Rocket, missile or mortar impact |
| `recoil_cannon`, `recoil_rocket`, `recoil_mortar` | Player fires that weapon family |
| `cockpit_critical` | Reserved for the critical-damage state |

### Audio

| File | Used by |
| --- | --- |
| `xthunder.wav` | `AcidRainVisual` lightning policy, played after a distance delay |

## Validation status

- EXU builds clean (`ExtraUtilities.vcxproj`, Release/Win32).
- Every new Ogre symbol the attachment and emitter code resolves was confirmed
  present in the shipped `OgreMain.dll` export table before it was used.
- Both Lua modules pass an offline smoke test that drives 600 frames of impacts,
  damage-band transitions, a preset change and a stand-down against a stubbed
  `exu`, and asserts that shutdown leaves zero live particle systems and zero
  material overrides.
- **Not yet validated in the running game.** No in-game visual pass, no frame
  cost measurement, and no save/load or mission-change cycle has been run.
