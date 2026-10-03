# BlackDog09 Lua port

`Scripts/bdmisn09.lua` ports `BlackDog09Mission.cpp` from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src`. The complete original is
archived at `References/BlackDog09Source/BlackDog09Mission.cpp`, matching Git
blob `0f93213b17334acf7c0a408a44cdaf3791e1e644` byte for byte. This preserves all
comments, native serialization, unused state, and both disabled gameplay calls.
The disabled perceived-team and objective calls also appear beside their Lua
counterparts, still commented out.

The port retains Execute order, strict timer/range comparisons, all eight
audio files, APC disguise and tracked-tank capture, four convoy path orders,
three camera beacons, the 75-meter straying test, eleven-unit deviation ambush
and full `cvturrc` sweep, five final tanks, portal activation and immediate
contact victory. Original `cvtnkb` timeout eligibility is intentionally retained;
it is not broadened to every tank or tied to the captured handle. Objective
durations use the stock default, as in the C++ calls. No missing SOE #9 or
unused camera/objective state has been given invented behavior.

Inline PORT FIX comments explain these bounded corrections:

- Arm the one-second exposure ambush once instead of postponing it every frame.
- Initialize the tank timeout disarmed (`-1`), so its original ten-minute
  departure timer can arm even without an earlier `cvtnkb` reset.
- Latch timeout failure so portal victory/destruction cannot overwrite it
  during the existing one-second failure delay.
- Guard absent/deleted handles and failed builds. Unspawned beacons cannot
  advance rendezvous logic; destroyed convoy members count as absent for
  straying. Missing/deleted portal handles follow the portal-loss branch.

Save/Load retains the state table, including timers, audio tokens, handles,
zero-based unused camera arrays, and ending flags. Load does not replay Setup.
Native `activatePortal(portal, true)` and `isTouching` map to stock Redux
`ActivatePortal` and `IsTouching`. Redux 2.1+ is required.

Validation from the repository root:

```sh
lua5.1 Tools/Test-BlackDog09.lua
python3 Tools/Test-BlackDog09SourceParity.py
python3 Tools/Validate-CampaignRepository.py
```

The Lua mock tests cover normal convoy progression and briefing completion,
strict boundaries, both deviation triggers, exact wave counts, turret sweep,
one-shot final ambush and portal activation, leave/return/releave timeout,
scheduled audio/timeout restoration, deleted portal, and outcome ordering.
They do not substitute for an engine playthrough or actual engine save/load.

Current main has no BlackDog09 mission map/terrain or LuaMission binding. This
change supplies the script without changing map registration or the shipping
lock. Before integrating, supply the original map with `portal`, `cvtnk1` through
`cvtnk5`, `tank_path`, `spawn_beacon1` through `spawn_beacon3`, `spawn_deviate1`
through `spawn_deviate6`, `trigger_1`, and `last_one`; confirm original ODF/audio/
objective/debrief assets resolve, and bind LuaMission to `bdmisn09.lua`.
In-game AI convoy behavior, disguise perception, portal contact/effects,
audio, and actual save/load remain to be validated.
