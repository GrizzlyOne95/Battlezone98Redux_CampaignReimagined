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
to `Local/NacelleJets/<unit>`; review sheets go to `review/`. Only `--ship` writes the receipt.

Shipping a unit, in order:

1. `--ship`, then commit the pre-rig `Assets/ModelFixes/<unit>.mesh`, the four textures,
   the material block and the receipt. Push. `--ship` replaces the rigged shipped mesh
   with the unrigged stage, so do not stop before step 2.
2. Put that commit in `models.json` `stage_revisions` for the mesh, then run
   `python Tools/Build-WeaponRigs.py --models <unit>`.
3. `python Tools/Build-TeamSkins.py --write` (adds `<unit>_nacjet_tm` and its mask).
4. If the unit has a generated cockpit (the scouts do), its receipt hashes the pre-rig
   exterior: run `python Tools/Build-ScoutCockpits.py`, then re-run step 2 for every unit
   that builder rewrote, so the rigged cockpit meshes come back. Only
   `exteriorSha256` in the receipt should end up changed.
5. `Manage-CampaignFiles.ps1 -bless` and keep only this unit's new lock entries.
6. Run `Tools/Test-WeaponRigs.py`, `Tools/Test-ScoutCockpits.py`,
   `Tools/Test-CombatPresentation.py`.

The pinned stage commit must stay reachable from `main`: merge the pull request with a
merge commit, not a squash.

## Adding a unit

Add an entry to `CONFIG` in `Tools/Build-NacelleJets.py` (faction, shape, stripe). The unit
needs class 67 nacelles and no class 75 part; a craft that carries its own class 75 part
emits from that part instead, and this tool does not handle it.

## Review sheets (avfigh)

- `review/avfigh-emit.jpg`: emit points and flame axis against the stock wing and the housing.
- `review/avfigh-mesh.jpg`: clay and wireframe.
- `review/avfigh-textured.jpg`: textured, on the scout.
- `review/avfigh-textures.jpg`: the four maps.

These are offline Blender studies, not game captures.
