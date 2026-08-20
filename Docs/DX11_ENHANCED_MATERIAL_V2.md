# DX11 Enhanced Material V2

## Outcome

Campaign Reimagined now has an optional, explicitly authored object-material
path for DX11 Enhanced. It is a specular workflow, not a metallic/roughness
conversion:

```text
base colour + normal + linear F0 RGB + perceptual roughness + emissive
                         |                    |
                         +---- direct GGX ----+
                         +---- static IBL ----+
```

Existing materials still inherit `CR_BZBase` or `CR_BZBaseCockpit` and compile
to byte-identical DXBC. A new asset must deliberately inherit
`CR_BZBaseMaterialV2` or `CR_BZBaseCockpitMaterialV2` and bind `MaterialMap`.
There is no filename, brightness, or channel heuristic.

This work is independent of the dynamic-light-selection experiment. It was
implemented from current `main` on `agent/enhanced-material-response`. No
OpenShim change or renderer hook was required.

## 1. Current CR material-semantic audit

The following is the pre-V2 Enhanced object path and remains the exact path for
every non-opted-in material.

| Quantity | Declaration/binding | Shader interpretation | Remap and bounds | Consumer |
| --- | --- | --- | --- | --- |
| Base colour | `DiffuseMap`, object `t0` | sampled RGB multiplied by Ogre `diffuseColor.rgb` and lighting | Stage A only: piecewise sRGB-to-linear decode of RGB; alpha untouched | final reflected surface colour |
| Normal | `NormalMap`, object `t1` | RGB expanded with `* 2 - 1`, sharpened near camera in Enhanced, transformed by tangent/cotangent frame, safely normalized | no colour decode; later derivative variance can raise effective roughness | direct GGX and IBL directions |
| Legacy specular RGB | `SpecularMap`, object `t2` | hybrid tint, strength, and weak smoothness cue | sampled RGB saturated; luminance uses `0.299/0.587/0.114`; no colour decode | F0 conversion and roughness bias |
| F0 | derived from legacy specular RGB | peak channel defines strength; normalized RGB defines tint | `strength = lerp(0.04, 0.45, peak^1.35)`; final blend from `0.04` toward tinted strength by `saturate(peak * 0.90)`; final saturate | direct Fresnel and IBL Fresnel |
| Roughness | Ogre `materialShininess` plus legacy specular luminance | perceptual roughness | `sqrt(2 / (max(shininess,0) + 2))`, clamp `[0.12,0.92]`; multiply by `1 - ((mask-0.5)*2)*0.10`, clamp again | GGX lobe and IBL LOD |
| Normal-variance roughness | derivatives of final view normal | specular anti-aliasing | `variance = min(max(dot(ddxN,ddxN),dot(ddyN,ddyN))*0.30,0.35)`; `sqrt(roughness^2 + variance)`; clamp `[0.12,0.92]` | same effective roughness for direct and IBL |
| Emissive | `EmissiveMap`, object `t3`, plus Ogre `materialEmissive` | separate emitted radiance | Stage A only: RGB decode; intensity is at least `1.0`, may be boosted by material emissive; atmosphere has separate transmission | added after reflected lighting |
| Direct specular | Ogre light arrays and the derived F0/roughness | Cook-Torrance | Schlick Fresnel, GGX NDF, Schlick-GGX/Smith geometry, denominator floors; primary light receives the established shadow term | `specularResult` |
| Static IBL | irradiance cube `t7`, prefiltered cube `t8`, BRDF LUT `t9` on High | split-sum IBL | `mip = saturate(roughness) * 7`; LUT coordinates are `(NdotV, roughness)` | diffuse irradiance plus `prefiltered * (F0*A+B)` |

The roughness convention is therefore confirmed: the stored/derived value is
perceptual roughness. `distribution_ggx` subsequently computes
`a = roughness * roughness` and then `a2 = a * a`. Material V2 must not square,
invert, or perceptually remap its alpha before supplying it. Doing so would be a
double remap.

The existing BRDF already has the required structure and was not rewritten.
Diffuse remains present and is Fresnel-reduced; no metallic classification is
inferred. Its legacy brightness compensation is also preserved.

## 2. BZCC material-semantic audit

Evidence came from the installed BZCC material corpus, DDS headers, DXBC
reflection/disassembly, cross-permutation reports, and source-asset spot checks.
The installed shader source is absent, so confidence is stated per finding.

### Confirmed BZCC behavior

| Evidence | Finding |
| --- | --- |
| 1,492 shipped `.material` files | Materials expose solid diffuse, specular, emissive, and ambient values; `specularPower`; and optional diffuse, team, emissive, normal, and specular textures. |
| DXBC reflection | Default object texture roles are `t0` diffuse, `t1` team, `t2` emissive, `t3` normal, and `t4` specular. Environment is available at `t27` in the applicable permutations. |
| DDS DX10 headers | Shipped `_s` maps are `BC3_UNORM_SRGB`. RGB is therefore hardware-decoded as colour; alpha remains an unchanged numerical channel. Normal maps use a separate data format/workflow. |
| `dx11_default_psh_0pdsl.fxc` disassembly | The sampled specular RGBA is multiplied component-wise by `g_MaterialSpecular`. RGB participates directly in the specular colour/Fresnel response. Alpha participates in the exponent/gloss math. |
| Same disassembly | The direct lobe computes an exponent with `exp2` and converts it to a microfacet-width term equivalent to `sqrt(2/(power+2))` before evaluating the direct specular response. |
| Environment permutations | A saturated gloss control is derived from the texture/material alpha product; its complement controls environment blur/LOD. Thus the same authored gloss family affects both direct and environment response, although not through CR's GGX equations. |
| Source `_s.tga` inspection | Some maps are RGB-only/default-alpha, while vehicle examples such as `ivscou` and `ivtank` contain materially varying alpha. Alpha is not universally disposable. |
| Corpus statistics | Authored `specularPower` ranges from 1 through 1024, median 32. Common values are 32, 20, and 1024. Specular RGB constants are commonly neutral but mapped RGB colour remains meaningful. |

BZCC is not a metallic/roughness renderer. Its actual authoring contract is a
specular-colour plus gloss/exponent workflow. It also has classified
chrome/environment paths rather than a general metallic flag.

### Strong inference, kept separate

The material parser's `specularPower` is almost certainly log2-packed into
`g_MaterialSpecular.w`: the shader applies `exp2` to that component and the
authored power range matches the reconstructed exponent behavior. A runtime
constant-buffer capture would make that final parser-to-register step
confirmed. The shader-side use of the register and texture alpha is confirmed.

## 3. BZCC to CR comparison

| Topic | BZCC | Existing CR legacy Enhanced | Material V2 adaptation |
| --- | --- | --- | --- |
| Workflow | specular RGB + gloss/exponent | hybrid legacy specular RGB + Ogre shininess | explicit specular RGB/F0 + roughness |
| Metallic | no general metallic input found | none | none |
| Specular RGB | authored colour, hardware sRGB decode | hybrid map, deliberately not decoded | authored linear numerical F0, deliberately not decoded |
| Width control | texture/material alpha and exponent/power | derived from shininess with weak specular-luminance bias | authored perceptual roughness in alpha |
| Direct/environment consistency | same gloss family feeds both paths | same derived CR roughness feeds both | same explicit effective roughness feeds both |
| Opt-in | BZCC material/permutation classification | existing CR base | dedicated CR V2 base and programs |

The useful lesson from BZCC is not to copy its equations or packed exponent. It
is that artists need independent specular colour and lobe-width information,
and that those inputs must agree between direct lighting and environment
reflection.

## 4. Chosen Material V2 representation

Material V2 reuses the existing object specular texture slot:

| Channel | Meaning | Authoring rule |
| --- | --- | --- |
| R | linear F0 red | numerical `[0,1]`; brighter means more red-channel reflection |
| G | linear F0 green | numerical `[0,1]` |
| B | linear F0 blue | numerical `[0,1]` |
| A | perceptual roughness | numerical `[0,1]`; lower is sharper, higher is broader/duller |

The shader bounds RGB to `[0,1]` and roughness to `[0.12,0.92]`. Values outside
the effective roughness interval are legal source data but converge to those
stability limits at runtime. High's normal-variance filter may increase the
effective roughness of high-frequency normal maps.

Why this layout:

- RGB F0 is useful for exposed metal-like machinery, warm/cool reflective
  details, visors, and stylized ice; a scalar specular channel would lose that.
- Alpha supplies the one independent scalar the shader lacks.
- Reusing `t2` adds no texture sample, resource, sampler, or constant.
- A material-level scalar alone cannot represent mixed matte/polished regions
  in one texture atlas.
- A second roughness texture would add a sample with no compensating benefit.
- Metallic would add an unnecessary classification and encourage global PBR
  conversion rather than deliberate Battlezone material differentiation.

Suggested starting points, not mandatory physical laws:

| Surface | F0 RGB | Roughness |
| --- | --- | --- |
| Matte dielectric paint | `0.04, 0.04, 0.04` | `0.70-0.88` |
| Smooth painted surface | `0.04, 0.04, 0.04` | `0.20-0.35` |
| Rough exposed metal-like | tinted `0.35-0.65` | `0.55-0.75` |
| Smooth reflective metal-like | tinted `0.55-0.85` | `0.12-0.25` |
| Rubber/plastic | `0.02-0.05` neutral | `0.65-0.90` |
| Ice/glass-like test | subtle cool `0.06-0.12` | `0.15-0.35` |

These values should differentiate materials, not make every surface reflective.
Glass transmission/refraction is not implemented; “glass-like” here means only
a controlled reflective surface test.

## 5. Explicit authoring opt-in

An object material opts in by inheriting the new base and setting both aliases:

```text
import * from "CR_EnhancedMaterialV2.material"

material example_vehicle : CR_BZBaseMaterialV2
{
    set_texture_alias DiffuseMap example_vehicle_D.dds
    set_texture_alias NormalMap example_vehicle_N.dds
    set_texture_alias MaterialMap example_vehicle_m2.dds
    set_texture_alias SpecularMap example_vehicle_m2.dds
    set_texture_alias EmissiveMap example_vehicle_E.dds
}
```

`MaterialMap` binds the explicit interpretation only in DX11 Enhanced
High/Medium/Low. `SpecularMap` points at the same file for inherited DX9, GL,
Default, Retro, and Enhanced Lowest fallbacks, which consume its RGB as an
ordinary conservative specular map. Existing materials are not edited and
cannot opt in accidentally.

The dedicated program set contains nine object pixel permutations:

- High, Medium, Low;
- no shadow, single shadow, PSSM;
- High retains normal maps and static split-sum IBL;
- Medium/Low retain explicit direct GGX with their existing light-count and PCF
  budgets;
- Enhanced Lowest stays on the compatibility path.

Separate compile-time programs were chosen over a runtime branch or universal
extra sample. The result is zero legacy runtime cost and a modest, bounded nine
HLSL plus nine unified declarations.

## 6. Direct GGX and static IBL integration

For V2, the sampled RGB becomes `surfaceF0` and alpha becomes
`surfaceRoughness`. The existing normal-variance filter then produces the final
effective roughness. That same pair is used without an intermediate legacy
conversion in both lighting paths:

- direct: F0 enters Schlick Fresnel; roughness controls GGX NDF and Smith
  geometry;
- IBL: F0 enters the split-sum Fresnel term; roughness selects
  `roughness * 7` from the prefiltered environment and is the BRDF LUT's Y
  coordinate;
- emissive remains separate from reflected lighting and keeps its established
  atmospheric transmission.

The implementation retains denominator floors, safe normalization, minimum
roughness, Fresnel-aware diffuse/specular sharing, and the existing primary-sun
shadow convention. No BRDF rewrite was justified.

## 7. Linear-light/data classification

| Resource | Classification | Treatment in the Stage A experiment |
| --- | --- | --- |
| Diffuse/albedo RGB | artist colour | explicit sRGB-to-linear decode |
| Diffuse alpha | data/coverage | unchanged |
| Emissive RGB | artist colour | explicit sRGB-to-linear decode |
| Normal | data | never decoded |
| V2 F0 RGB | linear numerical reflectance | never decoded |
| V2 roughness A | data | never decoded |
| Legacy specular RGB | hybrid compatibility data | never reinterpreted or decoded |
| Shadow maps | data | never decoded |
| BRDF LUT | data | never decoded |
| Generated irradiance/prefiltered IBL | linear numerical lighting data | never decoded |

This deliberately differs from BZCC's `_s` RGB storage. BZCC marks specular RGB
as sRGB colour and lets hardware decode it; CR V2 stores final linear F0 bytes
and treats the whole RGBA map as data. Copying BZCC `_s` bytes directly would be
wrong without an explicit conversion.

## 8. Packing tool

`Tools/Build-EnhancedMaterialMap.py` creates deterministic, uncompressed RGBA8
DDS files. It accepts 8-bit RGB/RGBA specular input plus 8-bit `L` roughness,
or constants. It rejects mismatched dimensions, unsupported channel modes,
out-of-range constants, ambiguous colour-profile metadata, accidental
overwrite, and non-DDS output. It never resizes, normalizes, or gamma-converts.

Examples:

```powershell
python Tools/Build-EnhancedMaterialMap.py `
  --specular vehicle_f0.png `
  --roughness vehicle_roughness.png `
  --output Textures/vehicle_m2.dds

python Tools/Build-EnhancedMaterialMap.py `
  --f0 0.04,0.04,0.04 `
  --roughness-value 0.78 `
  --size 256x256 `
  --output Textures/matte_paint_m2.dds
```

Uncompressed output preserves exact authored values and integrates with the
existing DDS asset flow. If production later uses compression, inspect channel
error deliberately—especially roughness alpha—rather than making compression a
hidden part of this tool.

## 9. Debug visualization

`CR_MATERIAL_DEBUG_MODE` defaults to zero and is accepted only in explicit V2
compilations:

| Mode | Output |
| --- | --- |
| 1 | effective `MATERIAL_F0` |
| 2 | effective `MATERIAL_ROUGHNESS` after stability/normal filtering |
| 3 | accumulated `DIRECT_SPECULAR` |
| 4 | accumulated `IBL_SPECULAR` |
| 5 | `EMISSIVE` contribution |

The numerical values replace final RGB after the ordinary Stage A display
encode. This prevents a second transfer function from obscuring the diagnostic
value. The five maximal debug permutations are compiler-validated; an explicit
debug material/scheme can be added for interactive art review if permanent UI
exposure proves useful.

## 10. Terrain decision

Terrain V2 is deferred. Terrain has a separate atlas/detail/layer architecture,
different material bases, and its own specular/emissive semantics. Forcing the
object RGBA contract into that system would make the object design serve
terrain compromises and could add texture pressure across every landscape.

The validator rejects any `CR_MATERIAL_V2` reference in the terrain shader or a
terrain program. A follow-up should first decide whether terrain needs per-layer
F0/roughness, an atlas-wide control map, or material constants. The object path
does not preclude any of those choices.

## 11. Automated validation and legacy proof

Commands run from the task worktree:

```powershell
python Tools/Test-EnhancedMaterialV2.py
./Tools/Validate-DX11Shaders.ps1
./Tools/Test-DX11ShaderValidator.ps1
./Tools/Compare-DX11ShaderBinaries.ps1 -BaselineRef main -RequireLegacyIdentical
```

Results:

- 11 CPU/packing tests pass, including the six deterministic reference
  materials, bounded inputs, finite BRDF output, F0 energy monotonicity,
  roughness peak reduction/lobe broadening, grazing Fresnel, IBL mip
  monotonicity, exact channel packing, determinism, and dimension/range errors.
- All 222 SM4 compiler cases pass. This includes all nine V2
  quality/shadow/PSSM combinations and all five material debug modes, while
  retaining the existing Stage A, atmosphere, terrain, Retro, and diagnostic
  matrices.
- All 20 validator mutation fixtures are correctly rejected, including V2
  default-on, terrain leakage, and a missing required V2 permutation.
- 111 unique non-V2 SM4 recipes compile to byte-identical DXBC against `main`.
  This is the hard legacy parity proof; approximate appearance is not used.
- DX9, GLSL, GLSLES, Default, Retro, and Enhanced Lowest shader sources are
  unchanged. Unified V2 programs delegate those backends to their existing
  compatibility programs.

## 12. DXBC performance analysis

Representative PSSM permutations were compiled with `fxc` and inspected with
`fxc /dumpbin`. V0 is the existing legacy conversion; V1 is explicit Material
V2 with otherwise identical defines.

| Tier | Path | Instruction slots | Texture sample instructions | Control-flow instructions | Constant buffer |
| --- | --- | ---: | ---: | ---: | ---: |
| High PSSM + IBL | legacy | 687 | 55 | 20 | 2,560 bytes |
| High PSSM + IBL | V2 | 666 | 55 | 20 | 2,560 bytes |
| Medium PSSM | legacy | 454 | 30 | 20 | 960 bytes |
| Medium PSSM | V2 | 433 | 30 | 20 | 960 bytes |
| Low PSSM | legacy | 364 | 15 | 15 | 288 bytes |
| Low PSSM | V2 | 343 | 15 | 15 | 288 bytes |

V2 is 21 instruction slots smaller in each representative tier because it
removes the luminance/peak/power/tint legacy conversion. Resource bindings,
samples, control flow, and constant-buffer sizes are identical. `t2` is sampled
once in either path. There is no runtime V2 branch in compiled DXBC because the
feature is a preprocessor permutation.

## 13. Original-art material acceptance checklist

The Venus, Moon, Mars, Frozen, and Titan Battlezone renders were used only as
art direction. They are not shader specifications and do not justify atmosphere
or HDR changes in this work.

- Moon: keep structures matte/dark; restrict polished response to selected
  machinery; lamps remain dominant.
- Mars: armor and helmet materials stay distinct and readable under strong
  coloured environmental fill.
- Frozen: ice separates clearly from paint and rock through F0/roughness, not a
  universal gloss increase.
- Titan: dark machinery keeps controlled local reflections around intense
  practical lights without becoming wet plastic.
- Venus: a near-silhouette vehicle retains selective highlight structure rather
  than a bright uniform specular coat.

## 14. Later interactive validation

No live visual validation is claimed; the workstation was locked and
unattended. Once available, place one controlled object/material set under:

1. direct sunlight;
2. shadow/IBL-dominant light;
3. grazing view angle;
4. a nearby local light;
5. an existing bright coloured environment.

A/B the same diffuse, normal, and emissive textures through `CR_BZBase` and
`CR_BZBaseMaterialV2`. Check highlight width/intensity, IBL agreement,
normal-map readability, shadowed definition, wet-plastic failure, excessive
mirror response, and boundaries between matte and polished regions. Use debug
modes 1-5 to distinguish bad inputs from lighting/environment calibration.

## Final status

| Component | Finding | Confidence | Implemented | Automated | Runtime headless | Visual |
|---|---|---|---|---|---|---|
| Legacy semantics | Hybrid spec RGB drives tint/F0 and luminance strength; shininess is primary roughness with weak mask bias; same final values feed direct/IBL | High | Preserved | 111 recipes byte-identical to `main` | Existing runtime evidence only | Deferred—locked |
| BZCC semantics | Specular/gloss-exponent workflow; RGB spec colour plus alpha/power width control; no general metallic input | High for shader use; medium-high for parser-to-`g_MaterialSpecular.w` packing | Adapted, not copied | DXBC reflection/disassembly and corpus audit | Shipped binaries/assets inspected | N/A—reference system |
| Material V2 layout | RGBA data map: linear F0 RGB + perceptual roughness A; explicit base-material opt-in | High | Yes, objects/cockpits | Guards, pack tests, nine permutations | Script/material loading not claimed | Deferred—locked |
| Direct GGX | Existing Cook-Torrance receives explicit F0/roughness; no BRDF rewrite | High | Yes, High/Medium/Low | CPU invariants + fxc | Not visually exercised | Deferred—locked |
| Static IBL | Same F0 and effective roughness feed Fresnel, LUT, and mip selection | High | Yes, High | CPU mip/Fresnel tests + fxc | Not visually exercised | Deferred—locked |
| Tooling | Deterministic RGBA8 DDS packer with strict dimensions/modes/ranges and no implicit transfer/rescale | High | Yes | Exact bytes, determinism, rejection tests | N/A | N/A |
| Terrain | Separate architecture; object layout not forced into it | High | Explicitly deferred | Validator rejects terrain leakage | Unchanged | Unchanged by this work |
