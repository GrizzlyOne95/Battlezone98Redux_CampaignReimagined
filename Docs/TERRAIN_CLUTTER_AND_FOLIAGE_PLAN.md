# Terrain Clutter and Foliage Plan

## Status

Phase A now has a deliberately small implementation: one deterministic grass
layer in `misn02b`, one cross-quad grass mesh and material, and a reusable EXU
bulk bridge to Ogre `StaticGeometry`. The prototype is intended to prove the
rendering and lifecycle path before CR grows a biome system.

The first layer is a controlled patch around the `misn02b` player start. It is capped at
128 clumps, excludes a 12 metre circle around the spawn point, rejects slopes
above 22 degrees, and is built once rather than updated per frame.

## Ownership and architecture

- CR owns placement policy, profiles, authored assets, mission integration,
  weather use, and future foliage shaders.
- EXU owns the reusable Lua-facing `StaticGeometry` primitive. It accepts a
  batch of transforms, creates one temporary Ogre entity, adds the transforms,
  builds the static geometry, and destroys the temporary entity.
- OpenShim owns renderer-wide material-scheme policy. CR must not duplicate its
  Enhanced scheme fallback.
- `CRWeather.GetWind()` is the only wind authority. Foliage must not maintain a
  second direction, strength, or gust simulation.

The shipped Ogre 1.10 runtime exports the required `SceneManager` and
`StaticGeometry` entry points: create/destroy/lookup, add entity, configure
regions/origin/distance/visibility/shadows, build, reset, and destroy. The EXU
bridge resolves those shipped exports dynamically so the primitive remains
reusable and does not extend CR with native renderer code.

## Phase A profile

The current CR schema is:

```lua
{
    name = "unique mission-scoped name",
    material = "Ogre material name",
    mesh = "mesh resource name",

    center = positionOrPath,
    radius = metres,
    density = instancesPerSquareMetre,
    maxInstances = safetyCap,
    minScale = number,
    maxScale = number,

    slopeMin = degrees,
    slopeMax = degrees,
    heightMin = worldHeight,
    heightMax = worldHeight,
    waterLevel = optionalWorldHeight,

    terrainTypes = optionalArray,
    terrainTypeAt = optionalQueryFunction,
    exclusionAreas = optionalBzrAreaNames,
    exclusionCircles = optionalCircleArray,
    seed = integer,

    regionDimensions = { x = 128, y = 256, z = 128 },
    renderingDistance = metres,
    castShadows = false,
}
```

Placement uses a local Park-Miller seeded generator. It samples a disk
uniformly, queries existing `GetTerrainHeightAndNormal`, applies slope/height/
water/exclusion filters, and submits accepted transforms to EXU in one call.
The same mission data and seed produce the same transforms. Placement is not
performed in `Update()` except for a single deferred rebuild after loading a
save.

CR does not currently expose a general terrain-type-at-position query.
`terrainTypes` is therefore supported only when a caller supplies the narrow
`terrainTypeAt(position)` capability. A profile requesting terrain types
without that capability fails gracefully rather than silently placing on the
wrong terrain. Phase A does not invent a new terrain-query framework.

## Lifecycle and diagnostics

Each layer name is unique within the Lua state. Building a layer first destroys
an EXU-owned layer with the same name. Save reload therefore replaces rather
than duplicates the grass. Mission/Lua-state shutdown destroys every EXU-owned
static geometry object before state bookkeeping is released.

The build log reports accepted instance count, requested count, attempts,
estimated occupied regions, native build time, and total Lua placement/startup
time. EXU also exposes layer info and visibility controls for diagnostics. A missing profile, invalid profile,
missing terrain query, or unavailable EXU API logs a reason and does not crash
the mission.

## Wind

Phase A is intentionally static. `TerrainClutter.GetWind()` is a safe read of
`CRWeather.GetWind()` and returns a zero vector when weather is absent or not
initialized, but no shader parameter is updated yet.

Phase B should use a global material/shader parameter, not per-instance CPU
updates. The vertex shader should combine the authoritative wind direction and
magnitude with time, world-position phase variation, and a vertex-height mask
so roots stay fixed and neighbouring clumps do not move in lockstep. Gusts and
local weather remain inputs from `CRWeather`; foliage must not simulate them.

## Renderer behavior

The Phase A material intentionally has a valid base technique and no `en-*`
technique. A missing Enhanced technique is **not** expected to render black.
With OpenShim PR #169, `EnhancedSchemeFallback` selects the supported base
technique, so the grass must remain visible under DX11 Enhanced. This is a
regression qualification for Phase A, not a reason to reproduce fallback logic
in CR.

An Enhanced-specific technique remains desirable for visual parity and quality
but does not block Phase A. The baseline must be qualified on DX9, DX11
default, and DX11 Enhanced (specifically exercising the base-technique
fallback).

## Performance boundaries

Phase A creates no scene node or persistent entity per clump, performs no
per-instance Lua update, and never rebuilds per frame. The test patch is local
and capped; it is not map-wide dense placement. Alpha-tested cross quads and a
finite rendering distance bound transparent overdraw.

Future map-scale work must measure mission-start cost, instance/region counts,
view distance, and overdraw before raising density. Region streaming or
density/view-distance LOD should be introduced only when measurements show the
single-build approach is insufficient.

## Validation gates

Phase A is complete only when the following are recorded in the accompanying
validation note:

- Lua 5.1 syntax and existing CR validators;
- deterministic placement and increasing-count stress cases;
- create, build, cleanup, and recreate without duplicates;
- graceful invalid/absent profile behavior;
- weather absent/uninitialized and zero wind behavior;
- EXU build/tests and export resolution against the shipped Ogre runtime;
- in-game `misn02b` smoke test and reload, when a local game is available;
- DX9, DX11 default, and DX11 Enhanced visibility. Enhanced must use a material
  with no `en-*` technique to qualify OpenShim's fallback.

Static/host validation must not be reported as visual success.

## Phase B (deferred)

1. Add shader-driven bending from `CRWeather.GetWind()` with height masking,
   time, and world-position phase/noise.
2. Author and qualify an Enhanced-specific foliage technique.
3. Measure and tune region dimensions, density, rendering distance, LOD, and
   transparent overdraw on representative large maps.
4. Add planet/mission profiles and several grass species, then shrubs,
   rocks/debris, terrain weighting, and biome variation as measured needs
   justify them.
5. Add reusable building/route exclusions only if existing mission areas and
   circles prove inadequate.
6. Consider vehicle flattening/destruction and local weather response only
   after the static system is stable and their gameplay value is established.
