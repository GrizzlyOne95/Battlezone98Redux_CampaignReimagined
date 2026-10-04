# Chinese01Mission source port

`Scripts/ch01.lua` ports the active mission to stock BZR 2.1+ / Lua 5.1.
It has no helper, EXU, or OpenShim dependency. This is a source port, not
a map/asset integration or a change to the existing campaign missions.

`Chinese01Mission.cpp` is an exact upstream snapshot, including all native
save/load scaffolding, comments, unused fields, and disabled code. The startup
`#if 0` block and inline cut calls are also kept as comments in the Lua script.
Upstream: `GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Chinese01Mission.cpp`.

## Preserved behavior

- Initialization on the first Update; five-second opening delay, sound-completion
  gates, hangar identification, and fifteen-second armory delay.
- Communication tower destruction unlocks the recycler. Deployment schedules
  wave 1 after 60 seconds. Waves 2 and 3 follow at 300-second intervals; airborne
  attacks follow after 180 and 30 seconds, wave 4 after 60, and the tug after 120.
- All original ODFs, teams, counts, build/order sequence, paths, command priorities,
  objective transitions, scrap/pilot changes, and seven random decoys.
- Tug destruction/escape failures, capture within 75 metres, 150-metre detector
  radius and both escort requirements. Ambush still spawns even with escorts.
- Relic pickup starts the 180-second cockpit countdown. Victory tests the relic's
  distance from the hangar against navEnd-to-hangar minus 50 metres, with strict
  `>` and the original three-second win/failure transition.
- Unused native fields/timers and duplicate SetPerceivedTeam calls remain.

## API adaptations and fixes

- Native `IsInfo(handle)` becomes `IsInfo(GetOdf(hangar))` in stock Lua. Its
  ODF-based identification semantics must be confirmed with the actual map.
- Airborne BuildObject's native height overload becomes a vector at path point
  zero plus 200/100 metres in Y. Lua's fourth path argument is a point index.
  Actual placement must be checked against the native map in-game.
- Correct stock capitalization for EnableAllCloaking, IsDeployed, IsFollowing;
  ColorFade replaces ColorFade_SetFade. Objective colors are strings.
- Native MakeExplosion(location, effect) becomes MakeExplosion(effect, location).
  Redux uses the D3D `xpltrsn` effect. The unavailable legacy useD3D switch and
  `xpltrsq` branch are retained in the source archive.
- Save/Load retain the complete state table, including zero-based detector and
  camera arrays. LuaMission remaps game handles; Setup is not rerun on Load.
- Deleted objects are dead for health gates and cannot satisfy proximity tests.
  Missing/deleted relic, hangar, or evacuation beacon cannot count as a safe relic.
  Valid-object distances and health comparisons stay unchanged.
- A previously latched failure cannot be overwritten by countdown success. The
  source otherwise permits this if failure audio lasts until detonation. Normal
  evacuation result tests and delays stay unchanged.
- Update the stationary ending camera each frame and release it on cancellation,
  subject deletion, or the three-second result transition after detonation. The
  source calls CameraPath once and never CameraFinish. Cancellation does not
  restart the shot; no countdown, distance, or mission-result gate changes.

## Validation

Run from the repository root:

```sh
lua5.1 Tools/Test-Chinese01.lua
```

The stock-API mock checks full success, all wave counts/order/timers, airborne
offsets, escort and decoy behavior, ending camera cleanup, save/load during audio,
tug/recycler deletion, tug escape, detection failure precedence, strict safety
boundary failure, and destruction of the relic. Lua 5.1 compilation is checked.

This does not prove engine/map behavior. BZR playtesting must verify map labels,
asset availability, hangar identification, aerial placement, tug capture/orders,
escort detection, the cockpit timer across save/load, and the cinematic effect.

Source blob: `210bb8193c11836ffb299bb15bf89afd945e48c5` (byte-preserved snapshot).
