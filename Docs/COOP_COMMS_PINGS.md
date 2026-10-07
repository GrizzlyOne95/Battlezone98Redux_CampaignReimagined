# Co-op PDA communications and pings

The existing PDA opens on **Co-op** in the migrated co-op missions (`misn02b`,
`misn03`, `misn04`). Solo play keeps its eight pages. Mouse input stays with the
game; this page uses the existing keyboard navigation.

| Key | Action |
| --- | --- |
| X | Open/close the PDA; opening during co-op selects Co-op (Y is the stock "ally with team" key online) |
| [ / ] | Previous/next visible PDA page |
| Up / Down | Select a Co-op row |
| Left / Right | Change the selected ping, rescue request, or host reply |
| J | Activate the selected Co-op row |
| J with PDA closed | Ping the current object or terrain hit |

Enter retains native chat. In network games Redux calls the mission `GameKey`
callback for J, [ ], the arrows and Enter only sometimes, so CR polls those keys
there through `exu.GetGameKey` (EXU needs the `LBRACKET`/`RBRACKET` names) and
ignores their `GameKey` copies. [ ] and the arrows act only while the PDA is
open. While the chat line or the ally/unally box has keyboard focus
(`exu.IsTextEntryActive()`), polled keys and X are ignored, so typing in chat
does not ping; older EXU builds without the probe still can. Co-op calls
`LockAllies(true)` from `CRCoop.Update` (Redux ignores it from `Start`), so Y/U
do not open the ally box. Pause, cinematic, dead-player and mission-end contexts
suppress actions. The migrated missions pass their local cinematic state into
`PersistentConfig.UpdateInputs`; future migrations should do the same.

Each player has one active ping, lasting ten seconds, with a 1.5-second send
cooldown. Object pings follow their handle. Terrain pings store three simulation
coordinates and project a local EXU label, including a direction indicator for
points outside the view. These labels never create game objects or change
mission objective flags/names. **Target selected object ping** explicitly calls
the local `SetUserTarget`; merely receiving a ping does not change the target.

Living pilots can request a rescue or cancel their request. The host can reply
**Coming** or **No craft available**. Native `DisplayMessage` notices appear on
each peer, and the PDA keeps current request/reply status. Requests clear when
the pilot dies, boards another craft, or leaves. Replies refer to the specific
request revision and pilot handle.

This checkpoint supplies communications. Unit ownership transfer, automatic
craft assignment and AI rescue orders remain separate work; a “Coming” reply
does not claim that a craft has already been assigned.

## Runtime and protocol

`CRCoop` supplies the admitted player registry and authority checks.
`CRCoopComms` owns transient pings/requests on channel `J`. Packets contain only
numeric codes, handles and coordinate numbers, with no wire strings or tables.
Known senders must match their registered current player handle. Host responses
require the campaign leader's team, not a migrated network host.

Receipts/retries are bounded to five seconds. Per-operation high-water marks
reject duplicates and delayed older pings/requests; cancellation prevents an
older request from returning. A response that overtakes its request is retried
until that request arrives. Communication state is reset at mission startup.

EXU `GetReticleHit()` returns `"object", handle, nil`,
`"terrain", nil, position`, or nil. On supported Redux 2.2.301 it checks the
current smart-reticle object and ground-hit result, avoiding the retained
coordinates exposed by `GetReticlePos()` after a miss. No range extension is
made. Unsupported builds return nil. Coordinate HUD projection uses BZR's
camera matrix and projection constants, with no Ogre world-space objects.

## Verification

Run `Tools/Test-CRCoopComms.lua`, `Tools/Test-CRCoopPda.lua` and the existing
`Test-CRCoop` / three complete co-op mission tests with Lua 5.1.
`Tools/Test-CoopCommsLive.ps1` is a scenario for OpenShim's
`Run-BZRCoopMission.ps1`, using two disposable clients and its loopback server.
Provide the changed Lua modules and a freshly built `exu.dll` through
`-ContentOverride`. Neither this scenario nor this checkpoint deploys files to
a player's installed game or publishes Workshop content.
