# Eagle's Nest: NSDF evacuation rocket

The end of `misn03` closes on the NSDF transport lifting off the launch pad.
The older ending (`misn0316`, the camera path, the in-base tank attack with
`misn0317`/`misn0318`, the `abwpow` shot and the six-second close) is unchanged.
Where it used to call `CameraFinish()` and `SucceedMission(0.1,"misn03w1.des")`
it now rolls the launch first, then ends the same way.

## Art

The rocket is GrizzlyOne95's own NSDF transport from the ROTBD/Resurgence mods
(`abtrans.mesh`, submesh `abtrans_BZBase_abtrans`, 2,750 triangles, 92 m tall).
The pad submesh is dropped and the skeleton link and bone assignments are
stripped, so it is a static prop. The four 1024 square maps ship as
BC1 DDS with full offline mips (`cr03rok_{d,n,s,e}.dds`); compressed textures
without mips render black in native DX11. The material is `cr03rok00` so it cannot clash with the Resurgence
addon's `abtrans_BZBase_abtrans`.

`python Tools/Build-Misn03Rocket.py [SOURCE_DIR]` regenerates, deterministically,
`Assets/ModelFixes/cr03rok.{mesh,geo,sdf}`, the textures, `Materials/cr03rok.material`,
`ODF/cr03rok.odf`, `Scripts/CR03RocketLayout.lua` and `References/Misn03Rocket/build.json`
(file hashes). The source directory defaults to the author's `ROTBDv2` folder
and is only read. All model I/O goes through the shared serializers
(`Tools/bzmodellibs.py`).

Origin convention: the same as `cr06rok`. X/Z sit on the rocket axis (24.745,
-23.415 in the abtrans frame) and Y is the mid-height of the bounds (66.2562 in
the abtrans frame), so the model spans Y +/-46.0047 and the nozzle plane is at
-46.0047 (cr06rok: +/-48.5).

## Fixture

`Tools/Add-Misn03Rocket.py` clones the `launch_pad` block of `Missions/misn03.bzn`
into a `cr03rok` fixture labelled `cr03_rocket` (team 0, health 0, no AI, no
damage). Misn03's BZN is not produced by `Build-CoopMap.py`, so the step edits the
committed file and is idempotent. The world transform comes from the pad's basis:

- The art's pad is the stock `ablpad` turned 180 degrees about Y, so in the stock
  pad's Ogre mesh frame the axis is at (-24.745, ., +23.415). Native local X is
  mirrored relative to the Ogre mesh (stock `ablpad` SDF centre x = +6.2092 for an
  Ogre mesh centre x = -6.2092 on the N64 pad), as for misn06's deck anchor, so the
  native pad-local offset is **(+24.745 right, 66.2562 up, +23.415 front)**.
- The heading is the pad's with right and front negated.
- The nozzle plane is therefore 20.2515 above the pad origin. Placed result for the
  shipped pad (1642.37, 53.5, 101678): fixture (1619.03414, 119.756185, 101653.18).

## Launch

misn03 reuses misn06's `CR06LaunchFilm` and `CR06LaunchFX`, now configurable
(defaults keep Mission 06 identical; its tests are unchanged). misn03 supplies:

- `CR03RocketLayout`: one centre bell and six on a 9 m ring at 0/60/120/180/240/300
  degrees (the skirt lobes), measured from the nozzle plane in fixture-local right/front.
- The shipped `CR/M06/Core`, `Plume` and `Dust` templates. No new payload. The
  smoke layer is left out (no atmosphere). The eight-emitter template keeps its
  eighth emitter dormant. The four second drain, the optional EXU point light
  (`{r=,g=,b=}`) and the flight (Y = base + 2.5 * max(0, age-1)^2 over 20 s, from
  `GetTime`, so it survives save/load) are unchanged.
- An eleven second camera on `cr03_rocket` with misn06's smoothstepped pullback.

Flow and co-op:

- When the older film would end (its six second close, or the 90 s deadline in co-op),
  `BeginRocketLaunch()` hands the previous camera back and starts
  the film. `coopOutroDeadline` was extended by the launch length.
- A skip (`CameraCancelled`, offline) still ends the mission at once, before or
  during the launch. In co-op each peer skips only its own camera.
- `RocketFX`/`RocketFXStop` are Present ops: applied locally on the leader and sent on
  the ordered E stream, with the whitelist in `ReceivePresentation` admitting them.
  Every peer moves its own fixture and owns its particles.
- Object cameras go on the existing C snapshot: the first four slots read as a path frame
  (`"@object"`, x, y, target) so an older peer ignores the rest; subject and z follow.
- The pad-destroyed failure is disabled once the launch starts. Losing the pad then ends the
  shot early and succeeds.
- `M.launchPhase`, `M.launchStart` and `M.launchFilm` ride in the saved mission table. Load
  re-acquires the camera and restarts the exhaust at the saved age.
- An old save or map without the fixture ends exactly as before.

## Checks

```
lua5.1 Tools/Test-Misn03LaunchFX.lua
lua5.1 Tools/Test-Misn03LaunchFilm.lua
lua5.1 Tools/Test-Misn03Launch.lua      # complete misn03 script, 3-4 peers and offline
python Tools/Test-Misn03RocketAssets.py
```

`Test-Misn03Launch.lua` reuses the engine/network harness of `Test-Misn03Coop.lua`.
Not verified in the game: the shot framing against the ablpad geometry (the camera
offsets are misn06's, applied to a fixture turned 180 degrees), the pad collision with
the new SDF, and the EXU point light. Credit for the art: GrizzlyOne95 (ROTBD/Resurgence).
