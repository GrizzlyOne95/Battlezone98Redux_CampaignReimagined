# Achilles flower placement plan (not applied)

This branch ships the `cr17_fl_*` meshes, `cr17_flowers.dds` and
`Materials/cr17_flowers.material`, but places nothing. `misn17.bzn` and
`Scripts/CRJungle17*.lua` are unchanged. This file describes the placement pass
that comes next.

## Mechanism

Add render-only StaticGeometry layers to `Scripts/CRJungle17Sites.lua`, in the
same shape as the existing ground cover:
`{mesh="cr17_fl_x.mesh", instances={{x,y,z,yaw,scale},...}}`. Generate them from
the placement pass in `Tools/Build-Misn17Jungle.py`, so they are tiled into the
same 384 m tiles that align with the 192 m regions from origin (2048, 99328).
Never hand-edit them. Heights come from the HG2 at 5 m cells. Tile types are
`mat >> 12` on the 20 m material grid.

Two edits to `CRJungle17.lua` come with the layers:

1. **Register the wind.** Add `CR17/FlowerWind`, `CR17/FlowerTallWind` and
   `CR17/CutoutCaster/FlowerTallWind` to the `Foliage.Register` list (about
   line 267). Unregistered, the cards render but stand still.
2. **Keep their materials.** The `cr17_mire_` material override (about line 379)
   does not match `cr17_fl_`. Keep it that way: the flowers use their own
   materials.

## Placement rules

- **Spacing.** Clumps are Poisson-disk scattered with the minimum spacing below.
  Each clump has 3 to 9 instances within a radius of 1.5 to 4 m, with random yaw
  and scale 0.8 to 1.3.
- **Keep-outs.** Keep clear of the routes, the base pads and every object
  footprint that the ground-cover pass already masks. Use the same masks.
- **Tile types.** Check tile types against `Build-Misn17Jungle.py`'s
  classification before placing. The brief calls the grass type 0 and the rocky
  type 2. The jungle script treats type 1 as forest and grass, and puts rocks on
  types 1 and 2.

| Mesh | Where | Clumps / km² | Min clump spacing | Per clump |
|---|---|---|---|---|
| `cr17_fl_grass`, `cr17_fl_grassseed`, `cr17_fl_tuft` | Through the existing grass (grass type), denser at forest edges (within 15 m of a tree site) | 220 | 25 m | 5-9 |
| `cr17_fl_harebell` | Grass type, open or edge, slopes under 25° | 60 | 45 m | 3-7 |
| `cr17_fl_anemone`, `cr17_fl_bunchberry`, `cr17_fl_twinflower` | Forest floor and edges, 4-20 m from a tree site; carpets | 90 (30 each) | 35 m | 5-9 |
| `cr17_fl_lupine` | Grass type, open ground and edges, slopes under 20° | 25 | 70 m | 3-5 |
| `cr17_fl_fireweed` | Open clearings only: grass type, at least 25 m from any tree site | 20 | 80 m | 4-8 |
| `cr17_fl_cottongrass` | Wet ground: within 12 m of the water mask or shore, above the waterline, never on ice | 70 | 30 m | 5-9 |
| `cr17_fl_sedge` | Shores and stream banks, 0-8 m from water | 80 | 25 m | 4-8 |
| `cr17_fl_saxifrage` | Rocky type, and within 3 m of `cr17_frock*` sites | 50 | 30 m | 3-6 |
| `cr17_fl_fern`, `cr17_fl_fernb` | Under trees: within 10 m of a tree site, alternating meshes | 110 | 20 m | 3-6 |

## Expected load

The existing mire ground cover is roughly 33,000 instances. Applied over the
playable forest, these densities add about 4,000 to 7,000 flower instances at
4 to 10 triangles each, which is under 60,000 triangles before tile culling.
Only the tall meshes (fireweed, lupine, ferns) cast shadows. Check the frame
time on a `C:\BZRCoop` instance once the layers exist.
