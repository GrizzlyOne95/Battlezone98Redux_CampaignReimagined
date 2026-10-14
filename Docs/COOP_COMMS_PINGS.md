# Co-op PDA communications and pings

The existing PDA opens on **Co-op** in the migrated co-op missions (`misn02b`,
`misn03`, `misn04`, `misn05`). Solo play keeps its eight pages. Mouse input stays with the
game; this page uses the existing keyboard navigation.

| Key | Action |
| --- | --- |
| X | Open/close the PDA; opening during co-op selects ==COOP== (Y is the stock "ally with team" key online) |
| [ / ] | Previous/next visible PDA page |
| Up / Down | Select a row |
| Left / Right | Change the selected row's choice (mark, teammate, YES/NO) |
| J | Activate the selected row |
| J with PDA closed | Ping the object or terrain under the reticle. The host with one of their own vehicles selected and a guest on foot sends that vehicle instead |
| V | Guests: call for help (on foot: a ride; in a vehicle: supplies). 20-second cooldown |

V is the only free letter besides J and X: every other letter is a stock
binding in `input.map`/`gamekey.map` (H is hop out, Z and V are edit-mode only).

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

The page lists only rows that work right now. Guests see a help row (CALL
RIDE, CALL SUPPLY or CANCEL HELP), TARGET for a teammate's object mark, GIVE
when they have their own units selected, and MARKERS. The host also sees SEND
RIDE (vehicle selected, guest on foot), one YES/NO reply row per open call, and
RECALL ALL TO ME (J twice within three seconds). The team list shows each
player's status: `H<hull%> A<ammo%>`, `on foot`, `NEEDS A RIDE`,
`NEEDS SUPPLIES`, or `ride coming`/`supplies coming`; ` !` marks hull at most 25%
or ammo at most 10%.

Each player has one active ping, lasting ten seconds, with a 1.5-second send
cooldown. Object pings follow their handle. Terrain pings project a local EXU
label reading `Name: TARGET` / `Name: GO HERE` with an arrow and distance.
Receiving a ping never changes the target; TARGET calls the local `SetUserTarget`.

Help calls: a ride call lasts until the guest boards a craft. A supply call times
out after 45 seconds unless the caller's status is critical, and then lasts
until it is not. After 15 seconds without a host reply, the caller alone is told
the call is still open.

Status markers: every two seconds each player broadcasts its own hull and ammo.
Each peer labels the other players' craft with `SetObjectiveName` and
`SetObjectiveOn` (both local-only), so MARKERS ON/OFF affects only that player's
HUD.

Ownership rule: a world change runs only on the machine that owns the object.
- **Send ride**: the host orders its own craft (`Goto`) toward a guest on foot,
  with or without a call. Within 35 m it is handed to the guest empty.
- **Give**: the giver must own the unit (`IsLocal`, own team, a craft, not
  recycler/factory/armory/constructionrig, not their own craft). The receiver
  rebuilds it on its own team with `exu.BuildSyncObject` at the same transform,
  hull and ammo (empty for a ride), then sends TAKEN, and the giver removes the
  original. If the receiver cannot rebuild it within eight seconds, the giver
  keeps it. `SetLocal` is never used, because it can break a remote AI's control.
- **Recall**: the host broadcasts its position, and each guest moves its own craft
  to a 25 m ring around it.

## Runtime and protocol

`CRCoop` supplies the admitted player registry and authority checks.
`CRCoopComms` owns pings, help calls, status, dispatch, recall and hand-off on channel `J` (protocol version 2; ops 1-10). Packets contain only
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

Run `Tools/Test-CRCoopComms.lua`, `Tools/Test-CRCoopAssist.lua`, `Tools/Test-CRCoopPda.lua` and the existing
`Test-CRCoop` / three complete co-op mission tests with Lua 5.1.
`Tools/Test-CoopCommsLive.ps1` is a scenario for OpenShim's
`Run-BZRCoopMission.ps1`, using two disposable clients and its loopback server.
Provide the changed Lua modules and a freshly built `exu.dll` through
`-ContentOverride`. Neither this scenario nor this checkpoint deploys files to
a player's installed game or publishes Workshop content.

**Not yet live-verified:** whether `BuildSyncObject` copies and the empty ride
replicate and board correctly, whether `GetAmmo` on the owner is accurate, and
how the recall placement looks. These need a two-client run before release.
