# Chinese mission 04 Lua port

`Scripts/ch04.lua` ports `Chinese04Mission.cpp` to stock BZR 2.1+ and Lua 5.1.
The complete native source, including every comment, disabled block and unused
serialization member, is in `References/Chinese04Source/Chinese04Mission.cpp`.
Source repository: `GrizzlyOne95/Battlezone_Source`, path
`BZ1/from_bz2_dll_src/Chinese04Mission.cpp`, blob
`11fb5b1a3203fd8a5e864ee30578624eb7788827`.

## Preserved behavior

- First Update: 0 scrap, 10 pilots, intro audio and same-frame opening camera.
- Five-second delay, 130-second route timer, six navs with strict 50m proximity.
- Alarm at trigger_1 within 70m or silo identification, one-second delay,
  ten pilots and same-frame alarm camera, then six further pilots.
- Cloak-dependent base alert, fighters within 200m of silo, identification,
  core failure audio/decloak, twelve chase units and six portal guards.
- Portal guards receive no initial scripted Attack. All surviving attack groups
  retarget only on player-handle changes at the source's state thresholds.
- Inward portal activation, ch04003 then ch04008 narration, 135-second escape
  timeout, strict 100m extraction radius, hidden player, moving end camera,
  two-second hold and success four seconds after closing the portal.
- Timeout precedence, strict timer comparisons, zero-based arrays and unused
  45-second stateTimer/lost/fakePlayer state. The end camera has no source
  cancellation or CameraFinish; neither is added.

Disabled code remains disabled: alternate uncloaked detection, forced initial
core failure, silo beacon, alarm narration, nine additional pilot spawns,
fake-player construction/health copy/movement and alternate final arrival test.
The native snapshot retains all of these verbatim for reconstruction.

## Fixes and API adaptations

- Guard native unchecked factory/portal/player health dereferences. Missing
  objects are skipped; surviving objects receive the same health delta each
  frame. No object is resurrected and no new failure/victory gate is added.
- Guard commands/targets for missing or deleted handles; invalid proximity
  returns infinity instead of advancing the route. Correct map/spawn behavior
  and command priorities remain unchanged.
- Use `IsInfo(GetOdf(target_silo))`: stock Lua accepts an ODF name rather than
  the native handle overload. Stock identification is class-based; another
  object with the same ODF can satisfy the engine's info query.
- Use exact stock names `IsCloaked`, `EnableCloaking`, `PortalIn` and
  `DeactivatePortal`; native `activatePortal(portal, TRUE)` means inward.
  `SetObjectiveName` implements native `SetName`.
- Null audio IDs become nil; absent audio does not block the existing sequence.
  Save/Load persist the state table without rerunning Setup or replaying events.

## Validation and integration

Run from the repository root:

```sh
lua5.1 Tools/Test-Chinese04.lua
python Tools/Test-Chinese04SourceParity.py
```

The decision harness covers stealth/exposed routes, startup/alarm fall-through,
strict radii and deadlines, both losses, spawn and attack counts, player changes,
missing handles, end-camera healing, victory and save/load between updates.
The parity check verifies the complete source snapshot and active content names.
Mocks cannot qualify engine camera paths, AI pilot boarding, cloak perception,
portal effects, or engine serialization/handle remapping. In-game testing on the
original ch04 map and assets remains necessary. This port does not change map
bindings or shipping manifests; configure the original map to load ch04.lua
when integrating it.
