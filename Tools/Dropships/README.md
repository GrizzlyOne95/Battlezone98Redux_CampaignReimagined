# avdrop tooling location

These scripts live in `Tools/Dropships/` (copied from the former untracked `build/capital_ships/src`).
Generated files are not committed: everything goes to `Local/dropships/{out,tex}` (git-ignored; override the
root with `BZ_DROPSHIPS_LOCAL`). `paths.py` holds the locations. Other environment variables:
`BZ_STOCK_MODELS` (stock Redux `.mesh` folder, used only for the cargo-fit proxies in the `.blend`; skipped when
absent), `BZ_TOOLBOX` (Modding Toolbox checkout, the DDS encoder for `texgen_avstock.py`), `BZ_BLENDER`.
`trim_layout.json` is tracked data (strip layout) read by `shipkit.py`; `texgen.py` rewrites it.
Order: `python texgen_avstock.py`, then `blender -b -P build_dropship.py -- --norender`, then
`blender -b -P build_dropship_sdf.py` (`AVD_NAME=avdropc` for the `avdropc` twin). The BZ98 Blender toolkit
addon (`bz98tools`) must be enabled in Blender. `export_cr.py` and `texgen.py`/the `ccahull` palettes are
unused by the dropship path except `texgen.py` as a library. The shipped `avdropx` is `avdropc` with ANIM index 0
reversed (frames 30 to 0); that step is not in these scripts. The `out/` and `tex/` paths named below mean the
`Local/dropships` ones.

# avdrop — NSDF dropship (prototype blockout)

Source concepts: `BZ1Concept/NSDF_DropShip (1).png` (front) and `(2).png` (front-quarter).
Read as a sky-crane: cockpit fuselage + wing beams + two tall lift nacelles, carried on
four struts plus a centre spine over an underslung octagonal cargo pod. Unseen surfaces
(the ramp, bay interior, landing gear, engine placement) are invented.

Build: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b -P build_dropship.py`
(`-- --norender` skips previews). Outputs in `../out`: `avdrop.mesh` (3 submeshes:
`avdrop_hull`, `avdrop_hullw`, `avdrop_trim`, skinned), `avdrop.skeleton`, `avdrop.material`,
`avdrop.blend`, and these previews: `avdrop_{q34,side,rear,top,low}.png`, `avdrop_cockpit.png`
and `avdrop_cockpit_front.png` (canopy close-ups), `avdrop_flight.png` (gear up, nacelles
tilted, bells gimballed), `avdrop_bayopen.png` (ramp bone lowered, load aboard) and
`avdrop_bayplan.png` (orthographic floor plan with the load).

Paint: the material uses its own `nsdfv` atlas (`nsdfvhull`, `nsdfvhullw`, `nsdfvtrim`,
`_D/_N/_S/_E`), painted by `texgen_avstock.py` in the stock NSDF style (avrecy, avmuf, avslf):
dark teal plate (median about 50, 66, 60 in the stock DDS) subdivided into bevelled panels,
with grilles, recesses, riveted plates, pipes, stencils and hatches placed without overlap,
then weathered (seam AO, streaked grime runs, rust, chipped edges showing bare metal).
Lights are small recessed lamps rather than flat ovals; stars, numbers and chevrons are worn
stencils. The Total Command ISDF dropship and carrier sheets (Steam Workshop
`624970/2911671536/tcai_dds_model`: `ivdropcox00`, `ivcarrcox00`, `ivtankcox00`; their DDS are
DXGI 72 BC1 sRGB, which PIL reads after patching the header format to 71) were used as a
reference for panel density and lamp scale, not copied.
Regenerate with `python texgen_avstock.py`; that writes only `tex/nsdfv*.png` and
`out/nsdfv*.dds` and leaves the `nsdf`/`cca` sets alone. Do not use `to_dds.py` for this: it
reconverts every texture. `export_cr.py`'s TEX map does not list the `nsdfv` textures yet. Add
them before a CR export.

Cockpit (front concept): a stepped, faceted hexagonal canopy at the bow with glowing glass
panes, and a lit brow light bar. On each side there is a slanted framed louvre vent with a
lit frame ring, a brow light plate, a glow lamp and a downward landing flood. The side
running lights are red to port (+X) and white to starboard. A red beacon sits on the
dorsal hump.
The exported mesh is in the rest pose (ramp closed, gear down). The blend also holds the
cargo proxies; these are not exported.
CR re-export: `blender -b --factory-startup ../out/avdrop.blend -P export_cr.py -- avdrop <crname>`
(not run).

## Rig and animation

The hull is one skinned mesh on `avdrop.skeleton`, following the stock Redux convention
(avrecy: one mesh, 8-character bone names, every vertex rigidly weighted 1.0 to one bone).
Bones point +Z with their heads on the real pivots, so a rotation about the bone turns the
part about its hinge.

| Bone | Parent | Moves | Pivot (x, y, z) |
|---|---|---|---|
| `adr11bdy` | — | everything not listed below | origin |
| `adr11lg1`/`lg2` | bdy | port leg (fore/aft): strut + pad | (14, −18 / 16, 3) hip |
| `adr11lg3`/`lg4` | bdy | starboard leg (fore/aft) | (−14, −18 / 16, 3) hip |
| `adr11rmp` | bdy | rear (stern) ramp | (0, 24, 4.5) floor lip |
| `adr11fmp` | bdy | front (bow) ramp, under the cockpit | (0, −23, 4.5) floor lip |
| `adr11nc1`/`nc2` | bdy | port / starboard lift nacelle with its nozzles | (±32, 0, 36) |
| `adr11vt1-3` | nc1 | port lift bells, fore to aft | each bell's top |
| `adr11vt4-6` | nc2 | starboard lift bells | each bell's top |

Sample animations (60 frames, 2.5 s each; every track is keyed, unused ones stay identity):

| Animation | Motion |
|---|---|
| `ramp_open` | both ramps rotate 106.3° about X, outward, until each lip touches the ground |
| `gear_retract` | legs telescope up 2.3 m so the pads tuck under the belly |
| `nacelle_tilt` | nacelles roll 30° about X, vectoring the bells aft for forward flight |
| `vtol_gimbal` | each bell gimbals 15° about X |

In `build_dropship.py`, `part()` declares a bone and its vertex ranges, `rig()` builds the armature
and weights, and `ANIMS` holds the poses. To add a moving part, wrap its geometry in a
`part(...)` range.

The game does **not** play these `.skeleton` clips: Redux animates objects from the `ANIM` chunk
of their VDF/SDF, moving the bone that carries each GEO's name. The clips above are for previews
only. The in-game path is the SDF variant below.

## SDF variant `avdropo` (landed, both ramps open)

`blender -b -P build_dropship_sdf.py` writes `../out/sdf/`: `avdropo.sdf`, 17 `adr11*.geo`,
`avdropo.mesh`/`.skeleton`/`.material`, `avdropo.odf`, `avdropo.blend`.

- Each bone above becomes its own GEO (type 61, collision generated, as the stock hangar `abhang`).
  The SDF header copies abhang's: size 2, type 1, mass 1750, `xbldx1.xdf`.
- ANIM elements, all play-once at 15 fps, copied from abhang's layout: index 0 = frames 0–30
  (ramps open), index 1 = 30 → 0 (closes), index 4 = 0–30. Only the ramps have keys (`RAMPS` in
  `build_dropship_sdf.py`): rotation about X from 0 to ±106.3° (stern +, bow −, both outward),
  **one rotation and one position key on every frame 0–30**, as stock
  moving parts do (`sbwpow`, `abspow`, `avrecy`; `abhang`'s sparse doors are the outlier, don't copy
  them). The other parts hold still. `AVD_RAMP_DEG=45` (or 90) builds a smaller swing for tests.
- **Both ramps open correctly in game (run 22, `out/avdtest_run22/shot_*.png`; stern alone in run 21):**
  each swings outward and lies on the ground with its deck drawn. One tank drives down the stern ramp
  onto the ground (+5.65 m hold floor to ground by about 55 m). The other drives up the bow ramp from
  65 m out and parks in the hold at floor height (+5.65 m). The stern tank is later lost on a ridge
  about 76 m out; that is the test path, not the ship (run 21 launched off the same ridge).
- **Earlier failure (runs 8–20: a slab under the stern plus a small patch on the ground) was an
  inverted face, not the animation.** `shipkit.loft` builds `cap0` and `cap1` from the ring in the same
  order, so one cap of every closed loft is wound inward. Its `_fix_winding` signed-volume test then
  gives position-dependent results: the stern ramp lost its deck (culled once the ramp passes
  vertical, leaving only the roundel and hazard plates), and the bow ramp came out fully reversed
  (sides and trim inward). `build_dropship.py` now runs `bmesh.ops.recalc_face_normals` on each ramp
  loft (shipkit itself is read-only here); `sdf_anim_tools.py faces` shows both ramps clean. The old
  XML-level `flip_ramp_deck()` is gone. Tests at 45° (run 18) and 90° (run 19) had already shown the
  swing sense and pose were right. Other ships' closed lofts may carry the same inward cap.
- **How Redux poses an SDF part (GOG exe):** `FUN_0067e260` binds each part to the skeleton bone
  with the GEO's name, set manually controlled, and stores it at node+0xC8. Each frame
  `FUN_00681a00(node, M)` takes the part's interpolated ANIM matrix (rotation keys are (w,x,y,z);
  position keys are in parent space and equal the GEO's matrix position), converts it with
  `FUN_0081f1e0` (matrix → quaternion), and writes orientation (w, −x, y, z) and position (−px, py, pz).
  That is the SDF→Ogre X mirror, applied on top of the `.skeleton` bind. The object root uses a
  Z mirror instead (`FUN_006802b0`/`FUN_00681610`). Stock skeletons are rooted at `U3DMesh`, ours at
  `adr11bdy`. Both keep model-space vertices and parent-relative bone positions, so that difference
  is harmless.
- Orientation: the legacy SDF/VDF exporter takes Blender **+Y** as the front (the direct `.mesh`
  export takes −Y). The script turns the model 180° about Z before splitting it, so in the SDF the
  bow is at +Y. The stern ramp hinges at (0, −24, 4.5) and trails toward −Y when open; the bow ramp
  hinges at (0, +23, 4.5) and trails toward +Y.
- **Collision.** BZ1 (1.5 decompile) copies each GEO's polygons as walls that follow the animated part,
  but snapshots floor faces (rotated normal y > 0.4) once, when the object is added: `Floor_AddEntity`
  → `CollectObjFloor` → `CollectFloorFaces`, with no later recompute. The ramp is closed (vertical) at
  that moment, so an animated ramp can never be driven on. The build therefore splits each ramp, as BZ2/BZCC's
  condor (`i76building`, `canCollide = 0`, `ownsTerrain = 1`, a static collision mesh stamped into
  the terrain) does:
  - `adr11rpf` (stern) and `adr11fpf` (bow): static 34.6 × 1.05 × 16.8 m slabs posed at the open angle,
    with no keys and no mesh vertices (invisible). Each deck sits 5 cm above its visual ramp and runs
    1 m past the lip into the ground.
  - `adr11rmp`/`adr11fmp`: keep their names, pivots and keys (they drive the visual bones), but their
    GEOs are 0.4 m blocks at the hinge, so the swinging plates have no walls. The closed `avdropc` will
    need real door GEOs.
- **Face planes.** The exporter writes face centres where GEO face records need planes (stock: unit
  Newell normal in file vertex order, inward on closed parts, d = −N·p). `geo_planes.py` rewrites them
  after export (it reproduces the stock `abh11*` doors exactly). Without it nothing on the ship collided.
- ODF class is `repairdepot` (its constructor plays index 0 once), with repair turned off.
- The toolkit's porter writes the skeleton but a flat-colour mesh, because there are no `.map`
  textures. So `avdropo.mesh` is the UV-textured rig export, turned into the porter's frame
  ((x, y, z) → (−x, y, −z)), with its bones remapped by name and linked to `avdropo.skeleton`.
- Checked offline: re-importing the SDF gives the same three ANIM elements and part hierarchy, and
  at frame 30 the ramp lip sits at z 0.06, 39 m behind the hull. The mesh has 14 bones, every
  vertex weighted 1.0, and real UVs. Renders: `out/avdropo_f00.png` (closed) and `avdropo_f30.png` (open).
- **In-game test (GOG, 2026-10-19, `addon\avdtest`):** lcbench terrain; the Lua searches for the flattest
  site (3.6 m height range), builds `avdropo`, and drives two `avtank`s. The ramp anim plays and the model
  faces the right way (`GetFront` points at the bow).
  - The hold floor GEO collides: a tank spawned inside sat at floor height (5.6 m above the base) and drove out.
  - The ramp GEO does **not** collide, in either pose. A tank ordered back into the hold stopped
    on the terrain at 31 m out, 5 m off the centreline, 0.8 m above the base. That point is under the open
    ramp, where the deck is about 2.4 m up. The outbound tank also passed through the closed-ramp position.
    Its descent fits a fall off the floor edge as well as a drive down the ramp.
  - `Goto` into the building footprint ends early (command 0) before it reaches the hold.
  - Camera captures (`out/avdtest_run7/shot_*.png`) show the side, not the ramp.
  - Not yet known: whether this is the animated GEO in general (stock hangar doors are type 61 too) or
    this ramp's collision data. Nothing found plays index 1, so closing still needs an `avdropc` swap.

- Test drive (`lcbench.lua` in the fixture): one tank spawns in the hold and is held with `Stop` each
  frame until the ramp is down, as BZ2's ISDF01 holds its condor cargo. Then each tank is pushed
  along centreline waypoints with `SetVelocity` (7 m/s): one drives out, one drives back in.
  - **Result (runs 11, 13):** both directions work. Out: hold floor at +5.65 m, then a steady descent
    to the ground by 50 m. In: from the ground at 46 m up to the hold floor (+5.6 m) by 23 m, then
    parked in the hold. Before `adr11rpf` (runs 7–9) no tank ever got back in.
  - `Goto` cannot do this (run 10): the pathfinder treats the footprint as blocked. Legs into it end at
    once (command 0), and a tank released inside paths out sideways **through the side wall**. So side
    walls do not stop a unit driving outward from inside (they may be one-sided). A landing scene must
    script the drive.

Planned landing scene (not built): fly the closed `avdrop` with Lua `SetPosition`/`SetTransform`
like CR's Fury transport (`CRMisn16.lua`), swap it for `avdropo` at touchdown, drive units down the
ramps, then swap to `avdropc` and lift off.

Axes (`avdrop` mesh and this README's tables): forward = Blender −Y, up = +Z, ground = z 0, metres.
The `avdropo` SDF is turned 180° (see above).

## Dimensions

| Part | Size (m) |
|---|---|
| Overall | 77.4 W × 53.9 L × 48.4 H (ramp face to ramp face) |
| Cargo pod (outer) | 40.6 W × 47 L × 20.6 H, belly at z 2.7, open at both ends |
| Bay interior | 35 W × 47 L × 16 H, floor at z 4.5, 0.4 m floor chamfers, 3.2 m ceiling chamfers |
| Ramps (bow and stern) | 34.6 W × 16 L × 1.4 thick, each hinged at its floor lip. Open = 106.3° (16.3° slope, lip on the ground) |
| Upper body | 22 W × 46 L, z 32–41, dorsal hump to 44.5 |
| Lift nacelles | 11 W × 25 L × 34 H, centres x ±32, canted out 7°. Each has 3 ventral lift bells and 2 aft nozzles |
| Pod-to-body gap | 9 m: 4 A-frame struts and a centre spine |
| Landing gear | 4 splayed legs with 5 × 7 m pads, plus 2 belly skid rails |

## Cargo fit check

Stock sizes were measured from the GOG `BZ_ASSETS/common/models` meshes:

- **avtank:** 6.33 W × 6.71 L × 2.83 H.
- **avrecy bind pose:** 35.9 W × 35.5 L × 13.4 H. This is the deployed pose: fold-out
  floor and wall wings (`are11bdb/bdc/bdd`) spread to the sides.
  - The core body (`bda/frt/bak` plus the stack) is 16.2 W × 35.5 L × 13.4 H.
  - **Packed envelope used: 18 W × 36 L × 13.4 H.** That is the core plus about 1 m a side
    for the folded wings.
  - This is inferred, not measured. The skeleton's `Take_001` deploy animation does not
    import cleanly through bz98tools, so no packed pose could be sampled.
  - The ODF `collisionRadius = 10` suggests the game treats the packed hull as smaller,
    so this envelope is conservative.

Layout on the 35 × 47 m floor (x across, y fore-aft, bay spans y −23 to +24):

| Load | Centre (x, y) | Footprint | Clearance |
|---|---|---|---|
| Recycler (packed) | (0, −4) | x ±9, y −22 to +14 | 1 m to the bow ramp hinge, 10 m of floor behind it to the stern ramp hinge |
| 4 × avtank | (±13.2, −12) and (±13.2, 0) | x ±(10.0 to 16.4) | 1.0 m to the recycler, 1.1 m to the side walls |

Height: the recycler top is at z 18.1. The ceiling is at 20.5, and the clear half-width at
that height is still 16.7 m (the chamfer starts at z 17.3). Tank tops are at 7.5.

Result: recycler + 4 tanks fit with ≥ 1 m clearance on every side. The side lanes
(y −23 to +24, 47 m) could take 6 tanks per side. The aft 10 m of floor is free for
scavengers or turrets.
