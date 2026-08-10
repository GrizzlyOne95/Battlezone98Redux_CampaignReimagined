# Terrain normal diagnostic test guide

These diagnostics isolate the DX11 terrain cotangent-frame path without changing
the broader lighting, fog, atmosphere, IBL, shadow, or texture setup. They write
only the GOG Campaign Reimagined runtime copy. The selector refuses Steam
Workshop cache paths.

## Launch pattern

Close Battlezone before changing a mode. From PowerShell:

```powershell
$tool = 'C:\Users\iestu\Documents\Google Drive\Ian Files\Battlezone Files\Redux Maps\Open Patch - CampaignReimagined\Tools\Set-TerrainNormalDiagnostic.ps1'
$game = 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux'

& $tool -Unpack RGB -Basis Stock -View None
Set-Location $game
.\battlezone98redux.exe misn04.bzn -renderer:dx11
```

Press Space when the loading bar appears to skip directly to the mission. Keep
the vehicle and camera in the same location for every screenshot.

## Primary basis A/B sequence

Run these one at a time, relaunching the game after each selector command:

```powershell
& $tool -Unpack RGB -Basis Stock         -View None
& $tool -Unpack RGB -Basis NormalizeAxes -View None
& $tool -Unpack RGB -Basis Orthonormal   -View None
& $tool -Unpack RGB -Basis GeometryOnly  -View None
& $tool -Unpack RGB -Basis TangentAsView -View None
```

Interpretation:

| Result | Meaning |
|---|---|
| `NormalizeAxes` removes the splotches | Stock common-scale T/B length imbalance is the owner. |
| Only `Orthonormal` removes them | TBN skew/non-orthogonality is the owner; Gram-Schmidt is the candidate fix. |
| `GeometryOnly` is clean | Confirms the artifact needs the sampled-normal transform path. This is a control, not a proposed visual fix. |
| `TangentAsView` retains the same spatial splotches | Look back toward the sampled normal, UV/atlas filtering, or mip selection. |
| `TangentAsView` is clean while stock/conditioned TBN are not | The derivative cotangent transform remains the owner. |
| Stock, normalized, and orthonormal modes all retain it | Do not retune lighting; proceed to the basis-quality and forced-LOD diagnostics. |

`TangentAsView` is intentionally not physically correct. It bypasses TBN only so
the sampled tangent normal can drive the unchanged lighting path as an isolation
control.

## Basis visualizations

Use the stock basis first, then repeat a suspicious view with `NormalizeAxes` or
`Orthonormal`:

```powershell
& $tool -Basis Stock -View GeometryNormal
& $tool -Basis Stock -View TangentAxis
& $tool -Basis Stock -View BitangentAxis
& $tool -Basis Stock -View BasisOrthogonality
& $tool -Basis Stock -View BasisCondition
& $tool -Basis Stock -View NormalDeviation
& $tool -Basis Stock -View NdotL
```

| View | How to read it |
|---|---|
| `GeometryNormal` | Remapped mesh normal. It should vary smoothly across continuous terrain. |
| `TangentAxis` / `BitangentAxis` | Remapped normalized T/B directions. Abrupt patches aligned with the splotches implicate derivative-frame construction. |
| `BasisOrthogonality` | R=`abs(T dot N)`, G=`abs(B dot N)`, B=`abs(T dot B)`, amplified 8x. Black is ideal; bright patches are basis error. |
| `BasisCondition` | R=T length, G=B length, B=absolute normalized-basis determinant. White is ideal. Dark/colored patches indicate imbalance or collapse. |
| `NormalDeviation` | Angle proxy between mapped and geometry normals. Black is close; white is severe deviation. |
| `NdotL` | First-light dot product before the rest of the BRDF/IBL chain. |

## Restore normal play

```powershell
& $tool -Unpack RGB -Basis Stock -View None
```

Do not leave `GeometryOnly`, `TangentAsView`, or a visualization selected after
testing.
