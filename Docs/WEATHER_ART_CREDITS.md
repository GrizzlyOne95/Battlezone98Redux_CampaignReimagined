# Weather billboard art — credits and licence

The weather and reactive-FX billboards in `Materials/CR_reactive.material` use
textures adapted
from **Kenshi Particle System Override** by **SCARaw**.

- Author profile: <https://www.nexusmods.com/kenshi/users/16691049>
- Mod: Kenshi Particle System Override (Nexus Mods, Kenshi, id 950), v3.4
- Licence: **Creative Commons Attribution-ShareAlike 4.0 International**
  (CC-BY-SA 4.0). Full text in `Docs/WEATHER_ART_LICENSE.txt`.

**ShareAlike applies.** These textures, and CR's adaptations of them, remain
under CC-BY-SA 4.0. Anything distributing them — including the Steam Workshop
build — must carry this credit and the licence file, and must not add terms that
restrict what the licence grants.

## Changes made

The files were **renamed only**. No pixels were altered: each `cr_*.dds` is a
byte-identical copy of its source, verified by SHA-256 after the copy. All
appearance changes come from CR's own particle scripts and material settings,
not from editing the art.

| CR texture | Source file | Why this one |
|---|---|---|
| `cr_haboob.dds` | `Haboob_Finger.dds` | 1265×619, peak alpha 199 — a large near-structureless dust veil that gets density from stacked cards |
| `cr_dustdevil.dds` | `TwisterDust_Large.dds` | 569×876 twister column, full alpha range |
| `cr_dust.dds` | `DustMite_DESERT.dds` | desert dust puff, peak alpha 198 |
| `cr_haze.dds` | `Sand-Wisp.dds` | peak alpha 182 — layers without stacking into a wall |
| `cr_dustsheet.dds` | `Long-wisp_version.dds` | peak alpha 68, the faintest in the set |
| `cr_grit.dds` | `DesertDetritus01.dds` | granular debris |
| `cr_iceveil.dds` | `Mist_Cloud_2.dds` | soft cloud veil |
| `cr_ash.dds` | `Ash_Flakez_Black_01.dds` | the alpha-carrying ash variant |
| `cr_snow.dds` | `Ash-Flake_Darker.dds` | flake silhouette; particle colour makes it white |
| `cr_rain.dds` | `Kenshi_Rain_Basic.dds` | opaque streak, additive by design |
| `cr_rainsplash.dds` | `Kenshi_Rain_Splash_basepart.dds` | opaque, additive by design |
| `cr_ember.dds` | `light_point.dds` | soft additive glow point |
| `cr_spore.dds` | `Fly-Particle_256.dds` | drifting mote with real alpha |
| `cr_slopewisp.dds` | `Snake-Wisps-Vertical.dds` | peak alpha 74, snakes vertically -- the volcano flank's own ground layer |
| `cr_smokethin.dds` | `smoke_trans1.dds` | alpha 0-246, wispy; the only alpha-carrying thin smoke in the set |
| `cr_smokeheavy.dds` | `Mist_Cloud.dds` | alpha 0-254, dense core; reads as SmokeThin getting worse |
| `cr_arc.dds` | `Lightning_Bolt2.dds` | bright bolt, additive by design |

## Why some are additive

Kenshi's rain textures are fully opaque — measured alpha 255 across the whole
image. That is not a defect: SCARaw's own materials declare `scene_blend add`,
so the black field composites away. CR's `CR_FX/Rain` and `CR_FX/RainSplash`
were `BZSprite/AlphaBlend`, which would have drawn solid rectangles, so they
moved to `BZSprite/Additive` to match how the art was authored.

`CR_FX/Spore` went the other way: its source carries real alpha, and additive
made a drifting mote glow like an ember.

## Selection method

Mappings were chosen from **measured** alpha range and dimensions, not from
source filenames. A texture with no alpha cannot drive an `alpha_blend`
material, and several plausible-sounding candidates (`DesertCloudStorm_Mite`,
`DustKick_Streak`, `Sand-Wisp_LIGHT`, `Ash-Flake_Light`) are fully opaque and
were rejected for that reason. `DesertCloudStorm_Mite` is also 2048×2048, far
past what a particle billboard needs.

## Reactive FX slots, added after the weather set

Four more textures were placed once the weather set was done. Three filled
`CR_FX` slots that `cr_reactive.particle` was already rendering with stock
Redux art (`smoke.png`, `shock.png`): `SmokeThin`, `SmokeHeavy` and `Arc`.

The fourth is `CR_FX/SlopeWisp`, which is new. `CR/Weather/SlopeDust` was
drawing `CR_FX/DustSheet` -- the plains card -- even though
`CRWeatherPresets.lua` describes the volcano flank layer as "slower, taller,
far more turbulent, climbing the flank rather than racing across it". A
vertically snaking wisp at the same faintness is what that description asks
for, so SlopeDust now has its own material.

Blend modes were again taken from SCARaw's own materials in the PSO tree, not
guessed: `Lightning_Bolt2` is `scene_blend add` there, the two smokes are
`alpha_blend`.

## Held back deliberately

`Vent_FastGas.dds` and `steam-vent-Top.dds` are good alpha-carrying steam
sources and would suit volcanic ground vents, but **CR has no consumer for
them**: there is no steam template and no director rung that would spawn one.
This file's sibling `CR_reactive.material` documents the same rule for the
damage-state materials -- a material with no consumer is not defined. If a vent
layer is ever authored, these two are the art.

`lightning.dds` is the one file in the mod with a **DX10 DDS header**
(`dxgiFormat` 72, BC1_UNORM_SRGB). Ogre 1.10 may not decode it. `Lightning_Bolt`
and `Lightning_Bolt2` are plain DXT1, so there is no reason to touch it.

Rejected on inspection rather than on filename: `FlameBall_01` (orange tendrils,
not the white-core bloom `CR_FX/Bloom` wants), `Acid-burn01` (near-black wisp,
nothing luminous for `BioLeak`), `lightning2` (red-dominant, will not tint to
`CR_FX/Ion`'s cyan), `Spark`/`SharpSpark`/`Spark4X` (4-8 pixels), and
`DriftingFoliage*`/`Ticker*` (seed pods, dry leaves and roots -- terrestrial
organic debris, wrong for Mars and the moons).

## Not yet verified in game

None of this has been through the engine. A `.dds` that Ogre cannot decode, or a
material whose blend mode is wrong for the art, fails quietly — see the standing
weather smoke-test debt. Confirm with `CRWeather.DescribeLiveSystems()` and a
clean `BZOgreLogfile.log` before shipping.
