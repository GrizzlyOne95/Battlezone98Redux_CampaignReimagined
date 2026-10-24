# NSDF and Black Dog Wolverine light-tank cockpits

Owner direction: redo `avltnk` / `bvltnk`, reduce peripheral obstruction, and
keep the good exterior framing. Follow-up: matching faction flavor on the full
third-person bodies and cockpit-visible hull pieces, particularly black/red
stripes for Black Dog.

Based on `agent/fleet-cockpits-next5` at `3c217da8` (PR #314), preserving all
earlier accepted cockpit work. This is an **offline art-review prototype**;
no deployment, game launch, merge or publication.

## Cockpit and visibility

- Replace the tall, near-eye instrument walls and tiled overhead control slab
  with a low mechanical center bank, low side equipment and dropped service
  panel. Do not substitute a generic fighter canopy or add new forward pillars.
- Retain all 316 usable triangles of the original shell-weighted exterior frame
  from the body material batch: exact native positions, connectivity, UVs and
  normalized source normals. Keep the familiar painted rails and upper overhang.
- Use the accepted shared NSDF petrol/cyan and Black Dog charcoal/red mechanical
  atlases; do not create duplicate textures. Rectangular instrument insets retain
  their original pre-repack artwork proportions. Structural paint does not emit.
- Closed floor, rear and roof; one intentional canopy boundary, capped hardware,
  worn knee plates and treaded foot trays rather than unfinished black sheets.

Both stock eyes derive to `(0.0997999981, 1.4606999755, 0.1421000063)` with identity
native/rest basis. NSDF shell is `aln21bdb` / handle 13; Black Dog is `bln21bdb`
/ handle 15. Preserve each complete original rig byte-for-byte, including the
Black Dog's extra root nodes. Never assume shared shape means shared handles.

One-sided horizon-band rays sample yaw -85..-25 and +25..+85 degrees and pitch
-12..+12 degrees, one-degree steps. Same eye, same rays and original frame:

| Sector (model axis) | Before open | After open |
| --- | ---: | ---: |
| Negative X | 56.46% | 83.08% |
| Positive X | 58.16% | 85.51% |
| Combined | 57.31% | 84.30% |

These are specified angular samples, not a universal FOV or in-game screen-area
claim. First-person review renders use 16:9 and 64-degree vertical FOV without
moving the eye. Third-person views are auto-framed inspections. Two-sided POV
locator images are original diagnostic references, not final visibility proof.

## Exterior faction accents

Use surface-clipped paint layers on the forward hull rails: charcoal-backed
paired diagonal red slashes for Black Dog, subtler gunmetal/petrol for NSDF.
Reuse quiet frame/trim charts in the existing scout atlases. No new bitmap art,
texture aliases, broad glow, altered insignia, or changed underlying hull shape.

Both full vehicles and cockpit copies use the same native-coordinate band
planes and palette. Full-model paint follows each original body/shell bone;
cockpit copies retain the stable shell. Each full model retains every original
submesh, material, index, vertex attribute and bone assignment, adding only one
paint batch. The original exterior frame remains unchanged underneath the paint.

`source/avltnk.mesh` and `source/bvltnk.mesh` are immutable, byte-exact pre-paint
CR baselines, not shipped duplicate models. Builders read these and write the
painted `Assets/ModelFixes` outputs, so repeated builds do not accumulate layers.
The cockpit has 2,644 opaque triangles: 2,248 interior, 316 original frame and
80 paint. Four batches including weather glass; budgets are not measured native
draw-time or performance qualification.

## Rebuild and checks

```powershell
python Tools/Build-LightTankCockpits.py
python Tools/Test-LightTankCockpits.py
python Tools/Validate-CampaignRepository.py
```

The build needs the stock GOG asset source or explicit `--game` path; it does
not modify that source or an installed game. It uses existing shared model
codecs through `bzmodellibs.py`, not custom format readers/writers. Tests need
no game. Receipts pin baseline/rig/output hashes, POV, charts, original frame
triangles and paint-source provenance.

272 focused checks cover output pins/resource naming, stock rig and frame
identity, original full-vehicle surfaces/skinning, conforming paint layers,
palette/nonemissive charts, finite geometry and tangent bases, closure, central
aim clearance, peripheral improvement and compiled aspect-correct instrument UVs.
Original exterior texture files, native VDF/GEO records, ODFs, and earlier
cockpits remain untouched. Exterior `.mesh` changes are limited to appended paint.

Six new shipping members (two cockpit meshes, two copied rigs, two selectors),
zero removals; the full models already ship. `-bless` refused the same 51 absent
generated payloads in this fresh worktree. Membership-only insertion follows
the knowledge-base fallback, preserving the old lock sequence and LF without
fabricating files or dropping missing members. This does not deploy anything.

Review helpers are currently ignored `Local/LightTanks/` files derived from the
earlier fleet renderer. Saved `review/` images and receipts are the durable
artifact trail. The local gallery includes forward, down, console, both side
looks, roof/rear/floor, near-dark optics and full exterior inspections.

Native first-person loading, HUD/weather/damage behavior, recoil, animation,
paint depth behavior under game lighting, performance, and all runtime lanes
remain **unverified**: Windows/GOG, Windows/Steam, Linux/Steam/Proton and
Linux/GOG under Wine/Proton. Offline art approval is not native qualification.
