# Black Dog 6 co-op: Blitzkrieg (bdmisn06)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd06` (a diversion draws the Chinese fighters off, the
Chinese outpost beside the Pegasus portal is razed within 11 minutes, a Recycler arrives to build an APC, and the APC
reprograms the portal while the Chinese counter-attack through it). One `Missions/bd06cr.bzn` and one
`Scripts/bd06cr.lua` serve both modes. Companion to the faithful DLL port underneath (`Scripts/bd06.lua`, see
[`BD06_LUA_PORT.md`](BD06_LUA_PORT.md), tested by `Tools/Test-BlackDog06.lua`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS2_COOP.md`](MISNS2_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd06cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bd06.lua` (`Tools/Test-Bdmisn06CoopSourceParity.py`); the body is never edited, the callbacks are wrapped in the last region. Holds the runtime CONFIG, the native shadows, the restorations and the weather beats. |
| `Scripts/CRGanymedeSitesBD06.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather (the Europa director with the generated sites for this map: four cryovolcanic vents). |
| `Missions/bd06cr.{bzn,vxt}`, `bdmisn06.{hg2,lgt,mat,trn}`, `Config/bd06cr.ini` | Map, vehicle list and multiplayer listing (not part of this change). The map carries the whole Chinese outpost and the ten diversion fighters; everything else the Chinese have is spawned by Lua. |
| `Tools/Bdmisn06Fixture.lua`, `Test-Bdmisn06Coop.lua`, `Test-Bdmisn06Presentation.lua`, `Test-Bdmisn06CoopSourceParity.py`, `Test-Bdmisn06CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/Test-BlackDog06.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the ten `bdtank_*`, the backup razors, the Recycler and its escort, the APCs) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: the outpost, the ten diversion fighters, the portal and every Lua-spawned unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. The map's own enemies are authored on team 5 already; nothing is left on team 2. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no AIP: the enemy is scripted. `SetScrap(1, 75)` becomes the shared pool plus 10 per guest;
`SetPilot(1, 10)` goes to every human team. Respawns rally on `backup_1` (the Black Dog start; no base exists until the
Recycler deploys late in the mission).

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one tank. In co-op `M.user` is the runtime's nearest-human token. The body uses
it once: `Attack(badguy, M.user)` for the two counter-attack groups. The CR layer's `Attack` answers it:

- A real unit is ordered at the human nearest to that unit.
- A unit that is still a waiting spawn ticket remembers the order and is ordered at the nearest human the moment it is
  built (`Restored.Built`; extras that mirror it too).
- The opening and end-scene shots look at the portal, the fake-attack shot at a diversion fighter: real objects, no change.

The APC gate counts every `bvapc` within 100 m of `apc_in` whatever its team (the faithful body's rule), so an APC built by
any human counts.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: `cvfigh`, `cvtnk`, `cvrckt`, `cvartl` (every Chinese craft the body builds). They become *tickets*: the body
gets a negative request id and the unit is built by the runtime on the next frames, with the body's later orders (`Goto`,
`Attack`, `Hunt`) replayed on it; `Hunt` is added to the runtime's order list for that. Not scaled: team-1 units (the
Recycler, its razors, the backup razors, the APCs).

Events. The runtime region wraps `BuildObject` once: a new frame **or a new entry path** is a new scaling event, and the
first scaled unit of an event is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Events: the five hunters every 110 s (`attack_always`, `Hunt`), the two-tank and three-tank counter-attacks (`attack_1`,
`attack_2`), the last five-tank raid (`attack_3`), the three artillery (`portal_attack_1`), the seven closing fighters
(`portal_attack_2`), the seven tanks that follow the narration (`dummy_1`) and each portal wave.

Portal waves. `BuildObjectAtPortal` stays the native build (a stage effect of the portal), so the wave's two units are never
tickets. The first unit of each wave is mirrored by its extras as tickets at the authored portal exit `portal_spawn`
(the ticket of the native build itself is cancelled), ordered like the wave (`Goto camera_go`). One human: no extras.

Cap: at most **24** live scaled units (`liveCap`; the runtime default is 12) because the hunters, a counter-attack, a raid
and the portal waves overlap. Extras are the only requests dropped for the cap. Build rate is two per frame.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next clear
authored enemy approach in `fallbackEntries` is used (`attack_always`, `dummy_1`, `attack_1`, `attack_2`, `attack_3`, first
that is clear), else the request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it). The humans'
start is 230 m from `portal_attack_1` and 85 m from `portal_attack_2`, so the artillery and the closing fighters usually use
a fallback entry. Reinforcements stop for good when the mission is won or lost (`endedFlags = lost, crWon`); the body itself
keeps the hunters coming until the result.

## Humans' result, timer, win and loss

- Win: the exit APC reaches the end of `apc_out` -> `SucceedMission(..., "bd06wina.des")`, preceded by the restored closing
  narration (below). The runtime holds the result until every guest acknowledged the preceding events. The victory is
  latched (`M.crWon`), so a late co-op failure is ignored.
- Loss, all through one shared `FailMission`: portal destroyed -> `bd06lseb`; Recycler and every APC gone before the portal
  is ours -> `bd06006`, `bd06lsec`; a diversion fighter damaged or lost during the first 20 s -> `bd06007`, `bd06lsea`;
  the 11 minutes run out -> `bd06lsea` (see the stock bug below); out of lives (every human out) -> `bd06lsea`
  ("... as you pilot your new Scavenger"). Leader departs: every guest fails.
- Timer: the body's deadline is `stateTimer2` (11 minutes from the end of the opening). The restored cockpit timer shows it.

## Cinematics are shared and unskippable in a network game [owner]

Three shots (`camera_start` on the portal, `camera_go` on a diversion fighter, `camera_end_scene` on the entering APC /
portal) are driven by `CameraPath` every frame, so the runtime's camera stream carries them to every guest;
`CameraCancelled` is false in a network game, offline all three stay skippable. The runtime stops driving a shot the host
skipped, so the CR `CameraPath` reports "arrived" for a host skip in a network game (the opening has no timeout: it would
stall forever otherwise); the CR `CameraReady` clears the cancel flag as a shot opens so an earlier skip cannot end a later
shot. A save/load cannot resume a film: on load the camera is opened again in the three film states and the body ends the
shot as usual.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the top
of the runtime region of `bd06cr.lua`).

| Restoration | Cut block it comes from | Behaviour |
| --- | --- | --- |
| Closing narration (`RESTORED_VICTORY_LINES`) | `MS_WAITAPCOUT` tail: `soundhandle = AudioMessage("bd06008.wav"); missionState = MS_WAITFORSOUND8;` ... `case MS_WAITFORSOUND8: if(IsAudioMessageDone(soundhandle)) { missionState = MS_WAITING4; stateTimer = GetTime() + 5; }` ... `case MS_WAITING4: if(stateTimer < GetTime()) { AudioMessage("bd06005.wav"); SucceedMission(GetTime() + 10.0f, "bd06wina.des"); lost = TRUE; }` | When the body's own victory fires (the exit APC has arrived), `bd06008` ("We're done, Lieutenant. Now the portal opens about a mile from where the Chinese headed.") plays, then 5 s after it ends `bd06005` ("Excellent work, Lieutenant. Now get back to HQ for debriefings.") and the victory 10 s later, exactly as the cut states did. Both lines ship (`Text/bd06005.txt`, `bd06008.txt`, `Config/durations.csv`) and were referenced nowhere else. Needs only audio, no map content. A save/load during it neither loses nor repeats the victory. |
| 11-minute cockpit timer (`RESTORED_COCKPIT_TIMER`) | `// StartCockpitTimer(11 * 60);` at the end of the opening, `// HideCockpitTimer();` once the base is down, and `// out of time? if(GetCockpitTimer() < 1)` | The body's own deadline (`stateTimer2`, `bd06lsea` on expiry) is unchanged; the timer is shown on every peer while the Chinese base stands, hidden when it falls or the mission ends, and shown again with the time left after a load. Showing the clock is coherent with the loss the player can already suffer. |

Skipped, with the reason:

- The friendly damage check (`if(i < 5) { o = GameObjectHandle::GetObj(bdtank[i]); if(o->GetCurHealth() != o->GetMaxHealth()) { missionState = MS_ATTACKTOEARLY; soundhandle = AudioMessage("bd06007.wav"); } }`
  over `bdtank_1..5`, the five Black Dog tanks beside the start): the faithful port already ends the mission for damage to a diversion
  fighter with the same `bd06007`/`bd06lsea`; losing the mission when any human's stray shot or the first Chinese fighter scratches
  a Black Dog tank would be a one-shot failure for a shared team. Not restored; the test asserts a damaged `bdtank_1` is not a loss.
- `portalAttackStage`, `portalAttackNum` (cut declarations "number of fighters attacking through the portal (2-5)"): dormant,
  no behaviour to restore. The body keeps the fixed two-unit wave.
- `randomAttack` (always `TRUE`, never read): dormant.
- The unused debrief `bd06lsed`: not restored, see the stock bugs.

Authored paths the script never uses (documented, not wired): `edge_path` (the playable box, used by the weather),
`outer_limits` (an 11-point boundary ring), `path_1`, `path_2`, `path_3` (one-point scratch routes beside the Chinese
silos).

### Voice lines [owner decision 2026-11-01]

Nine shipped lines `bd06001`..`bd06009` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`). The faithful
body plays seven; `bd06005` and `bd06008` are unused by the DLL and are slotted into the closing narration above. The
contract test asserts the script names exactly the lines the repo has transcripts for, and that these two are the restored
ones.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **`bd06lsed.des` does not exist.** The 11-minute loss calls `FailMission(..., "bd06lsed.des")`; the game ships only
  `bd06lsea`, `bd06lseb`, `bd06lsec` and `bd06wina`. The CR layer maps it to `bd06lsea` (the debrief about time lost before
  the next attempt on the gateway). The faithful test still asserts `bd06lsed`.
- **One human as "the player"**: the counter-attack groups attack the single `M.user`. See "Humans as the player".
- **Idle counter-attackers**: the body's gates wait for the first counter-attack tank (and for all three of the second group) to
  die. A human can die and respawn here (the DLL's single player could not), which leaves a unit whose target is gone idle and
  the gate shut. Every 10 s an idle chaser attacks the nearest human again.
- **Portal visuals**: `PortalOut`/`ActivatePortal`/`DeactivatePortal` act on the local copy of the portal object, so they run on
  every peer through the ordered stream (`BD6PortalOut/On/Off`).
- **Concealed spawns**: the body gives `Hunt`/`Goto`/`Attack` to units it has just built; in co-op they may still be tickets,
  so those orders are in the runtime's replayed order list.
- **Missing audio handle**: `AudioMessage` returns `0` instead of `nil`, and `IsAudioMessageDone(nil/0)` is true, so no gate
  waits for ever and no `soundhandle == nil` test replays the line.
- **Reinforcements after the result**: the random hunters stop at the result.
- **Loads**: the runtime's `Load` resets the presentation; the objective list (`resetObjectives`) and the cockpit timer are
  republished from the mission state, the film camera reopened.
- **Enemy team**: the body builds on the map-native team 2; the runtime maps it to the co-op enemy 5.
- Objective rebuilds are coalesced by the runtime. Every line the body names has a subtitle in `Text/`.
- The body already carries its own documented port fixes (see `BD06_LUA_PORT.md`).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same options as
`misn12cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD06`, networked through the runtime (seeded timeline from the host,
host-chosen plumes/quakes/surges over the ordered stream as `EuropaState`/`EuropaPlume`/`EuropaQuake`/`EuropaSurge`,
`Save`/`Load` state, `AnnounceState`). No new weather module: Ganymede reuses the Europa director for an icy, airless Jovian
moon. `Environment.BindWeatherSensors("Ganymede", ...)` is registered once per start from the runtime's update hook on every
peer, so the director slows radar as it intensifies. If the module or the sites module is missing, or a weather call errors,
the mission runs without weather and logs once. The site file has four vents: `eggeizr130_geyser` (far east, by the
armoury), and `eggeizr142/143/144_geyser`, three in the Chinese base, so plumes stay enabled.

Beats (host/offline only, each once, tied to the mission's own moments; the director never damages):

| Moment | Weather |
| --- | --- |
| Opening | level 1 (Quiescent) |
| "Delta Three is Go" (the diversion starts) | level 2 and a quake (0.3, 3 s) |
| The Chinese base is down (`MS_WAITFORREDDEVIL`) | level 3, a quake (0.4, 3 s) and a plume from `eggeizr143_geyser` |
| The first counter-attack arrives | a plume from `eggeizr142_geyser` |
| The heavy counter-attack is beaten (`bd06003`) | a surge (5 s, 0.8) |
| The Recycler deploys and the last raid comes | level 4, a quake (0.35, 3 s) and a plume from `eggeizr144_geyser` |
| The APC is in the portal (`portalours`) | a quake (0.5, 3.5 s) and a surge (6 s, 0.9) |
| Victory | forced level released, back to level 2 |
| Loss | level 4 |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn06Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, fallback, portal, films, timer, results, weather
lua5.1 Tools/Test-Bdmisn06Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Bdmisn06CoopSourceParity.py # bd06cr.lua minus CR regions == bd06.lua
python Tools/Test-Bdmisn06CoopContract.py     # labels/paths/teams in bd06cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-BlackDog06.lua              # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change; the four co-op commands above are the
step to add. The contract test checks `Config/bd06cr.ini`, `Config/crbd.ini` and `Missions/bd06cr.vxt` only when
they are in the tree and says which it skipped.

## Inferences and open questions

- Scaling is per frame and entry path, a CR inference; `liveCap = 24` instead of the default 12.
- The portal is authored on team 5 and the body orders the Chinese artillery and closing fighters to `Attack` it after the
  APC enters. The body never changes the portal's team; whether the engine lets team-5 units attack a team-5 portal is
  unverified (the faithful behaviour is kept).
- `BuildObject("bvapc", 1, "portal")` names the portal object, not a path (the map has none): the faithful behaviour is kept
  and unverified for the real engine.
- The cockpit timer: other maps on this mission class restart the engine's timer every frame (see the bd04 notes); the
  displayed clock may count up. The body's own deadline is not affected.
- Portal extras at `portal_spawn` are 20 m from the portal, a CR choice; collision at the exact point is unverified.
- Rally `backup_1` is the start area, not the deployed Recycler (the Recycler exists only late).
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Opening: the same shot on every peer, looking at the portal; cameras balanced; the briefing plays; the 11-minute timer
   appears on every peer when the shot ends.
2. +20 s "Delta Three is Go": the ten fighters leave, the shared shot follows one, then they vanish; sky level 2.
3. Destroy the six outposts: the timer disappears, a vent opens in the ruins. Letting it run out gives `bd06lsea`.
4. +80 s portal waves every 80 s (the portal opens and closes on every peer); with 2-4 humans extras arrive from the
   portal exit; hunters every 110 s from a hidden approach; nothing pops in view.
5. +90 s replacement razors per lost Black Dog tank; +3 min two tanks, +3 min after the first dies three more, each aimed at
   the nearest human; killing the nearest human leaves them re-targeting.
6. `bd06003`, the Recycler arrives and deploys; `bd06004`; the last raid; build an APC and drive it to `apc_in`.
7. The shared end scene; artillery on the portal; `bd06009`; seven tanks; a minute later the exit APC; `bd06008`, five
   seconds, `bd06005`, one shared victory with `bd06wina`.
8. Portal destroyed, Recycler/APCs lost, damaging a diversion fighter: each gives one shared failure with its debrief.
9. A save/load during each film and during the closing narration; objectives and the timer come back; no weather error in the log.
