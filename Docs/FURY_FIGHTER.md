# Restored Fury fighter prototype

Owner request, 16 October 2026: restore the cut `hvraz` as a primary enemy in
NSDF Missions 14 onward, give it balanced custom Fury weapons, review its texture,
and investigate the reported destruction crash.

## Source and asset contract

The owner selected `Battlezone Files/Mods and Custom Files/Fury Fighter` in
Google Drive. `References/FuryFighter/original` preserves that standalone Redux
port and its material, with hashes in `provenance.json`. The native VDF is
byte-identical to the copy also found in ISDFC, but no ISDFC ODF or red texture
is used. The installed Redux/classic stock archives inspected contain the cut
texture `hvraz00.map`, without this VDF; this is a restored cut-asset port,
not a claim that Redux shipped an enabled stock fighter.

`crfraz` is the independent CR ODF/model name. `cfr11*` names its twelve GEO
companions, preventing collisions with another add-on's parts. The builder changes
material/skeleton resource strings and part-name prefixes only. Mesh vertices,
UVs, normals, skin weights, bounds, collision, hardpoints and native animation
remain intact. The GEO companions ship alongside the mesh: the legacy engine
still reads them, including during destruction.

The diffuse edit starts from Redux `Hvsav00_d.dds`. The built-in imagegen tool
sharpened the existing cyan-blue Fury atlas, preserving the UV islands and palette.
The selected PNG and prompt are retained under `References/FuryFighter`.
The shipped atlas is 1024-square BC1 DDS with full offline mips (the engine cannot
generate mips for compressed textures). Stock
Fury specular/emissive maps and a flat normal map are reused. The initial image
experiment using ISDFC's red atlas was discarded and is not part of this feature.

Rebuild with `python Tools/Build-FuryFighter.py`. The default source is the
preserved standalone port, so rebuilding does not depend on Google Drive.

## Initial balance

| Attribute | Prototype |
| --- | --- |
| Role | Fast ground-hover skirmisher; no SAV takeoff, WASP deployment or human pilot |
| Health | 2400, versus stock SAV/SAT 4000 |
| Forward / strafe speed | 35 / 24 m/s |
| Ammo / scrap dropped | 1400 / 3 |
| Fury Pulse, GC1 | Visible blue projectile, 55 damage each 0.5 s, 180 m range, 5 ammo |
| Fury Arc, GC2 | Blue Bolt Buddy derivative, 80 damage each 0.8 s, 160 m range, 8 ammo |
| Combined ideal sustained damage | 210 DPS; stock Bolt Buddy alone is 250 DPS |

The pulse can be dodged; the arc requires a closer approach. Neither weapon has
splash damage. Both use the existing native cannon/ordnance classes, with custom
weapon/ordnance definitions and Fury-style effects. These are prototype balance
values, not a completed human combat-balance qualification.

The owner also requested distinct Olympian and Fury mines. Stock `boltmine.inf`
explicitly says Fury mines inflict much more damage than the Mars Olympian
version. [Bolt mine variants](BOLT_MINE_VARIANTS.md) documents the new textures,
separate amber/cyan discharges, damage ratio and Mission 05/15/16/17 integration.

## Mission integration

| Mission | Fighter use |
| --- | --- |
| 14 | Two fighters and one SAV per base wave, +1 fighter per extra human. Existing twelve-Fury cap, tank escalation and hidden entry selection remain. The controllable prototype squad keeps its established identity. |
| 15 | Denial pairs and Tartarus response use fighters. Patrols follow light/light/heavy cadence, using the saved hunter counter; existing human scaling and ten-Fury cap remain. Fighters participate in target reacquisition. |
| 16 | Recurring off-boundary attack is a fighter pair. SAT strike roles and SAV facility/Texas counterattacks remain. Fighters block an optional camera when within 150 m of a human. Existing hidden entry and shared-camera spawn safeguards apply. |
| 17 | Two of every three scripted SAV/SAT spawns become fighters. Heavy slots keep their original type, routes and counts. Counter is saved with mission state. |
| 18 | Same two-thirds roster through the faithful offline script. Transport, engines, objectives, trigger order and total craft counts are untouched. Any later mine requests select the explicit Fury variant. |

Missions 17/18 still have their existing offline ports; this change does not
claim to implement or qualify their future co-op conversions. `CR_TEST_FAITHFUL`
bypasses only their roster adapter for archived source behavior tests; the
production adapter is exercised separately by `Test-FuryRoster.lua`.

## Validation and limits

`Test-FuryFighterAssets.py` checks provenance, geometry/native byte preservation,
hardpoints, resource links, ordnance range/damage and shipping membership.
`Test-FuryRoster.lua` exercises the actual Mission 17/18 adapters and persistence.
Mission 14/15/16 regressions cover the changed composition, guest authority,
caps, watched entries and the new camera-safety classification.

Native tests use private, windowed GOG loopback clients with the qualified
OpenShim/EXU bundle. The original standalone asset survived three lethal damage
cycles and normal shutdown in `hvraz-stock-baseline-3` (22 checks). The reported
VDF crash has **not been reproduced in that configuration**; its original cause
is **UNKNOWN**. No speculative VDF repair or crash-suppression hook is claimed.

The first candidate fixture stopped because its test-only runtime label was not
published to the guest. The second fixture observed eight gradual-damage and
moving-destruction cycles on both peers with normal exits, but failed its two
weapon-damage assertions. Those runs are diagnostic, not passing qualification.
The corrected fixture supplies an attack order before firing, so the native
scout turns toward its target. `FireAt` alone did not align the stopped craft.

| Run | Scope | Result |
| --- | --- | --- |
| `hvraz-stock-baseline-3` | Original Drive model; three destructions; two native clients | PASS, 6 steps / 22 checks; both clients exited normally |
| `hvraz-candidate-6` | Namespaced model/new texture, each gun separately, eight moving gradual-damage destructions observed on both peers | PASS, 13 steps / 35 checks; pulse inflicted 770 damage, arc 695 including an arriving pulse; normal exits |

The damage samples validate native hits, not a DPS benchmark. Both native clients
used DX11 Enhanced with `ChunkMeshes=1`.

`hvraz-legacy-chunks-9` passed 9 steps / 28 checks with `ChunkMeshes=0`: three
destructions of the original Drive model and three of `crfraz`. Both clients
exited normally and their previous INI bytes were restored. Thus the reported
crash is not reproduced here with either native or replacement debris.

Four-client attempts 7/8 stopped at the audio/session/registry preflight,
before fighter tests. They are **not** four-player fighter qualification. The
coordinator reported a missing/lost per-process audio session; subsequent
network checks do not establish a fighter fault because no fighter was spawned.

`fury-art-final-19` rechecked the final RGBA8 atlas with both mine variants on
two native clients: 13 steps / 30 checks, both guns hit (770 pulse / 720 arc damage)
and both clients observed destruction and exited normally. The original geometry
and material links remain; only the DDS encoding changed (RGBA8, then BC1 with
offline mips after the mine art comparison exposed gray BC3 output without mips). [Native fighter frame](images/fury-assets-20261017/fury-fighter.png).

Steam, Proton/Wine, native save/load and full mission combat balance are unverified
for this prototype. No normal game installation or Workshop content is deployed.
