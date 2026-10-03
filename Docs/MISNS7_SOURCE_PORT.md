# misns7 DLL-source Lua port

`Scripts/misns7.lua` targets single-player Battlezone 98 Redux and Lua 5.1.
It uses stock APIs from `Docs/BZR_LUA_AGENT_REFERENCE.md`; no EXU, OpenShim,
community mission, or existing Lua reconstruction is required as a logic source.
The original source is pinned in `References/Misns7Source/README.md`.

## Preserved mission behavior

- Initial resources, prison objective, perceived-team settings, starting rig
  command, scavenger spawn after eight seconds, and periodic turret defense.
- Prison discovery and 120-second escalation; damage-triggered escalation;
  fighter waves, APC targeting, turret deployment, and all four enemy AIPs.
- Prison destruction camera, three prisoners after 1.5 seconds, pickup within
  20 metres, 0.2-second boarding grace, pilot accounting, and every survivor mix.
- Threat-gated briefing, delayed objectives, recycler/factory engineer deliveries
  in either order, shared engineer timers, camera cancellation, and spare-factory
  detection. Each engineer restores one asset; one or two survivors retain the
  source's reduced recovery options.
- Locked supply shed, key messages, engineer route, 15-second cache delay,
  two scavengers, two turrets, three ammo packs, and two repair packs.
- Enemy scavenger relocation, factory destruction/rebuild plans, walker staging
  and retargeting, tower/power construction, offscreen rig removal, replacement
  rig and barracks, base turret, and main tower/power maintenance.
- Enemy recycler destruction wins; all prisoners lost or the APC lost before
  either producer restoration fails. The source's success-first tie ordering
  and ten-second outcome delays remain.

All 122 gameplay line comments and 20 block comments are retained. Disabled
APC stopping/pickup cameras, factory retreat, alternative AIP switch, immediate
rig replacement, later power/tower expansion, extra objective, and perceived-team
changes remain disabled. The complete archive additionally retains native class,
constructor/destructor, serialization, initialization, and handle-remapping code.

## Explained corrections and adaptations

| Issue | Lua handling | Effect on normal flow |
| --- | --- | --- |
| `b0`–`b9` declared as handles but used as build flags | Initialize boolean flags; preserve active b1/b2 and disabled b3/b4 logic | Same construction steps and delays; flags survive saving without being remapped as object handles |
| Dead main tower/power handles block replacement discovery because only NULL was accepted | Accept a replacement only when its predecessor is no longer alive | Existing maintenance recognizes completion; live slots and first-match discovery order remain |
| `&&` guards apply only to the last `||` survivor permutation | Group the survivor alternatives before all one-shot/delivery guards | Same initial briefing/deadlines for every survivor mix; later delivery state cannot restart briefing |
| Native null/removed handles passed to distance queries | Return infinite distance for invalid objects | Missing objects cannot satisfy pickup/delivery thresholds; live distances unchanged |
| Native booleans assigned NULL and numeric zero handles | Use false for booleans and nil for handles | Correct Lua truth values without changing triggers |
| Native object-pointer health reads and AiMission lifecycle | Use fractional GetHealth; configure team-2 AI only in Start | Preserve health thresholds and strategic-AI flow |

Lua Save/Load serializes the mission state table. Loading does not run Setup,
toggle AI, replay audio/cameras, rebuild units, or reset deadlines. Native unused
timers retain the 99999 sentinel, including the rig-check timer that is armed
only after offscreen rig removal.

## Source quirks deliberately retained

The safe-area cleanup removes surviving prisoners still outside the APC after
five seconds with no nearby enemy; subsequent death checks can reduce the survivor
count. This is active source behavior, not disabled content. Changing it into
automatic boarding would alter rescue difficulty, so it remains intact.

The third escalation fighter targets the APC whenever the second fighter lives,
despite a source comment mentioning radar range. The active condition has no
range test; none was invented. Source camera skipping restores a producer after
the engineer has spawned even if it has not walked to its destination. Jail-camera
timing and the supply route retain their source-specific behavior.

## Validation and integration status

`Tools/Test-Misns7SourceParity.py` verifies both exact Git blobs, all 210 fields,
every gameplay comment, stock API usage, disabled expansion, and all 497 active
assignments/calls in their original per-method order. It does not substitute for
condition/engine testing.

`Tools/Test-Misns7.lua` uses a strict Lua 5.1 mock host to exercise startup,
strict deadlines, escalation, all survivor permutations, boarding, both delivery
orders, camera skipping, reduced payloads, resources, supply spawns, enemy AIPs,
walker retargeting, construction/rebuilds, terminal ordering, and save/load during
mission stages. CI runs both tests.

The matching misns7 map and content assets are not added by this port. Test it
with the original map labels/paths, ODFs, AIPs, audio, objectives, and debriefing
files. Actual BZR strategic AI, soldier GetIn/Retreat behavior, construction-rig
production, camera presentation, and native userdata save/load still require
in-game validation. No map, shipping lock, or deployed mission was changed.
