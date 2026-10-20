# Per-world terrain art controls

Edit each material in `Config/cr_terrain_hd.json`. All nine worlds have explicit
starting values. Mars stays rocky: existing HD maps, relief scale 1, no added
surface blend and unchanged detail constants. Other worlds also retain their
reviewed HD art until an author deliberately changes a value or supplies an
overlay. No generic dust or craters are applied across all planets.

| Control | Default / range | Meaning |
|---|---|---|
| `microReliefScale` | 1 / 0..4 (Moon 2.5) | Geometry amplitude, capped at 1 m. |
| `detailContrast` | 0.55 / 0..1 | Detail brightness modulation; 0 is neutral. |
| `detailNormalStrength` | 2.2 / 0..4 | Derived detail-normal slope; 0 disables it. |
| `detailNormalNearScale` | 0.55 / 0..1 | Relative strength of the finer 32x normal layer. |
| `surfaceBlend.coverage` | 0 / 0..1 (Moon recipe 1) | Authoring-time multiplier on an authored mask. |

Geometry depth and detail normal strength are independent. The latter does not
flatten the authored HD tile normal. Contrast can be reduced without reducing
detail-normal relief, and vice versa. Runtime controls affect native HD DX11
Enhanced only; other render profiles retain the existing atlas fallback.
Use matching OpenShim with per-material detail tuning, deploy the changed pack
and restart. Older OpenShim versions ignore the new detail fields. The log
`[TERRAIN-HD] detail tuning material=...` states the values actually installed.

The runtime specializes each owned fragment source before calculating its
source-hashed shader name. Defaults preserve the existing shader exactly.
There are no new texture slots, source image caches or per-frame uniforms;
changing a value creates the appropriate existing shader variant on installation.
This does not imply a measured RAM-overhead A/B.

## Authoring surfaces without losing HD textures

Moon's `surfaceBlend.recipe` selects the existing local crater/dust generator:
`Tools/Build-MoonRegolith.py`. Its coverage multiplier softens only the masked
crater floors, raised rims and sparse patches. Set coverage to 0 to keep the original HD
surface everywhere while retaining crater geometry. This is separate from
`floorDustStrength` and `patchDustStrength` in `Moon/regolith.json`, which shape
the authored mask. The generator reads the same runtime controls into its
portable pack and computes reference depth from the current relief scale.
Moon's recipe also has independent ground A/C crater layouts and per-crater
size, floor, rim and wear controls; see `Docs/MOON_REGOLITH_CANDIDATE.md`.
The recipe's new art still requires an explicit preview/build; adding the
authoring fields does not replace the shipping DDS automatically.

Other worlds can blend independent authored D/N/S/E surfaces before their
rotations and transition tiles are built. For example, Venus could add softer
deposits within a new mask, preserving crust elsewhere:

```json
"surfaceBlend": {
  "coverage": 0.35,
  "sourceType": 0,
  "mask": "../Local/TerrainHD/VenusDeposits/mask.png",
  "channels": {
    "D": "../Local/TerrainHD/VenusDeposits/deposit_d.png",
    "N": "../Local/TerrainHD/VenusDeposits/deposit_n.png",
    "S": "../Local/TerrainHD/VenusDeposits/deposit_s.png",
    "E": "../Local/TerrainHD/VenusDeposits/deposit_e.png"
  }
}
```

Paths are relative to `Config/`, must stay inside the CR checkout and match the
independent source tile dimensions (normally 1024px). `sourceType` selects the
saved source recipe's terrain type. Supply all four channels plus a grayscale
mask; use a black emissive image when no emission is wanted. Normals must be
linear RGB XYZ in the same engine U/V convention. No map is inferred from D.
The same mask blends every channel; N blends slopes and renormalizes. Pixels
outside the mask retain the source exactly. Zero coverage reads no overlay art.
Positive coverage without authored inputs reports an error rather than
fabricating a placeholder surface.

Rebuild with `Build-HdTerrainBundle.py --world venus ...` using new `--sources`
and `--output` folders. Input hashes prevent reusing a cache made before an
overlay/mask/coverage edit. Runtime detail/depth edits alone do not require
re-encoding DDS: the builder updates the portable runtime manifest even when
reusing an unchanged bundle. Rebuild/install preserves all per-world tuning and
surface authoring metadata; it does not reset other worlds.

`Test-MarsHdTerrainLive.ps1` copies current runtime tuning into its temporary
matching-material manifest. It preserves the selected bundle's own height art,
and `-DetailTexture` remains available for the authored HD detail texture.

## Validation scope

Focused tests cover every world's defaults/Mars retention, finite bounds,
preserving settings during pack rebuild, masked multi-channel authoring,
no-op coverage, source hash invalidation and missing-asset refusal. Existing
nine-pack rebuild checks remain in place. OpenShim checks default shader
identity, per-material source differences, unsupported-contract atomicity and
tuned HD HLSL compilation. Live evidence is recorded below once completed;
Steam/Proton/Wine and broader lifecycle acceptance remain separate.

Windowed Windows/GOG DX11 trials on 2026-10-20:

- Moon PID 20144 (`Local/TerrainHD/run-20261020-182908`) installed temporary
  contrast 0.35, normal strength 1.1 and near scale 0.2 with 0.625 m crater relief.
  The capture was inspected and the HD rocky surface remained. All 1,486
  height-binding scopes, 144 streams/bounds, 82 passes and 146 staged files
  restored. The source config was restored to its original defaults afterward.
- Mars PID 74796 (`run-20261020-183008`) installed default 0.55 / 2.2 / 0.55
  detail controls and 0.25 m relief. The inspected capture retains rocky HD
  Mars; all 320 streams/bounds, 82 passes and 171 staged files restored.
- Median private RAM: Moon 361.75 MiB, Mars 431.16 MiB; largest free VA block
  remained 2,044.79 MiB in both. These are short observations on different
  maps, not a tuning-overhead A/B or long-session memory qualification.

OpenShim's Release Win32 build, all 136 CTests, GCC/WSL material checks and
tuned fragment shader compilation pass. CR passes six art-control checks,
six pack rebuild checks, six Moon checks, PowerShell parsing and repository
invariants. No new binary texture assets are committed or publicly deployed.
