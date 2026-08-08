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
- **Vertex-lighting fallback, OG Retro, and non-Enhanced:** unchanged legacy linear fog.

No new material/program binding was required. `CR_static_ibl.program` already binds `inverseViewMatrix` for all three Enhanced High IBL DX11 variants, while the existing unified programs already supply fog, ambient, and light arrays.

## Colour space (Stage A linear-light interaction)

The Stage A linear-light experiment (`CR_LINEAR_LIGHT`, default `0`) wraps this atmosphere code rather than replacing it. See `Docs/DX11_COLOR_SPACE_AUDIT.md`.

When `CR_LINEAR_LIGHT=1` on the DX11 Enhanced per-pixel path:

- artist-authored COLOR textures (object diffuse/emissive, terrain diffuse/emissive) are decoded sRGB → linear at the sample;
- **all of Phase 3 executes inside that linear-light region** — extinction, aerial perspective, height/horizon density, sun scattering, and emissive transmission all operate on linearized surface values;
- the final RGB is encoded linear → sRGB exactly once, *after* atmosphere integration, immediately before the ordinary UNORM render target.

The atmosphere's own engine-provided RGB inputs are deliberately **not** converted:

- `fogColour`
- `sceneAmbient`
- `lightDiffuse` / `lightSpecular` (including the sun tint derived from `lightDiffuse`)

Their authoring colour space is still unresolved — BZR's missions may have been tuned visually against the legacy nonlinear pipeline — so guessing at a conversion would contaminate the experiment.

**A visible atmosphere/surface mismatch during A/B testing is therefore expected, not a bug.** Linearized surfaces sit against untreated haze colours, so fog may read too bright, too flat, or wrongly tinted relative to the terrain and vehicles it covers. That mismatch is the useful diagnostic signal: it is the measurement that tells us whether the engine RGB constants are authored as linear coefficients or as display-referred colour.

Do not recalibrate any `CR_ATMOS_*` constant to compensate. Converting the engine RGB inputs is a separate, later experiment (a suitable name is `CR_LINEAR_LIGHT_DECODE_ENGINE_COLORS`), and it must not be bundled with texture decode.

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
