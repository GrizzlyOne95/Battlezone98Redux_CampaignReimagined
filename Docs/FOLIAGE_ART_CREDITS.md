# Foliage and forest art: credits and licence

The Mission 17 (Achilles) forest trees and rocks are adapted from **Low Poly
Forest Tree Pack** by **99.Miles**.

- Author: 99.Miles, <https://sketchfab.com/99.Miles>
- Source: <https://sketchfab.com/3d-models/low-poly-forest-tree-pack-5ff5a51e74324845a4e4905f182dfb2b>
- Licence: **Creative Commons Attribution 4.0 International** (CC-BY-4.0),
  <http://creativecommons.org/licenses/by/4.0/>. The licence and author are also
  recorded in the GLB's own `asset.extras`, which `Tools/Build-Misn17Forest.py`
  checks before it builds anything.
- Source file: `low_poly_forest_tree_pack.glb`, SHA-256
  `0e45ebd11053f28561201ccfcc6d0771e2dd1a60c38ae47942fadbd0cf09915b`.

Attribution is required. Anything that distributes these files, including the
Steam Workshop build, must carry this credit. CC-BY-4.0 does not require
derivatives to use the same licence; CR's adaptations keep this attribution.

## Changes made

`Tools/Build-Misn17Forest.py` produces every derived file from the GLB. The
changes are:

- **Split.** Four trees and the rock set were taken out of the single pack scene
  as separate Ogre meshes: `c17frst1`-`c17frst4` (trunk and branch submeshes)
  and `cr17_frock1`-`cr17_frock9`.
- **Scaled and re-based.** Each tree is centred on its trunk foot and scaled to
  a target height of 58, 46, 52 or 40 m. Rocks are scaled per placement.
- **Engine data added.** Each tree gained a one-bone skeleton, an SDF, a trunk
  prism collision GEO (written through the shared toolbox and toolkit), and a
  wind-sway vertex stream from `Tools/Bake-FoliageSway.py`.
- **Textures re-encoded.** Base colour was re-encoded to DXT1 or DXT5 with mips.
  Rock normals were halved to 512 px.
- **Normals converted.** The glTF normal maps (OpenGL, +Y) had their green
  channel flipped to the game's DirectX (-Y) convention.
- **Specular derived.** Specular maps (`*_s.dds`) were derived from the glTF
  roughness channel.
- **Tinted.** The branch material carries a slight cold tint
  (`$diffuse 0.86 0.94 0.96`).

| CR file | From |
|---|---|
| `cr17_fbranch1.dds`, `cr17_fbranch2.dds` | pack branch base colour |
| `cr17_ftrunk1*.dds`, `cr17_ftrunk2*.dds` | pack trunk base colour, normal, roughness |
| `cr17_frock.dds`, `cr17_frock_n.dds`, `cr17_frock_s.dds` | pack rock base colour, normal, roughness |
| `c17frst1`-`4` `.mesh/.skeleton/.sdf/.geo` | pack tree meshes |
| `cr17_frock1`-`9.mesh` | pack rock meshes |

`References/Misn17Forest/source-assets.json` records the SHA-256 of every source
consumed and every texture written.

## Ice props (not from the pack)

The ice props `c17bice*` and `c17dice*` come from the owner's **ISDF
Chronicles** mod (`GrizzlyOne95/ISDF_Chronicles`): `baneice1`-`4`, `darkice1`
and `darkice4`, plus the `iceberg*.dds` textures. The meshes were re-serialized
with the material `CR17/Ice` and renamed skeletons. Skeleton and SDF bytes,
and the textures, are unchanged copies. ISDFC was read only, never modified.
