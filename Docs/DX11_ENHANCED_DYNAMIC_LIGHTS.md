# DX11 Enhanced dynamic lights

Status: OpenShim experiment implemented and automatically validated; interactive visual acceptance pending.

## Confirmed Campaign behavior

Campaign Reimagined's Enhanced High SM4 programs already declare and bind 24
lights. Ogre's `Pass` default is eight, but `SceneManager::renderSingleObject`
treats that default as a sentinel for an ordinary, non-iterated, unmasked pass
and forwards the renderable's complete candidate list. The shader's dynamic
`light_count` loop is therefore the effective High limit: 24 total lights,
normally the directional sun plus as many as 23 local point/spot lights.

An unattended GOG mission probe observed nine candidates reaching the current
`en-high-noshadow` path without any material override. This directly disproves
an eight-light cap for Enhanced High. Medium remains shader-limited to eight and
Low/Lowest to one.

No Campaign shader or material change is required for the experiment. DX9,
Classic, PSSM behavior, and all lighting constant layouts remain unchanged.

## Paired OpenShim experiment

OpenShim preserves Ogre's visibility, light-mask, and range filtering, then
reorders only CR `en-*` per-renderable candidates. Directional lights stay first.
Local lights use estimated color/intensity, Ogre attenuation at the object's
bounding sphere, and spotlight cone relevance. Stable light IDs and a five-percent
retention bonus reduce arbitrary churn at the actual High 24/25 cutoff.

Set `EnhancedLightSelectionV2=0` and restart for the exact stock Ogre ordering.
See OpenShim's `Docs/DX11_ENHANCED_DYNAMIC_LIGHT_AUDIT.md` for source/binary
evidence, GOG/Steam applicability, tests, performance, and diagnostics.

## Automated validation

- All 208 DX11 SM4 permutations compile.
- The existing High shader loop remains runtime-counted with a compile-time 24
  bound; no dummy-light expansion was introduced.
- OpenShim native ranking, determinism, hysteresis, removal, combat-churn, and
  benchmark tests pass.
- A locked-desktop GOG run reached mission simulation and exercised the hook;
  the quiet scene reached nine per-object candidates.

## Later visual A/B

1. Run DX11 Enhanced High with a stationary-camera 5v5 battle, headlights, and
   sustained projectile/explosion effects sufficient to exceed 24 candidates.
2. Enable bounded `[LIGHTSEL]` diagnostics and record candidate count, selection
   churn, FPS, and frame time with V2 enabled.
3. Disable V2, restart, and repeat from the same save and view.
4. Compare headlight/projectile/explosion popping and whether strong nearby
   lights displace weak distant lights without lingering.
5. Repeat while moving, then briefly verify DX11 Classic and DX9 parity.

Do not label the experiment visually accepted until those comparisons pass.
