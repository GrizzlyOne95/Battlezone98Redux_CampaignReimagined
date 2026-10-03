# misns4 native-source port

`Scripts/misns4.lua` ports `BZ1/from_bz2_dll_src/Misns4Mission.cpp` from
[Battlezone_Source](https://github.com/GrizzlyOne95/Battlezone_Source/blob/main/BZ1/from_bz2_dll_src/Misns4Mission.cpp).
It targets stock BZR Lua 5.1 and follows `Docs/BZR_LUA_AGENT_REFERENCE.md`.
The complete `.cpp` and `.h` are preserved byte-for-byte in
`References/Misns4Source/`, including native serialization and the header's
existing `Misns6Mission` guard typo. Source Git blob IDs:

- `.cpp`: `efc5de9d0b4cd4fcfd0165c04319725417f87ae7`
- `.h`: `2fd7c8a8ba44333518856982269ad9eac5a2fa77`

## Preserved behavior

Startup runs on the first Update: artillery, Bridge pod, two towers, two powers,
and a Soviet constructor; +50 scrap and 30 pilots per team; the original objective,
both briefing messages, and a 420-second cockpit timer with 300/0 thresholds.
At strictly greater than 30 seconds, one commanded reminder fighter and two
uncommanded raiders spawn. At strictly greater than 100 seconds, two tanks and
one howitzer spawn at `sbridge`.

Five friendly `svhaul` transports start after 420 seconds, then at 45-second
intervals measured from each actual spawn Update. AddObject orders them down
`escort`. The first spawn plays `misns402.wav` and stops/hides the timer; every
spawn receives an objective marker. Preplaced friendly haulers count as in the
native callback. Default command priority remains uncommandable.

Approaching `sbridge` within 200m creates the original north force. Clearing
`t1`, `t2`, and `b1` after that approach plays `misns405.wav`, sets `misns4.aip`,
and starts a 150-second counterattack deadline. The source's annotated
“wrong message” is retained; there is insufficient evidence to choose another.
The source can clear the bridge before the guards' 100-second spawn; this is
also retained because adding a spawn prerequisite changes mission ordering.

The four-rocket counterattack requires the **third** hauler to be alive and
either the deadline to expire or that hauler to reach within 200m of `warn1`.
It remains disabled if that particular hauler dies; other haulers do not replace
it. The player warning at `warn1` remains separate.

Four arrivals within 100m of `goal` succeed after ten seconds with
`misns4w1.des`. Two losses fail after fifteen seconds with `misns4l1.des`;
native integer division is explicitly preserved with `math.floor(5 / 3)`.
An arrived hauler remains tracked, and later destruction still counts as a
casualty, matching the source. No removal/despawn or new escort AI is added.

## Documented port fixes

- Guard missing/dead distance operands and missing spawn handles. A nonexistent
  or destroyed hauler cannot earn an arrival; living-unit radii are unchanged.
- Bound the ten-slot native convoy list and deduplicate registrations. Register
  returned haulers immediately as well, so synchronous and deferred AddObject
  delivery both produce five transports at the original spacing.
- Set the source's unused `lost` flag at the second casualty. Further casualties
  report their own audio but cannot push the existing failure deadline later.
  Latched failure takes precedence over stale arrival state.
- Use `>= 4` for success: a fourth and fifth arrival in the same Update can jump
  from three to five and miss the source's equality. The intended four-of-five
  requirement and ten-second delay stay the same.

Each fix is explained beside the relevant Lua code. Unused state (`first_bridge`,
`attack_time`, `b2`, `h1`, `h2`, and all ten array slots) is retained. Save/Load
serializes mission state with engine handles and does not replay startup.

## Cut content

The disabled light tank at `spawn4`, second howitzer at `sbridge`, and extra
tank at `spawn3` are retained inline. All escort-path notes, future north-force
notes, AIP note, casualty audio placeholders, and unfinished casualty cinematic
note are also retained. None is activated by this port. The source contains no
implemented cinematic.

## Validation and integration

From repository root:

```sh
lua5.1 Tools/Test-Misns4.lua
python Tools/Test-Misns4SourceParity.py
```

The mock host checks timing boundaries, forces, synchronous/deferred callbacks,
the third-hauler triggers, four/five simultaneous arrivals, two-loss defeat,
invalid handles, callback bounds, map loading, and save/load. Source audit checks
the exact archive hashes, source resource names, and retained cut-code lines.
These are host checks, not an in-game playthrough.

The script retains the source's map paths, ODFs, `.otf`, audio, `.aip`, and debrief
names. Existing main does not contain a `misns4` mission map/package; this PR adds
the script and evidence only. Deployment requires matching stock mission assets
and TRN LuaMission wiring. In-game path following, native AIP behavior, dialogue,
and saved-game handle restoration still need validation in BZR. No shipping-lock
blessing or deployment is included.
