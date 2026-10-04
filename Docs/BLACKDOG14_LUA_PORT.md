# BlackDog14 Lua port

`Scripts/bdmisn14.lua` ports `BlackDog14Mission.cpp` to stock Battlezone 98
Redux 2.1+ / Lua 5.1. It requires the original mission's map labels, paths,
ODFs, `bdmisn14.aip`, WAVs, OTFs, and debrief files. This change adds the script;
it does not switch a map's mission class or package/deploy the mission.

The complete original source is archived at
`References/BlackDog14Source/BlackDog14Mission.cpp`, preserving Git blob
`5217e98a56da2b57a53f32b9e3fdad6e788b1a18` byte for byte. This includes all
comments, unused state, native serialization, and the disabled three-turret
wave. The `#if 0` block also remains inactive at its original place in Lua.

The port retains strict `< GetTime()` timer comparisons, sequential independent
event checks, every spawn and command in source order, resource setup, audio,
objective colors, ambush radii, and outcome arbitration. Enemy recycler death
wins arbitration over APC arrival and player recycler destruction, as in C++.
No new APC-destruction prerequisite is added to the enemy-recycler win.
One-shot sentinel times and unused camera/objective fields are also preserved.
Save/Load retains the state table, including object and audio-message handles;
Load does not repeat startup or spawns.

## Documented fixes and adaptations

- **Walker cloak targets:** the three native walker spawns each cloak `h`,
  which still refers to the previous light tank. Lua cloaks `w1`, `w2`, and
  `w3`. Spawn counts, routes, followers, event sequence, and timers stay the
  same; the intended cloak state changes and can affect detection/combat.
- **Destroyed APC arrival:** SOE #9 cannot fail an intercept already completed
  by SOE #7 or query an absent APC. Living APC arrival still causes the same
  narration, red objectives, and loss debrief. A dead wreck at the endpoint
  completes interception instead of also causing an arrival loss.
- **Handle guards:** missing/deleted objects count as zero health; a vanished
  player cannot trigger ambushes. Marker removal is skipped once the APC has
  been deleted. All valid-object thresholds remain unchanged.
- **Native path helper:** stock Lua has `GetPathPointCount` and indexed
  `GetDistance`, but does not expose `isAtEndOfPath`. Lua queries the last
  zero-based waypoint. The native helper's radius is **unknown** in the
  supplied source corpus. The provisional 25 m radius follows `bd03.lua` and
  is explicitly an approximation requiring stock-map testing. Missing/empty
  paths do not count as arrival.
- C++ color constants become stock Lua color strings. Native base-class
  bookkeeping and handle conversion are supplied by LuaMission.

## Validation

`Tests/test_bdmisn14.lua` passes under Lua 5.1 using mocked stock API calls.
Run from the repository root with `lua5.1 Tests/test_bdmisn14.lua`.
Coverage includes strict timer boundaries; wave composition; cloaked walkers
and their followers; disabled turrets; APC death and scavenger delay; all three
outcomes and their narration gates; simultaneous outcome precedence; one-shot
ambushes; missing handles; final waypoint indexing; and save/load during timers,
after ambushes, and while outcome narration is pending.

Engine gameplay has not been tested. Before integration, validate the APC's
arrival radius and route on the original map, strategic AI/AIP behavior,
objective display, cloaking, and engine serialization of active narration.
Mock tests establish script flow, not native AI/path equivalence.
