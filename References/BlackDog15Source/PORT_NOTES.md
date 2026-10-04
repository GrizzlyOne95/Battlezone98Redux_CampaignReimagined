# Black Dog 15 Lua port

`Scripts/bdmisn15.lua` ports BlackDog15Mission.cpp to stock BZR 2.1+ / Lua 5.1.
The original C++ is retained byte-for-byte, including disabled code, comments,
member declarations, native serialization and preprocessor alternatives.
Upstream blob: `7a7d7d440cbc1ec875abf02a97683349820d1814`.

The script is standalone single-player Lua. Select LuaMission for the original
mission map and use the map/script basename `bdmisn15`. No map or packaging
files are changed by this port. Existing mission paths, ODFs, OTFs, WAVs and
debriefs must be supplied by the original mission assets.

## Preserved sequence

| Trigger | Action |
| --- | --- |
| First update | 50 scrap, 10 pilots, initial objective and bd15001.wav |
| Initial audio completes + 20 seconds | One west fighter, bd15002.wav |
| West audio completes + 40 seconds | Six south units, bd15003.wav |
| South audio completes + 120 seconds | Seven north units, bd15004.wav |
| North audio completes + 180 seconds | Six east units, bd15005.wav |
| First east wave + 60 seconds | Six more east units |
| Second east wave + 180 seconds | Six mixed-direction units, bd15006.wav |
| All 32 attackers dead, no breach | Completed defence objective, escape objective, bd15007.wav |
| Escape audio completes | Cockpit countdown: 30 seconds, warnings at 10 and 5 |
| Timer at 2 seconds or less | Finale camera at height 2400, speed 0 |
| Timer at zero | White fade, launch-site explosion, success scheduled + 5 seconds |

All scheduled waves use the source's strict `deadline < GetTime()` comparison.
The launch proximity message plays once at strictly less than 300 metres.
A live attacker at strictly less than 100 metres latches defeat, plays
bd15011.wav, waits for that audio to finish plus five seconds, plays
bd15012.wav and fails after its completion. Spawns continue during that
dialogue as in the source.

## Port fixes and adapters

- Dead or missing attackers are excluded from the breach-distance scan.
  Their stale/invalid positions cannot cause defeat; living attackers retain
  the original radius and check order.
- A latched breach excludes the all-dead success branch. Native code could
  begin both outcomes if the last attacker died after reaching the launch
  site. Successful unbreached defence still uses the original completion gate.
- The stationary finale view is submitted each update, as stock Lua cinematic
  controls require. The camera starts at the original timer threshold, with
  no new cancellation/skip behavior or CameraFinish before mission transition.
- Native CameraPathPath has no stock Lua binding. CameraPath needs a handle,
  so the adapter creates one hidden neutral apcamr at spawn_explosion1, gives
  it very high health, and uses it as the target. It never enters the enemy
  list, receives no objective marker, and does not affect mission gates.
  It survives the explosion and lasts until mission transition. This extra
  object is a camera approximation requiring runtime verification; hiding
  does not guarantee that AI ignores it.
- Native useD3D is unavailable to Lua. The port selects the hardware effect
  xpltrso; the original xpltrsp alternative remains documented in the script.
  MakeExplosion's stock Lua argument order is ODF, location. ColorFade maps
  directly to the source fade parameters.

The disabled DO_EXPLOSION build switch remains a false local Lua constant.
Enabling it skips the battle and starts the finale briefing as in the native
test build. Dormant objective flags, intro handles and sound8/sound9 timers
remain represented. The commented alternative explosion/camera/audio timers,
distance gate and bd15013.wav call remain comments beside their ported code.

## Validation and remaining runtime checks

Run `python Tools/test_bdmisn15.py` with `lupa.lua51` installed. The tests
execute actual Lua 5.1, compare all ordered enemy spawns with the C++ source,
verify the exact source blob, strict time/radius boundaries, defeat exclusivity,
audio gates, save/load continuation, camera target reuse and one-shot finale.

The BZR engine is unavailable in this environment. In-game testing is still
needed for asset/path resolution, wave AI, audio playback, countdown
restoration, the hidden camera target's framing/radar/AI behavior, and xpltrso
damage/rendering. Preserve the source's scheduled success after the explosion;
verify that player death near the blast overrides it as the native comment
expects. No invented distance-based failure condition is added.
