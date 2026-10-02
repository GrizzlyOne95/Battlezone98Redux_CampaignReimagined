# misn10 source-faithful Lua 5.1 port

`Scripts/misn10.lua` ports `Setup`, `AddObject`, and `Execute` from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misn10Mission.cpp`,
blob `1e000fdc8e95fa7c58009b249031bb420c789980`. It targets stock single-player
Battlezone 98 Redux, with no EXU, OpenShim, aiCore, or campaign helper dependency.
The complete C++ and include-guard-only header are archived byte for byte in
`References/Misn10Source/`; their original Git blob hashes are checked by the
provenance test. No community mission or existing Lua port supplied the logic.

## Preserved behavior

- Original briefing, objective, nearby relic marker, three beacon names, starting
  scrap/pilots, and `misn10.aip` to `misn10a.aip` production transition.
- Two relic escort fighters, two forward turrets, one base turret, and three
  artillery placements; original staggered 19/20/21/22/23-second checks and
  three-second polling, strict proximity thresholds, and command priorities.
- All seven relic-location/outbound/pickup/return branches, including the direct
  recycler return for position 2 and route 1's priority-0 tank follow orders.
- Player/CCA pickup detection, tug-loss recovery, CCA seizure warning, pursuit
  by all nine eligible units, and the original interrupted-pickup wait branches.
- Initial bombardment after 180 seconds, later 150-second intervals, and the
  200-meter player-versus-geyser targeting decision.
- The relic's 100 raw health gain on each scheduled second, with no catch-up loop.
- Original outcome ordering: player delivery, CCA delivery, relic destruction,
  then Utah destruction. Each schedules its original debrief after 15 seconds.
  Other simulation logic continues during that delay, as in the source.
- All 66 booleans, 13 floats, 31 handles, and the unused integer, including state
  for cut content. Save/Load uses BZR's serializable state table without rerunning
  Setup, spawning objects, or replaying production/briefing commands.

| Nearest geyser | Outbound path | CCA return |
| --- | --- | --- |
| 1 | `relic_path1` | `main_return_path` |
| 2 | `relic_path1` | Soviet recycler handle |
| 3 | `attack_path_central` | `lsouth_return_path` |
| 4 | `attack_path_central` | `main_return_path` |
| 5 | `attack_path_south` | `ssouth_return_path` |
| 6 | `attack_path_north` | `main_return_path` |
| 7 | `attack_path_south` | `msouth_return_path` |

## Cut code

All seven gameplay block comments and eight standalone commented code lines
remain verbatim and inactive at their corresponding locations in the Lua file.
The archive also preserves every declaration/serialization comment and all
original whitespace. Disabled experiments include alternative cargo tracking,
earthquakes, tank stops, the `misn10b.aip` transition, temporary relic creation,
timer assignments, and the manual 30-second CCA tug rebuild loop.

These are retained as C++, not enabled Lua. Reconstruction still needs a design
decision and map/assets verification. Dormant variables are retained as well.

## BZR adaptations and documented fixes

- `Get_Time` becomes `GetTime`; native `SetName` and `AddHealth` become the stock
  Lua functions. Null handles become nil. A safe distance helper returns infinity
  for invalid handle operands, keeping them outside proximity triggers.
- ODF admission accepts bare names and `.odf` names, without introducing a team
  filter. `SetAIControl(2, true)` runs at script initialization to supply the
  native mission's strategic AI before the unsafe late-initialization boundary.
- **Own-carrier pursuit:** the source checks only `tugger != 0`, even after
  assigning the CCA carrier to `tugger`. Priority-1 attacks can target same-team
  objects. The Lua pursuit requires a living team-1 carrier and `sav_secure`.
  Intended player pickup pursuit keeps all original orders/priorities; CCA pickup
  follows its original haul/return flow. This also excludes nil, which compares
  unequal to numeric zero in Lua.
- **Replacement tracking:** source admission tests only NULL, leaving dead
  handles unable to admit replacements. Lua admits an AIP-built unit into the
  first dead/vacant matching slot and resets its prior command state. Cached
  handle comparisons in DeleteObject avoid unsafe destroyed-object queries.
  A replacement can arrive before Update; carrier-loss recovery therefore also
  runs when that slot is cleared/replaced. The third turret's stale underway flag
  and surviving tanks' old carrier-follow flags are cleared. Living-unit
  admission order and production timing are unchanged; no script-built units are
  introduced. Duplicate notifications cannot occupy multiple slots.
- **Equal nearest distances:** every source comparison is strict, but
  `got_position` is set even if none wins. The Lua keeps the original seven
  comparisons, then resolves a tie with the lowest numbered finite minimum.
  Unique minima retain their exact original routes. Missing references leave
  the route uncommitted for a later retry instead of recording an empty route.

Other historical quirks remain: `relic_free` is separate from `sav_free`,
position 4 retains its extra seizure guard, route 1 retains its asymmetrical
escort priority, and player cargo release is detected by carrier death rather
than adding a new voluntary-drop mechanic. No cut content is activated.

Repository validation also now recognizes matching equals-delimited Lua long
comments. Previously it treated preserved C++ inside misn07's `--[==[...]==]`
comments as live Lua and falsely rejected its commented word `goto`.

## Validation and integration

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn10.lua
python Tools/Test-Misn10SourceParity.py
python Tools/Validate-CampaignRepository.py
```

The mock-host suite passes 162 checks under Lua 5.1. It covers all seven outbound,
early/fallback pickup and return routes; ownership/pursuit; wait branches; exact
distance/timer boundaries; production stages; all tracked replacement types;
between-update carrier replacement; bombardment/healing; Save/Load; every ending
and source precedence; invalid handles; and cut content remaining disabled.
The provenance suite passes 24 checks for byte-identical source, commented code,
all 111 state fields, and every active native string literal. Both run in campaign
CI. These checks verify scripted behavior, not native AI movement or save-file
handle rebasing in the game.

In-game qualification is outstanding. At the inspected base revision
`6636e74086d1587a6cf129b04b2d8d04ea997a99`, no `Missions/misn10` map bundle,
mission AIPs, or mission WAV/OTF/debrief files were present in this repository;
its `Text/misn10*.txt` files are voice transcripts. Supply the original mission
bundle/assets or confirm the stock game supplies them, verify all labels/paths,
and bind its mission class to LuaMission before playing. Check strategic AI,
lava-safe routing, attachment/drop behavior, and a real mid-haul save/load.

No mission map, shipping lock, deployment, or release configuration is changed.
This branch is a source-port checkpoint, not a deployed mission.
