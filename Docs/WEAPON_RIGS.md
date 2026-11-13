# Requested CR weapon model edits

Authored source and exported assets, 2026-11-04. **27 model families; not deployed or qualified in native gameplay.**

[Exported model gallery](../References/WeaponRigs/review/index.html) · [Full ODF/slot coverage](COMBAT_WEAPON_EFFECTS.md) · [Companion native PR 698](https://github.com/GrizzlyOne95/Battlezone98Redux_Shim/pull/698)

## Implemented model edits

Gun regions retain source surfaces, materials and UVs. New moving boundaries are capped, with reverse caps closing the fixed receiver cuts. Helpers remain children of each original geometry driver, preserving aiming, arm, deployment and visibility relationships. Only helpers receive new tracks; existing bind poses and animation tracks are retained.

| Model | Model edit | Rigged cockpit channels |
|---|---|---|
| `avfigh` | Paired visible side-rail gun tips; fixed nose armor, hull and mounts. | 0 / 2 |
| `avltnk` | Small upper gun plus launcher bell; retain the separate aiming drivers. | 1 / 2 |
| `avrckt` | Paired forward launcher outlet sections; fixed launcher housings. | 0 / 2 |
| `avtest` | Two existing gun assemblies receive separate helper clips. | No cockpit gun copy |
| `avwalk` | Left and right forward gun sections; retain arm and aiming motion. | 2 / 2 |
| `bvltnk` | Small upper gun plus launcher bell, using the Black Dog source geometry. | 1 / 2 |
| `bvraz` | Paired visible side-rail gun tips; mirrored outward casing paths. | 0 / 2 |
| `bvrckt` | Paired launcher outlet sections; cockpit cabin stays fixed. | In-mesh cabin / no separate gun copy |
| `bvrdev` | Forward gun tip and secondary launcher outlet; preserve the existing atlas. | 0 / 1 |
| `bvwalk` | Independent left/right gun sections beneath their original arm drivers. | 2 / 2 |
| `cblasr` | Emitter tip split from tower; restore missing native aiming hierarchy in the rendered rig. | Building; no cockpit gun copy |
| `cvartl` | Four forward tube sections with separate clips; existing single equipped hardpoint selects its own channel. | In-mesh cabin / no separate gun copy |
| `cvfigh` | Spin the full exposed minigun barrel clusters and retaining rings about each bore; rear receivers, mounts and wings stay fixed. | 2 / 2 |
| `cvhraz` | Paired forward launcher aperture sections; launcher bodies stay fixed. | 0 / 2 |
| `cvhtnk` | Independent paired cannon sections; corresponding cockpit gun copies use the same clip names. | 2 / 2 |
| `cvltnk` | Forward cannon section, shared by cannon/launcher hardpoint aliases. | 1 / 1 |
| `cvrckt` | Paired forward launcher sections and the visible cockpit copies. | 2 / 2 |
| `cvtnk` | Primary cannon and secondary gun tip; the art-fitted cockpit primary gun has its own matching helper. | 1 / 2 |
| `cvturr` | Four separate barrels, four clips, four equipped slots; all four cockpit copies are rigged. | 4 / 4 |
| `svartl` | The equipped GM1 tube recoils independently; the other visible tubes remain fixed. | 1 / 1 |
| `svfigh` | Paired forward gun aperture sections; apply the recorded cockpit fitting transform to the copied gun regions. | 2 / 2 |
| `svhraz` | Two large round forward apertures, selected by disconnected source component before cutting; fixed housing. | 0 / 2 |
| `svltnk` | Forward cannon section with the cannon/launcher alias bound to the same clip. | 1 / 1 |
| `svrckt` | Paired forward launcher outlet sections; cockpit cabin stays fixed. | In-mesh cabin / no separate gun copy |
| `svtank` | Primary cannon and secondary tip; preserve the art-fitted cockpit primary gun and source UVs. | 1 / 1 |
| `svturr` | Three gun sections (GC1-GC3); restore native alias parents while preserving existing world bind poses. | 0 / 3 |
| `svwalk` | Paired groups of small forward head-aperture sections; retain the original head driver. | 0 / 2 |

A zero cockpit count means that resource contains no selected gun surface; the cabin, nose or frame is not moved just to create recoil. In-mesh rocket/artillery cockpits contain cabin/glass surfaces rather than duplicate guns. Guns outside the forward cockpit FOV still receive tracks when they are present in the resource.

`svsav` is excluded. `svmine` deploys utility ordnance and has no firearm barrel to split. ODF aliases sharing these models receive their actual equipped-hardpoint bindings without changing their loadouts.

## Remaining mesh additions proposed

The following secondary mounts have no independently selected visible barrel in this pass. They are not counted as working recoil. The full slot report also distinguishes utility weapons and unsupported native firing producers.

| ODF / mount | Remaining model proposal |
|---|---|
| `avwamp` / GM1 Splinter | Add a closed short mortar insert at the top/head mount; retain native aiming and include it in the cockpit only if actually visible. |
| `svfi12`, `svdemo` / GR1 centerline | Add a closed centerline emitter/barrel insert between the existing scout guns. The ballistic variant already has a fitted outward casing port; the existing side guns are not moved on its behalf. |
| `svhrmp` / GC1 tagger | Add a small closed auxiliary emitter at the existing marker, separate from the two bomber nose apertures. |
| `cvrckt` / GM1 MDM | Separate the lower launcher outlet from the upper rocket outlet, with closed receiver and moving caps. Native detonator producer support remains pending. |
| `svrckt` / GM1 MDM | Add a closed mortar outlet at the raised centerline mount; do not recoil the whole launcher body. Native detonator producer support remains pending. |
| Scout GR1 guided-rocket variants | A centerline launcher insert is needed where there is no visible tube; qualify the guided firing producer before calling this working recoil. |

Mine, popper, flare, camera and field-device mounts have no firearm barrel to move. Their lack of a recoil binding is intentional. Their per-weapon effect/producer decisions remain in the slot report.

## Flash and casing placement

Flash offsets are fitted to the exported moving-piece fronts in the native hardpoint-parent frame. Ballistic slots receive fitted local casing offsets and directions. Each port is outside the full world hull with at least 0.25 m surface clearance; the outward ray and eight jitter-cone corner rays clear the hull in the authored rest pose. Paired scout ports point away from the centerline in opposite directions. Energy, rocket and utility weapons retain their no-brass decisions.

All ballistic slots on the requested model families have fitted casing offsets/directions, including the centerline `svfi12` variant that has no visible recoil barrel. Offsets are a static geometry fit. Aiming, recoil, vehicle motion, casing collision and cockpit emission still require native acceptance. The new spin/port keys require OpenShim PR 698, which `Bin/openshim.dll` now includes.

## Evidence and remaining work

- `Test-WeaponRigs.py`: six final-asset contracts pass for requested coverage, exported hashes, finite geometry, rigid helper ownership, closed moving surfaces, original bind poses/clips, four-barrel/spin counterparts, port clearance and the reviewed actual gun regions.
- Weapon/flash/casing and combat-presentation suites: fifteen tests pass; all 132 armed ODF gameplay baselines remain unchanged.
- Original cockpit/art suites validate their pinned pre-rig stage through `weaponrigs.base_asset_path`; final runtime files are checked separately by `Test-WeaponRigs.py`. Twelve related art suites pass. The existing `Test-TankCockpits.py` fails on the unchanged `avtank_cockpit.mesh` receipt: current/base SHA-256 `29e82cd602926a10af03c4844bf91d5d697a8afb4d917283104dc91f8977ffc9`, receipt expects `9868c0b465eda741fd5d0061823c4e90e680201441ed98aae7ff00b319035205`.
- Repository invariants pass. Shipping membership adds 49 helper skeletons, with no removals. Preview gallery covers all 27 exported world models and 22 separate cockpit resources, including fired rear/underside views with backface culling. Grey is fixed hardware; colors identify firing channels. These are diagnostic Blender renders, not textured native captures.
- Companion OpenShim builds in Release, passes 172 host tests, and passes the exact executable static hook qualification. Neither that binary nor the content has been deployed or live tested.
- Shared-codec gap: the original `bvwalk.mesh` has a precomputed Ogre edge-list chunk. The shared writer omits it after topology changes, avoiding stale indices. Before accepting native shadows, rebuild that derived data with supported Ogre tooling or establish that the native renderer regenerates it. The other edited source meshes have no omitted top-level derived chunks.
- Native acceptance must check firing/recovery and sustained spin; all four turret barrels; turret pitch/deploy and arm motion; cockpit copies; flash at rest/kick; outboard brass under vehicle motion; repeated/simultaneous shots, swaps and reloads. Other firing producer gaps remain listed in the full slot report.
- The broader CR report still lists model families outside this requested edit set. `avartla` references the missing weapon `gpopguna`; no gameplay substitution was made.

## Rebuild

The immutable source revision is recorded in `References/WeaponRigs/models.json`. Builders read pre-rig tracked inputs from that Git revision; keep repository history available. Stock fallbacks require the local retail assets. Region bounds and cockpit fitting overrides are authoring data, not runtime heuristics.

```powershell
python Tools/CockpitsAndRigs/Build-WeaponRigs.py
python Tools/CockpitsAndRigs/Build-WeaponRigs.py --sync
python Tools/Weapons/Build-WeaponFlashes.py --measure
python Tools/Weapons/Build-CombatPresentation.py
python Tools/CockpitsAndRigs/Test-WeaponRigs.py
```

`--init` is one-time configuration creation and refuses to overwrite reviewed regions. For previews, run `Tools/CockpitsAndRigs/Render-WeaponRigs.py` through background Blender. The renderer preserves eye position and uses the native VDF local POV basis, a 64 degree vertical FOV and 16:9 aspect; the down view pitches 25 degrees from that basis.
