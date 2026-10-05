# Mission 03 offline and co-op

`Missions/misn03.bzn` uses `MultSTMission` for both campaign/offline loading and
online strategy loading. The same `Scripts/misn03.lua` handles either mode.
The four stock `pspwn_1` spawn buoys are preloaded at the original player start;
they register human teams 1–4 before native multiplayer initialization.

## Session setup

- Use the bundled CR/EXU version on every machine and load `misn03` as a strategy
  map. This change does not add a separate map or change campaign progression.
- Host on team 1. Guests select distinct teams 2, 3, or 4. All four teams are
  allied; authored enemies stay on team 5. Start with all participants present.
- Team 1 commands Montana and owns its production. Guests support the shared
  defense/convoy in their player craft; this does not add shared factory control
  or give each guest another recycler.
- Native strategy respawning remains enabled. EXU sets 999 lives on each peer.
  The local handle exchange follows pilot ejection, vehicle changes and respawns.
- All connected humans must be clear of nearby enemy tanks/fighters before the
  evacuation film, and all must reach within 100m of the launch pad to finish.
- Skipping a film releases only that player's camera online. Shared film timers
  and host-controlled destruction keep running. The network outro has a 90s
  fallback for a stuck cinematic prop. Offline retains the authored skip gates.
- Guest departure releases that slot. Host departure ends the mission on the
  remaining peers. Late join/rejoin pauses progression and displays the existing
  restart instruction; native world reconciliation is not implemented.

## Implementation

EXU `DisableStartingRecycler()` runs at script load, before native Init, so
Montana stays the only recycler. If the offline BZN player craft survives native
network startup, the host removes it after the player registry completes, with
an explicit check that it is not a current human craft. Offline keeps that craft.

Only team-1 authority runs scripted AI, spawning, random wave schedules,
health changes, transport orders, failure checks and victory progression.
Pilot Mode excludes registered human craft and non-local objects. Clients keep
their subtitle, input/lighting and other local presentation updates running.
Starting resources are applied by each team owner; the leader's difficulty is
distributed before defense presentation. Offline autosave and Save/Load remain.

Mission HUD objectives, dynamic markers/names, target cues, dialogue, queued
warnings, custom maximum-health values, prop removal and results use `E` events with monotonically increasing
sequence numbers and cumulative `A` acknowledgements. Up to eight individual
events per recipient are retried every 0.2s. Clients discard duplicate events and
withhold an acknowledgement across a sequence gap. A delayed dynamic handle is
retried for up to five seconds; a marker for an already-destroyed object then
drops without blocking cleanup or the result. Packets contain primitive/game
values, never Lua tables, and stay below the stock payload limit.

`C` camera snapshots carry a serial, cinematic generation, path, height, speed
and target every 0.2s. Older snapshots are ignored; every new cinematic resets
the local skip latch. Result publication waits for previous event delivery and
schedules native mission termination at least five seconds ahead for retries.
Only the registered team-1 sender can drive client presentation. This protocol
does not reuse CRCoop's `H/Q/K/P` message types.

The array-survivor loss gate now stops when evacuation begins, matching the
stock phase-specific failure checks. Defense still requires the same number of
arrays at each difficulty; later cinematic destruction cannot fail that defense.

## Evidence and validation

The current Redux project findings in
[BZR_LUA_AGENT_REFERENCE.md](BZR_LUA_AGENT_REFERENCE.md) govern ownership,
remote-player lookup and local-only HUD/name behavior. Bundled EXU signatures
are documented in [ExtraUtils.lua](lua-definitions/ExtraUtils.lua).

The following historical 1.5 disassembly informed the native lifecycle choices;
it is supporting evidence, **not a live Redux multiplayer test**. Links pin
Battlezone_Source commit `e7c410573ffedc9e118dd90f402af6d5585955cc`:

- [MultSTMission::Init](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0044/0044d409_MultSTMission_Init.c): spawn-point selection, local player creation and default recycler creation.
- [MultSTMission::Update](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0044/0044d2cd_MultSTMission_Update.c): calls LuaMission::Update, native timer and death-camera behavior.
- [SpawnBuoy::Init](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/004b/004b1104_SpawnBuoy_Init.c): registers a team-associated spawn point only in network play.
- [MultSTMission::Respawn](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0044/0044d135_MultSTMission_Respawn.c): native local respawn/lives handling.
- [AiMission::End](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0040/00401b11_AiMission_End.c) and [Update](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0040/00402f39_AiMission_Update.c): result/debrief state and absolute shutdown time.
- [GameObject::SetMaxHealth](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0045/0045e518_GameObject_SetMaxHealth.c) and [Craft::PackTempState](https://github.com/GrizzlyOne95/Battlezone_Source/blob/e7c410573ffedc9e118dd90f402af6d5585955cc/BZ1/1.5/functions/0048/00488f8e_Craft_PackTempState.c): custom maximum-health fields need explicit delivery in addition to owner health updates.

Focused checks:

```sh
lua5.1 Tools/Test-Misn03Coop.lua
lua5.1 Tools/Test-CRCoop.lua
lua5.1 Tools/Test-EarlyMissionFlow.lua
python Tools/Test-Misn03CoopContract.py
python Tools/Test-EarlyMissionSourceAudit.py
python Tools/Validate-CampaignRepository.py
```

The complete-script harness runs isolated offline/host/client Lua environments
using the real CRCoop module and mocked engine/network calls. It covers lost and
reordered packets, four humans, leader difficulty, local resources, authority,
evacuation presentation/cleanup, individual camera skipping, all-player launch,
replicated win/loss, offline autosave/load and participant lifecycle handling.
Static checks verify BZN CRLF, object/sequence counts, four spawn teams, mission
class and enemy-team isolation. CI runs the new harness with Lua 5.1.

Live Redux verification is still required: load this BZN offline, complete and
reload a save, then run a two-machine strategy session through defense,
evacuation and win/loss. Check Montana's visibility/production, enemy ownership,
spawn positions, prop removal, death/respawn camera interaction and debrief exit
on both machines. Native loading, EXU binary hooks and replication cannot be
validated by mocks. No native binary, loader/path behavior or release payload
changes are included; the same Lua/BZN content is used on GOG/Steam and
Wine/Proton, with those live runtime lanes unverified here.
