# Mission 16 corrupted CCA textures

Owner-approved texture style, 16 October 2026. Built-in imagegen edited each
stock diffuse atlas with `hvsat00` as the Fury style reference. These PNGs are
the retained authoring outputs; their 1024 × 1024 BC3 DDS conversions are in
`Assets/Textures`. No generated geometry is used.

| Authoring image | Stock edit target | Copied model/material |
| --- | --- | --- |
| `cr16cmd_d.png` | `sbhqcp_d.dds` | `cr16cmd` |
| `cr16hng_d.png` | `sbhang_d.dds` | `cr16hng` |
| `cr16pwr_d.png` | `sbspow_d.dds` | `cr16pwr` |
| `cr16tow_d.png` | `sbtowe_d.dds` | `cr16tow` |

Prompt set: edit each flat stock building atlas, preserving its normalized UV
island positions, sizes, doors, vents and recognizable CCA markings. Corrupt
the metal with dark charcoal ribbed biomechanical Fury growth, cyan-blue nodes
and energy veins, matching the stock Fury reference. Partially overgrow the
CCA stars/numbers. Keep the atlas flat; no perspective, 3D model render or
rearranged UV islands. Apply this separately to command, hangar, power and tower.

Models are direct stock copies. Only material/skeleton resource names in the
mesh change; the copied skeleton and native SDF/VDF remain byte-identical.
Stock normal/specular/emissive aliases are retained. The source/copy hashes
and geometry counts are recorded in `asset-manifest.json`.

`Missions/misn16b.bzn` binds all ten enemy CCA structures to the copies.
It retains the stock mission class and amended terrain as the art baseline.
The shared runtime is now `Missions/misn16.bzn` / `Scripts/CRMisn16.lua`, with
an off-boundary Titan pad and the stock Fury transport assembly. The shipping
lock admits these assets. See `Docs/MISN16_COOP.md` for behavior and test limits,
and `Docs/MISN16_PLANNING.md` for the original source/cut-content audit.
