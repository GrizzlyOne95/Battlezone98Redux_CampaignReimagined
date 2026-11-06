# Chinese 07 co-op: Leave Home (chmisn07)

Shared offline / 2-4 player co-op port of Chinese mission 7 (a disguise-and-ambush mission on Europa: a Chinese sniper
slips into a Soviet comm tower in a Russian uniform, learns which bridge the convoy will use, detonates the crates at
the bridge, finds the APC that carries the relic, shoots it, and walks back to the drop zone through the Soviet
reinforcements). One `Missions/ch07cr.bzn` and one `Scripts/ch07cr.lua` serve both modes. Companion to the
faithful port underneath (`Scripts/ch07.lua`, [`References/Chinese07Source/`](../References/Chinese07Source/)) and to
[`CCA_COOP_RUNTIME.md`](CCA_COOP_RUNTIME.md) (the shared runtime). Pattern: [`BDMISN04_COOP.md`](BDMISN04_COOP.md) (the
other disguise mission). Status: **host-tested only**; nothing here has run in the game (see "Live checklist").

## Layout

| File | Role |
| --- | --- |
| `Scripts/ch07cr.lua` | The faithful port plus marked `-- CR ... >>` / `<<` regions. Outside them it is exactly `ch07.lua` (`Tools/Test-Chmisn07CoopSourceParity.py`): the body is **not edited at all**, the runtime's per-frame calls wrap its callbacks at the end of the file. Holds the runtime CONFIG, the native shadows and the co-op fixes. |
| `Scripts/CREuropaWeather.lua`, `Scripts/CREuropaSitesCH07.lua` | The Europa weather and the generated sites for this map. The generated vent list is **empty** (no geysers in `chmisn07`). |
| `Missions/ch07cr.{bzn,vxt}`, `chmisn07.{hg2,lgt,mat,trn}` | Map and companions (not part of this change). The enemy team 2 was moved to team 5; guests are teams 2-4 at the `coop_spawn1`..`coop_spawn4` buoys; every co-op player starts as the on-foot sniper `ssuserb`. |
| `Tools/Chmisn07Fixture.lua`, `Test-Chmisn07Coop.lua`, `Test-Chmisn07Presentation.lua`, `Test-Chmisn07CoopSourceParity.py`, `Test-Chmisn07CoopContract.py` | Multi-peer fixture and tests (real map coordinates). `Test-Chinese07.lua` still covers the faithful port, unchanged. |

## Teams and ownership

| Team | Use |
| --- | --- |
| 1-4 | Humans (host on 1). The Chinese side the body builds on team 1 (the two bridge/drop-zone beacons, the five rescue pilots) stays on team 1: shared, host-run. Extra starting recyclers are disabled (there is no base to build). |
| 5 | The Soviets: the whole authored base, the fighters, mines and foot patrols, and every ambush, convoy or reinforcement unit. The body still says team 2; the runtime maps `BuildObject(..., 2, ...)` to team 5. |
| 0 | The comm-tower stand-in pilot (built neutral, as in the body). |
| 7 | Support (nothing uses it here). |

Only the authority (host, or the offline player) runs the body; guests only present. `SetAIControl(5, true)` runs once at chunk
load. The mission has no `SetAIP`. `SetScrap(1, 8)` becomes 8 plus 10 per guest (nothing can be built) and `SetPilot(1, 10)`
goes to every human team.

### Humans as the player (`M.user`)

The DLL keeps **one** handle for "the player". The CR layer answers `GetPlayerHandle()` with the runtime's `PLAYERS` token (offline
too, so there is a single code path): every `GetDistance(M.user, X)` is the **nearest human** to X. That makes the body's own tests
co-op rules without an edit: *any* human at the comm tower (30 m) starts the burglary; *any* human within 900 m of a zone trigger
springs that zone; *any* human within 160 m of a fighter or 350 m of the bridge trigger sets those off; ammo and repair pickups work
for whoever stands at them (below).

- `Attack(unit, M.user)` goes to the human **nearest to that unit** (nearest to its entry while it is a ticket).
- **The disguise.** The body disguises the player for the burglary with `SetPerceivedTeam(user, 2)`, the Soviet side, and gives the
  player's own side back with `SetPerceivedTeam(user, 1)`. In this map the Soviets are team **5**, so the CR layer maps 2 -> 5 and
  applies it to **every human** (teams 1-4) on **every peer** (`CH7Disguise`: the host's AI must see it on its copy of a guest's
  pilot). A perceived 1 is each human's *own* team (a guest on team 3 gets 3, not 1). `Test-Chmisn07Coop.lua` asserts, for 1-4
  humans, that all of them are perceived as 5 during the burglary (never 2), and are back on their own team after it.
- `Hide`/`UnHide` apply to every human on every peer (`CH7Hide`); `SetPosition(user, "burglar_exit")` becomes `CH7Exit`: every peer
  lifts **its own** pilot out of the tower (the host cannot teleport a guest's pilot), guests landing 4 m apart (`4 * (team - 1)`).
- **Pickups.** `Refill(M.user, ...)` reads the health/ammo of "the player": `GetCurHealth`, `GetMaxHealth`, `SetCurHealth`, `GetCurAmmo`,
  `GetMaxAmmo` and `SetCurAmmo` are shadowed so `PLAYERS` means the human nearest to a live pickup. A full ship leaves the pickup in
  place (the body's own rule). The green flash and the sound go only to the peer of the human who used the pickup (`CH7Pickup`, by team).
  `MakeExplosion` (the crate) is shown on every peer (`CH7Boom`).

## Scaling and concealed arrivals [owner rules, mission decisions]

Scaled spawns: the Soviet **infantry** the body builds (`ssusera` snipers, `sssold` soldiers, `sspilo` pilots): the seven zone ambushes,
the bridge squads, the back-up waves, the end guards. They become *tickets*: the body gets a negative request id and the unit is built by
the runtime on the next frames, with the body's `Attack` orders replayed on it. Not scaled: the turrets (`svturr`, fixed emplacements),
the convoy APCs and their `svfigh` escorts (they need real handles for `SetPilotClass`, `Goto` and `Defend2`, and the relic APC is the
win condition), the neutral stand-in, the beacons and the rescue pilots.

An event is **one frame**: the first scaled unit of a frame is mirrored by `min(floor(humans / 2), 2)` extras of the same kind, entry and orders.
(A zone builds up to 17 units from a dozen entry paths; one event per entry path would multiply the whole zone.)

| Humans | Extras per event |
| --- | --- |
| 1 (offline) | 0 |
| 2 or 3 | 1 |
| 4 | 2 |

Cap: at most **40** live scaled units (`liveCap`); extras are the only requests dropped for the cap.

No pop-in: a ticket is never built within 460 m of any human. If a human is near the authored entry, the next hidden Soviet approach in
`fallbackEntries` is used (`north_spn`, `east_spn`, `zn_7_snip_1_spn`, `zn_1_snip_1_spn`, `back_2_1_spn`, `pilo_end_1_spn`, `zn_2_snip_1_spn`,
`zn_5_snip_1_spn`: first that is clear), else the request waits (saved in `M.crcca`, so a save/load neither loses nor duplicates it).
Reinforcements stop for good once the mission is won or lost (`endedFlags`).

## Humans' result

- Win: the body's test (nearest human within 50 m of `nav_end`, relic APC down, all six end guards dead) plus two co-op conditions in
  the CR layer: **every human within 60 m of `nav_end`** (a human without a live ship counts as far) and **the first end guard's
  extras dead**. They are enforced through `IsAlive` of the last end guard (`Restored.HoldExtraction`), so the body is not edited: it
  sees a living guard and retries next frame. Then `ch07009` -> `SucceedMission(..., "ch07win.des")` once (the runtime holds the result
  until every guest acknowledged the preceding events). `wonFlags = { "won" }`: a loss after the win is ignored.
- Loss: the relic APC reaches `north_fail`/`east_fail` -> `ch07007` -> `FailMission(..., "ch07lose.des")` once. Out of lives (every
  human): the same debrief. The leader departing fails every guest.

## Cinematics are shared and unskippable in a network game [owner]

All four films (the flight over the base, the burglary, the north or east bridge) are driven by `CameraPath` every frame, so the
runtime's camera stream carries them to every guest; `CameraCancelled` is false in a network game, offline all stay skippable. A skip on one machine
releases only that machine's camera (the runtime's rule) and would leave the host's `CameraPath` waiting for an arrival that never comes, so a
network shot also ends at its flight time plus a margin (`CAMERA_ETA` = path length / (speed / 100), recomputed from the map by the
contract test). A save during a film cannot resume it (the cameras are gone): the first `CameraPath` after the load reports arrival.

## Restored content [owner decision 2026-11-01]

Cut-content restorations live only in the CR layer and sit behind `RESTORED_*` flags. **None of this mission's cut content is coherent
enough to restore**; the audit, so the decision can be reversed:

| Cut content | Why it is left cut |
| --- | --- |
| `getBase()` and its `#if 0` list (recycler, factory, armoury, silos) | The map has none of those objects, the function is never called. |
| The `#if 0` debugging block (`SetPerceivedTeam(user, 0)`, jump to the north film) | A developer shortcut that would skip the burglary. |
| `//if (objective1Complete)` around the seven zone ambushes | The designers shipped the ambushes live from the first minute (the zones start 740 m+ from the landing point); gating them on the burglary would remove the early game's pressure. |
| `/* convoySpawned && */ !triggered` | Would hold the bridge squad until the convoy exists (14 minutes); the shipped objective flip at the bridge is the design. |
| `//h = BuildObject("sssold", 2, "back_1_5_spn")` ... `back_2_6_spn` | Already live: `backup4` builds exactly these four. |
| `figh1Time`, `figh2Time`, `figh3Time`, `burglarStopTime`, `detected`, `gotInFighter`, `gotOutOfFighter`, `inHauler` | Declared and initialised, never read: no code, active or cut, to restore. |

Authored content the script never touches (documented, not wired, nothing invented):

- Paths: `edge_path` (the playable box the weather uses), `foot_1_path`, `foot_2_path`, `foot_3_path`, `foot_4_path`, `figh_1_path`, `figh_2_path`,
  `figh_3_path` (patrol routes for the foot soldiers and fighters; the DLL never issues `Patrol`/`Goto` with them, the map's own orders
  are all they have).
- Units: `figh_2_3` (a Soviet fighter 104 m from the landing point: giving it the 160 m attack rule would open fire on all four humans in the
  first seconds, so the fighter table stays at seven) and `pilot_1`, `pilot_2`, `pilot_3`, `pilot_4`, `pilot_5`, `pilot_6` (six Soviet pilots scattered over the map).

Unused voice lines [owner decision 2026-11-01]: **none.** `ch07001`..`ch07009` is the whole shipped catalogue of the mission
(`Config/durations.csv`, `Text/`), and the body plays all nine. The neighbouring families were surveyed for shipped, unplayed
`chNNxxx` lines (`ch01010`, `ch03007`, `ch04004`, `ch04005`, `ch05008`, `ch06007`, `ch08001`..`ch08009`): every one is another mission's
(`ch06007`, "...You are required for a delicate mission on Europa", is the previous mission's debrief; `ch08xxx` is the next
mission's briefing), so none fits here and none is slotted.

## Stock bugs and co-op fixes in the CR layer (the faithful body is untouched)

- **The burglary cannot end in a network game if the stand-in never vanishes.** The body ends it when the stand-in reaches `fake_vanish` (+3 s) or
  the player skips; a network game cannot skip, so a stand-in that is blocked would hold every human for ever. The CR layer ends the sequence
  25 s after it started if the 3-second timer was never armed (the walk is 32 m).
- **A skipped shared film hangs the host** (above): the network flight-time fallback.
- One hidden, disguised, nearest-to-X player: see "Humans as the player" (a single stock handle would ignore every human but one).
- Orders aimed at a dead or replaced single player handle: every `Attack` picks the nearest live human when it is issued.
- The ammo/repair pickups, the crate blast and the pickup flash are per-peer effects: they run on the peer that owns the human.
- The `BuildObject("cspilo", 1, "rescue_N_spn", 200)` path argument is kept verbatim for the team-1 builds (the runtime's `Spawn` takes no fourth
  argument); only the Soviet side goes through it.
- A save in the middle of a film: see "Cinematics".
- A load resets the presentation: the objective list is rebuilt from the saved flags (the body issues objectives only at its events).
- Objective rebuilds are coalesced by the runtime (a rebuild identical to the last published list is dropped).
- Audio: every line the body names has a subtitle in `Text/` (`Test-Chmisn07CoopContract.py`); `audioSubstitute` is empty. The `.des` debriefs ship with the game.
- The body already carries its own documented port fixes (the relic APC destroyed-handle test, the single loss-message reschedule, the pickup
  refill that does not consume a pickup on a full ship, the native `MakeExplosion` argument order). None is changed here.

## Weather: Europa

`Environment.Init` in orbit mode (the Jovian sun path, as for `misn12`) plus the **Europa director** (`CREuropaWeather`) with
`CREuropaSitesCH07`, networked through the runtime (seeded timeline from the host, host-chosen quakes and surges over the ordered
stream, `Save`/`Load` state, `AnnounceState`) and bound to the sensor service (`Environment.BindWeatherSensors("Europa", ...)`). If the
weather module or the sites module is missing, or any weather call errors, the mission runs without weather and logs once. **The generated
site table has no vents**, so no plume ever forms and the bomb beat guards `TriggerPlume` with the vent count; quakes and surges still run.
Beats (host/offline only, each once, tied to the story): the comm tower is burgled -> level 2; the convoy rolls -> level 3; the crates
blow -> level 4, a quake and a radiation surge; the relic is down -> level 2; victory -> `ReleaseForcedLevel` and calm; a loss -> level 4.
The director never damages.

## Tests

```sh
lua5.1 Tools/Test-Chmisn07Coop.lua            # offline == faithful, 1-4 peers, disguise (team 5), scaling, 460 m, pickups, convoy, win/loss, saves, weather
lua5.1 Tools/Test-Chmisn07Presentation.lua    # E/A/C protocol and this mission's five ops on a guest
python Tools/Test-Chmisn07CoopSourceParity.py # ch07cr.lua minus CR regions == ch07.lua
python Tools/Test-Chmisn07CoopContract.py     # labels/paths/teams/start file in ch07cr.bzn (skips with a message if the map is absent)
lua5.1 Tools/Test-Chinese07.lua               # the faithful port, unchanged
```

The contract test checks `Missions/ch07cr.vxt` and `Config/ch07cr.ini` only when they are present.

## Inferences and open questions

- **Nearest human for approach triggers, every human for the extraction.** The body's single-player distances become "nearest human" (the
  runtime's `PLAYERS` rule); the final extraction needs everyone within 60 m of the drop zone (a CR inference, same reach-gate rule the other ports use).
- That the engine carries a pilot's perceived team into the fight (the stand-in logic, enemy turrets and soldiers ignoring a perceived-team-5 pilot)
  is the DLL's design, not tested here.
- Scaling is per frame, a CR inference; `liveCap = 40` so a four-human zone (17 units + 2 extras) and its back-up waves fit.
- A group is hidden from the humans, so a watched approach brings the ambush from another point: the order of `fallbackEntries` is a guess at
  which Soviet approaches are usable (the far convoy starts first).
- Per-human health and ammo writes (`SetCurHealth`/`SetCurAmmo` on a guest's pilot from the host) are the first thing to confirm live: if the engine only
  replicates a guest's own writes, the pickup must be applied by the guest's peer instead.
- The out-of-lives path is not exercised by the host tests (leader departure is).

## Live checklist (unrun)

1. Two clients, DX11: the flight over the base is the same on both (cameras balanced), the opening line plays once on both.
2. One client at the comm tower: both pilots vanish for the burglary, the stand-in walks to the vanish point, both reappear beside `burglar_exit`
   (guest 4 m apart), the north or east bridge film plays on both, the bridge beacon is named on both.
3. Walk a human into a zone (900 m): the ambush arrives without anything popping into view; the zone's turrets stand at their spots.
4. The Soviet soldiers and turrets treat a burgling pilot as one of their own (perceived team 5) and the pilot's own side afterwards.
5. Crates: the bridge crate dies to a shot, the blast shows on both screens, the troops come out.
6. The convoy passes the crates; shoot the relic APC; `ch07008`, the drop zone beacon, back-up waves.
7. Guest stands at an ammo/repair pickup: only the guest is refilled and flashed.
8. Everyone at the drop zone with every guard dead -> `ch07009` -> one shared victory; the relic APC at the failure point -> `ch07007` -> one shared defeat.
9. The Europa sky renders on guests (orbit lighting, quake at the crates), no weather error in the log.
