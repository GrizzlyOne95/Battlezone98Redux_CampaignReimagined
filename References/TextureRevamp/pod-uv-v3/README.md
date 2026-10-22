# Pod v3 — selected stock geometry, full unwrap and functional glow

The owner selected **A: stock models with the new texturing**, then requested
the stock emissive/glowy idea be retained. B's new silhouettes were explicitly
rejected and are kept only as labelled historical render experiments.

The full unwrap now drives the existing runtime `cram{ns,bd,cc,cr}` and
`crhp{ns,bd,cc,cr}` variants, one material plus 1024px diffuse/emission maps
each. Native geometry, weights, VDFs, skeletons, ODFs and gameplay remain stock.
Accepted nav resources/material blocks and the two original NSDF masters are
byte-pinned unchanged in `../nav-pickups/owner-selected-art.json`.

Six full-atlas faction paint edits (`faction-prompts.json`) retain the NSDF
chart layout and functional blue ammo/green repair cues. The CCA repair edit
needed a green-cue correction (`cca-repair-color-correction.json`), also saved.
Runtime emission derives from the painted blue/green functional regions, not
insignia or broad shell metal. All creative edits used built-in ImageGen;
builders perform only technical conversion. No installed game was changed.

## A: selected completely re-UV'd stock shapes

`cramns3.mesh` and `crhpns3.mesh` derive from the byte-pinned `apammo` / `aprepa`
snapshots in `../nav-pickups/original/`. All 126 ammo and 92 repair triangles
receive fresh UVs, with no overlap or collapsed UV faces. Every oriented
triangle, non-UV corner attribute, bone weight, bounds and rig reference remains
unchanged. Each model is now **one diffuse atlas and one material**, not per-facet
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
`Tools/poduv.py` is shared by this reference builder and the runtime compiler.
Normals stay flat; old tangent streams are not suitable for newly authored
non-flat tangent-space relief until rebuilt against the new UV basis.

## B: rejected new-model experiment — never ship

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
entry**. The owner rejected these shapes; do not integrate them into runtime,
finish their native companions or substitute them for the selected stock pods.

## Rebuild / review

```text
python Tools/Build-PodUVPrototype.py --textures
python Tools/Build-FactionNavPickups.py
python Tools/Test-FactionNavPickups.py
python Tools/Test-PodUVPrototype.py
```

All serialization uses the shared codecs via `bzmodellibs` / `bzstaticmodel`.
The narrow prototype test passes 13241 checks; rebuilding both prototype
pipelines reproduces all 13 model/map/material/receipt hashes exactly. The
current faction nav/pickup test passes 5375 contracts. The runtime checkpoint
changes eight existing render meshes/full diffuse maps and four material files,
adds eight functional emission maps, and preserves all existing ODF/menu/native
bytes and accepted nav resources. No rejected new-model shipping entries exist.
`build.json` records the stock remaps, UVs, chart membership and geometry pins;
`new-models.json` records new-model counts, bounds and file hashes. Source PNGs
and complete built-in ImageGen prompt sets live beside them (`prompts.json`,
`new-repair-prompt.json`, `faction-prompts.json`,
`cca-repair-color-correction.json`). No network/image-generation calls occur
in builders. `Build-NewPodPrototype.py` is retained only for reproducing the
rejected historical B comparison, not as an integration step.

Offline Blender renders only, not native engine acceptance:

- `../review/faction-ammo-repair-stock-v3.jpg`: current runtime stock/faction art.
- `../review/pod-stock-glow-v3.jpg`: current runtime day/low-light emission.
- `../review/pod-v3-shape-comparison.jpg`: historical A/B; B explicitly rejected.
- `../review/pod-v3-stock-full-unwrap.jpg`: stock-remap front/rear.
- `../review/pod-v3-new-models.jpg`: new-model front/rear.

The selected stock direction is implemented across four factions. Native
GOG/Steam/Proton/Wine load, spinning parts, collection/rejection and performance
remain unrun; the new faction paint/glow is still an art-review checkpoint.
