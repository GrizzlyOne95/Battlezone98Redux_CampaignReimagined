# CCA fleet surface revision — 2026-10-19

The owner rejected both the original flat blockouts and the subsequent raised
plate grids. This revision replaces that tiled treatment on all three CCA
capital ships. The NSDF carrier and the five stock scale comparisons are not
repainted or recreated.

## References and resulting construction

The installed Redux APC (`svapc`), Czar (`svtank`) and Recycler (`svrecy`) were
inspected as textured 3D meshes, including their actual UVs and split normals.
`Tools/Inspect-CCAStock.py` reproduces those private inspection renders from an
installed game; it does not copy stock meshes or atlases into the repository.
The launch pad's diffuse atlas was also inspected. The source concept remains
`CCAfleet3.webp`, with the same approximate 0.25 m/pixel scale and three hull IDs.

The relevant stock cues are broad continuous faceted armour, restrained flush
skin joints, ivory over charcoal, a narrow ochre identification band, red star
and interrupted ring markings, and concentrated dark cooling/mechanical areas.
Those cues replace the repeated raised rectangular plates and rooftop grids.
Broad paint regions now clip exactly to each visible structural triangle;
projecting only polygon corners onto a bevel produces triangular intersections
and is insufficient. Shallow authored seam paths and clipped service-hatch
outlines follow the skin without changing the silhouette into a tiled surface.

The grey carrier keeps its single large side bay and real fork opening. The
long red hull keeps its pale ribs, V-shaped dorsal cover and one low forward
spike. The pale-bow red ship retains its cabin, ventral blister and dorsal cap.
New miniature gun turrets and extra stacked bridge slabs were removed. Width
and unseen surfaces remain interpretations, not newly discovered concept views.

## Materials and exports

The original generated painted-steel swatch remains a restrained material input;
its exact built-in imagegen prompt and provenance are in
`References/CCAFleet/Materials/README.md`. Paint contrast and bump are reduced
so large facets do not read as uniformly pitted concrete. Geometry, faction
markings, UVs, shaders and per-ship bakes are authored in Blender.

Each ship has 2048-square diffuse and tangent-normal atlases plus 1024-square
specular and emissive atlases. Runtime DDS files are RGBA8 conversions of the
saved PNG sources. Normal maps use DirectX -Y, matching the game's
`cross(tangent,normal)` bitangent. Ogre vertices carry explicit unit tangents
in a 44-byte position/normal/UV/tangent buffer. The native GEO/SDF proxy retains
closed structural solids below its 4,096-entry limits; visual seam and lamp
geometry does not consume the collision budget.

Quick review without touching runtime assets:

```text
blender -b --factory-startup --python Tools/Author-CCAFleet.py -- --only crcred1 --preview-output <private-folder>
```

Full rebuild and targeted verification:

```text
python Tools/Build-CCAFleet.py --blender <blender.exe> --render
python Tools/Test-CCAFleetAssets.py
python Tools/Test-NSDFCarrierAssets.py
```

## Pickup status

Private previews and final rebuilding are in progress. The older native images
in `CONCEPT_FLEET_ASSETS.md` show blockouts and do not validate this revision.
Record final mesh counts, hashes, deployment and native evidence after rebuilding.
Art quality requires visual review; a triangle count does not establish it.
Exact co-op fleet motion remains unqualified, independently of the stationary
asset-rendering smoke test. No production mission placement is added here.
