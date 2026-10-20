# Moon crater height prototype

This replaces rolling procedural relief with an explicit signed height texture
in a **local Moon preview bundle**. It keeps Moon's `microReliefScale: 2.5`
(maximum crater depth approximately 0.625 m). Paving and paving transitions
are flat; ground/rock tiles have shallow bowls, worn raised rims and flat
intervening ground. Native terrain and collision files are unchanged.

The source recipe is `Tools/TerrainHD/Moon/craters.json`. Adjust crater centers
(tile UV), radii in meters, relative depth, rim height/width or tile gains.
The original D/N/S/E files are untouched. Native geometry uses a small, separate
R32 height lookup with the existing CSV layout; diffuse and other HD channels
remain independent tile arrays. This does not crop or rebuild their atlases.

From this checkout, using an already built local Moon bundle:

```powershell
python Tools/Build-MoonCraterDisplacement.py `
  --bundle Local/TerrainHD/MoonRelief25 --openshim ../BZR-OpenShim-moon-relief-depth
```

Outputs include `moon_craters_height.png` (editable 16-bit grayscale),
`resources/crhd_moon_craters_h.dds`, a JSON report and a bundle manifest updated
with `heightTexture` / `heightEncoding: signed-unit-r32`. They stay under
ignored `Local/`; the PR tracks the recipe and tool, not new binary textures.
The canonical shipping manifest/art has not been switched to this candidate.

Black is a depressed floor, neutral gray is zero displacement, and lighter
values raise the rim. To export edits to the PNG, rerun with
`--height-image Local/TerrainHD/MoonRelief25/moon_craters_height.png`.
Export enforces flat paving and tile-edge guards. To regenerate from the JSON
recipe, omit `--height-image`. Depth remains adjustable separately in
`Config/cr_terrain_hd.json`; the preview helper applies that current CR value.

Preview with the companion OpenShim texture-height branch:

```powershell
./Tools/Test-MarsHdTerrainLive.ps1 -OpenShimRepo ../BZR-OpenShim-moon-relief-depth `
  -TileDirectory Local/TerrainHD/MoonRelief25 -World moon -Hd -MicroRelief -GroundView
```

`-GroundView` places the temporary camera on an existing solid ground region
and uses a closer view; `-WideView` retains the earlier Moon framing. The shared
launch harness serializes tests, runs windowed, gracefully exits its own game,
and verifies restoration of staged files. Neither trial changes canonical maps.

## Evidence and remaining acceptance

Windows/GOG PID 61460 (`Local/TerrainHD/run-20261020-162549`) bound the actual
R32 texture at DS t127 on a native rasterized HD draw: 243,200 DS invocations,
59,949 PS invocations and HD mask 7. All 1,626 binding scopes restored, along
with 144 bounds/streams, 82 material passes and 136 staged files. The wide shot
was inspected and paving stayed flat. Median process private commit was
346.50 MiB, lifetime peak 496.95 MiB, largest free VA region 2,044.79 MiB.
This is a short-run measurement, not an isolated overhead A/B.

The closer ground-region trial PID 48852 (`run-20261020-162745`) also passed
actual texture/raster proof and restored 1,202 binding scopes and 136 files.
Its screenshot was inspected. The recipe's floor is about -1 signed unit and
rim about +0.22, so the rim is intentionally much lower than the bowl depth.

The final ordinary-settings trial PID 59068 (`run-20261020-163229`) ran with
`TerrainHdEnabled=1`, `TerrainMicroRelief=1`, terrain probe disabled and no
diagnostic tessellation flag. It installed 0.625 m texture displacement and
restored 1,056 binding scopes and all 136 files. Its inspected close screenshot
is the current candidate. `-SettingsOnly` reproduces this activation check;
the separate diagnostic trials above establish actual GPU resource/raster proof.

Five focused art checks and the companion native 112-test suite pass. Native
tests include 192 GPU domain-output cases (meter and scaled signed-unit modes),
exact shader ownership, original DS-slot restoration, foreign-writer and PS
resource preservation, malformed/nonfinite DDS rejection and the SDK hook ABI.

This remains an art prototype: repetition, source-art alignment, contacts,
cross-cluster camera motion, displaced shadow casting/DXR geometry, profile/
device cycling, long-session RAM and Steam/Proton/Wine runtime need acceptance
or qualification before promotion. Other planet height artwork is unchanged.
