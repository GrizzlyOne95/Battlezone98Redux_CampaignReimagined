# Black Dog 9 co-op: Grand Theft Portal (bdmisn09)

Shared offline / 2-4 player co-op port of the Black Dog mission `bd09`, a disguise mission: the party starts in stolen
Chinese APCs, one human takes the first of five Chinese tracked tanks, the convoy drives to three nav beacons while the
party stays inside it, and everyone must reach the Chinese portal. One `Missions/bd09cr.bzn` and one
`Scripts/bd09cr.lua` serve both modes. Companion to the faithful port underneath (`Scripts/bdmisn09.lua`, tested by
`Tools/Test-BlackDog09.lua`) and [`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern:
[`MISNS2_COOP.md`](MISNS2_COOP.md), closest sibling [`BDMISN02_COOP.md`](BDMISN02_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd09cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bdmisn09.lua` (`Tools/Test-Bdmisn09CoopSourceParity.py`). Holds the runtime CONFIG, the native shadows and the restoration. |
| `Scripts/CRElysiumSitesBD09.lua`, `Scripts/CRElysiumWeather.lua` | Elysium weather (the Venus director re-dressed as a blue-grey storm world, generated sites for this map: two geysers, no sulphur). Written separately; not part of this change. |
| `Missions/bd09cr.{bzn,vxt}`, `bdmisn09.{hg2,lgt,mat,trn}`, `Config/bd09cr.ini` | Map, vehicle list (`cvapc` only) and multiplayer listing. Not part of this change. |
| `Tools/Bdmisn09Fixture.lua`, `Test-Bdmisn09Coop.lua`, `Test-Bdmisn09CoopSourceParity.py`, `Test-Bdmisn09CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Tools/Test-BlackDog09.lua` still covers the faithful port, unchanged. There is no Presentation test: the mission has no camera. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The nav beacons stay on team 1. |
| 5 | The Chinese: the base, the five tracked tanks `cvtnk1..5`, the turret tanks, the portal and every ambush unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5 and the `SetPerceivedTeam` shadow maps its `2` to `5`. |
| 7 | Support (nothing uses it). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once
at chunk load. `SetScrap(1, 0)` stays 0 (`scrapPerGuest = 0`: the mission has no production). `SetPilot(1, 0)` is
dropped in a network game (the shared lives of CRCoop own that) and kept offline. Respawns rally on `cvtnk1`, the
convoy's lead tank.

## Humans as the player

The DLL's "player" is `GetPlayerHandle()`, one vehicle. The CR layer answers it with the runtime's nearest-human token
(`crcca_players`), and gives each use the meaning a disguise mission needs:

| Body use | Meaning with several humans |
| --- | --- |
| `Distance(user, x)` (beacons, trigger, portal range, straying) | The nearest living human (`farthestTargets` is empty). Straying (`> 75 m` from all four convoy tanks) therefore fires only when no human is with the pack. |
| `Odf(user, "cvapc")` (the briefing gate and its exact complement, the exposure test) | **Every** living human is in a stolen APC. One human leaving the APC before the briefing exposes everyone (the single-player rule, shared). A missing remote handle never exposes. |
| `Odf(user, "cvtnkb")` (the ten-minute departure timer) | **Any** living human is in a tracked tank. The timer starts when no human is in one. |
| `SetPerceivedTeam(user, t)` | Every living human. `2` is the co-op enemy `5`; a reveal (`1`) puts each human on their own team and ends the disguise for good, because the body never restores it. |
| `user == cvtnk1` (taking the first tank) | While the first tank is unclaimed and the briefing is done, `GetPlayerHandle` returns the human sitting in `cvtnk1`; at every other time the token. Any human can take it. |
| `Attack/Goto(unit, user)` | The living human nearest the unit. A unit that is still a spawn ticket remembers the order and receives it when built. A tank a human is driving is never ordered (the convoy skips it, the exposure hunt skips it). |
| `IsTouching(user, portal)` | Every living human has touched the portal (sticky per player, so a human who went through and died or respawned still counts; a human with no ship is not waited for). See "The portal". |

### The disguise reaches every human

The map authors the disguise (`perceivedTeam` 5) only on the host's own APC `svapc2_apc` and on the five tanks. In co-op
every human's ship is disguised from the first frame, and so is every ship a human becomes while the cover holds (the
pilot after ejecting, the stolen tank, a respawn), once per ship, until the body reveals the party. The body's own
every-frame `Perceived(2)` while `oneOfTheEnemy` runs through the same shadow. The cover is lost on exactly the events
the body loses it: leaving the APC before the briefing, straying, and the ambush firing.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: `cvfigh`, `cvltnk`, `cvhtnk`, `cvrckt`, `cvtnk`, i.e. every enemy craft the body builds. They become tickets
(a negative request id) built by the runtime on later frames, with the body's later orders replayed. Not scaled: the three
team-1 nav beacons. A new frame is a new scaling event: the first scaled unit is mirrored by `min(floor(humans / 2), 2)`
extras of the same kind, entry and orders. The events are the eleven-unit ambush and the final five tanks.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **16** live scaled units (`liveCap`); only extras are dropped for it. No pop-in: a ticket is never built within
460 m of any human; if a human is near the authored entry the next clear approach of `fallbackEntries`
(`spawn_deviate5`, `6`, `2`, `3`, `4`, `1`) is used, else the request waits (saved, so a save/load neither loses nor duplicates
it). Reinforcements stop for good when the party has won or lost (`wonFlags = won`, `endedFlags = lost, won`).

A runtime hazard fixed here: the runtime rewrites every state value equal to a built ticket's negative id, and the body's
disarmed tank timer is `-1`. The first ticket would turn it into a unit handle (a Lua error). Tickets start at id 2.

## The portal

`ActivatePortal` is a local effect of the object, so the CR layer presents it on every peer (`presentationOps.PortalOpen`;
each peer opens its own copy of the map's `portal`), the same way `bd05cr` does for its pulse. It opens once, when the
nearest human is within 250 m (`bd09008`).

Victory needs **every living human** to have touched the portal: the body's `IsTouching(user, portal)` is true when each has,
and then ends the mission once for everyone (`bd09win.des`). The first human through does not end it. A dead human is not
waited for; a respawned human must go through. *Owner question:* if "first through wins" is preferred, drop the
`IsTouching` shadow.

## Results

- Win: as above, once, shared (the runtime holds the result until every guest acknowledged the preceding events).
- Loss: the portal destroyed -> `bd09lseb.des` (one second later); the ten-minute departure -> `bd09lose.des`.
- Out of lives (every human out): `bd09lose.des`, the generic debrief. Leader departs: every guest fails.
- The body has no player-death rule; in a network game the shared lives decide, offline the engine ends the game.

## Restored content [owner decision 2026-11-01]

Each restoration lives only in the CR layer, applies offline and in co-op, and has a flag (`RESTORED_*` at the top of the
runtime region of `bd09cr.lua`). The original C++ is in `References/BlackDog09Source/BlackDog09Mission.cpp`; the
faithful port keeps both disabled calls as comments.

| Restoration | Cut block it comes from | Status |
| --- | --- | --- |
| `RESTORED_COMPLETED_OBJECTIVE` | `//AddObjective("bd09001.otf", GREEN);` right after `ClearObjectives()`, before `AddObjective("bd09002.otf", WHITE)` (end of `bd09003`) | **Restored.** The objective list now shows the finished first objective in green above the second, which is how the body itself ends (`bd09001` and `bd09002` green, `bd09003` white). Done in the `AddObjective` shadow, only when the list was just cleared. |
| `//SetPerceivedTeam(user, 2);` after the briefing line | The disguise block | **Not restored, redundant.** The body already applies the disguise every frame (`if oneOfTheEnemy then Perceived(2)`). |

Unused authored map content, documented and not wired: `edge_path` (the weather's playable bounds), `portal_in` (a
two-point path at the portal; `bdmisn05` uses its twin for the retreat) and `camera_portal_escape` (a camera spot beside
the portal). The body has no camera, only a dormant "camera info" record, so no film is restored. Dormant state the DLL
declares and never reads (`objective3Complete`, `cameraReady`, `cameraComplete`, `sound5`, `sound7`): no behaviour to
restore. The missing SOE #9 is not invented.

### Voice lines

All eight shipped lines `bd09001`..`bd09008` (wavs plus `Text/` transcripts, durations in `Config/durations.csv`) are
played by the faithful body; the contract test asserts the script names exactly the lines the repo has transcripts for.
There is **no unused shipped voice line** for this mission, so nothing is slotted in (the only other `Grand Theft Portal`
audio is the briefing `intro09`).

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **One human as "the player"**: see "Humans as the player".
- **A line the engine cannot start**: `AudioMessage` would return no handle and the body only advances on a handle that
  reports done, so the chain (`bd09001` -> `bd09002` ...) stalled for ever. `AudioMessage` returns `0` instead of nil and
  `IsAudioMessageDone` treats nil/0 as finished.
- **Load loses the presentation**: the runtime's Load resets it, so the objective list and the two markers the body sets once
  (`cvtnk1`, the portal) vanish. The list is remembered and republished with the markers from the saved state on the
  frame after a load (`hooks.load` -> flag -> `Restored.Run`). The mission has no cockpit timer.
- **Orders on concealed spawns**: orders aimed at the player on a ticket wait for the real unit.
- **Orders on human-driven tanks**: the convoy `Goto` and the exposure `Attack` would order a tank a human drives; skipped.
- **Reinforcements after the result**: the ambush and the last five stop when the party has won or lost.
- **Ticket id collides with the disarmed timer**: see "Scaling".
- **Enemy team**: the body builds and disguises on the map-native team 2; the runtime maps it to the co-op enemy 5.
- **Portal pulse is local**: see "The portal".
- The body already carries its own documented port fixes (the exposure ambush armed once, the disarmed tank timer, the
  latched timeout failure, guarded handles).
- Not carried over: the cameras (none), the weather sensor binding (the Elysium director scrambles radar itself).

## Weather: Elysium

`CRElysiumWeather` with `CRElysiumSitesBD09`, networked through the runtime (seeded timeline from the host, host-chosen
strikes and fog over the ordered stream, Save/Load state, `AnnounceState`). If the module or the sites module is missing,
or any weather call errors, the mission runs without weather and logs once. No `ops` are listed: the module shares the
Venus op names, which are the runtime default.

Beats (host/offline only, each once, tied to the mission's own moments):

| Moment | Weather |
| --- | --- |
| Start, the briefing | level 1 (calm), held |
| A tank is taken (`objective1Complete`) | level 2 |
| The first beacon is reached (`gotoBeacon2`) | level 3 |
| "That's not the path" (`gotoBeacon3`, `bd09005`) | level 4 |
| The cover is blown (`deviateSpawned`) | level 5 for 100 s (12 s blend) and a strike at `spawn_deviate1`, then back to 4 |
| The last five (`trigger1`) | level 5 |
| Through the portal (`won`) | level 2 |

## Tests

```sh
lua5.1 Tools/Test-Bdmisn09Coop.lua            # offline == faithful, 1-4 peers, disguise, capture, scaling, 460 m, portal, results, load, weather
python Tools/Test-Bdmisn09CoopSourceParity.py # bd09cr.lua minus CR regions == bdmisn09.lua
python Tools/Test-Bdmisn09CoopContract.py     # labels/paths/teams in bd09cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-BlackDog09.lua              # the faithful port, unchanged
```

The workflow `.github/workflows/campaign-validation.yml` is not edited by this change. The contract test checks
`Config/bd09cr.ini`, `Config/crbd.ini` and `Missions/bd09cr.vxt` only when they are in the tree and says which it
skipped.

## Inferences and open questions

- Whether the host sees a guest who climbs into a map-authored tank as that tank (`ForEachPlayerHandle` returns the guest's
  new handle; the fixture assumes handles of map objects match across peers). If not, only the host (or a human whose
  handle the host knows) can take `cvtnk1`.
- Whether `SetPerceivedTeam` set by the host on a remote human's ship takes effect for the host-run AI (assumed).
- Straying uses the nearest human, so a lone wanderer is not punished while a human is with the pack; the portal needs
  everyone. Both are CR decisions.
- The portal's engine contact effect (does it remove the toucher?) is unknown; the sticky per-player latch is safe either way.
- A respawned human lands near a teammate or the lead tank and is disguised as long as the cover holds.

## Live checklist (unrun)

1. Start: each human in a Chinese APC, disguised from frame one (enemy units ignore the party), `bd09001`, the first tank marked.
2. 23 s later `bd09002`; leave an APC earlier and the whole party is exposed (the ambush after 1 s, `bd09007`).
3. Any human climbs into the first tank: objective 1 green, `bd09003`, the first beacon, the convoy sets out; a tank a
   human drives is not ordered.
4. Beacons: `bd09004` / `bd09005` when the first human arrives, `bd09006` and the portal marker on every peer.
5. Stay with the convoy: no ambush. Leave it (no human within 75 m of a tank): the cover drops, `bd09007`, eleven units plus
   extras from hidden approaches, the turret tanks hunt a human.
6. Within 200 m of `trigger_1`: the last five tanks once.
7. Within 250 m of the portal: it opens on every peer, `bd09008`; the mission ends only when every human is through.
8. Portal destroyed / ten minutes out of every tank: one shared failure with the right debrief.
9. A save/load at each stage: objectives and markers republish, no duplicate wave; weather sky on guests; no weather
   error in the log.
