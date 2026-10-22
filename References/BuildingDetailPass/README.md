# Large-building detail pass — offline review

Owner request, 22 October 2026: proceed with the ranked building candidates.
The first bounded batch covers the NSDF launch pad and CCA supply building.
The second adds Black Dog HQ and NSDF/CCA hangar regions, detailed below.
Factory/comms and other pad surfaces remain in the queue.
Base: `origin/main` e6123c9c, after the merged faction texture PR #288.
The canonical checkout, installed game, Bin, missions and gameplay are untouched.

## Selected surfaces

| Model / patch | Original diffuse allocation | Dedicated output | Existing triangles |
|---|---|---|---:|
| `ablpad` / ribbed approach deck | 960×512 | 1792×960 | 809 |
| `ablpad` / star-marked wall | 530×359 | 1280×864 | 197 |
| `sbsupp` / octagonal service deck | 628×594 | 1280×1216 | 506 |
| `sbsupp` / service-pillar door panels | 174×186 | 1024×1088 | 1207 |

The CCA door chart is reused around small service pillars, not the main front
grille. Its numerous selected triangles do not mean 1207 unique doors. The
before/after camera targets one measured original pillar face. The service deck
retains its five ochre bay outlines, white lane markings and coloured indicators;
the NSDF deck retains ribs, stripes and arrow. The wall retains its original
white star, not an invented insignia. Original muted NSDF metal and CCA charcoal
are retained; this is not a generic faction-wide teal/ivory recolour.

Built-in ImageGen supplied four detailed diffuse masters. `prompts.json` records
the complete prompts and input roles, `sources.json` pins captured source meshes
and original D/E rasters, and `original/` retains the exact crop references.
The selected master dimensions are 1717×916, 1524×1032, 1290×1219 and 1213×1297.
Shipping sizes are modest format resampling choices, not claims of 4K authored
detail. The compiler does not draw panels or generate artwork from code.

## Resource and preservation contract

- Each building adds two material batches. Exactly 1006/5813 NSDF triangles and
  1713/2907 CCA triangles receive positive-affine UV crop maps; all other UVs and
  source material selections remain exact. Oriented triangles, position/normal/
  tangent attributes, weights, bounds and skeleton names remain unchanged.
- Only render `.mesh` resources are added. Stock SDF/GEO, skeleton, collision,
  hardpoints, launch animation data, ODFs and mission placements are not edited.
  Native loading/animation remains unverified, not inferred from geometry hashes.
- Shared `Build-BuildingTexturePatches.py` and `bzmodellibs.py` handle mesh data;
  there is no private format codec. Defaults still reproduce both earlier pad
  pilots unchanged. The material import uses the real `sbsupp.material` script,
  not a nonexistent `sbsupp00.material` inferred from its internal material name.
- Existing functional emission comes from stock E at the same normalized UVs.
  Stock E rasters are 512×512, while D is 2048×1024 or 1024×1024: resize into
  common UV space before extracting crops. Original diffuse lamp pixels are
  retained over that footprint to avoid generated shifts. Existing stock E/D
  quirks are preserved, not claimed to be newly authored optics. Painted stars
  and hazard markings are not used as a brightness-derived emission mask.
- The nonemitting wall uses shared `black.dds`; no blank full-size E is shipped.
  Seven new BC1 maps with complete legacy-header mip chains total 6,593,392 bytes
  (~6.29 MiB). The existing 4×4 quiet specular is reused. Flat normal maps avoid
  fabricated diffuse-as-height relief; no new normal/shader/point-light system.
- Mesh bytes grow from 246,456→669,446 (`ablpad`) and 142,703→393,053 (`sbsupp`)
  through bounded buffer duplication, not added geometry. Two extra draw batches
  per model and their memory/performance tradeoff require native review.

## Build / evidence

```text
python Tools/Build-BuildingDetailPass.py
python Tools/Test-BuildingDetailPass.py
python Tools/Test-TextureRevamp.py
python Tools/Validate-CampaignRepository.py
```

`Prepare-BuildingDetailPass.py` is a one-time source capture from an extracted
stock BZ_ASSETS tree; ordinary builds need only checked-in masters. It refuses
to overwrite an existing source manifest. Rebuilds make no generation/network
calls. The 106 targeted checks cover source/current hashes, exact geometry and
unmodified remainder UVs, selected chart coverage, source-E mapping, full DDS
mips, actual material import and shipping membership. A moved-vertex negative
fixture proves the geometry contract rejects changes. They run in campaign CI.
All 14 asset/material/receipt outputs reproduce exactly; the previous CCA/Black
Dog pad builder also reproduces its original outputs unchanged.

Review: `review/ablpad-before-after.jpg` and `review/sbsupp-before-after.jpg`,
matched-camera source/render comparisons produced in isolated Blender processes.
These show texture presentation, not native Ogre lighting, gameplay or final
performance. Windows GOG/Steam and Proton/Wine runtime checks are unrun.
The owner requested continuing after this first batch; the second batch still
needs art acceptance. No deployment or Workshop publication.

Shipping lock: `-bless` refused to remove 51 absent sibling-generated payloads
in this fresh worktree and left the lock unchanged. The documented in-place
fallback admits only this batch's 11 new resources (2 meshes, 2 materials, 7
maps), preserving all 4426 earlier members/order; the total is 4437. No absent
native payload is removed or substituted to obtain a successful source check.

## Second batch — HQ and hangars

The owner's continuation request keeps this batch on the same open PR #305.
Six additional built-in ImageGen diffuse masters and the complete prompts are
saved here (`prompts-batch2.json`). The raw control-strip output had white
letterbox bands: only that padding was cropped (bounds recorded with its prompt).
No code-painted detail or new light motifs were introduced.

| Model / authored region | Original crop | Runtime allocation | Existing triangles |
|---|---|---|---:|
| `bbhqcp` / facade | 525×440 | 1280×1088 patch | 778 |
| `bbhqcp` / control banks | 390×72 | 1536×288 patch | 412 |
| `abhang` / wall | 562×477 | 1124×954 within 2048² atlas | 1672 |
| `abhang` / door-control chart | 457×265 | 914×530 within same atlas | 724 |
| `sbhang` / octagonal door | 714×715 | 1280×1280 patch | 610 |
| `sbhang` / insignia vent | 426×308 | 1280×928 patch | 1248 |

Selected master dimensions are 1369×1149, 2172×401 (after padding removal),
1362×1155, 1647×955, 1254×1254 and 1475×1067 respectively. The HQ facade's
525px boundary includes the original outermost UV at 524.21px; do not narrow it
to 524px and allow wrapping just outside a dedicated map.

HQ and CCA hangar use the same positive-affine patch technique as the first
batch: two added batches each; exact oriented geometry/non-UV attributes and
rig contracts. Their meshes are 284,671 and 775,885 bytes. Source palettes,
white stars, CCA vent insignia and existing glass/emission remain authoritative.
The HQ control chart occurs on small external banks: the matched camera targets
one measured outside face, not the aggregate midpoint hidden inside the tower.

**NSDF hangar is deliberately texture-only.** The existing animated ModelFixes
mesh contains precomputed edge lists. Repartitioning without regenerating those
would leave stale shadow topology. Its mesh (958,929 bytes), SDF and skeleton
remain byte-identical. Only the material's diffuse alias changes to one 2048²
atlas. Two new authored regions are composited there; all other chart pixels
are resampled original art. This is not a whole-atlas detail-remaster claim.
The original E/N/S bindings and constants stay unchanged; no duplicate E/N/S or
individual hangar patch atlases ship. The cost is one 2K BC1 diffuse (~2.67 MiB),
without any extra draw batch or UV/door-rig change.

This batch adds nine maps totalling 9,013,432 bytes (~8.60 MiB), two meshes and
two material scripts. The existing `abhang.material` is updated in place.
`-bless` again refused 51 absent sibling-generated payload removals; the same
in-place membership fallback adds exactly 13 resources, 4437→4450, preserving
every previous member and its order. No removals or installed-game changes.

Current checks: 246 building contracts; 808 general texture checks; hangar
door/hinge/bone/shipping regressions; 5016 repository files; 1197 owned program
references. All pass. All 32 current asset/material/receipt hashes reproduce
exactly, and the first batch's outputs stay unchanged. The original CCA/Black
Dog pad pilots also reproduce unchanged. Offline Blender processes exit cleanly.

Review sheets: `review/bbhqcp-before-after.jpg`, `review/abhang-before-after.jpg`,
`review/sbhang-before-after.jpg`. These are matched offline views, not native
Ogre lighting or gameplay/performance evidence. GOG/Steam/Proton/Wine runtime
checks and second-batch owner art acceptance remain unrun/pending.

## Owner follow-up — Red Devil

The owner prefers the legacy Black Dog **Red Devil** skin (`bvrdev`), not the
Redux interpretation. Read-only comparison found `bvrdev_d.dds` (2048²) and
legacy `bvrdev00_d.dds` (256²). Their UV layouts differ: rebinding the legacy
texture directly onto the Redux mesh is not a safe restoration. Use the legacy
red/black shapes, stronger markings and warm yellow headlights as the visual
authority for a separate authored pass. No Red Devil runtime asset is changed
in this building checkpoint.
