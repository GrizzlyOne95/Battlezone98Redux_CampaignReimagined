# Black Dog 13 Lua port

`Scripts/bdmisn13.lua` ports `BlackDog13Mission.cpp` to stock BZR 2.1+ / Lua 5.1.
The archived C++ source is complete, including every comment, declaration,
unused member, and native serialization routine. This revision contains no
commented-out executable mission code.

Source: https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/BlackDog13Mission.cpp

Source blob: `ac9bdec108f18a8d5ad933353ebd612fc156da34`.

## Faithfulness and adaptations

- Retains resource setup, the 45-minute cockpit timer, four attack waves at
  3/10/15/30 minutes, all six four-unit defender groups, spawn paths, command
  priorities, intro camera parameters, audio, objectives, and debrief files.
- Uses stock `IsRecycledByTeam(handle, 1)` for the native
  `isRecycledByTeam(handle, 1)` check. Dead handles must reach this query;
  command-target or scrap-gain guesses are unnecessary.
- Each native defender condition converts `GetDistance` directly to a boolean.
  Lua requires `~= 0` to reproduce C++ truthiness. No inferred proximity radius
  is introduced, and all six groups retain the shared `spawn_defend1` and
  `spawn_defend6` paths.
- Guards missing/deleted handles for health/distance/name overloads. Absent
  health counts as zero, preserving native loss/completion gates. A dead silo
  handle is retained for the recycle query. Comments explain these binding fixes.
- Uses `SetObjectiveName`, the stock equivalent of native `SetName`, and string
  objective colors. Objective duration is omitted to preserve the default.
- Preserves update ordering, including timeout before silo checks, silo checks
  before enemy-recycler damage, and player-recycler loss before victory. A final
  recycle on the expired-timer frame still loses. No new terminal return alters
  camera/wave activity or suppresses additional native silo-loss calls.
- Saves every mission field in a Lua table, including unused objective flags,
  the unused second camera state, prior player handle, and scrap bookkeeping.
  Engine serialization replaces native union I/O and `ConvertHandle`; loading
  does not replay startup resources, camera/audio, waves, or cockpit timer.

## Validation and integration

Run `python Tools/test_bdmisn13.py` with `lupa` installed. It explicitly uses
`lupa.lua51`, derives wave/defender compositions from the archived C++ source,
and checks strict timer boundaries, command targets, camera/audio gates,
nonzero-distance semantics, team-1 recycling, all four losses, victory, and
save/load state across completed waves and pending audio.

These are mocked API checks, not an in-engine playthrough. Test with the original
BD13 mission assets and map labels/paths; confirm recycle reporting for removed
objects, camera/timer save restoration, objectives, and the failure/victory
debriefs in Redux. This work adds the script without changing BZN mission-class
configuration or deployment manifests. The script basename fits the game's
legacy eight-character convention.
