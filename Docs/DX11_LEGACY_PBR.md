# DX11 Legacy-PBR Lighting

This document describes the first experimental physically based direct-lighting pass for the Battlezone 98 Redux Campaign Reimagined shader stack.

## Scope and renderer selection

- **DX9 remains the compatibility/stability renderer.** `CR_base.hlsl` and `CR_terrain.hlsl` are intentionally not part of this milestone.
- **Retro / OG rendering remains unchanged.** `OG_RETRO_MODE` continues to strip normal/specular/emissive map features from the SM4 shaders.
- **DX11 Enhanced High uses the Legacy-PBR path.** The existing `ENHANCED_MODE` high-tier SM4 variants in `CR_base.program` and `CR_terrain.program` already provide the required isolation, so this milestone does not add new UI/config/runtime switching.
- Lower quality / vertex-lighting variants remain on their compatibility lighting path.

The implementation is shader-side only. It does not add renderer hooks, new render targets, environment probes, temporal resources, reflection passes, or new texture requirements.

## Legacy material compatibility

The game material library is treated as a **specular/gloss legacy source**, not as metallic/roughness data.

Existing inputs are interpreted as follows:

- **Diffuse:** consumed as the base/diffuse color supplied by Ogre.
- **Normal:** consumed through the existing tangent or cotangent-frame path.
- **Specular:** conservatively remapped to dielectric/legacy F0 tint and strength.
- **Material shininess:** primary input used to derive perceptual roughness.
- **Emissive:** remains additive and independent of direct illumination.
- **Terrain detail:** unchanged and applied through the existing detail pipeline.

No ORM, metallic, roughness, AO, height, or newly authored textures are required.

### Gamma / linear-light note

The shader intentionally does **not** add a manual `pow()` decode for diffuse/specular textures. BZR/Ogre resource creation and sRGB interpretation must be confirmed before changing texture-space conversion; adding shader-side conversion without that verification risks double-gamma correction. The PBR math operates on the sampled values Ogre provides today.

## Roughness derivation

The baseline conversion is:

```text
roughness = sqrt(2 / (shininess * scale + 2))
```

The result is clamped to avoid singular GGX highlights and excessive aliasing.

A deliberately weak specular-map heuristic then nudges roughness based on legacy specular intensity. This is not a `1 - specular = roughness` conversion; specular strength and roughness remain separate properties.

Finally, when a normal map is active, screen-space normal derivatives (`ddx` / `ddy`) estimate high-frequency normal variance and increase effective roughness. This reduces distant sparkle and unstable micro-highlights without discarding normal-map detail.

## BRDF

Enhanced SM4 direct lighting now uses a Cook-Torrance microfacet model built from:

- GGX / Trowbridge-Reitz normal distribution
- Schlick-GGX geometry term
- Smith masking-shadowing
- Schlick Fresnel
- Fresnel-aware diffuse/specular energy sharing

No metallic classification is inferred in this milestone. Strong legacy specular regions can produce a stronger/tinted F0, but diffuse remains present rather than being aggressively removed as if the material were known to be metal.

The direct-light loop continues to use the existing Ogre/BZR:

- light position arrays
- diffuse/specular light color arrays
- attenuation arrays
- spotlight parameter arrays
- light direction arrays
- light count
- `MAX_LIGHTS`

Directional, point, and spot behavior therefore remains on the existing binding model.

## Shadows and stability

The existing PSSM layout and texture registers are preserved. The existing convention that the primary light receives the shadow term while later local lights do not is also preserved.

The SM4 shadow projection helper now guards against an invalid/near-zero projected `w` before reciprocal projection and clamps inverse map size inputs away from zero. Local-light attenuation also guards its denominator before reciprocal evaluation. These changes are intended to prevent INF/NaN propagation in the DX11 path.

No cascade blending, PCSS, new bias model, or shadow-system redesign is included here.

## Calibration constants

The duplicated Legacy-PBR helper block in `CR_base-sm4.hlsl` and `CR_terrain-sm4.hlsl` is intentional for this milestone. Introducing a new shared include would add shader-resource/loading risk to an already less-stable renderer path. Keep the two blocks synchronized until a shared include is proven safe.

Current tunables:

| Constant | Purpose |
| --- | --- |
| `CR_PBR_MIN_ROUGHNESS` | Lower bound for GGX roughness / highlight stability |
| `CR_PBR_MAX_ROUGHNESS` | Upper bound for very dull legacy materials |
| `CR_PBR_SHININESS_SCALE` | Global calibration for shininess-to-roughness conversion |
| `CR_PBR_SPECULAR_ROUGHNESS_INFLUENCE` | Weak legacy specular influence on inferred smoothness |
| `CR_PBR_NORMAL_VARIANCE_SCALE` | Strength of derivative-based specular AA |
| `CR_PBR_MAX_VARIANCE_ROUGHNESS` | Caps the roughness added by normal variance |
| `CR_PBR_DEFAULT_F0` | Default dielectric F0 when no useful legacy specular color exists |
| `CR_PBR_MAX_LEGACY_F0` | Prevents old specular maps from becoming uncontrolled mirror/chrome values |
| `CR_PBR_DIFFUSE_COMPENSATION` | Retains recognizable brightness for lights authored around legacy Lambert |
| `CR_PBR_SPECULAR_COMPENSATION` | Global direct-specular calibration |

Visual calibration should start with these constants rather than changing BRDF equations or burying new magic numbers in the light loop.

## Validation

`Tools/Validate-DX11Shaders.ps1` compiles representative SM4 variants with Windows `fxc.exe` when a Windows SDK is installed. It covers:

- base and terrain vertex entry points
- Enhanced no-shadow
- Enhanced normal shadow
- Enhanced PSSM
- normal/specular/emissive/detail map feature combinations
- OG/Retro fragment paths

Compilation is necessary but not sufficient. In-game validation should specifically check:

- black/disappearing materials
- blown-out or chrome-like highlights
- rough rock/terrain staying subdued
- normal-map response on buildings/vehicles
- transparency and fog
- emissive independence from direct light
- PSSM behavior across cascades
- directional sun, local point lights, and spotlights
- multiple-light scenes
- specular shimmer while moving the camera
- DX11 device-loss/crash behavior

## Known limitations / next stages

This first pass is direct-lighting only. It deliberately does **not** implement:

- irradiance/environment cubemaps
- prefiltered reflection maps
- BRDF LUTs
- SSR
- dynamic reflections
- HDR render-target changes
- GTAO/SSAO
- temporal filtering
- terrain anti-tiling/triplanar modernization
- major shadow modernization

The BRDF keeps normal, view direction, F0, roughness, and Fresnel concepts separated so a later static IBL pass can reuse the same material interpretation.
