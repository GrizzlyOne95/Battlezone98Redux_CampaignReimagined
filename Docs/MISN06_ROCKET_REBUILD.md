# Mars artwork rocket rebuild

The owner requested a full rebuild after the comparison with `marspict.png`.
The current geometry and textures are newly authored for CR. The first clean
cylindrical pass was too generic; the next pass corrected the dorsal housing
to face aft, added interlocking armour plates and service channels, slimmed the
nose and lightened the engine bells. The perspective inspection below uses a
low engine-side angle to make comparison with the painting more useful.

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
20,151 rendered triangles and 2,410 native fallback triangles. The native SDF
bounds cover the new dorsal housing. The four new atlases use RGBA8 DDS; the
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

The fixture now uses the pad's heading so its dorsal housing faces the clear
approach corridor. Terrain samples along the lower camera's line to the nozzle
show at least 8 m clearance; this still needs confirmation in the native view.

Next: isolated manager deployment using the already-built EXU main checkout
that includes point lights, then two-client native captures and final framing /
material checks. Do not treat the Blender studio images as native validation.
Keep progress in this document and push each coherent checkpoint.

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

Next: keep the validated pad and lighting fixes, move the camera around the
tower, and bring the authored silhouette and surface detail much closer to
that transport. Imported Total Command source assets are not shipping inputs.
