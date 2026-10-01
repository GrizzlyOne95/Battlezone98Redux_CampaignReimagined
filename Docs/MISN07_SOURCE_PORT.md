# misn07 source-faithful Lua 5.1 port

`Scripts/misn07.lua` ports the active `Setup` and `Execute` logic from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misn07Mission.cpp`
(source blob `9a849940dc7157dae309212923ebe59f28260905`). The header is empty apart from its include guard.
The verbatim files are retained in `References/Misn07Source/` for reconstruction.

The script targets stock single-player BZR Lua 5.1. It does not require EXU,
OpenShim, aiCore, or the reimagined campaign's weather/coop helpers.

## Preserved behavior

- Initial patrols, disguised stationary rendezvous tanks, delayed briefing,
  rendezvous tank replacement, tower warning, and rookie lookout/ejection.
- Vehicle and friendly-unit proximity alarms, damage-driven infiltration alarm,
  stolen Soviet vehicle detection, separate pilot/soldier reinforcement branches,
  looping alarm sound, and radar damage dispatch.
- Runner selection, pursuit announcements, escape detection, and patrol rebuilding.
- Radar destruction, the 7.5-second Utah/factory handoff, original ODF/path/audio
  names, team resources, strategic AIP activation, deployment objectives, and outcomes.
- Original strict timer comparisons, condition precedence, branch order, redundant
  second-objective checks, and failure precedence on simultaneous recycler deaths.
  Historical oddities such as the patrol-3 retreat guard referencing `p2_retreat`
  remain unchanged.

## Cut content

All disabled C++ in the gameplay routines remains disabled in Lua comments at its
corresponding location. It is deliberately not rewritten as executable Lua:
reconstruction needs an explicit design decision and map/assets validation.
The complete source archive also preserves declaration and serialization comments.

Notable blocks include the opening camera, alternate rookie jump, tank command
release, alternate alarm thresholds/dispatch, infiltration camera, extra friendly
alarm triggers, patrol-2 runners/replacements, rookie test-range and mine-path
beacons, radar/Utah camera cuts, streamed proximity mines, and MAG-cannon cinematic.
Unused mission state and zero-based arrays are retained for future reconstruction.

## BZR adaptations

- `Get_Time` becomes `GetTime`; native object names use `SetObjectiveName`;
  fractional health uses `GetHealth`; recycler deployment uses `IsDeployed`.
- Native `AiPath*` values become path-name strings. `m000` through `m110` are
  retained, although mine spawning remains disabled. Lua loops preserve the
  source member `count`, including its final value of 111.
- Null handles become nil (the source's explicit `wingman2 = 0` is retained).
  A distance helper returns infinity for absent/invalid handle operands, avoiding
  invalid stock API overload calls and false proximity alarms.
- Vehicle identification accepts both bare and `.odf` names. The damage helper
  checks validity rather than adding a new alive-only requirement.
- Save/Load serializes the state table through BZR's LuaMission mechanism.
  It does not replay Setup, respawn units, or reactivate disabled cameras on load.
  Native C++ pointer rebasing and binary array serialization are not Lua operations.
- The deployed predicate remains local; it does not alter the unused member `test`.

## Validation and integration status

`Tools/Test-Misn07.lua` passes 31 mock-host behavior checks under Lua 5.1, covering
startup, zero-based paths, strict timing, rendezvous, rookie ejection, both alarm
branches, stolen-vehicle detection, runner escape, tank patrol replacement,
radar destruction, producer/AIP handoff, deployment, save/load state, victory,
failure precedence, and disabled content remaining inactive.

Run from the repository root: `lua5.1 Tools/Test-Misn07.lua`.

This is a script checkpoint, not an in-game-qualified mission. At the inspected
main revision, the repository contains the Utah/factory ODFs and mission text,
but no `Missions/misn07` map bundle or `misn07.aip` was present. Before deployment,
provide/verify the original map and its labels, paths, audio, objective/debrief
files, AIP, and vehicle assets; bind its mission configuration to the Lua script.
Native strategic AI and real save/load handle restoration require in-game checks.
No mission map, shipping lock, deployment, or release configuration was changed.
