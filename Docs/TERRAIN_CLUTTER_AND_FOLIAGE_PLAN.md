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

Foliage sways on the GPU; Lua writes one float4 per material when the wind
changes, never per instance or per frame.

- **Weights.** StaticGeometry bakes vertices into region space, so the shader
  cannot recover a vertex's height above its own root. `Tools/Bake-FoliageSway.py`
  instead adds a TEXCOORD1 stream of (bend, flutter) weights in 0..1 to each
  foliage submesh, on its own vertex buffer, and renames the submesh to the
  wind material. A wind material on an unbaked mesh fails the D3D11 vertex
  declaration on every draw, so the still materials stay for other meshes.
  - `plant` mode: bend = h^1.5, flutter = h (ferns, fronds, reeds, grass).
  - `tree` mode: the bark keeps its BZBase material and does not move; the
    canopy bends with h^2 and flutters with h times its distance from the trunk.
- **Programs.** `cr17_surface.hlsl`/`-vertex.glsl` gain a `WIND` path
  (`cr17_wind.program`, every Plain/Shadow/PSSM/Caster variant) and
  `CR_textured*.hlsl` a `textured_wind_vertex` entry (`CR_grasswind.program`).
  Both use the same displacement: a directional bend of
  `windShape.x * bend * amp * (0.6 + 0.4 sin(time * windShape.y + phase))` plus a
  3-axis flutter of `windShape.z * flutter * amp` at `windShape.w`, with
  `amp = saturate(speed / 20) * (1 + 0.6 gust) * scale` and a world-position
  phase so neighbours never move in lockstep. The offset is computed in world
  space and taken back through `inverse_world_matrix`.
- **Feed.** `windParams` = (wind x m/s, gust 0..1, wind z m/s, scale). The CR17
  programs read it from the pass emissive colour, which their fragments ignore;
  `CR_GrassWind` reads specular, because `CR_Textured_fragment` uses emissive as
  lighting. `windShape` is a per-material constant.
- **Driver.** `Scripts/CRFoliageWind.lua` registers wind materials and writes
  `exu.SetMaterialPassColors(material, {slot = ...}, -1, -1, nil, true)` (all
  techniques and schemes, glow included: the glow fragments read diffuse or
  emissive, not the wind slot). `CRWeather.Update` calls it after stepping, so
  `CRWeather` stays the only wind authority: bearing from `GetWind()`'s xz,
  magnitude from `GetWindSpeed()`, gust from the new `CRWeather.GetGust()`.
  Registration and `Stop` write calm, because Ogre materials outlive the
  mission's Lua state. `CRWeather.Shutdown` stops it; `ResetSystems` (load)
  recreates the litter.
- **Leaf litter.** `CRFoliageWind.EnableLitter(points)` bins foliage placements
  into a 32 m grid. `CR/LeafLitter` (`cr_foliage.particle.payload`, sprite
  `cr_leaf.png` from `Tools/Build-LeafTexture.py`) rides the camera; its rate is
  `rate * density near the camera * wind above minSpeed * gust`, and its
  emitter and LinearForce follow the wind.

Wired today: misn17's jungle (`CR17/LeavesWind` canopies, `CR17/GroundWind`
ground cover, `CR17/CutoutCaster/FoliageWind` shadow casters, litter from every
ground-cover placement). A TerrainClutter profile opts in with
`wind = { slot = "specular", litter = {...} }` and the `CR/GrassWind` material;
misn02b keeps `CR/GrassPrototype`, because the Moon has no wind.

Regenerating: `Tools/Build-FoliageWindMaterial.py` writes
`cr17_wind.material` from `cr17_surface.material` (CI runs `--check`). Rerun
`Bake-FoliageSway.py` after re-exporting any foliage mesh, including
`crgrass.mesh` from `Tools/Assets/crgrass.mesh.xml`, or the stream is lost.

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

## Phase B

1. Done: shader-driven bending and leaf litter (see Wind).
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
