# DX11 Enhanced PSSM v2

Status: **IMPLEMENTED + STATICALLY VALIDATED**
Visual status: **PENDING** (workstation was locked/unattended)

The complete BZR/BZCC evidence audit is in OpenShim's
`reverse_engineering/campaign_reimagined_enhanced_pssm_audit_20260820.md`.
This document describes the CR-owned implementation, configuration, cost, and
the exact later visual acceptance pass.

## Isolation

The feature is active only when all of these are true:

```text
DX11 SM4 + ENHANCED_MODE + SHADOWRECEIVER + PSSM_ENABLED
+ CR_ENHANCED_PSSM_V2=1
+ the Enhanced comparison-sampler material pass
```

The active schemes use `BZPassSchemeENHighPSSMV2` for objects and
`BZTerrainPassSchemeENHighPSSMV2` for terrain. Classic continues to use the old
abstract PSSM passes and ordinary samplers. DX9 HLSL was not edited.
Each material also keeps a second `en-high-pssm` lod-0 technique using the
original pass. The v2 technique's vertex program is intentionally HLSL4-only,
so DX9 rejects it and selects that unchanged fallback.

| path | result |
|---|---|
| DX9 | unchanged |
| DX11 Classic | unchanged |
| DX11 Enhanced High, no shadow/single shadow | unchanged |
| DX11 Enhanced High, PSSM | v2 |
| Enhanced medium/low/lowest LOD delegates | unchanged |

No OpenShim code or Ogre binary patch is required.

## Behavior

### Filtering

Each selected cascade uses four `SampleCmpLevelZero` reads from a bilinear
comparison sampler at symmetric half-texel offsets. This is a compact
three-texel tent-like PCF footprint based on BZCC's four-hardware-tap strategy.
It replaces 16 ordinary linear depth reads followed by manual `step()` compares.

### Cascade transitions

The BZR executable supplies splits `0.1, 16, 64, 256`. Ogre already pads
adjacent cameras by one unit, producing valid overlap at `[15,17]` and
`[63,65]`. V2 applies Hermite/smoothstep blending only in those ranges:

```text
cascade 0 ---- [0 -> 1 blend] ---- cascade 1 ---- [1 -> 2 blend] ---- cascade 2
                 15 .. 17                              63 .. 65
```

Normal pixels sample four comparison taps. Pixels in either blend interval
sample eight. V2 never pays the double-sampling cost outside the overlap.

### Receiver bias

Objects and terrain use the same object-space normal-offset rule before all
three shadow matrix transforms:

```text
offset = min(0.04 + 0.0002 * max(clipDepth, 0), 0.10)
shadowPosition = position + normalize(normal) * offset
```

BZCC ships the same mathematical technique at `0.2 + 0.001 * viewDepth`.
CR intentionally starts at one fifth of those coefficients and caps the result.
The BZCC constants cannot be assumed to share BZR's scene scale or peter-panning
budget. There is no new constant projected-depth subtraction and no unbounded
slope reciprocal.

### Far fade

Cascade 2 remains fully weighted through depth 232, then its shadow contribution
fades smoothly to fully lit at 256. Geometry beyond 256 performs no shadow map
lookup. Depth values are never modified to create the fade.

## Configuration: before and after

| parameter | V1 | V2 |
|---|---:|---:|
| cascade count | 3 | 3 |
| split points | 0.1 / 16 / 64 / 256 | unchanged |
| shadow resolutions by PSSM quality | 1024 / 2048 / 4096 | unchanged |
| map format | `PF_FLOAT32_R` / `R32_FLOAT` | unchanged |
| PCF reads, normal region | 16 ordinary samples | 4 comparison samples |
| PCF reads, blend region | n/a | 8 comparison samples |
| sampler | linear ordinary | bilinear comparison, greater-equal |
| cascade blend half-width | 0 | 1.0 |
| active receiver shadow bias | none | normal offset 0.04 + 0.0002/depth, max 0.10 |
| far fade | none | 232 to 256 |
| Enhanced shadow ambient floor | 0.22 | unchanged |
| camera stabilization | none in Focused/PSSM path | unchanged / deferred |

The named constants are declared together near the top of both SM4 shaders:

- `CR_PSSM_CASCADE_BLEND_HALF_WIDTH`
- `CR_PSSM_FAR_FADE_WIDTH`
- `CR_PSSM_NORMAL_OFFSET_BASE`
- `CR_PSSM_NORMAL_OFFSET_PER_DEPTH`
- `CR_PSSM_NORMAL_OFFSET_MAX`

Keep the base and terrain values synchronized.

## A/B selection

The old algorithm remains behind the compile-time flag, and its ordinary-sampler
material passes remain intact. Switch both halves safely with:

```powershell
.\Tools\Set-EnhancedPssmVersion.ps1 -Version V1
.\Tools\Validate-DX11Shaders.ps1

.\Tools\Set-EnhancedPssmVersion.ps1 -Version V2
.\Tools\Validate-DX11Shaders.ps1
```

The selector updates only the six Enhanced PSSM HLSL4 program definitions and
the two Enhanced lod-0 material pass references. This keeps sampler state and
shader sampler type paired. The branch is left in V2 state.

## Automated validation

Run:

```powershell
.\Tools\Test-EnhancedPssmV2.ps1
.\Tools\Validate-DX11Shaders.ps1
```

The focused test validates:

- selection before, at, inside, and after both split bands;
- blend/fade values stay in `[0,1]`;
- continuity at 15, 17, 63, 65, 232, and 256;
- `fade(232)=0`, `fade(256)=1`, with monotonic values between;
- normal offset is finite and bounded for zero, tiny, axial, and grazing normal
  inputs and depths through an extreme `1e9` case;
- DX9 source contains no v2 flag;
- exactly three comparison-enabled texture units exist per v2 material pass;
- object/terrain VS, non-IBL PS, and IBL PS variants compile;
- DXBC reflection declares comparison samplers and assembly emits
  `sample_c_lz`.

The repository-wide validator compiled 230 SM4 permutations successfully,
including all affected object, terrain, PSSM, IBL, linear-light, radial-fog, and
terrain-normal diagnostic combinations.

An independent origin/main compile comparison produced byte-identical DXBC for
Classic object PSSM, Classic terrain PSSM, Enhanced V1 object PSSM, and Enhanced
V1 terrain PSSM. The inactive v2 source blocks therefore do not perturb the
baseline algorithms.

## Generated shader cost

FXC 10.1 (`vs_4_0` / `ps_4_0`) reports:

| variant | V1 slots | V2 slots | static ordinary sample ops | static comparison ops |
|---|---:|---:|---:|---:|
| object PSSM PS, no IBL | 629 | 516 | 52 -> 4 | 0 -> 28 |
| terrain PSSM PS, no IBL | 643 | 530 | 54 -> 6 | 0 -> 28 |
| object PSSM PS + IBL | n/a in focused baseline | 574 | 7 | 28 |
| terrain PSSM PS + IBL | n/a in focused baseline | 587 | 9 | 28 |
| object V2 VS | — | 36 | 0 | 0 |
| terrain V2 VS | — | 46 | 0 | 0 |

The 28 static comparison opcodes are mutually exclusive branch bodies:
4 + 8 + 4 + 8 + 4. Runtime shadow fetches are 4 normally, 8 in only four total
depth units, and 0 beyond 256. The extra VS work normalizes one normal, computes
one bounded scalar, and transforms the already-required position through the
same three matrices.

This predicts neutral-to-lower shader cost outside narrow transition bands, but
it is not a frame-time measurement. GPU/FPS capture remains part of live
acceptance.

## Exact visual acceptance procedure

Use the GOG development install and the CR manager/development deployment; do
not edit the Steam Workshop cache.

1. Select DX11, Enhanced High, and PSSM shadow quality.
2. Run `misn04.bzn`. It has already been used for CR DX11 terrain/lighting work.
3. Start at the NSDF base/player area near map `(x=1909, z=100764)`; the allied
   recycler is near `(1933,100685)`. Face across the open corridor toward the
   distant Soviet recycler near `(3630,99806)`.
4. Capture V1, then V2, with the same mission start, sun state, camera, and
   settings. Do not compare different mission timing.
5. At the initial recycler/buildings, inspect terrain contact, vehicle underside,
   hull facets, vertical walls, and a long straight shadow edge for acne and
   peter-panning.
6. Drive slowly forward/backward and strafe while watching geometry cross the
   16- and 64-unit cascade distances. Rotate the camera slowly. Reject a visible
   seam, brightness line, or transition pop.
7. Continue observing a building edge, terrain ridge, and vehicle shadow during
   very slow movement. Record shimmer separately; v2 does not yet stabilize the
   Ogre camera matrices.
8. Compare near and far softness. Reject excessive blur or a shifted/asymmetric
   edge. Inspect the far field for a smooth end rather than a line at 256.
9. Record matched screenshots and GPU/frame time or FPS in a representative busy
   Enhanced High scene.

Acceptance checklist: cascade seam, transition pop, shimmer, terrain/vehicle
acne, building/vehicle/pilot contact, peter-panning, near/far softness, far
cutoff, and performance.

## Known limitations

- No claim of live visual validation is made.
- Normal-offset and fade constants are mathematically bounded but still visual
  tuning values (MEDIUM confidence).
- BZCC's actual runtime split distances, map resolutions, sampler descriptor,
  and CPU stabilization were not captured.
- Symmetric half-texel taps adapt BZCC's four-tap strategy to Ogre coordinates;
  edge centering must be checked visually.
- BZR's Focused/LiSPSM camera setup permits swimming and remains unchanged.
- The fourth BZCC cascade was not backported; there is no evidence that adding
  distance is preferable to improving the existing three cascades.

## Final status matrix

| Component | Static audit | Automated validation | Runtime non-interactive | Visual validation |
|---|---|---|---|---|
| Cascade blending | complete | PASS | assembly checked | PENDING |
| PCF | complete | PASS | R32 comparison support PASS | PENDING |
| Bias | complete | PASS | compiled assembly checked | PENDING |
| Stabilization | complete; missing snap identified | not implemented | no matrix capture | PENDING |
| Far fade | complete | PASS | assembly checked | PENDING |
