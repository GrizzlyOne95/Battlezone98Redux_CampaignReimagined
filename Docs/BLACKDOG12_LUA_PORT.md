# BlackDog12 Lua port

`Scripts/bdmisn12.lua` ports the active logic of
`Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog12Mission.cpp` to stock
Battlezone 98 Redux 2.1+ / Lua 5.1. It requires no EXU/OpenShim or project helper.
Attach the script to the original bd12 map for engine testing; this change
does not modify a map, assets, packaging or deployment.

The complete source is archived byte for byte at
`References/BlackDog12Source/BlackDog12Mission.cpp`, Git blob
`584450878d2ed983c75195f10d8ccaeb6abcaedc`. This preserves every original
comment, unused member, declaration and native save/load/PostLoad routine.
This particular source contains no disabled gameplay statements or cut-code
blocks; no inactive content has been enabled in Lua.

## Fidelity

- Keep zero-based arrays and Execute order, including updates during the intro.
- Keep strict `timer < GetTime()` comparisons and finite disarmed timer values.
- Keep resources (50 player scrap, 10 enemy scrap, 10 player pilots), all 36
  timed enemy units, exact spawn paths/ODFs/targets, all priority-1 commands,
  defender relationships and uncloaked walkers.
- Keep four portal reinforcements, eight independent
  quarter-health warnings and two counterattack tanks per destroyed
  shield/power pair.
- Keep intro cancellation, objective transitions, all-goals-dead victory,
  portal-death failure, narration gates, +1/+2 ending delays and success-first
  ordering if both endings become eligible in the same frame.
- Replace native serialization/ConvertHandle with LuaMission Save/Load of the
  state table. Loading does not rerun Start or reset cameras/timers/latches.
- Map native `activatePortal(portal, false)` to outward `PortalOut` and
  `ActivatePortal`; use stock `DeactivatePortal` and `BuildObjectAtPortal`.
  Portal visuals, activation behavior and launch physics need engine testing.

## Explained port fixes

Each fix is documented inline:

1. Missing/deleted objects count as zero health, retaining native death
   triggers without unsafe Lua handle calls. Failed builds receive no cloak
   or AI commands; successful builds retain their source behavior.
2. A missing camera subject ends the intro through its existing arrival
   branch. Normal path parameters and cancellation remain unchanged.
3. Missing narration handles count as completed for endings. Successful
   narration retains the original completion gate and ending delay.

## Timing aligned to TRO 1.3

The C++ source schedules the recycler at `13 * 60` (780 seconds) but the escorts at 546/552 s and the objective advance
at 555 s, with the portal opening at 778 s and closing at 554 s. The shipped TRO 1.3 executable (FUN_005aa100) has
the recycler at 780 s, the escorts at 786 s and 792 s, the portal open 778-794 s and the objective advance at 795 s,
and it spawns no scrap (`scrap_1`/`scrap_2` are never used). The Lua follows TRO 1.3 on both counts; the six
`npscr1` pickups per minute from the C++ source are gone.

## Validation

From the repository root:

```sh
lua5.1 Tools/CoopCampaignTests/Test-BlackDog12.lua
python Tools/CoopCampaignTests/Test-BlackDog12SourceParity.py
```

The behavior suite passes 148 checks on Lua 5.1, using strict engine mocks
to test timer boundaries, waves/escorts/cloaking, resource setup, intro
cancellation, reinforcements, portal direction, objectives, warning thresholds,
counterattacks, deleted handles, failed builds/audio, endings and save/load
continuity. The parity check verifies the exact source archive, all 139
ordered gameplay side-effect calls and all timer assignment expressions.

These checks do not simulate BZR AI, audio playback, portal physics or the
engine's handle serialization. A full mission playthrough and in-game save/load
remain required before calling the port gameplay-verified.
