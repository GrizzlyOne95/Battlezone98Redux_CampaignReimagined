# Mission 04 offline and co-op

The Relic Discovered uses one `misn04.bzn`/`misn04.lua` pair for campaign
`MISSION3` and the multiplayer strategy listing `CR: The Relic Discovered Coop`.
The map uses `MultSTMission`, four native `pspwn_1` spawn buoys at the authored
player start, and the bundled EXU hooks to suppress extra starting recyclers.

## Session setup

- Use matching CR/EXU/OpenShim builds and content on every client.
- Host on team 1. Guests use distinct teams 2–4; select an NSDF tank or scout.
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

## Focused validation

```sh
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
offline save/load, host departure, late joins and repeated starts. The weather
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
