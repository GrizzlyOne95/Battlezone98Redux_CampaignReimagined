# DX11 Enhanced Phase 3 — Atmospheric Rendering

Phase 3 replaces the simple linear fog presentation in the DX11 Enhanced per-pixel shader path with a restrained analytic atmospheric model. DX9, OpenGL, OG Retro, non-Enhanced, and vertex-lighting compatibility behavior remains on the legacy fog path.

## What changed

- Camera-distance exponential-squared extinction driven by the existing Ogre `fog_params` start/end/inverse-range values.
- Scene-aware aerial perspective using mission `fogColour`, `sceneAmbient`, and the primary directional-light colour.
- Subtle forward sun scattering, only when light 0 uses the engine's established directional-light convention (`lightPosition[0].w == 0`).
- Enhanced High + static IBL adds camera-relative world-height density and horizon haze using the already-bound `inverseViewMatrix`.
- Emissive maps are separated from reflected surface lighting during the final atmosphere step and use reduced, not bypassed, extinction.
- Terrain detail multiplication remains equivalent before atmosphere, preserving the existing rough-dielectric terrain tuning and emissive behavior.
- The obsolete temporary magenta IBL visualization was removed. `CR_ATMOS_DEBUG_MODE` provides focused atmosphere diagnostics and is disabled by default.

## Mission fog interaction

Ogre supplies fog parameters as density/start/end/inverse-range. The Enhanced model treats start/end/inverse-range as the authored mission identity:

1. No extinction occurs before the authored start distance.
2. Distance after the start is normalized by the authored inverse range.
3. That normalized travel becomes a bounded exponential-squared optical depth.
4. Height and horizon terms only modulate that optical depth; they cannot create atmosphere when the mission fog range is effectively disabled.

This keeps light-fog and airless missions restrained while intentionally heavy-fog missions remain heavy.

## Radial smooth fog (`CR_RADIAL_FOG`, default `0`)

`CR_RADIAL_FOG=1` replaces **only** step 3 above — how normalized travel becomes a fog factor. Everything else in this document still applies: the authored start, end and colour keep their meanings, and height, horizon, sun scattering, aerial desaturation and emissive transmission are untouched.

### The Enhanced path was already radial

Worth stating plainly, because it is easy to assume otherwise: `compute_enhanced_atmosphere` has always consumed `length(viewPosition)`, and `viewPosition` is the camera-space fragment position interpolated at `TEXCOORD3`. Enhanced fog has therefore always been a spherical shell around the eye. **No new interpolator was needed and none was added.**

What *is* planar is the legacy fog in the non-Enhanced branch:

```hlsl
float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);
```

`vDepth` is clip-space z, so that fog measures distance along the view axis only and shifts as the camera yaws. That is Default, Retro and the vertex-lighting delegates, and it is deliberately left exactly as it is.

### What actually changes

The baseline factor is `1 - exp(-opticalDepth)` where optical depth grows with the square of normalized travel. Two consequences:

- at the authored fog end the factor is only ~0.934, so "end" is not where fog becomes opaque;
- past the authored end it keeps thickening, approaching 1 asymptotically but never arriving.

The Hermite (`smoothstep`) curve pins the factor to 0 at `fogStart` and exactly 1 at `fogEnd`, with zero first derivative at both ends.

| normalized travel | baseline | radial smooth | delta |
|---|---|---|---|
| 0.1 | 0.027 | 0.028 | +0.001 |
| 0.3 | 0.217 | 0.216 | −0.001 |
| 0.5 | 0.494 | 0.500 | +0.006 |
| 0.7 | 0.737 | 0.784 | +0.047 |
| 0.9 | 0.890 | 0.972 | +0.082 |
| **1.0 (authored end)** | **0.934** | **1.000** | **+0.066** |

The near and mid field are within a few thousandths of the existing look. The change is concentrated in the far field, which now resolves to the authored fog colour at the authored distance instead of staying permanently milky. Expect the difference to be most visible on maps with a deliberately short fog end.

`densityScale` (height + horizon) now scales normalized travel rather than an optical depth. The meaning is preserved: denser atmosphere reaches full fog nearer the camera, thinner atmosphere further away.

### Scope

Gated identically to Stage A — `defined(ENHANCED_MODE) && !defined(VERTEX_LIGHTING) && !defined(OG_RETRO_MODE) && !defined(RETRO_UNLIT_MODE) && CR_RADIAL_FOG != 0` — and enabled through `preprocessor_defines` on the same 12 Enhanced SM4 fragment programs that carry `CR_LINEAR_LIGHT=1`.

`compute_radial_fog_factor` is duplicated **byte-identically** in both world shaders, the same convention the rest of the shared region uses, because nothing in `Shaders/` uses `#include` and introducing one would make the mod depend on Ogre's runtime HLSL include resolution. `Validate-DX11Shaders.ps1` asserts the two copies stay identical rather than trusting the comment.

### Validation

- `Tools/Compare-DX11ShaderBinaries.ps1` compiles all 113 shipped DX11 SM4 permutations from both this tree and a baseline revision and compares DXBC. With the source added but the `.program` files untouched, **all 113 were bit-identical** — the feature is a provable no-op at its default. With the 12 Enhanced programs opted in, exactly those 12 changed and the other 101 stayed bit-identical.
- `Validate-DX11Shaders.ps1` sweeps the full `CR_LINEAR_LIGHT` × `CR_RADIAL_FOG` cross product (108 permutations) and asserts that the two fog models never both appear, that non-Enhanced permutations contain no atmosphere fog helpers at all, and that the legacy depth fog survives everywhere it should.
- `Tools/Test-DX11ShaderValidator.ps1` proves the guards themselves work, including a fixture that feeds `vDepth` to the radial factor and one that tunes the shared helper in a single file.

## Calibration constants

The `DX11 Enhanced Atmospheric Calibration` block is intentionally kept matching in `CR_base-sm4.hlsl` and `CR_terrain-sm4.hlsl` instead of introducing a larger shader-include refactor.

- `CR_ATMOS_DISTANCE_DENSITY_SCALE = 1.65` — maps the authored fog range into exponential-squared optical depth.
- `CR_ATMOS_HEIGHT_FALLOFF = 0.0035` — sensitivity to camera-relative vertical displacement.
- `CR_ATMOS_HEIGHT_STRENGTH = 0.22` — keeps valley/elevation effects subtle.
- `CR_ATMOS_HORIZON_STRENGTH = 0.18` / `CR_ATMOS_HORIZON_POWER = 3.0` — broad, band-free horizon haze.
- `CR_ATMOS_SUN_SCATTER_POWER = 7.0` — forward-scattering lobe width.
- `CR_ATMOS_SUN_SCATTER_STRENGTH = 0.28` — limits sunward haze influence.
- `CR_ATMOS_AMBIENT_TINT_STRENGTH = 0.16` — conservatively mixes scene ambient into authored fog colour.
- `CR_ATMOS_SUN_TINT_STRENGTH = 0.28` — allows the directional light to colour, not replace, mission haze.
- `CR_ATMOS_AERIAL_DESATURATION = 0.08` — small distance saturation loss before extinction.
- `CR_ATMOS_EMISSIVE_TRANSMISSION = 0.38` — blends normal transmission toward square-root transmission for emissives.
- `CR_ATMOS_MAX_OPTICAL_DEPTH = 12.0` — numerical guard for extreme map distances.

## Quality tiers

- **Enhanced High + IBL:** full model — exponential distance fog, height density, horizon haze, aerial perspective, sun scattering, and emissive-aware extinction.
- **Other Enhanced SM4 per-pixel tiers:** exponential distance fog, aerial perspective, sun scattering, and emissive-aware extinction. Height and world-horizon terms stay neutral because those delegates do not currently bind `inverseViewMatrix`.
- **Vertex-lighting fallback, OG Retro, and non-Enhanced:** unchanged legacy linear fog. This is asserted mechanically, not by inspection — see the DXBC comparison under *Radial smooth fog*.

No new material/program binding was required. `CR_static_ibl.program` already binds `inverseViewMatrix` for all three Enhanced High IBL DX11 variants, while the existing unified programs already supply fog, ambient, and light arrays.

## Colour space (Stage A linear-light interaction)

The Stage A linear-light experiment (`CR_LINEAR_LIGHT`, default `0`) wraps this atmosphere code rather than replacing it. See `Docs/DX11_COLOR_SPACE_AUDIT.md`.

When `CR_LINEAR_LIGHT=1` on the DX11 Enhanced per-pixel path:

- artist-authored COLOR textures (object diffuse/emissive, terrain diffuse/emissive) are decoded sRGB → linear at the sample;
- **all of Phase 3 executes inside that linear-light region** — extinction, aerial perspective, height/horizon density, sun scattering, and emissive transmission all operate on linearized surface values;
- the final RGB is encoded linear → sRGB exactly once, *after* atmosphere integration, immediately before the ordinary UNORM render target.

The 2026-08-30 Mars/Redux comparison and live `[DX11FOG]` probe resolve the
`fogColour` classification: it is mission-authored display RGB. Leaving
`(0.65, 0.45, 0.25)` untreated and applying the final output transfer produced
`(0.826657, 0.701411, 0.537099)`, the observed pale Enhanced haze. The
linear-light atmosphere now decodes only the explicitly classified
`authoredFog` copy before compositing. At full extinction the one final encode
therefore returns the authored fog colour instead of encoding it twice.

`sceneAmbient`, `lightDiffuse`, and `lightSpecular` remain untreated engine
coefficients. Their exact authoring semantics are not inferred from the fog
result, and no `CR_ATMOS_*` calibration constant was changed to compensate.
The source validator requires the `authoredFog` decode while continuing to deny
a direct conversion of raw `fogColour` and all data-texture identifiers.

## Known limitations

- Height fog is camera-relative rather than tied to an absolute world sea level. This is deliberate: it avoids large-coordinate precision problems and does not require engine hooks or new mission parameters. Terrain below the camera becomes slightly denser; terrain above it becomes slightly clearer.
- Only the primary light can contribute atmospheric sun scattering, and only when it is represented as a directional light. Point and spot lights do not drive atmospheric scattering.
- This is an analytic forward-shader approximation. It does not ray march, sample the framebuffer/depth buffer, render volumetrics, or add HDR, bloom, SSR, or SSAO.

## Debug visualization

Set `CR_ATMOS_DEBUG_MODE` at compile time:

- `0` — normal rendering
- `1` — total fog factor
- `2` — height contribution
- `3` — sun-scattering contribution
- `4` — resolved atmosphere colour

## Runtime test checklist

- [ ] DX11 Enhanced High
- [ ] IBL active
- [ ] PSSM active
- [ ] no-shadow path
- [ ] terrain broad sightlines and horizon
- [ ] vehicles and buildings
- [ ] emissive engines, panels, and building lights at near/mid/far distance
- [ ] light-fog or near-airless map remains restrained
- [ ] heavy authored fog map remains heavy
- [ ] sun-facing horizon gains subtle brighter haze without a fake sun disk
- [ ] sun-away view remains primarily `fogColour`/ambient-driven
- [ ] elevated camera/terrain shows slightly reduced haze
- [ ] low valley terrain shows slightly increased haze
- [ ] terrain remains rough/dry; no return of wet/varnished IBL highlights
- [ ] Retro mode comparison is visually unchanged
- [ ] no-shadow, single-shadow, and PSSM variants render without shader errors
- [ ] very large view distances remain stable with logarithmic depth enabled

`misn04` remains a useful runtime validation candidate, but the implementation is deliberately mission-agnostic.

## 2026-08-30 art-direction closeout

The supplied Mars and lunar comparisons were traced through CR, EXU, Ogre, and
the DX11 output target. Mars was the fog transfer mismatch documented above.
The lunar near-field flattening was separate: the terrain IBL path applied the
same neutral diffuse intensity in every environment. Terrain diffuse IBL now
uses the continuous authored fog-range support function documented in
`Docs/DX11_COLOR_SPACE_AUDIT.md`; objects, specular IBL, direct lighting,
emissives, Default, and Retro are unchanged.

Static validation completed with all 208 SM4 compiles passing. A GOG windowed
probe reached `misn04` and `misn02b`, invalidated stale shader microcode by
source fingerprint, and logged the corrected Mars values plus the live terrain
IBL scales. Automated captures were not locked to the supplied camera/HUD, so a
final paired art-direction recapture remains a release gate.
