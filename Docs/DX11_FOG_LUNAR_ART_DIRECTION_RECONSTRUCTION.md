# DX11 Fog / Lunar Art-Direction Reconstruction

This branch reconstructs only the still-relevant portion of retired
`agent/dx11-lighting-art-direction` commit `d506060` on current `main`.
No earlier light-budget branch history is carried forward.

## Changes

- Mission-authored `fogColour` is explicitly classified as display RGB
  and decoded before Enhanced linear-space atmosphere composition, so
  the final output transfer does not encode the fog colour twice.
- Terrain diffuse IBL is scaled by continuous authored fog-range support.
  Airless/very-long-range scenes retain a 0.15 floor instead of the full
  neutral diffuse environment fill; object IBL, specular IBL, direct
  lights and emissives are unchanged.
- The DX11 source validator requires the fog decode, confines the
  atmosphere-support correction to terrain diffuse irradiance, and
  rejects accidental propagation into the base/object shader.

## Scope

This is an Enhanced DX11 art-direction correction only. Default, Retro,
DX9/GL, object diffuse IBL, all specular IBL, direct lighting, emissives,
material semantics and PSSM ownership remain unchanged.

Automated shader validation is run during reconstruction and again by
the normal DX11 PR workflow. Locked-camera Mars/Moon visual comparison
remains the final human acceptance gate before merge.
