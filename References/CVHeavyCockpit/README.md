# CRA heavy-tank cockpit: offline prototype

Owner approved the CRA fighter wing/gun correction followed by `cvhtnk`, the
next high-priority stock mismatch. This pass stacks on walker PR #316 at
`b3f5f310`; branch `agent/cra-cockpit-connections`. No install or game launch.

## Vehicle-specific shape

Replace the sparse 100-triangle stock interior with a low armored command
station: a broad recessed fire-control bank, separate pilot/ordnance side
stations, dropped service panel, ribbed foot trays, swept wine-red/ochre armor
framing and a closed rear, roof and lower liner. Instruments have planar
rectangular inserts, retaining their original artwork proportions rather than
stretching dial textures over tapered faces. Existing CRA bomber mechanical
charts and lime/amber optical maps are reused. No new texture atlas.

The camera is the actual `CEM11POV`, handle 13, at
`(0, 2.7389559746, 0.0980949998)` with identity native/rest basis. The stable
shell is `CEM21BDA`, handle 16. `cvhtnk_cockpit.mesh` and a byte-identical stock
rig copy use the existing separate-cockpit resource lookup. Every native POV,
hardpoint, exterior mesh, ODF, material source and VDF remains unchanged.

## Recognizable exterior, not a body merge

- Bow: retain the actual forward shell section at native coordinates, with
  `z >= 1.95` and `y <= 2.30`. Clip source triangles and interpolate their
  existing UVs/normals/tangents; explicitly cap newly exposed cut contours.
  The bow is a small lower sightline cue, not a large shelf forced into view.
- Side guns: retain the two **complete** original 1,735-triangle gun-pod
  assemblies, including their armored rear housings. The first barrel-only
  crop was rejected during review because it looked detached. No rescale,
  sideways fit or muzzle movement. Pods retain native bones 1/3 instead of
  being frozen onto the shell; bow and its backs follow the stable shell.
- Exclude marker cubes and the main rear body. Preserve all source texture
  relationships. Weather glass fits the cockpit interior only; the distant
  pods do not inflate it. Recompute the exported AABB after appending them.

Opaque budget: 7,614 triangles (2,300 interior, 5,132 source exterior section,
182 new bow backs), plus fitted weather glass; four batches. This is an asset
count, not measured native frame cost.

At the unchanged eye, one-sided ray tests find visible source geometry on
both sides (125 sampled rays each) and over the lower bow (28 rays). Central
yaw +/-10 degrees and pitch 0..10 degrees remain clear. These angular samples
are not universal in-game visibility or screen-area claims. Offline review
uses 64-degree vertical FOV, 16:9 and actual exported/reloaded resources.

## Build, review and limits

```powershell
python Tools/Build-CVHeavyCockpit.py
python Tools/Test-CVHeavyCockpit.py
python Tools/Test-CockpitSections.py
python Tools/Test-CVFighterCockpit.py
python Tools/Validate-CampaignRepository.py
```

Build accepts `--game` and reads stock source without modifying it. Shared
`bzmodellibs` codecs own all binary mesh/rig/native I/O; `cockpitsections.py`
only clips in-memory surface arrays. Its synthetic box fixture checks two
successive caps for watertightness, exact area, attribute interpolation and
open-contour rejection. Heavy-tank tests require no installed game: output
and source pins, exact camera, assembly provenance, cap reproduction, original
pod geometry, skinning, closure, aim/exterior visibility and compiled chart
corners. Saved review images live in `References/CRACockpitConnections/review`.
The heavy-tank suite passes 106 checks; fighter 71 and synthetic section
geometry 15. Earlier combat-five (497), main tanks (277) and Red Devil (55)
regressions pass. Repeat builds produce identical runtime resources/receipts.

Three new shipping members: mesh, rig copy and material selector; zero new
textures. Bless safely refused the same 51 absent generated payloads in this
fresh worktree, leaving the lock unchanged. Membership-only fallback follows
the knowledge base: retain old ordering/membership and LF; no removals or
fabricated stand-ins. No deployment follows from membership alone.

**Unverified:** native first-person visibility of side-pod `*11*` branches,
pose/wing/pod motion and synchronization, recoil, projectile/flash appearance,
HUD/weather/damage integration, depth behavior and performance. The renderer
explicitly includes all authored opaque batches; it is not proof of the native
bone-hiding policy. Static native positions do not establish runtime shot
alignment. Windows/GOG, Windows/Steam, Linux/Steam/Proton and Linux/GOG under
Wine/Proton remain untested. Offline art approval is not runtime qualification.
