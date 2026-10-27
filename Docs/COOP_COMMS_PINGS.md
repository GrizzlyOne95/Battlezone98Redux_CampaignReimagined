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
| Enter | Do the selected row (chat stays on ` and Ctrl+C) |
| J | Ping the object or terrain under the reticle (PDA open or closed) |
| V | Guests: call for help (on foot: a ride; in a vehicle: supplies), 20-second cooldown. Host: send the selected vehicle to pick up whoever asked first (or the first guest on foot) |
| Z | Give your selected units to the teammate under the reticle |

J, V and Z work without opening the PDA, so urgent actions never need menu
scrolling. Stock `input.map`/`gamekey.map` bind every other letter (H is hop
out); V and Z are edit-mode only. Stock binds Backspace to the satellite view
(`TOGGLE_OVERVIEW BSP`), so it cannot do PDA rows.

Stock binds Enter, ` and Ctrl+C to chat. In network games CR calls
`exu.SetChatOnEnter(false)` every frame (Redux rereads `gamekey.map`, and so
rebinds Enter, after every ESC menu) and `SetChatOnEnter(true)` at mission
end, so Enter does PDA rows while ` and Ctrl+C still open chat. EXU builds
without the call leave Enter on chat. Plain `[` and `]` are bound only to
DEC_VAR/INC_VAR, which the shipping exe never handles (Ctrl+[ / Ctrl+] are
the separate ally prompts); the real arrow keys are bound only to the
Shift-held command menu and the track camera. In network games Redux calls the mission `GameKey`
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
RECALL ALL TO ME (Enter twice within three seconds). The team list shows each
player's status: `H<hull%> A<ammo%>`, `on foot`, `NEEDS A RIDE`,
`NEEDS SUPPLIES`, or `ride coming`/`supplies coming`; ` !` marks hull at most 25%
or ammo at most 10%.

Each player has one active ping, lasting ten seconds, with a 1.5-second send
cooldown, shown only as a stock objective marker plus a chat line. Receiving a
ping never changes the target; TARGET calls the local `SetUserTarget`.

A pinged unit is renamed `Name: TARGET PING` on every player's HUD until the
ping ends, then gets its old name back. If it was not an objective it also gets
the stock marker (local `SetObjectiveOn`) for the ping. If it already was (a
mission objective or a teammate status marker) it flashes for about a second
and is never switched off. A teammate's status marker relabels its craft every
second, so on teammates the ping name is brief. The check needs EXU `IsObjectiveOn` (it reads the
engine flag at GameObject+0x189); without it, an object ping shows only the chat line.
A terrain ping builds an invisible marker object on each player's machine
(`exu.BuildAsyncObject("crping", 0, pos)`, local-only), names it
`Name: TERRAIN PING`, switches its objective marker on, and removes it when the ping
ends or is replaced. `ODF/crping.odf` is a plain `i76building` that reuses the
stock geyser base mesh `eggeizr1`, which sits entirely below ground. Rejected
classes: `camerapod`/`apcamr` (looks like a mission nav), `spawnpnt` (joins
respawn selection), `dropoff` (a powerup that banks a friendly scavenger's
scrap) and other powerups (picked up). The stock path grid blocks every building's whole
SDF box (geysers, scrap fields and spawn points are exempt, but an
`i76building` is not), so `crping` sets `pathBlock = "none"`, which OpenShim
(`[General] PathBlockFaces`, on by default) and EXU `exu.pathing` honour. The engine's objective list holds
32 objects and is not bounds-checked, so co-op keeps its own markers few.

Help calls: a ride call lasts until the guest boards a craft. A supply call times
out after 45 seconds unless the caller's status is critical, and then lasts
until it is not. After 15 seconds without a host reply, the caller alone is told
the call is still open.

Status markers: every two seconds each player broadcasts its own hull and ammo.
With MARKERS ON (opt-in, off by default, per player), each peer labels the
other players' craft with `SetObjectiveName` and `SetObjectiveOn` (both
local-only), switching a marker on once and renaming it only when its status
text changes. They are off by default because those calls share the mission's
objective namespace: mission scripts and their presentation tests expect only
their own objective calls.

Ownership rule: a world change runs only on the machine that owns the object.
- **Send ride**: the host gives one of its own craft the stock "Pick Me Up"
  order, `SetCommand(craft, AiCommand["RESCUE"], 1, pilot)`, for a guest on
  foot, with or without a call. The engine's `RescueTask` (1.5 `0045b6e8`)
  drives to the pilot, and within 30 m waits a second and bails its AI pilot
  out. The guest then boards through the stock hop-in, which hands ownership
  to the guest's machine (`Person::RegCollision`: SetLocal, team, SetAsUser).
- **Give**: the giver must own the unit (`IsLocal`, own team, a craft, not
  recycler/factory/armory/constructionrig, not their own craft). With EXU
  `AdoptObject`, the receiver takes over the real unit: SetLocal (the old
  owner's engine drops its AI when it sees the claim), the receiver's team,
  then a fresh AI attached from the ODF, the same steps the engine runs when
  a pilot boards an empty craft. It replies TAKEN 1 and nothing is removed.
  Pending orders do not carry over. On an older EXU the receiver rebuilds the
  unit with `exu.BuildSyncObject` (same transform, hull and ammo) and replies
  TAKEN 0, and the giver removes its original. If neither happens within eight
  seconds, the giver keeps the unit.
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
made. Unsupported builds return nil.

## Verification

Run `Tools/Test-CRCoopComms.lua`, `Tools/Test-CRCoopAssist.lua`, `Tools/Test-CRCoopPda.lua` and the existing
`Test-CRCoop` / three complete co-op mission tests with Lua 5.1.
`Tools/Test-CoopCommsLive.ps1` is a scenario for OpenShim's
`Run-BZRCoopMission.ps1`, using two disposable clients and its loopback server.
Provide the changed Lua modules and a freshly built `exu.dll` through
`-ContentOverride`. Neither this scenario nor this checkpoint deploys files to
a player's installed game or publishes Workshop content.

**Not yet live-verified:** whether the native rescue targets a remote guest's
pilot and the guest can board the bailed craft, whether `BuildSyncObject`
copies replicate, whether `GetAmmo` on the owner is accurate, and
how the recall placement looks. These need a two-client run before release.
