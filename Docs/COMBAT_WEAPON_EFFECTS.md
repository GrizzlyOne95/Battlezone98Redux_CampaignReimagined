# CR combat weapon effects: implementation and mesh-edit report

Initial implementation, 2026-11-04. This report is generated from the current CR source, reviewed model policy and fitted flash data.

**132 armed ODFs / 50 models / 267 equipped slots.** Authored recoil: 55 slots; fitted flash offsets: 124 slots; ballistic casing selections: 114 slots.

Scope: CR vehicle/building definitions, including mission variants and utility carriers. People retain per-weapon effects; armories supply weapons. This source-only count excludes stock-only aliases from the earlier 139-definition/52-model audit.

## What is implemented

- Recoil bindings use reviewed independent gun pieces and preserve the existing tank configurations. Mortar/rocket and minigun slots receive local kick overrides where their weapon supplies none. Weapon gameplay/loadouts are preserved.
- Flash fitting uses explicit visible gun pieces, including sibling bomber guns, non-BG turret tubes and the CRA gun-tower tube. The weapon offset stays zero; craft slots receive geometry-derived corrections.
- All 100 inventoried weapon ODFs already select small/medium/large/none casings. This pass checks every CR loadout against those decisions; plasma/energy/rocket/utility weapons remain casing-free.

## Remaining runtime and asset work

- These are authored configurations, not native visual acceptance. Existing OpenShim/EXU effect settings, exact-build and single-player gates remain. Beam/guided/targeting/other producer gaps remain explicit in the slot report.
- OpenShim currently supports weapon casingType/casingMesh, not per-craft ejection-port offsets. Brass still uses the firing mount and estimated breech. For a fitted port, add native per-slot local offset/direction support and author matching breech/port markers; do not invent inert ODF keys.
- Recoil is cosmetic. Qualify muzzle flash placement at both rest and kicked poses, aiming, deployment, repeated/simultaneous shots, weapon swaps and scene reload.
- `avartla` selects `gpopguna`, absent from both CR and the extracted stock ODFs. It remains unresolved rather than silently substituting a different weapon.

## Units needing mesh or rig edits

| Model | Unit ODFs | Work category | Proposed change |
|---|---|---|---|
| `avfigh` | `avfigh`, `avfimp` | Isolate gun geometry | Guns share roof/hull/pod weights with fixed structure. Select each visible tube or muzzle sleeve, give it its own recoil child below the existing moving parent, and reweight only that geometry. Split and cap joined boundary faces where necessary. Keep left/right channels independent and use a small machinegun kick; do not recoil the entire carrier. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `avland` | `avlamp` | Isolate gun geometry | The armed lander marker is attached to lla11bda. Identify/select the visible muzzle/emitter and give it a gun-only child; preserve the large landing structure. No ready dedicated cannon-tip node found. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `avltnk` | `avltmp`, `avltnk` | Isolate gun geometry | Main gun is weighted to the hull (aln11bda/bln11bda); launcher box is a different part. Isolate the visible cannon/minigun tip and add a recoil child under the hull. Use a separate launcher sleeve if wanted. Black Dog GR1 also lacks a matching rendered marker; use native hardpoint data and verify fit. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `avrckt` | `avrckt` | Isolate gun geometry | Rocket/launcher outlets are integrated into body weights. Separate the actual tube mouth/launch rail/sleeve for a short local compression animation; preserve hull and utility hardpoints. Use per-slot launch behavior, not cannon-like whole-body translation. Guided/targeting launchers need their own accepted-fire path support. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `avsav` | `avpsav`, `avrsav`, `avsav`, `avsav14` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `avtest` | `avtest` | Rig/animation work | Separate aVT11bgA/bgb gun pieces have changing native position tracks. This is a drone/debug definition with dummy weapons. Compose recoil with existing animation; do not classify as an immediate static slide target. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `avwalk` | `avwalk`, `avwamp` | Isolate gun geometry | Each cannon shares an aimed arm (age11tx2 / age11tx1). Select the gun end/barrel inside each arm, create independent recoil children and reweight. Keep shoulders, arms and walking animation on their existing bones; do not use one clip that kicks both arms for either shot. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `bvltnk` | `bvltnk`, `bvltnka` | Isolate gun geometry | Main gun is weighted to the hull (aln11bda/bln11bda); launcher box is a different part. Isolate the visible cannon/minigun tip and add a recoil child under the hull. Use a separate launcher sleeve if wanted. Black Dog GR1 also lacks a matching rendered marker; use native hardpoint data and verify fit. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `bvraz` | `bvfigh`, `bvfigha`, `bvra8`, `bvraz` | Isolate gun geometry | Guns share roof/hull/pod weights with fixed structure. Select each visible tube or muzzle sleeve, give it its own recoil child below the existing moving parent, and reweight only that geometry. Split and cap joined boundary faces where necessary. Keep left/right channels independent and use a small machinegun kick; do not recoil the entire carrier. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `bvrckt` | `bvrckt` | Isolate gun geometry | Rocket/launcher outlets are integrated into body weights. Separate the actual tube mouth/launch rail/sleeve for a short local compression animation; preserve hull and utility hardpoints. Use per-slot launch behavior, not cannon-like whole-body translation. Guided/targeting launchers need their own accepted-fire path support. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `bvrdev` | `bvrdev`, `bvrdeva`, `bvrmpa`, `bvrmpb` | Isolate gun geometry | Primary and launcher markers are under brd11bda, despite other decorative/aiming pieces existing. Isolate actual gun geometry for cannon/minigun variants and separate launch sleeves where appropriate. Avoid recoiling the entire vehicle shell. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `bvwalk` | `bvwalk` | Isolate gun geometry | Each cannon shares an aimed arm (age11tx2 / age11tx1). Select the gun end/barrel inside each arm, create independent recoil children and reweight. Keep shoulders, arms and walking animation on their existing bones; do not use one clip that kicks both arms for either shot. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cblasr` | `cblasr`, `cbtowea`, `cbtowec`, `cbtowee` | Emitter/asset decision | The shipped rendered skeleton has only clz11bda/clz11bdb, while native GC1 is under clz11bdd. Resolve the missing rendered aiming/emitter hierarchy first. A localized lens/nozzle pulse can then use isolated geometry; translating the whole tower top is unsuitable. Beam variants also require producer support. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `crfraz` | `crfraz` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `cvartl` | `cvartl`, `cvartla` | Isolate gun geometry | CAR11TX1 owns 5013 vertices including the large aiming housing and all four gun assemblies. Separate each desired barrel/tube from the housing, with children below TX1; preserve aim/deployment. Do not slide the entire 6.9 m-wide aiming assembly for one fired slot. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvfigh` | `cvfigh`, `cvfigha`, `cvfighb`, `cvfighc`, `cvfighd`, `cvfighe`, `cvfighf`, `cvfighg`, `cvfighh`, `cvfimp`, `cvraz` | Isolate gun geometry | Guns share roof/hull/pod weights with fixed structure. Select each visible tube or muzzle sleeve, give it its own recoil child below the existing moving parent, and reweight only that geometry. Split and cap joined boundary faces where necessary. Keep left/right channels independent and use a small machinegun kick; do not recoil the entire carrier. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvhraz` | `cvhraz`, `cvhraza`, `cvhrazb`, `cvhzmp` | Isolate gun geometry | Default GR1/GR2 markers are attached to CPX11BDA0 while the physical launcher/side assemblies are weighted with large engine/body pieces. Isolate outlet sleeves or add small moving nozzle parts under the correct pod; do not recoil CPX11BDA0 or an entire engine. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `cvhtnk` | `cvhmpa`, `cvhmpb`, `cvhtnk` | Rig/animation work | The rendered side gun/sponson assemblies already have separate weighted bones CEM11WGL0 and CEM11WGR1 (1070 vertices each), but these are Ogre-only names, longer than the 8-byte native node route. Native WGL/WGR nodes own only tiny marker geometry. An authored clip/helper can recoil existing assemblies; gun-tip-only action needs a further surface selection/split. Do not translate CEM11BDA. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvltnk` | `cvltnk` | Isolate gun geometry | GC1 and GR1 are integrated into CNA11BDA. Separate a gun-only tube/sleeve from the hull weights; author independent recoil helper. Preserve the existing rocket hardpoint selection. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvrckt` | `cvrckt` | Isolate gun geometry | Rocket/launcher outlets are integrated into body weights. Separate the actual tube mouth/launch rail/sleeve for a short local compression animation; preserve hull and utility hardpoints. Use per-slot launch behavior, not cannon-like whole-body translation. Guided/targeting launchers need their own accepted-fire path support. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `cvtnk` | `cvtank`, `cvtmpa`, `cvtnk`, `cvtnka`, `cvtnkb`, `cvtnkc`, `cvtnkd` | Isolate gun geometry | Primary and secondary guns are on CYE11BDA; the tall/long cannon does not have its own weighted barrel. Isolate the barrel or front sleeve and add a child, retaining hull/pod parts. Handle dual-gun mission variants separately. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvturr` | `cvturr`, `cvturra`, `cvturrb`, `cvturrc` | Isolate gun geometry | CAD11TX1/TX2 each combine an aiming assembly with multiple barrels. Reweight individual barrel tips beneath those parents and bind slots 1/2/3/4 independently; preserve folded legs and aimed parts. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `cvwalk` | `cvwalk`, `cvwamp` | Isolate gun geometry | Two guns share the aiming head. Add independent weighted gun children beneath the head, retaining aim and gait. Current rendered muzzle names also differ from some native model names; fit from the native fired slots and actual visible barrels. Do not translate the entire head. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svartl` | `svarmp`, `svartl`, `svartla` | Rig/animation work | sar11bgb is already a separate weighted barrel, but its native translation is animated. Use an additive recoil child/helper or a composed firing clip so deployment keys do not fight recoil. No initial geometry split is required for whole-barrel recoil. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `svfigh` | `svdemo`, `svfi12`, `svfigh`, `svfigha`, `svfimp` | Isolate gun geometry | Guns share roof/hull/pod weights with fixed structure. Select each visible tube or muzzle sleeve, give it its own recoil child below the existing moving parent, and reweight only that geometry. Split and cap joined boundary faces where necessary. Keep left/right channels independent and use a small machinegun kick; do not recoil the entire carrier. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `svhraz` | `svhr13`, `svhraz`, `svhrmp` | Isolate gun geometry | Default saturation-rocket hardpoints GR1/GR2 belong to shb11bda; there are no independent launcher-barrel bones like the NSDF bomber. Isolate launch-port/nozzle geometry into short-stroke children. The small shb11bdc part belongs to the other-side TAG marker and is not proof of a default rocket barrel. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svltnk` | `svlt13`, `svltnk` | Isolate gun geometry | Both relevant markers are on slt11trt, a small turret/gun housing rather than a dedicated sliding tip. Whole-housing motion is possible as an art choice, but a localized barrel action needs a separate tube/sleeve child and weights; preserve turret aim. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svrckt` | `svrckt` | Isolate gun geometry | Rocket/launcher outlets are integrated into body weights. Separate the actual tube mouth/launch rail/sleeve for a short local compression animation; preserve hull and utility hardpoints. Use per-slot launch behavior, not cannon-like whole-body translation. Guided/targeting launchers need their own accepted-fire path support. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svsav` | `svsav` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svturr` | `svtump`, `svturr`, `svturra`, `svturrb`, `svturrc` | Rig/animation work | Separate rendered barrels already exist, so geometry cutting is not the first problem. Native GC1 parent is STU11BGC, which exists and owns 314 vertices. Native GC2 parent STU11BGB is absent from the Ogre skeleton; rendered siblings are STU11BGCA/STU11BGCB/STU11BGC. GC markers are absent from the rendered skeleton. Reconcile world rig names/bindings for each tube and preserve the existing deploy/cockpit fix before enabling. One ready tube does not establish dual-slot correctness. Fit muzzle markers to the visible apertures; add a separate breech/ejection-port marker for ballistic loadouts once native per-slot port support exists. |
| `svwalk` | `svwalk`, `svwalka`, `svwamp` | Isolate gun geometry | Two guns share the aiming head. Add independent weighted gun children beneath the head, retaining aim and gait. Current rendered muzzle names also differ from some native model names; fit from the native fired slots and actual visible barrels. Do not translate the entire head. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |

## Models using existing gun pieces

| Model | Unit ODFs | Binding / remaining detail |
|---|---|---|
| `abtowe` | `abtowe` | Use agn11bgb: 38 vertices / 34 triangles, rigid weight 1.0, native node and static local translation. GC1 is its child. No geometry split needed; tune short tip travel. Preserve ty1/tx1 aim parents. |
| `avartl` | `avarmp`, `avartl`, `avartla` | Four separate aar11bgd/bgc/bgb/bga barrels for GM1/2/3/4. Bind each fired slot independently. Preserve deployed pose and aiming; mortar weapons need an explicit kick because existing CR kicks are CANN-category only. |
| `avhraz` | `avhraz`, `avhrmp` | Two independent top-gun meshes: ahr11bga / ahr11bgb, each 500 vertices / 636 triangles, weight 1.0 and static native node. Default GR1/GR2 markers are under ahr11rof, but their positions lie inside the corresponding left/right barrel bounds. Bind slot 2 to bga, slot 3 to bgb explicitly; both grktbomb slots need craft recoilKick overrides. No geometry split is needed to move the whole existing top-gun pieces. A tip-only telescoping action would require subdivision/reweighting. Do not recoil the roof. |
| `avtank` | `avdemo`, `avtamp`, `avtank` | Existing AGR11BGA cannon binding. Secondary gun is on AGR11BDA and needs gun-only weighting if physical secondary recoil is wanted; do not slide the hull. |
| `avturr` | `avtump`, `avturr` | Independent barrel tubes aDE11blc/bld/ble/blf, each 116 vertices / 190 triangles. GC1 uses blc; GC2 uses blf. These names are not BG*, so the old heuristic missed them. Static translations allow a node-slide candidate without cutting geometry. Keep the animated deploy base and aiming parents; choose whether a whole barrel cluster or only fired tube should react. Miniguns require a craft kick override. |
| `bbtowe` | `bbtowe` | Use agn11bgb: 38 vertices / 34 triangles, rigid weight 1.0, native node and static local translation. GC1 is its child. No geometry split needed; tune short tip travel. Preserve ty1/tx1 aim parents. |
| `bvartl` | `bvartl` | bar11bgd is the default GM1 barrel; the model also has the other separate barrel pieces. No split needed for its existing barrel; preserve deployment and use mortar kick opt-in. |
| `bvhraz` | `bv0002`, `bvhraz`, `bvhraza` | Same separate top-gun layout as NSDF: bhr11bga/bhr11bgb. The default rocket variants use slots 2/3 under the roof; map them explicitly to left/right gun pieces. The bvhraz variant has TAG at GC1 under bga, GM1 utility and Comet at GR1: choose bindings per loadout, not per generic slot index. |
| `bvtank` | `bvtank`, `bvtanka` | Existing bGR11BGA cannon binding. GM1 is under the hull and must not blindly reuse the cannon barrel merely because it is spatially nearby. |
| `bvturr` | `bvtump`, `bvtur8`, `bvturr` | Independent bDE11blc/bld/ble/blf tubes; GC1 uses blc, GC2 uses blf. Same static tube/deploy hierarchy as NSDF turret. No split needed for an individual tube; configure kick for machinegun variants and per-slot behavior for AT-Stabber variants. |
| `cbtowe` | `cbtowe`, `cbtoweb`, `cbtowed`, `cbtowef` | cgt11tx1 owns only the long narrow cannon tube: 444 vertices / 648 triangles, approximately 0.70 x 0.70 x 5.65 m. It is a static native node beneath yaw and owns GC1. Recoil can translate this aimed tube while retaining live orientation. No mesh split needed to move the whole tube; splitting is optional if only its end sleeve should telescope. |
| `cr16tow` | `cr16tow` | Separate sgn11bgb (GC1) and sgn11bga (GC2) tips. Static native nodes and distinct weighted geometry. Keep shared aiming head stationary in translation. Beam variants still need accepted-fire/runtime support and kick policy; geometry readiness alone does not enable them. |
| `sbtowe` | `sb0002`, `sbtowe`, `sbtowea`, `sbtoweb`, `sbtowec`, `sbtowed`, `sbtowee` | Separate sgn11bgb (GC1) and sgn11bga (GC2) tips. Static native nodes and distinct weighted geometry. Keep shared aiming head stationary in translation. Beam variants still need accepted-fire/runtime support and kick policy; geometry readiness alone does not enable them. |
| `svtank` | `svtank`, `svtanka`, `svtas8`, `svtk13`, `svtnk7` | Existing SCZ11BGB slot-1 binding. Secondary chaingun is on scz11bda and needs its own gun-only weighting. Utility/Thumper slots must not drive the cannon barrel. |

## Every CR unit and equipped slot

| ODF | Slot / weapon | Recoil | Flash offset | Casings | Runtime / unresolved placement |
|---|---|---|---|---|---|
| `abtowe` | 1: `gspstabn` | `agn11bgb` | -0.06 0.02 0.23 | large | accepted-shot path; live validation pending; casing port estimated |
| `avarmp` | 1: `ghartmp` | `aar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; casing port estimated |
| `avartl` | 1: `ghartill` | `aar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; casing port estimated |
| `avartl` | 2: `ghartill` | `aar11bgc` | 0.04 -0.06 0.74 | large | accepted-shot path; live validation pending; casing port estimated |
| `avartl` | 3: `ghartill` | `aar11bgb` | 0.00 -0.07 0.68 | large | accepted-shot path; live validation pending; casing port estimated |
| `avartl` | 4: `ghartill` | `aar11bga` | -0.01 -0.08 0.72 | large | accepted-shot path; live validation pending; casing port estimated |
| `avartla` | 1: `gpopguna` | `` | pending / omitted | unresolved | weapon definition missing; weapon definition missing |
| `avdemo` | 1: `gatstab` | `AGR11BGA` | 0.20 0.10 2.41 | medium | accepted-shot path; live validation pending; casing port estimated |
| `avdemo` | 2: `gminigun` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent AGR11BDA is not a barrel node and the hardpoint is 0.41 m behind its front geometry; casing port estimated |
| `avdemo` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `avdemo` | 4: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent AGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `avfigh` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `avfigh` | 2: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `avfimp` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `avfimp` | 2: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `avhraz` | 2: `grktbomb` | `ahr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhraz` | 3: `grktbomb` | `ahr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhrmp` | 2: `grktbomb` | `ahr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhrmp` | 3: `grktbomb` | `ahr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avlamp` | 1: `gtechno` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent lla11bda is not a barrel node and the hardpoint is 2.66 m behind its front geometry |
| `avltmp` | 1: `gtminig` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent aln11bda is not a barrel node and the hardpoint is 0.24 m ahead of its front geometry; casing port estimated |
| `avltmp` | 2: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent aln11bdc is not a barrel node and has no geometry around the hardpoint |
| `avltmp` | 3: `gmitsmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avltnk` | 1: `gminigun` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent aln11bda is not a barrel node and the hardpoint is 0.24 m ahead of its front geometry; casing port estimated |
| `avltnk` | 2: `ghornet` | `` | pending / omitted | none | native firing producer pending; parent aln11bdc is not a barrel node and has no geometry around the hardpoint |
| `avltnk` | 3: `gflare` | `` | pending / omitted | none | native firing producer pending; countermeasure deployment |
| `avmine` | 1: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avpsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avpsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avrckt` | 1: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `avrckt` | 2: `ghornet` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `avrckt` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avrsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avrsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avsav14` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avtamp` | 1: `gatstab` | `AGR11BGA` | 0.20 0.10 2.41 | medium | accepted-shot path; live validation pending; casing port estimated |
| `avtamp` | 2: `gmaggun` | `` | pending / omitted | none | native firing producer pending; parent AGR11BDA is not a barrel node and the hardpoint is 0.41 m behind its front geometry |
| `avtamp` | 3: `gredfld` | `` | pending / omitted | none | native firing producer pending; radar device |
| `avtank` | 1: `gatstab` | `AGR11BGA` | 0.20 0.10 2.41 | medium | accepted-shot path; live validation pending; casing port estimated |
| `avtank` | 2: `gminigun` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent AGR11BDA is not a barrel node and the hardpoint is 0.41 m behind its front geometry; casing port estimated |
| `avtank` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `avtank` | 4: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent AGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `avtest` | 1: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 2: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 3: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 4: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtump` | 1: `gtminig` | `aDE11blc` | 0.69 0.38 0.27 | small | accepted-shot path; live validation pending; casing port estimated |
| `avtump` | 2: `gtminig` | `aDE11blf` | 0.83 0.39 0.27 | small | accepted-shot path; live validation pending; casing port estimated |
| `avturr` | 1: `gtminig` | `aDE11blc` | 0.69 0.38 0.27 | small | accepted-shot path; live validation pending; casing port estimated |
| `avwalk` | 1: `gatstaba` | `` | pending / omitted | medium | accepted-shot path; live validation pending; parent age11tx2 is not a barrel node and the hardpoint is 0.85 m behind its front geometry; casing port estimated |
| `avwalk` | 2: `gatstaba` | `` | pending / omitted | medium | accepted-shot path; live validation pending; parent age11tx1 is not a barrel node and the hardpoint is 0.83 m behind its front geometry; casing port estimated |
| `avwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent age11ty1 is not a barrel node and the hardpoint is 0.49 m behind its front geometry |
| `avwamp` | 1: `gmaggun` | `` | pending / omitted | none | native firing producer pending; parent age11tx2 is not a barrel node and the hardpoint is 0.85 m behind its front geometry |
| `avwamp` | 2: `gmaggun` | `` | pending / omitted | none | native firing producer pending; parent age11tx1 is not a barrel node and the hardpoint is 0.83 m behind its front geometry |
| `avwamp` | 3: `gsplint` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent age11ty1 is not a barrel node and the hardpoint is 0.49 m behind its front geometry |
| `bbtowe` | 1: `gblastb` | `agn11bgb` | -0.06 0.02 0.23 | none | accepted-shot path; live validation pending |
| `bv0002` | 2: `grktbomb` | `bhr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bv0002` | 3: `grktbomb` | `bhr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvartl` | 1: `ghartill` | `bar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; casing port estimated |
| `bvfigh` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvfigh` | 3: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvfigha` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvfigha` | 2: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvhraz` | 1: `gtaggun` | `bhr11bga` | pending / omitted | none | native firing producer pending; visible tip is -2.03 m from the hardpoint (under -0.1 m) |
| `bvhraz` | 2: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `bvhraz` | 3: `gcomet` | `bhr11bga` | 0.03 -0.01 1.32 | none | native firing producer pending |
| `bvhraza` | 2: `grktbomb` | `bhr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvhraza` | 3: `grktbomb` | `bhr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvltnk` | 1: `gatstab` | `` | pending / omitted | medium | accepted-shot path; live validation pending; parent bln11bda is not a barrel node and the hardpoint is 0.24 m ahead of its front geometry; casing port estimated |
| `bvltnk` | 2: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `bvltnk` | 3: `gphantom` | `` | pending / omitted | none | native firing producer pending; cloak device |
| `bvltnka` | 1: `gatstab` | `` | pending / omitted | medium | accepted-shot path; live validation pending; parent bln11bda is not a barrel node and the hardpoint is 0.24 m ahead of its front geometry; casing port estimated |
| `bvmine` | 1: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvmru` | 1: `grepa` | `` | pending / omitted | none | native firing producer pending; repair dispenser |
| `bvmru` | 2: `gammo` | `` | pending / omitted | none | native firing producer pending; supply dispenser |
| `bvra8` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvra8` | 2: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvraz` | 1: `gtminig` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvraz` | 3: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvrckt` | 1: `gtaggun` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvrckt` | 2: `gtaggun` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvrckt` | 3: `gredfld` | `` | pending / omitted | none | native firing producer pending; radar device |
| `bvrdev` | 1: `gtminig` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry; casing port estimated |
| `bvrdev` | 2: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent brd11bda is not a barrel node and has no geometry around the hardpoint |
| `bvrdev` | 3: `gsitecam` | `` | pending / omitted | none | native firing producer pending; camera device |
| `bvrdeva` | 1: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry; casing port estimated |
| `bvrdeva` | 2: `ghornet` | `` | pending / omitted | none | native firing producer pending; parent brd11bda is not a barrel node and has no geometry around the hardpoint |
| `bvrmpa` | 1: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry |
| `bvrmpa` | 2: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and has no geometry around the hardpoint |
| `bvrmpb` | 1: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry; casing port estimated |
| `bvrmpb` | 2: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent brd11bda is not a barrel node and has no geometry around the hardpoint; casing port estimated |
| `bvtank` | 1: `gspstab` | `bGR11BGA` | 0.20 0.10 2.41 | large | accepted-shot path; live validation pending; casing port estimated |
| `bvtank` | 3: `gmortar` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent bGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `bvtank` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvtanka` | 1: `gspstab` | `bGR11BGA` | 0.20 0.10 2.41 | large | accepted-shot path; live validation pending; casing port estimated |
| `bvtanka` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent bGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `bvtanka` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvtump` | 1: `gatstab` | `bDE11blc` | 0.69 0.38 0.27 | medium | accepted-shot path; live validation pending; casing port estimated |
| `bvtump` | 2: `gatstab` | `bDE11blf` | 0.83 0.39 0.27 | medium | accepted-shot path; live validation pending; casing port estimated |
| `bvtur8` | 1: `gminigun` | `bDE11blc` | 0.69 0.38 0.27 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvturr` | 1: `gtminig` | `bDE11blc` | 0.69 0.38 0.27 | small | accepted-shot path; live validation pending; casing port estimated |
| `bvwalk` | 1: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent age11tx2 is not a barrel node and the hardpoint is 0.85 m behind its front geometry; casing port estimated |
| `bvwalk` | 2: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent age11tx1 is not a barrel node and the hardpoint is 0.83 m behind its front geometry; casing port estimated |
| `cblasr` | 1: `gspstaba` | `` | pending / omitted | large | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `cbtowe` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; casing port estimated |
| `cbtowea` | 1: `gflashch` | `` | pending / omitted | none | native firing producer pending; hardpoint 'GC1' matches 0 skeleton bones |
| `cbtoweb` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; casing port estimated |
| `cbtowec` | 1: `gflashch` | `` | pending / omitted | none | native firing producer pending; hardpoint 'GC1' matches 0 skeleton bones |
| `cbtowed` | 1: `grktbomb` | `cgt11tx1` | 0.10 0.00 0.26 | none | accepted-shot path; live validation pending |
| `cbtowee` | 1: `gflashch` | `` | pending / omitted | none | native firing producer pending; hardpoint 'GC1' matches 0 skeleton bones |
| `cbtowef` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; casing port estimated |
| `cr16tow` | 1: `cr16bolt` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `cr16tow` | 2: `cr16bolt` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `crfraz` | 1: `crfpuls` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cfr11bda is not a barrel node and has no geometry around the hardpoint |
| `crfraz` | 2: `crfarc` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cfr11bdb is not a barrel node and has no geometry around the hardpoint |
| `cvartl` | 1: `ghartill` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvartla` | 1: `cvwo003` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `cvfigh` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfigh` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfigha` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfigha` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighb` | 1: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighb` | 2: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighc` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighc` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighd` | 1: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighe` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighe` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighf` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighf` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighg` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighg` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighh` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfighh` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfimp` | 1: `gminignc` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvfimp` | 2: `gminignc` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvhmpa` | 1: `gspstaba` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint; casing port estimated |
| `cvhmpa` | 2: `gspstaba` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint; casing port estimated |
| `cvhmpa` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `cvhmpb` | 1: `gmaggun` | `` | pending / omitted | none | native firing producer pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint |
| `cvhmpb` | 2: `gmaggun` | `` | pending / omitted | none | native firing producer pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint |
| `cvhraz` | 1: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhraz` | 2: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhraza` | 2: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhraza` | 3: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhrazb` | 2: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhrazb` | 3: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhtnk` | 1: `gspstaba` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint; casing port estimated |
| `cvhtnk` | 2: `gspstaba` | `` | pending / omitted | large | accepted-shot path; live validation pending; parent CEM11BDA is not a barrel node and has no geometry around the hardpoint; casing port estimated |
| `cvhzmp` | 1: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvhzmp` | 2: `grktbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent CPX11BDA0 is not a barrel node and has no geometry around the hardpoint |
| `cvltnk` | 1: `gatstab` | `` | 0.00 0.00 0.00 | medium | accepted-shot path; live validation pending; casing port estimated |
| `cvltnk` | 3: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `cvmine` | 1: `gctesla` | `` | pending / omitted | none | native firing producer pending; field deployment |
| `cvminea` | 1: `gammoa` | `` | pending / omitted | none | native firing producer pending; supply dispenser |
| `cvminea` | 2: `grepaa` | `` | pending / omitted | none | native firing producer pending; repair dispenser |
| `cvraz` | 1: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvraz` | 2: `gminigun` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvrckt` | 1: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `cvrckt` | 2: `gshadow` | `` | pending / omitted | none | native firing producer pending; parent CDR11BDA is not a barrel node and the hardpoint is 0.30 m ahead of its front geometry |
| `cvrckt` | 3: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent CDR11BDA is not a barrel node and the hardpoint is 0.30 m ahead of its front geometry |
| `cvrckt` | 4: `gctesla` | `` | pending / omitted | none | native firing producer pending; field deployment |
| `cvtank` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtmpa` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtmpa` | 2: `gmaggun` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `cvtmpa` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent CYE11BDA is not a barrel node and the hardpoint is 0.12 m ahead of its front geometry |
| `cvtnk` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtnk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent CYE11BDA is not a barrel node and the hardpoint is 0.12 m ahead of its front geometry |
| `cvtnka` | 1: `gdummy` | `` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvtnkb` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtnkc` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtnkc` | 2: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtnkd` | 1: `gspstabd` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvtnkd` | 2: `gspstabd` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvturr` | 1: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturr` | 2: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturr` | 3: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturr` | 4: `gminigrn` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturra` | 1: `gtminis` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturra` | 2: `gtminis` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturra` | 3: `gtminis` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `cvturra` | 4: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `cvturrb` | 1: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvturrb` | 3: `gspstabb` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvturrc` | 1: `gspstabc` | `` | 0.00 0.00 0.00 | large | accepted-shot path; live validation pending; casing port estimated |
| `cvwalk` | 1: `gblastg` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `cvwalk` | 2: `gblastg` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.97 m behind its front geometry |
| `cvwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent cvw11sup is not a barrel node and has no geometry around the hardpoint |
| `cvwamp` | 1: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `cvwamp` | 3: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent cvw11sup is not a barrel node and has no geometry around the hardpoint |
| `sb0002` | 1: `gflashgn` | `sgn11bgb` | -0.02 0.47 3.23 | none | native firing producer pending |
| `sb0002` | 2: `gflashgn` | `sgn11bga` | 0.01 0.47 3.22 | none | native firing producer pending |
| `sbtowe` | 1: `gblasth` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowe` | 2: `gblasth` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowea` | 1: `gtminis` | `sgn11bgb` | -0.02 0.47 3.23 | small | accepted-shot path; live validation pending; casing port estimated |
| `sbtowea` | 2: `gatstab` | `sgn11bga` | 0.01 0.47 3.22 | medium | accepted-shot path; live validation pending; casing port estimated |
| `sbtoweb` | 1: `gspstab` | `sgn11bgb` | -0.02 0.47 3.23 | large | accepted-shot path; live validation pending; casing port estimated |
| `sbtoweb` | 2: `gspstab` | `sgn11bga` | 0.01 0.47 3.22 | large | accepted-shot path; live validation pending; casing port estimated |
| `sbtowec` | 1: `gbolt` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowec` | 2: `gbolt` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowed` | 1: `grktbomb` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowed` | 2: `grktbomb` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowee` | 1: `gflashgn` | `sgn11bgb` | -0.02 0.47 3.23 | none | native firing producer pending |
| `sbtowee` | 2: `gflashgn` | `sgn11bga` | 0.01 0.47 3.22 | none | native firing producer pending |
| `svarmp` | 1: `ghartmp` | `` | pending / omitted | large | accepted-shot path; live validation pending; visible tip is -0.02 m from the hardpoint (under 0.1 m); casing port estimated |
| `svartl` | 1: `ghartill` | `` | pending / omitted | large | accepted-shot path; live validation pending; visible tip is -0.02 m from the hardpoint (under 0.1 m); casing port estimated |
| `svartla` | 1: `ghartila` | `` | pending / omitted | large | accepted-shot path; live validation pending; visible tip is -0.02 m from the hardpoint (under 0.1 m); casing port estimated |
| `svdemo` | 1: `grktbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svdemo` | 2: `grktbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svfi12` | 1: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfi12` | 2: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfi12` | 3: `gsitecam` | `` | pending / omitted | none | native firing producer pending; camera device |
| `svfigh` | 1: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfigh` | 2: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfigha` | 1: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfigha` | 2: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfimp` | 1: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svfimp` | 2: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; casing port estimated |
| `svhr13` | 2: `gsrkbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svhr13` | 3: `gsrkbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent shb11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry |
| `svhraz` | 2: `gsrkbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svhraz` | 3: `gsrkbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent shb11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry |
| `svhrmp` | 1: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent shb11bdc is not a barrel node and the hardpoint is 0.79 m behind its front geometry |
| `svhrmp` | 2: `gsrkbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svhrmp` | 3: `gsrkbomb` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent shb11bda is not a barrel node and the hardpoint is 0.86 m behind its front geometry |
| `svlt13` | 1: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent slt11trt is not a barrel node and the hardpoint is 1.03 m behind its front geometry |
| `svlt13` | 3: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svltnk` | 1: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent slt11trt is not a barrel node and the hardpoint is 1.03 m behind its front geometry |
| `svltnk` | 3: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svmine` | 1: `gbetmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svrckt` | 1: `gshadow` | `` | pending / omitted | none | native firing producer pending; parent srt11bda is not a barrel node and the hardpoint is 1.43 m behind its front geometry |
| `svrckt` | 2: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svrckt` | 3: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent srt11bda is not a barrel node and the hardpoint is 0.74 m ahead of its front geometry |
| `svrckt` | 4: `gbetmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent ssv11bda is not a barrel node and the hardpoint is 17.29 m ahead of its front geometry |
| `svsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svtank` | 1: `gsatstab` | `SCZ11BGB` | 0.00 0.00 3.42 | none | accepted-shot path; live validation pending |
| `svtank` | 2: `gminisov` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent scz11bda is not a barrel node and the hardpoint is 1.46 m behind its front geometry; casing port estimated |
| `svtank` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtanka` | 1: `gsatstab` | `SCZ11BGB` | 0.00 0.00 3.42 | none | accepted-shot path; live validation pending |
| `svtanka` | 2: `gminisov` | `` | pending / omitted | small | accepted-shot path; live validation pending; parent scz11bda is not a barrel node and the hardpoint is 1.46 m behind its front geometry; casing port estimated |
| `svtanka` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtas8` | 1: `gatstab` | `SCZ11BGB` | 0.00 0.00 3.42 | medium | accepted-shot path; live validation pending; casing port estimated |
| `svtas8` | 2: `gflashgn` | `` | pending / omitted | none | native firing producer pending; parent scz11bda is not a barrel node and the hardpoint is 1.46 m behind its front geometry |
| `svtas8` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtas8` | 4: `gnavdrop` | `` | pending / omitted | none | native firing producer pending; navigation beacon deployment |
| `svtk13` | 1: `gspstab` | `SCZ11BGB` | 0.00 0.00 3.42 | large | accepted-shot path; live validation pending; casing port estimated |
| `svtk13` | 2: `gflashgn` | `` | pending / omitted | none | native firing producer pending; parent scz11bda is not a barrel node and the hardpoint is 1.46 m behind its front geometry |
| `svtk13` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtk13` | 4: `gnavdrop` | `` | pending / omitted | none | native firing producer pending; navigation beacon deployment |
| `svtnk7` | 1: `ga7stab` | `SCZ11BGB` | 0.00 0.00 3.42 | medium | accepted-shot path; live validation pending; casing port estimated |
| `svtump` | 1: `gtminis` | `` | pending / omitted | small | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `svtump` | 2: `gtminis` | `` | pending / omitted | small | accepted-shot path; live validation pending; hardpoint 'GC2' matches 0 skeleton bones; casing port estimated |
| `svturr` | 1: `gtminis` | `` | pending / omitted | small | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `svturra` | 1: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `svturrb` | 1: `gspstab` | `` | pending / omitted | large | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `svturrc` | 1: `gminigna` | `` | pending / omitted | small | accepted-shot path; live validation pending; hardpoint 'GC1' matches 0 skeleton bones; casing port estimated |
| `svwalk` | 1: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent svw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `svwalk` | 2: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent svw11hed is not a barrel node and the hardpoint is 0.97 m behind its front geometry |
| `svwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
| `svwalka` | 1: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent svw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `svwalka` | 2: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent svw11hed is not a barrel node and the hardpoint is 0.97 m behind its front geometry |
| `svwalka` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
| `svwamp` | 1: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent svw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `svwamp` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
