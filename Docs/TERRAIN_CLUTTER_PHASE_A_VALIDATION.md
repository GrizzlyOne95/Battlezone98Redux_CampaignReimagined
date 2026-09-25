# Terrain Clutter Phase A Validation

Date: 2026-09-20

This note distinguishes host/static checks from in-game visual qualification.
It is updated as each lane is run.

## Implemented scope

- Deterministic, filtered placement in one controlled `misn02b` patch.
- One cross-quad `crgrass.mesh`, transparent `crgrass.png`, and baseline
  `CR/GrassPrototype` material.
- One bulk EXU/Ogre `StaticGeometry` build per layer.
- Destroy-before-recreate and Lua-state shutdown cleanup.
- Build diagnostics for instances, attempts, estimated regions, and build time.
- No wind deformation; the weather-safe authoritative wind read is present for
  Phase B.

## Host/static results

- `python Tools/Validate-CampaignRepository.py`: passed.
- `lua Tools/Test-TerrainClutter.lua Scripts`: passed deterministic placement,
  exclusion filtering, graceful failures, missing/zero weather wind, explicit
  destroy-before-recreate, BZR-style missing `os` timing fallback, shutdown,
  and 32/128/512-instance stress cases.
- Changed Lua parsed under the local Lua 5.4 compiler and executed successfully
  in BZR's shipped Lua 5.1 runtime. CI performs the additional stock Lua 5.1
  compiler gate.
- `Tools/Test-ProgramReferences.ps1`: all owned program references resolve.
- `Tools/Test-DX11ShaderValidator.ps1`: source guards and all 17 mutation
  fixtures passed.
- EXU `Release|x86`: built with `/W4 /WX`, 0 warnings and 0 errors.
- EXU hardening smoke, parameter-value, render-space, API-parity, version-parity,
  and address-catalog tests: passed.
- Shipped `OgreMain.dll` exports and Ogre 1.10 source were checked for
  SceneManager create/destroy/lookup, entity add/destroy/material assignment,
  region/origin/distance/visibility/shadow configuration, build/reset/destroy,
  and SceneManager ownership cleanup.

## Resolution (2026-09-21)

**Visibility is no longer unverified.** The table below is the historical
record of what this validation pass could and could not establish on
2026-09-20; do not re-open the investigation it describes.

The cause was not in this repository: `exu.CreateStaticGeometry` built every
instance in BZR simulation coordinates instead of Redux's render space
(origin-recentred, Z-mirrored). Every renderable Redux draws goes through
that conversion — EXU's particles already made it — and StaticGeometry was
the one path that skipped it. It built correctly, reported success, and was
placed several thousand units outside the render world, identically on every
backend, which is exactly what "unverified" below was hiding.

Fixed in `ExtraUtilities`
[PR #29](https://github.com/GrizzlyOne95/ExtraUtilities/pull/29)
(`OgreRenderSpace::SimPositionToRender`/`SimOrientationToRender` applied to
every instance and to the region-bucketing origin). Confirmed live
2026-09-20 on Achilles via
`BZR-OpenShim/reverse_engineering/test_missions/lcbveg`, DX11 Enhanced: three
patches of 739 instances each rendered, at the exact lift heights (0.02 / 3 /
10 units) the bench placed them at.

The desktop-capture gap noted below is a separate, still-open limitation of
this validation harness; the resolution came from a live GOG launch with a
human observer, not from solving that gap.

## Runtime qualification (historical, 2026-09-20, pre-fix)

Direct GOG launches proved the native resource and lifecycle path. The desktop
provider could not expose the native game window, so the viewport could not be
captured or inspected. Visibility was recorded unverified below and was not
inferred from successful resource loading.

| Backend/profile | Map | Instances | Visible | Reload cleanup | Evidence |
| --- | --- | ---: | --- | --- | --- |
| DX9 | `misn02b` | 115 / 4 regions | unverified | passed on graceful teardown | CLI override reported effective DX9; mesh/texture loaded; one build at 0 ms; one object cleared |
| DX11 default | `misn02b` | 115 / 4 regions | unverified | passed on graceful teardown | effective profile changed to Redux; D3D11 texture loaded; one build at 16 ms; one object cleared |
| DX11 Enhanced, no `en-*` technique | `misn02b` | 115 / 4 regions | unverified | passed on graceful teardown | effective Enhanced; `en-high-pssm`; fallback listener installed; material parsed and resources loaded; one build at 0 ms; one object cleared |

Three clean launches each created one named StaticGeometry object and each
graceful shutdown cleared one tracked object. Host tests separately prove the
same-state destroy-before-recreate order used by save reload. An interactive
in-process save reload remains visually unverified because native window input
was unavailable.

The rebased branch was deployed again through `Manage-CampaignFiles.ps1`:
4 foliage files were added, 4 integration files were updated, and 3,322 files
were unchanged on the first deployment. A final one-file Lua correction was
then deployed, and the manager's automatic post-deploy verification reported
0 missing, 0 differing, and 0 unexpected shipped files.

## Known Phase A limits

- No generic terrain-type query is available; profiles requiring terrain types
  must supply a query callback.
- Water rejection uses an optional known water height; the controlled patch
  does not add a generalized water-body query.
- Wind deformation, Enhanced-specific shading, biome profiles, LOD/streaming,
  and vehicle interaction are Phase B or later.
