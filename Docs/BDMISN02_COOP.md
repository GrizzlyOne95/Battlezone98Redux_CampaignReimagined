# Mission BD2 co-op: Hidden Enemy (bdmisn02)

Shared offline / 2-4 player co-op port of the Black Dog mission `bdmisn02` (a freshly landed Black Dog recycler is
attacked by cloaked Chinese craft: two small waves, a massive attack that forces a retreat, a harassment pair and a
six-fighter ambush on the way to Nav Alpha, then two bombers that destroy the crippled recycler in a final film).
One `Missions/bd02cr.bzn` and one `Scripts/bd02cr.lua` serve both modes. Companion to the faithful port
underneath (`Scripts/bd02.lua`, native source in `References/BlackDog02Source/`) and
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS2_COOP.md`](MISNS2_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd02cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bd02.lua` (`Tools/CoopCampaignTests/Test-Bdmisn02CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the restoration and the co-op fixes. |
| `Scripts/CRGanymedeSitesBD02.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather: the Jovian-moon director (it was written for Europa and is shared) and the generated sites for this map: **two** geyser vents (`eggeizr10_geyser`, `eggeizr11_geyser`), frost clusters and bounds. No new weather module. |
| `Missions/bd02cr.{bzn,vxt}`, `bdmisn02.{hg2,lgt,mat,trn}`, `Config/bd02cr.ini` | Map and companions (not part of this change). The map carries the recycler, two Bobcats, a scavenger and the four cloaked turrets (already on team 5); Lua spawns every other enemy. |
| `Tools/CoopCampaignTests/Bdmisn02Fixture.lua`, `Test-Bdmisn02Coop.lua`, `Test-Bdmisn02Presentation.lua`, `Test-Bdmisn02CoopSourceParity.py`, `Test-Bdmisn02CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Bd02.lua` / `Test-Bd02SourceParity.py` still cover the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the recycler, the Bobcats, the scavenger, Nav Alpha) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: every wave unit, the bombers, and the four map turrets (`enemy_turret1..4`, authored on team 5 in the co-op map). The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 (the stage-prop builds below do the same by hand). The body has no other hard-coded team 2 (no `SetPerceivedTeam`, `GetTeamNum`, `SetAIP`). |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs
once at chunk load. The mission has no AIP: the enemy is entirely scripted. The starting `SetScrap(1, 20)` goes
through the runtime and grows by 10 per guest (the shared base is the recycler). `SetPilot(1, 10)` is skipped for the
human teams in a network game (the shared lives of `CRCoop` own pilots) and unchanged offline.

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, assigned to `user` every frame. In co-op it is the runtime's
nearest-human token (`crcca_players`). The body uses it in three ways:

- *Liveness* (`!IsAlive(user)` for two seconds -> `bd02lose.des`). Offline the token is alive exactly while the
  player's ship is, so the DLL's defeat is unchanged. In a network game the token never reads dead: the shared
  lives/respawn (`CRCoop`, out-of-lives -> `bd02lose.des` for everyone) own that decision, so one dead human never
  fails the mission and a respawning human is not "dead".
- *Orders aimed at it*: `Goto(harrass_scout1, user)`, `Goto(harrass_ltnk1, user)` and the six `Attack(temp, user)` of
  the ambush. A real unit is ordered at the human nearest to that unit; a unit that is still a waiting ticket
  remembers the order (the runtime drops one whose target is the token) and is ordered at the nearest human the
  moment it is built, extras included.
- It never appears in a distance test (the body measures the recycler and the bombers), so `farthestTargets` is empty.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `cvfigh`, `cvltnk`, `cvtnk`. They become *tickets*: the body gets a negative request id and the
unit is built by the runtime on the next frames, with the body's later orders replayed on it. The body's helper tests
(`Valid`, `Alive`) see tickets as present and alive, so wave-clear gates wait for a unit that is still being held back.

Stage props, built directly on team 5 (never tickets, never mirrored): `spawn_wave1_scout1` (the unit the decloak
camera follows) and the eight units of the massive attack (`spawn_enemy_*`). A camera needs a real handle (a ticket
is dropped from the camera target), and these units exist to be filmed: the whole massive-attack wave is removed
~12 s later by the body. The bombers (`cvhraz`) are scripted actors built directly as well.

Events. The body spawns each wave in one frame, so **a new frame is a new scaling event**: the first scaled unit of a
wave is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Events: wave 1 (extras are scouts), wave 2 (scouts), the harassment pair, the six-fighter ambush. Cap: the runtime
default of **12** live scaled units; extras are the only requests dropped for the cap, primaries always spawn.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden
Chinese approach in `fallbackEntries` is used (`spawn_wave2_scout3`, `spawn_wave1_scout2`, `spawn_wave2_scout1`,
`spawn_bomber_1`; the first that is clear), else the request waits (saved in `M.crcca`, so a save/load neither loses nor
duplicates it). At the start the shared base is 386 m from `spawn_wave2_scout3`/`4` (the two western wave-2 scouts), so
with humans at the base those two come from a hidden approach; with three or more humans the ambush's `fighter_1`
(439 m from the farthest start) comes from a fallback too.

Known exception, not concealed: the stage props above (the camera has to see them).

## Humans' result, timer, win and loss

- Win: unchanged. The bombers kill the recycler, the last narration ends, a three-second hold, then
  `SucceedMission(..., "bd02win.des")` once (the runtime holds the result until every guest acknowledged the
  preceding events). `crWon` latches it so a later out-of-lives failure is ignored.
- Loss: the recycler dies before the final film -> `bd02lose.des` once. Out of lives (every human out): the same
  debrief for everyone. Leader departs: every guest fails.
- The body's own `lost` latch stops the mission after a defeat and the runtime drops every waiting ticket.

## Cinematics are shared and unskippable in a network game [owner]

All three films are driven by `CameraPath` every frame, so the runtime's camera stream carries them to every guest;
`CameraCancelled` is false in a network game, offline each stays skippable:

1. The decloak shot (`camera_decloak`) on the stage-prop scout, until the host's camera arrives.
2. The massive-attack shot (`camera_massive_attack`) on the stage-prop tank, through `bd02004` and `bd02005`.
3. The chase shot (`camera_bomber_chasecam`) on the recycler through the final narration and hold.

A save/load cannot resume a camera (the shots are gone): on load the host reopens it (`CameraReady`) when the state is
one that holds a film (the decloak, both massive-attack states, the final film and its hold); the body keeps calling
its own `CameraPath` and ends the film itself.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at
the top of the runtime region of `bd02cr.lua`). Each is gated on what `bd02cr.bzn` carries.

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Bomber routes (`RESTORED_BOMBER_ROUTES`) | `//Goto(bomber_scripted, "path_bomber_attackpath");` between the bomber build and `Attack(bomber, recycler)` (the original, single-bomber route name). | The map carries one authored route per bomber: `path_bomber_1_attackpath` (5 points, ends 40 m from the chase-camera trigger `camera_bomber_chasecam`, where the body starts the final film at 50 m) and `path_bomber_2_attackpath` (7 points, ends ~78 m from the retreat's end). The bombers are sent along them in the build frame (replacing the Attack of that same frame) and attack the recycler once either has finished its route (no current command, after a 3 s grace), once the film has begun, or after 60 s. The trigger and the film are the body's own. Without the paths the body's Attack stands. |

Skipped, with the reason:

- The factory gate in `AddObject`: `if (missionState == MS_WAITFORFACTORY && IsOdf(h, "bvmuf")) { missionState =
  MS_WAITFORWAVE1; stateTimer = GetTime() + (60 + 5); resetObjectives(); }`. `MS_WAITFORFACTORY` is not defined in this
  mission; a 65 s build-then-wave design that the timed first wave replaced. `bd02001` already says "Establish a base as
  quickly as possible" and the first wave arrives 20 s after that line ends by design; the map has no factory. Not coherent with the
  shipped audio.
- The recycler-hit block: `Recycler::Explode()`, `AddHealth(-((GetCurHealth() / 4) * 3))`, `Stop/RemoveObject(bomber)`,
  `stateTimer = GetTime() + 3`. Engine-internal calls with no Lua equivalent; the immortal bombers already destroy the
  recycler during `bd02008`/`bd02009`.
- `//Retreat(recycler, "path_recycler_retreat");` and `//Attack(harrass_scout1/harrass_ltnk1, user);`: the active `Goto`
  forms the body uses instead do exactly this.
- `//CameraPath("camera_bomber_chasecam", 1000, 0, bomber_scripted);`: replaced by the recycler shot (and a bomber
  target only in the CameraPathDir fallback below).

Authored paths the script never uses (documented, not wired): `edge_path` (the playable box the weather reads from the
generated sites) and `outer_limits` (a 5-point boundary polygon nothing reads), and `wave2_scout1_attackpath`,
`wave2_scout2_attackpath`, `wave2_scout3_attackpath` and `wave2_scout4_attackpath` (TRO 1.3 orders wave 2 to attack the recycler directly, so the body no longer follows them).

Unused voice lines: **none**. The game ships `bd02001`..`bd02009` and the body plays all nine (`bd02001` at the
start, `bd02002` as the first wave decloaks, `bd02003` after it, `bd02004`/`bd02005` through the massive attack,
`bd02006` at the stall, `bd02007` at the bombers, `bd02008` at the first hit, `bd02009` at the death). The audio
listing of the game and the references hold no other `bd02*` line. `Text/bd0200N.txt` exists for each.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- **`bd02lsea.des` does not exist.** The recycler-loss branch calls `FailMission(..., "bd02lsea.des")`; the game ships
  only `bd02lose.des` and `bd02win.des`. The CR layer maps it to `bd02lose.des`. The faithful test still asserts the
  stock name.
- **The skipped decloak film hangs a network game.** The film ends only when the host's `CameraPath` returns arrival
  or `CameraCancelled`; the runtime releases the host's own view on a skip and never answers `CameraPath` again, so a
  host that presses skip would hold state 4 until the scout died. After 30 s in the state (network game only) the CR
  layer ends the film exactly as the body does (`CameraFinish`, `WAITINGOBJ2`, +5 s).
- **`CameraPathDir` is a native, unshared camera.** The body's fallback when the recycler no longer exists would not
  reach guests. The CR layer issues the same path on the shared stream, aimed at a bomber (never null: they cannot
  die).
- **Player death versus shared lives**: see "Humans as the player".
- **Waiting tickets and `RemoveObject`**: the body removes the harassment pair and the massive-attack wave by handle. A
  removal of a ticket cancels the request (the runtime would send a negative handle). The harassment extras are not in
  the body's list: when the body removes the pair, the CR layer removes the extras too and cancels the ones still
  waiting.
- **Absent audio handle**: a line without a handle counts as finished (no gate can wait for ever on it).
- **Absent bomber route / camera target**: see the restoration and the cinematics.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- The `.des` debriefs ship with the game, not in this tree.
- The map's one area of interest (AOI) still names team 2; the generator moved the units, not the AOI. It is inert
  here (`interesting = false`) and left alone; if a later map pass changes it, the contract test's AOI assertion fails
  as a reminder.
- The body already carries its own documented port fixes (see the comments in `bd02.lua`: the dead-player grace
  timer, the bomber heal guard, the destroyed-recycler camera, the end sequence after `bd02009`).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same lighting as
`misn13cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD02`, networked exactly as in the other CCA ports (seeded
timeline from the host, host-chosen events over the ordered stream, `Save`/`Load` state, `AnnounceState`); the ops
are `EuropaState`, `EuropaPlume`, `EuropaQuake`, `EuropaSurge`. Ganymede is airless and icy: no wind or cloud, only
frost haze, geyser plumes, tidal quakes and Jupiter's radiation surges. The director's sensor modifier is bound once
as `Ganymede` (the same radar softening `misn12cr` / `misn13cr` use for Europa). If the weather module or the sites
module is missing, or any weather call errors, the mission runs without weather and logs once. Beats (host/offline
only, each once):

| Story moment | Beat |
| --- | --- |
| The first Chinese wave decloaks (state 4) | level 2 |
| The massive attack (state 10) | level 3, a quake (0.35, 3 s) and a radiation surge (6 s, 0.8) |
| The recycler is crippled and runs (state 13) | level 4 and a plume at the abandoned base (`eggeizr11_geyser`) |
| The bombers come in (state 15) | a plume at the other vent (`eggeizr10_geyser`) |
| The recycler goes down (state 17) | a hard quake (0.6, 4 s) and a surge (5 s, 0.9) |
| The win (state 18) | back to level 2 |

The director never damages.

## Tests

```sh
lua5.1 Tools/CoopCampaignTests/Test-Bdmisn02Coop.lua            # offline == faithful, 1-4 peers, scaling, 460 m, fallback, cameras, results, saves, weather
lua5.1 Tools/CoopCampaignTests/Test-Bdmisn02Presentation.lua    # E/A/C protocol on a guest, the leader's full stream
python Tools/CoopCampaignTests/Test-Bdmisn02CoopSourceParity.py # bd02cr.lua minus CR regions == bd02.lua
python Tools/CoopCampaignTests/Test-Bdmisn02CoopContract.py     # labels/paths/teams in bd02cr.bzn (skips with a message if the map is absent;
                                              # vxt / Config ini / crbd.ini checked only when present)
lua5.1 Tools/CoopCampaignTests/Test-Bd02.lua && python Tools/CoopCampaignTests/Test-Bd02SourceParity.py          # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` runs all four co-op tests (the CI lines are listed in the
change report; the workflow itself is not part of this change).

## Inferences and open questions

- Scaling is per frame (the body spawns each wave in one frame), a CR inference; the first scaled unit of a wave is
  mirrored, so a wave that starts with a stage prop (wave 1) mirrors its first *scaled* unit (a scout).
- The restored bomber routes assume `GetCurrentCommand(...) == AiCommand.NONE` reads true when a bomber finishes a
  `Goto` path (the body uses the same reading for the recycler's retreat). The 60 s timeout is the safety net; the
  route ends 40 m from the chase trigger, so the film should start without it.
- The 30 s decloak guard is a guess at "long enough for the shot to finish": the shot is two points about 80 m apart.
- `fallbackEntries` assumes the four listed spawn points are usable enemy approaches (the western `spawn_wave2_scout3`
  is first because it is far from the eastern retreat route); a ticket can arrive from the far west.
- Stage props can appear within 460 m of a human (the cameras show them to everyone).
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Start: objective, `bd02001`, then 20 s after it ends the decloak film on every peer (same shot, cameras balanced), wave 1
   afterwards; with 2-4 humans the extra scouts arrive from a hidden point.
2. Press skip as the host in a 2+ player game during the decloak: the film must end by itself within ~30 s.
3. Wave 2: the two western scouts appear from a hidden approach when humans are at the base.
4. Massive attack: eight units visible to everyone on the shared shot, removed at the end, Nav Alpha appears.
5. Retreat: the recycler leaves along its route; the two harassers chase the nearest human; at `trigger_1` the
   six-fighter ambush (hidden entry with 3-4 humans) attacks the nearest human.
6. Bombers: `bd02006` then `bd02007`; both bombers fly their route and the chase film starts near
   `camera_bomber_chasecam`; the recycler dies, `bd02008`/`bd02009`, hold, one shared victory, extras of the
   harassment pair gone.
7. Recycler lost early: one shared failure with the shipped `bd02lose.des`.
8. A human dies in a 2+ player game: no mission failure; offline player death still fails after two seconds.
9. Ganymede sky and sensor softening on guests; plumes at the two geysers on the beats; no weather error in the log.
10. Save/load inside the decloak and the final film: the camera reopens and the film ends normally.
