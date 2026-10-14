# Campaign terrain edge pass

This is a visual/gameplay prototype for the reviewed terrain feedback of
14 October 2026. It changes fourteen maps. Following the owner's visual review,
the complete CR candidate was deployed to the GOG development mod on that date.
All 2,389 shipping-lock files match, with zero missing, differing or unexpected
files. It has not been published to Workshop. Driving, camera sightlines,
dynamic construction and engine AI navigation remain acceptance checks.

| Map | Implemented change |
| --- | --- |
| misn02b | Add source-derived relief and paint to the west/south flats marked in the Red Arrival reference. |
| misn06 | Break up the high, flat northwest corner with matching relief and paint. |
| misn07–09 | Extend Venus relief into empty boundary corners and beyond the playable limits. |
| misn10 | Fill flat Io corners and classify the raised terrain as land instead of leaving lava paint on it. |
| misn12 | Add the correctly named `edge_path`, tighten the rectangular limits around mission objects/routes, and texture the surrounding ice fields. |
| misn13 | Tighten the existing limits without expanding them; add relief and paint around the canyon network. |
| misn14 | Fill empty corners and nearby surrounds while keeping the current co-op mission's object and travel pads. The closed `world` area outline does not leave an artificial square track. |
| misn15b | Add relief/paint to the empty Io outskirts. |
| misn16 | Change `misn16b` terrain, which is the actual terrain referenced by this BZN and its alternate phase. |
| misns4 | Move southern pieces 450 m south; rebuild the actual crossing as a 550 m level metal bridge with smooth approaches. Paint the surrounding sea with the molten-pool family and add small height waves. |
| misns5 | Add broad gentle undulations and source-family paint. Maximum added slope is 9.40 degrees in the asset check. |
| misns6 | Replace the central rush space with a connected winding canyon through an eroded upland, preserve authored object pads, and reroute `counter_attack_path` through the canyon. |

`edge_path` defines an axis-aligned rectangle in Redux. It cannot express an
arbitrary polygon around the Europa canyons. The edits therefore combine a
smaller rectangle with physical surrounding relief. `path_edge` is retained as
authored and is not mistaken for the engine boundary.

## Authoring and preservation

`Tools/Build-TerrainEdgePass.py` builds from immutable CR baseline
`20692052db9b0a234604cfcad25272d0300d5987`. Terrain absent at that revision is
restored from CR's unsmoothed heightmap history (`ce18e89`); missing companions
come from the owner's stock `bzone.zfs`. This avoids smoothing the authored
mission terrain or reading a generated installed copy as source.

New background relief uses the map's own height-field spectrum, with broad
irregular editing limits and smooth joins. The selected ground must belong to
a substantial locally flat component. Authored object pads and named mission
routes are protected. Io's Bridge is the deliberate exception: the southern
terrain, objects, physics transforms, path points and playable lower bound all
receive the same Z warp. Runtime mission classes, object labels, teams, ODFs
and Lua objectives are retained.

The misn14 BZN baseline is pinned separately at
`773564a9b60c79aa464e6ad2474d455869440752` to retain the merged co-op mission's
pads and objects. Its `world` path is an area-of-interest outline rather than a
travel route; preserving a flat strip there produced an artificial square.

Io's Bridge explicitly uses type 5 (`io55sA0.map`) on the deck and type 1
(`io11sA0.map`) on the surrounding lava. Type 0's cracked red crust is not the
molten-pool appearance requested in the review. The deck is level at 30 m;
southern side islands translate intact rather than stretching into rectangular
strips. Mission path and object transforms use the corresponding spatial warp.

Painting learns the source's material/height/slope associations, then encodes
supported transitions. Newly painted entries are checked against the TRN;
unsupported transitions fall back to a defined solid family. Lighting is
updated on altered land so old baked shadows are not retained there. misn06's
baseline LGT does not match its HG2/TRN extents, so that map receives a complete
compatible soft lighting map rather than a guessed reinterpretation of its
truncated lighting data. The lighting is provisional pending in-game review.

## Rebuild and inspect

Install Python with NumPy, SciPy, Pillow and Matplotlib, and provide the sibling
Modding Toolbox checkout. The resulting game assets have no new runtime
dependency and use the existing Windows/Steam/GOG/Wine terrain formats.

```powershell
python Tools/Build-TerrainEdgePass.py --game-root '<game folder>'
python Tools/Test-TerrainEdgePass.py
python Tools/Render-TerrainEdgePass.py --game-root '<game folder>'
```

Use `--maps misn12 misn13` for a subset and `--toolbox <path>` when the Toolbox
is elsewhere. The build merges subset results into the local manifest. If
rebasing onto newer mission work, deliberately update `--base`; the prototype
must not silently consume a different BZN or overwrite later mission edits.

`Local/terrain-edge-pass/` contains baseline fingerprints, per-map arrays,
validation results and a before/after HTML review. Personal reference captures
stay local and are excluded from commits. Regenerate the shipping membership
through `Manage-CampaignFiles.ps1 -bless`; do not drop missing sibling-generated
files to get a fresh worktree through that check.

## Validation and remaining checks

- Fourteen maps pass HG2/MAT/LGT dimensions and height range checks.
- Newly painted slots resolve to defined TRN entries.
- Object counts, ordering and labels are preserved. Non-bridge object fields
  and protected terrain samples compare exactly with their baseline.
- All Europa mission objects remain inside the tightened bounds.
- Io's Bridge's objects use the same warp as the terrain; original ground
  offsets are checked within the raster resampling tolerance.
- Clear the Path has a connected 5.87 km route in the offline navigation proxy,
  compared with 3.28 km before and a direct distance of 3.09 km. The proxy uses
  a 20 m grid with a 35 degree slope ceiling; it does not prove live AI or hover
  behavior. The counterattack's new path uses the same canyon in reverse.
- The general repository validator passes after the deployment manager refreshes
  generated payloads from the matching OpenShim 1.0.0.52 assets. The shipped
  native binaries are retained byte-for-byte; the older default native checkout
  is not used. Deployment input provenance is recorded locally.
- The BZN deployment guard distinguishes `binarySave=true` from text saves;
  binary payload bytes are not interpreted as line endings. CRLF text passes,
  bare-LF/mixed text fails, and a binary payload containing 0x0A passes.

Before release, drive both directions through the new canyon with tanks,
scavengers and the counterattack; traverse the stretched bridge with the
escort; inspect the relit Mars plateau and the lava waves at ground level;
and test Europa boundary warnings and scripted spawns in offline and co-op.
