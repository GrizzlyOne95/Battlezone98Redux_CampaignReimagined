# Chinese 5 co-op: Dire Straits (chmisn05)

Shared offline / 2-4 player co-op port of the Chinese mission `ch05`, a disguise-and-defence mission: the party starts as
Chinese scavengers disguised as Soviets, collects scrap, trails a Soviet convoy to learn where the Chinese base went, then
defends the relocated base against seven Soviet waves, a raid every four minutes, paratroopers and an artillery battery.
One `Missions/chmisn05cr.bzn` and one `Scripts/chmisn05cr.lua` serve both modes. Companion to the faithful port underneath
(`Scripts/ch05.lua`, tested by `Tools/Test-Chinese05Port.py`) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared
runtime). Pattern: [`BDMISN09_COOP.md`](BDMISN09_COOP.md) (a disguise mission with a shared "player"), closest in shape
[`BDMISN07_COOP.md`](BDMISN07_COOP.md) (Elysium weather, waves, a defended base).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/chmisn05cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch05.lua` (`Tools/Test-Chmisn05CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows, the restorations and the callback wrappers. |
| `Scripts/CRElysiumSitesCH05.lua`, `Scripts/CRElysiumWeather.lua` | Elysium weather (the Venus director re-dressed as a blue-grey storm world, generated sites for this map: three geysers, no sulphur). Written separately; not part of this change. |
| `Missions/chmisn05cr.{bzn,vxt}`, `chmisn05.{hg2,lgt,mat,trn}`, `Config/chmisn05cr.ini` | Map, vehicle list (`cvscav`, `cvtnk`) and multiplayer listing. Not part of this change. |
| `Tools/Chmisn05Fixture.lua`, `Test-Chmisn05Coop.lua`, `Test-Chmisn05Presentation.lua`, `Test-Chmisn05CoopSourceParity.py`, `Test-Chmisn05CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/Test-Chinese05Port.py` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). Team 1 also owns the shared Chinese base: the recycler, the silo, the repair depot, the supply depot, two towers, the convoy and the scouts. |
| 5 | The Soviets: the enemy base (towers, power plants, a turret tank), the tug and its escort, every wave, the paratroopers, the artillery. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5, the `BuildObject` shadow does the same for the direct builds, and the `SetPerceivedTeam` shadow maps its `2` to `5`. |
| 0 | Neutral: the daywreckers (`apwrck`), the map's scrap, the neutral scout the tug picks up. |
| 7 | Support (nothing uses it). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. Respawns rally on the map's `recycler` (it travels with the convoy). `SetPilot(1, 10)` is dropped in a network
game (the shared lives of CRCoop own that) and kept offline.

## Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one vehicle. The CR layer answers it with the runtime's nearest-human token
(`crcca_players`), with these meanings:

| Body use | Meaning with several humans |
| --- | --- |
| `GetDistance(user, x)` and `GetDistance(x, user)` (silo leash, trigger, tug sight, base nav) | The nearest living human. A removed or destroyed object is infinitely far (stock bug, below). |
| Stay within 250 m of the silo until the last fix (`ch05lsea`) | Fails only when **no** human is within 250 m: one human at the silo keeps the shift. |
| Stay beyond 175 m of the tug (`ch05lseb`) | Fails when **any** human is within 175 m (nearest rule). |
| Stay within 500 m of the tug (`ch05lsed`) | Fails only when **every** human is beyond 500 m. A destroyed tug is a lost convoy (the dead handle is "infinitely far"). |
| `SetPerceivedTeam(user, t)` | Every living human. `2` is the co-op enemy `5`; the reveal (`1`) puts each human back on their own team. The body re-issues the disguise every frame while the cover holds, so a respawned ship is disguised too. |
| `GetScrap(1) >= 3` (the scrap gate) | The most scrap any human team holds: a guest's scav fills its own team's pool. `SetScrap(1, 0)` zeroes every human team; `scrapPerGuest = 0` so the gate does not open at the start. The later `SetScrap(1, 50)` stays the base's. |
| `Attack(unit, user)` (the sappers of wave 3) | The living human nearest the unit. A unit that is still a spawn ticket remembers the order and receives it when built. |
| `SetUserTarget(nav1)` | Local to the player in the engine; a network game also marks the nav for every peer. |
| `SetName(h, ...)` | Stock `SetObjectiveName`: the name travels to every peer ("Last GPS Fix", "Base"). |

## The disguise

The mission's cover is the body's: the party is perceived as Soviet (`SetPerceivedTeam(user, 2)` every frame while
`stayTeam2`) from the first frame until the base is attacked (`ch05006`); ten seconds later the body reveals the party
(`SetPerceivedTeam(user, 1)`). The CR layer only makes both reach every human. The scouts (`cvfighh`, team 1) are perceived
as team 5 as in the body.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the Soviet combat craft built at the six wave entries and the raid entry, i.e. `svwalk`, `svhraz`, `svtank`,
`svltnk`, `svfigh`, `svrckt`, `svapc` at `wave_1`, `wave_2`, `wave_4`, `wave_5`, `wave_6`, `wave_7` and `annoy_1`. They become tickets (a
negative request id) built by the runtime on later frames, with the body's later orders replayed. A new wave (a new frame
or a new entry path) is a new scaling event: the first scaled unit is mirrored by `min(floor(humans / 2), 2)` extras of
the same kind, entry and orders.

| Humans | Extras per wave |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Not scaled, built directly on team 5: the tug and its two escorts, the artillery pair and its four escorts, wave 3's soldiers
and sappers, the paratroopers (`sssold`, 400 m up), and the neutral daywreckers.

Cap: at most **40** live scaled units (`liveCap`; the biggest wave is 14 and earlier waves are still marching); only extras are
dropped for it. No pop-in: a ticket is never built within 460 m of any human; if a human is near the authored entry the next
clear approach of `fallbackEntries` (`wave_7`, `annoy_1`, `wave_6`, `wave_1`, `wave_5`, `wave_4`, `wave_2`) is used, else the
request waits (saved, so a save/load neither loses nor duplicates it). Reinforcements stop for good when the party has won or
lost (`wonFlags = won`, `endedFlags = lost, won`). The runtime builds two tickets a frame, so a wave takes a few frames.

The victory test is the body's: the thirteen `mustKill` primaries of wave 7. The co-op extras of that wave are not in that
list, so the CR layer holds the victory while any of them lives or waits as a ticket (`Restored.Wave7Alive`).

## The tug film: shared and unskippable

`CameraReady` / `CameraPath("haul_cam", 800, 0, tug)` run on the host; the runtime streams the shot to every guest. A skip
releases only the skipper's own camera and never the shared timing (the body's 15-second timer ends the film), offline and
in co-op alike except that offline a skip also ends the film (the body's `CameraCancelled` is honoured). A load during the
film takes the shot up again on the host (`S.doHaulCam`).

## Results

- Win: wave 7 dead, once, shared (the runtime holds the result until every guest acknowledged the preceding events), with the
  restored line `ch05008` first (below).
- Loss: strayed from the silo -> `ch05lsea.des`; seen by the tug -> `ch05lseb.des`; both producers (recycler and factory)
  destroyed -> `ch05lsec.des`; lost the convoy -> `ch05lsed.des`.
- Out of lives (every human out): `ch05lsec.des`, the closest generic debrief (a lost base). Leader departs: every guest fails.
- The body has no player-death rule; in a network game the shared lives decide, offline the engine ends the game.

## Restored content [owner decision 2026-11-01]

Each restoration lives only in the CR layer, applies offline and in co-op, and has a flag (`RESTORED_*` at the top of the
runtime region of `chmisn05cr.lua`). The original C++ is archived at the end of `Scripts/ch05.lua`.

| Restoration | Cut block it comes from | Status |
| --- | --- | --- |
| `RESTORED_SILO_TARGET` | `getBase()`: `// if (GetHealth(silo) > 0.0f) h[numH++] = silo;` | **Restored.** The silo is a base building the wave 3 soldiers and the paratroopers may pick, like the recycler and the factory. |
| `RESTORED_VOICE_LINES` | the declared-and-never-used `winSound`, and the shipped line `ch05008` | **Restored.** See "Voice lines". |

Not restored, with the reason:

- The cut/debug block of the first frame (a nav at `trigger_1`, `wave7Time = GetTime()`, `SetPerceivedTeam(user, 2)`, a
  `cvtank` for the player): a test shortcut that skips the mission, not content.
- `//RemovePilot(smokingUnit);` and the `smokingUnit` handle: no object of that name is ever built; nothing coherent to restore.
- `//recycler = BuildObject("cvrecy", 1, "convoy");`: the map already carries the recycler (`recycler`), which the body sends
  down `convoy_path`.
- The commented `//Goto(leadScout, "scout_path", 1);` lines for the followers: the body already forms them on the lead scout.
- Dormant state the DLL declares and never reads (`objective2Complete`, `objective3Complete`, `closeToScout`, `lose1Sound`,
  `lose2Sound`): no behaviour to restore.

Unused authored map content, documented and not wired: `edge_path` (the weather's playable bounds), `outer_limits` (a
five-point line along the map's west edge) and one unnamed two-point path with no label. The body never names them.

### Voice lines

The faithful body plays `ch05001`..`ch05007` and the Betty lines `abetty6` / `abetty14`. The one shipped line it never
plays is **`ch05008`** ("Good work, Scavenger Three... High Command considers that you have... redeemed yourself. You may
continue in command of the Elysium base.", 12.51 s, `Config/durations.csv`). Inference: it is the victory line. It answers
the briefing (`ch05001`: "Your worthless performance on Ganymede sickens me") and the debrief text `ch05win.des` ("You can
consider yourself reinstated at your old rank, Major"), and the C++ declares a `winSound` it never assigns. It is played when
the body ends the mission, and the debrief is delayed until it has finished (`WIN_LINE_SECONDS + 1`). The contract test
asserts that `ch05008` is the only unused `ch05` line and that the wait equals its shipped duration. No other `chNN` line
fits this mission (the unused ones belong to missions 01, 03, 04, 06 and 08).

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **One human as "the player"**: see "Humans as the player".
- **Dead handles read**: `GetDistance` on a removed or destroyed tug, scout or follower, and `GetTug` on a removed scout (the
  body keeps asking after the four-minute cleanup, and after any kill) are answered "infinitely far" / "none".
- **A line the engine cannot start**: `AudioMessage` would return no handle and the body only advances on a handle that
  reports done, so the chain (`ch05003` -> `ch05004` ...) stalled for ever. `AudioMessage` returns `0` instead of nil and
  `IsAudioMessageDone` treats nil/0 as finished.
- **Attack on a missing base**: `getBase()` returns nothing once the recycler and the factory are gone; the order is skipped.
- **Load loses the presentation**: the runtime's Load resets it, so the objective list, the markers, the nav names and a film
  in flight vanish. The lists are remembered and republished on the frame after a load.
- **Orders on concealed spawns**: orders aimed at the player on a ticket wait for the real unit.
- **Reinforcements after the result**: the waves and the raid stop when the party has won or lost.
- **Enemy team**: the body builds and disguises on the map-native team 2; the runtime maps it to the co-op enemy 5.
- **Scrap gate**: see "Humans as the player".
- **Local-only UI**: `SetUserTarget` and `SetName` reach every peer.
- The body already carries its own documented port fixes (the formation order, the wave 7 timer, the altitude vector of the
  paratroopers, the empty-pilot escorts).

## Weather: Elysium

`CRElysiumWeather` with `CRElysiumSitesCH05`, networked through the runtime (seeded timeline from the host, host-chosen strikes
and fog over the ordered stream, Save/Load state, `AnnounceState`). If the module or the sites module is missing, or any weather
call errors, the mission runs without weather and logs once.

Beats (host/offline only, each once, tied to the mission's own moments):

| Moment | Weather |
| --- | --- |
| Start | level 1 (calm), held |
| The first scrap sends the scouts (`scoutsSpawned`) | level 2 |
| The tug rolls in (`tugSpawned`) | level 3 |
| The base is attacked (`trigger2`, `ch05006`) | level 4 and a strike over `base_1` |
| The siege is scheduled (the first wave) | level 4 and a strike at `wave_1` |
| The fourth wave (the tanks) | level 5 |
| The artillery is located (`artl1`) | a strike at `artl_1` |
| The last wave (`wave7Spawned`) | level 5 for 100 s (12 s blend) |
| Victory (`won`) | level 2 |

## Tests

```sh
lua5.1 Tools/Test-Chmisn05Coop.lua            # offline == faithful, 1-4 peers, disguise, scrap gate, film, scaling, 460 m, victory line, results, load, weather
lua5.1 Tools/Test-Chmisn05Presentation.lua    # the E/A/C protocol through a real guest, then the leader's own stream
python Tools/Test-Chmisn05CoopSourceParity.py # chmisn05cr.lua minus CR regions == ch05.lua
python Tools/Test-Chmisn05CoopContract.py     # labels/paths/teams in chmisn05cr.bzn (skips with a message if the map is absent)
python Tools/Test-Chinese05Port.py            # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` and `Tools/Test-CoopAuthoredLabels.py` are not edited by this change.
The labels the script presents to guests by `GetHandle` are `silo` and `recycler`; every other object it marks or names is
built at run time and travels under the runtime's `crcca_N` label.

## Inferences and open questions

- Whether removals the host makes (the map's scrap, the ns* objects, the tug and its escorts, the scouts) reach the guests by
  the engine's own replication. They are plain `RemoveObject` calls, as in the body; the runtime's labelled `RemoveObject` is
  not used because the scrap sweep would flood the ordered stream.
- Whether `SetPerceivedTeam` set by the host on a remote human's ship takes effect for the host-run AI (assumed, as in `bdmisn09`).
- The nearest-human rule makes the strict leashes lenient (one human at the silo, one human in sight of the tug); the "seen"
  rule is strict (any human within 175 m). Both are CR decisions.
- `ch05lsec.des` is used for the out-of-lives failure; no shipped `ch05` debrief covers it.
- The silo is a new target for the soldiers and paratroopers; the silo is not a failure condition (the body still fails on the
  recycler and the factory).
- The Soviet `svturr` turret tank, towers and power plants are authored on team 5 and are not scripted.

## Live checklist (unrun)

1. Start: each human in a scav (`cvscav`) or tank near the silo, disguised from frame one, `ch05001`; wander more than 250 m
   from the silo (every human) and the shift fails (`ch05lsea`).
2. Any human picks up 3 scrap: four scouts leave `scout_1`/`scout_2` for the fix; `ch05002` near the silo, the scouts vanish at
   `trigger_1`, `ch05003`, `ch05004`, the "Last GPS Fix" nav appears with its name and marker on every peer.
3. A human within 400 m of `trigger_1`: the tug appears, the film plays on every peer and cannot be skipped (a skip frees only
   that player's camera), `ch05005`, the scrap is cleared, the tug is marked. Any human within 175 m of the tug: `ch05lseb`.
4. The tug carries the scout west; every human more than 500 m away: `ch05lsed`.
5. At `trigger_2`: `abetty6`, `abetty14`, `ch05006` (each once), the convoy (recycler, factory, constructor, two escorts)
   drives to the base, 50 scrap, the "Base" nav; ten seconds later enemies see the party as human again.
6. Four minutes later the siege: wave 1 at once, wave 2 after 5 minutes... wave 7 after 22; each wave appears out of sight of
   every human, with the extras for 2-4 players; a raid every four minutes; paratroopers every four minutes.
7. `ch05007` and the artillery to the west; destroy both guns and the daywreckers stop.
8. Kill wave 7 and its extras: `ch05008`, then the debrief 13.5 s later, once, on every peer.
9. A save/load at each stage (before the fix, in the film, after the convoy): objectives, nav names and markers republish, no
   duplicate wave; weather sky on guests; no weather error in the log.
