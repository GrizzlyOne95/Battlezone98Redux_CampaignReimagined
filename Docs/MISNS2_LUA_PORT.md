# misns2 Lua 5.1 port

`Scripts/misns2.lua` ports the native BZ1 DLL mission from
`Battlezone_Source/BZ1/from_bz2_dll_src/Misns2Mission.cpp` to stock Battlezone 98
Redux Lua 5.1. The mission behavior comes from that C++ source. The port does not
require EXU, OpenShim, aiCore or a community mission implementation.

## Source and preserved content

The complete C++ and header are archived in `References/Misns2Source/`, including
class members, native save/load code and every original comment. The upstream
Git blob IDs are `4b5fbd742130d38863281fb790edca869f4cc86d` for the C++ and
`955de033c629752f002188670f6b117301eb8af8` for the header.

All 22 comments in Setup/AddObject/Execute remain at the corresponding Lua
locations. Disabled C++ is retained verbatim inside Lua long comments. This
includes the alternate opening camera sequence, the timed platoon cinematic,
extra first-wave fighters, nav-mine lookup, nav5 cutoff attackers (including the
original `bdcut0ff2` typo), the two extra final-wave tanks, and the first camera
network. These remain disabled. All 159 original save fields are represented,
including dormant camera/nav state; Lua adds one outcome-scheduling latch.

The active port retains both cinematics, all five waves and their alternate
triggers, the nineteen mines, cutoff ambush, second camera network, camera-loss
patrol timer, both scout responses, platoon variants, objective recoloring,
arrival radios, victory radio trio, all 44 retreat calls and both debriefs.
Threshold comparisons and source statement order are preserved.

## Narrow fixes

The fixes are explained beside the affected Lua code, with original spellings
retained for review. They correct faulty edge cases; the normal convoy route,
spawn rosters, commands, thresholds, cinematics and audio-gated endings retain
their source behavior.

| Source problem | Lua correction | Effect on the intended flow |
| --- | --- | --- |
| The `bdnet4` cutoff branch creates wave 4 (`bd12`–`bd14` at `bdsp4`) but sets `wave3gone`. | Set `wave4gone`. | Keeps that ambush's roster and orders; prevents a later wave 4 trigger from overwriting its handles and leaves wave 3 eligible. This intentionally changes the broken bookkeeping. |
| Both scout checks compare `nine` (enemy nearest `pat2`) to `pat1`; the duplicate second check cannot run after the first latches wave 3. | First check pairs `nine`/`pat2`; second pairs `ten`/`pat1`. | Either scout can trigger the existing 50 m response. Original first/second branch orders and the shared wave 3 latch are retained. |
| A destroyed APC wreck can still satisfy an arrival distance, and latched arrivals can permit success after an APC dies. | Require living APCs for arrivals and give mission failure precedence over victory and success scheduling. | Enforces escorting all three APCs without changing healthy arrivals, radio timing or debrief selection. Death during the victory radio queue now correctly fails. |
| `FailMission` and `SucceedMission` repeat every update after audio completes. | Save `outcomeSent` and issue the ending once. | Uses the same completion time and debrief, without repeated requests or competing endings. |
| Missing/removed handles can reach distance, nearest-enemy, naming and marker calls. | Use guarded helpers and skip calls on absent objects. | Missing objects cannot spuriously trigger proximity conditions; valid-object calculations and marker/name behavior are unchanged. |

Several suspicious details remain faithful because their intended replacement is
uncertain: the early nearest-vehicle wave 3/4 branches omit explicit attack
orders; early wave 4 has a tank where its APC branch has a second artillery unit;
only the APC-triggered wave 3 schedules the artillery warning and nineteen mines;
the proximity platoon omits explicit attack orders; the patrol uses `svfigh` on
team 2; and `playerfound` is initialized but never assigned. The fixed startup
`svtank0_wingman` player-object reference also remains as authored.

`GetNearestVehicle(path, 1)` preserves native **path point 1**, not a team
filter. The existing explicit team tests remain intact. No additional filters
are added to wave 2 or camera-network proximity checks.

## Save/load and validation

`Save()` returns the mission table. `Load(state)` restores it without rerunning
Setup, spawning craft, replaying audio or restarting cameras. BZR handles native
game-handle serialization/remapping. Host checks simulate restoring the script
during both cinematics, a patrol and an ending; actual engine save/load still
needs an in-game test.

Run from the repository root:

```text
lua5.1 Tools/Test-Misns2.lua
python Tools/Test-Misns2Source.py
```

The Lua checks cover startup, strict timer/distance boundaries, normal/skipped
cinematics, every wave branch, all nineteen mines, both networks, each of the
eight possible camera losses, both scouts, platoon fallback, all 44 retreat
handles, destroyed/missing objects, objective colors, audio-gated outcomes and
save/load continuation. The source audit checks all in-place comments, all
159 original save fields and the ordered arguments of 325 native calls,
including all 104 active spawn sites and 44 retreat sites.

In-game validation remains outstanding. Check both route choices, APC navigation
and player orders, camera-path targeting and cancellation, queued radio timing,
artillery behavior, mine placement, and save/load through both cinematics and
the camera-loss patrol timer. The script expects the original `misns2` map labels,
paths, ODFs, OTFs, WAVs and debrief assets. This change adds the port and review
material; map wiring, shipping-lock changes and deployment are separate work.
