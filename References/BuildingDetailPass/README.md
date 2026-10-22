# Large-building detail pass — offline review

Owner request, 22 October 2026: proceed with the ranked building candidates.
This first bounded batch covers the NSDF launch pad and CCA supply building;
HQ, hangars, factory/comms and other pad surfaces remain in the queue.
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
Owner art acceptance is pending. No deployment or Workshop publication.

Shipping lock: `-bless` refused to remove 51 absent sibling-generated payloads
in this fresh worktree and left the lock unchanged. The documented in-place
fallback admits only this batch's 11 new resources (2 meshes, 2 materials, 7
maps), preserving all 4426 earlier members/order; the total is 4437. No absent
native payload is removed or substituted to obtain a successful source check.
