# misn02b / misn03 / misn04 / misn05 source audit

Audited the existing Lua ports at CR main commit
`6636e74086d1587a6cf129b04b2d8d04ea997a99` against the native DLL missions in
[`Battlezone_Source/BZ1/from_bz2_dll_src`](https://github.com/GrizzlyOne95/Battlezone_Source/tree/main/BZ1/from_bz2_dll_src).
The review treats the existing QOL, difficulty, AI, weather and co-op changes as
intentional. Differences alone are not omissions, and this is not a claim of
strict native gameplay equivalence.

All major active mission phases are represented. The native escort arrival/stop
hooks in misn03 are absent from active Lua, which instead assigns the escorts to
the early-spawned transports. That appears consistent with the QOL escort role;
their original block is now retained as an inactive alternative next to the
current orders, without interrupting those escorts. The comparison also found
missing historical comments/cut code and concrete failures in target selection, order
dispatch, patrol transitions, one-shot spawning, cinematic progression and
terminal result handling. Those are corrected with `PORT FIX` explanations in
the scripts. Healthy progression keeps the existing QOL rules and cinematics.

## Source identity and phase coverage

`Misn02Mission.cpp` explicitly says that `misn02b.msn` uses
**`Tran05Mission.cpp`**. Comparing misn02b against the tiny Misn02 stub would miss
the actual mission. That dispatch stub is included in the source archive.

| Lua port | Native implementation | Active mission pieces checked |
| --- | --- | --- |
| misn02b | Tran05Mission.cpp | Intro shots; initial vehicle objective; scrap discovery/patrol; second scrap-field waves; shot-triggered retreat; second scavenger rescue; regeneration; final ambush; audio-delayed loss and victory. |
| misn03 | Misn03Mission.cpp | Opening assault/retreat; turret count; timed defense waves; both scavenger hunts; escort/APC reinforcements; combat-clear evacuation trigger; CCA base film; transport/turret departure; transport ambush; launch-pad return; repeated warnings; demolition outro; tower, array, transport and timeout losses. |
| misn04 | Misn04Mission.cpp | Relic search/discovery/recon; all four relic camera/patrol variants; survey and guard forces; tug acquisition/delivery; CCA theft and failure film; search warnings; five base waves and arrival/death messages; CCA-base clear and retreat branches; relic/recycler losses; audio-delayed closing film. |
| misn05 | Misn05Mission.cpp | Random harassment; approach/recon/order delays; all four shuffled deployment waves; turret-to-patrol transitions; base attack; final razor approach; proximity attack/warning; four supplemental waves; CCA-recycler destruction branch; residual attacker checks; recycler/factory losses; victory sequence. |

The 23 `path_1` through `path_23` mines are still represented by the Lua loop.
Its persistent static minefield replaces the DLL's proximity-based build/remove
system intentionally; the complete original implementation is archived. Dynamic
path generation in misn04 likewise covers the native numbered relic paths and
cameras; absence of individual literal strings does not mean those variants
were lost.

## Corrections

| Mission | Before | Correction and flow boundary |
| --- | --- | --- |
| misn02b | The outer `bscav ~= nil` Lua guard swallowed the DLL's independent base/recycler loss clauses. | Restore native Boolean grouping so base/recycler destruction also fails before the first scavenger is tracked. Keep unit-loss gating, audio and debrief timing. |
| misn02b | Loss and rescue/win could run in one update and replace the shared terminal audio; a settled win could subsequently become a loss. | Give the first terminal result precedence. A pending loss cannot rescue or win; healthy convoy return and repairs are unchanged. |
| misn03 | The DLL and port's second scavenger-hunt fallback tested **not alive**. | Target a living scav2 when scav1 is gone. Keep the existing wave, command priority, hunt latch and phase timing. |
| misn03 | Stock solar2-only failure contradicted the QOL rule accepting enough surviving backup arrays. | Require an insufficient living-array count before that failure branch. Retain the native failure audio/debrief when insufficient, and the existing difficulty-dependent counts. |
| misn03 | A tower destroyed after evacuation began prevented the outro's attack/destruction latches from advancing. Dead prop1 also blocked later distance gates despite an earlier QOL dead-prop fallback. | Continue the same visual stages with the tower already destroyed; extend the dead-prop fallback through the later shots. Keep the seven-second destruction delay, current healthy-prop distance thresholds, six-second closing shot and final camera-completion success gate. |
| misn04 | Persistent secure latches could start victory on an objective-loss frame or while theft/search failure audio was pending. | Require living relic/recycler and no pending failure before entering victory. The healthy secure gates, audio completion and existing twenty-second end film remain. |
| misn05 | Wave 1 armed wave-2 patrol checks, which could immediately consume themselves on absent wave-2 handles. | Arm wave-2 checks when wave 2 spawns. Both shuffled arrival orders work; keep units, shuffle times, QOL 40m arrival threshold and patrol path. |
| misn05 | The existing correction from native `platoonhere > time` to `< time` left `go` permanently true, respawning the main assault after every casualty clear and resetting reinforcements. | Consume `go` on the scheduled main spawn. Keep the existing delay, unit scaling and 15/55/110/160-second supplemental timetable. Recover this latch from existing handles or an armed reinforcement timer in old saves. |
| misn05 | Lua `CheckAndAttack(a) or CheckAndAttack(b)` stopped evaluating after the first eligible razor. The DLL's shared latch also stranded later arrivals; anonymous difficulty extras had no corresponding handoff. | Issue independent orders and persist progress for every main-assault survivor, including extras. Keep the QOL 60m destinations and three-second poll. This restores the assault's intended orders without adding waves or changing phase gates. Old saves seed named handles and recheck a previously latched partial order. |
| misn05 | Lua moved the failure checks after victory, allowing enemy clearance to win while the factory/recycler died, or after failure was already pending. | Restore failure precedence with living-objective/no-pending-loss guards. Keep the fleet cinematic, commander reveal and success timing. |
| misn05 | Native display-name `SetName` became `SetLabel`, changing the `cam1` lookup identity instead of its HUD name. | Use `SetObjectiveName` at both sites. Keep the same camera object and stable map label for rehydration. |

## Reconstructable cut content

Each script now ends with an **inactive C++ comment ledger**, preserving every
original comment token, in order, with its native file and line number. No
fragment is silently translated into active Lua. Some cut ideas already appear
in active QOL additions; their original historical status is still preserved.
Complete source copies retain surrounding conditions, declarations and ordering.

| Mission | Preserved comment tokens | Examples of historical material now retained |
| --- | ---: | --- |
| misn02b | 42 | Alternate player/scout handles; intro `misn0232.wav`; disabled patrol attack; `misn0226.wav` victory line and accompanying briefing text. |
| misn03 | 87 | Third opening fighter and alternate retreat; extra defense units; unused build2 handle; `misn0313.wav` escort calls; prop6/prop7 with `fighter2_spawn`, `fighter3_spawn` and `cool_path2`; alternate demolition timer. |
| misn04 | 84 | Four cut preplaced wingmen; extra guards/survey/wave units; ally-driven relic discovery with `misn0407.wav` and `OBJECT`; alternate camera finish; `misn0402.otf` display; audio completion latches; nearest-enemy safety gate. |
| misn05 | 64 | Extra random/wave units; all extra razor destination branches; disabled recon cinematic; disabled `misn0515.wav` line; alternate early victory check; aw1a/aw3a/aw7a spawns and orders; original timer annotations. |

The replaced active misn03 support block is retained in full at the relevant
location: native `Goto(help1/help2, solar2)`, 75m stop checks and player-nearby
re-tasking. The evidence establishes the difference; it cannot establish whether
every removed hook was consciously intended. Keeping the current transport
escort orders is the conservative interpretation of the requested QOL scope.

The existing misn02b `misn0224.wav` to `misn0201.wav` intro replacement is kept,
with the native reference preserved. The existing misn03 early transport spawn,
recycler follow/undeploy behavior, alternate-array objectives, co-op gates and
outro swarm are kept. The misn04 pilot-mode, weather and camera-stack repairs
are kept. The misn05 static mines, difficulty registries, restored recon film,
and fleet/commander ending are kept.

## Verbatim evidence

`References/EarlyMissionSources/` retains exact original bytes, including CRLF.
These Git blob hashes are pinned by the automated source checks:

| Source file | Git blob SHA-1 |
| --- | --- |
| Misn02Mission.cpp | `7afb97a4628dfcd9634626ca1a43e5e00e2e75f1` |
| Tran05Mission.cpp | `f318d388fb7976a40652c88b0fb375dcc18fc93a` |
| Tran05Mission.h | `8b479b59bcdb5fe02e64a11a2270f29b69575968` |
| Misn03Mission.cpp | `9aa778f241bfd2fa6d4939d7db4da1bdba3821e5` |
| Misn03Mission.h | `2c5d98f54585a63d6fcd9b1a18083cc0a4b625b0` |
| Misn04Mission.cpp | `9cbc6c519f8cdec0759f07de348cd47de20947c5` |
| Misn05Mission.cpp | `e2c612866d09c144356a20cf6c96a7ecf8c1d81f` |
| Misn05Mission.h | `53477ae443c46897ef0754c45b48763b5d3bfeed` |

## Validation and limits

Run from the repository root:

```sh
lua5.1 Tools/Test-EarlyMissionFlow.lua
python Tools/Test-EarlyMissionSourceAudit.py
python Tools/Test-Misn03CoopContract.py
```

Lua 5.1.5 passes **117 focused flow checks** using actual script blocks and
mocked engine calls, and all four complete scripts compile under Lua 5.1.
Python passes **501 source preservation/coverage checks**: exact archive hashes,
all 277 original comment tokens and their line references, named phases, active
audio/objective/debrief/AIP references with the explicit intro exception, all
23 static mine locations, the camera name mapping, and the replaced native
escort block with current QOL orders. The workflow runs both
new suites alongside existing repository checks. The validator now recognizes
Lua long-comment delimiters with equals signs, so inactive C++ is excluded from
Lua-syntax diagnostics. The existing misn03 co-op test likewise ignores inactive
comments before checking enemy teams. This same validator repair also appears in the separate
misn09 source-port PR.

These tests do not execute complete mission updates inside BZR, establish visual
camera fidelity, or qualify EXU AI, weather, pathfinding, multiplayer or actual
engine save serialization. In-game follow-up should exercise both scavenger
routes, backup-array losses on each difficulty, the normal and dead-prop outro,
all relic variants/theft, both shuffled turret-wave orders, staggered razor
arrival including extras, old/new saves during the assault, and simultaneous
enemy clearance/objective destruction. No merge, deployment or release is
performed by this audit.
