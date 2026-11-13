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
| `svtank` CCA | Real exterior deck nose (red/blue paint) and the real cannon overhead; a small deck hatch with a thin trim coaming | Deck-nose hatch (owner review, Total Command layout idea, no assets): eye at vehicle (0.12, 1.62, 3.10), 15 cm above the deck just behind the muzzle; `svtank` hull and barrel unmoved. The opening is clipped out of the real deck; the barrel runs overhead to the VDF hardpoint and the deck nose frames the bottom of the view. The sunk tub walls are a mosaic of distinct atlas modules (no repeats); an open hatch lid behind the head closes rear and roof. |
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

Each hull apron is a bounded crop of original body-weighted front triangles,
with original UVs and one rigid fit. Owner follow-up replaces the inadequate
20-triangle Grizzly strips with the complete 448-triangle front group on each:
center sloped nose, painted markings, shoulders, bevels and recess walls. The
NSDF group pitches -3 degrees, Black Dog -15 degrees, about model point
`[0, 1.25, 1.10]`, with eye-relative tops of -0.54 and -0.44 m (owner reviews:
-12/-22 and then -5/-22 still read as a nose-up ramp; levelling fully hides the
hull behind the console, so the plates were lowered as well). The far edge now
sits about 21 degrees (NSDF) and 12 degrees (Black Dog) below the eye line, from
18 and 6.5. NSDF alone widens 1.35x across X (owner review: the nose read as a
narrow wedge); no other scaling, bending, mirroring, or eye adjustment. The
coaming extends underneath the rear crop to avoid sky slivers beside the warning
horns. On NSDF it drops and tapers to stay under the hull shoulders (they
clipped through it), and a leaning bulkhead under the plate's open near edge
stops the pilot eye seeing into the hull; the test casts for any such ray. The
right instrument pod mirrors the left pod's console strip, which previously cut
its top button row (both Grizzly cockpits). CCA 3 and CRA 10
triangles are unchanged. These are front groups, not complete exterior meshes.
Existing first-person guns remain separate from
the new, stable-shell interior skinning. ODFs, native VDF/GEOs, original exterior
meshes and existing materials are unchanged.

## Atlas reuse and provenance

NSDF and Black Dog use a generated per-unit panel atlas from
`Tools/tankpanelatlas.py` (armour plate, faction hazard sill bands, recessed pod
scopes, service grille). The pod, console and switch charts are copied from
the accepted scout atlas (`crvascp`/`crvbscp`) so the instrument faces keep
their earlier art; painted dials and toggles were rejected in review:

- NSDF: `crvatkp_d/e/N.dds`; `CRV/avtankTankPanels`.
- Black Dog: `crvbtkp_d/e/N.dds`; `CRV/bvtankTankPanels`.

The stock floor, spine strut and upper bridge stay; only the lower walls and
sloped sills (`stockReplacedTriangles` in `build.json`) are re-emitted, at the
same positions, as panels cut on face-local metric cells. The other factions
reuse accepted modular art:
- CRA: `../CVBomberCockpit/atlas-master.png` and `prompt.json`, compiled
  `crvchcp_d/e.dds`; only the small mechanical pilot/ordnance charts, not its
  large terrain screen.
- CCA: original `soviet_units_cockpit_d/n/S/e.dds`, deliberately re-UV'd onto
  new physical hardware. `svtank01` instead uses `crcca_cockpit_d/n/s/e.dds`,
  a 2048 repaint in the stock layout (same UVs) built by
  `Tools/Build-CCACockpitAtlas.py` from the owner-generated masters in
  `cca/atlas-src/` (prompts in `provenance.json`); other CCA units opt in by
  repointing their `*01` material. The shared liner borrows only the quiet charcoal
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

277 offline geometry/identity checks pass: finite tangent bases, nondegenerate
triangles, original gun skinning/UVs, bounded original hull crops, clear central
aiming corridors, floor/roof/rear closure, a single deliberate liner opening,
weather-glass ownership, output hashes and case-correct separate resource lookup.
At the 1-degree diagnostic angular sample grid, the CRA barrel occupies only
21 forward samples, with none in the central aiming corridor. This is not a
pixel or gameplay obstruction measurement. All tanks have five material batches
including weather, and 1,240–2,236 opaque triangles. Grizzly hull visibility
is tested against the entire one-sided cockpit, not the isolated hull: NSDF
418 and Black Dog 379 diagnostic angular samples, with both shoulders visible.
The original eye, dashboard geometry, gun parts and central aiming corridor
stay unchanged. `review/grizzly-hulls.jpg` compares the previous strip-only
pass with this revision from the identical forward cameras.

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
