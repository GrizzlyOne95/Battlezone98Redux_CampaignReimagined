# Pod v3 art comparison — not a shipped replacement

The owner accepted the v2 navs, rejected the pod art again, requested a full
unwrap, then also authorized exploring entirely new pod models. Accepted nav
assets, shipping membership, existing ODFs and gameplay values stay untouched.
Only NSDF examples are authored here until the owner selects an art direction.

## A: completely re-UV'd stock shapes

`cramns3.mesh` and `crhpns3.mesh` derive from the byte-pinned `apammo` / `aprepa`
snapshots in `../nav-pickups/original/`. All 126 ammo and 92 repair triangles
receive fresh UVs, with no overlap or collapsed UV faces. Every oriented
triangle, non-UV corner attribute, bone weight, bounds and rig reference remains
unchanged. Each model is now **one atlas and one material**, not per-facet
panel stamps plus a stock-UV remainder.

Ammo has five charts: continuous side wrap, continuous upper cone/tip wrap,
shoulders, underside and small top cap. Repair has three: continuous upper
cross shell, underside and side wrap. Side bands unwrap the actual concave
cross-section by cumulative perimeter distance, with matched U/V texel density.
Surface paint bands can therefore cross adjacent faces coherently.

`*-uv-guide.png` are technical diagrams, not shipped art. ImageGen painted new
art to those guides, avoiding the rejected vent-panel collage. The 1254px PNG
masters are compiled to 1024px legacy BC1 DDS with full mips. The compiler only
resizes, compresses and extrudes existing edge pixels into unused UV gutters.
Normals stay flat; old tangent streams are not suitable for newly authored
non-flat tangent-space relief until rebuilt against the new UV basis.

## B: new purpose-built models

`cramnew3.mesh` is a faceted ammo canister with protective boot/collar,
carrying handle, latches and shallow blue-topped lid (628 triangles).
`crhpnew3.mesh` is a low octagonal maintenance case with a raised center cap,
four green service cartridges and protective corner stays (288 triangles).
Both use two material batches and remain below the stock pods' overall extents.

The new ammo canister uses the same new NSDF ammo art to compare silhouettes.
The new repair case has its own filled octagonal lid atlas: reusing a concave
cross-shaped chart on a solid lid left obvious gaps and was rejected internally.
New-model hardware uses deliberate small trim samples; the no-overlap claim
above applies to the fully unwrapped **stock** pair, not these hardware samples.

These new meshes are unskinned render prototypes. They have **no new native
collision/SDF/VDF, placeable ODF, pickup animation/spin qualification or shipping
entry** yet. Do not copy them into a release as functional powerups. If selected,
finish their native companions and collision/pivot/pickup behavior validation
before replacing the existing faction models. No installed game was changed.

## Rebuild / review

```text
python Tools/Build-PodUVPrototype.py --textures
python Tools/Build-NewPodPrototype.py
python Tools/Test-PodUVPrototype.py
```

All serialization uses the shared codecs via `bzmodellibs` / `bzstaticmodel`.
The narrow prototype test passes 13241 checks; rebuilding both prototype
pipelines reproduces all 13 model/map/material/receipt hashes exactly. The
existing faction nav/pickup test still passes its 5305 contracts, and the
runtime Assets/Materials/ODF/Shipping diff is empty for this checkpoint.
`build.json` records the stock remaps, UVs, chart membership and geometry pins;
`new-models.json` records new-model counts, bounds and file hashes. Source PNGs
and complete built-in ImageGen prompt sets live beside them (`prompts.json`,
`new-repair-prompt.json`). No network/image-generation calls occur in builders.

Offline Blender renders only, not native engine acceptance:

- `../review/pod-v3-shape-comparison.jpg`: A/B stock-remap vs new geometry.
- `../review/pod-v3-stock-full-unwrap.jpg`: stock-remap front/rear.
- `../review/pod-v3-new-models.jpg`: new-model front/rear.

Owner direction and native integration remain pending. Do not propagate another
rejected design across four factions just because structural tests pass.
