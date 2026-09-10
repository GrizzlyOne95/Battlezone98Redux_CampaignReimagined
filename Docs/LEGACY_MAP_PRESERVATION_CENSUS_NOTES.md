# Legacy Map Preservation Census Notes

This file records reconciliation caveats that should not be collapsed into assumptions while the census is still being built.

## Historical count discrepancy

Ssuser's historical page explicitly publishes these counts:

- Battlezone maps: 262
- Red Odyssey maps: 9
- Battlezone 1.5 maps: 21
- Mod/map packs: 9, containing 88 missions total

A prior manual row-counting pass appeared to produce a larger normal-Battlezone count. Until the source table is parsed mechanically and duplicates/variants are understood, **262 remains the published historical count and the higher working count is not treated as authoritative**.

## Catalog semantics

- A historical row is not automatically a missing Redux map.
- `Needs Workshop check` means exact-name and renamed/remade-port reconciliation is pending.
- `Verified missing` should only be used after that reconciliation.
- Alternate archive names and repaired historical ZIPs remain provenance even if only one Redux item is ultimately published.
- TRO originals take precedence over later BZ conversions when preserving TRO-specific behavior.
- Strategy maps are a selective lane; they should not be mixed into IA counts.

## Drive findings from the 2026-09-10 pass

The linked preservation folder contains complete archives for several active candidates, including Europa Snipe, Rabbit Hole, CCA Fun, A Call To Arms, The Return of Eagle's Nest 1, Sweet Venegence, and Rescue the 5th. Broader archived `Old Maps` storage also contains complete copies of Fury Hell, Macho Man, Payback, and War Zone.

The historical `Map readmes & pics` folder contains additional provenance for many old maps, including Alien Yard. These reference files are useful for author/title/version recovery but should not be mistaken for complete playable source archives.

## Release policy

Standalone Workshop publication is the default. CR is a development/preservation workspace, not a mandatory runtime dependency. Preserve coherent campaigns/packs as packs where splitting would damage their identity, progression, or shared-asset structure.
