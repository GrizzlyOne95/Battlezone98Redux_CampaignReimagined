# NSDF / Black Dog walker cockpit prototype

Owner direction: add appropriate walker body/gun presence, keep the cannons
just barely visible looking forward, and make their appearance agree with the
shots. Based on `agent/light-tank-cockpits` at `56407910` (PR #315).
**Offline art review only. No game deployment or launch.**

## Interior and actual camera

Broad, low split mechanical control desks and side equipment, treaded foot
trays, closed rear/floor/roof, narrow swept framing and an open aiming area.
Use the already accepted NSDF petrol/cyan and Black Dog charcoal/red scout
hardware sheets. No new bitmap textures or duplicate atlases. Instrument
inserts are rectangular and preserve pre-repack artwork proportions.

The existing `AGe11POV` is handle 11, an independent root at
`(0.0650999993, 9.1999998093, -0.2865999937)`, native/rest basis identity.
It is low at gun-arm height, not inside the exterior's high head. The shell
is independent `age21hed`, handle 12. The torso is largely behind/above this
view: do not merge the main model into the cockpit.

These walkers use the engine's fixed first-person table. Replace the existing
`Assets/ModelFixes/avwalk_c.mesh` / `bvwalk_c.mesh`; an additional namespaced
`*_cockpit.mesh` would be ignored. Preserve the existing `_c.skeleton` resource
and original rig bytes, all 26 bones, and `Take_001` / 15 tracks. Fixtures are
saved for game-independent testing, not added to runtime shipping.

## Source arms and firing-ray fit

Copy all 2,824 nondegenerate triangles of the original four complete arm
components: `age11lsh`, `age11rsh`, `age11tx1`, `age11tx2`. Preserve UVs,
connectivity, shape and unit scale. Use original faction exterior D/N/S/E maps.
Each component retains its own driver, mapped by name (handles 2/5/6/3), not
bound to the stationary cockpit. No hardpoint-marker cubes, legs or head.
Back the two tiny 12-edge upper socket openings (20 new triangles). The three
front bore cavities on each forearm remain intentionally open.

An early sideways `.8 m` / forward `.2 m` art fit was rejected after the owner
asked about projectile alignment. The final fit uses the **native VDF firing
rays**, not a lateral shift and not the different Ogre bind hardpoint positions.
Read the complete band-0 hierarchy with the shared legacy codecs, mirror X into
Ogre space, and rigidly fit each upper/forearm pair in native-rest preview space:

| Mount | Rest shot origin (Ogre model space) | Rest direction |
| --- | --- | --- |
| GC1 | `(4.87191, 9.98004, 2.19599)` | `(-.002000, -.000004, .999998)` |
| GC2 | `(-4.88955, 9.98005, 2.19595)` | `(.000000, -.000004, 1)` |

The main 16-edge bore axis goes through that ray. Its opening sits **1.60 m
along** the ray from the unchanged native origin. This is an explicit axial
viewmodel fit, not an assertion that the projectile/flash origin equals the
rendered lip. The shot origins and main openings are outside the forward view;
only inboard casing edges peek in. In this rest setup, a projectile along the
native ray first enters the forward frustum beyond the model's muzzle plane,
not beside the housing. No native hardpoints, ODF weapon parameters, firing
direction, convergence, recoil configuration or full exterior models change.

At 64-degree vertical FOV, 16:9, one-sided 320x180 sampling, the visible cannon
assemblies occupy 620 pixels (1.0764%) for each faction, confined to the outer
10% columns. Both sides are present; central yaw +/-10 and pitch 0..10 degrees
are clear. This is a specified rest-view sample, not universal gameplay proof.

## Qualification limits

The offline renderer explicitly includes all four authored submeshes. Native
first-person paths can hide `*11*` branches; their visibility here is **not**
evidence that the game will draw those arms. Preserved driver names also do
not prove native locomotion/servo synchronization. Synthetic +/-12-degree
forearm-pitch renders only check that the arms are independently skinned and
the cockpit stays still; they are not playback of native walk/recoil clips.

The ray fit is measured at rest. Runtime aim/animation, flash location (the
unchanged origin is behind the viewmodel lip), shot emergence during side
looks, visibility under native branch hiding, weather/HUD, depth order,
performance and all four platform lanes remain unverified: Windows/GOG,
Windows/Steam, Linux/Steam/Proton, Linux/GOG/Wine or Proton. Do not deploy or
call this shot-aligned in gameplay before a live firing/turning/walking test.

## Rebuild and checks

```powershell
python Tools/Build-WalkerCockpits.py
python Tools/Test-WalkerCockpits.py
python Tools/Validate-CampaignRepository.py
```

Build needs the stock GOG source or `--game` path; it never modifies it.
All mesh/rig and legacy reads/writes use shared `bzmodellibs` codecs. Tests
need no game: 262 focused checks cover source-arm and original-rig fixtures, native chain records,
hash receipts, compiled bore alignment, forward emergence/frustum sampling,
shape/skinning identity, closed shell, normals/tangents and actual instrument
UV corners are checked. Saved `review/` renders are durable evidence; ignored
`Local/Walkers/` contains the local Blender renderer and gallery assembly.
Repeat builds produce identical runtime resources and receipts. Regression
suites pass: light tanks 272, combat-five 497, scout pair 134; repository
invariants pass. None of these checks qualifies native rendering or firing.

5,432 opaque triangles per cockpit: 2,588 interior, 2,824 original arms, 20
socket backs; four material batches including fitted weather glass. Two new
shipping members (material selectors) only; both meshes already shipped.
`-bless` refused 51 absent generated payloads in this fresh worktree without
modifying the lock. Membership-only insertion follows the knowledge-base
fallback, preserving old membership/order and LF, with no fabricated files
or removals. No installed files, VDFs, source exterior meshes or rigs changed.
