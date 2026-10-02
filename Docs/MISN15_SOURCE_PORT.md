# misn15 source-faithful Lua 5.1 port

`Scripts/misn15.lua` ports the active mission logic directly from
`GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Misn15Mission.cpp`
(Git blob `75974c4173246e540bf871eedc94cf09736989c8`). No community or existing
Lua mission was used as the gameplay source. The original C++ and include-guard
header are archived byte-for-byte in `References/Misn15Source/`.

The script targets stock single-player Battlezone 98 Redux / Lua 5.1. It requires
no EXU, OpenShim, aiCore, weather, or coop module.

## Preserved mission behavior

- First Update adds ten scrap, resolves the original map labels, names six camera
  pods, sends two Soviet tanks and an APC along `tank_path` at command priority 0,
  plays the briefing, and targets Nav Beta. The commented `misn15.aip` stays disabled.
- The follow-up briefing waits for the opening audio and a strict two-second
  deadline. Its tank camera uses the original 800/600/1200 centimeter offsets
  and eight-second duration. Soviet arrival is tested at either original pod.
- The three-minute NW rescue reminder and strict 150-meter approach trigger are
  preserved. Rescue creates one scavenger, one APC, and one turret, then shows
  `rescue_cam1` for three seconds. It does not revive the old factory composition.
- Approaching Tartarus plays both `misn1513.wav` and `misn1514.wav`, in source order.
- The first `hvsav` wave arrives after 120 seconds, then one every 240 seconds,
  up to 50 waves. The two spawn sites remain equally likely; Lua's random stream
  is not expected to reproduce the native C `rand()` sequence. Friendly scavenger
  AddObject callbacks select the latest attack target; startup selects the recycler.
  Dead targets are not replaced with a new gameplay target. The five-second
  scheduler sends only living, idle savs along `alien_path`.
- The `misn15b` marker enables the two pairs of `hvsat` units at 300 and 400 seconds,
  using the original sites and `deny1`/`deny2` paths. The second pair overwrites
  the saved `sat1`/`sat2` handles without deleting the first pair, as in the source.
- Two friendly silo additions complete the silo objective. This is a cumulative
  AddObject count, not a live-silo count. Destruction does not undo it.
- Recycler destruction plays the original cross-mission `misn1414.wav` and queues
  `misn15l1.des` after ten seconds. More than 74 team-1 scrap queues `misn15w1.des`
  after ten seconds. Arrival, rescue, and silo objectives are **not** additional
  victory prerequisites; the original script tests only scrap for success.
- Original strict timer/distance comparisons, branch order, 99999 timer sentinels,
  zero-based sav list, unused state, and literal asset/path names remain intact.

## Preserved cut content

Every disabled gameplay block remains C++ inside Lua comments at its corresponding
location. Keeping it disabled avoids introducing unverified map/content changes.
The complete archive also retains all declaration and binary save/load comments.

The retained experiments include `SetAIP("misn15.aip")`, the `waspmsl` spawn and
front-vector aiming, frozen preplaced scavengers/factory/howitzer/turret handles,
the full NE rescue reminder and two-scavenger/howitzer composition, its camera,
the earlier relic-warning sketch, and the old briefing/proximity/spawn intervals.

## BZR adaptations and documented fixes

- Native `Get_Time` is spelled `GetTime` in stock Lua. Native object `SetName`
  uses the stock `SetObjectiveName` alias. `CMD_NONE` becomes `AiCommand.NONE`.
- Nil/deleted handles are excluded from distance, naming, targeting, camera, and
  unit-command calls. Normal valid-map behavior is unchanged; missing objects
  cannot accidentally satisfy proximity conditions or reach invalid Lua overloads.
- Mission state exists before map AddObject callbacks. Start does not reset it,
  so it preserves silo additions reported during map loading. Startup actions
  remain in the first Update, matching native Execute.
- A missing camera subject releases the shot. The rescue shot also honors
  CameraCancelled and requires its active flag before finishing. These changes
  release camera control without changing rescue spawns, mission timers, or the
  normal three-second shot duration. Source camera sequencing otherwise remains.
- Recycler failure has precedence over success. Native Execute checks failure
  first, then can call SucceedMission in the same frame when scrap is already 75.
  The added `not lost` success guard prevents that overwrite while preserving
  every success with a surviving recycler and the original ten-second delay.
- Native `won` was never set. Victory now records it, and objective refreshes keep
  all four entries green after `got_dough`, matching the source victory display.
  This changes bookkeeping/display during the outcome delay, not victory gates.
- Save/Load returns/restores the mission state table through LuaMission. It does
  not rerun startup, recreate units, clear timers, or recount loaded silos. Native
  binary-array serialization and ConvertHandle are engine responsibilities in Lua;
  their exact C++ remains available in the archive.

## Validation and integration status

Run from the repository root:

```sh
lua5.1 Tools/Test-Misn15.lua
python3 Tools/Test-Misn15SourceParity.py
```

The Lua 5.1 mock host passes **85 checks** covering startup/callback order, strict
boundaries, both active cameras, cancellation/missing subjects, Soviet arrival,
rescue composition, relic warnings, both random branches, idle-only scheduling,
the 50-wave cap, target selection, both map variants, cumulative silos, save/load
state, outcomes, failure precedence, and cut content remaining disabled.

The source audit verifies both original Git blob hashes, all 13 gameplay block
comments, every gameplay line comment, all 49 active string identifiers, and all
28 initialized boolean/timer/counter members. The repository's Lua checks also
accept the new script and host test. These checks do not simulate native strategic
AI, audio-message persistence, cinematic restoration, or actual handle remapping.

At inspected main commit `6636e74086d1587a6cf129b04b2d8d04ea997a99`, the repository
contains mission text and friendly ODFs but no `Missions/misn15` map bundle.
In-game qualification still requires the original map/variant, their labels and
paths, and audio/objective/debrief/alien assets resolving through BZR content.
Verify real save/load during both cameras and between wave spawns, including
native handle restoration and the opening audio token. This checkpoint adds no
map binding, shipping-lock entries, deployment, or release configuration.
