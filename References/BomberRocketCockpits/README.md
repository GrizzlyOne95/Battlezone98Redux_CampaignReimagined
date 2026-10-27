# CCA bomber and CRA rocket cockpit prototypes

Owner's next combat priorities after `cvhtnk`: `svhraz` and `cvrckt`.
Branch `agent/bomber-rocket-cockpits` stacks on CRA connection PR #317 at
`44947a8f`, retaining the accepted fighter sill correction and heavy tank.
Original/fallback full models, ODFs, VDFs, texture atlases, hardpoints and
stock skeleton bytes remain unchanged. No install, game launch or publication.

## CCA bomber: low offset pilot pod

Keep the actual `Shb11POV` at `(2.534184933, 1.170401031, .480317041)`, identity
native-rest basis; stable first-person shell `shb21bdb`, handle 16. This is an
offset pilot pod, not a centered chair behind the full vehicle's main bow.
The old 282-triangle shell is mostly absent/off to one side from this eye;
do not recenter the camera to make the old shell appear plausible.

New short faceted canopy, low broad mechanical instrument desk, asymmetrical
side boxes, dropped selector panel, knee plates, tread ribs and closed liner.
At the owner's request, red structural armor and narrow framing sample this
bomber's own worn exterior atlas, not a cream generic CCA tub. Instrument
inserts retain the accepted cream analog hardware and orange lamp masks.
Structural paint explicitly uses black emission; the exterior maps and all
other CCA cockpits are untouched. No bitmap tinting or new atlas.

The tiny pointed nose cue comes from source body batch 0, bone 2, clipped at
source z>=1.52 and capped. It is deliberately lowered .30 m in the cockpit
copy to avoid a tall cap blocking the glazing; source scale/UVs and the
actual eye remain unchanged. This is an art-directed hood, NOT an exact
native hull fit or a weapon relocation. One original-surface ray survives
the coarse forward/down sample; most visible near hood area is the red
closed mounting/cap, so no claim of extensive source hull visibility.

## CRA rocket tank: split nose

Keep `CDR11POV` at `(0, 2.611823082, -.933486998)`, identity native-rest basis;
stable shell `CDR21BDA`, handle 12. Replace the tall generic red guard rails
and broad striped banks with slim red framing, ochre closed roots, split
mechanical desks, low arming keel and asymmetrical side equipment.
Reuse accepted CRA lime/amber hardware, no new texture sheet.

Original forward prong surfaces remain at native coordinates and unit scale.
Source body batch 0 / bone 0 is sectioned at z>=.55, each abs(x)>=.95 half,
and y<=1.93. The height trim intentionally omits tall shoulder plates beside
the eye; all new planar openings have explicit armor caps. Both source
prongs are visible through the complete cockpit, not merely in a cutaway.
This is a selected lower hull assembly, never the complete vehicle merged in.

## Rebuild and review

```powershell
python Tools/Build-BomberRocketCockpits.py --game <BZR root>
python Tools/Test-BomberRocketCockpits.py
```

Shared model codecs own binary I/O; the existing section helper interpolates
source UVs and caps cuts. The pair-local float32 guard omits only zero-area
cap triangles and remaps tiny UV-degenerate cap faces inside the same quiet
allocation. It does not modify the source faces or shared builders.
Receipts record source hashes, exact eye, source-face provenance, cut planes,
fit matrix, cap handling, compiled glass and output hashes. Weather glass
fits the cabin only; distant prongs do not alter its window projection.

`review/` retains exported/reloaded, one-sided actual-eye renders at 64-degree
vertical FOV / 16:9: forward/down, console, side/down-side, roof, rear, floor,
low-light optics and unchanged full-body POV diagnostic guides. Guides are
explicitly two-sided cutaway/locator evidence, not native visibility proof.
The local gallery is `http://127.0.0.1:8767/bomber-rocket/index.html` while the
maintainer review server runs.

Targeted checks cover source/rig preservation, tangent bases, nondegenerate
faces, chart proportions, compiled UVs, closed roof/rear/floor, open aim,
source-hull visibility, negative fixtures and case-correct resource routing.
195 checks pass. Adjacent regressions: combat-five 497, fighter 71, heavy
tank 106, synthetic section geometry 15. Repeated pair builds are byte-identical;
repository invariants pass. No new texture assets or edits to accepted units.
Six new shipping members: two meshes, two skeletons and two materials.
Bless refused 51 absent pre-existing generated payloads without changing the
lock; membership-only additions preserve every existing entry/order and LF.
No removals, placeholders, texture copies or installed-game changes.

Native first-person selection/drawing, damage/weather/HUD interaction, motion,
firing/flash appearance, performance and GOG/Steam/Proton/Wine runtime behavior
remain UNVERIFIED. The rendered rest-pose previews do not qualify these lanes.
The untouched stock GEO drivers and launch hardpoints remain authoritative.

Remaining priority queue: CRA light tank `cvltnk`, CRA/CCA walkers `cvwalk` /
`svwalk`, then howitzers and NSDF/Black Dog turrets. Not changed in this pass.
