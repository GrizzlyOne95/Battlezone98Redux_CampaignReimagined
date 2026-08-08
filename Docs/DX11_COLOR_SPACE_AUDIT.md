# BZR DX11 Color-Space Audit

> **Status: diagnostic / experimental, Stage 1.**  This document deliberately does **not** claim that the live BZR 2.2.301 DX11 texture SRVs are linear UNORM until an actual Enhanced DX11 mission is captured with the OpenShim diagnostic described below. No rendering behavior is changed by this branch.

## Scope

This audit covers Battlezone 98 Redux 2.2.301 and the current Campaign Reimagined DX11 Enhanced path:

- legacy-compatible Cook-Torrance GGX direct lighting;
- normal/specular/emissive support;
- static split-sum IBL;
- PSSM shadows;
- separate Enhanced material schemes.

Repositories audited:

- `Battlezone98Redux_CampaignReimagined`
- `Battlezone98Redux_Shim` / OpenShim
- `ExtraUtilities`
- the checked-in Ogre 1.10 headers in ExtraUtilities, plus upstream Ogre 1.10 D3D11 source as implementation reference.

The goal is to separate source facts from runtime facts. Upstream Ogre behavior is useful evidence, but the BZR renderer binary is authoritative.

---

# Executive diagnosis

## PROVEN

### Campaign Reimagined source behavior

1. `Materials/CR_BZBase.material` does not request Ogre hardware gamma on the diffuse, normal, specular, or emissive texture units.
2. `Materials/CR_BZTerrainBase.material` does not request Ogre hardware gamma on the diffuse, detail, normal, specular, or emissive texture units.
3. `Shaders/CR_base-sm4.hlsl` and `Shaders/CR_terrain-sm4.hlsl` perform no manual sRGB-to-linear decode and no final linear-to-sRGB encode. They explicitly state that samples are consumed in the space Ogre supplies until resource creation is verified.
4. Normal maps are data. They are sampled and numerically remapped from `[0,1]` to `[-1,1]`; applying an sRGB transfer function to them would corrupt the normal vectors.
5. Shadow maps/depth are data and are used as numerical comparison/depth inputs.
6. The BRDF LUT is numerical split-sum data and must remain linear.
7. The current generated static IBL bootstrap assets are generated from numerical lighting values by `Tools/Generate-StaticIBL.py`. The generator does not sRGB-encode the integrated irradiance, GGX prefilter values, or BRDF terms before writing the DDS payload. Therefore those generated values are **linear numerical data stored in LDR containers**, not display-authored sRGB color that should be decoded in the shader.
8. Current legacy specular maps are semantically hybrid in the CR shaders: RGB affects tint/F0 while luminance is also used as a numerical strength/mask and weak roughness cue. They cannot safely be classified as pure sRGB color or pure scalar data from shader source alone.
9. Ogre 1.10 exposes independent hardware-gamma state for textures and render targets. Texture hardware gamma performs gamma/sRGB-to-linear conversion while sampling; render-target hardware gamma performs the opposite conversion while writing.
10. In upstream Ogre 1.10 D3D11, `D3D11Texture::_chooseD3DFormat()` converts supported ordinary formats to `_SRGB` when `Texture::isHardwareGammaEnabled()` is true. The normal 2D path then creates its SRV with the same `DXGI_FORMAT` as the resource. This is an implementation reference, not proof that the BZR binary is identical.
11. In upstream Ogre 1.10 D3D11, the render-window `gamma` misc parameter becomes `mHwGamma`. The render-window code explicitly permits the swapchain/backbuffer resource to remain ordinary UNORM while the RTV format is `_SRGB`; therefore the RTV must be inspected independently from the swapchain/backbuffer resource.
12. ExtraUtilities' BZR/Ogre bridge exposes scene-manager/current-viewport access and plain float RGB light/ambient structures, but it also contains version-specific BZR offsets. OpenShim already has a safer pattern for dynamically resolving Ogre exports and for optional/fail-closed instrumentation.

### Evidence supplied before this diagnostic branch

The existing BZR Ogre log supplied for this investigation reports:

```text
D3D11: RenderSystem Option: sRGB Gamma Conversion = No
```

and the observed render-window creation state is `gamma=false`.

That is evidence that Ogre was **not asked** to perform render-window hardware gamma conversion in that run. It does **not**, by itself, prove the texture SRV formats or the final RTV format. The OpenShim capture is required for that.

## LIKELY

These classifications are strongly supported by asset/shader semantics but are not all provable from source metadata alone:

| Resource | Working classification | Rationale |
| --- | --- | --- |
| Object diffuse/albedo | COLOR / likely sRGB-authored | Artist-visible base color. |
| Terrain diffuse | COLOR / likely sRGB-authored | Artist-visible base color. |
| Terrain detail RGB | COLOR / likely sRGB-authored | Multiplies visible terrain color; exact authoring convention still needs representative asset review. |
| Emissive RGB | COLOR / likely sRGB-authored | Artist-visible emitted color/intensity texture. |
| Normal maps | DATA / linear | Vector encoding. |
| Shadow/depth | DATA / linear | Numerical depth/comparison values. |
| BRDF LUT | DATA / linear | Numerical BRDF integration terms. |
| Generated CR irradiance cube | DATA / linear numeric | Offline integration writes numerical values directly. |
| Generated CR prefiltered environment cube | DATA / linear numeric | Offline GGX filtering writes numerical values directly. |
| Legacy specular map | AMBIGUOUS / hybrid | Simultaneously used as visible RGB tint/F0 and numerical mask/roughness cue. |

If live diffuse/emissive SRVs are ordinary `_UNORM`, the likely result is that legacy artist color values are entering the GGX equations without sRGB decode. That would make the current Enhanced BRDF physically inconsistent even though it can still be visually calibrated to look reasonable.

## UNRESOLVED UNTIL AN ACTUAL BZR DX11 RUN

The following are deliberately **not** marked proven by source inspection:

- the live `ID3D11Texture2D` format for representative object diffuse, terrain diffuse/detail, normal, specular, emissive, IBL, and BRDF resources;
- the live `ID3D11ShaderResourceView` format actually bound for those resources;
- whether BZR's renderer binary exactly matches upstream Ogre 1.10 gamma-format behavior;
- the live swapchain format;
- the live backbuffer resource format;
- the live backbuffer RTV format;
- the active DXGI swapchain color-space state where `IDXGISwapChain3` is available;
- whether any hidden/offscreen sRGB or floating-point render target is already used by BZR;
- whether any renderer/plugin code performs a color conversion outside the CR shaders;
- the exact authoring convention of representative legacy specular maps;
- whether engine-authored light/ambient/fog/material RGB values were intended as linear coefficients or were tuned visually around the legacy nonlinear pipeline.

---

# Part 1 - Ogre and source audit

## What the Ogre material `gamma` texture flag means

Ogre's material texture-unit `gamma` option requests **hardware gamma correction on that texture**. In the checked-in Ogre 1.10 headers, the TextureManager loading APIs call the option `hwGammaCorrection`; the documentation states that supported 8-bit texture values are converted from gamma/sRGB space to linear space when sampled.

This is resource state, not a shader macro. It must be chosen consistently for a shared Ogre texture resource because the hardware-gamma choice can affect how the underlying API resource/view is created.

Campaign Reimagined currently does not specify `gamma` on the audited texture units.

## How Ogre stores hardware-gamma state

The checked-in Ogre headers expose:

- `Texture::isHardwareGammaEnabled()` backed by `Texture::mHwGamma`;
- `RenderTarget::isHardwareGammaEnabled()` backed by `RenderTarget::mHwGamma`.

The meanings are opposite directions:

- texture hardware gamma: encoded texture -> linear sample;
- render-target hardware gamma: linear shader output -> encoded target value.

For a render window, Ogre's D3D11 implementation reads the `gamma` creation misc parameter into the render target's `mHwGamma` state.

## How upstream Ogre 1.10 maps texture gamma to DXGI

The upstream Ogre 1.10 `D3D11Texture::_chooseD3DFormat()` implementation maps hardware-gamma-enabled formats directly, including:

- `R8G8B8A8_UNORM` -> `R8G8B8A8_UNORM_SRGB`
- `BC1_UNORM` -> `BC1_UNORM_SRGB`
- `BC2_UNORM` -> `BC2_UNORM_SRGB`
- `BC3_UNORM` -> `BC3_UNORM_SRGB`
- `BC7_UNORM` -> `BC7_UNORM_SRGB`

The ordinary 2D creation path uses that selected format as `D3D11_TEXTURE2D_DESC::Format`, then uses `desc.Format` again as `D3D11_SHADER_RESOURCE_VIEW_DESC::Format`.

For this upstream path, an sRGB request therefore creates an `_SRGB` typed resource and matching `_SRGB` SRV; it is **not** implemented as an `_SRGB` SRV layered over a typeless resource.

This is why the runtime diagnostic logs both resource and SRV formats rather than inferring one from the other or from the DDS header.

## What `sRGB Gamma Conversion = No` controls

Ogre's common RenderSystem configuration option controls the render-window `gamma` creation parameter. In upstream Ogre D3D11, that parameter controls render-target hardware gamma.

A crucial implementation detail is that the swapchain/backbuffer resource itself may remain an ordinary UNORM format while Ogre creates an `_SRGB` RTV when window hardware gamma is enabled. Therefore:

```text
Swapchain = UNORM
```

does **not** alone prove that final output writes are non-sRGB. The RTV format must also be logged.

Likewise, render-window gamma does not automatically imply that ordinary texture resources use sRGB SRVs; texture gamma is requested separately.

## Campaign Reimagined current shader behavior

### Object/base

Current SM4 bindings are:

| Resource | Register |
| --- | ---: |
| diffuse | `t0` |
| normal | `t1` |
| specular | `t2` |
| emissive | `t3` |
| shadows | `t4` (+ `t5`, `t6` for PSSM) |
| IBL, no shadow | `t4`, `t5`, `t6` |
| IBL, one shadow | `t5`, `t6`, `t7` |
| IBL, PSSM | `t7`, `t8`, `t9` |

The shader samples diffuse/emissive without transfer-function conversion, feeds legacy specular values directly into the legacy/PBR mapping, and numerically unpacks normals. Fog is a direct RGB lerp into the same target-space values.

### Terrain

Current SM4 bindings are:

| Resource | Register |
| --- | ---: |
| diffuse | `t0` |
| detail | `t1` |
| normal | `t2` |
| specular | `t3` |
| emissive | `t4` |
| shadows | `t5` (+ `t6`, `t7` for PSSM) |
| IBL, no shadow | `t5`, `t6`, `t7` |
| IBL, one shadow | `t6`, `t7`, `t8` |
| IBL, PSSM | `t8`, `t9`, `t10` |

Terrain detail RGB is multiplied into the visible terrain result. This makes it color-like semantically, but its authoring convention must be checked before it is included in a decode experiment.

---

# Part 2 - OpenShim DX11 color-space diagnostic

OpenShim branch `agent/dx11-colorspace-audit` adds an opt-in, rendering-state-neutral D3D11/DXGI observer.

Enable with either:

```text
OPENSHIM_TRACE_DX11_COLORSPACE=1
```

or `openshim.ini`:

```ini
[Diagnostics]
TraceDX11ColorSpace=1
```

If the switch is absent, no DX11 color-space observation hooks are installed.

If `RenderSystem_Direct3D11.dll` is not observed during startup, the probe logs that no DX11 renderer was captured and leaves DX9 untouched.

## Probe architecture

The diagnostic intentionally avoids hardcoded Ogre object layouts. It observes public D3D11/DXGI ABI calls at the renderer boundary:

- D3D11 device creation;
- DXGI factory/swapchain creation;
- `ID3D11Device::CreateTexture2D`;
- `CreateShaderResourceView`;
- `CreateRenderTargetView`;
- `CreateDepthStencilView`;
- pixel-shader SRV binding;
- output-merger render-target binding;
- current D3D11 viewport state.

It does not change:

- Ogre texture hardware-gamma flags;
- Ogre render-window gamma state;
- resource formats;
- SRV/RTV formats;
- shader constants;
- material schemes;
- shaders;
- blend state;
- render-target selection.

All observation hooks preserve the original call first or transparently chain it. Vtable/install mismatches fail closed. Logging is deduplicated and hard-capped by record class so repeated frame bindings cannot grow the log without bound.

## What the probe records

### Renderer/presentation

The capture reports, when available:

- D3D11 renderer plugin activation/device creation;
- D3D feature level;
- active D3D11 viewport dimensions/depth range;
- swapchain format and dimensions;
- backbuffer resource format;
- swapchain color-space state through `IDXGISwapChain3::GetColorSpace1()` when supported;
- bound/created RTV resource format and RTV view format independently;
- whether the resource/view is `_SRGB`, typeless, or floating-point;
- whether a bound render target is the captured swapchain backbuffer.

The probe intentionally does **not** read an Ogre `RenderWindow` object by guessed offsets merely to print `mHwGamma`. The effective D3D11 backbuffer/RTV state is the authoritative runtime result. The existing Ogre log's `gamma=false` / `sRGB Gamma Conversion = No` evidence should be saved beside the D3D capture.

### Textures/SRVs

For each unique observed resource/view/binding combination, the log can include:

- D3D object debug name if one was assigned by the renderer;
- resource pointer and SRV pointer;
- texture width/height/array size/mip count;
- cube-map state;
- underlying `ID3D11Texture2D` format;
- actual SRV format;
- `_SRGB` state of each;
- typeless state;
- pixel-shader slot and a CR slot-semantic hint.

Object debug names are best-effort; Ogre is not required to assign them in a retail build. The decisive evidence remains the actual D3D resource/SRV format at the shader binding point.

### Intermediate targets

Created/bound RTVs are deduplicated by resource/view/format. Floating-point formats and `_SRGB` RTVs are called out explicitly, allowing the capture to establish whether BZR already owns an intermediate float or sRGB target without dumping every resource every frame.

## Log schema example - NOT runtime proof

The following illustrates the intended schema only. Values are placeholders until copied from an actual BZR run:

```text
[DX11 ColorSpace] SwapChain ... format=DXGI_FORMAT_<captured>
[DX11 ColorSpace] SwapChain colorSpace=DXGI_COLOR_SPACE_<captured>
[DX11 ColorSpace] Backbuffer resource=0x... format=DXGI_FORMAT_<captured> srgb=<yes/no> typeless=<yes/no>
[DX11 ColorSpace] RTV bind ... backbuffer=yes resourceFormat=DXGI_FORMAT_<captured> rtvFormat=DXGI_FORMAT_<captured>

[DX11 ColorSpace] PS bind t0 ... resourceFormat=DXGI_FORMAT_<captured> srvFormat=DXGI_FORMAT_<captured> ... hint="CR base + terrain diffuse/albedo slot (COLOR candidate)"
[DX11 ColorSpace] PS bind t1 ...
[DX11 ColorSpace] PS bind t2 ...
...
```

Do not paste this schema into the PROVEN section as if it were captured evidence.

---

# Part 3 - Color semantics

## COLOR - likely sRGB-authored

### Diffuse/albedo

Treat object diffuse and terrain diffuse as artist-visible color. If the live SRV is ordinary `_UNORM`, a future Enhanced-only linear experiment should decode RGB before lighting.

Alpha is not sRGB data. Any helper must transform RGB only and preserve alpha unchanged.

### Terrain detail

The current terrain shader treats detail RGB as a visible multiplicative color modulation. That suggests sRGB-authored color, but representative assets should be inspected before decode is enabled because legacy detail maps are sometimes authored as centered numerical modulation around 0.5 rather than literal base color.

### Emissive RGB

Emissive artwork is likely artist-visible sRGB color. In a proper linear pipeline its RGB should be decoded before being added to scene radiance. The existing Enhanced emissive intensity logic can then operate on linear RGB; its constants will require visual recalibration rather than a BRDF change.

## DATA - must remain linear

Never apply sRGB decode to:

- normal maps;
- depth textures;
- shadow maps;
- BRDF LUT;
- roughness/AO/control maps if introduced later;
- other scalar/control textures;
- the currently generated CR irradiance cubemap;
- the currently generated CR prefiltered environment cubemap.

The last two are especially important: they look like environment *color*, but the current generator stores already-integrated numerical lighting values directly. Decoding those values as if they were display-encoded sRGB would be a second, incorrect transfer function.

## Legacy specular - unresolved/hybrid

The original/legacy CR shading path and the current SM4 path both use sampled specular RGB as more than a simple scalar:

- luminance drives a strength/mask;
- RGB drives visible specular tint;
- Enhanced maps that RGB into F0;
- the mask weakly biases derived roughness.

That is a mixed color/data interpretation. There is not enough source evidence to justify silently decoding it.

Initial Enhanced linear-light experiment policy:

1. leave legacy specular sampling exactly as it is;
2. compare the resulting highlights/F0 against the nonlinear Enhanced baseline;
3. if asset inspection supports color-authored specular RGB, test decode behind a **separate explicit experimental define** rather than coupling it to albedo decode;
4. do not change the normal/data path in either case.

A suitable future name is `CR_LINEAR_LIGHT_DECODE_LEGACY_SPECULAR`; it should default off for the first experiment.

---

# Part 4 - Engine-supplied color constants

The Ogre/BZR interfaces audited here expose light/material/fog/ambient RGB as ordinary float values. The shaders receive values such as:

- `lightDiffuse`;
- `lightSpecular`;
- `sceneAmbient`;
- `fogColour`;
- material diffuse/specular/emissive colors.

No automatic sRGB transfer on those float constants has been established in the audited source.

That does **not** prove that the content values are physically linear. BZR's missions/materials may have been tuned visually around a gamma-style rendering pipeline. Their intended semantics are therefore partly empirical.

For the first Enhanced linear-light experiment:

- leave engine light/ambient/fog/material RGB constants unchanged;
- treat them as legacy linear coefficients/intensities;
- recalibrate named intensity constants if the scene exposure changes;
- do not silently run them through `srgb_to_linear()`.

If a later A/B test is warranted, isolate it behind a clearly named experimental control such as `CR_LINEAR_LIGHT_DECODE_ENGINE_COLORS`. Do not conflate that experiment with texture decode.

---

# Part 5 - Why the linear-light shader experiment is intentionally not in this Stage-1 branch

The task requires the experiment **only after** the diagnostic conclusively establishes that color textures are sampled as ordinary nonlinear UNORM data.

That runtime proof is not available in this repository branch yet. Therefore adding `srgb_to_linear()` now would violate the audit requirement and could double-decode a texture if BZR's live renderer creates an `_SRGB` SRV through behavior not visible in the material scripts.

## Gate to unlock the experiment

An actual Enhanced DX11 mission capture must establish at minimum:

1. representative object diffuse is bound through a non-sRGB `_UNORM` SRV;
2. representative terrain diffuse is bound through a non-sRGB `_UNORM` SRV;
3. representative emissive is bound through a non-sRGB `_UNORM` SRV if emissive decode is to be enabled;
4. normal/data SRVs are identified and remain on their unmodified numerical paths;
5. IBL/BRDF resources are identified and remain undecoded;
6. swapchain, backbuffer resource, and RTV formats are captured independently;
7. no hidden conversion stage is observed that invalidates a manual final-encode test.

Only after that evidence is attached to the draft PR should the shader experiment be added.

## Planned experiment after the gate passes

Enhanced DX11 only, with the proper piecewise sRGB transfer function:

```hlsl
float3 srgb_to_linear(float3 c)
{
    float3 low = c / 12.92;
    float3 high = pow((c + 0.055) / 1.055, 2.4);
    return lerp(low, high, step(0.04045, c));
}

float3 linear_to_srgb(float3 c)
{
    c = max(c, 0.0);
    float3 low = c * 12.92;
    float3 high = 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    return lerp(low, high, step(0.0031308, c));
}
```

First experiment decode list:

- object diffuse/albedo RGB;
- terrain diffuse RGB;
- terrain detail RGB only if asset semantics are confirmed;
- emissive RGB.

First experiment no-decode list:

- normals;
- BRDF LUT;
- shadows/depth;
- current generated irradiance/prefilter IBL assets;
- legacy specular by default;
- engine light/ambient/fog/material colors by default.

The final manual `linear_to_srgb()` would be an **opaque-scene appearance test only** if the captured final target is ordinary non-sRGB 8-bit UNORM.

It is not the final architecture.

---

# Rendering implications

## GGX/PBR/IBL

GGX assumes linear radiometric quantities. If albedo/emissive are proven to arrive as nonlinear sRGB-style values through ordinary UNORM SRVs, feeding them directly into the BRDF biases energy and midtones. Existing PBR calibration constants can mask the issue visually but cannot make the math linear.

The existing `CR_PBR_DIFFUSE_COMPENSATION = 2.70` was tuned against the current pipeline and must not be treated as physically meaningful after transfer-function behavior changes.

Generated IBL is already numerical linear data. Its decode policy must remain independent from albedo/emissive decode.

## Fog

Fog should ultimately be composited in linear scene space and then encoded once at presentation. In the current path the shader directly lerps scene RGB with `fogColour` before writing the 8-bit target. Whether `fogColour` itself should be transformed is unresolved content semantics; do not silently change it in the first experiment.

## Emissive

In a linear experiment, decoded emissive becomes linear scene radiance before addition. The current LDR target will clip bright values before any future tone mapping, so emissive behavior in Stage 1 cannot predict final HDR appearance.

## Alpha blending and transparent effects

A manual final `linear_to_srgb()` inside world shaders does **not** make the renderer fully linear when the final target is ordinary non-sRGB UNORM.

Fixed-function alpha blending would still combine already-encoded destination values. That is mathematically wrong for linear-light blending and is a primary reason this manual encode can only be an opaque-scene A/B experiment.

Transparent particle/effect paths and UI overlays must not be assumed to inherit correct behavior from a world-shader experiment.

## UI/overlays

Campaign Reimagined has separate UI/overlay shader paths. The Stage-1 audit does not change them. Runtime validation must specifically verify that world color-space experimentation does not decode or double-encode UI/overlay content.

---

# Part 6 - Recalibration policy after linear-light mode exists

Do not modify GGX equations to recover legacy brightness.

First run the transfer-function experiment with the existing constants unchanged so the raw effect is visible. Then perform a small dedicated recalibration using named constants only.

Review:

- `CR_PBR_DIFFUSE_COMPENSATION`;
- `CR_PBR_SPECULAR_COMPENSATION`;
- `CR_IBL_DIFFUSE_INTENSITY`;
- `CR_IBL_SPECULAR_INTENSITY`;
- `CR_IBL_LEGACY_AMBIENT_RETAIN`;
- `CR_IBL_SCENE_TINT_STRENGTH` if retained;
- terrain minimum roughness/F0 limits;
- terrain IBL specular scale;
- emissive intensity;
- any future explicit engine-color experiment scale.

Prefer a compact calibration block shared conceptually between base and terrain over new scattered literals.

---

# Part 7 - Validation

## Automated validation in this Stage-1 branch

`Tools/Validate-DX11Shaders.ps1` retains the existing compile matrix for:

- object/base Enhanced;
- object/base Enhanced shadow;
- object/base Enhanced High PSSM;
- object/base IBL no-shadow/single-shadow/PSSM;
- terrain equivalents;
- tangent/cotangent variants;
- lower compatibility variants;
- Retro representative variants;
- UI/overlay SM4.

Stage-1 source guards additionally prevent an sRGB helper/define from being introduced before runtime proof is recorded. No DX9, GL, Default, Retro, or shader source is changed by this Stage-1 audit branch.

## Required runtime capture

Use the same mission, camera, time-of-day/light state, and graphics settings for:

1. Default DX11;
2. current Enhanced nonlinear;
3. Enhanced linear-light experiment **after the runtime gate passes**.

Inspect:

- overall brightness;
- dark/midtone albedo;
- saturated colors;
- vehicle/building shading;
- terrain;
- direct sunlight;
- shadow regions;
- IBL;
- specular highlights;
- emissives;
- fog;
- transparent effects.

Also:

- test emissives through every existing object LOD transition;
- confirm UI/overlays are not incorrectly decoded by the world pipeline;
- check logs for NaN/INF symptoms, black materials, shader exceptions, Ogre errors, D3D11 device removal/reset, or resource creation failures;
- retain the `[DX11 ColorSpace]` log lines that prove representative SRV and backbuffer/RTV state.

## Suggested capture procedure

1. Enable the OpenShim diagnostic switch.
2. Launch BZR using DX11.
3. Load a Campaign Reimagined mission using Enhanced High with PSSM/IBL active.
4. Spend enough time near representative terrain, a normally textured object, a normal/specular object, and an emissive object for their resources to bind.
5. Exit normally.
6. Save the OpenShim log and the matching `BZOgreLogfile` from the same run.
7. Extract the `[DX11 ColorSpace]` lines and attach them to the draft PR.
8. Classify each representative binding by resource role and record both resource and SRV format.

A useful evidence table to fill from the real run is:

| Role | Resource/name evidence | Resource format | SRV format | sRGB? | Proven classification action |
| --- | --- | --- | --- | --- | --- |
| Object diffuse | pending | pending | pending | pending | pending |
| Terrain diffuse | pending | pending | pending | pending | pending |
| Terrain detail | pending | pending | pending | pending | pending |
| Normal | pending | pending | pending | pending | must stay data |
| Legacy specular | pending | pending | pending | pending | semantics still hybrid |
| Emissive | pending | pending | pending | pending | pending |
| Irradiance cube | pending | pending | pending | pending | generated data; no decode |
| Prefilter cube | pending | pending | pending | pending | generated data; no decode |
| BRDF LUT | pending | pending | pending | pending | data; no decode |
| Backbuffer resource | pending | pending | n/a | pending | pending |
| Backbuffer RTV | pending | n/a | pending | pending | pending |

---

# Future FP16/HDR architecture

The correct long-term architecture is not “manual gamma everywhere.” It is:

1. decode sRGB-authored color inputs exactly once at sampling;
2. keep normals/masks/depth/BRDF/control textures numerical;
3. perform direct lighting, IBL, emissive, fog, and transparent blending in a linear floating-point scene target (likely FP16);
4. preserve values above 1.0 for exposure/tone mapping rather than clipping to the current 8-bit target;
5. run post-processing in a defined linear/HDR working space;
6. tone-map/expose once;
7. perform the final display transfer at presentation;
8. composite UI/overlays through an explicitly defined path rather than inheriting world assumptions.

An HDR compositor, bloom, GTAO, SSR, TAA, or unrelated effects are intentionally outside this audit.

---

# References audited

Repository-local:

- `Materials/CR_BZBase.material`
- `Materials/CR_BZTerrainBase.material`
- `Shaders/CR_base-sm4.hlsl`
- `Shaders/CR_terrain-sm4.hlsl`
- `Shaders/CR_base.hlsl`
- `Docs/DX11_STATIC_IBL.md`
- `Tools/Generate-StaticIBL.py`
- `Tools/Validate-DX11Shaders.ps1`
- ExtraUtilities `src/Ogre/Ogre.h`
- ExtraUtilities bundled Ogre 1.10 `OgreTexture.h`, `OgreTextureManager.h`, `OgreRenderTarget.h`, `OgreRenderSystem.h`, and related headers
- OpenShim `d3d_startup_hooks.cpp`, `ogre_shader_cache.cpp`, hook engine, patcher, startup/config code.

Upstream Ogre 1.10 implementation reference:

- `RenderSystems/Direct3D11/src/OgreD3D11Texture.cpp`
- `RenderSystems/Direct3D11/src/OgreD3D11RenderWindow.cpp`

The upstream implementation is used to explain expected Ogre behavior. It is never substituted for the runtime BZR 2.2.301 D3D11 resource/SRV/RTV evidence required by this audit.
