# Who owns the Enhanced shaders

Campaign Reimagined used to carry its own complete copy of the DX11 Enhanced
base and terrain shader implementation, forked from the stock set and renamed
into a `CR_` namespace. OpenShim carried the same implementation under `OSE_`.
Two copies, kept in step by hand.

They are one copy now. **OpenShim owns the implementation; CR owns the art
direction.**

## The split

| OpenShim (`resources/renderer/enhanced/`) | Campaign Reimagined |
| --- | --- |
| `openshim_enhanced_base-*` and `openshim_enhanced_terrain*-*` — HLSL SM3/SM4, GLSL, and the two `.program` scripts that declare 422 program names in the `OSE_` namespace | `Materials/CR_BZBase.material`, `Materials/CR_BZTerrainBase.material` — which technique each scheme gets, which pass, and every texture alias and material constant |
| The lighting model, the colour-space experiment, radial fog, PSSM v2, terrain normal encoding and its diagnostics | `Shaders/CR_static_ibl.program` — CR's own static-IBL wrappers, which compile the payload sources with `IBL_ENABLED` and fall back to the payload's own delegates off DX11 |
| | Everything else in `Shaders/`: glow, occlusion, overlay, scope, simple, sky, stdQuad, textured, UI, untextured, depth-shadowmap |

Ogre resolves program names from one flat namespace, so a CR material can
reference an `OSE_` program with no ceremony. The payload is deployed by
OpenShim into `openshim\renderer\enhanced\` in the game root; CR's Workshop
staging copies it from the OpenShim repo on every publish
(`Update-OpenShimManifest` in `Manage-CampaignFiles.ps1`), so CR's local
`openshim/` folder is a build artifact and is not tracked.

## Working on an Enhanced shader

Edit it in the OpenShim repository. Then, from CR:

```
./Tools/Test-ProgramReferences.ps1
./Tools/Validate-DX11Shaders.ps1
./Tools/Test-DX11ShaderValidator.ps1
```

All three resolve the payload through `BZR_OPENSHIM_REPO`, falling back to a
sibling `BZR-OpenShim` checkout, and refuse to run if they cannot find it. A
validator that silently skips its subject passes exactly as loudly as one that
checked it, so the failure is deliberate.

`Tools/Test-ProgramReferences.ps1` is the one that specifically guards this
split: it resolves every `*_program_ref` and unified `delegate` in CR's
materials and program scripts against the union of what CR declares and what
the payload declares. That check matters because the failure it catches is
silent — Ogre does not error on a material naming a program nothing declares.
It logs a line, drops the technique, falls back to whatever else the scheme can
resolve, and the map still renders: darker, or unlit, or with the stock shader.

On the OpenShim side, `scripts/Compare-EnhancedShaderParity.ps1` is what proved
the two copies were identical before CR's was removed.

## Setting the PSSM version

`Tools/Set-EnhancedPssmVersion.ps1` now covers only what CR still owns: its
static-IBL wrapper, and which pass the materials select. The base and terrain
Enhanced programs are switched in the OpenShim repository.
