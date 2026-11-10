# Thruster housings ("flame nacelle emitters")

Hover craft draw their engine flame from a point under each nacelle, but most stock wings
have no engine there, so the flame comes out of bare wing. `Tools/Build-NacelleJets.py`
adds a small faction-coloured thruster housing at each emit point so the flame leaves a
nozzle. First unit: the NSDF scout (`avfigh`). Total Command wing engines were looked at
for proportion only; no Total Command asset is used.

## Where the flame comes from

Line numbers are in the BZ 1.5 decompile, `Battlezone_Source\BZ1\1.5\all_decompiled.c`.

- Stock `avfigh.vdf` has no class 75 (flame emitter) or 76 (smoke) part, only the two
  class 67 nacelles `ARA11NRL` and `ARA11NRR` (read with the toolkit VDF reader).
- When a hover craft has class 0x43 nacelles and no class 0x4B part (193458-193473), the
  engine creates a flame emitter under each nacelle (193477-193478).
- Its transform is right (1,0,0), up (0,0,1), front (0,-1,0) (193479-193488), placed at the
  nacelle's up axis times the nacelle bounding box's lowest y (193476, 193489-193491). So
  the emit point is the bottom of the nacelle box below the nacelle pivot, and the flame
  runs along the nacelle's local -Y, pitching with the nacelle (193659-193678).
- The flame draws only above 10% throttle (193719). Scale is throttle x 0.2 (193771,
  193821) x a random 1.0-1.1 (193780); `EngineFlame::AddFlame` (255440) makes the length
  flameLength x scale x 2 (255590-255597) and the width right x scale (255617).
- Nacelles are posed by the engine every frame (`HoverCraft::UpdateGimbals`, 193563), so
  the housing is bound rigidly to its nacelle bone and moves with the flame.

UNVERIFIED in the Redux shipping exe: none of the above was re-checked in a Redux
decompile. The owner compared the emit render with the game and confirmed the location
looks correct (2026-11-09).

For `avfigh` in Ogre mesh space (Ogre X = -VDF X, +Z forward) the emit points are
(+-0.762, 0.599, -1.810); `avfigh/build.json` records them with the nacelle pivots.

## What the tool builds

- One closed solid per nacelle (`Tools/nacellejet_blender.py`): a faceted fairing pod with
  its roof buried in the wing, the nozzle bell unioned in, then the bore, a bell groove
  and side vents cut as recesses. Each boolean is EXACT, applied alone, and must change
  the solid and leave it manifold. Faces left wholly inside the wing are dropped.
- Textures `<unit>_nacjet_{D,N,S,E}.dds`, painted from the solid's own zones and edges in
  the unit's hull colour (sampled from its diffuse map).
- Material `<unit>_nacjet : CR_BZBase`, appended to the unit's mesh as its last submesh.
  The stock submeshes are not edited, so their UVs, normals and weights stay as they were.

Known limits: the pod root is buried in the wing, not boolean-joined to the stock wing.
The bore glow and the blue ring are emissive all the time; the engine flame itself still
only shows above 10% throttle. Under co-op team colours only the hull paint is recoloured.

## Running it

    python Tools/Build-NacelleJets.py --units avfigh              # preview + review renders
    python Tools/Build-NacelleJets.py --units avfigh --ship       # install as the pre-rig stage

The tool always starts from the unit's pre-rig mesh at `source_revision` in
`References/WeaponRigs/models.json`, so it can be re-run at any time. Preview output goes
to `Local/NacelleJets/<unit>` (with a `preview.json` receipt); review sheets go to `review/`
only with `--ship`, and to the git-ignored `Local/NacelleJets/review-rollout/` otherwise.
Only `--ship` writes the tracked receipt. `--contact` composes one sheet per faction from
finished preview renders.

Shipping a unit, in order:

1. `--ship`, then commit the pre-rig `Assets/ModelFixes/<unit>.mesh`, the four textures,
   the material block and the receipt. Push. `--ship` replaces the rigged shipped mesh
   with the unrigged stage, so do not stop before step 2. A `housing=False` unit writes
   only the receipt (its mesh is unchanged).
2. If the receipt has `vdfParts`: `python Tools/Build-UnitAnimSlots.py --stock-dir
   "<Redux>/StockODFFiles" <unit>.vdf`. Then put the step 1 commit in `models.json`
   `stage_revisions` for the mesh (rigged units only), and run
   `python Tools/Build-WeaponRigs.py --models <unit>` for every rigged unit whose mesh or
   VDF changed (the rig reads the shipped VDF).
3. `python Tools/Build-TeamSkins.py --write` (adds `<unit>_nacjet_tm` and its mask).
4. If the unit has a generated cockpit (the scouts do), its receipt hashes the pre-rig
   exterior: run `python Tools/Build-ScoutCockpits.py`, then re-run step 2 for every unit
   that builder rewrote, so the rigged cockpit meshes come back. Only
   `exteriorSha256` in the receipt should end up changed.
5. `Manage-CampaignFiles.ps1 -bless` and keep only this unit's new lock entries.
6. Run `Tools/Test-WeaponRigs.py`, `Tools/Test-ScoutCockpits.py`,
   `Tools/Test-CombatPresentation.py`, `Tools/Test-UnitAnimSlots.py`.

The pinned stage commit must stay reachable from `main`: merge the pull request with a
merge commit, not a squash.

## Adding a unit

Add an entry to `CONFIG` in `Tools/Build-NacelleJets.py`: `unit(faction, scale, length,
also=..., offset=...)`. `scale` sizes the whole shape family (the engine draws every unit's
flame the same size, so 0.8-1.5 covers the fleet); `length` stretches the pod along the
chord; `offset=(dx, dz)` moves the pod body off the emit point to reach solid skin (the
nozzle stays on the emit point); `also=((part-name regex, fitted(...)),)` gives a nacelle
its own shape (avartl's rear pod). Emitters that seat alike share one solid; the others
carry rigid copies (mirrored across x when needed), each bound to its own bone.

Emit points come from class 67 nacelles (nacelle up axis x GEO bbox min y; a missing GEO is
estimated from the lowest mesh vertex the bone owns and flagged) or, when the VDF authors
them, from each class 75 part (its position, flame along its front axis; BZ 1.5 decompile
`all_decompiled.c` 255588-255605 and 193702-193706, UNVERIFIED against the Redux renderer).
An emitter whose flame runs into mesh 0.05-0.5 m ahead sits in modelled geometry and gets
no housing; `housing=False` records a unit's emit points and renders an emit sheet only
(bvrdev). Class 76 is smoke only.

`shift=((part-name regex, move),)` builds at an approved new emit point: metres along the
flame axis (positive = up, against the flame), an (x, y, z) build-frame vector, `'skin'`
(up or down to the seat skin) or `'relocate'`: the build moves the flame off the bbox-rule
point to the nearest flat, solid spot on the same nacelle skin (within 0.8 m, mirrored
left/right when the twin seats alike) and builds the housing there with the nozzle on the
new point. Use it where the stock point lands on a joint between parts or forces a stalk,
overhang or offset nozzle. `ports=True` with `housing=False` (avartl, bvartl, avapc, bvapc)
instead finds the glowing exhaust ports a nacelle already models (emissive texels linked
within 5 cm, elongated patches split in two, patches under 15 samples dropped) and proposes
each flame into the largest downward-facing one, along its normal.

`conform=True` (avhraz, bvhraz, svltnk) is for skins too stepped or curved for a flat seat:
the seat plane is lowered to the lowest skin point, and the pod roof follows a 2 cm height
grid of that skin (window maximum, never below the plane) instead of a flat top, with the
roof edge buried into the hull. Nozzle, ring, glow and paint are unchanged; units without
the flag build exactly as before.

This tool does not write the VDF. Each moved emitter carries `emitShift` (stock point, moved
point, delta, flame direction, reason) in `preview.json`, and the unit carries `vdfParts`:
one class 75 part per emitter, parented to its nacelle, with its local `matrix` in the VDF
layout (rows right, up, front, then position; the flame runs along front). A class 75 part
draws the flame from its own position along its front axis, and one authored class 75 part
suppresses every automatic under-nacelle emitter (BZ 1.5 decompile `all_decompiled.c`
193462-193491; throttle scaling needs a nacelle parent, 193771-193776), so unmoved nacelles are recorded too, at their stock points.
The emit points are always read from the VDF at `source_revision` (or the stock VDF), never
from the shipped VDF that already carries these parts, so re-runs give the same answer.

`Tools/Build-UnitAnimSlots.py` is the one VDF writer: it reads each shipped `build.json` and
adds its `vdfParts` to the stock VDF (and makes any `nacelles` it lists class 67), writing
`Assets/ModelFixes/<unit>.vdf`. `Tools/Test-UnitAnimSlots.py` checks every recorded part is
there and that no class 67 nacelle in a file with class 75 parts is left without its own.
`svtank/build.json` is hand-recorded (no CONFIG entry, no mesh change): its stock wing pods
become nacelles, each with a flame at its rear glow panel, and `ODF/svtank.odf` sets the pod
pitch (`pitchThrot/SteerNacelleRun 0.10`, `...Jump 0.12`).

The seat is a plane fitted under the pod footprint and raised to the highest skin, so the
roof is buried everywhere; the pod deepens to carry the nozzle at the emit point. Asserts:
some skin to seat on (>= 35% of the footprint), roof never exits the far side, every boolean
leaves one manifold piece. Clip checks against every opaque stock triangle (VDF pose): none
may pass through the bore or the 0.9 m flame cone below the lip (the nozzle hangs lower when
skin sits over the bore), and the housing's exposed surface may cross stock mesh only at its
seat: no crossing more than 0.02 m + 0.03 x scale below the seat plane, however uneven the
skin is (a band that grew with the unevenness let avhraz's pod cut 0.14 m into its rail).
When the configured pod clips, the pod is slid along the seat, then scaled down (not
below 0.8), then turned about the flame axis, with the nozzle kept on the emit point; the first
variant that passes is used and recorded as `adjusted`. A unit with no passing variant fails
with the reasons, and leaves no preview. Read the `notes` in `preview.json` before shipping.

Pod paint is the median texel of the downward-facing seat skin under and around the footprint,
after dropping saturated trim and decals and near-black gaps, taken from the dominant colour only.
Ring, bore and throat glow follow the faction flame colour (`FACTIONS`): NSDF blue, Black
Dogs blood red, CCA burnt orange, CRA green.

## Review sheets (avfigh)

- `review/avfigh-emit.jpg`: emit points and flame axis against the stock wing and the housing.
- `review/avfigh-mesh.jpg`: clay and wireframe.
- `review/avfigh-textured.jpg`: textured, on the scout.
- `review/avfigh-textures.jpg`: the four maps.

These are offline Blender studies, not game captures.
