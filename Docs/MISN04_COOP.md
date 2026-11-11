# Mission 04 offline and co-op

The Relic Discovered uses one `misn04.bzn`/`misn04.lua` pair for campaign
`MISSION3` and the multiplayer strategy listing `CR: The Relic Discovered Coop`.
The map uses `MultSTMission`, four native `pspwn_1` spawn buoys at the authored
player start, and the bundled EXU hooks to suppress extra starting recyclers.

Starting choices follow [the co-op production progression](COOP_STARTING_UNITS.md).

## Session setup

- Use matching CR/EXU/OpenShim builds and content on every client.
- Host on team 1. Guests use distinct teams 2–4; select an NSDF tank, scout, or light tank.
- Start together. Late join/rejoin pauses progression and requires a restart.
  Host departure ends the mission; guest departure releases readiness.
- Team 1 owns Montana, production, the automated relic cargo job and mission AI.
  Any human can discover the relic, and any friendly tug can bring it home.
  Guest tugs remain under their owner's control.
- Online human death uses native respawning near a living teammate, with 5
  co-op lives per player (COOP_RESPAWN.md); running out fails the mission. Offline
  campaign saving/loading, local camera skips and original debriefs remain.
  Native multiplayer difficulty remains locked to Very Hard; mission difficulty
  and starting resources are delivered from the leader to each owning peer.

## Ownership and presentation

CCA objects use team 5, leaving teams 1–4 free for humans. The autonomous CCA
base remains distinct from mission-controlled defenders, patrols, five attack
waves and relic thieves. Network bootstrap registers only locally owned
non-human objects; scripted CCA units are excluded from aiCore production and
orders. The existing `scriptedTeam2Handles` save field keeps its historical name.

Ordered, acknowledged primitive messages deliver dialogue, objectives, markers,
cleanup and terminal results. Dynamic markers wait for their native replicas.
Camera snapshots let each player skip locally without advancing shared mission
state. Online discovery and theft cameras have time limits if audio stalls.

The host selects weather rungs and set-piece cues; guests run their local visual
weather and Environment updates. Sensor changes apply only to locally owned
craft. Online global wind-push gravity is disabled because independent random
winds could write conflicting physics on each peer. Offline wind remains.
Weather particles and exact visual transition timing are not synchronized.
EXU development probes that retask AI or change physics remain offline-only.

`CRCoop.Initialize` resets prior mission admission/handshake state while retaining
native player records that may have arrived before `Start`, allowing repeated
same-process mission starts without inheriting a late-join flag.

## Dropship opening [CR addition, offline and co-op]

The mission opens with two NSDF dropships landing the base and the players, in campaign and in co-op. The module is
`Scripts/CRDropIn.lua` (generic: the mission passes the anchors and the cargo, so a later Titan opening can reuse
it). It replaces the single-player `CR04Drop.lua`, which stays in the tree only because `CRDrop18.lua` and
`MISN18_COOP.md` cite its numbers. Numbers marked "CR guess" in `CRDropIn.lua` need a live tune; the rest are
`CR04Drop`'s measured ones.

| Step | What happens |
| --- | --- |
| Plan | The leader picks two sites behind the anchors (the Recycler/Factory midpoint and the stock player spot), sterns toward them, the flattest unblocked of 18 candidates. The **cargo ship** carries the Recycler and Factory; the **personnel ship** carries every human craft (teams in order) and the wingman, two lanes of six (row 1 is `CR04Drop`'s player/wingman spot, the further rows are a CR guess). |
| Replication | The plan goes out as numbers on the ordered stream: `DropShip(i, n, x, z, y, sx, sz, lx, lz, delay)` per ship, `DropCrew(team, ship, along, lat)` per human, then `DropGo(leaderTime)` (one number: the leader's `GetTime()` at send; optional). No pose is ever sent: every pose until the release is a pure function of the plan and the seconds since `DropGo`, which each peer starts when it applies it (a guest that applies it late starts its clock that many seconds in, capped at `MAX_LATE` = 5 s because peers share no clock, so a skewed `GetTime()` never skips the drop). A co-op warn state (late joiner, bad team) or host departure aborts the drop so no peer stays locked. The ops are listed statically in `misn04cr.lua` (`DROP_OPS`), so a guest without the module still acknowledges them. |
| Descent (0-18.5 s) | The LEADER builds and moves the ships (`avdropc`, 16 s each, the personnel ship 2.5 s behind) and pins the Recycler, Factory and wingman in their holds. EVERY peer pins its OWN craft (`GetPlayerHandle`) in its slot and tops its health up. The camera pod stands 150 m out past the ramps: `CameraObject(pod, 0, 1800, 0, personnel ship)`, streamed as shot kind "O". |
| Touchdown | The leader swaps each ship for a new `avdropo` (floor collision is snapshotted at creation; its ramps swing open, 2.6 s). The stock opening (`missionstart`, `misn0401`) waits. |
| Release (21.1 s) | The camera ends on every peer, the pod goes, offline the EXU control mask clears; every peer stops pinning its craft. The leader pushes the AI cargo down the ramp lanes onto its stock spots (handed back after 40 s at most, a CR guess). The stock opening runs. |
| Lift-off | 6 s after release, once no cargo and no human craft is within 45 m, each ship is swapped for `avdropx` (ramps fold, 2.4 s) and climbs out at 1.5 m/s^2. |

Offline the same code runs with one peer; the controls are locked by the EXU mask until the release, and a camera
skip touches both ships down at once (the ramps still take 2.6 s). In network games each peer masks its own player too
(an older bundled `exu.dll` refuses it, and pinning every frame stays the hold) and `CameraCancelled` is false, so no skip moves the shared timeline; a player's skip only
drops their own view.

**Save/load mid-opening** cannot resume it (the ship handles and the cameras are gone): the leader removes every
dropship and the pod (by ODF only: a saved handle that now names something else is left alone), sets any AI cargo still carried or driving down on its stock spot, and each peer whose craft
was still carried sets it down past its ramp lip, so nothing is stranded in the air; the stock opening then runs. If
`CRDropIn` fails to load, `misn04cr.lua` logs `[misn04] stock opening: CRDropIn unavailable` and starts as stock;
missing ship art does the same. The leader validates the plan (anchors, delays, ship art) before it sends any drop event, and an error while starting it (`pcall`; `DropIn.Abort`) removes the ships already built and falls back to the stock start. A failing `SetTransform` is contained (`pcall`) and only skips that pose. At each hull swap the shared camera looks at the pod for 1 s so guests do not wait for the new hull's label.

## Focused validation

```sh
lua5.1 Tools/Test-CRDropIn.lua
lua5.1 Tools/Test-Misn04Coop.lua
lua5.1 Tools/Test-BZRPeerTransport.lua
lua5.1 Tools/Test-CRCoop.lua
lua5.1 Tools/Test-CRMarsWeather.lua
python Tools/Test-Misn04CoopContract.py
python Tools/Test-SetupMissionShell.py
python Tools/Test-EarlyMissionSourceAudit.py
python Tools/Validate-CampaignRepository.py
```

The complete-script test uses four isolated Lua 5.1 environments, the real
CRCoop registry, separate native object replicas and delayed dynamic creation.
Both candidate Lua Send reliability modes cover packet loss/reordering, shared
opening/difficulty/resources, guest discovery and towing, five waves, severe
weather, local skips, stalled audio, respawn and victory. Separate cases cover
recycler/relic destruction, CCA theft, missed investigation, timed survey,
offline save/load, host departure, late joins and repeated starts. The dropship
opening is checked in co-op (only the leader builds; each guest pins only its own
craft and sees the shared camera; skips move nothing), across a mid-opening
save/load, and without the module (stock start). The weather
fixture runs the real Environment module to verify owner-local sensor writes.

The BZRNet transport model and its limitations are documented in
[MISN02B_COOP.md](MISN02B_COOP.md). It does not emulate native object wire data,
Lua serialization, pathfinding, physics, native map loading or EXU binary hooks.
Passing simulations does not qualify live multiplayer.

Before release, run real Redux clients through discovery, guest towing, CCA theft,
five waves, base destruction, respawn and every debrief; also load/reload offline
campaign saves. Verify multiplayer discovery, spawn ownership and Montana's
production. The same content targets GOG/Steam and Wine/Proton, but those live
lanes remain unverified here. Nucleus can provide paired Windows processes if
its handler preserves CR/EXU/OpenShim and the transport being validated.

Shipping admits four INI/BMP/DES/VXT assets, with no removals. The Linux
PowerShell bless attempt needed a Windows-relative path adapter and then
refused because 28 sibling-supplied renderer/UI files are absent from this
checkout. The existing members were retained and only the four mission assets
were added directly; static shipping checks pass. A complete Windows checkout
still needs the normal `Manage-CampaignFiles.ps1 -bless` review. No game deployment
or Workshop publication is part of this change. Run native Windows staging and
installation verification before live qualification.
