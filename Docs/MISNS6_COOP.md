# Mission S6 co-op: Clear the Path (misns6)

Shared offline / 2-4 player co-op port of the Soviet mission `misns6` (CCA 06). The Soviet force must fight up
a mined canyon, find the Black Dog artillery, hold off two counter-attacks and destroy the Black Dog command
centre (`abcafe8_i76building`) without losing the recycler. One `Missions/misns6cr.bzn` and one
`Scripts/misns6cr.lua` serve both modes. The faithful DLL port underneath is `Scripts/misns6.lua` (archived source in
`References/Misns6Source/`); the shared runtime is [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) and
`misns1cr.lua` / `MISNS1_COOP.md` is the template.
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns6cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns6.lua` (`Tools/Test-Misns6CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the weather beats. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime, including the CCA mission's NSDF-to-Black-Dog ODF remap. |
| `Scripts/CRTitanSitesS6.lua`, `Scripts/CRTitanWeather.lua` | Titan weather director and the generated methane-pool sites for this map (160 anchors). |
| `ODF/crns6.aip` | The Black Dog version of stock `misns6.aip`; all opposing unit entries use Black Dog ODFs. |
| `Missions/misns6cr.bzn` | Map roster; authored NSDF vehicles are switched to Black Dog ODFs while their labels stay intact. |
| `Missions/misns6cr.vxt`, `misns6.{hg2,lgt,mat,trn}` | Terrain and map companions. |
| `Tools/Misns6Fixture.lua`, `Test-Misns6Coop.lua`, `Test-Misns6CoopSourceParity.py`, `Test-Misns6CoopContract.py` | Multi-peer fixture and tests. `Test-Misns6.lua` / `Test-Misns6SourceParity.py` still cover the faithful port, unchanged. No presentation test: the mission has no cameras and no cutscene. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Soviet recycler (`svrecy0_recycler`), wingman tank, camera pod and three walkers stay on team 1, shared and host-run. Extra starting recyclers are disabled. |
| 5 | The Black Dogs (the authored team 2: turrets, towers, power plants, hangar, silos, howitzers, command centre, and everything the body builds). The body still says team 2; the layer maps `BuildObject(..., 2, ...)` and `SetAIP(name)` to team 5, and `GetTeamNum` answers 2 for a team-5 object so the body's mine-layer filter still matches. |
| 7 | Support (allied to humans; unused here). |

`abcafe8_i76building` is team 5 with perceived team 1 (a Black Dog building disguised as a Soviet one). The
disguise is kept; the contract test asserts it.

Only the authority (host, or the offline player) runs the body; guests only present. The engine's `AddObject`
callback also fires on guests, so the layer's `AddObject` wrapper runs the body's mine-layer registration on the
authority only. `SetAIControl(5, true)` runs once at chunk load; `SetAIP` is called only from the body's `Update`,
120 s into the mission, with team 5.

## What is wrapped

`BuildObject` (Spawn), `IsAlive`, `SetScrap`, `SetAIP`, `Goto`, `Attack`, `Defend`, `AudioMessage`,
`ClearObjectives`, `AddObjective`, `SetObjectiveOn`, `SucceedMission`, `FailMission`, `GetPlayerHandle`, plus
mission-specific shadows of `IsValid`, `GetDistance`, `GetTeamNum` and `IsAudioMessageDone`.

## Humans as one trigger

The body calls `GetPlayerHandle()` once per frame and measures from it. The layer returns the runtime's `PLAYERS`
token and teaches the body's helpers about it:

- `IsValid(token)` is true, so the body's `Exists` helper accepts it.
- `GetDistance(token, x[, point])` and `GetDistance(x, token[, point])` answer the **nearest** human to the path or
  object (no reach gate in this body, so `farthestTargets` is empty). A human with no live ship is ignored; no
  live human is infinitely far. The runtime's `WrapDistance` only handles two arguments; the body also uses the
  path-point form `GetDistance(h, "m1", 1)`, so the mission wraps it itself.
- `Attack(raider, token)` (the two miner-raid raiders) targets the human nearest the raid entry (`counter1`) as a
  real handle, because a ticket's replayed order needs a handle.

Triggers that fire for ANY human: the minefield warning (within 250 m of `m1`/`m2`/`m3`, `misns602`), the
artillery find (within 200 m of either howitzer, `misns605`), the silo counter-attack (within 400 m of the far
silo, `misns603`) and the last-objective switch (within 300 m of the command centre).

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `bvraz`, `bvltnk`, `bvtank`, `bvrckt` (`scaledOdfs`). They become *tickets*: the body gets a
negative request id, the runtime builds the unit on the next frame at the authored path and replays the body's
orders (`Attack`, `Goto counter_attack_path`). The mine layers (`avmine`) and the guns are never scaled.

Events that get extras (one `BeginEvent()` each, in `-- CR co-op scaling >>` regions): the miner raid (first of the
two `bvraz`) and the silo counter-attack (first `bvltnk` of the five). The first scaled unit of the event is
mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders:

| Humans | Extras per event | Raiders | Counter-attack |
| --- | --- | --- | --- |
| 1 (offline) | 0 | 2 | 5 |
| 2 or 3 | 1 | 3 | 6 |
| 4 | 2 | 4 | 7 |

Cap: at most 12 live scaled units; extras are the only requests dropped for it. Scrap: team 1's starting scrap is
`20 + 10 per guest`.

No pop-in: a scripted unit is never built within 460 m of any human. An entry that is a map path is checked; if a
human is near it the next authored approach in `fallbackEntries` (`counter3`, `counter4`, `counter2`, `counter5`)
is tried, else the request waits (saved in `M.crcca`). The raid entry `counter1` lies about 470 m north of the mine
rows (a player shooting a layer is often within 460 m of it) and `counter_attack` is 370 m from the command centre,
so a player already at the objective fails the test: the wave then arrives at a fallback point or waits instead of
popping in beside them.

## Timer, win and loss

- Win: destroying `abcafe8_i76building` -> `misns609` -> `SucceedMission(..., "misns6w1.des")` once, on every peer.
  Loss: the recycler dies -> `FailMission(GetTime() + 2, "misns6l1.des")`. `FailMission` is ignored once `won` has latched.
- Out of lives (every human out): the mission fails for everyone with `misns6l1.des`. Leader departs: guests fail.
- Audio: every line the body names has subtitles in `Text/` (`misns601/602/603/605/609`); `audioSubstitute` is empty.

## Weather: Titan [owner decision]

`CRTitanWeather` with `CRTitanSitesS6`: `weather = {module, sites, startLevel = 1, targetLevel = 2, environment =
{nativeBaseline = true}, ops = {"TitanState", "TitanRoll"}}`. A missing module or sites file disables weather, never
the mission. The director runs on the authority and streams `TitanState`/`TitanRoll` to guests. Beats (each fires once):

| Beat | Trigger | Level |
| --- | --- | --- |
| Minefield | `warning` (a human reaches the mines) or `counter1` (a layer was shot, raid launched) | 3 Drizzle |
| Shroud | `counter_attack` (silo assault) or `last_objective` (a human nears the command centre) | 4 Shroud |
| Easing | `won` | 2 Hazy |

## Restored content [owner decision 2026-11-01]

**No cut block is restored.** Each cut or dormant block was checked against the shipped map and the no-pop-in rule;
none is coherent with both. The only `RESTORED_*` flag, `RESTORED_VOICE_LINES`, covers six unused shipped voice lines.
Unused shipped voice lines [owner decision 2026-11-01; widened 2026-11-11 to 607, 610, 611, 612 and 813]: the wav and `Text/misns6NN.txt` transcript ship in the game but the DLL never plays them. Each plays once through the CR layer (`AudioMessage`: replicated to co-op guests, queued behind a line still playing), is latched in `M.crcca.r` (kept by Save/Load) and sits behind `RESTORED_VOICE_LINES`.

| Line | Transcript | Trigger | Why it fits |
| --- | --- | --- | --- |
| `misns606` | "We've cleared the artillery. Continue to push forward." | Both howitzers the body holds (`avartl3_howitzer`, `avartl4_howitzer`, handles `art1`/`art2`) have been seen alive and are now both destroyed; once, not after the mission is won, lost or scheduled | The two howitzers are the artillery that `misns605` points out. |
| `misns607` | "The Black Dogs are well entrenched ahead. Hide, you dogs!" | A human first comes within 500 m of a live command-centre defender turret (`defender1`/`defender2`, handles `tur3`/`tur4`) before the body's 300 m last-objective trigger; once, not after won, lost or scheduled | The two turrets guard `abcafe8_i76building`; the line warns of the entrenched final defence. |
| `misns610` | "Our attack outpost is under heavy attack!" | The recycler `svrecy0_recycler` (the loss condition) first drops below half health; once, not after won, lost or scheduled | The recycler is the attack outpost the players must protect. |
| `misns813` (shipped with mission 8) | "This does not look good, comrades." | 10 s after `misns610`, if the recycler is still alive and the mission is undecided; dropped otherwise | Follow-up pressure line; a stock CCA voice. |
| `misns611` | "You've lost the Grozny. Pull our forces back. ... I fear what Karnov will do to you ..." (about 10.8 s) | The recycler loss: the body's `FailMission(GetTime() + 2.0, "misns6l1.des")` is shadowed in the CR layer, plays the line and fails 11 s after the loss instead of 2 s, so the line finishes | Its transcript is this mission's loss. |
| `misns612` | "I recognize this is a good strategic position. Advance our mobile factories. ..." | The body's last-objective trigger first fires (a human within 300 m of the command centre `abcafe8_i76building`); once, not after won, lost or scheduled | Marks the push onto the final objective. |

`misns604` ("The Black Dogs are counterattacking from the southeast.") was considered for the miner-shot raid and
skipped: in `misns6cr.bzn` the raiders are built at `counter1` (2263, 99498) and `counter2` (1229, 100132) while the
players start near (2500, 98600) and the minefield is at x 1988-2931, z 99030-99100, so the raid arrives from the north
(north-north-west and west), not the south-east. Playing it would announce the wrong direction.

| Block | Source location | Decision |
| --- | --- | --- |
| Cut recycler spawn `// BuildObject("svrecy",1,"spawn1");` | `Misns6Mission.cpp:140`, comment in `misns6.lua` | Skipped. The map already carries `svrecy0_recycler` (loss condition, co-op rally point); a second would duplicate the base. `spawn1` stays unused. |
| Dormant proximity ambushes `check1..check4` / `counter2..counter5` (two `bvtank` + one `bvturr` when a human comes within 400 m (`counter2`, `counter3`) or 200 m (`counter4`, `counter5`)) | `Misns6Mission.cpp:239-281`; `Setup` never arms the timers and the port keeps them at 99999 | Skipped. The trigger radius is under the 460 m no-pop-in rule, so the units would appear inside view range (or be pushed to a fallback and ambush nobody). The paths `check1..check4`, `counter2..counter5` exist and serve only as fallback entries and the second raider's entry (`counter2`). |
| `// if (what == CMD_NONE) Attack(friend1, enemy1);` | `Misns6Mission.cpp:184` | Pseudo-code; no behaviour. |
| Native-only `MineLayerProcess::laying` inspection under `#if 0` | `Misns6Mission.cpp:199-210` | Not scriptable; the port's `GetCurrentCommand == NONE` test stands. |
| Unreferenced lines `misns604` (wrong direction, see above), `misns608` (no walkers in `crns6.aip`), `misns613` (audited, skipped; `misns606`, `misns607`, `misns610`, `misns611` and `misns612` are restored) and the `base_suggestion` / `lost_message` / `beacon` state | `Text/misns60{4,8}.txt`, `Text/misns613.txt`; flags declared, never used | Skipped. No code block triggers them; inventing triggers would be new content. |

Unused authored paths: `t1`, `t2`, `t3`, `spawn1`, `check1`, `check2`, `check3`, `check4`, `boundary`, `path_2`,
`path6`, `protectme`, `edge_path`, and three unlabeled sowing routes (19, 12 and 10 points, ending at
`s1`/`s2`/`s3`). The body uses only `m1..m3`, `s1..s3`, `counter1..5`, `counter_attack` and `counter_attack_path`.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

The body already carries its own documented port fixes (uninitialised `closest`, the success latch, distance for
missing handles). In the CR layer:

- `misns6.aip` asks the Black Dog base for Soviet `svturr` turrets it cannot build. `SetAIP` maps it to `ODF/crns6.aip`,
  the Black Dog version of the plan.
- The body tests `GetTeamNum(h) ~= 2` for the mine layers; with the enemy on team 5 no layer would ever register.
  `GetTeamNum` answers 2 for a team-5 object inside this file.
- `IsAudioMessageDone(M.audmsg)` is read raw by the win wait. The runtime's `AudioMessage` may return a nil handle and
  the native call on nil is a Lua error (fatal for the host). The layer answers "done" for a nil/zero handle.
- `Attack(raider, GetPlayerHandle())` targets "the player"; with several humans it targets the human nearest the
  raid entry and the order is replayed on the ticket's extras.
- The engine's `AddObject` callback runs on guests too; the wrapper keeps the order-issuing registration on the authority.

## Live checklist (host-tested only)

1. Offline: briefing `misns601`, objectives; 3 `avmine` (team 5) walk to `s1..s3` and lay mines.
2. Approach the mines: `misns602` once; shoot a layer: two `bvraz` arrive from `counter1`/`counter2` out of sight and hunt the nearest human.
3. Approach a howitzer: `misns605`. Approach the far silo: `misns603`, five units march `counter_attack_path`.
4. Approach the command centre: objective turns green with a marker. Destroy it: `misns609`, then the debrief.
5. Lose the recycler: `misns6l1.des` after 2 s.
6. Two to four players: extras per the table, no pop-in, guests never issue orders, leader quit fails guests, save/load keeps timers.
7. Titan weather: level 2 at start, 3 near the mines/raid, 4 at the silo assault or command centre, 2 after victory.
8. After 120 s the Black Dog AIP (`crns6.aip`) builds only Black Dog units.
9. A dead human's ship pauses the shared mission until respawn (the runtime's session-ready gate); check it feels acceptable.
