# Five combat cockpit prototypes

Owner revision: **combat units first**. Tugs and scavengers were removed from
this workstream before implementation. Based on the fleet review, these five
are the next priority after the accepted Red Devil/scout/tank/bomber chain:

| Unit | Why this one | New design |
| --- | --- | --- |
| `cvturr` CRA turret | Sparse, heavy cage; little role-specific instrumentation | Low dual fire-control desks and dropped selector, open center, original paired-gun pod fronts visible at the lower corners |
| `svfigh` CCA fighter / Flanker | Frame-heavy view with sparse small controls; little connection to the twin-gun fuselage | Compact faceted canopy, cream mechanical instrument bank, side service equipment, original gun/nose module beyond the sill |
| `svltnk` CCA light tank | Large intersecting diagonals and broad flat dash | Armored asymmetric control stations, low open aiming area, original front glacis and side-mounted cannon |
| `avhraz` NSDF bomber | Very sparse narrow tapered pit, shared material/layout with Black Dog; weak exterior connection | Tall tapered bomber canopy, low split desks and service keel, cyan/petrol equipment, small original bow cue |
| `bvhraz` Black Dog bomber | Same generic shared cockpit finish as NSDF | Same related hull-family design with independent charcoal/red equipment and actual Black Dog exterior paint |

Stack: `agent/fleet-cockpits-next5` from `agent/tank-cockpits` at `6458342d`
(open tank PR #313). All prior cockpit work is retained. These are **offline
art-review prototypes**, not deployed, merged, published, or game-qualified.

## Shape, hardware and vehicle identity

Each cockpit is built against its own actual full POV transform, using the
native VDF GEO-local orientation rule through the shared codecs. All five rest
bases happen to be identity; positions differ and are pinned in the tests.
Stock skeleton bytes, original exterior/fallback meshes, ODFs, VDF/GEOs,
hardpoints, original material files and earlier cockpits are untouched.

The four role layouts are separately authored. Related NSDF/Black Dog bombers
share geometry, not their faction finishes. Their tapered canopy and split
bomb-aiming pit are not copies of the Razor scout. The turret's broad low dual
desks, fighter's compact center bank, and light tank's asymmetric console have
different proportions, frames and hardware placements. Small stock warning
strips preserve the original industrial language without repeating a whole
atlas or putting giant warning textures across every bevel.

New instrument cassettes have closed wedge housings, a recessed face, raised
bezel, capped edging and small physical eight-sided screw caps. Structural
beams and mounting fairings are capped. The connected liner has exactly one
intentional canopy opening and a continuous trim unwrap, with a closed roof,
floor and rear. No generic hologram or large modern dashboard makeover.

Selected exterior pieces keep original UVs, surface geometry and unit scale:
one rigid rotation/translation per recorded piece, normals and tangents
transformed together. No whole-body merge or arbitrary per-triangle stretching.

- CRA turret: two real paired-gun pod fronts, 356 triangles per side. GC nodes
  are only tiny hardpoint markers; the visible guns are in TX pod geometry.
- Flanker: 2,881 triangles of the forward twin-gun/fuselage module, not wings,
  rear body or tail. Its denser Redux surface accounts for the largest budget.
- CCA light tank: front glacis and actual side cannon, 700 triangles total.
  Twenty degenerate source triangles are omitted from the selected prototype
  group; the source is not edited.
- Each bomber: 705 original bow triangles, fitted above the sill after an
  initial fit proved fully occluded. Kept as a small cue rather than a large
  obstruction in the bomb-aiming window.

The builder saves exact selections, transforms and source hashes. These
art-directed exterior fragments are bound to the stable cockpit shell; this
does **not** claim live gun recoil, turret servo, deployment or muzzle-position
equivalence. In particular, `cvturr` rest renders are not an operating-pose
test. Its complete original skeleton/hierarchy is unchanged, but native
aim/deploy visibility must be reviewed before deployment.

## Faction textures and provenance

Imagegen skill used in **built-in tool mode** for one new stock-inspired CCA
hardware atlas. The input stock sheet was a hardware-style reference, not an
edit target. The returned master is 1,254 square (not the requested ideal
2,048); deliberate charts are repacked into a shared 1,024-square BC1/full-mip
diffuse/emissive pair. Do not describe this as native 2K art.

- Saved selected master: `cca/atlas-master.png`.
- Exact final prompt/mode: `cca/prompt.json`.
- Stock style reference: `cca/source-reference.png`.
- Physical-lens mask: `cca/optical-mask.png`; red enamel, toggles, fuse paint,
  wiring and quiet structural swatches are explicitly excluded from emission.
- Runtime shared maps: `crvsmcp_d.dds` / `crvsmcp_e.dds`, warm orange optics.
- Both CCA models use `CRV/CCAMechanicalCockpit`; there are no per-model duplicate
  atlases. Flat normal/shared legacy specular maps are reused.
- NSDF and Black Dog reuse the accepted `References/ScoutCockpits/nsdf` and
  `bdog` masters/prompts and `crvascp_d/e.dds` / `crvbscp_d/e.dds` with their
  physical lens masks. Cyan NSDF, red Black Dog.
- CRA turret uses only the accepted mechanical pilot/ordnance charts in
  `References/CVBomberCockpit/atlas-master.png`, not its large screen. Lime and
  amber lens colors remain. The selected exterior keeps original faction maps.

No shared base material/shader changes. New resources are case-correct.

## Reproduce and review

```powershell
C:/Python314/python.exe Tools/Build-CombatCockpits.py
C:/Python314/python.exe Tools/Test-CombatCockpits.py
C:/Python314/python.exe Tools/Validate-CampaignRepository.py
```

The builder needs the stock asset source (default GOG or explicit `--game`).
The tests use saved rigs and immutable CR source meshes and need no game.
All model I/O uses `Tools/bzmodellibs.py` and shared toolkit serializers; no
hand-rolled binary formats. `build.json` per unit pins outputs, source rig/mesh,
native VDF, POV, charts, source triangle selections, rigid transforms and glass.

308 focused checks pass: compiled hashes, rig/eye identity, source surface/UV
identity, rigid unit-scale transforms, finite orthonormal tangent bases,
nondegenerate geometry, stable-shell skinning, closure, central aim corridor,
one canopy boundary, selected exterior visibility, first-person resource lookup,
planar cassette mounts, physical-lens masks, orange optics, quiet nonemissive paint, BC1/full mip chains,
deliberate chart packing and shipping membership.

Regression tests: tanks 277, scouts 134, CRA bomber 68 checks pass. Repository
invariants pass. Eighteen new shipping members (five meshes/rigs/selectors plus
one shared CCA selector and two maps), zero removals. `-bless` refused 51
pre-existing missing generated payloads in the fresh worktree; documented
membership-only insertion keeps the existing lock sequence and LF, without
deleting or fabricating any missing payload.

Saved `review/` contains same-camera before/after, forward, down and low-light
renders for each unit, plus a five-unit overview. The local gallery also has
left/right, roof, rear, floor and console views. One-sided Blender surfaces,
unchanged native-rest eye and 64-degree vertical FOV, no auto-framing tricks.
The emissive test view is near-dark; the static lamps are artwork, not live
engine telemetry or a native bloom/light demonstration.

Four material batches each including weather; opaque triangle counts: turret
1,780, fighter 3,977, light tank 2,004, each bomber 2,297. These are prototype
budgets, not measured retail draw time or memory qualification.

## Explicit limits

No game launch or install mutation. Native first-person loading, animation,
turret yaw/pitch/deploy, recoil, HUD alignment, cockpit weather/damage glass,
actual material scheme behavior, performance, and all runtime lanes remain
**unverified**: Windows/GOG, Windows/Steam, Linux/Steam/Proton and Linux/GOG
under Wine/Proton. Offline success must not be reported as native qualification.
User art review precedes deployment or broader qualification.
