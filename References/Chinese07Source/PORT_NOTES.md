# Chinese mission 07 Lua port

`Scripts/ch07.lua` targets stock Battlezone 98 Redux and Lua 5.1. Wire the
mission's LuaMission configuration to `ch07`; the script requires the original
Chinese07 map labels, paths, ODFs, audio, objectives, and result descriptions.
This change adds the script, not replacement map content or installation files.

## Source and preservation

Source: `Battlezone_Source/BZ1/from_bz2_dll_src/Chinese07Mission.cpp`, blob
`15672b609a6bb5bda727c99ced2b7ed25dad3b6e`.
The adjacent C++ file preserves the full original content. The Lua includes an
ordered archive of every native comment and disabled preprocessor block, plus
translated inactive debug/base/backup fragments near their relevant logic.
The commented objective-1 and convoy-spawn gates remain disabled. The special
APC selection remains active, including its commented debug directives.

Zero-based explicit tables retain native indexes. The opening camera's local
`arrived` is kept separate from the persistent route-camera flag. The source's
unused flags, timers, empty AddObject, and inactive getBase are retained.

## API translations

- `curPilot = 0` becomes `SetPilotClass(h, "")`, clearing the pilot class while
  retaining convoy and escort AI. This is supported by the source repository's
  `BZ1/1.5/functions/0045/0045efdb_SetPilotClass.c` and the project's existing
  BlackDog01 port.
- Native explosion argument order is reversed for stock Lua. Redux uses
  `xtorxplb`; the old renderer-dependent `xtorxpla` branch is archived.
- Native refill booleans become explicit current/max comparisons and setters.
  Full units do not consume the pickup. Fade and sound use ColorFade/StartSound.
- Rescue pilots retain the native fourth integer path argument `200` verbatim.
  Native path overload evidence is `0046/00460b7a_BuildObject.c`; this port does
  not invent an altitude conversion. The map's handling of this index needs an
  engine playtest, as do camera, explosion, pilot, and pickup behavior.
- Save/Load persist the entire mission state table, including handles and
  audio tokens, using LuaMission serialization rather than native union arrays.

## Bug fixes

Both are documented at the affected Lua statements:

1. Consume the completed loss audio token before FailMission. Native code
   repeatedly schedules `GetTime()+1`, potentially postponing defeat forever.
   The escape trigger, audio gate, description, and one-second delay remain.
2. Query warning/escape distances only for a live relic APC. A destroyed handle
   can otherwise produce a false loss after objective 3 is awarded. The live
   convoy's route and timing are unchanged, and extraction still follows its
   destruction.

## Validation

Run from repository root: `lua5.1 Tools/Test-Chinese07.lua`.
Executed with Lupa's Lua 5.1 runtime: syntax and mission regression checks pass.
Coverage includes all six route/relic combinations, strict timer boundaries,
three convoy entries and their escort/pilot classes, all 81 ambush units,
disabled gates, one-shot bomb explosion, guarded extraction, pickups,
one-shot defeat/victory, and save/load across convoy and defeat state.

These API doubles validate script logic. No BZR engine playtest was available.
