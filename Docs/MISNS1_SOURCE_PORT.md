# misns1 DLL-source port for BZR Lua 5.1

`Scripts/misns1.lua` ports the active `Setup` and `Execute` routines from
`Battlezone_Source/BZ1/from_bz2_dll_src/Misns1Mission.cpp`.
The exact source files, including every comment, declaration, and native
serialization routine, are archived in `References/Misns1Source/`:

- C++ blob: `2777814cd482d24d7d9aed0ee4b76bb5c937f241`
- Header blob: `43fb73ea0d7172dc74442979ffba85203f772c4e`

The port targets stock single-player Battlezone 98 Redux with Lua 5.1.
It uses no EXU, OpenShim, aiCore, or campaign helper modules.

## Preserved mission behavior

- Original map labels, unit ODFs, teams, resources, visible names, radio files,
  objective files, and three outcome debriefs, except the documented filename typo.
- One initial walker, four camera pods, five additional Soviet units, and the
  removal of two American tank escorts.
- The 180-second convoy departure, three random routes, convoy followers,
  walker blockade placement, entrance and halfway warnings, and blockade escape.
- The enemy-within-200-meters retreat, surviving escort response, geyser arrival,
  `misn09.aip` handoff, and retreat reinforcement schedule.
- Colorado's destruction before reaching safety, escort retreat, two scavengers,
  `misn14.aip` handoff, and the alternate reinforcement schedule.
- Nine factory reinforcement units and two turrets. The first two waves require
  a living factory; the third also requires a living silo. The source's turret
  triggers have no health requirement: a still-valid wreck remains a spawn
  position, but a missing factory cannot supply a position.
- The three-unit cavalry wave 180 seconds after Colorado's destruction; four
  random cavalry results still map to two routes, with their original warnings.
- Original destruction announcements, objective rebuild order, audio-gated
  victory and losses, strict distance/time comparisons, and per-frame branch order.

## Commented-out content

All 59 gameplay comments remain verbatim inside disabled Lua long comments near
their source locations. The exact C++ archive preserves the remaining declaration
and serialization comments as well.

The cut content includes two extra walkers, two extra walker camera pods, alternate
startup movement/removal commands, the opening cinematic, two extra convoy tank
followers, alternate trap triggers, walker attack/independence commands, explicit
attack-wave dispatch, two extra cavalry tanks, and the third/fourth cavalry route
warning sequences. None of these blocks runs in this port.

All 143 declared mission fields are initialized and retained, including unused
state needed for reconstruction. The cut wave-dispatch blocks reference undeclared
`aw1sent`, `aw2sent`, and `aw3sent`; restoring them also requires capturing the
wave's `BuildObject` results. Those source omissions remain visible in the archive.

## Documented fixes and BZR adaptations

Each fix is explained beside the Lua code, including its effect on mission flow:

- The victory recycler objective uses `misns103.otf`, correcting the source's
  `misn103.otf` typo. This changes objective text selection only.
- Missing object handles cannot trigger distance warnings or reach mutation APIs.
  In particular, the removed `et3` escort is skipped rather than replaced, and
  unbuilt `walkcam2` cannot produce a false cavalry warning. Valid object behavior,
  trigger thresholds, branch latches, and the cut unit counts remain unchanged.
- A missing factory cannot be used as the position for scavenger or turret
  creation. No alternative spawn location or new factory-alive requirement is
  introduced. Attempts retain their original one-shot flags and deadlines.
- The escape camera's `geyser2` lookup is disabled in the source. Its loss shot
  uses Colorado as the fallback anchor; if `geyser2` is restored, it takes priority.
  Camera framing changes, while the original escape trigger and two-message wait
  remain intact.
- Each outcome request is emitted once at its first eligible frame. Separate
  saved latches preserve the source call order if different outcomes coincide;
  the port introduces no new delay or global outcome precedence.

Native `GetObj(...)->SetName` calls become `SetObjectiveName`. Null object handles
become nil. The random route draws become `math.random(0, 2)` and
`math.random(0, 3)`; the selections are saved, and loading never redraws them.
The source escort-retreat priority `1000` is retained for runtime verification.

`Save` returns the mission state table and `Load` restores it through LuaMission.
Loading does not rerun startup, respawn units, or replay completed outcomes. Native
binary-array serialization and `ConvertHandle` are preserved in the C++ archive;
LuaMission handles serialization/restoration of supported game userdata.

Source oddities whose correction would require a gameplay choice remain intact:
the repeatedly requested objective rebuild after both outpost structures are
destroyed, late convoy dispatch if Colorado dies before departure, and overlapping
success/failure conditions. The unused `walkcam2` warning remains available for
future camera reconstruction.

## Validation and integration

Run from the repository root:

```sh
lua5.1 Tools/Test-Misns1.lua
python3 Tools/Test-Misns1SourceParity.py
```

The Lua mock-host suite passes 164 checks, including all convoy/cavalry choices,
both complete reinforcement schedules, strict trigger boundaries, objective/radio
flow, valid-wreck versus absent-factory behavior, all outcomes, source call order,
save/load resumption, and disabled content remaining inactive.

The source audit verifies two byte-identical archived blobs, all 59 gameplay
comments, all 143 initial state fields, 62 ordered predicates, 131 ordered string
references with the documented typo correction, and active API call coverage.
Both suites are wired into campaign validation CI.

This is a source-script checkpoint. In-game qualification remains outstanding:
map labels and paths, strategic AI, original mission audio/objective/debrief files,
camera framing, the native priority-1000 commands, and real userdata restoration
must be checked in BZR. The inspected repository main has mission text but no
`misns1` map bundle or the referenced `misn09.aip` / `misn14.aip` files. Supply or
verify these stock mission assets and bind the mission configuration to the Lua
script before gameplay testing or deployment.
