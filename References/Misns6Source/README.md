# misns6 source port

`Scripts/misns6.lua` ports `BZ1/from_bz2_dll_src/Misns6Mission.cpp` from
GrizzlyOne95/Battlezone_Source, blob `d00a5728a0a925755807683d6d09a234d3afe593`.
The C++ and empty guarded header here are byte-identical source snapshots,
including every comment, disabled statement, preprocessor branch, and native
serialization routine. Disabled gameplay fragments also remain beside their
corresponding Lua logic; they have not been activated.

The script implements Start, AddObject, Update, Save and Load using stock BZR
APIs and Lua 5.1. No EXU/OpenShim dependency or cooperative redesign is added.
Mission/map/resource files are not modified; selecting this Lua script for the
stock Soviet mission 6 map and shipping its existing assets remain integration
work. It expects the original map labels and paths.

## Preserved source behavior

- Three enemy `avmine` units register by nearest `m1`/`m2`/`m3` point 1 and
  initially go to `s1`/`s2`/`s3`. Only the first three of six native slots are
  polled, with a shared zero-based rotation over s1, s2, s3, m1, m2, m3.
- Polling begins strictly after ten seconds, then strictly after each three
  second deadline. A positive enemy-shot timestamp on a surviving miner
  launches the two-razor retaliation once. Health loss is not substituted.
- The AIP switches strictly after 120 seconds. The four proximity-wave
  deadlines stay at the native Load default of 99999: they are not armed
  during normal play. Their repeatable wave bodies and inconsistent old-time
  versus current-time cooldown arithmetic are retained for reconstruction.
- Six defenders, 20 starting scrap, both starting objectives, mine warning,
  artillery discovery, the five-unit silo counterattack, final objective
  marking, victory narration, success description and recycler failure all
  retain their source thresholds, order, priorities and delays.
- Unused beacon, base_suggestion, lost_message and extra miner slots survive.
  The original commented recycler spawn remains disabled.

## Adaptations and fixes

- `GetLastEnemyShot(h)` replaces the native object-pointer call directly.
  It is used by the project's existing `misn02b.lua` and
  `RuntimeEnhancements.lua`; no damage approximation is used.
- Lua cannot inspect `UnitProcess::USTATE1`. The port waits for
  `GetCurrentCommand(h) == AiCommand.NONE`. The native stock
  `MineLayerProcess::DoUState1` clears LAY_MINES when the task completes;
  active LAY_MINES commands are therefore not restarted. `IsBusy` cannot
  replace this state check because it reports producer activity. A transient
  NONE command while still in USTATE1 remains an engine-level parity limit
  to check in-game. The original #if 0 and active native state reads remain
  recorded inline and in the complete source snapshot.
  Supporting native implementation:
  `Battlezone_Source/BZ1/1.5/functions/0041/0041d04c_MineLayerProcess_DoUState1.c`
  and `0045/0045fb0b_IsBusy.c`. These are engine evidence, not alternate
  mission scripts; mission behavior comes exclusively from the supplied DLL
  source. Redux runtime testing must confirm the command lifecycle.
- Native `closest` is uninitialized if all three distances are >=99999.
  Lua safely falls back to slot zero; the source cutoff, ties, and normal
  intermediate Goto commands stay unchanged.
- Victory is latched rather than clearing `won` after scheduling success.
  This fixes repeated victory audio/success and same-frame recycler failure.
  Already-scheduled loss is final too. Victory still wins simultaneous
  objective/recycler destruction, waits for the same audio completion and
  schedules success with zero delay; failure still has a two-second delay.
  These changes affect contradictory/repeated endings, not mission progression.
- Invalid handle proximity checks return infinity. Missing defenders receive
  no object command. Present objects retain identical thresholds and orders.
- Explicit registration of newly spawned miners and duplicate callback
  suppression cover synchronous and delayed AddObject delivery. Save/Load
  preserves the complete table, including native handles, audio message and
  outcome latch; startup is not replayed after loading.

## Validation

Run `lua5.1 Tools/Test-Misns6.lua` and
`python Tools/Test-Misns6SourceParity.py` from the repository root.
The mock host covers mission decisions, source timer boundaries, callback
delivery, idle/active mining, waves, absent objects, endings, and reloads.
The source audit checks exact Git blob hashes plus mission assets and state.
These checks do not qualify real minelayer navigation/state transitions,
audio userdata restoration, or engine handle rebasing. In-game checks should
cover mine-laying completion/reassignment, save/load during mining and victory
audio, and the stock map's labels/paths and existing mission assets.
