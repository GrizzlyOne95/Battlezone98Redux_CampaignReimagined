# DX11 Legacy-PBR Phase 2: Static Image-Based Lighting

This phase extends the experimental DX11 Enhanced/Legacy-PBR path with static image-based lighting (IBL). It is intentionally renderer-hook-free: the game still uses the existing forward lights, PSSM shadows, fog, transparency, emissive behavior, and material system.

## Scope

The Enhanced DX11 high tier becomes:

```
Direct GGX lighting
+ diffuse irradiance
+ roughness-aware specular environment reflection
+ emissive
+ existing shadows and fog
```

Out of scope for this phase:

- dynamic reflection probes;
- SSR;
- HDR/FP16 render targets;
- GTAO/SSAO/contact shadows;
- depth/normal buffer exposure;
- renderer/EXE hooks;
- metallic inference or ORM reinterpretation of legacy maps.

DX9, GL, Retro/OG, and the existing lower Enhanced compatibility delegates remain on their previous paths.

## Split-sum IBL

The direct-light BRDF from Phase 1 is unchanged. The ambient/environment term uses the common split-sum approximation:

1. A low-frequency irradiance cubemap is sampled by the final shaded normal.
2. A GGX-prefiltered environment cubemap is sampled by the reflection vector at a mip selected by derived roughness.
3. A 2D BRDF integration LUT is sampled by `NdotV` and roughness.
4. The same legacy-derived F0 and roughness used by direct GGX lighting drive the IBL result.

The shader does not infer a metallic channel. Diffuse ambient remains present and is reduced only by Fresnel energy sharing.

## Stable environment space

The Phase-1 BRDF works in view space because BZR supplies light positions/directions in view space. Cubemap lookup vectors must not rotate with the camera, so the IBL variants bind Ogre's `inverse_view_matrix` automatic parameter and rotate the final normal/reflection vectors back into world/environment space before sampling.

This is shader/program-only and does not require an engine hook.

## Resources

Checked-in runtime bootstrap resources live directly under `Textures/` so they resolve through the same resource location as existing shared textures without depending on recursive subdirectory scanning:

- `cr_ibl_neutral_irradiance.dds` - 32x32 BC1 cubemap;
- `cr_ibl_neutral_prefilter.dds` - compact 32x32 BC1 cubemap with a full mip chain for the repository bootstrap set;
- `cr_ibl_brdf_lut.png` - 64x64 RG split-sum BRDF LUT.

`Tools/Generate-StaticIBL.py` regenerates the reference set using real cosine-weighted irradiance integration, GGX importance-sampled prefiltering, and BRDF integration. Its default output directory is `Textures/IBL` so generation can be staged without overwriting the runtime set accidentally. Its default prefiltered cube is 128x128 with eight mips, so replacing the compact checked-in bootstrap cube with the generated 128px version requires no shader-layout change.

To intentionally regenerate the runtime copies in place:

```powershell
python .\Tools\Generate-StaticIBL.py --output .\Textures
```

NumPy is required only by the offline generator, not by the game.

## Texture aliases

The material integration exposes three aliases:

- `IrradianceMap`
- `PrefilteredEnvironmentMap`
- `EnvironmentBrdfLut`

The default aliases point at the neutral reference environment. A material or theme-specific child can replace the first two without changing shader code. The BRDF LUT is shared globally.

The current material system does not expose a global per-map alias switch for every shared vehicle/building material. Therefore the no-hook first implementation uses the neutral environment as the safe global fallback and applies only a weak tint from the existing scene ambient/fog values. Terrain/theme-owned materials can override the aliases directly. A true automatic map-wide environment selector would be a later, very small engine/shim integration rather than something to fake in this shader phase.

## Resource/register layout

IBL resources are appended after the existing material and shadow textures. Existing texture registers do not move.

### Base/object high tier

| Variant | Existing last resource | Irradiance | Prefilter | BRDF LUT |
| --- | ---: | ---: | ---: | ---: |
| no shadow | t3 | t4 | t5 | t6 |
| one shadow | t4 | t5 | t6 | t7 |
| PSSM | t6 | t7 | t8 | t9 |

### Terrain high tier

| Variant | Existing last resource | Irradiance | Prefilter | BRDF LUT |
| --- | ---: | ---: | ---: | ---: |
| no shadow | t4 | t5 | t6 | t7 |
| one shadow | t5 | t6 | t7 | t8 |
| PSSM | t7 | t8 | t9 | t10 |

## Calibration constants

The IBL calibration is isolated from the Phase-1 BRDF:

- `CR_IBL_DIFFUSE_INTENSITY = 0.62`
- `CR_IBL_SPECULAR_INTENSITY = 0.82`
- `CR_IBL_LEGACY_AMBIENT_RETAIN = 0.20`
- `CR_IBL_SCENE_TINT_STRENGTH = 0.18`
- `CR_IBL_MAX_SPECULAR_MIP = 7.0`

The last value targets the generated 128px reference cube. Sampling the compact bootstrap cube automatically clamps at its last available mip.

The 20% legacy ambient floor is deliberate for the first test build. Once mission-to-mission IBL exposure is validated, it can be lowered or removed instead of compensating with gamma hacks.

## Material interpretation

Phase 2 intentionally reuses Phase 1's conservative legacy conversion:

- diffuse remains diffuse/albedo input;
- legacy specular RGB derives F0 conservatively;
- material shininess is the primary roughness source;
- the specular map only weakly biases roughness;
- normal-map variance increases roughness to reduce shimmer;
- emissive remains independent;
- no manual `pow(..., 2.2)` decode is introduced until Ogre resource sRGB state is verified.

IBL is expected to expose poor legacy F0/roughness calibration more aggressively than direct light. If ordinary painted assets become chrome, adjust the legacy mapping/constants rather than adding a metallic heuristic.

## Validation

Run the SM4 compiler matrix on Windows:

```powershell
.\Tools\Validate-DX11Shaders.ps1
```

The validator includes no-shadow, single-shadow, and PSSM IBL variants for both base and terrain shaders in addition to the Phase-1 compatibility cases.

In BZR, validate at minimum:

1. Enhanced DX11 launches and changes missions repeatedly without device removal/crashes.
2. Reflections remain fixed to the world while the camera rotates.
3. Cubemap orientation is correct on all axes.
4. Normal maps perturb the environment reflection in the expected direction.
5. Smooth legacy materials receive sharper reflections and rough materials receive broader reflections.
6. Roughness transitions through the cubemap mip chain without obvious bands or sparkling.
7. Ordinary painted vehicles/buildings do not become chrome.
8. Dark/specular-poor materials do not become unnaturally reflective.
9. Direct directional/point/spot GGX lighting remains consistent with Phase 1.
10. PSSM/no-shadow paths still render correctly.
11. Emissive, transparency, fog, and terrain detail remain intact.
12. Enhanced high-to-medium/low LOD transitions are inspected, because Phase 2 remains high-tier-only just like Phase 1.
13. DX9 and Retro/OG output is unchanged.

## Deferred follow-ups

After IBL calibration is stable, the next high-value shader-only work remains terrain modernization: macro variation, anti-tiling, and improved detail/roughness behavior. Dynamic probes, SSR, HDR, and depth-driven effects should stay separate because they require materially different renderer support and risk.
