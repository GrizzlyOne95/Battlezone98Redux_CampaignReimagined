# Black Dog 04 co-op: Wolf in Sheep's Clothing (bdmisn04)

Shared offline / 2-4 player co-op port of Black Dog mission 4 (a disguise mission on Ganymede: the Black Dog pilots
walk in, commandeer a Chinese scavenger, snoop around the Chinese base, lift an alien data fragment with the base's
own hauler and bring it back to a drop zone through a Chinese strike). One `Missions/bd04cr.bzn` and one
`Scripts/bd04cr.lua` serve both modes. Companion to the faithful DLL port underneath (`Scripts/bd04.lua`,
[`References/BlackDog04Source/`](../References/BlackDog04Source/README.md)) and to
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`MISNS2_COOP.md`](MISNS2_COOP.md).
Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/bd04cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `bd04.lua` (`Tools/Test-Bdmisn04CoopSourceParity.py`): the body is **not edited at all**, the runtime's per-frame calls wrap its callbacks at the end of the file. Holds the runtime CONFIG, the native shadows and the restorations. |
| `Scripts/CREuropaWeather.lua`, `Scripts/CRGanymedeSitesBD04.lua` | The Ganymede weather (the Europa director, no new module) and the generated sites for this map. The generated vent list is **empty** (no `eggeizr1` geysers in `bdmisn04`). |
| `Missions/bd04cr.{bzn,vxt}`, `bdmisn04.{hg2,lgt,mat,trn}` | Map and companions (not part of this change). Every co-op player starts as the on-foot pilot `bsuser` (the `.vxt` is `bsuser ,`; the map start `asuser1_person` is the same). The Chinese side is team 5, the map's own enemy team 2 having been moved. |
| `Tools/Bdmisn04Fixture.lua`, `Test-Bdmisn04Coop.lua`, `Test-Bdmisn04Presentation.lua`, `Test-Bdmisn04CoopSourceParity.py`, `Test-Bdmisn04CoopContract.py` | Multi-peer fixture and tests (real map coordinates, the real `base_limit` polygon). `Test-BlackDog04.lua` / `Test-BlackDog04SourceParity.py` still cover the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The Black Dog side the body builds on team 1 (the intro pilot, the rendezvous pod, the six escorts, the five bombers) stays on team 1: shared, host-run. Extra starting recyclers are disabled (there is no Recycler in this mission). |
| 5 | The Chinese: the whole authored base (turrets, scavs, hauler, portal, walkers, silo), the two portal fighters and every strike or ambush unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5, and the portal build and the disguise are mapped by hand (below). |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at
chunk load. The mission has no `SetAIP`. `SetScrap(1, 8)` becomes 8 plus 10 per guest (no use for it here: nothing can be
built) and `SetPilot(1, 10)` goes to every human team.

### Humans as the player (`M.user`)

The DLL keeps **one** handle for "the player" and reads it in a dozen places (hide, disguise, scav, base entry, turret orders, tug, left-the-scav). In a network game the CR layer answers
`GetPlayerHandle()` with the human the current step is about (`Restored.Focus`), offline with the player exactly as the
body does:

1. a human **entering the base** (`base_limit`) while the entry has not been judged yet; a human outside the scav first, because
   being on foot there is what sets the alarm off;
2. the human **carrying the fragment** (`GetTug(fragment)`) until the pickup is judged;
3. the human **sitting in the commandeered scav** (`scav_3`);
4. else the host.

So the body's own tests become co-op rules without an edit: *any* human commandeering the scav completes the first
objective; the safe route (`trigger_1`) is judged for the scav pilot; any human walking into the base on foot sets the alarm
off (a human outside the scav never gets the scav's standing-order warning); *any* human lifting the fragment starts the
extraction; and the "left the scav" alarm after the fragment is identified fires when **no** human is in the scav any more.

Orders aimed at the player (`Attack(turret, user, 1)` for the nine turrets) go to the **human nearest to that turret**. The turrets
are ordered again when the set of human craft changes while the alarm is up (a human died, respawned, or changed craft), so
they never keep a dead handle. Offline the nearest human is the player.

`IsInfo("cbport")` and `IsInfo("obdataa")` are the local player's info panel, so a guest's inspection reaches the host
as a short `I` packet every 0.25 s while the panel shows the object; the host honours a report for one second
(the `misn08cr` pattern). `SetUserTarget(scav3)` is the local player's HUD target: a network game sets it on every peer by
the object's label (`BD4Target`).

### The disguise (this is a disguise mission)

The body calls `SetPerceivedTeam(user, 2)` **once**, when the opening shot ends, and never lifts it: what exposes the
infiltrators is the script's alarm (`doAttack`: turrets ordered onto the player at priority 1), not a change of perceived team.
The CR layer gives **every human** the same treatment on the same event: `SetPerceivedTeam(h, 5)` (the DLL's 2 mapped to the
co-op enemy) on every human handle, applied on every peer (`BD4Disguise`: the host's AI must see it on its copy of a guest's pilot).
It is lifted on the same events as in the body: never. Two refinements, both in the CR layer only:

- a human who **died and respawned** as a new pilot (also one killed inside a craft) is disguised again (the body has no respawn);
- after a **load** (the runtime resets the presentation) the objective list is rebuilt from the saved flags, the running one-minute timer is re-issued with its remaining time and the disguise is applied again;
- a pilot who **ejects** from a live craft is *not* disguised, exactly as in the body.

The opening hides the player (`Hide`) while a stand-in pilot walks the beacons; the CR layer hides and shows **every** human
(`BD4Hide`, on every peer, because Hide state diverges between peers otherwise). The portal film is a set piece, no human
goes through it, so there is no per-human teleport to handle.

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the ODFs `cvfigh`, `cvfighg`, `cvtnk` (every Chinese unit the body sends at the hauler). They become *tickets*: the
body gets a negative request id and the unit is built by the runtime on the next frames, with the body's later orders replayed
on it. Not scaled: the two portal fighters of the opening (`BuildObjectAtPortal`, stage props), camera pods (`apcamr`), the
intro pilot (`aspilo`), and all Black Dog units (escorts, bombers).

Events. The runtime region wraps `BuildObject` once: **a new frame or a new entry path is a new scaling event**, and the first
scaled unit of an event is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders.

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

The events: the **extraction strike** 30 s after the fragment is lifted (four events: 6 `cvfighg` at `chinese_scout_x6_spawn_point`, 2
at `attack_1`, 4 at `attack_2`, 3 `cvtnk` at `attack_3`: 15 units, 23 with four humans) and each **route ambush** (3 `cvfigh` at
`return_1`..`return_4`, sprung when the hauler comes within 300 m of the spot). All of them attack the hauler (priority 1 for the strike).
Cap: at most **26** live scaled units (`liveCap`; the runtime default is 12); extras are the only requests dropped for the cap.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry (the humans stand at the
fragment, 98 m from `attack_1`), the next hidden Chinese approach in `fallbackEntries` is used (`chinese_scout_x6_spawn_point`,
`attack_2`, `attack_3`, `return_2`, `return_4`, `return_3`, `return_1`, `attack_1`, first that is clear), else the request waits (saved
in `M.crcca`, so a save/load neither loses nor duplicates it). Reinforcements stop for good once the mission is won or lost
(`endedFlags`).

## Results

- Win: unchanged. The fragment within 50 m of the Drop Zone -> `bd04008` -> `SucceedMission(..., "bd04win.des")` once (the runtime holds
  the result until every guest acknowledged the preceding events). `wonFlags = { "won" }`: a loss after the win is ignored.
- Loss: the hauler or the portal destroyed -> `FailMission(..., "bd04lose.des")` once. Out of lives (every human): the same debrief. The
  leader departing fails every guest.

## Cinematics are shared and unskippable in a network game [owner]

Both films (the pilot's walk past the two beacons; the portal opening) are driven by `CameraPath` every frame, so the runtime's camera stream
carries them to every guest; `CameraCancelled` is false in a network game, offline both stay skippable. A skip on one machine releases only
that machine's camera (the runtime's rule); the opening still ends by the body's own paths (the shot's arrival, or the stand-in pilot reaching
`nav_2` plus two seconds, which needs no camera). The portal itself is opened and closed on every peer by label (`BD4Portal`):
`PortalOut` / `DeactivatePortal` are per-peer animation calls. A save during a film cannot resume it (the cameras are gone): the shot
then reports arrival until the body ends it by its own timer, and the films are never replayed.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer, apply offline and in co-op, and each has a flag (`RESTORED_*` at the top of the runtime
region of `bd04cr.lua`).

| Restoration | Cut block it comes from | Status in this map |
| --- | --- | --- |
| `RESTORED_USER_TARGET` | `navBeacon = BuildObject("apcamr", 1, "rv_scout");` `//SetUserTarget(navBeacon);` (at the fragment pickup) and, after the bombers, `navBeacon = BuildObject("apcamr", 1, "proposed_end_area"); SetName(navBeacon, "Drop Zone"); SetObjectiveOn(navBeacon); //SetUserTarget(navBeacon);` | Both lines come back: the rendezvous pod is the HUD target from the pickup, then the Drop Zone. A network game sets it for every human by label (`BD4Target`), the rendezvous pod being labelled for the purpose (`bd04rv`). The Drop Zone win test and objective are untouched. |

Unused shipped voice line [owner decision 2026-11-01]: the wav and `Text/bd04009.txt` ship with the game (`Config/durations.csv`
lists the wav) but the DLL never plays it. It plays once through the CR layer (`AudioMessage`: replicated to co-op guests, queued
behind a line still playing), is latched in `M.crcca.r` (kept by Save/Load) and sits behind `RESTORED_VOICE_LINES`.

| Line | Transcript | Trigger | Why it fits |
| --- | --- | --- | --- |
| `bd04009` | "Careful, Lieutenant. There aren't many of those." | The frame the fragment is lifted (`gotFragment`), once; it queues behind `bd04007` if that is still talking | Command's remark on the alien fragment as the hauler picks it up, between `bd04007` ("bring it back to the drop zone") and the bombers' arrival. |

Skipped, with the reason:

- `//doAttack = FALSE;` in the attack block: it would turn the permanent alarm into a one-frame pulse that the next frame cannot
  re-arm (`doAttack` is also set by the audio chain, so it would flicker), and nothing in the audio or objectives is written for a stand-down.
- The unused members `silo` (the label `silo` is in the map, a Chinese `cbsiloa`, and the body reads it into `M.silo` and
  nothing else), `fightersSpawned` and the third camera slots `cameraReady[2]` / `cameraComplete[2]`: they never had code, active or cut.
- The Chinese walkers `cvwalk0_walker` / `cvwalk1_walker` and their authored path `walker_path` are map content the DLL never touches: not
  cut script content, so nothing is invented for them.

Authored paths the script never uses (documented, not wired): `edge_path` (the playable box the weather uses), `portal_units` (the
body sends the portal fighters down `unit_path` instead) and `walker_path` (above). There is no authored path left over for the
bombers or escorts: `bomber_wing_x5_spawn_point`, `escort_units` and `rv_scout` are all used.

## Stock bugs fixed in the CR layer (the faithful body is untouched)

- **The one-minute check-in never expires on this map's clock.** The map's mission class is `MultSTMission`, which restarts the cockpit timer
  upward every frame, so `GetCockpitTimer() <= 0` is never true: the standing-order warning, the second line and the alarm that follow a
  minute of snooping never play, in co-op *and* offline on the same map. The CR layer shadows `StartCockpitTimer` / `GetCockpitTimer`:
  the host counts the 60 s itself (saved with the mission state) and shows the same timer on every peer. The faithful test shows the stock
  body never sees the zero under this clock.
- One hidden, disguised, targeted and inspecting player: see "Humans as the player" and "The disguise" (a stock single handle would ignore every human but one).
- Turrets left on a dead or replaced handle: see above.
- The portal opens and closes on every peer, not only the host.
- A save in the middle of a film: see "Cinematics".
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body or the CR layer names has a subtitle in `Text/` (`Test-Bdmisn04CoopContract.py`); `audioSubstitute` is empty.
  The `.des` debriefs ship with the game.
- The body already carries its own documented port fixes (`References/BlackDog04Source/README.md`: the timeout latch, the final Drop Zone test,
  the absolute success time, null-handle guards) and preserved quirks (the `trigger_1` latch, the ungated route ambushes, the one-time base-entry
  check). None is changed here.

## Weather: Ganymede

`Environment.Init` in orbit mode (the Jovian sun path, as for `misn12`) plus the **Europa director** (`CREuropaWeather`: Ganymede is also an
airless icy moon of Jupiter, no new module) with `CRGanymedeSitesBD04`, networked through the runtime (seeded timeline from the host, host-chosen
quakes and surges over the ordered stream, `Save`/`Load` state, `AnnounceState`) and bound to the sensor service (`Environment.BindWeatherSensors("Ganymede", ...)`, the
shared weather sensor policy). If the weather module or the sites module is missing, or any weather call errors, the mission runs without weather and
logs once. **The generated site table has no vents**, so no plume ever forms (every plume path returns at zero sites) and the
strike beat guards `TriggerPlume` with the vent count; quakes and surges still run. Beats (host/offline only, each once, tied to the
story): the portal tears open -> level 2 and an ice quake; the alarm (`doAttack`) -> level 3 and a radiation surge; the fragment lifted -> a
stronger quake; the strike (bombers, Drop Zone, Chinese fleet) -> level 4, quake and surge; victory -> `ReleaseForcedLevel` and calm; a loss
-> level 4. The director never damages.

## Tests

```sh
lua5.1 Tools/Test-Bdmisn04Coop.lua            # offline == faithful, 1-4 peers, disguise, focus, relay, timer, scaling, 460 m, saves, weather
lua5.1 Tools/Test-Bdmisn04Presentation.lua    # E/A/C protocol and this mission's four ops on a guest
python Tools/Test-Bdmisn04CoopSourceParity.py # bd04cr.lua minus CR regions == bd04.lua
python Tools/Test-Bdmisn04CoopContract.py     # labels/paths/teams/start file in bd04cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-BlackDog04.lua && python Tools/Test-BlackDog04SourceParity.py   # the faithful port, unchanged
```

The contract test checks `Missions/bd04cr.vxt` and the `.mpdes` only when they are present.

## Inferences and open questions

- **Authored craft and guests.** The scav (`scav_3`) and the hauler (`hauler_1`) are map-authored. Redux sends an authored object's handle as nil
  unless the OpenShim label-id hooks are installed (`AGENT_KNOWLEDGE_BASE.md` 3.3). Without them a guest sitting in one is invisible to the
  host and `CRCoop` keeps the session "not ready" (the body pauses; it does not crash). With the hooks the label travels as the id and everything above holds.
  The tests cover both (`nilAuthoredHandles` in the fixture). This is the first thing to confirm live.
- That the engine carries a pilot's perceived team into the scav it commandeers (the body assumes it) is unverified; the CR layer disguises
  the pilots exactly where the body does and adds nothing for vehicles.
- The engine's own scoring of a disguised human is unverified: whether turrets (`cvturr`) ignore a perceived-team-5 pilot until the alarm orders
  them is the DLL's design, not tested here.
- Scaling is per (frame, entry path), a CR inference; `liveCap = 26` instead of the default 12 so four humans' extras fit the strike.
- A group is hidden from the humans, so a watched approach brings the strike from another point: the order of `fallbackEntries` is a guess at
  which Chinese approaches are usable.
- The minute is host-counted and shown with the engine's own `StartCockpitTimer` on every peer; if the HUD keeps counting upward (the
  MultSTMission override) the number on screen is wrong while the logic is right.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Two clients, DX11: the walk-in film is the same on both (cameras balanced), both pilots are hidden for it and visible after; the portal
   opens on both screens with the fighters coming through.
2. Guest commandeers `scav_3` (needs the OpenShim label-id hooks): the first objective completes for everyone, the other scavs head out, the host's
   session does not stall.
3. Pilots on foot beside the scav are ignored by the turrets until the alarm: walk a foot human to the east edge of `base_limit` -> turrets fire at
   the nearest human; walk the scav past `trigger_1` first -> nothing happens.
4. Guest inspects the portal (`cbport`) -> the minute starts and counts on both HUDs; stay silent for 60 s -> the two standing-order lines and the alarm.
5. Guest inspects the fragment (`obdataa`) before then -> the timer stops everywhere, `bd04007` plays.
6. Guest hops into `hauler_1` and lifts the fragment: `bd04009` once on both, rendezvous pod targeted, escorts appear, 30 s later bombers, the Drop
   Zone and the Chinese strike (none visible at spawn), the Drop Zone is the HUD target.
7. Route ambushes from `return_1`..`return_4` when the hauler passes; the hauler at the Drop Zone -> `bd04008` -> one shared victory.
8. Hauler or portal destroyed -> one shared failure; a human dying mid-mission respawns at the rim and is ignored by the Chinese again.
9. The Ganymede sky renders on guests (orbit lighting, quake shakes at the portal and the pickup), no weather error in the log.
