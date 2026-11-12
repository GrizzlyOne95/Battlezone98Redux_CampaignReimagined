# CR combat weapon effects: implementation and mesh-edit report

Weapon-rig update, 2026-11-04. Generated from CR source, reviewed model policy and fitted flash data. See [the model-edit report](WEAPON_RIGS.md) for the requested 27-model pass and exported previews.

**136 armed ODFs / 53 models / 305 equipped slots.** Authored recoil: 225 slots; fitted flash offsets: 221 slots; ballistic casing selections: 145 slots.

Scope: CR vehicle/building definitions, including mission variants and utility carriers. People retain per-weapon effects; armories supply weapons. This source-only count excludes stock-only aliases from the earlier 139-definition/52-model audit.

## What is implemented

- The requested 27 models now have closed split gun pieces and EXU clips, with matching clips on visible cockpit gun copies. `cvfigh` rotates its forward minigun clusters; `cvturr` has four independent channels. Other reviewed independent gun pieces retain node bindings. Weapon gameplay/loadouts are preserved.
- Flash fitting uses explicit visible gun pieces, including sibling bomber guns, non-BG turret tubes and the CRA gun-tower tube. The weapon offset stays zero; craft slots receive geometry-derived corrections.
- All 100 inventoried weapon ODFs already select small/medium/large/none casings. This pass checks every CR loadout against those decisions; plasma/energy/rocket/utility weapons remain casing-free.

## Remaining runtime and asset work

- These are authored configurations, not native visual acceptance. Existing OpenShim/EXU effect settings, exact-build and single-player gates remain. Beam/guided/targeting/other producer gaps remain explicit in the slot report.
- The new spin and fitted per-slot casing ports require [OpenShim PR 698](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/698). That source builds and passes host tests; CR shipping binaries have not been refreshed. Other models still use the estimated native breech.
- Recoil is cosmetic. Qualify muzzle flash placement at both rest and kicked poses, aiming, deployment, repeated/simultaneous shots, weapon swaps and scene reload.
- `avartla` selects `gpopguna`, absent from both CR and the extracted stock ODFs. It remains unresolved rather than silently substituting a different weapon.

## Units needing mesh or rig edits

| Model | Unit ODFs | Work category | Proposed change |
|---|---|---|---|
| `avland` | `avlamp` | Isolate gun geometry | The armed lander marker is attached to lla11bda. Identify/select the visible muzzle/emitter and give it a gun-only child; preserve the large landing structure. No ready dedicated cannon-tip node found. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `avsav` | `avpsav`, `avrsav`, `avsav`, `avsav14` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `crfraz` | `crfraz` | Emitter/asset decision | GC1/GC2 sit at the muzzles of static wing-top cannon mounts (Build-HardpointMounts, 2026-11-10). The mounts are welded to the wings and get no recoil; do not recoil the complete Fury hull or wings. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `cvwalk` | `cvwalk`, `cvwamp` | Isolate gun geometry | Two guns share the aiming head. Add independent weighted gun children beneath the head, retaining aim and gait. Current rendered muzzle names also differ from some native model names; fit from the native fired slots and actual visible barrels. Do not translate the entire head. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `hvturr` | `hvturr` | Emitter/asset decision | Fury Turret (CR original, skinned organic hull): both gbolt hardpoints fire from the glowing eye face on the head (hvt11tx1) with no barrel node. Do not recoil the head or hull; if motion is wanted, author an eye-glow pulse. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `hvwalk` | `hvwalk` | Isolate gun geometry | Fury Walker (CR original, procedural organic hull): the gbolt muzzles are moulded into the head (hvw11tx1/tx2) with no separate barrel node. Give each bolt gun a gun-only child before authoring recoil or casing ports. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `savfury` | `savfury` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |
| `svsav` | `svsav` | Emitter/asset decision | No independent conventional barrel found for the active weapon. These hull/emitter-driven special units need a deliberate emitter-core/lens mechanism or an authored energy pulse. If mechanical motion is desired, isolate/add a small local piece; do not recoil the complete Fury/special-unit hull or satellite structure. Fit muzzle/emitter markers to the visible apertures; energy/rocket loadouts need no brass port. |

## Requested model edits authored

| Model | Unit ODFs | Result / qualification |
|---|---|---|
| `avfigh` | `avfigh`, `avfimp` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `avltnk` | `avltmp`, `avltnk` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `avrckt` | `avrckt` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `avtest` | `avtest` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `avwalk` | `avwalk`, `avwamp` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `bvltnk` | `bvltnk`, `bvltnka` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `bvraz` | `bvfigh`, `bvfigha`, `bvra8`, `bvraz` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `bvrckt` | `bvrckt` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `bvrdev` | `bvrdev`, `bvrdeva`, `bvrmpa`, `bvrmpb` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `bvwalk` | `bvwalk` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cblasr` | `cblasr`, `cbtowea`, `cbtowec`, `cbtowee` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvartl` | `cvartl`, `cvartla` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvfigh` | `cvfigh`, `cvfigha`, `cvfighb`, `cvfighc`, `cvfighd`, `cvfighe`, `cvfighf`, `cvfighg`, `cvfighh`, `cvfimp`, `cvraz` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvhraz` | `cvhraz`, `cvhraza`, `cvhrazb`, `cvhzmp` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvhtnk` | `cvhmpa`, `cvhmpb`, `cvhtnk` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvltnk` | `cvltnk` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvrckt` | `cvrckt` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvtnk` | `cvtank`, `cvtmpa`, `cvtnk`, `cvtnka`, `cvtnkb`, `cvtnkc`, `cvtnkd` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `cvturr` | `cvturr`, `cvturra`, `cvturrb`, `cvturrc` | Closed gun sections and EXU world/cockpit clips authored; 4 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svartl` | `svarmp`, `svartl`, `svartla` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svfigh` | `svdemo`, `svfi12`, `svfigh`, `svfigha`, `svfimp` | Closed gun sections and EXU world/cockpit clips authored; 2 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svhraz` | `svhr13`, `svhraz`, `svhrmp` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svltnk` | `svlt13`, `svltnk` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svrckt` | `svrckt` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svtank` | `svtank`, `svtanka`, `svtas8`, `svtk13`, `svtnk7` | Closed gun sections and EXU world/cockpit clips authored; 1 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svturr` | `svtump`, `svturr`, `svturra`, `svturrb`, `svturrc` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |
| `svwalk` | `svwalk`, `svwalka`, `svwamp` | Closed gun sections and EXU world/cockpit clips authored; 0 channels contain cockpit gun geometry. Original drivers, source UVs and closed receiver caps retained. Outboard casing ports are ray-fitted clear of the world hull; requires companion OpenShim spin/port support. Native visual qualification remains pending. |

## Models using existing gun pieces

| Model | Unit ODFs | Binding / remaining detail |
|---|---|---|
| `abtowe` | `abtowe` | Use agn11bgb: 38 vertices / 34 triangles, rigid weight 1.0, native node and static local translation. GC1 is its child. No geometry split needed; tune short tip travel. Preserve ty1/tx1 aim parents. |
| `avartl` | `avarmp`, `avartl`, `avartla` | Four separate aar11bgd/bgc/bgb/bga barrels for GM1/2/3/4. Bind each fired slot independently. Preserve deployed pose and aiming; mortar weapons need an explicit kick because existing CR kicks are CANN-category only. |
| `avhraz` | `avhraz`, `avhrmp` | Two independent top-gun meshes: ahr11bga / ahr11bgb, each 500 vertices / 636 triangles, weight 1.0 and static native node. Default GR1/GR2 markers are under ahr11rof, but their positions lie inside the corresponding left/right barrel bounds. Bind slot 2 to bga, slot 3 to bgb explicitly; both grktbomb slots need craft recoilKick overrides. No geometry split is needed to move the whole existing top-gun pieces. A tip-only telescoping action would require subdivision/reweighting. Do not recoil the roof. |
| `avtank` | `avdemo`, `avtamp`, `avtank` | Existing AGR11BGA cannon binding. Secondary gun is on AGR11BDA and needs gun-only weighting if physical secondary recoil is wanted; do not slide the hull. |
| `avturr` | `avtump`, `avtur2b`, `avturr` | Independent barrel tubes aDE11blc/bld/ble/blf, each 116 vertices / 190 triangles. GC1 uses blc, GC2 blf, GC3 bld, GC4 ble (one tube per hardpoint). These names are not BG*, so the old heuristic missed them. Static translations allow a node-slide candidate without cutting geometry. Keep the animated deploy base and aiming parents; choose whether a whole barrel cluster or only fired tube should react. Miniguns require a craft kick override. |
| `bbtowe` | `bbtowe` | Use agn11bgb: 38 vertices / 34 triangles, rigid weight 1.0, native node and static local translation. GC1 is its child. No geometry split needed; tune short tip travel. Preserve ty1/tx1 aim parents. |
| `bvartl` | `bvartl` | bar11bgd is the default GM1 barrel; the model also has the other separate barrel pieces. No split needed for its existing barrel; preserve deployment and use mortar kick opt-in. |
| `bvhraz` | `bv0002`, `bvhraz`, `bvhraza` | Same separate top-gun layout as NSDF: bhr11bga/bhr11bgb. The default rocket variants use slots 2/3 under the roof; map them explicitly to left/right gun pieces. The bvhraz variant has GM1 utility and Comet at GR1: choose bindings per loadout, not per generic slot index. Its GC1 fires from the static hardpoint-mount cannon on bhr11bda (References/HardpointMounts/bvhraz.json), so GC1 has no recoil binding: it must not kick the top gun. |
| `bvtank` | `bvtank`, `bvtanka` | Existing bGR11BGA cannon binding. GM1 is under the hull and must not blindly reuse the cannon barrel merely because it is spatially nearby. |
| `bvturr` | `bvtump`, `bvtur8`, `bvturr` | Independent bDE11blc/bld/ble/blf tubes; GC1 uses blc, GC2 blf, GC3 bld, GC4 ble (one tube per hardpoint). Same static tube/deploy hierarchy as NSDF turret. No split needed for an individual tube; configure kick for machinegun variants and per-slot behavior for AT-Stabber variants. |
| `cbtowe` | `cbtowe`, `cbtoweb`, `cbtowed`, `cbtowef` | cgt11tx1 owns only the long narrow cannon tube: 444 vertices / 648 triangles, approximately 0.70 x 0.70 x 5.65 m. It is a static native node beneath yaw and owns GC1. Recoil can translate this aimed tube while retaining live orientation. No mesh split needed to move the whole tube; splitting is optional if only its end sleeve should telescope. |
| `cr16tow` | `cr16tow` | Separate sgn11bgb (GC1) and sgn11bga (GC2) tips. Static native nodes and distinct weighted geometry. Keep shared aiming head stationary in translation. Beam variants still need accepted-fire/runtime support and kick policy; geometry readiness alone does not enable them. |
| `sbtowe` | `sb0002`, `sbtowe`, `sbtowea`, `sbtoweb`, `sbtowec`, `sbtowed`, `sbtowee` | Separate sgn11bgb (GC1) and sgn11bga (GC2) tips. Static native nodes and distinct weighted geometry. Keep shared aiming head stationary in translation. Beam variants still need accepted-fire/runtime support and kick policy; geometry readiness alone does not enable them. |

## Every CR unit and equipped slot

| ODF | Slot / weapon | Recoil | Flash offset | Casings | Runtime / unresolved placement |
|---|---|---|---|---|---|
| `abtowe` | 1: `gspstabn` | `agn11bgb` | -0.06 0.02 0.23 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avarmp` | 1: `ghartmp` | `aar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avartl` | 1: `ghartill` | `aar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avartl` | 2: `ghartill` | `aar11bgc` | 0.04 -0.06 0.74 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avartl` | 3: `ghartill` | `aar11bgb` | 0.00 -0.07 0.68 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avartl` | 4: `ghartill` | `aar11bga` | -0.01 -0.08 0.72 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avartla` | 1: `gpopguna` | `` | pending / omitted | unresolved | weapon definition missing; weapon definition missing |
| `avdemo` | 1: `gatstab` | `AGR11BGA` | 0.04 0.00 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avdemo` | 2: `gminigun` | `` | pending / omitted | small | accepted-shot path; live validation pending; visible tip is -0.00 m from the hardpoint (under 0.1 m); estimated native breech; model port fitting pending |
| `avdemo` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `avdemo` | 4: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent AGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `avfigh` | 1: `gminigun` | `animation:cr_fire_1` | -0.03 0.08 0.05 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avfigh` | 2: `gminigun` | `animation:cr_fire_2` | 0.03 0.08 0.05 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avfimp` | 1: `gminigun` | `animation:cr_fire_1` | -0.03 0.08 0.05 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avfimp` | 2: `gminigun` | `animation:cr_fire_2` | 0.03 0.08 0.05 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avhraz` | 2: `grktbomb` | `ahr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhraz` | 3: `grktbomb` | `ahr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhrmp` | 2: `grktbomb` | `ahr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avhrmp` | 3: `grktbomb` | `ahr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `avlamp` | 1: `gtechno` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent lla11bda is not a barrel node and the hardpoint is 2.66 m behind its front geometry |
| `avltmp` | 1: `gtminig` | `animation:cr_fire_1` | -0.01 0.01 0.42 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avltmp` | 2: `gtaggun` | `animation:cr_fire_2` | 0.04 -0.06 0.38 | none | native firing producer pending |
| `avltmp` | 3: `gmitsmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avltnk` | 1: `gminigun` | `animation:cr_fire_1` | -0.01 0.01 0.42 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avltnk` | 2: `ghornet` | `animation:cr_fire_2` | 0.04 -0.06 0.38 | none | native firing producer pending |
| `avltnk` | 3: `gflare` | `` | pending / omitted | none | native firing producer pending; countermeasure deployment |
| `avmine` | 1: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avpsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avpsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avrckt` | 1: `gshadow` | `animation:cr_fire_1` | 0.00 -0.23 0.24 | none | native firing producer pending |
| `avrckt` | 2: `ghornet` | `animation:cr_fire_2` | 0.00 -0.23 0.24 | none | native firing producer pending |
| `avrckt` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avrsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avrsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `avsav14` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent polymsh is not a barrel node and the hardpoint is 2.27 m behind its front geometry |
| `avtamp` | 1: `gatstab` | `AGR11BGA` | 0.04 0.00 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtamp` | 2: `gmaggun` | `` | pending / omitted | none | native firing producer pending; visible tip is -0.00 m from the hardpoint (under 0.1 m) |
| `avtamp` | 3: `gredfld` | `` | pending / omitted | none | native firing producer pending; radar device |
| `avtank` | 1: `gatstab` | `AGR11BGA` | 0.04 0.00 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtank` | 2: `gminigun` | `` | pending / omitted | small | accepted-shot path; live validation pending; visible tip is -0.00 m from the hardpoint (under 0.1 m); estimated native breech; model port fitting pending |
| `avtank` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `avtank` | 4: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent AGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `avtest` | 1: `gdummy` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 2: `gdummy` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 3: `gdummy` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtest` | 4: `gdummy` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `avtump` | 1: `gtmgav2` | `aDE11blc` | -0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtump` | 2: `gtmgav2` | `aDE11blf` | 0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtump` | 3: `gtmgav2` | `aDE11bld` | -0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtump` | 4: `gtmgav2` | `aDE11ble` | 0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtur2b` | 1: `gtmgav4` | `aDE11blc` | -0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtur2b` | 2: `gtmgav4` | `aDE11blf` | 0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtur2b` | 3: `gtmgav4` | `aDE11bld` | -0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avtur2b` | 4: `gtmgav4` | `aDE11ble` | 0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avturr` | 1: `gtmgav4` | `aDE11blc` | -0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avturr` | 2: `gtmgav4` | `aDE11blf` | 0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avturr` | 3: `gtmgav4` | `aDE11bld` | -0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avturr` | 4: `gtmgav4` | `aDE11ble` | 0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `avwalk` | 1: `gatstaba` | `animation:cr_fire_1` | 0.12 0.07 0.84 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avwalk` | 2: `gatstaba` | `animation:cr_fire_2` | -0.10 0.12 0.81 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `avwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent age11ty1 is not a barrel node and the hardpoint is 0.49 m behind its front geometry |
| `avwamp` | 1: `gmaggun` | `animation:cr_fire_1` | 0.12 0.07 0.84 | none | native firing producer pending |
| `avwamp` | 2: `gmaggun` | `animation:cr_fire_2` | -0.10 0.12 0.81 | none | native firing producer pending |
| `avwamp` | 3: `gsplint` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent age11ty1 is not a barrel node and the hardpoint is 0.49 m behind its front geometry |
| `bbtowe` | 1: `gblastb` | `agn11bgb` | -0.06 0.02 0.23 | none | accepted-shot path; live validation pending |
| `bv0002` | 2: `grktbomb` | `bhr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bv0002` | 3: `grktbomb` | `bhr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvartl` | 1: `ghartill` | `bar11bgd` | 0.04 -0.07 0.71 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvfigh` | 1: `gminigun` | `animation:cr_fire_1` | -0.02 -0.24 -1.41 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvfigh` | 3: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvfigha` | 1: `gminigun` | `animation:cr_fire_1` | -0.02 -0.24 -1.41 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvfigha` | 2: `gminigun` | `animation:cr_fire_2` | 0.03 -0.25 -1.41 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvhraz` | 1: `gtaggun` | `` | pending / omitted | none | native firing producer pending; visible tip is -2.03 m from the hardpoint (under -0.1 m) |
| `bvhraz` | 2: `gsandbag` | `` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `bvhraz` | 3: `gcomet` | `bhr11bga` | 0.03 -0.01 1.32 | none | native firing producer pending |
| `bvhraza` | 2: `grktbomb` | `bhr11bga` | 0.03 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvhraza` | 3: `grktbomb` | `bhr11bgb` | -0.01 -0.01 1.32 | none | accepted-shot path; live validation pending |
| `bvltnk` | 1: `gatstab` | `animation:cr_fire_1` | -0.01 0.01 0.42 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvltnk` | 2: `gsandbag` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `bvltnk` | 3: `gphantom` | `` | pending / omitted | none | native firing producer pending; cloak device |
| `bvltnka` | 1: `gatstab` | `animation:cr_fire_1` | -0.01 0.01 0.42 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvmine` | 1: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvmru` | 1: `grepa` | `` | pending / omitted | none | native firing producer pending; repair dispenser |
| `bvmru` | 2: `gammo` | `` | pending / omitted | none | native firing producer pending; supply dispenser |
| `bvra8` | 1: `gminigun` | `animation:cr_fire_1` | -0.02 -0.24 -1.41 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvra8` | 2: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvraz` | 1: `gtminig` | `animation:cr_fire_1` | -0.02 -0.24 -1.41 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvraz` | 3: `gshadow` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `bvrckt` | 1: `gtaggun` | `animation:cr_fire_1` | 0.00 -0.23 0.24 | none | native firing producer pending |
| `bvrckt` | 2: `gtaggun` | `animation:cr_fire_2` | 0.00 -0.23 0.24 | none | native firing producer pending |
| `bvrckt` | 3: `gredfld` | `` | pending / omitted | none | native firing producer pending; radar device |
| `bvrdev` | 1: `gtminig` | `animation:cr_fire_2` | 0.00 0.02 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvrdev` | 2: `gtaggun` | `animation:cr_fire_2` | 0.02 -0.01 0.08 | none | native firing producer pending |
| `bvrdev` | 3: `gsitecam` | `` | pending / omitted | none | native firing producer pending; camera device |
| `bvrdeva` | 1: `gspstab` | `animation:cr_fire_2` | 0.00 0.02 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvrdeva` | 2: `ghornet` | `animation:cr_fire_2` | 0.02 -0.01 0.08 | none | native firing producer pending |
| `bvrmpa` | 1: `grktbomb` | `animation:cr_fire_2` | 0.00 0.02 -0.00 | none | accepted-shot path; live validation pending |
| `bvrmpa` | 2: `grktbomb` | `animation:cr_fire_2` | 0.02 -0.01 0.08 | none | accepted-shot path; live validation pending |
| `bvrmpb` | 1: `gspstab` | `animation:cr_fire_2` | 0.00 0.02 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvrmpb` | 2: `gspstab` | `animation:cr_fire_2` | 0.02 -0.01 0.08 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvtank` | 1: `gspstab` | `bGR11BGA` | 0.04 0.00 0.00 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtank` | 3: `gmortar` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent bGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `bvtank` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvtanka` | 1: `gspstab` | `bGR11BGA` | 0.04 0.00 0.00 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtanka` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent bGR11BDA is not a barrel node and has no geometry around the hardpoint |
| `bvtanka` | 4: `gproxmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `bvtump` | 1: `gatsbv2` | `bDE11blc` | -0.04 -0.04 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtump` | 2: `gatsbv2` | `bDE11blf` | 0.04 -0.04 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtump` | 3: `gatsbv2` | `bDE11bld` | -0.04 0.04 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtump` | 4: `gatsbv2` | `bDE11ble` | 0.04 0.04 0.00 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtur8` | 1: `gmgnbv4` | `bDE11blc` | -0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtur8` | 2: `gmgnbv4` | `bDE11blf` | 0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtur8` | 3: `gmgnbv4` | `bDE11bld` | -0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvtur8` | 4: `gmgnbv4` | `bDE11ble` | 0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvturr` | 1: `gtmgbv4` | `bDE11blc` | -0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvturr` | 2: `gtmgbv4` | `bDE11blf` | 0.04 -0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvturr` | 3: `gtmgbv4` | `bDE11bld` | -0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvturr` | 4: `gtmgbv4` | `bDE11ble` | 0.04 0.04 0.00 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `bvwalk` | 1: `gspstab` | `animation:cr_fire_1` | 0.12 0.07 0.84 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `bvwalk` | 2: `gspstab` | `animation:cr_fire_2` | -0.10 0.12 0.81 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cblasr` | 1: `gspstaba` | `animation:cr_fire_1` | -0.00 0.00 0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cbtowe` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `cbtowea` | 1: `gflashch` | `animation:cr_fire_1` | -0.00 0.00 0.00 | none | native firing producer pending |
| `cbtoweb` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `cbtowec` | 1: `gflashch` | `animation:cr_fire_1` | -0.00 0.00 0.00 | none | native firing producer pending |
| `cbtowed` | 1: `grktbomb` | `cgt11tx1` | 0.10 0.00 0.26 | none | accepted-shot path; live validation pending |
| `cbtowee` | 1: `gflashch` | `animation:cr_fire_1` | -0.00 0.00 0.00 | none | native firing producer pending |
| `cbtowef` | 1: `gatstaba` | `cgt11tx1` | 0.10 0.00 0.26 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `cr16tow` | 1: `cr16bolt` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `cr16tow` | 2: `cr16bolt` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `crfraz` | 1: `crfpuls` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cfr11bda is not a barrel node; the hardpoint already sits at the wing-top cannon mount muzzle |
| `crfraz` | 2: `crfarc` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cfr11bdb is not a barrel node; the hardpoint already sits at the wing-top cannon mount muzzle |
| `cvartl` | 1: `ghartill` | `animation:cr_fire_1` | 0.01 0.01 0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvartla` | 1: `cvwo003` | `animation:cr_fire_1` | 0.01 0.01 0.09 | none | accepted-shot path; live validation pending |
| `cvfigh` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfigh` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfigha` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfigha` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighb` | 1: `gdummy` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighb` | 2: `gdummy` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighc` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighc` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighd` | 1: `gdummy` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvfighe` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighe` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighf` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighf` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighg` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighg` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighh` | 1: `gminigrn` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfighh` | 2: `gminigrn` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfimp` | 1: `gminignc` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvfimp` | 2: `gminignc` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvhmpa` | 1: `gspstaba` | `animation:cr_fire_1` | 0.04 -0.01 0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvhmpa` | 2: `gspstaba` | `animation:cr_fire_2` | -0.03 -0.01 0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvhmpa` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `cvhmpb` | 1: `gmaggun` | `animation:cr_fire_1` | 0.04 -0.01 0.02 | none | native firing producer pending |
| `cvhmpb` | 2: `gmaggun` | `animation:cr_fire_2` | -0.03 -0.01 0.02 | none | native firing producer pending |
| `cvhraz` | 1: `grktbomb` | `animation:cr_fire_1` | -0.02 0.00 0.01 | none | accepted-shot path; live validation pending |
| `cvhraz` | 2: `grktbomb` | `animation:cr_fire_2` | 0.02 0.00 -0.11 | none | accepted-shot path; live validation pending |
| `cvhraza` | 2: `grktbomb` | `animation:cr_fire_1` | -0.02 0.00 0.01 | none | accepted-shot path; live validation pending |
| `cvhraza` | 3: `grktbomb` | `animation:cr_fire_2` | 0.02 0.00 -0.11 | none | accepted-shot path; live validation pending |
| `cvhrazb` | 2: `grktbomb` | `animation:cr_fire_1` | -0.02 0.00 0.01 | none | accepted-shot path; live validation pending |
| `cvhrazb` | 3: `grktbomb` | `animation:cr_fire_2` | 0.02 0.00 -0.11 | none | accepted-shot path; live validation pending |
| `cvhtnk` | 1: `gspstaba` | `animation:cr_fire_1` | 0.04 -0.01 0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvhtnk` | 2: `gspstaba` | `animation:cr_fire_2` | -0.03 -0.01 0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvhzmp` | 1: `grktbomb` | `animation:cr_fire_1` | -0.02 0.00 0.01 | none | accepted-shot path; live validation pending |
| `cvhzmp` | 2: `grktbomb` | `animation:cr_fire_2` | 0.02 0.00 -0.11 | none | accepted-shot path; live validation pending |
| `cvltnk` | 1: `gatstab` | `animation:cr_fire_1` | 0.00 0.07 0.08 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvltnk` | 3: `gsandbag` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `cvmine` | 1: `gctesla` | `` | pending / omitted | none | native firing producer pending; field deployment |
| `cvminea` | 1: `gammoa` | `` | pending / omitted | none | native firing producer pending; supply dispenser |
| `cvminea` | 2: `grepaa` | `` | pending / omitted | none | native firing producer pending; repair dispenser |
| `cvraz` | 1: `gminigun` | `animation:cr_fire_1` | -0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvraz` | 2: `gminigun` | `animation:cr_fire_2` | 0.05 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvrckt` | 1: `gshadow` | `animation:cr_fire_1` | 0.26 -0.01 0.01 | none | native firing producer pending |
| `cvrckt` | 2: `gshadow` | `animation:cr_fire_2` | -0.29 -0.01 0.01 | none | native firing producer pending |
| `cvrckt` | 3: `gmdmgun` | `` | 0.00 0.00 0.00 | none | native firing producer pending |
| `cvrckt` | 4: `gctesla` | `` | pending / omitted | none | native firing producer pending; field deployment |
| `cvtank` | 1: `gspstabb` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtmpa` | 1: `gspstabb` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtmpa` | 2: `gmaggun` | `animation:cr_fire_1` | 0.00 0.06 -0.09 | none | native firing producer pending |
| `cvtmpa` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent CYE11BDA is not a barrel node and the hardpoint is 0.12 m ahead of its front geometry |
| `cvtnk` | 1: `gspstabb` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtnk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent CYE11BDA is not a barrel node and the hardpoint is 0.12 m ahead of its front geometry |
| `cvtnka` | 1: `gdummy` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; paintball/debug effect |
| `cvtnkb` | 1: `gspstabb` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtnkc` | 1: `gspstabb` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtnkc` | 2: `gspstabb` | `animation:cr_fire_1` | 0.00 0.06 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtnkd` | 1: `gspstabd` | `animation:cr_fire_2` | 0.01 0.05 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvtnkd` | 2: `gspstabd` | `animation:cr_fire_1` | 0.00 0.06 -0.09 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturr` | 1: `gmgrcv1` | `animation:cr_fire_1` | -0.00 0.00 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturr` | 2: `gmgrcv1` | `animation:cr_fire_2` | -0.00 0.01 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturr` | 3: `gmgrcv1` | `animation:cr_fire_3` | 0.00 0.01 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturr` | 4: `gmgrcv1` | `animation:cr_fire_4` | 0.00 0.00 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturra` | 1: `gtminis` | `animation:cr_fire_1` | -0.00 0.00 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturra` | 2: `gtminis` | `animation:cr_fire_2` | -0.00 0.01 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturra` | 3: `gtminis` | `animation:cr_fire_3` | 0.00 0.01 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturra` | 4: `gsandbag` | `animation:cr_fire_4` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `cvturrb` | 1: `gspbcv2` | `animation:cr_fire_1` | -0.00 0.00 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrb` | 2: `gspbcv2` | `animation:cr_fire_2` | -0.00 0.01 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrb` | 3: `gspbcv2` | `animation:cr_fire_3` | 0.00 0.01 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrb` | 4: `gspbcv2` | `animation:cr_fire_4` | 0.00 0.00 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrc` | 1: `gspccv4` | `animation:cr_fire_1` | -0.00 0.00 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrc` | 2: `gspccv4` | `animation:cr_fire_2` | -0.00 0.01 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrc` | 3: `gspccv4` | `animation:cr_fire_3` | 0.00 0.01 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvturrc` | 4: `gspccv4` | `animation:cr_fire_4` | 0.00 0.00 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `cvwalk` | 1: `gblastg` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `cvwalk` | 2: `gblastg` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.97 m behind its front geometry |
| `cvwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent cvw11sup is not a barrel node and has no geometry around the hardpoint |
| `cvwamp` | 1: `gblast` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent cvw11hed is not a barrel node and the hardpoint is 0.80 m behind its front geometry |
| `cvwamp` | 3: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent cvw11sup is not a barrel node and has no geometry around the hardpoint |
| `hvturr` | 1: `gbolt` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `hvturr` | 2: `gbolt` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `hvwalk` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent hvw11tx2 is not a barrel node and the hardpoint is 7.82 m ahead of its front geometry |
| `hvwalk` | 2: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent hvw11tx1 is not a barrel node and the hardpoint is 7.82 m ahead of its front geometry |
| `hvwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent hvw11ty1 is not a barrel node and has no geometry around the hardpoint |
| `savfury` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent csf11bda is not a barrel node and the hardpoint is 17.29 m ahead of its front geometry |
| `savfury` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `sb0002` | 1: `gflashgn` | `sgn11bgb` | -0.02 0.47 3.23 | none | native firing producer pending |
| `sb0002` | 2: `gflashgn` | `sgn11bga` | 0.01 0.47 3.22 | none | native firing producer pending |
| `sbtowe` | 1: `gblasth` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowe` | 2: `gblasth` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowea` | 1: `gtminis` | `sgn11bgb` | -0.02 0.47 3.23 | small | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `sbtowea` | 2: `gatstab` | `sgn11bga` | 0.01 0.47 3.22 | medium | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `sbtoweb` | 1: `gspstab` | `sgn11bgb` | -0.02 0.47 3.23 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `sbtoweb` | 2: `gspstab` | `sgn11bga` | 0.01 0.47 3.22 | large | accepted-shot path; live validation pending; estimated native breech; model port fitting pending |
| `sbtowec` | 1: `gbolt` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowec` | 2: `gbolt` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowed` | 1: `grktbomb` | `sgn11bgb` | -0.02 0.47 3.23 | none | accepted-shot path; live validation pending |
| `sbtowed` | 2: `grktbomb` | `sgn11bga` | 0.01 0.47 3.22 | none | accepted-shot path; live validation pending |
| `sbtowee` | 1: `gflashgn` | `sgn11bgb` | -0.02 0.47 3.23 | none | native firing producer pending |
| `sbtowee` | 2: `gflashgn` | `sgn11bga` | 0.01 0.47 3.22 | none | native firing producer pending |
| `svarmp` | 1: `ghartmp` | `animation:cr_fire_1` | -0.03 0.04 -0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svartl` | 1: `ghartill` | `animation:cr_fire_1` | -0.03 0.04 -0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svartla` | 1: `ghartila` | `animation:cr_fire_1` | -0.03 0.04 -0.02 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svdemo` | 1: `grktbomb` | `animation:cr_fire_1` | 0.06 -0.01 0.03 | none | accepted-shot path; live validation pending |
| `svdemo` | 2: `grktbomb` | `` | 0.00 0.00 0.00 | none | accepted-shot path; live validation pending |
| `svfi12` | 1: `gminisov` | `animation:cr_fire_1` | 0.06 -0.01 0.03 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfi12` | 2: `gminisov` | `` | 0.00 0.00 0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfi12` | 3: `gsitecam` | `` | pending / omitted | none | native firing producer pending; camera device |
| `svfigh` | 1: `gminisov` | `animation:cr_fire_1` | 0.06 -0.01 0.03 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfigh` | 2: `gminisov` | `animation:cr_fire_2` | -0.07 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfigha` | 1: `gminisov` | `animation:cr_fire_1` | 0.06 -0.01 0.03 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfigha` | 2: `gminisov` | `animation:cr_fire_2` | -0.07 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfimp` | 1: `gminisov` | `animation:cr_fire_1` | 0.06 -0.01 0.03 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svfimp` | 2: `gminisov` | `animation:cr_fire_2` | -0.07 0.01 0.02 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svhr13` | 2: `gsrkbomb` | `animation:cr_fire_1` | 0.43 -1.30 1.36 | none | accepted-shot path; live validation pending |
| `svhr13` | 3: `gsrkbomb` | `animation:cr_fire_2` | 1.61 -0.27 1.48 | none | accepted-shot path; live validation pending |
| `svhraz` | 2: `gsrkbomb` | `animation:cr_fire_1` | 0.43 -1.30 1.36 | none | accepted-shot path; live validation pending |
| `svhraz` | 3: `gsrkbomb` | `animation:cr_fire_2` | 1.61 -0.27 1.48 | none | accepted-shot path; live validation pending |
| `svhrmp` | 1: `gtaggun` | `` | pending / omitted | none | native firing producer pending; parent shb11bdc is not a barrel node and the hardpoint is 0.79 m behind its front geometry |
| `svhrmp` | 2: `gsrkbomb` | `animation:cr_fire_1` | 0.43 -1.30 1.36 | none | accepted-shot path; live validation pending |
| `svhrmp` | 3: `gsrkbomb` | `animation:cr_fire_2` | 1.61 -0.27 1.48 | none | accepted-shot path; live validation pending |
| `svlt13` | 1: `gtaggun` | `animation:cr_fire_1` | 0.04 -0.02 -0.00 | none | native firing producer pending |
| `svlt13` | 3: `gsandbag` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svltnk` | 1: `gtaggun` | `animation:cr_fire_1` | 0.04 -0.02 -0.00 | none | native firing producer pending |
| `svltnk` | 3: `gsandbag` | `animation:cr_fire_1` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svmine` | 1: `gbetmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svrckt` | 1: `gshadow` | `animation:cr_fire_1` | -0.07 -0.16 0.11 | none | native firing producer pending |
| `svrckt` | 2: `gsandbag` | `animation:cr_fire_2` | pending / omitted | none | accepted-shot path; live validation pending; anchoring device |
| `svrckt` | 3: `gmdmgun` | `` | pending / omitted | none | native firing producer pending; parent srt11bda is not a barrel node and the hardpoint is 0.74 m ahead of its front geometry |
| `svrckt` | 4: `gbetmin` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svsav` | 1: `gbolt` | `` | pending / omitted | none | accepted-shot path; live validation pending; parent ssv11bda is not a barrel node and the hardpoint is 17.29 m ahead of its front geometry |
| `svsav` | 2: `gwasp` | `` | pending / omitted | none | native firing producer pending; mine deployment |
| `svtank` | 1: `gsatstab` | `animation:cr_fire_1` | 0.04 -0.00 -0.00 | none | accepted-shot path; live validation pending |
| `svtank` | 2: `gminisov` | `` | -0.04 -0.00 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtank` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtanka` | 1: `gsatstab` | `animation:cr_fire_1` | 0.04 -0.00 -0.00 | none | accepted-shot path; live validation pending |
| `svtanka` | 2: `gminisov` | `` | -0.04 -0.00 -0.00 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtanka` | 4: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtas8` | 1: `gatstab` | `animation:cr_fire_1` | 0.04 -0.00 -0.00 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtas8` | 2: `gflashgn` | `animation:cr_fire_1` | -0.04 -0.00 -0.00 | none | native firing producer pending |
| `svtas8` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtas8` | 4: `gnavdrop` | `` | pending / omitted | none | native firing producer pending; navigation beacon deployment |
| `svtk13` | 1: `gspstab` | `animation:cr_fire_1` | 0.04 -0.00 -0.00 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtk13` | 2: `gflashgn` | `animation:cr_fire_1` | -0.04 -0.00 -0.00 | none | native firing producer pending |
| `svtk13` | 3: `gquake` | `` | pending / omitted | none | accepted-shot path; live validation pending; ground-contact seismic emitter |
| `svtk13` | 4: `gnavdrop` | `` | pending / omitted | none | native firing producer pending; navigation beacon deployment |
| `svtnk7` | 1: `ga7stab` | `animation:cr_fire_1` | 0.04 -0.00 -0.00 | medium | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtump` | 1: `gtmssv15` | `animation:cr_fire_1` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtump` | 2: `gtmssv15` | `animation:cr_fire_2` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svtump` | 3: `gtmssv15` | `animation:cr_fire_3` | -0.00 0.01 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturr` | 1: `gtmssv3` | `animation:cr_fire_1` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturr` | 2: `gtmssv3` | `animation:cr_fire_2` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturr` | 3: `gtmssv3` | `animation:cr_fire_3` | -0.00 0.01 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturra` | 1: `gspssv3` | `animation:cr_fire_1` | -0.00 -0.00 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturra` | 2: `gspssv3` | `animation:cr_fire_2` | -0.00 -0.00 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturra` | 3: `gspssv3` | `animation:cr_fire_3` | -0.00 0.01 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrb` | 1: `gspssv3` | `animation:cr_fire_1` | -0.00 -0.00 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrb` | 2: `gspssv3` | `animation:cr_fire_2` | -0.00 -0.00 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrb` | 3: `gspssv3` | `animation:cr_fire_3` | -0.00 0.01 0.07 | large | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrc` | 1: `gmgasv3` | `animation:cr_fire_1` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrc` | 2: `gmgasv3` | `animation:cr_fire_2` | -0.00 -0.00 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svturrc` | 3: `gmgasv3` | `animation:cr_fire_3` | -0.00 0.01 0.07 | small | accepted-shot path; live validation pending; fitted outboard port; companion native runtime required |
| `svwalk` | 1: `gblast` | `animation:cr_fire_1` | 0.21 -0.65 0.47 | none | accepted-shot path; live validation pending |
| `svwalk` | 2: `gblast` | `animation:cr_fire_2` | -0.10 -0.73 0.66 | none | accepted-shot path; live validation pending |
| `svwalk` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
| `svwalka` | 1: `gblast` | `animation:cr_fire_1` | 0.21 -0.65 0.47 | none | accepted-shot path; live validation pending |
| `svwalka` | 2: `gblast` | `animation:cr_fire_2` | -0.10 -0.73 0.66 | none | accepted-shot path; live validation pending |
| `svwalka` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
| `svwamp` | 1: `gblast` | `animation:cr_fire_1` | 0.21 -0.65 0.47 | none | accepted-shot path; live validation pending |
| `svwamp` | 3: `gpopgun` | `` | pending / omitted | none | native firing producer pending; parent svw11sup is not a barrel node and has no geometry around the hardpoint |
