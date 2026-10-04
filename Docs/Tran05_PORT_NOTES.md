# Tran05 source port

`Scripts/tran05.lua` is a standalone Lua 5.1 / stock BZR port of
`Tran05Mission.cpp` (source blob `f318d388fb7976a40652c88b0fb375dcc18fc93a`).
The existing reimagined `Scripts/misn02b.lua` is retained. The new script does
not load its difficulty, AI, weather, subtitles, pilot-management or QOL modules.

The complete native source already exists, byte-for-byte, at
`References/EarlyMissionSources/Tran05Mission.cpp`. Every original comment,
including disabled C++ statements, is also preserved in the Lua comment ledger.

## Preserved behavior

- Original labels, ODFs, AIP, paths, objective files, audio and result descriptions.
- Intro camera stages can advance in the same update, as in native Execute.
- First fighter follows patrol1 at priority 0; later fighters attack the first
  scav within 200 metres of bgoal, otherwise follow patrol2 at priority 0.
- First patrol trigger: 75 metres from bhandle. Second trigger: 200 metres from
  bhandle2. Reinforcements start after 30 seconds and repeat every 45 seconds.
- Retreat requires the first scav to have taken an enemy shot. Its initial
  Follow is priority 0, matching native AiCmdInfo rather than the wrapper default.
- Rescue checks message1/message4 and 300 metres from home; it intentionally
  does not require message2. The later Follow retains its native default priority.
- Second scav retreats on the original path. Its pursuer appears after 10
  seconds. First-scav regeneration is 200 health per second with strict deadlines.
- Arrival within 200 metres heals both scavs by 1000, plays misn0234, and waits
  for completion before success. Failure likewise waits for misn0227.
- Base/recycler loss is independent of whether the first scav has been built.

## Documented fixes

Handle validity checks prevent missing-object distance queries and native-style
null object dereferences. Live-object thresholds, timers and orders are retained.
Unset native audio ID 0 becomes nil, treated as no pending playback in Lua.

The source can latch both terminal outcomes and overwrite their shared audio
handle. The port retains the first result; loss is evaluated before rescue and
victory, matching source order. This changes only conflicting terminal states,
without adding a new mission phase or delaying the ordinary outcome.

Unused native state remains initialized or nil. Native serialization unions,
pointer conversion and AiMission forwarding are replaced by LuaMission Save/Load;
loading retains state without replaying startup or resetting delays.

## Map integration and remaining fidelity checks

Use a copy of the original `misn02b.bzn` with `tran05.lua` selected as its mission
script. This change does not replace the current campaign mission or modify a map.

Native PostLoad changes `player_path.points[7].x -= 40.0f` to route the cinematic
dummy around buildings. Stock BZR Lua exposes point reads and path-type changes,
but no documented point-coordinate setter. In the copied map, shift the **eighth
player_path point 40 metres toward negative world X once**. Check the map has not
already incorporated this correction before applying it. Keep native Goto path
following; do not substitute distance-driven Lua waypoint movement. The script
does not reproduce this adjustment on its own.

The native retreat Follow attaches a private two-point AiPath from the scav to
home. Stock Follow retains the destination and priority but cannot attach that
private path. Compare its navigation in BZR against the DLL during playtesting.

Validate both camera stages (normal completion and cancel), first-scav retreat,
all death conditions, final pursuit and arrival, and save/load during the intro
and rescue. Engine navigation, audio userdata persistence and camera behavior
have not been validated in-game in this environment.

## Validation

`Tests/tran05_spec.lua` runs from the repository root with Lua 5.1. It uses API
stubs to exercise patrol/wave progression, strict deadlines, command priorities,
rescue without an added message2 gate, regeneration, pursuit, result audio waits,
state restoration, base loss before scav creation, deleted objects, late fighter
callbacks, and simultaneous base loss/arrival. These checks validate Lua logic;
they do not replace BZR playtesting.

Syntax and flow checks passed using the Lua 5.1 runtime provided by `lupa.lua51`.
