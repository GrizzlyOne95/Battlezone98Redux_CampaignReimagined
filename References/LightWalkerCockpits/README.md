# CRA light tank and CRA/CCA walker cockpit prototypes

Owner's next combat priorities: `cvltnk`, then `cvwalk` / `svwalk`.
Branch `agent/cra-light-walkers` stacks on bomber/rocket PR #318 at `ff8a3ed6`,
retaining all earlier accepted cockpit passes. Offline art review only:
no installation, game launch, deployment, merge or publication.

## CRA light tank

Keep actual `CNA11POV`, handle 6, at `(0, 1.856879950, .582378983)`, identity
native-rest basis; shell `CNA21BDA`, handle 10. Replace the broad hazard strips
and tiny central controls with a compact low split station, asymmetrical side
equipment, ochre armor, wine-red framing and accepted lime/amber instruments.
Closed knee plates, tread ribs, liner, roof and rear service panel complete it.

Reuse the original sloping bow and overhead cannon, NOT a full body merge.
Both are separate welded islands within source body batch 0, all on bone 0.
The bow is selected from island seed face 1291, source z>=2.2; the cannon
from seed face 0, source z>=1.12. All new planar cuts have explicit backs.
The original hull is not closed everywhere, so more rearward bow cuts fail
closed rather than silently accepting open contours. No source translation,
scaling, hardpoint or exterior/ODF/VDF edits. The cannon is connected to a
closed overhead housing, not a cropped floating muzzle. A low bridge leaves
original bow surfaces visible above the coaming. Cannon backs are quiet dark
metal; bow backs use red structural paint. No emissive cut faces.

## CRA and CCA walkers

Retain the existing fixed-table `_c.mesh` selection and byte-exact fixed
`_c.skeleton` rigs. `cvw11POV` / `svw11POV` are handle 12, stable shells
`cvw21hed` / `svw21hed` handle 13, beneath native head handle 4. Camera and
original native walk/deploy data, including the previous twitch fixes, stay
unchanged. Actual rest eyes are approximately `(-.16455, 8.04261, 5.09502)`;
receipt matrices retain the full native-parent basis, not an assumed identity.

The old cockpit crosses the native-rest view at a steep tilt. Author the new
low mechanical stations and head enclosure around the unchanged native eye;
inverse-compensate each vertex into its ORIGINAL driver's bind coordinates.
That prevents native GEO-local rotations from tilting the new cabin twice.
The exact same compensation applies to compiled weather glass. No hierarchy,
POV, animation or native API fix is introduced here. The compensated preview
does NOT independently qualify actual engine animation behavior.

Use the complete closed main helmet island (seed face 7192), not the separate
open muzzle/equipment islands. Keep two small native-position head sections:
chin at eye-relative z>=1.05, y<=-.56; brow at z>=.90, y>=.32. A closed visor
bridge and side posts join the brow to the roof; the chin backs are beyond
the instrument banks, not blocking them. Explicit cut backs become the inner
armor faces. Source outer skin is mostly back-facing from the pilot: coarse
forward/down source-only visibility is brow 1 sample, chin 0, per walker.
Do not describe cap visibility as extensive original exterior visibility.
The original head shape supplies the outline; the new closed interior faces
make that shape usable from inside. No two-sided outer-skin workaround.

CRA retains ochre/red hardware with lime/amber lenses; CCA retains cream/red
mechanical controls with warm orange lamps. Their shared head-family geometry
does not imply a shared faction material. Cut backs explicitly use black
emission. No new bitmap, atlas copy or repaint of the full vehicles.
Arm/shoulder/leg geometry is not copied or repositioned in this head-focused
pass. This work does not claim forward cannon peeks or shot/flash alignment.

## Build and evidence

```powershell
python Tools/Build-LightWalkerCockpits.py --game <BZR root>
python Tools/Test-LightWalkerCockpits.py
```

Shared model codecs own every mesh/skeleton/VDF read and write. Reuse existing
hardware, section, mapped-tangent and cap-stability helpers. Per-unit references
retain immutable original cockpit meshes, original full/cockpit rigs and small
pre-pose source-section fixtures. Receipts pin all inputs/outputs, native VDF
hashes, source face provenance, cut planes, driver assignments and exact camera.
These reference fixtures are not shipping resources. Rebuilds never select a
generated `_c.mesh` as source geometry; only the unchanged rig is reused.

355 targeted checks pass: rig/native-source pins, shader bases, nondegenerate
faces, compiled native-rest source/UV reproduction, instrument proportions and
visibility, roof/rear/floor closure, open forward aim, actual source versus cap
visibility, resource routing, a missing-compensation negative fixture and
synthetic +/-15-degree head pitch. Synthetic head motion verifies the relative
geometry only, not native playback, locomotion, aiming or branch draw policy.
The tank samples retain 57 original bow and 207 original cannon hits.
Adjacent regressions pass: NSDF/Black Dog walkers 262, combat-five 497,
bomber/rocket pair 195. Repeated builds preserve runtime resources, source
fixtures and receipts byte-for-byte; repository invariants pass.

`review/` contains one-sided exported/reloaded actual-eye forward/down, console,
side/down-side, roof/rear/floor and low-light optics, before/after comparisons,
camera contracts and original third-person POV guides. Review baseline:
64-degree vertical FOV / 16:9. Original full-body guides are explicitly
two-sided/cutaway diagnostics, not proof of native first-person visibility.
Local gallery: `http://127.0.0.1:8767/light-walkers/index.html` while served.

Five new shipping members: light-tank mesh/rig plus three material files.
Existing walker `_c.mesh` entries stay in place. Bless refused 51 absent
pre-existing generated payloads without modifying the lock; membership-only
additions preserve every old member and ordering, with LF formatting.
No removals, stand-ins, new textures, shaders or native binaries.

Native model loading/branch hiding, head/walk/deploy/aim behavior, firing/flash,
HUD/weather/damage, performance and GOG/Steam/Proton/Wine runtime lanes remain
UNVERIFIED. The earlier existing native data fixes are preserved, not requalified
by this art pass. Offline approval must not be treated as deployment approval.

Remaining combat queue: howitzers and NSDF/Black Dog turrets. Utility craft
remain lower priority and are not changed here.
