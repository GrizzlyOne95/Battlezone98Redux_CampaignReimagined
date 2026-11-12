# Chinese mission 08 Lua port

`Scripts/ch08.lua` ports `Chinese08Mission.cpp` to stock BZR 2.1+ and Lua 5.1.
The complete native source, including every comment, disabled block and unused
serialization member, is in `References/Chinese08Source/Chinese08Mission.cpp`.
Source repository: `GrizzlyOne95/Battlezone_Source`, path
`BZ1/from_bz2_dll_src/chinese08mission.cpp` (lower-case file name on the
repository's `main`), blob `319372874b7b9379401b4199562d1fd5c16dbe21`, 1423
lines. A local Battlezone_Source checkout may lag `origin/main`; the snapshot was
read with `git show main:...`. This is the faithful single-player port only; no
co-op behaviour is added.

Stock data used for verification: `chmisn08.bzn/.aip/.odf` in `tro_cam.zfs` and
the `ch08*.otf/.des/.wav` and `chmisn08.des` entries in `bzone_en.zfs` (read with
the Battlezone98_Modding_Toolbox `ZFSArchive` and `read_bzn`). Every object label
and path the script names exists in the stock BZN.

## Preserved behavior

- First Update: `chmisn08.aip`, 0 scrap team 1, 10 pilots, 0 scrap team 2,
  `ch08001.wav`, the eight escort tanks (`west_1_*`, `east_1_*`) cloaked,
  `CameraReady`. The 26 snipers are told to attack the player on the first
  frame and again only whenever the player handle changes.
- Cut-scene: `cut_1` follows `west_1_1` until either escort leader is within 50 m
  of `cut_trigger`, then runs 22 s; afterwards `CameraFinish`, `ch08002.wav`,
  the eight escort tanks and `walker_1` are removed.
- Convoy: 30 s later `ch08003.wav`, `svapc` #1 plus two `svfigh` `Defend2`
  escorts, then `svapc` #2..#5 at 5 s intervals, all sent on `apc_path`. When
  `ch08003.wav` finishes (and the state is still 5..10) a `cpcamr` nav "APC
  Convoy" is built at `apc_nav` and targeted.
- Capture: player in APC #5 (`apc[4]`) within 30 m of the "Base" nav starts a
  5-second delay, 100 scrap, `ch08004.wav`, the objective marker on APC #4
  (`apc[3]`, cleared at 100 m) and the formation rules. At `trigger_1` inside
  APC #5: `ch08006.wav` and a 20-second window to jump out (staying in fails
  with `ch08lseg.des`). Jumping out sets the player's perceived team to 2 for
  20 s (re-entering fails), then the 5-second `cut_bang` camera, the APC
  explosion, `wrecker_1` explosion, removal of the six `magpull` mines, military
  `cvrecy`/`cvmuf`/`cvslf` on `military_spawn` -> `military_path`, and full scrap.
- Convoy rules (`checkAPCs`): losing APC #5 or any of #1..#4 fails with
  `ch08lsed.des` (two seconds); `apcInLine` is 2 near `break_point`, a 25-second
  grace after APC #5 is dead, then formation distance > 100 m fails with
  `ch08lseb.des` (20 s) / `ch08lsee.des`; breaking off at `apc_fail`/`trigger_1`
  fails with `ch08lsec.des` after `ch08005.wav`.
- Fort: 5 minutes after the bang, team 2 scrap 100; at `nw_trigger`/`ne_trigger`
  (60 m) `ch08007.wav` + `ch08008.wav`, markers on both howitzers, power plants
  and comm towers, the nearer howitzer user-targeted. First power/comm death
  starts the 270 second cockpit timer; expiry fails with `ch08lsef.des`; power
  plant death removes that side's four `*_mag_*` mines and the bolt mine. After
  all four are dead: 40 s, then 10 timed `xpltrsd` demolition blasts over 106
  seconds, `ch08009.wav` and success 10 s later (`ch08win.des`).
- Fail when both recycler and factory are dead after the bang
  (`ch08lsea.des`). Core-failure rule: within 200 m of `east_cloak`/`west_cloak`
  the player's cloak is cut with `ch04002.wav` (the ch04 wav) and cloaking is
  disabled.
- Six reinforcement triggers (`spawn_1..6`, with `spawn_2a`/`spawn_3a`
  alternates sharing their flag) at 100 m of the nearest team-1 unit.
- Strict timer comparisons, zero-based arrays, native state order, and the
  `missionState` write / `resetObjectives` / write-back patterns (for example
  `MS_DISPLAYOBJ6` is set only while rebuilding objectives).

## Source quirks kept (not fixed)

- The east power plant branch removes `west_bolt` a second time; `east_bolt` is
  never removed.
- `ch08005.wav` is both the convoy-break and the straggler warning.
- Native `Setup` leaves `stateTimer` at its 99999 default; `lost` and
  `startwalker` are never read.

## Cut and unreachable content (kept as comments)

- `#if 0` blocks in four states that would send `walker_1` down `walker_path`
  when APC #1 is within 200 m (`startwalker`), and the two commented
  `Goto(walker_1, "walker_return")`.
- Commented `SetUserTarget(apc[4])` after the fifth APC spawns.
- The whole `ch08003.otf` objective and all GREEN variants of the intermediate
  objectives in `resetObjectives`.
- A commented earlier version of the military base spawn (`cvrecy`, `cvmuf`,
  `cvslf`) at the end of `MS_WAITFORSOUND4`.
- Six `svscav` team-2 Hunts from path `scavs` after the 5-minute timer.
- A commented `soundHandle = AudioMessage("ch08008.wav")` / `MS_WAITFORSOUND8`
  hand-off. `MS_WAITFORSOUND8` and `MS_DESTROYTOWERS` (100-second tower timer,
  `ch08lsef.des`) are therefore unreachable; they are ported as live but
  unreachable branches. `MS_WAITFORCLOAK` is empty and never entered.
- A "play avi..." comment before the end of `MS_WRECKER106`.
- The `useD3D & 4` split: `xpltrss` is the legacy renderer effect and is
  archived only; Lua uses `xpltrsr`.

## Unused voice and text

All nine `ch08001..9.wav` lines and their `Text/ch08001..9.txt` subtitles are
played by the active code, so no VO is unused. Unused data: `ch08003.otf` (cut
objective) and these map paths the script never names: `east_scout`,
`west_scout`, `east_sniper`, `guard_area`, `edge_path`, plus the cut-only
`walker_path`, `walker_return`, `scavs`. Stock English `bzone_en.zfs` has empty
(0 byte) `ch08003..07.otf` and `ch08lsea`, `ch08lseb`, `ch08lseg`, `ch08win`
`.des` files (see Risks).

## Fixes and API adaptations

- Null native handles become `nil`. Every handle query is guarded (`Alive`, `Cloak`,
  `Distance`, `Health`, `Strike`, `Remove`): invalid handles return infinity,
  false or no-op instead of reaching the stock overloads. A dead or removed
  handle never becomes a zero-distance trigger. No object is resurrected and no
  new gate is added.
- Camera and explosion calls that take `apc[4]` or `west_1_1` are skipped when
  that handle is dead; the native code uses it unchecked.
- `MakeExplosion(location, odf)` is reversed for stock Lua (`odf, location`).
- `SetName` is used (stock alias of `SetObjectiveName`); colours are `"white"`
  and `"green"`; `isCloaked/enableCloaking` become `IsCloaked/EnableCloaking`.
- `GetNearestUnitOnTeam(path, 0, 1)` becomes `GetNearestUnitOnTeam(path, 1)`.
- APC #2..#4 spawn cases share one Lua branch (names `apc_2..apc_4`).
- Save/Load persists the single state table through LuaMission serialization
  and does not replay spawns, cameras or audio.

## Binding

None of `Scripts/ch01.lua..ch07.lua` is bound to a map in this repository: no
`chmisn0N.bzn` ships in the repo, nothing maps the mission name to the script,
and the ch0N scripts say only "attach to the original map" (ch07's notes: wire
the mission's LuaMission configuration to the script). The stock `chmisn08.bzn`
(version 2004, binary) is a native `Chinese08Mission` object, not a `LuaMission`.
This port follows that state and does not invent a binding; the later co-op
step has to ship a `LuaMission` BZN (as `crsetup.bzn` does) pointing at this
script. `chmisn08.aip` is not in `aiCore.lua`'s AIP table (only `chmisn06.aip`
is), the same as for the other Chinese ports.

## Risks and live-test checklist

Risks: only API doubles were run; there is no engine playtest. English stock
objectives `ch08003..07.otf` and `ch08lsea/lseb/lseg/win.des` are empty, so
those objective panels and fail/win texts show blank in English until replaced.
`GetNearestUnitOnTeam` is assumed to accept a path name in the stock Lua build.
A modified map missing the stock labels would silently skip the affected steps.

Checklist (with a LuaMission BZN bound to the script):

1. Intro VO, camera, cloaked escort tanks drive; cut-scene triggers, 22 s, ends.
2. Five `svapc` and two fighters spawn 30 s later; nav "APC Convoy" after VO.
3. Capture APC #5, reach "Base" nav, VO 4, scrap 100, APC #4 marker clears at 100 m.
4. Each failure: lose an APC, straggle > 100 m, break off early, stay in APC 20 s.
5. Jump out at `trigger_1`: bang camera, mags removed, recycler/factory arrive.
6. `nw_trigger`/`ne_trigger`: VO, markers, howitzer targeted; kill one power
   plant, see the 4:30 timer, kill the remaining pieces; timer expiry fails.
7. 10 demolition blasts, `ch08009.wav`, win 10 s later.
8. Reinforcement waves; cloak field message at the cloak paths.
9. Save and load at: convoy, timer running, demolition. Nothing respawns.

## Validation

`lua5.1 Tools/Test-Chinese08.lua` (mission logic with stock API doubles) and
`python Tools/Test-Chinese08SourceParity.py` (source blob, asset/ODF/path names,
37 MS_ constants, timers, cut content absent from active Lua). Both run in
`.github/workflows/campaign-validation.yml`.
