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

## Ice slabs and the xplnxpl puff (not from the pack)

The shore-ice slabs `cr17_islab1`-`6` are built from the owner's **ISDF
Chronicles** mod (`GrizzlyOne95/ISDF_Chronicles`): the bergs `baneice2`, `baneice4`,
`baneice5`, `darkice1`, `darkice3` and `darkice4`, plus the `iceberg*.dds` textures.
Each berg is centred, scaled to a unit half-width and squashed to 15% of it, then
written as an unskinned mesh with the material `CR17/Ice`. Its UVs, triangles and
the textures are unchanged.

`ODF/xplnxpl.odf` (the trees' zero-damage explosion) and `Assets/Textures/smoke.dds`
are unchanged ISDFC copies. `Materials/smokeb.material` is ISDFC's, alpha-blended to
match the ODF. `amb_wind.wav` is stock. ISDFC was read only, never modified.

## Achilles flowers, ferns and grasses (botanical plates)

The `cr17_fl_*` cards are cut out of public-domain botanical plates and one CC0
texture by `Tools/Build-Misn17Flowers.py`. Each licence was read from the Wikimedia
Commons file page (`LicenseShortName`) or from ambientCG before the file was used.
The raw plates are not in the repository. The build script pins each plate's
SHA-256 and refuses to run on a different file.

| Card | Plate | Author | Licence | Bytes | SHA-256 |
|---|---|---|---|---|---|
| harebell | [Campanula rotundifolia, Thomé Bd. 4, Tafel 561](https://commons.wikimedia.org/wiki/File:Campanula_rotundifolia_%28Thom%C3%A9_Bd.4_1905%2C_BHL-81515%2C_Tafel_561%29_clean.jpg) | Otto Wilhelm Thomé (1904/05) | Public domain | 1256721 | `9863e9c83cd98b1d3eee693831a0626b2a66e5f1e21b468652abe639e3e31ce8` |
| fireweed | [Illustration Epilobium angustifolium0](https://commons.wikimedia.org/wiki/File:Illustration_Epilobium_angustifolium0.jpg) | Thomé, *Flora von Deutschland* series (Commons names no artist) | Public domain | 774337 | `58c254b9e4af2b5108a63bd3e32f6ef1311e68abb2e833b3a8afde8ef1f40c58` |
| anemone, anemone_leaf | [Illustration Anemone nemorosa0](https://commons.wikimedia.org/wiki/File:Illustration_Anemone_nemorosa0.jpg) | Walther Otto Müller | Public domain | 563045 | `9f9f9cb229241480609621db5b3302c43efd76f845b6d9e6cc8c481bc2c7b6b8` |
| bunchberry, bunchberry_top | [Cornus canadensis HdB2](https://commons.wikimedia.org/wiki/File:Cornus_canadensis_HdB2.png) | Charles Louis L'Héritier de Brutelle (1788) | Public domain | 1520809 | `13dbc5c0b804e5febb210df00fef6dd1bafd7af2a7efc88c615d07fbac04b5b7` |
| twinflower | [Linnaea borealis Sturm12046](https://commons.wikimedia.org/wiki/File:Linnaea_borealis_Sturm12046.jpg) | Jacob Sturm (1796) | Public domain | 218597 | `bf9b927a2779a20e04447cb5966c5704edc7c9115183e81213cb4e4ea817320e` |
| cottongrass | [Eriophorum polystachion, Flora Batava vol. 1](https://commons.wikimedia.org/wiki/File:Eriophorum_polystachion_%E2%80%94_Flora_Batava_%E2%80%94_Volume_v1.jpg) | Jan Kops (1800) | Public domain | 474095 | `ecf87e96d85b14a2a2ebe15e1e05497e02cb7ba41cd53ca3e3cf4eafc26172a3` |
| saxifrage | [Saxifraga oppositifolia Sturm54](https://commons.wikimedia.org/wiki/File:Saxifraga_oppositifolia_Sturm54.jpg) | Johann Georg Sturm, painted by Jacob Sturm (1796) | Public domain | 237605 | `2d3a5e83e8294fc97ba2caeefb7ee349ca9948551306065fc4e74273c3f6651b` |
| lupine | [Lupinus polyphyllus Lindley 1827](https://commons.wikimedia.org/wiki/File:Lupinus_polyphyllus_Lindley_1827.jpg) | John Lindley (1827) | Public domain | 1004236 | `36a370a4a66e654db363d64e3875f18566dcf3834342ac0273df4811032d227b` |
| fern | [Athyrium filix-femina Moore30](https://commons.wikimedia.org/wiki/File:Athyrium_filix-femina_Moore30.png) | Thomas Moore, ed. John Lindley, nature-printed by Henry Bradbury (1857) | Public domain | 1858321 | `f244eee97d15dfd6a29b27a42ea55af8c50be531e28f87c3ebb89ba99078043a` |
| fern_b | [Illustration Athyrium filix-femina0](https://commons.wikimedia.org/wiki/File:Illustration_Athyrium_filix-femina0.jpg) | Thomé, *Flora von Deutschland* series (Commons names no artist) | Public domain | 1192831 | `4db4335856c91bd3a3d409e5071698b45d1a06bb4be189217a0ecc5b544a1b00` |
| grass, grass_seed | [Illustration Festuca ovina0](https://commons.wikimedia.org/wiki/File:Illustration_Festuca_ovina0.jpg) | Thomé, *Flora von Deutschland* series (Commons names no artist) | Public domain | 604702 | `d4c8e7f049cc7684a455d39ac69e21b6c889c28bdd8f98b7c9975313e830dd66` |
| sedge | [Carex vulgaris, Flora Batava vol. 12](https://commons.wikimedia.org/wiki/File:Carex_vulgaris_%E2%80%94_Flora_Batava_%E2%80%94_Volume_v12.jpg) | Jan Kops et al. (1865) | Public domain | 696542 | `0aa26da033370c0c7338bc156b0bea3194cec32f2b4a3adb1f4d345975beee9b` |
| tuft | [ambientCG Foliage006](https://ambientcg.com/view?id=Foliage006) (`Foliage006_1K-PNG.zip`, Color and Opacity maps) | ambientCG (Lennart Demes) | CC0 | 6131155 | `273edcdf98fea19255ef90266a3123c2c0054d0f995b4ec7c680daf9aea679fa` |

Two more plates were downloaded and checked but are **not used**:

| Plate | Author | Licence | Bytes | SHA-256 | Why unused |
|---|---|---|---|---|---|
| [Twinflower by Rosa Fiveash](https://commons.wikimedia.org/wiki/File:Twinflower_by_Rosa_Fiveash.jpg) | Rosa Catherine Fiveash | CC0 | 284981 | `d822d23a4372b8656395dd71c3194aef179e8105b68fa694eb2ab06e1fd4b636` | It shows a yellow-green, bell-flowered Australian plant, not *Linnaea borealis*. Sturm's plate is used instead. |
| [Epilobium angustifolium, Flora Batava vol. 19](https://commons.wikimedia.org/wiki/File:Epilobium_angustifolium_%E2%80%94_Flora_Batava_%E2%80%94_Volume_v19.jpg) | Jan Kops et al. (1893) | Public domain | 913459 | `efb252a7fb827f31576558777d51a7e6c9016e856d802a3bf9ff5414e9d3f522` | Alternate fireweed. The primary plate keyed well enough. |

**Changes made to the plates:**

- **Cut out.** The paper was removed by colour distance from an estimated paper
  field. Enclosed paper holes were filled only when they were not paper-coloured.
  Plate text, numbers, dissection details and neighbouring plants were erased.
- **Recoloured.** Greens were graded toward Achilles' cool, slightly desaturated
  palette, and flower hues were steered to read clearly in game.
  - Bunchberry's plate is an uncoloured engraving, so it was colourised: green
    leaves, white bracts and red berries.
  - The saxifrage petals were painted purple.
- **Composed.** The `tuft` card was composed from the Foliage006 blades.
- **Packed.** All cards were packed onto one 2048 DXT5 atlas with mips.

`References/Misn17Flowers/source-assets.json` records the plates, the atlas
rectangles and the mesh hashes.
