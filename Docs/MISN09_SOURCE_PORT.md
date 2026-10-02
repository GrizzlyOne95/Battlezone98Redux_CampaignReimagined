# misn09 DLL source port to BZR Lua 5.1

`Scripts/misn09.lua` ports `Setup`, `AddObject`, and `Execute` from the original
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misn09Mission.cpp`.
No community or existing Lua mission supplied gameplay logic.

The verbatim source and header are retained in `References/Misn09Source/`:

| File | Original Git blob |
| --- | --- |
| Misn09Mission.cpp | `888ee877b4b56348ddf3e9717f01aed95fc0f066` |
| Misn09Mission.h | `924152c5233b7933506d19c2417e7cbff84ea7a0` |

This is a stock single-player BZR script. It requires Lua 5.1 and no EXU,
OpenShim, aiCore, or campaign helper modules.

## Preserved gameplay

- Opening scrap camera and delayed briefing; audio completion moves the factory.
- Factory rendezvous, unit command priorities, and original team resource grants.
- Deployment/silo scavenger release; artillery defense and camera; initial AIP.
- Recon/base proximity warnings; first-empty-slot ODF matching in AddObject.
- Four turret fortifications and their ten-second/15-second defense timers.
- Six-artillery objective completion and the aggressive AIP transition.
- Warnings at 700/1000 seconds; convoy spawn after 1300 seconds, deferred eleven
  seconds while the player is within 500 m of its spawn. All comparisons retain
  their original strict boundaries.
- Original relic, tug, ten escorts, paths, commands, teams, audio and asset names;
  reserved convoy AIP; enemy pickup, escort handoff and convoy camera.
- Friendly/enemy/free relic state transitions and destroyed-tug recovery.
- Charon proximity, info scan and navigation beacon.
- Original victory/failure branch order, debrief files, and delays. Victory still
  requires a living relic within 100 m of the living factory, not enemy-held;
  it adds no new deployment or friendly-carrier requirement.
- All 141 native state members, including those used only by disabled content.
  Camera heights retain the original per-update `x += 90` and `y -= 10` behavior.

## Three deliberate source fixes

Each is marked `PORT FIX` beside the relevant Lua code. The archived C++ remains
unchanged so reconstruction can inspect the literal original behavior.

| Source mistake | Lua correction | Effect on mission flow |
| --- | --- | --- |
| Turret 3 sets `post1 = true` after moving to post 3 | Set `post3 = true` | Stops reissuing Goto/resetting its timer every frame; restores the same one-shot move and periodic defense as the other posts. Does not change any spawn, objective, convoy, or outcome gate. |
| Convoy camera guard uses `CameraCancelled` without parentheses | Call `CameraCancelled()` | The function address was always true. Restores the existing 18-second/cancel shot rule. Camera completion does not gate mission progression or outcomes. |
| A semicolon immediately follows the factory deployment/distance condition | Apply its authored `IsDeployed` and `< 400 m` check | Prevents a premature green deployment objective. The latch controls this display update only; convoy, relic and outcome rules are unchanged. |

These corrections change the defective turret/camera/display behavior; they do
not introduce a new gameplay sequence or alter mission success/failure rules.

## Cut content

Every original comment in Setup/Execute remains verbatim inside inactive Lua long
comments at its corresponding location. The source archive also preserves all
declarations, native lifecycle/serialization code and their comments.

Retained disabled blocks include alternate player-tug cargo detection, the
20-second start flag, the old 900-second convoy timer, launchpad/choke-point
camera alternatives and dialogue, the alternate factory-follow sequence, the
five-artillery camera montage, replacement enemy tugs, immediate convoy Pickup,
and the all-enemies-cleared victory call. Restoring them requires a deliberate
Lua translation and verification of the original map/assets.

## BZR adaptations and preserved oddities

- `Get_Time` becomes `GetTime`, native factory casts become `IsDeployed`, native
  SetName calls become `SetObjectiveName`, and objective colors become strings.
- Null object handles become nil; audio messages remain opaque stock message
  values. No-message audio stop/completion is handled without passing nil to the
  stock message API. Bare and `.odf` ODF names are accepted for object callbacks.
- Absent/removed handle operands return infinite distance rather than selecting
  an invalid Lua overload or triggering a false proximity check.
- Save/Load returns/restores the mission state table. Load does not call Start,
  repeat Setup, spawn units or replay commands/cameras. Native binary arrays and
  ConvertHandle rebasing are replaced by LuaMission's serialization mechanism.
- AddObject remains ODF-only, with no new team filter or dead-slot reuse. Convoy
  creation can fill those slots through normal synchronous callbacks.
- Relic carrier changes are detected under the original free-state rules;
  detach-without-carrier-death is not redesigned. The non-team-1 branch retains
  its original assignment of `tugger = ccatug`.
- The artillery camera/AIP handoff remains inside the artillery-6-alive branch,
  including its original behavior if that unit dies before the shot completes.
- The shared deployment polling timer, duplicate area-cleared messages and
  informational `game_over5` flag remain unchanged.

## Validation and remaining integration

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn09.lua
python Tools/Test-Misn09SourceParity.py
```

Validated with Lua 5.1.5: 110 mock-host behavior checks and 199 source-preservation
checks. The latter pin exact source/header bytes, preserve every gameplay comment
and state member, and compare Setup/Execute API call order and all 16 AddObject
slot mappings. Both suites run in campaign CI. Mock tests do not prove native AI,
camera rendering, audio timing, or engine save/load handle restoration.

This is a script checkpoint, not an in-game-qualified mission. At inspected main
`6636e74086d1587a6cf129b04b2d8d04ea997a99`, no `Missions/misn09` bundle or
`misn09*.aip` files were present. Supply/verify the original map, labels, camera
and movement paths, AIPs, ODFs, audio, objective/debrief files, and LuaMission
binding before deployment. Test initial AddObject delivery, real tug attachment,
strategic AI, camera motion/cancellation and save/load in BZR. No mission bundle,
shipping lock, deployment or release configuration is changed by this port.
