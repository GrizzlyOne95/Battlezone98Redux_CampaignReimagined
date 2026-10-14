# misn13 DLL-source Lua port

`Scripts/misn13.lua` ports the NSDF mission directly from
[`BZ1/from_bz2_dll_src/Misn13Mission.cpp`](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/from_bz2_dll_src/Misn13Mission.cpp).
Target: stock Battlezone 98 Redux, Lua 5.1. The DLL port itself uses no community
mission implementation, EXU/OpenShim feature, or Campaign Reimagined helper; the
shared offline + 2-4 player co-op layer, the restored cut content and the Europa
weather that now sit on top of it live between `-- CR ... >>` / `<<` marker lines
and are documented in [MISN13_COOP.md](MISN13_COOP.md). The source-parity test
strips those regions, so everything below still describes the DLL port.
The API authority is `Docs/BZR_LUA_AGENT_REFERENCE.md`.

## Source and disabled content

`References/Misn13Source/` contains the byte-exact original `.cpp` and `.h`,
including native class declarations and save/load/handle-remapping methods.
Original Git blob IDs:

- C++: `9116778815ab02b25467a9427961ddb573cf626f`
- Header: `c51fcc6fc360ff0090613cdd0cb52cc307af5c53`

All 106 original C++ comments also appear verbatim in Lua long comments.
Disabled blocks remain disabled, including the initial communications-tower APC
attack, bomber retreat, replacement/reload using `avhraz`, alternate second-APC
handling, and bomber reload/reset combinations. All 149 original state fields
remain represented, including unused wave flags, handles, timers, and latches.

## Preserved mission behavior

- Opening briefing/objective, 10/40 starting pilots, 40/200 starting scrap,
  artillery escort, camera label, and turret positioning.
- First attack after five seconds; second staging wave five seconds later;
  normal AIP starts 60 seconds after staging and repeats every 240 seconds.
- One-shot Soviet scrap clamps to 150, 100, 50, and 0 after losing one through
  four silos. Every silo combination and the source's strict scrap thresholds
  are retained.
- Bomber AIP activation by player gun/communications towers, original capture
  order, target preferences, escort branch nesting, hold/release state, and
  reset after both tracked howitzers die.
- Silo defense below 95% health, two-second reaction delay, and 120-second
  repeated orders. Factory defense below 90% health, 40-scrap bonus, defensive
  AIP, turret deployment, and original coast-clear polling.
- Artillery starts its march after 900 seconds, stages when artillery4 reaches
  the split geyser, attacks scavengers after another 120 seconds, and warns
  once when tracked artillery shoots a player producer/scavenger.
- Scavenger replacement below 40 scrap at the original 60-second polls.
- Recycler loss schedules failure; enemy factory loss schedules victory.
  Both wait 15 seconds. Failure wins simultaneous destruction, and the outcome
  is emitted once. Execute order and strict `<` comparisons are retained.

## Adaptations and narrow fixes

The script explains each change at its implementation site:

1. `Get_Time`, native health/shooter access, and native camera naming become
   `GetTime`, `GetHealth`, `GetWhoShotMe`, and `SetObjectiveName`.
2. Lua state lives in one serializable table. `Save`/`Load` preserve every latch,
   timer, and handle, including the opaque shooter handle. `choke_bridged` is a
   boolean in Lua: native code declared it as a handle but only used it as a flag.
3. Map-object callbacks received before `Start` are replayed after Setup,
   matching native Setup-before-object-registration order. Loaded games use
   their restored handles and do not replay startup.
4. Invalid distance endpoints return infinity rather than reaching a wrong Lua
   overload or satisfying a proximity gate. Native thresholds for live units
   are unchanged. ODF registration accepts both basename and `.odf` forms.
5. A nil shooter is excluded as well as native zero, preventing absent artillery
   and an absent shooter from producing a false warning.
6. Scavenger swaps require a surviving original unit. The C++ non-null check
   could pass a destroyed handle as the spawn location. This prevents an invalid
   spawn or resurrection of killed units; survivors retain the original timer,
   resource threshold, replacement order, and commands.
7. The factory safety count requires a living factory. Factory destruction
   still schedules victory at the original end-of-update check; it no longer
   makes an invalid unit-count query earlier in that update.
8. The C++ statement `safe_time_check < Get_Time() + 60.0f;` discards its result.
   A bare comparison is invalid Lua, so it is retained as a comment and omitted
   from executable code. **The original actual behavior is preserved:** after
   the 120-second grace period, the mission checks every update until fewer
   than two team-1 units remain within 400 meters. Replacing `<` with `=` would
   sample once per minute, potentially delaying normal AI/bomber resumption by
   almost 60 seconds. This port deliberately avoids that gameplay change.

Other suspicious behaviors remain unchanged because changing them needs a
gameplay decision: first-captured dynamic slots are not recycled after death;
turret staging shares a timer with silo defense; turret2 tests key_geyser1 but
goes to key_geyser2; artillery4 alone gates artillery staging; `artil_lost` starts
true and is unused; tank4 receives a duplicate silo order; and bomber retargeting
and factory safety use one-shot latches. None are silently redesigned here.

The repository validator now recognizes every Lua long-comment delimiter,
including `--[=[...]=]`, so preserved native comments are not mistaken for Lua.
This also resolves its existing false `goto` report in misn07.

## Validation and integration

Run from the repository root:

```sh
python Tools/Test-Misn13SourceParity.py
lua5.1 Tools/Test-Misn13.lua
luac5.1 -p Scripts/misn13.lua
python Tools/Validate-CampaignRepository.py
```

The source audit checks exact original blobs, all comments and state fields,
107 ordered active asset/label strings, 159 ordered predicates, 253 ordered
state assignments, and API call counts with explicitly listed adaptations.
The offline Lua suite (`Test-Misn13.lua`) covers 242 checks with opaque userdata
handles, every silo combination, timer boundaries, AIP/bomber branches,
artillery, damaged/destroyed objects, callback timing, save/load, and outcomes.
Both suites are wired into campaign CI. Host checks do not run native AI,
pathfinding, audio, or engine serialization.

The co-op map (`Missions/misn13.bzn`, built by `Tools/Build-CoopMap.py --mission misn13`)
keeps every original map label, path, ODF, AIP, voice file and debriefing from the
matching stock content; see MISN13_COOP.md for what the co-op layer changes (the CCA on
team 5, the whole-base win, the restored waves 2-4, the unused misn1301 line).

In-game validation remains outstanding: load the original mission through
LuaMission, verify the opening and two early waves, trigger bomber/factory/silo
responses, observe the 15-minute artillery sequence, save/reload during each
phase, and confirm both debriefings. Check dead lead artillery and rebuilt
producer/bomber behavior against the documented original latches before making
any separate gameplay fixes.
