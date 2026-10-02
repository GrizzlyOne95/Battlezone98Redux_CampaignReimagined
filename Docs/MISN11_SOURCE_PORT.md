# misn11 source-faithful Lua 5.1 port

`Scripts/misn11.lua` ports the active `Setup` and `Execute` logic from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misn11Mission.cpp`.
Source blob: `127e2f66fe3de1c79434a4c1a7b284601909ee7c`.
The original C++ and its include-guard-only header are preserved byte for byte
in `References/Misn11Source/`, including all declaration and serialization comments.

The script targets stock single-player Battlezone 98 Redux, Lua 5.1.
It does not require EXU, OpenShim, aiCore, or campaign helper modules.

## Preserved behavior

- The three named/marked transports, three waypoint names, initial target,
  50 scrap, briefing, and strictly-after-15-seconds convoy departure.
- Oppenheimer's +300 health on every Update, including after betrayal. It is
  not converted to full invulnerability or scaled by the update timestep.
- Waypoint-1 betrayal, the 15-second announcement delay, real team change,
  turret command priorities, first strike, and pursuit warning.
- Separate first-waypoint player/transport triggers and the original second
  checkpoint at `check2` path point **1**, rather than the second camera.
- The second strike, blockade-dependent convoy restart, and two-tank ambush
  when the player or Transport 1 is within 450 metres of the first pad.
- The source's literal pad health delta `-0.90`. No guessed conversion to
  90 percent damage is applied; the existing fallback still removes the pad
  if both ambush tanks die while the pad survives.
- Natural pad destruction starts a 40-second escape delay. Forced removal
  starts a 10-second delay and does not invent the natural-loss announcement.
- Escape orders, the second-pad objective, final-wave timing, the destroyed
  old-pad camera fallback, two strike fighters, and the late-spawned player
  attacker at pad 2. A final camera is built at `last_camera`.
- Full matching-fighter scans at each strike: existing fighters on any team
  are re-tasked too. The late player attacker is deliberately spawned after
  the last scan, keeping its player target rather than Transport 2.
- Original failure conditions, debrief filenames, 15-second outcome delays,
  and independent arrival latches within 200 metres of pad 2. The player
  and transports need not arrive simultaneously; both cargo transports must
  still be alive when success is scheduled.
- Strict timer/range comparisons, source branch order, default versus
  explicit command priorities, `99999` timer sentinels, and unused members.
  There is no added global outcome-return or redesigned state machine.

## Source oddities and documented safety fixes

The pursuit warning tests `GetDistance(turr1, player)` directly as a C++
boolean. The port uses `~= 0`: zero is false in C++, but truthy in Lua.
There is no source distance threshold to recover confidently, so none is
invented. The warning therefore normally plays immediately after the
betrayal announcement if the first turret is alive.

The source unconditionally dereferences objects for startup names/markers,
the betrayer's team write, and the pad health write. The port guards those
writes with object existence checks. Inline `BUG FIX` comments identify
each case and explain why present-object behavior, mission timing, and
transitions remain identical. Missing cargo still triggers the original loss
condition; a missing betrayer does not suppress the scheduled announcement.
Missing map labels remain integration defects, not replacement content.

The distance adapter rejects nil, zero, and invalid object operands before
calling stock Lua overloads, returning infinity for proximity checks. It
preserves an explicit path point when supplied. ODF matching accepts bare
and `.odf` spellings without adding team filters. Native pointer/list calls
become `SetObjectiveName`, `SetObjectiveOn/Off`, `SetTeamNum`, `AddHealth`,
and `AllObjects`; `Get_Time` becomes `GetTime`.

## Commented-out and reconstruction content

All nine original block comments in `Execute` remain at their corresponding
locations in the Lua script, including the incomplete transport-damage radio
idea and the disabled scan that commands **every** `svtank` to attack the pad.
The original narrative, path inventory, and inline gameplay comments remain
available too. Disabled C++ stays disabled as C++ text, so future restoration
can inspect the original intent before converting it to executable Lua.
The byte-identical source archive preserves everything outside the gameplay
routines, including native class layout and Load/Save/PostLoad implementation.

## Save/load and validation

`Save` returns the mission state table; `Load` restores it through LuaMission.
Load does not replay Start, label initialization, briefing, or object creation.
Native binary member arrays and `ConvertHandle` are replaced by LuaMission's
serialization of primitive values and game handles. The current player
handle is refreshed on every Update, as in the source.

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn11.lua
```

88 mock-host behavior checks passed under an actual Lua 5.1 interpreter.
They cover startup, command priorities, strict timer/range boundaries,
both waypoint triggers, both strike scans, C++ numeric truthiness, pad
destruction/removal, camera loss, wave spawn/target order, arrival latches,
all cargo-loss branches, missing-object safety, and fresh-chunk save/load.
Both Lua files also compile under Lua 5.1. The repository validator's
Lua, engine-filename, and case-collision checks pass for the task files.
Source archive Git blob hashes match the originals, and a separate
comment-preservation check confirms all nine Execute block comments.

This checkpoint still needs in-game validation of AI paths, attack behavior,
health restoration, objective/audio presentation, and real save/load handle
restoration. At inspected main revision
`6636e74086d1587a6cf129b04b2d8d04ea997a99`, the repository has mission 11
transcript text but no `Missions/misn11` map bundle or mission-11
objective/debrief files. The port does not create a replacement map.

Before integration, provide the original map and verify these dependencies:

| Kind | Required names |
| --- | --- |
| Map labels | `avhaul0_tug`, `avhaul1_tug`, `avhaul2_tug`, `svturr2_turrettank`, `second_blockade`, `svturr3_turrettank`, `apcamr3_camerapod`, `apcamr4_camerapod`, `apcamr5_camerapod`, `launch_pad`, `launch_pad2` |
| Paths | `base1`, `base2`, `openheimer`, `check2` (point 1), `strike1`, `strike2`, `strike_path1`, `strike_path2`, `launch_attack`, `escape`, `last_camera` |
| Spawn ODFs | `svfigh`, `svtank`, `avcamr` |
| Voice audio | `misn1101.wav` through `misn1113.wav` |
| Objectives | `misn1101.otf`, `misn1102.otf`, `misn1103.otf` |
| Debriefs | `misn11l1.des`, `misn11w1.des` |

Bind the original mission configuration to the Lua script and verify asset
availability in the installed stock/mod environment. No mission configuration,
shipping lock, deployment, or release settings are changed by this port.
