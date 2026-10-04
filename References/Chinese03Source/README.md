# Chinese mission 03 Lua port

`Scripts/ch03.lua` ports `Chinese03Mission.cpp` to stock BZR 2.1 / Lua 5.1.
The native source is archived verbatim, including all declarations, original
serialization, comments, and disabled code. Source repository:
https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Chinese03Mission.cpp
Source Git blob: `41b44bf53de2ce74a49bca874aaa440bb2fcfc9c`.

The four disabled scavenger spawns and the commented `cspilo` assignment also
remain beside their corresponding Lua logic. Unused camera/objective/audio
state and the unreachable `lose2Sound` branch remain available for reconstruction.

The port preserves the 780-second timer; strict health/ammo >400 checks; strict
timer comparisons; six random general slots; all six APCs and their four escorts;
480-second factory/armoury reinforcement and both 100-scrap grants; route radii;
15 explosions; capture, ambush and debrief sequence; command priorities; and
zero-based state arrays. Lua explosion arguments are reversed to the stock API
signature. Save/Load retain the mission table without replaying setup.

## Documented repairs

- Initialize only three `turnedAround` flags; C++ writes past the three-element
  array into other mission flags. Intended initial state and route flow are unchanged.
- Ignore missing/dead APCs in proximity triggers and guard invalid command
  handles. Existing live units use the same targets, paths and thresholds.
- Clear completed loss audio handles before scheduling failure. The first
  audio-completion +1-second failure remains identical and cannot be postponed
  by repeated per-frame scheduling.
- Prevent the escape loss after victory is already scheduled, matching the
  other native terminal-state guards. The pre-victory grace period is unchanged.
- Permit the final repaired howitzer's AI handoff after objective 1 completes,
  using the existing ready/entered/left conditions. APC spawning is not delayed.

## Fidelity limit and integration

The native howitzer handoff directly modifies `curPilot` and calls
`AiProcess::Attach` when `GetAIProcess()` is null. Those internals have no stock
Lua binding. The port resets the default pilot class and sends a one-shot `Stop`
to an unpiloted howitzer, restoring any already-triggered APC attack afterward.
This substitute is provisional: validate that empty repaired howitzers acquire
AI and fire on the intended APCs in BZR. No pilot unit is spawned and no team is
changed to simulate attachment. The full original block is preserved in Lua.

No mission map/TRN, ODF, audio, text, or packaging files are changed. To integrate,
use the original mission's labels, paths and assets and configure its LuaMission
entry point to load `ch03.lua`. `ch03.lua` has a short basename suitable for the
project's legacy filename conventions. Test all three routes, boarding/hop-out
and ejection, capturing the general APC, early capture before the factory arrives,
all failure debriefs, delivery, and an engine save/load during each phase.
The factory attackers still spawn on early capture; when the factory does not
yet exist their invalid Attack orders are omitted, without inventing a target.

## Validation

Run `python Tools/test_ch03.py` with `lupa.lua51` installed. The tests execute
Lua 5.1 against strict engine mocks and cover the timeline, all six random slots,
repair bounds, route explosions, capture/ambush/delivery, losses, invalid handles,
final howitzer handoff, save/load, and source asset/disabled-code preservation.
Mock tests cannot validate native AI behavior, mission assets or engine persistence.
