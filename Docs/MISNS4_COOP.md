# Mission S4 co-op: Io's Bridge (misns4)

Shared offline / 2-4 player co-op port of the Soviet mission `misns4` (hold the single bridge across Io's lava
fields while five relic transports are escorted down to the goal; four must arrive, two losses fail). One
`Missions/misns4cr.bzn` and one `Scripts/misns4cr.lua` serve both modes. Companion to
[`MISNS4_SOURCE_PORT.md`](MISNS4_SOURCE_PORT.md) (the faithful DLL port underneath, `Scripts/misns4.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/misns4cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `misns4.lua` (`Tools/Test-Misns4CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the restorations and the Io weather beats. |
| `Scripts/CRCCARuntime.lua` | Shared co-op runtime, including the CCA mission's NSDF-to-Black-Dog ODF remap. |
| `Scripts/CRIoWeather.lua`, `Scripts/CRIoSitesS4.lua` | Io weather and the generated lava pools (338) and vent sites for this map. |
| `Missions/misns4cr.bzn` | Map roster; authored NSDF vehicles are switched to Black Dog ODFs while their labels stay intact. |
| `Missions/misns4cr.vxt`, `misns4.{hg2,lgt,mat,trn}` | Terrain and map companions. |
| `Tools/Misns4Fixture.lua`, `Test-Misns4Coop.lua`, `Test-Misns4CoopSourceParity.py`, `Test-Misns4CoopContract.py` | Multi-peer fixture and tests. `Test-Misns4.lua` / `Test-Misns4SourceParity.py` still cover the faithful port, unchanged. |

No cameras exist in this mission, so there is no presentation test.

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored recycler, the Bridge pod, the Soviet constructor and the five transports stay on team 1: shared, host-run. |
| 5 | The Black Dogs (the DLL's team 2: howitzer, towers, power plants, raiders, bridge guard, north force, rocket counterattack). `BuildObject(..., 2, ...)`, `SetAIP(name)` and `SetPilot(2, ...)` are mapped to team 5; the literal 2 never reaches the engine. |
| 7 | Support (allied to humans; unused here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load; `SetAIP("misns4.aip")` runs only inside the body's `Update`, with team 5.

The body's `AddObject` (register a transport, order it down `escort`) is kept: the file-end `AddObject` calls the
runtime, then the body's version on the authority only, under `pcall`. Guests receive the engine callback for each
transport but never order it.

## Humans as one trigger

`GetPlayerHandle()` returns the runtime token and `Distance` is wrapped (`WrapDistance`), so the two approach
triggers answer for the NEAREST human: any player within 200 m of `sbridge` springs the north force, any within
200 m of `warn1` plays the artillery warning (`misns409`). The haulers' own checks (`goal`, third-hauler trigger at
`warn1`) are NPC distances and unchanged. `farthestTargets` is empty (no reach gate waits for every player).

## Scaling and concealed arrivals [owner rules]

The CCA runtime resolves the mission's NSDF `av*` requests to Black Dog ODFs. Scaled requests (concealed from humans,
mirrored, orders replayed) include `avfigh`->`bvraz`, `avtank`->`bvtank`, `avltnk`->`bvltnk`, `avrckt`->`bvrckt`,
`avturr`->`bvturr`, `avscav`->`bvscav`, and `avrecy`->`bvrecy`. Structures (`abtowe`, `ablpow`), the authored `avartl`, the restored
howitzers (`avhraz`, `b1`/`b2`, not in `scaledOdfs`: built directly, without the 460 m check) and all Soviet-side
builds (pod, constructor, transports) are built straight away.

Events that get extras (one `BeginEvent()` each, in `-- CR co-op scaling >>` regions): the two raiders, the bridge
guard (first tank), the north force (first unit, the light tank) and the four-rocket counterattack. The first scaled
unit of each is mirrored by `min(floor(humans / 2), 2)` extras (same kind, entry and orders):

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

The lone reminder fighter (`wakeup`) is not an event and is not mirrored. Extras are NOT part of the bridge-clear
test (`t1`, `t2`, `b1`, as in the DLL): the bridge counts as clear when the three named guards die.
Cap: at most 12 live scaled units; extras are the only requests dropped for it (primaries always spawn). Scrap:
team 1's `AddScrap(1, 50)` becomes 50 + 10 per guest; pilots (`SetPilot(1, 30)`) go to every human team and the
enemy's `SetPilot(2, 30)` to team 5.

No pop-in: a scaled scripted unit is never built within 460 m of any human (the restored tank and light tank are
concealed this way; the restored howitzer is not). If a human is near the entry path the next of
`fallbackEntries` (`spawn4`, `spawn3`, `counter`) is tried, else the request waits (saved in `M.crcca`, so a
save/load neither loses nor duplicates it).

## Timer, win and loss

- The 420 s cockpit countdown is shown on every peer (`Present("StartCockpitTimer")`); its stop/hide at the first
  transport also reaches every peer. The DLL's own 420 s deadline drives the spawn, not the clock readback.
- Win: unchanged. Four transports within 100 m of `goal` -> `SucceedMission(+10 s, "misns4w1.des")` on every peer.
  `>=` (the faithful port's own fix) covers a fourth and fifth arrival in one frame. `FailMission` is ignored once
  `won` has latched (nothing can fail a won mission in co-op; this also applies offline, a deliberate difference
  from the DLL for the overlap case of two later losses).
- Loss: the second lost transport -> `misns403` per loss, then `FailMission(+15 s, "misns4l1.des")` once on every
  peer.
- Out of lives (every human out): the mission fails for everyone with `misns4l1.des` (the stock set has no better
  description).
- Leader departs: every guest fails the mission (`HasLeaderDeparted`).

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag
(`RESTORED_*` at the top of the runtime region of `misns4cr.lua`). Each is built only when the map carries its path
(`R.PathExists`), once, and is saved in `M.crcca.r` (no repeat after a load). The restored tank and light tank go
through the same scaled spawn layer (concealed, team 5) but are not themselves mirrored by extras; the restored
howitzer is built directly on team 5 with no 460 m check.

| Flag | Cut block (in `Scripts/misns4.lua`) | Behaviour |
| --- | --- | --- |
| `RESTORED_RAIDER_LTNK` | `-- BuildObject("avltnk",2,"spawn4");` after the two raiders | One light tank at `spawn4` with the raiders at 30 s. |
| `RESTORED_BRIDGE_HRAZ` | `-- b2=BuildObject("avhraz",2,"sbridge");` after the bridge guard | A second howitzer at `sbridge` at 100 s, stored in `M.b2`. Not a bridge-clear requirement (the DLL's clear test never named `b2`). |
| `RESTORED_NORTH_TANK` | `-- BuildObject("avtank",2,"spawn3");` ahead of the north force | One tank at `spawn3` with the north force. |

Unused shipped voice lines [owner decision 2026-11-01]: the wav and `Text/misns4NN.txt` transcript ship in the game but the DLL never plays them. Each plays once through the CR layer (`AudioMessage`: replicated to co-op guests, queued behind a line still playing), is latched in `M.crcca.r` (kept by Save/Load) and sits behind `RESTORED_VOICE_LINES`.

| Line | Transcript | Trigger | Why it fits |
| --- | --- | --- | --- |
| `misns408` | "That's the bridge ahead." | `north_bridge` (a human within 200 m of `sbridge`), once; skipped if the guard is already cleared that same beat, because `misns405` ("The bridge seems secure...") would play first and contradict it | Names the bridge the convoy is about to reach. |
| `misns404` | "A transport has cleared the pass." | The first hauler to reach `goal` (`win_count >= 1`), once; not played if the win line is due in the same beat | The natural report for a hauler arriving; later arrivals stay silent, as in the body. |
| `misns407` | "The transports have cleared the pass. I'm certain CCA Command will be pleased with our work here." | The win (`M.won`), played at once during the source's 10 s `SucceedMission` delay; queues behind `misns404`/`misns403` if one is still playing | The closing line of the mission. |

### Skipped (documented, not restored)

- **Casualty cinematic and casualty audio**: the `--[[ Another one bites the dust ... ]]` and `--[[ Cineractive on
  neareset guy ... ]]` notes are stubs; there is no implemented cinematic, no camera pod, no path and no audio line
  for them. The shipped line `misns406` ("this convoy is too insecure") is never called by any block of the
  source and its trigger is not clear (audited, skipped). `misns404`, `misns407` and `misns408` are restored (see
  above) with CR-chosen triggers, not DLL ones.
- **`-- AudioMessage("transport dead..")`** (placeholder; `misns403` already plays) and **`-- AudioMessage()`** at the
  failure (the description carries it).
- **"Now load an AIP" note** at the north force and **`attack_time` / `first_bridge` / `h1` / `h2`**: unused state.
- **"wrong message.. (source annotation)" at `misns405`**: the text reads "The bridge seems secure, but there's heavy
  enemy activity on the other side", which fits the bridge-clear moment; there is no evidence of a better line, so it
  stays.

### Stock bugs

The faithful port already fixes the native defects (null distance operands, the hauler list bound and duplicate
registration, the unlatched `lost`, the equality win). In the CR layer: (1) `GetPlayerHandle` is a token and
`GetDistance`/`Distance` answer for all humans (stock reads one player); (2) literal team 2 is mapped to 5; (3) the
countdown reaches every peer; (4) `FailMission` after a latched win is ignored; (5) `misns4.aip` asks the Black Dog base for Soviet `svturr` turrets it cannot build, so the CR layer substitutes `ODF/crns4.aip` (the same plan with Black Dog unit entries) for `SetAIP("misns4.aip")`; `Scripts/misns4.lua` is untouched.

## Weather: Io (`CRIoWeather`, sites `CRIoSitesS4`) [owner decision]

Wired through `CONFIG.weather` (start and target rung 1, calm). Everything is cosmetic; the director never touches
gameplay. Orbit lighting with Jupiter-shine (same as misn10), the Io sensors bound to `Environment` on every peer
once the director runs (and again after a load). Beats (host only, `s.ioBeats`, each once, `pcall`'d):

| Event | Beat |
| --- | --- |
| first transport appears (`first`) | target rung 2 (restless) |
| a human reaches the bridge (`north_bridge`) | rung 3 (active) |
| bridge cleared (`bridge_clear`) | a light tremor (`Quake(0.3, 5)`) |
| rocket counterattack (`counter`) | rung 4 (intense), `Quake(0.5, 6)`, a vent erupts |
| first transport lost | a vent erupts (power 1.5) |
| defeat (`lost`) | `ForceLevel(5, 60 s)`, paroxysm |
| victory (`won`) | eases back to rung 2 |

A missing or failing module or sites file disables the weather and logs; it never stops the mission.

## Live checklist

1. Offline: the whole mission completes (win and the two-loss defeat); the timer shows 7:00 and stops with the
   first transport; no unit is on team 2.
2. 2-4 players: every peer hears `misns401/410` once, sees the Bridge pod name, the 420 s timer, and the transport
   markers; the transports go down `escort` and exactly five spawn 45 s apart.
3. Raiders at 30 s (+ light tank), bridge guard at 100 s: counts grow with player count; nothing appears within
   460 m of a player (watch `spawn4`, `spawn3`, `counter`).
4. Standing within 200 m of the bridge triggers the north force for any player; an enemy pop-in beside the watching
   player falls back to another entry.
5. Clearing the bridge plays `misns405` and starts `misns4.aip` (team 5 builds and attacks); the counterattack
   rockets drive to `sbridge`; with the third transport dead, no counterattack comes.
6. Win after the fourth arrival (10 s delay) and defeat after the second loss (15 s delay) on every peer, once.
7. Save and load mid-convoy: no repeated opening (scrap/pilots/structures), the convoy continues, the weather
   re-initialises.
8. Weather beats: rung changes at the convoy start/bridge, the vent/tremor at the counterattack and a lost transport.
9. Open risks to look for: the cockpit timer readback (`MultSTMission` calls `StartCockpitTimerUp`, see misn18),
   the restored howitzer standing on the authored path, and the enemy `avrecy` arrival (`spawn3`) waiting while a
   player camps there.
