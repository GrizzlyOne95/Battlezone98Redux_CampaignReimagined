# Battlezone 98 Redux Lua — Agent Reference

This document is a compact, agent-oriented reference for the **stock Battlezone 98 Redux LuaMission API**. It translates the repository's HTML API mirror into a form that coding/review agents can search and reason from without losing the stock bugs, version differences, lifecycle constraints, or multiplayer locality quirks that matter in real missions.

It is intentionally not a replacement for the original HTML corpus. Use this document for fast decisions and implementation; follow the linked source page when a behavior is unusual, version-sensitive, or safety-critical.

## Source authority

Use the following evidence order when sources disagree:

1. **`References/StockLuaAPI-Functions/` and `References/StockLuaAPI-Expressions/`** — primary behavioral reference, including version tags and `Known Issues` sections.
2. **`Scripts/scriptutils.lua`** — canonical searchable signature/type inventory. It is excellent for LuaLS annotations, but a clean signature does **not** imply the function is bug-free.
3. **`Text/ScriptingGuide.txt`** — Campaign Reimagined operational notes and multiplayer experiments. Treat these as valuable observed behavior, but version-qualify them and prefer the HTML corpus when they conflict.

This ordering matters. For example, the project notes say `ObjectiveObjects()` is broken, while the HTML reference explains that the engine bug affected Battlezone 1.5.2.x and was **fixed in Battlezone 98 Redux**. Agents targeting Redux must use the Redux result.

## Scope

- Runtime: **Lua 5.1**.
- Target: stock Battlezone 98 Redux (`GameVersion` begins with `"2"`).
- No external Lua libraries should be assumed. In normal stock missions, do not assume `io`, `os`, or `debug` are available.
- Do not use Lua 5.2+ syntax/features such as `goto` / `::label::`.
- Project DLL APIs (EXU, BZFILE, OpenShim bridges, etc.) are **out of scope** here unless explicitly named by the task.
- Campaign Reimagined-only helpers present in `Scripts/scriptutils.lua` (for example `SetTeamColor`, `ClearTeamColor`, and `ResetTeamColors`) are **not stock BZR Lua functions**.

## Agent rules — read before generating Lua

1. **Check hazards before trusting a signature.** `GetPlayerHandle(team)` is syntactically valid but its team argument is broken in Redux.
2. **Prefer capability tests to version parsing** for optional functions:

   ```lua
   if IsTouching ~= nil then
       -- BZR 2.1+ path
   end
   ```

3. **Keep Lua 5.1 compatibility.** Avoid `goto`, bit libraries, newer standard-library assumptions, and external modules unless the mission explicitly supplies them.
4. **Reason about multiplayer ownership before mutating an object.** `IsLocal`, `IsRemote`, `SetLocal`, host/client authority, and `Send`/`Receive` are part of the design, not cleanup work to add later.
5. **Do not call `SetAIControl` after strategic AI setup.** It is a startup configuration function with a crash hazard if used later.
6. **Do not exceed ten simultaneous objective messages.** The documented implementation can overflow its fixed buffer and eventually crash.
7. **Distinguish immediate object creation from producer commands.** `BuildObject(...)` spawns an object; `Build(...)` / `BuildAt(...)` command a producer.
8. **Use `TeamSlot`, `AiCommand`, `PathType`, and `ClassId` names instead of magic integers** when the supplied table exists.
9. **Do not assume UI/chat/network effects replicate.** Many script effects are local unless explicitly networked.
10. **When project observations conflict with an HTML `Known Issues` section, use the HTML behavior and preserve the conflict in comments/documentation rather than silently choosing the older note.**

---

# Runtime types and globals

## Core userdata

| Type | Meaning | Notes |
|---|---|---|
| `handle` | game-object identifier | custom light userdata; may be `nil` where no object exists |
| `message` | audio message handle | returned by `AudioMessage` |
| `odfhandle` | parsed ODF/INI/TRN file | returned by `OpenODF` |
| `vector` | `x`, `y`, `z` | custom userdata; supports arithmetic operators |
| `matrix` | orientation + position | custom userdata with right/up/front/posit components |
| `teamnum` | integer 0–15 | team 0 is normally neutral/environment |
| `weaponslot` | integer 0–4 | five weapon hardpoint slots |
| `weaponmask` | integer 0–31 | bit mask for AI weapon hardpoints |
| `priority` | `0` or `1` | `0` commandable; default `1` uncommandable |

## Important globals

```text
string GameVersion
number Language              -- BZR 2.0+
string LanguageName          -- BZR 2.0+
string LanguageSuffix        -- BZR 2.0+
string LastGameKey
matrix IdentityMatrix
ClassId ClassId
TeamSlot TeamSlot
PathType PathType
AiCommand AiCommand
```

`GameVersion` is the most direct coarse distinction: Battlezone 1.5 builds begin with `"1"`; Redux builds begin with `"2"`. Prefer feature tests when testing for one API function.

### Common enum values

`TeamSlot` includes `PLAYER`, `RECYCLER`, `FACTORY`, `ARMORY`, `CONSTRUCT`, offense/defense/utility ranges, beacon, power, comm, repair, supply, silo, barracks, and gun-tower slots.

`PathType`:

```text
ONE_WAY = 0
ROUND_TRIP = 1
LOOP = 2
```

Common `AiCommand` values include `NONE`, `STOP`, `GO`, `ATTACK`, `FOLLOW`, `FORMATION`, `PICKUP`, `DROPOFF`, `GET_REPAIR`, `GET_RELOAD`, `GET_WEAPON`, `DEFEND`, `RECYCLE`, `SCAVENGE`, `HUNT`, `BUILD`, `PATROL`, `STAGE`, `GET_IN`, `LAY_MINES`, and `CLOAK`.

---

# LuaMission lifecycle and event handlers

These functions are implemented by the mission script and called by LuaMission.

```text
Load(...)
... Save()
Start()
GameKey(string key)
Update(number timestep)
CreateObject(handle h)
AddObject(handle h)
DeleteObject(handle h)
CreatePlayer(integer id, string name, teamnum team)
AddPlayer(integer id, string name, teamnum team)
DeletePlayer(integer id, string name, teamnum team)
boolean Receive(integer from, string type, ...)
boolean Command(string command, string arguments)
```

### Lifecycle guidance

- `Start()` is one-time mission initialization.
- `Update(timestep)` runs every simulation frame after network update and before game-object simulation. Keep hot-path work bounded.
- `CreateObject` can receive heavy traffic; avoid broad scans or expensive parsing there.
- `AddObject` generally covers important mission objects and excludes some incidental objects such as scrap.
- `Save`/`Load` support serializable scalar/game types; do not try to persist functions, threads, or arbitrary userdata.
- Multiplayer-only missions generally should not build important logic around save/load.
- `Receive` is the stock mechanism for explicit script-level network synchronization.

### Legacy `DeleteObject` warning

In **Battlezone 1.5.2.x**, destroyed units can reach `DeleteObject` too late for normal object properties to remain valid; the HTML reference recommends caching needed properties while the unit is alive. This is a **legacy 1.5 issue**, not a reason to automatically cripple Redux code. See `References/StockLuaAPI-Functions/Script Event Handlers/DeleteObject/`.

---

# Critical bugs, quirks, and do-not-assume behavior

This section is intentionally redundant with the function index. Agents should search here first when a function behaves strangely.

## Redux-relevant hazards

### `GetPlayerHandle(team)` — team argument is broken

```text
handle GetPlayerHandle([teamnum team])
```

Calling `GetPlayerHandle()` without an argument is the normal local-player lookup. In Battlezone 98 Redux, passing a team number does **not** correctly retrieve that team's player and returns `nil`.

Do not generate multiplayer code like:

```lua
local remote = GetPlayerHandle(2) -- do not assume this works
```

For remote-player tracking, maintain the handles explicitly and synchronize them using `CreatePlayer`/`AddPlayer` plus `Send`/`Receive` or another validated identity mechanism.

Source: `References/StockLuaAPI-Functions/Team Slots/GetPlayerHandle/`.

### `LockAllies` in `Start()` has no effect in Redux

The HTML reference documents that calling `LockAllies(...)` from `Start()` has no effect in Battlezone 98 Redux. Do not assume that a startup call successfully locks the alliance UI/state. If the mission requires locked alliances, perform the one-shot call after startup has advanced and validate the resulting behavior.

Source: `References/StockLuaAPI-Functions/Alliances/LockAllies/`.

### Objective-message duration is not honored

For both `AddObjective` and `UpdateObjective`, the documented `duration` argument is ignored and objective messages use a fixed eight-second duration.

Do not implement timing logic that assumes this argument controls display lifetime.

### Maximum ten simultaneous objective messages

`AddObjective` uses a fixed-size internal buffer. The HTML reference warns that adding more than **10 simultaneous objective messages** causes a buffer overflow and can eventually crash the game.

Maintain at most ten entries. Prefer updating/removing existing objective slots rather than appending indefinitely.

Source: `References/StockLuaAPI-Functions/Objective Messages/AddObjective/`.

### Cockpit timers conflict with stock multiplayer mission modes

In `MultSTMission` and `MultDMMission`, the stock multiplayer mode code calls `StartCockpitTimerUp()` every frame. Consequences documented by the HTML reference:

- a true countdown via `StartCockpitTimer` cannot be maintained in those modes;
- warning/alert thresholds cannot be reliably adjusted through the count-up function;
- showing/hiding the timer remains possible.

Do not build a multiplayer countdown mechanic around the stock cockpit timer without first changing/overriding the mission-mode behavior.

Source: `References/StockLuaAPI-Functions/Cockpit Timer/StartCockpitTimer/` and related timer pages.

### `Attack` and same-team targets

`Attack(me, him, priority)` only attacks a target on the attacker's **own team** when `priority` is `1` (uncommandable). If intentionally commanding friendly-fire/same-team attack behavior, use and test priority `1`.

Source: `References/StockLuaAPI-Functions/Unit Commands/Attack/`.

### Cross-team Armory `Build` / `BuildAt` behavior

The HTML reference documents an Armory targeting bug when the Armory belongs to a team other than the player's own: launched powerups may not correctly reach the requested target when using `Build` or `BuildAt`. The source page includes Lua and ODF workarounds involving the powerup/Armory `aiName2` configuration.

Do not assume cross-team Armory delivery is equivalent to the local player's Armory.

Source: `References/StockLuaAPI-Functions/Unit Commands/Build/` and the four `BuildAt (...)` pages.

### `SetAIControl` is startup-only configuration

```text
SetAIControl(teamnum team, [boolean control])
```

The strategic AI is initialized shortly after the mission script starts. Calling `SetAIControl` later can crash the game. Configure it from the script root/startup phase only. `GetAIControl` can be queried later.

### Exact capitalization matters

Two names are especially easy for agents to “correct” incorrectly:

```lua
UpdateEarthQuake(magnitude) -- capital Q in Quake
isPortalActive(portal)      -- lower-case initial i
```

Use the stock spelling exactly.

### Timer numeric limits

- `StartCockpitTimer` supports at most `35999` seconds (`9:59:59` on screen).
- `StartCockpitTimerUp` has a display malfunction after ten hours.

### `Build` then `Dropoff` requires a simulation update

Armories and Construction Rigs commanded with `Build(...)` need at least one simulation update to process the build selection before a location is supplied with `Dropoff(...)`.

Do not issue both back-to-back in one synchronous code path and assume the location command is accepted.

## Legacy Battlezone 1.5 issues that agents must NOT blindly apply to Redux

These are preserved because the HTML corpus documents both games, but the version qualifier is critical.

| Issue | Affected version | Redux guidance |
|---|---|---|
| `ObjectiveObjects()` loop counter fails and can hang the game | 1.5.2.x | **Fixed in Redux.** The iterator is usable in BZR. |
| unexpected `\0` bytes from `GetOdf`, `GetBase`, `GetPilotClass`, `GetWeaponClass` | 1.5.2.x | Treat the cleanup wrapper as a 1.5 compatibility workaround unless Redux testing proves otherwise. |
| `SetLabel` is named `SettLabel` | 1.5.2.x | Redux uses `SetLabel`; compatibility code may use `SetLabel = SetLabel or SettLabel`. |
| removing the currently active weapon with `GiveWeapon` can crash | Battlezone 1.5 | Do not automatically attribute this legacy crash to Redux. |
| destroyed objects can reach `DeleteObject` after useful properties are gone | 1.5.2.x | Preserve cached-state patterns when useful, but do not label this a confirmed Redux engine bug. |
| `GetAIControl` needs a Lua compatibility implementation | specific 1.5 build(s) | BZR supplies the function. |

This version separation supersedes older project notes that list some of these as unqualified engine bugs.

---

# Multiplayer ownership and synchronization

## Canonical network API

```text
boolean IsNetGame()
boolean IsHosting()
SetLocal(handle h)
boolean IsLocal(handle h)
boolean IsRemote(handle h)
DisplayMessage(string message)
Send([integer to], string type, ...)
```

`Send` broadcasts when `to` is `nil`, omitted, or `0`. The type is an arbitrary one-character message identifier. The packet payload limit is approximately **244 bytes** after network headers, so keep messages compact.

Supported serialized values include nil/boolean/handle/numbers/strings/vector/matrix and supported aggregate encodings documented by the runtime. Never assume arbitrary userdata/functions/threads can cross the wire.

### `SetLocal` safety rule

Only one machine should attempt to claim a particular object with `SetLocal` at a time. Ownership races are not a synchronization mechanism.

## Campaign Reimagined observed multiplayer behavior

The following items come from `Text/ScriptingGuide.txt`. They are valuable BZR field observations, but they are operational evidence rather than a replacement for the stock HTML contract. Re-test when changing engine build or ownership strategy.

| Operation | Observed behavior / design rule |
|---|---|
| `MakeExplosion` | local visual/gameplay effect; remote peers do not automatically receive the explosion/damage |
| `SetVelocity` | observed to synchronize correctly |
| `BuildObject` | globally useful creation is safest from the host/authoritative machine; client creation can have visibility/AI problems |
| `RemoveObject` on non-local object | can be corrected by remote ownership/state and appear to “respawn”; explicit per-peer synchronization is safer |
| `SetPosition` on non-local object | similar locality problems to removal |
| `SetLocal` on remote AI | can break AI ownership/control; avoid casual ownership theft |
| `SetName` / visible name changes | observed local-only in project testing |
| objective-marker changes | observed not to synchronize automatically |
| `Hide` / `UnHide` | peers may need the hidden state applied consistently; vehicles/buildings can diverge in visibility/AI/radar behavior |
| team-changing mutations | project notes require local ownership for reliable changes to another player's units |
| `GiveWeapon` | project notes recommend broadcasting the change with `Send`/`Receive` so every peer applies it consistently |
| `DisplayMessage` | local chat-window output; stringify non-string values explicitly |

### Recommended authoritative pattern

For replicated script actions, prefer a small explicit protocol:

```lua
local MSG_REMOVE = "R"

function RequestRemove(h)
    if IsNetGame() then
        Send(0, MSG_REMOVE, h)
    else
        RemoveObject(h)
    end
end

function Receive(from, kind, ...)
    if kind == MSG_REMOVE then
        local h = ...
        if IsValid(h) then
            RemoveObject(h)
        end
        return true
    end
    return false
end
```

The exact ownership policy is mission-specific; the important rule is that a local mutation is not proof of replicated state.

---

# Function index

Notation in this section:

- `T?` = optional / may be omitted.
- `A|B` = overload/union.
- `pos` means `handle | path[, point] | vector | matrix` where the function provides those overloads.
- `[2.0+]` / `[2.1+]` are Redux-era availability markers inherited from the stock reference.

## Audio messages

```text
RepeatAudioMessage()
message AudioMessage(string filename)
boolean IsAudioMessageDone(message msg)
StopAudioMessage(message msg)
boolean IsAudioMessagePlaying()
```

Audio messages are 2D voice/narration playback and use the Voice Volume setting.

## Sound effects

```text
StartSound(string filename, handle? h, integer? priority, boolean? loop, integer? volume, integer? rate)
StopSound(string filename, handle? h)
```

With a handle, sound is positional and follows that object. Without a handle it is global 2D sound. Priority is 0–100; volume is 0–100; rate overrides playback sample rate.

## Game objects

```text
handle GetHandle(string label)
handle BuildObject(string odfname, teamnum team, handle h)
handle BuildObject(string odfname, teamnum team, string path, integer? point)
handle BuildObject(string odfname, teamnum team, vector position)
handle BuildObject(string odfname, teamnum team, matrix transform)
RemoveObject(handle h)
boolean IsOdf(handle h, string odfname)
string GetOdf(handle h)
string GetBase(handle h)
string GetLabel(handle h)
SetLabel(handle h, string label)
string GetClassSig(handle h)
string GetClassLabel(handle h)
ClassId GetClassId(handle h)
string GetNation(handle h)
boolean IsValid(handle h)
boolean IsAlive(handle h)
boolean IsAliveAndPilot(handle h)
boolean IsCraft(handle h)
boolean IsBuilding(handle h)
boolean IsPerson(handle h)
boolean IsDamaged(handle h, number? threshold)
[2.1+] boolean IsRecycledByTeam(handle h, teamnum team)
```

`ClassId` is a bidirectional table of stock numeric class identifiers and names. Prefer `ClassId.SCRAP`, etc. over raw numbers.

## Team number / perceived team

```text
teamnum GetTeamNum(handle h)
SetTeamNum(handle h, teamnum team)
teamnum GetPerceivedTeam(handle h)
SetPerceivedTeam(handle h, teamnum team)
```

Perceived team can differ from real team during disguise/empty-enemy-vehicle behavior.

## Target

```text
SetUserTarget(handle? target)
handle GetUserTarget()
SetTarget(handle h, handle target)
handle GetTarget(handle h)
```

`SetUserTarget` / `GetUserTarget` apply to the local player UI target.

## Owner

```text
SetOwner(handle h, handle owner)
handle GetOwner(handle h)
```

## Pilot class

```text
SetPilotClass(handle h, string? odfname)
string GetPilotClass(handle h)
```

A nil pilot class resets to the default nation-based assignment.

## Position and orientation

```text
SetPosition(handle h, string path, integer? point)
SetPosition(handle h, vector position)
SetPosition(handle h, matrix transform)
vector GetPosition(handle h)
vector GetPosition(string path, integer? point)
vector GetFront(handle h)
SetTransform(handle h, matrix transform)
matrix GetTransform(handle h)
```

`SetPosition` moves position only for the matrix overload; use `SetTransform` when orientation must also be applied.

## Linear / angular velocity

```text
vector GetVelocity(handle h)
SetVelocity(handle h, vector velocity)
vector GetOmega(handle h)
SetOmega(handle h, vector omega)
```

## Position helpers

```text
vector GetCircularPos(vector center, number? radius, number? angle)
vector GetPositionNear(vector center, number? minradius, number? maxradius)
```

Angles are radians. `GetPositionNear` is useful for scattering spawns without stacking them at exactly one location.

## Shot information

```text
handle GetWhoShotMe(handle h)
number GetLastEnemyShot(handle h)
number GetLastFriendShot(handle h)
```

## Alliances

```text
DefaultAllies()
LockAllies(boolean lock)
Ally(teamnum team1, teamnum team2)
UnAlly(teamnum team1, teamnum team2)
boolean IsTeamAllied(teamnum team1, teamnum team2)
boolean IsAlly(handle me, handle him)
```

`Ally`/`UnAlly` update both directions. Player-driven alliance actions can create half-allied states, so `IsTeamAllied(a,b)` need not equal `IsTeamAllied(b,a)`.

## Objective markers / visible names

```text
SetObjectiveOn(handle h)
SetObjectiveOff(handle h)
string GetObjectiveName(handle h)
SetObjectiveName(handle h, string name)
[2.1+] SetName(handle h, string name)
```

`SetName` is effectively an alias of `SetObjectiveName` in the stock API.

## Distance

```text
number GetDistance(handle h, handle|string|vector|matrix target [, integer point])
boolean IsWithin(handle h1, handle h2, number distance)
[2.1+] boolean IsTouching(handle h1, handle h2, number? tolerance)
```

Default `IsTouching` tolerance is about 1.3 m.

## Nearest-object queries

Each family supports the applicable `handle`, `path[,point]`, `vector`, and `matrix` reference overloads:

```text
handle GetNearestObject(pos)
handle GetNearestVehicle(pos)
handle GetNearestBuilding(pos)
handle GetNearestEnemy(pos)
[2.0+] handle GetNearestFriend(pos)
[2.1+] handle GetNearestUnitOnTeam(pos, teamnum team)
integer CountUnitsNearObject(handle h, number distance, teamnum team, string? odfname)
```

## Iterators

```text
iterator ObjectsInRange(number distance, pos)
iterator AllObjects()
iterator AllCraft()
iterator SelectedObjects()
iterator ObjectiveObjects()
```

Typical use:

```lua
for h in AllCraft() do
    -- ...
end
```

Use `AllObjects()` sparingly; it includes incidental objects such as scrap. **Redux note:** `ObjectiveObjects()` is usable in BZR; the hang bug documented in the reference is a 1.5.2.x bug fixed in Redux.

## Scrap management

```text
GetRidOfSomeScrap(integer? limit) -- default limit 300
ClearScrapAround(number distance, pos)
```

## Team slots

```text
handle GetTeamSlot(TeamSlot slot, teamnum? team)
handle GetPlayerHandle(teamnum? team)       -- WARNING: team argument broken in Redux
handle GetRecyclerHandle(teamnum? team)
handle GetFactoryHandle(teamnum? team)
handle GetArmoryHandle(teamnum? team)
handle GetConstructorHandle(teamnum? team)
```

When no team is supplied, the local player's team is used.

## Team pilots

```text
integer AddPilot(teamnum team, integer count)
integer SetPilot(teamnum team, integer count)
integer GetPilot(teamnum team)
integer AddMaxPilot(teamnum team, integer count)
integer SetMaxPilot(teamnum team, integer count)
integer GetMaxPilot(teamnum team)
```

## Team scrap

```text
integer AddScrap(teamnum team, integer count)
integer SetScrap(teamnum team, integer count)
integer GetScrap(teamnum team)
integer AddMaxScrap(teamnum team, integer count)
integer SetMaxScrap(teamnum team, integer count)
integer GetMaxScrap(teamnum team)
```

## Deploy / selection / mission-critical

```text
boolean IsDeployed(handle h)
Deploy(handle h)
boolean IsSelected(handle h)
[2.0+] boolean IsCritical(handle h)
[2.0+] SetCritical(handle h, boolean? critical)
```

Mission-critical objects disable player commands that could remove/recycle them.

## Weapons and damage

```text
SetWeaponMask(handle h, weaponmask mask)
boolean GiveWeapon(handle h, string? weaponname, weaponslot? slot)
string GetWeaponClass(handle h, weaponslot slot)
FireAt(handle me, handle him)
Damage(handle h, number amount)
```

Weapon mask bits correspond to hardpoints 1/2/4/8/16. Giving a blank/nil weapon with an explicit slot removes the weapon in that slot.

Multiplayer project note: apply weapon changes through an explicit replicated action when peers need identical equipment state.

## Time

```text
number GetTime()
number GetTimeStep()
number GetTimeNow()
```

`GetTimeNow()` is system milliseconds and is useful for profiling; mission logic should normally use simulation time/timestep.

## Mission / strategic AI

```text
SetAIControl(teamnum team, boolean? control) -- startup-only; see hazard
boolean GetAIControl(teamnum team)
string GetAIP(teamnum? team)                 -- default team 2
SetAIP(string aipname, teamnum? team)        -- default team 2
FailMission(number time, string? filename)
SucceedMission(number time, string? filename)
```

## Objective messages

```text
ClearObjectives()
AddObjective(string name, string? color, number? duration, string? text)
UpdateObjective(string name, string? color, number? duration, string? text)
RemoveObjective(string name)
```

Supported color names include black/grey/white/blue/green/yellow/red plus dark variants. See hazards: duration is fixed to eight seconds and more than ten simultaneous messages is unsafe.

## Cockpit timer

```text
StartCockpitTimer(integer time, integer? warn, integer? alert)
StartCockpitTimerUp(integer time, integer? warn, integer? alert)
StopCockpitTimer()
HideCockpitTimer()
integer GetCockpitTimer()
```

See the multiplayer-mode caveat above.

## Earthquake

```text
StartEarthquake(number magnitude)
UpdateEarthQuake(number magnitude)
StopEarthquake()
```

The unusual capital `Q` in `UpdateEarthQuake` is intentional.

## Path type / path area

```text
[2.0+] SetPathType(string path, PathType type)
[2.0+] PathType GetPathType(string path)
SetPathOneWay(string path)
SetPathRoundTrip(string path)
SetPathLoop(string path)
[2.0+] integer GetPathPointCount(string path)
[2.0+] integer GetWindingNumber(string path, handle|vector|matrix target)
[2.0+] boolean IsInsideArea(string path, handle|vector|matrix target)
```

A non-zero winding number means the point is inside the path-defined polygonal area.

## Unit commands

```text
boolean CanCommand(handle me)
boolean CanBuild(handle me)
boolean IsBusy(handle me)
AiCommand GetCurrentCommand(handle me)
handle GetCurrentWho(handle me)
integer GetIndependence(handle me)
SetIndependence(handle me, integer independence)
SetCommand(handle me, AiCommand command, priority? priority, handle? who,
           matrix|vector|string? where, number? when, string? param)
Attack(handle me, handle him, priority? priority)
Goto(handle me, string|handle|vector|matrix destination, priority? priority)
Mine(handle me, string|vector|matrix destination, priority? priority)
Follow(handle me, handle him, priority? priority)
[2.1+] boolean IsFollowing(handle me, handle him)
Defend(handle me, priority? priority)
Defend2(handle me, handle him, priority? priority)
Stop(handle me, priority? priority)
Patrol(handle me, string path, priority? priority)
Retreat(handle me, string|handle destination, priority? priority)
GetIn(handle me, handle him, priority? priority)
Pickup(handle me, handle him, priority? priority)
Dropoff(handle me, string|vector|matrix destination, priority? priority)
Build(handle me, string odfname, priority? priority)
BuildAt(handle me, string odfname, handle|string|vector|matrix destination, priority? priority)
[2.1+] Formation(handle me, handle him, priority? priority)
[2.1+] Hunt(handle me, priority? priority)
```

Priority `0` leaves the unit player-commandable; default priority `1` makes it uncommandable. `SetCommand` is low-level and not every command is valid for every unit.

## Tug cargo

```text
boolean HasCargo(handle tug)
[2.1+] handle GetCargo(handle tug)
handle GetTug(handle cargo)
```

## Pilot actions

```text
EjectPilot(handle h)
HopOut(handle h)
KillPilot(handle h)
RemovePilot(handle h)
handle HoppedOutOf(handle h)
```

## Health

```text
number GetHealth(handle h)        -- 0..1 ratio
number GetCurHealth(handle h)
number GetMaxHealth(handle h)
SetCurHealth(handle h, number health)
SetMaxHealth(handle h, number health)
AddHealth(handle h, number health)
[2.1+] GiveMaxHealth(handle h)
```

## Ammo

```text
number GetAmmo(handle h)          -- 0..1 ratio
number GetCurAmmo(handle h)
number GetMaxAmmo(handle h)
SetCurAmmo(handle h, number ammo)
SetMaxAmmo(handle h, number ammo)
AddAmmo(handle h, number ammo)
[2.1+] GiveMaxAmmo(handle h)
```

## Cinematic camera

```text
boolean CameraReady()
boolean CameraPath(string path, integer height, integer speed, handle target)
boolean CameraPathDir(string path, integer height, integer speed)
boolean PanDone()
boolean CameraObject(handle base, integer right, integer up, integer forward, handle target)
boolean CameraFinish()
boolean CameraCancelled()
```

`CameraObject` offsets are centimeters.

## Info display

```text
boolean IsInfo(string odfname)
```

## ODF / INI / TRN reads

```text
odfhandle OpenODF(string filename)
boolean value, boolean found = GetODFBool(odfhandle odf, string? section, string label, boolean? default)
integer value, boolean found = GetODFInt(odfhandle odf, string? section, string label, integer? default)
number value, boolean found = GetODFFloat(odfhandle odf, string? section, string label, number? default)
string value, boolean found = GetODFString(odfhandle odf, string? section, string label, string? default)
```

If `OpenODF` receives a filename without an extension it appends `.odf`. Retain frequently used ODF handles rather than reparsing repeatedly.

## Terrain / floor

All overloads accept a handle, path/point, vector, or matrix where applicable:

```text
number height, vector normal = GetTerrainHeightAndNormal(pos)
number height, vector normal = GetFloorHeightAndNormal(pos)
```

Floor queries include upward-facing polygons of entities marked as floor owners; terrain queries use the terrain height field.

## Map / files / screen effects

```text
[2.0+] string GetMissionFilename()
string GetMapTRNFilename()
[2.0+] string UseItem(string filename)
[2.0+] ColorFade(number ratio, number rate, integer r, integer g, integer b)
```

## Vector math

```text
vector SetVector(number? x, number? y, number? z)
number DotProduct(vector a, vector b)
vector CrossProduct(vector a, vector b)
vector Normalize(vector v)
number Length(vector v)
number LengthSquared(vector v)
number Distance2D(vector a, vector b)
number Distance2DSquared(vector a, vector b)
number Distance3D(vector a, vector b)
number Distance3DSquared(vector a, vector b)
```

Vector userdata supports negation, addition, subtraction, multiplication and division. Vector×vector multiplication/division is component-wise, not dot/cross product.

## Matrix math

```text
matrix SetMatrix(...12 components...)
matrix BuildAxisRotationMatrix(number? angle, number? x, number? y, number? z)
matrix BuildAxisRotationMatrix(number? angle, vector axis)
matrix BuildPositionRotationMatrix(number? pitch, number? yaw, number? roll,
                                   number? x, number? y, number? z)
matrix BuildPositionRotationMatrix(number? pitch, number? yaw, number? roll, vector position)
matrix BuildOrthogonalMatrix(vector? up, vector? heading)
matrix BuildDirectionalMatrix(vector? position, vector? direction)
```

Angles are radians. Axis-rotation axes must be unit length. Avoid constructing non-orthonormal transforms unless the engine behavior is explicitly understood.

## Portal — BZR 2.1+

```text
PortalOut(handle portal)
PortalIn(handle portal)
DeactivatePortal(handle portal)
ActivatePortal(handle portal)
boolean IsIn(handle portal)
boolean isPortalActive(handle portal)
handle BuildObjectAtPortal(string odfname, teamnum team, handle portal)
```

`BuildObjectAtPortal` creates the object at the portal effect and gives it an initial 50 m/s velocity.

## Cloak — BZR 2.1+

```text
Cloak(handle h)
Decloak(handle h)
SetCloaked(handle h)
SetDecloaked(handle h)
boolean IsCloaked(handle h)
EnableCloaking(handle h, boolean enable)
EnableAllCloaking(boolean enable)
```

Direct `Cloak`/`Decloak` calls do not replace the unit's current AI command, unlike issuing a cloak command through `SetCommand`.

## Hide — BZR 2.1+

```text
Hide(handle h)
UnHide(handle h)
```

Hidden objects are invisible and radar-hidden, but AI generally does not treat “hidden” as equivalent to “does not exist.” See multiplayer locality notes before using this as synchronized gameplay state.

## Explosion — BZR 2.1+

```text
MakeExplosion(string odfname, handle|string|vector|matrix location)
```

Explosions are not script-visible game objects and do not return handles.

---

# Common implementation patterns

## Feature-gated BZR code

```lua
if IsTouching ~= nil then
    if IsTouching(a, b) then
        -- Redux 2.1+ behavior
    end
else
    if GetDistance(a, b) < 1.3 then
        -- fallback
    end
end
```

## Safe player-handle model for multiplayer

Do not derive remote player handles with `GetPlayerHandle(team)`. Track them from session events and explicitly exchange current handles when required.

Conceptually:

```lua
local players = {}

function CreatePlayer(id, name, team)
    players[id] = { name = name, team = team }
end

function DeletePlayer(id, name, team)
    players[id] = nil
end
```

The exact handle update protocol depends on the mission because respawn/vehicle transitions can replace the player-controlled object.

## Producer build sequencing

```lua
local pendingDropoff = nil

function QueueRigBuild(rig, odf, where)
    Build(rig, odf)
    pendingDropoff = { rig = rig, where = where, frames = 1 }
end

function Update(dt)
    if pendingDropoff then
        if pendingDropoff.frames > 0 then
            pendingDropoff.frames = pendingDropoff.frames - 1
        else
            Dropoff(pendingDropoff.rig, pendingDropoff.where)
            pendingDropoff = nil
        end
    end
end
```

This models the documented requirement that the producer process `Build` for at least one simulation update before `Dropoff`.

## Bounded objective panel

```lua
local objectiveSlots = {}

local function SetObjectiveSlot(key, text, color)
    if objectiveSlots[key] then
        UpdateObjective(key, color or "white", 8, text)
        return
    end

    local count = 0
    for _ in pairs(objectiveSlots) do
        count = count + 1
    end

    if count >= 10 then
        error("objective panel limit reached")
    end

    AddObjective(key, color or "white", 8, text)
    objectiveSlots[key] = true
end
```

The `8` is documentary only; the engine's duration is fixed regardless of the supplied value.

---

# File-name and content constraints used by this project

Campaign Reimagined's scripting guide records an important content constraint: ODFs and files directly referenced from mission Lua should stay within the game's legacy **8-character basename** convention where applicable. Preserve existing short-name conventions when adding mission assets.

This is a project integration rule rather than a Lua language rule, but agents editing mission scripts should account for it.

---

# Source reconciliation notes

## `ObjectiveObjects()` conflict resolved

`Text/ScriptingGuide.txt` contains an older blanket warning not to use `ObjectiveObjects()`. The HTML function page gives the more precise behavior: the iterator's C++ loop counter was broken in Battlezone 1.5.2.x and could hang the game, but **the issue was solved in Battlezone 98 Redux**. For BZR work, use the HTML result.

## Null-padded strings conflict resolved

The project guide warns about hidden null bytes in several string-returning functions. The HTML pages qualify that bug to **Battlezone 1.5.2.x** and provide a compatibility wrapper for `GetOdf`, `GetBase`, `GetPilotClass`, and `GetWeaponClass`. Do not automatically wrap/alter BZR values unless a BZR runtime test reproduces the fault.

## Stock versus project APIs

`Scripts/scriptutils.lua` may contain Campaign Reimagined additions alongside the stock declarations. Treat explicit tags such as `[campaignReimagined]` as project APIs, not evidence that the retail BZR Lua runtime provides them.

---

# Maintenance rules for future agents

When updating this reference:

1. Inspect the relevant HTML leaf page, including `Known Issues`, not just `Scripts/scriptutils.lua`.
2. Preserve the exact affected game/version when documenting a bug.
3. If project runtime testing contradicts the HTML reference, record both with build/test provenance rather than overwriting history.
4. Add new stock functions to the function index under the correct category and availability marker.
5. Keep EXU/OpenShim/BZFILE/project helpers out of the stock index; document them in their own references.
6. Never “fix” odd stock capitalization in documentation or generated Lua.
7. For multiplayer findings, state whether behavior is canonical, observed, local-only, host-only, ownership-sensitive, or explicitly synchronized.

## Primary repository sources

- `References/StockLuaAPI-Functions/`
- `References/StockLuaAPI-Expressions/`
- `Scripts/scriptutils.lua`
- `Text/ScriptingGuide.txt`

These should be consulted in that order for stock API behavior and quirks.
