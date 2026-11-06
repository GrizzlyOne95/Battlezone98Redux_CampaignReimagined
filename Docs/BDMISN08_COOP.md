# Black Dog 8 co-op: Hook, Line, and Sinker (bdmisn08)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd08` (the Chinese power up a portal near the Black Dog
base, wave after wave comes through, an APC with an engineering team follows, the engineers reprogram the portal, and
the player must take their APC when they are done). One `Missions/bd08cr.bzn` and one `Scripts/bd08cr.lua`
serve both modes. Companion to the faithful DLL port underneath (`Scripts/bdmisn08.lua`, tested by
`Tools/Test-BlackDog08.lua`) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern:
[`MISNS2_COOP.md`](MISNS2_COOP.md) and [`BDMISN03_COOP.md`](BDMISN03_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd08cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bdmisn08.lua` (`Tools/Test-Bdmisn08CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restoration. |
| `Scripts/CRGanymedeSitesBD08.lua`, `Scripts/CREuropaWeather.lua` | Ganymede weather (the Europa director with the generated sites for this map: three cryovolcanic vents, the geysers `eggeizr17_geyser`, `eggeizr18_geyser`, `eggeizr19_geyser` of the Black Dog base). |
| `Missions/bd08cr.{bzn,vxt}`, `bdmisn08.{hg2,lgt,mat,trn}`, `Config/bd08cr.ini` | Map, vehicle list and multiplayer listing (not part of this change). The map has the Chinese portal (`cbport` on team 5) and no other enemy: every attacker is made by Lua. |
| `Tools/Bdmisn08Fixture.lua`, `Test-Bdmisn08Coop.lua`, `Test-Bdmisn08Presentation.lua`, `Test-Bdmisn08CoopSourceParity.py`, `Test-Bdmisn08CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/Test-BlackDog08.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The authored Black Dog side (the base, the Recycler, the wingmen, the two turret tanks, the scavengers, both nav beacons) stays on team 1: shared, host-run. Extra starting recyclers are disabled. |
| 5 | The Chinese: the portal, every attacker, the APC and the engineers' pilots. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5, and two CR shadows do the same for `BuildObjectAtPortal` and `SetPerceivedTeam`. The map's portal is authored on team 5 already. |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no `SetAIP`: the enemy is entirely scripted. `SetScrap(1, 100)` becomes the shared pool plus 10
per guest (`scrapPerGuest`); `SetPilot(1, 10)` is unchanged. Respawns rally on the Recycler.

### Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one tank. In co-op the CR layer answers it with the runtime's nearest-human
token (`crcca_players`), so `M.user` is the token. The body uses it in three places:

- The intro shot `CameraPath("path_camera_intro", 800, 1500, user)` needs a real object to look at: the CR layer targets
  the host's ship (the authority), else the first live human, else the portal.
- `Valid(user)` (the guard of that shot) and `Healthy(user)` (the guard of the engineers' attack, below) call `IsValid` and
  `GetHealth` on the token. Both are shadowed: the token is valid always and healthy while any human has a living ship.
- `Attack(pilot, user)`, when the engineers' return pilot finds a pilot already in the APC (see below), is rewritten to
  the human nearest to that pilot.

Nothing else reads the player. The body has no player-death loss; the shared lives are CRCoop's.

### "Owned by the player" is a human team

The capture gate is `GetTeamNum(apc) == 1` (the APC is team 1 once a human sits in it) and it latches
`apcCommandeered`, which with `portalReprogrammed` is the win. In co-op the human who takes the APC is on team 1-4, so the
CR layer maps `GetTeamNum` of any human team (1-4) to 1. Without this only the host's team could ever win the mission.

## Scaling [owner rules, mission decisions]

Scaled spawns: the five portal attackers `cvtnk`, `cvltnk`, `cvfigh`, `cvrckt`, `cvhraz` (the body's `attackers` pool).
Not scaled: the APC (`cvapc`) and the engineers' pilots (`cspilo`).

These are not concealed tickets. They are built by `BuildObjectAtPortal`, which puts the unit in the portal's effect with
50 m/s of initial velocity; the runtime's ticket builder only knows `BuildObject(odf, team, where)` and a spawn at an
object is exempt from the 460 m rule anyway. The arrival through the portal is the staged, visible event of the mission
(it is the first thing the intro shows), so there is nothing to conceal. The CR layer does the scaling itself:

- Each attacker the body builds is the primary of an event. It is mirrored by `min(floor(humans / 2), 2)` extras of the
  same ODF, built at the same portal 2 s and 4 s later (units stacked on one point at the same frame would collide), sent
  down the same path as the primary (`Goto` is shadowed to remember the path the body gave it), and kept in the saved
  state (`M.crcca.r`) so a save/load neither loses nor duplicates them.
- Cap: at most 12 live extras (the runtime's `LIVE_CAP`); only extras are dropped for it, primaries always come.
- Nothing more comes through once the portal is reprogrammed, the mission is decided or the portal is gone (the body's
  waves stop at the reprogramming anyway; the extras that are still queued do not trickle in afterwards).

| Humans | Extras per attacker |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

## Humans' result, win and loss

- Win: unchanged. A human takes the APC after the reprogramming (`apcCommandeered` and `portalReprogrammed`) -> `bd08007`
  -> `SucceedMission(..., "bd08win.des")` once. The body's own latch quirk is kept: no base-return requirement.
- Loss: the Recycler or the command post dies, or the engineers' pilot dies on the way to the portal, or the APC returns
  through the portal -> `bd08006` -> `bd08lsea.des`; the APC dies -> `bd08005` (restored, below) -> `bd08lseb.des`; the
  portal is destroyed -> `bd08lsec.des` at once.
- Out of lives (every human out): `bd08lose.des`, the stock generic debrief that the DLL never names. Leader departs: every
  guest fails.
- The portal's own mechanics (`PortalOut`/`PortalIn`/`ActivatePortal`/`DeactivatePortal`, `isPortalActive`) and the
  pilot/APC mechanics (`RemovePilot`, `GetIn`, `SetPerceivedTeam`, `Stop`) are authority-side engine calls and are not
  wrapped (except `SetPerceivedTeam`, below). No human goes through the portal in this mission, so there is nothing to
  teleport: the APC does.

## Cinematics are shared and unskippable in a network game [owner]

The intro (`path_camera_intro`, `bd08001`) and the portal shot (`path_portalcam`, `bd08002`) are driven by `CameraPath` every
frame, so the runtime's camera stream carries them to every guest; `CameraCancelled` is false in a network game, offline
both stay skippable. The intro ends when the path has arrived **and** `bd08001` is done; the portal shot ends on arrival. A
save/load cannot resume a film (the cameras are gone): on load the intro that was running is ended (the 25 s timer to the
portal shot is armed), and a portal shot that was running is ended (its timers are already armed).

### Stock bug: a host's skip hangs the shared shot

Both shots end on the path's arrival, which `CameraPath` returns. In a network game a host who presses skip releases only
their own camera, and the runtime then never reports an arrival again (`cameraSkipped`). The intro is what arms the portal
(`secondCameraTime`), so the whole mission would hang at the first shot. The CR layer treats a host skip in a network game
as arrival once the shot has run 12 s: the intro still waits for its briefing line, the guests keep their streamed shot
until then, and the portal shot ends 12 s into the shot. This is a fix local to this mission; the runtime is untouched
(other missions with arrival-gated shots may want the same).

A cancel that is still latched when a shot begins (the host's skip of the intro) is not a skip of the portal shot: the CR
layer samples the cancel when each shot begins and counts only one that rises afterwards, so the portal shot is not
"arrived" 12 s after it opens because of the intro's skip.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the
top of the runtime region of `bd08cr.lua`).

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| Reprimand for a shot-down APC (`RESTORED_APC_LOSS_VOICE`) | `bd08005.wav` (12.75 s, `Text/bd08005.txt`: "You idiot! HQ's long-term strategy revolved around that APC. And you can't even keep your finger off the trigger for three minutes. I'm having you posted to Io effective now!") is named by no line of `BlackDog08Mission.cpp`. Both losses play `bd08006` ("How can we get ahead in this war if you keep wasting resources? ... Phobos"): `loseSound2 = AudioMessage("bd08006.wav");` (base lost) and `loseSound3 = AudioMessage("bd08006.wav");` (APC lost, then `bd08lseb.des`). | `bd08005` is the APC's line (HQ's strategy revolved around the APC; the player pulled the trigger on it). It replaces `bd08006` for the APC-loss branch only, when the APC was found dead at the start of the frame (the CR layer notes it before the body runs, because the body forgets `apc` the moment it schedules the loss) and the base is intact. An APC that escaped through the portal, a failed APC build, a lost base and a dead pilot keep `bd08006`. Played once, on every peer, through the runtime's `AudioMessage`; the debrief is unchanged. |

Skipped, with the reason:

- `//GetHealth(factory) <= 0.0f ||` in the "significant units" test of the source (the factory loss, commented out in the
  DLL, kept as a comment in the Lua port): the factory is not needed to win (the win is the capture), so the designers left its loss
  survivable, and with a shared base a single lost factory would end the match for everyone. Not restored; `factory` is still resolved
  by `GetHandle` as in the source.
- `#define TEST_PORTAL` (disabled in the shipped source): the debug variant disguises the player as team 2, disables the
  waves and shortens the two timers to 15 s. It is a developer switch, not content; the faithful port keeps it `false`.
- `//StopAudioMessage(intro2Sound); //sound3Time = GetTime() + 5.0f;` after the portal shot: the cut early engineers'
  warning. `bd08003` ("That's the Chinese engineering team ...") is played one second after the APC arrives, which is where
  the line makes sense; before the APC exists it would be about nothing. Not restored.
- Dormant state the DLL declares and never reads (`objective1Complete`..`objective3Complete`, `scheduleLose1`,
  `waveHandle`): no behaviour to restore.

Authored paths the script never uses (documented, not wired): `spawn1` (a single point beside the portal, a leftover spawn
marker; the pilots use `spawn_pilot`) and `edge_path` (used by the weather as the playable box). Twenty-eight unlabeled
paths in the map (2 to 28 points each) are leftover AI scratch routes and have no name to reference.

### Voice lines [owner decision 2026-11-01]

The shipped lines are `bd08001`..`bd08007` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`). The
faithful body plays six of them; **`bd08005` is the only unused line** and is restored above. The contract test asserts
the script (body plus CR layer) names exactly the lines the repo has transcripts for.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **One human as "the player"**: the intro camera target, the `Valid`/`Healthy(user)` guards and the engineers' attack
  order take a single tank. See "Humans as the player".
- **Capture by a human of any team**: `GetTeamNum(apc) == 1` is a team-1-only test. See "Owned by the player".
- **The disguise on team 2**: the body disguises the boarded APC as team 2 (the Chinese). In co-op team 2 is a human slot, so
  the APC would look allied. `SetPerceivedTeam` maps 2 to 5 (the neutral 0 is unchanged).
- **The portal's units on team 2**: `BuildObjectAtPortal(..., 2, ...)` maps to 5 (nothing is built on team 2).
- **A host skip hangs the shared shot**: see above.
- **Setup publishes before the presentation resets**: `Start()` names the two nav beacons (`SetObjectiveName`). The
  runtime's `Start()` clears the presentation stream, so the CR callback runs `campaignRuntime.Start()` right after
  `M = NewState()` and before the handles; both names reach every guest.
- **Reinforcements after the result / reprogramming**: the extras stop (see "Scaling").
- **Loads during the films**: ended as described above.
- **Objectives and the APC marker after a load**: the runtime's `Load` resets the presentation (objective list, nav names,
  `SetObjectiveOn`), and the body publishes them only when a stage begins. After a load (authority, once the opening is
  done) the CR layer republishes the two nav names and rebuilds the list from the mission state with the body's own names
  and colours: portal shot open: `bd08001` white; engineers' pilot out or walked into the portal (`pilotSpawned1` or
  `apcPilotTime2` armed): `bd08001`, `bd08002` white, with the marker on a healthy APC; portal reprogrammed: `bd08002`
  green, `bd08003` white, marker on.
- **A nil audio handle**: the win and lose gates test `sound ~= nil and Done(sound)`, so a line that returns no handle would
  strand the mission. The CR `AudioMessage` wrapper turns nil into 0, which `Done` already counts as finished (the body
  tests `~= 0` before stopping the intro line, and tests nil/0 alike elsewhere).
- **`TEST_PORTAL` debug branch**: `SetPerceivedTeam` on the nearest-human token disguises the host's ship instead.
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line has a subtitle in `Text/` (`Test-Bdmisn08CoopContract.py`); `audioSubstitute` is empty. The `.des`
  debriefs ship with the game.
- The body already carries its own documented port fixes (health of a missing object, a failed APC build counted as an
  APC loss, `RemovePilot`/`GetIn` for the native pilot-field writes).

## Weather: Ganymede

`Environment.Init` in `orbit` mode (the sun's real path, a short eclipse, Jupiter-shine at night: the same options as
`misn12cr` and `bd03cr`) plus `CREuropaWeather` with `CRGanymedeSitesBD08`, networked through the runtime (seeded
timeline from the host, host-chosen plumes/quakes/surges over the ordered stream as
`EuropaState`/`EuropaPlume`/`EuropaQuake`/`EuropaSurge`, `Save`/`Load` state, `AnnounceState`). No new weather module:
Ganymede reuses the Europa director for an icy, airless Jovian moon. `Environment.BindWeatherSensors("Ganymede", ...)` is
registered once per start from the runtime's update hook on every peer. If the module or the sites module is missing, or
any weather call errors, the mission runs without weather and logs once. The site file has three vents (all in the Black
Dog base: they are the geysers the base is built on), so plumes stay enabled.

Beats (host/offline only, each once, tied to the mission's own moments; the director never damages):

| Moment | Weather |
| --- | --- |
| Start, the intro | level 1 (Quiescent) |
| The portal shot opens (`cameraReady[1]`, "massive electromagnetic activity", `bd08002`) | level 2, a surge (4 s, 0.5) and a plume from the first vent |
| The engineers' APC comes through (`apc` set) | level 3 |
| The portal is reprogrammed (`portalReprogrammed`, `bd08004`) | level 4, a quake (0.35, 3 s), a surge (6 s, 0.8) and plumes from the other two vents |
| The captured APC wins (`won`) | forced level released, back to level 1 |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn08Coop.lua            # offline == faithful, 1-4 peers, scaling, films, captures, results, weather
lua5.1 Tools/Test-Bdmisn08Presentation.lua    # E/A/C protocol on a guest
python Tools/Test-Bdmisn08CoopSourceParity.py # bd08cr.lua minus CR regions == bdmisn08.lua
python Tools/Test-Bdmisn08CoopContract.py     # labels/paths/teams in bd08cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-BlackDog08.lua              # the faithful port, unchanged
python Tools/Test-BlackDog08SourceParity.py   # the faithful port against the C++ reference
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change; the four co-op commands above are
the step to add. The contract test checks `Config/bd08cr.ini`, `Config/crbd.ini` and `Missions/bd08cr.vxt` only
when they are in the tree and says which it skipped.

## Inferences and open questions

- `BuildObjectAtPortal` is not part of the runtime's ticket system, so the portal arrivals are not concealed from a human
  standing at the portal and are not subject to the 460 m rule. They are visible by design (a human who guards the portal
  sees every arrival, as in the original).
- The extras are a CR inference: staggered by 2 s so they do not stack on the portal's output point (unverified on the
  real portal), one extra queue shared by all attackers.
- The 12 s host-skip arrival is a CR inference; the real shot length is unknown.
- The mock `IsTouching` radius (30 m) is a test assumption. The engine's contact radius for the pilot reaching the portal and
  the return pilot reaching the APC is as in the faithful port (untested on the real map).
- `GetIn` boarding is asynchronous in the engine and host-run; whether the boarded APC's pilot and team replicate to every
  peer in the same frame is unverified, as is `SetPerceivedTeam(apc, 5)` hiding the APC from the AI of the other teams.
- `PortalOut`/`PortalIn`/`ActivatePortal` are host-side calls; whether the portal effect and the 50 m/s arrival velocity
  replicate to guests is unverified.
- A shot-down APC is recognised as dead at the start of the frame the body notices it; if the APC and the base die in the same
  frame the base line (`bd08006`) plays.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Intro: the same shot on every peer, looking at the host's ship; cameras balanced; the line `bd08001` ends the shot. A
   host skip does not hang it (it ends with the line); in a 2-4 player game a guest skip never ends it for the others.
2. 25 s later the portal shot: the portal powers up, `bd08002`, the sky stirs (level 2), a vent erupts; the portal shot ends
   on arrival.
3. Waves from the portal about every 4 s in fours, then a 30 s gap, until the APC: with 2-4 humans each unit has 1-2 staggered
   twins on the same path; none on team 2; the attackers are hostile to every human team.
4. At +90 s the APC comes through (`bd08003`, level 3), stops and the pilot gets out: marker and objective on every peer;
   the pilot walks into the portal.
5. Nine minutes later the return pilot appears (`bd08004`), the portal shuts down (level 4 with a quake, surge and plumes),
   the waves stop, "take the APC" is the objective. A human of ANY team entering the APC wins (`bd08007`, one shared
   victory, `bd08win.des`); the weather eases.
6. If nobody takes it within 25 s of the pilot boarding the APC drives home and the mission fails with `bd08lsea.des`
   (`bd08006`).
7. Shooting the APC down before the capture plays `bd08005` and fails with `bd08lseb.des`. Losing the Recycler or the
   command post, or the engineers' pilot, plays `bd08006` and fails with `bd08lsea.des`. Destroying the portal fails at
   once with `bd08lsec.des`.
8. A save/load during each film and in the wave phase; the weather sky and radar on guests; no weather error in the log.
