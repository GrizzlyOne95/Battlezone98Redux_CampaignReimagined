# EvolveMission Lua port

`Scripts/evolve.lua` ports `BZ1/from_bz2_dll_src/evolvemission.cpp` from
GrizzlyOne95/Battlezone_Source, source blob
`e53413c1824f2dd4a38de8912e4d6ebe6067707e`, to standalone stock BZR Lua 5.1.
The complete original C++ is retained in a disabled long comment at the end
of the Lua file, including all comments, native serialization, and file I/O.

## Preserved behavior

- Pilot, soldier, sniper, fighter, light tank, tank, razor, walker, and heavy
  tank waves, with the original ODFs and three numbered spawn points.
- Immediate initial pilot wave (the table's initial five-second wait is unused
  by the native code), immediate soldier/sniper transitions, the first handle
  change gate before fighters, then 30 seconds for fighters and 10 seconds for
  the other vehicle waves. Comparisons remain strictly `< GetTime()`.
- Vehicle-only repetition at zero-based round 3, increasing from one to twenty
  attackers per spawn point (three to sixty attackers per wave).
- Original twelve friendly pickups, initial time-1 spawn threshold, 30-second
  replenishment, and four enemy cover attackers unlocked at round 4. Cover
  attackers remain unlocked through wave wrap and give one point per death.
- Scrap HUD as score/best-so-far, ten pilots, cockpit count-up, retargeting
  order, scrap-object cleanup, death grace period and two-second ending delay.
- Save/Load retains timers, handles, scored deaths, unlocked items, and score.
  The native empty AddObject handler remains empty.

## Corrections

| Native problem | Lua correction and gameplay effect |
| --- | --- |
| All floats, including deadTimer, start at 99999. A death before the first living update can wait hours. | Initialize deadTimer to zero, enabling the already intended two-second grace period. Living-player flow is unchanged. |
| The `alldead = 0` else belongs to `if (!diedAttackers[i])`, not `if (!IsAlive(...))`. Live unscored attackers do not block progression, while scored deaths do. | Only living attackers block a wave clear; dead slots score once. This deliberately corrects broken progression and restores clear-wave flow. Wave data and waits remain unchanged. |
| Retargeting and removal can reference dead/removed handles. | Guard commands/removals with IsValid; successful live actors receive the same orders. |
| Native mutates static spawnitems.initround when an item unlocks. That mutation is absent from native saved state and can leak into a new mission. | Store unlocks in serializable mission state, keeping the intended unlock through wave wraps/reloads and resetting on Start. |
| Native removes objects while traversing a native list, restarting traversal after each deletion. | Collect matching npscr ODF handles through AllObjects and remove afterward, avoiding mutation of a live Lua iterator. |

## Stock API limits and integration

This is a script port, not a playable mission package. Configure the original
map to use LuaMission and `evolve.lua`; original paths, ODFs, and debrief assets
must be available. No mission configuration or shipping list is changed here.

Stock Lua does not expose the native `emission.bst` file access or
`CheckCheater(UserProfile.playOption)`. This port uses the native missing-file
baseline of zero score/time, maintains best-so-far during the run, and does not
read/write or certify persistent records. The comparison selecting sammywin
versus sammylse therefore reflects that zero baseline and cannot reproduce
record comparisons or cheat disqualification against an existing native file.

Stock SucceedMission accepts time and filename, without the third native
values argument. Both original filenames are retained. The six result values
are stored as `resultValues` in mission state and shown in one short objective
before the exit. Parameter substitution inside the original debriefs remains
unsupported; verify those assets in-game before packaging. An explicit native
extension would be needed for full score-file, cheat, and debrief parity.

The native `invehicle` flag is a permanent latch after *any* player handle
change, not a query of the player's current craft. That behavior is preserved.
There is no strategic AI, project helper dependency, or multiplayer support.

## Validation

`Tools/Test-Evolve.lua` runs with Lua 5.1 and checks partial/all wave clears,
one-time scoring, exact timer boundaries, handle-change gating, wave ordering,
cover unlock/respawn, save/load, all vehicle repetitions through the spawn cap,
retargeting, scrap filtering, early death, revival, and single ending dispatch.
It currently passes 69 assertions under the Lua 5.1 runtime supplied by Lupa.
Engine pathing, spawn overlap at high difficulty, original assets, score HUD
capacity, and debrief rendering still require Battlezone 98 Redux testing.
