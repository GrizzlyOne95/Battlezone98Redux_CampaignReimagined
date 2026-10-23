# Main battle tank cockpit detail pass

Offline art prototypes, stacked on `agent/scout-cockpits` at `95133095`.
No deployment, game launch, merge, or Workshop publication.

Owner direction: keep each tank's **soul**, add realistic detail where visible,
and include the CRA barrel. This pass uses a restrained roof-edge peek. Stay grounded in Battlezone,
not generic science-fiction avionics. No full-body/cockpit merge.

## Four distinct interiors

| Unit | Retained identity | Detail pass |
| --- | --- | --- |
| `avtank` NSDF | Wide window, raised warning horns, stepped control pods and service bridge | Petrol-painted cassettes, cyan button lenses, recessed bezels, caps and slotted fasteners; original-painted glacis |
| `bvtank` Black Dog | Same stock structural lineage, its own substantially lower eye and shell positions | Charcoal/red hardware, red lamps, original warning horns, new low liner and glacis |
| `svtank` CCA | Cream enamel, red seams, dark equipment, domed mechanical controls and overhead cannon | Rebuilt low, solid consoles and substantial window frames, practical side stations, closed charcoal liner |
| `cvtank` -> `cvtnk` CRA | Small split control banks, open center aisle, yellow braces, original ceiling | Oxblood instrument cassettes and guarded controls, fitted hull surface, original barrel underside just below the roof |

The NSDF, Black Dog and CRA original cockpit surface positions, triangles and
UVs are retained byte-for-byte as geometry arrays. New cassettes sit on their
existing faces. CCA's exceptionally thin, off-center shell is rebuilt rather
than retained. The complete original rigs, names and POV positions are copied
byte-for-byte. All original gun vertices, UVs and individual bone assignments
are retained. Only CRA's complete first-person barrel receives an art-directed
rigid offset: `[0, +0.02, +4.30]` m in the native POV frame. Its root is hidden
by the original ceiling, not left floating. This is a review fit, not native
animation or muzzle alignment qualification.

Each hull apron is a bounded crop of original body-weighted, upward-facing
front triangles, with original UVs and one rigid fitting translation. Counts
are NSDF 20, Black Dog 20, CCA 3, CRA 10 triangles. These are small hull hints,
not complete exterior meshes. Existing first-person guns remain separate from
the new, stable-shell interior skinning. ODFs, native VDF/GEOs, original exterior
meshes and existing materials are unchanged.

## Atlas reuse and provenance

**No new DDS or duplicate atlas.** Accepted modular art is reused:

- NSDF: `../ScoutCockpits/nsdf/atlas-master.png` and `prompt.json`, compiled
  `crvascp_d/e.dds`; `CRV/NSDFScoutCockpit`.
- Black Dog: `../ScoutCockpits/bdog/atlas-master.png` and `prompt.json`, compiled
  `crvbscp_d/e.dds`; `CRV/BDogScoutCockpit`.
- CRA: `../CVBomberCockpit/atlas-master.png` and `prompt.json`, compiled
  `crvchcp_d/e.dds`; only the small mechanical pilot/ordnance charts, not its
  large terrain screen.
- CCA: original `soviet_units_cockpit_d/n/S/e.dds`, deliberately re-UV'd onto
  new physical hardware. The shared liner borrows only the quiet charcoal
  chart in `crvascp_d/e.dds`; no NSDF paint, lamps or emblems appear on it.
- Stock warning marks, original equipment and selected exterior surfaces keep
  their existing faction maps. Existing stock functional lamp colors remain.

The accepted masters above were generated using built-in ImageGen; their exact
prompts and physical-lens masks remain beside them. New CCA/CRA atlas generation
was attempted but failed; no rejected image or CLI fallback was used. Keeping
the existing artwork also avoids redundant faction texture resources.

`Tools/Build-TankCockpits.py` uses shared model codecs via `bzmodellibs.py`.
It needs a stock GOG asset source (or `--game` alternative); tests do not.

```powershell
C:/Python314/python.exe Tools/Build-TankCockpits.py
C:/Python314/python.exe Tools/Test-TankCockpits.py
C:/Python314/python.exe Tools/Validate-CampaignRepository.py
```

Each faction's `build.json` pins source exterior/skeleton hashes, native VDF
hash, exact POV, output hashes, chart panel placements, gun weights, hull
triangle selection/offset, connected liner boundary, and refitted weather glass.
CCA's native `SCZ11POV` basis differs from its skeleton bind basis: use the
case-sensitive VDF GEO rotation with the unchanged bind position. Do not rotate
its rig to make a renderer look right. Other three native bases are identity.

## Review and limits

`review/` has forward, down, low-light optics, and same-camera before/after
images for all four. The local gallery additionally includes console, left,
right, roof, floor and rear. All use actual faction eye positions, native rest
orientations, one-sided faces and 64-degree vertical FOV. The old CCA view is
the actual same-camera problematic source, not an auto-framed comparison.

259 offline geometry/identity checks pass: finite tangent bases, nondegenerate
triangles, original gun skinning/UVs, bounded original hull crops, clear central
aiming corridors, floor/roof/rear closure, a single deliberate liner opening,
weather-glass ownership, output hashes and case-correct separate resource lookup.
At the 1-degree diagnostic angular sample grid, the CRA barrel occupies only
21 forward samples, with none in the central aiming corridor. This is not a
pixel or gameplay obstruction measurement. All tanks have five material batches
including weather, and 1,240–1,808 opaque triangles.

Adjacent scout (134 checks) and bomber (68 checks) regressions pass. Repository
validation passes. The shipping lock adds only 12 owned model/rig/material files:
`-bless` refused 51 missing pre-existing generated payloads in this fresh
worktree, so the documented membership-only fallback preserves every previous
entry and its order. Nothing was removed or replaced to bypass that refusal.

Static artwork is not live instrument telemetry. Native loading, HUD placement,
recoil, weather/damage rendering, graphics schemes, performance and all four
platform combinations (Windows/GOG, Windows/Steam, Linux/Steam/Proton,
Linux/GOG/Wine or Proton) remain unqualified. User review comes before those
tests or deployment.
