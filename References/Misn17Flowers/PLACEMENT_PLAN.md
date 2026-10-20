# Achilles flower placement (applied)

`python Tools/Build-Misn17Flowers.py --place` writes the flowers into
`Scripts/CRJungle17Sites.lua` as render-only StaticGeometry layers:
`{mesh="cr17_fl_x.mesh", distance=150|220, instances={{x,y,z,yaw,scale},...}}`.
It needs no plates, uses a fixed seed and is idempotent: it removes any
`cr17_fl_` layers and reinserts them straight after the mire ground cover.
`Build-Misn17Forest.py` keeps every layer that is not a rock or ice layer and
appends ice and rocks after them, so rerunning it leaves the flowers in place.
`Build-Misn17Jungle.py` regenerates Sites from scratch, so rerun `--place`
after it. Never hand-edit the layers.

`Scripts/CRJungle17.lua` has three matching edits:

1. `CR17/FlowerWind`, `CR17/FlowerTallWind` and `CR17/CutoutCaster/FlowerTallWind`
   are in the `Foliage.Register` list, so the cards sway.
2. Each layer's `distance` sets its `renderingDistance` (the default is still
   260 for the mire, ice and rocks). Small plants use 150 m and tall plants
   (fireweed, lupine, ferns) use 220 m.
3. Flower layers feed the wake cover but not `Foliage.EnableLitter`, so leaf
   litter is unchanged.
   The `cr17_mire_` material override does not match them, so the flowers keep
   their own materials.

## Rules

Tile types are `mat >> 12` on the 20 m grid: 0 is open grass, 1 is forest and
2 is rock.

**Clump centres** are dart-thrown with a per-species minimum spacing, and are at
least 6 m from any other species' centre. Each centre is kept clear of every
bzn object by 30 m and of route points by 18 m, as the forest pass does.

**Plants** go within the clump radius of the centre. Every plant must be:
- inside the play area (x 780-3640, z 98430-101740);
- off the water grid (the watermask plus the river strip);
- on a slope of 0.9 or less;
- at least 2 m from a tree trunk (2.5 m for ferns).

The height is the bilinear HG2 height, sunk 3 cm per unit of scale. Each plant
gets a random yaw.

**Scale.** The cards are botanical size (a harebell is 0.3 m tall), so each
species gets a game scale to read beside the 3 m mire ferns.

| Species (meshes) | Centre rule | Clumps | Spacing | Per clump | Scale |
|---|---|---|---|---|---|
| grasses (`grass`, `grassseed`, `tuft`) | type 0, slope < .5; edge 6-20 m from trees, elsewhere 35 % | 260 | 25 m | 5-9 | 1.5-2.2 |
| harebell | type 0, slope < .47, ≥ 8 m from trees | 70 | 45 m | 3-7 | 1.7-2.4 |
| carpets (`anemone`, `bunchberry`, `twinflower`) | type 1, slope < .5, 3-15 m from trees | 180 | 30 m | 5-9 | 2.2-3.2 |
| lupine | type 0, slope < .36, ≥ 12 m from trees | 50 | 70 m | 3-5 | 1.3-1.8 |
| fireweed | type 0, slope < .36, ≥ 25 m from trees (clearings) | 35 | 80 m | 4-8 | 1.0-1.4 |
| cottongrass | not type 2, slope < .4, 2-12 m from water | 65 | 30 m | 5-9 | 1.5-2.2 |
| sedge | slope < .5, 1.5-8 m from water | 75 | 25 m | 4-8 | 1.5-2.2 |
| saxifrage | type 2, or within 4 m of a `cr17_frock` rock; slope < .9 | 70 | 30 m | 3-6 | 2.4-3.4 |
| ferns (`fern`, `fernb`) | type 1, slope < .6, ≤ 10 m from a tree | 200 | 20 m | 3-6 | 1.3-2.0 |

## Result

The layers are tiled per mesh on 1152 m tiles from (2048, 99328), like the
rocks. The pass writes 164 layers holding 5,312 instances, which is
34,198 triangles before culling. The mire ground cover alone is about 31,000
instances.

| Mesh | Instances | Mesh | Instances |
|---|---|---|---|
| anemone | 440 | grassseed | 519 |
| bunchberry | 391 | harebell | 290 |
| cottongrass | 405 | lupine | 171 |
| fern | 431 | saxifrage | 280 |
| fernb | 410 | sedge | 399 |
| fireweed | 180 | tuft | 502 |
| grass | 482 | twinflower | 412 |

CRJungle17 builds one layer per update, so the flowers add 164 updates to the
ground-cover stream, which runs after the mire layers and before ice and rocks.
