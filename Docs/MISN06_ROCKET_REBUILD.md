# Mars artwork rocket rebuild

The owner requested a full rebuild after the comparison with `marspict.png`,
then selected Coxxon's Total Command CCA Rocketship as the close model reference.
The current geometry and textures are newly authored for CR around that model's
measured silhouette: stepped conical skirts, recessed machinery wells, dark
command panels, segmented lamp rings and long engine casings with ribbed bells.
The earlier straight-cylinder / dorsal-housing reconstruction is superseded.

![Rebuilt rocket, engine-side perspective](../References/Misn06Rocket/rebuilt-concept-angle.png)

## Source and repeatable build

- Editable source: `References/Misn06Rocket/CCA-Mars-Transport.blend`, with relative
  texture paths and authored procedural materials.
- Geometry/material authoring: `Tools/Author-Misn06Rocket.py`.
- Build/export: `python Tools/Build-Misn06Rocket.py --blender <blender.exe> --render`.
  Requires Blender 4.5+ and Pillow. `--textures-only` reconverts existing baked
  maps and regenerates the bell layout and particle emitter blocks.
- Baked PNG sources, neutral views, bounds, nozzle anchors and game-file hashes
  are retained under `References/Misn06Rocket`.
- The old Resurgence extraction remains available as
  `Tools/Extract-Misn06RocketLegacy.py`; it is the previous prototype, not an input
  to this rebuilt model. Original Battlezone concept-art credit remains with
  the original creators.

## Runtime contract

The model retains the old origin, 97 m height and -48.5 m nozzle plane. It has
24,760 rendered triangles and 1,726 native fallback triangles (3,855 native
vertices, below the 4,096 limit). The native SDF bounds cover the new conical
skirts. The d/e/s atlases use BC1 DDS with offline mips (the normal map is a flat 16x16 RGBA8); the
physical geometry carries the panel relief and the normal map is neutral.

Eight bell exits generate `CR06RocketLayout.lua` and the Core/Plume emitters.
Each peer transforms those offsets using its own fixture basis. Four particle
systems share a total quota of 1,006; no extra network events are needed.
One optional EXU point light follows the engines, flickers gently and is
destroyed at shutdown. Its range is 180 m. Older EXU builds retain the clustered
particles without the optional light. Particle stops disable every emitter;
smoke/dust have a bounded four-second drain. The original mission cue and
flight, pad and recon contract remain intact.

## Checkpoint

Geometry, normal winding, native bounds, atlas formats and eight nozzle anchors
pass `Tools/Test-Misn06RocketAssets.py`. The expanded FX suite passes 322 checks,
including all bell rates, rotated fixtures, light cleanup and older-runtime
fallback. Mission 6's 1,063 host checks, four-peer presentation tests and source
parity pass. The shipping list admits exactly one additional runtime file,
`Scripts/CR06RocketLayout.lua` (2,764 total files).

The fixture uses the stock pad's heading. The current TC study and pullback
camera are staged for native run 5 with the pinned runtimes below. Do not treat
the Blender studio images as native validation. Keep progress in this document
and push each coherent checkpoint.

Implementation checkpoints: `298f3200` (model, sources and clustered FX) and
`49d15a60` (corridor-facing fixture and lower camera). CI passes both campaign
and shader checks. Native rebuild attempt 1 received WM_CLOSE before lobby
authentication. Attempt 2 stopped in the lobby on an Ogre duplicate `Top Screen`
UI object; neither reached the mission or exercised the rebuilt rocket.
The older canonical OpenShim build was 1.0.0.47 while the installed resources
were 1.0.0.53. The next run pins the consistent deployed build explicitly:

- `BZR_OPENSHIM_REPO=C:/Users/iestu/Documents/GIT/BZR-OpenShim-deploy-main`
  (build 1.0.0.53), also passed to the runner's `-OpenShimRepo`.
- `BZR_EXU_REPO=C:/Users/iestu/Documents/GIT/ExtraUtilities-deploy-main`
  (main checkpoint `332a18c`, including point lights).
- Isolated staging only: `C:/BZRCoop/mars-launch-20261018/content`.
- Native run being checked: `mars-rocket-rebuild-3`.

## Owner corrections, 18 October

Rebuild 3 reached the mission with an ivory hull and eight emitting bells, but
the light failed: EXU requires named `{r=...,g=...,b=...}` colour fields. This is
fixed, with the native argument shape asserted by the mock. The light now uses
a yellow-white colour and a 180 m range. Rebuild 4 confirms it on both peers.

The owner spotted that the fixture was beside the launch PAD. The inherited
socket had the wrong native local X sign. Stock Redux's raised deck measures
Ogre X -0.11085..38.92560 and Z -59.09940..-25.97380 at Y 29.129. Native local X
is mirrored; the corrected native deck centre is (-19.407374,29.129,-42.536600).
The model's nozzle plane stays -48.5 m; its map origin is now 25 cm above that
deck. Regeneration repairs an existing fixture as well as creating a new one.
The map contract asserts the anchor. Rebuild 4's capture confirms the deck
under the engines, but the tower now partly blocks this camera angle.

Disconnected red paint cards were reversed by a blanket Blender normals
recalculation. Primitives now retain explicit outward winding. The binary
asset test samples the diffuse atlas and verifies the red paint faces outward.
Native rebuild 4 shows the forward red band again.

The owner's next close model reference is Coxxon's Total Command (Workshop
2344006579). The local race dependency is installed under
`steamapps/workshop/content/624970/2343997862/BZTC_Races_1`. `sbcone.odf` names
the CCA Rocketship, `sbconecox00.msh` its main model, and
`sbconecox01.msh` an alternate. Materials point to `svconecox00_{d,e,n,s}.dds`.
It has eight `hp_emit_*` exhaust hardpoints and a 77.582 m tall, 24 m wide
silhouette: tapered skirts, recessed equipment bays and long engine casings.
Inspection renders and a Blender reference scene are retained privately under
`C:/BZRCoop/mars-launch-20261018/total-command-reference`.

Current TC study: the reference's 77.582 m height is normalized to the existing
97 m rocket while keeping its origin and -48.5 m nozzle plane fixed. Maximum
width is 30.037 m, within 0.1% of the uniformly scaled TC reference. Its eight
7 m engine offsets become an 8.752 m ring; the generated layout moves exhaust
with the new bell exits. The fixture remains on the validated deck anchor.
Native run 5 passes all 7 steps / 23 checks and confirms the TC silhouette,
deck anchor and aligned exhaust. The angle (-55,-20,95)m looked back toward
the sun and put the hull in deep shadow despite the neutral normal map. The
next camera pass alone moves to the sunlit clearing: local (95,-20,20)m, pulling
back to (140,-25,29.5)m. A twelve-sample native height-field check retains the
previous elevated shot if the low sightline becomes obstructed. The film suite
now passes 51 checks, including clear/blocked terrain and the pullback.

Reference identity, file hashes and scale are recorded in
`References/Misn06Rocket/total-command-reference.json`. Imported Total Command
source assets are not shipping inputs.

## Verified TC checkpoint

`mars-rocket-rebuild-6` passes all 7 steps / 23 checks on two Windows/GOG clients.
The only visual change from run 5 is the camera: the same model, textures and
exhaust now read as weathered ivory on the sunlit side, with the tower clear of
the bell cluster. The low shot is selected on the current terrain; the high
fallback is covered by the blocked-height-field unit case. Both peers show the
engines centred over the stock deck, eight active emitters in each engine layer,
four particle systems and a physical engine light. Camera release, continued
flight, original pad/timers and effect cleanup pass. Both clients exit normally.

Final captures: `Docs/images/misn06-tc-ignition.png` (host) and
`Docs/images/misn06-tc-ascent.png` (guest). The real dialogue still starts the
shot; the test advances only the existing transport-arrival deadline.
All 2,764 manager-admitted files match the isolated staged install.

Checkpoints pushed: `e28b32e9` (deck/lighting/paint), `9db3e9b3` (TC study),
`82840e1c` (sunlit clearing and terrain fallback). Draft PR #228 stays open for
visual review. Keep this active worktree. No main merge, regular GOG deployment
or Workshop upload was performed. Steam and Proton/Wine remain unverified.
