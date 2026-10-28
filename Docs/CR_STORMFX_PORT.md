# CRStormFX port of the ISDF Chronicles weather stack

Source: ISDF Chronicles (ISDFC) at commit `0775645a1bcc7295fecdbac809f7e97cd1685759`
(`addon\ISDF Chronicles`, flat layout). All new names are `CR`/`crwx` prefixed so CR and ISDFC
can be loaded together without Ogre name collisions. Nothing here creates a Lua global and no
BZ API is called at require time.

## File mapping

| ISDFC | CR |
| --- | --- |
| `precip.lua` | `Scripts/CRPrecip.lua` |
| `isdfcsplash.lua` | `Scripts/CRSplash.lua` |
| `isdfclava.lua` | `Scripts/CRGroundFX.lua` |
| `effects.lua` (weather subset) | `Scripts/CRStormFX.lua` |
| `isdfc_precip.particle` (`ISDFC/*`) | `Materials/crwx_precip.particle.payload` (`CRWX/*`); listed in `CRParticleTemplates` `names` as `crwx_precip` |
| `isdfc_precip.material` (`ISDFC_FX/*`) | `Materials/crwx_precip.material` (`CRWX_FX/*`) |
| `isdfc_precip.program` | `Shaders/crwx_precip.program` (`CRWX_OgreParticle_*`; SM3 delegate `CR_Effect_vertexHLSL`) |
| `isdfc_ogre_particle-sm4.hlsl`, `-vertex.glsl` | `Shaders/crwx_ogre_particle-sm4.hlsl`, `crwx_ogre_particle-vertex.glsl` |
| `isdfc_fixedfunc.program` (5 of its programs) | `Shaders/crwx_fixedfunc.program` (`CRWX_FF_LitFlat2_vertex`, `CRWX_FF_ModAlphaBlend_NoFog_fragment`, and for cockpit glass `CRWX_FF_Lit1_vertex`, `CRWX_FF_Unlit1_vertex`, `CRWX_FF_Mod_NoFog_fragment`) |
| `isdfc_fixedfunc-sm4.hlsl` | `Shaders/crwx_fixedfunc-sm4.hlsl` |
| `isdfc_precip_{flake,mist,mote,streak}.png` | `Assets/Textures/crwx_precip_*.png` |
| `isdfc_splash_ripple.png`, `isdfc_fx_glow.png`, `isdfc_bootprint.png` | `Assets/Textures/crwx_splash_ripple.png`, `crwx_fx_glow.png`, `crwx_bootprint.png` |
| `wsplat.dds` | `Assets/Textures/crwx_wsplat.dds` (`Materials/wsplat.material` aliases it) |

## Public API

All modules degrade silently (return false/nil) when EXU is missing, is a stub (`isStub`), or lacks
particle support. Particle templates are loaded through `require("CRParticleTemplates").Ensure()`.

### CRStormFX (weather subset of effects.lua)
- `Update()` - per frame: flushes CRPrecip/CRSplash/CRGroundFX, steps the director if started, otherwise plays out hand-fired strikes and the flash once the environment is captured.
- `Shutdown()` - stops rain/acid/snow/dust, splash and strike particles, the rain loop, pending strikes and the director; restores the captured fog/ambient/sun once (no-op if nothing was written).
- `Rain(i)`, `AcidRain()`, `Lightning(perMinute, palette)`, `StrikeNow(cloudOnly, palette)`, `Atmosphere(fogScale, lightScale)`, `RainAndBolt("Light"|"Medium"|"Heavy")`.
- `StartDynamicWeather(saved, options)`, `UpdateDynamicWeather()`, `SetWeather(name, seconds)`, `GetWeather()`, `GetRainIntensity()`, `SeedRandom(n)` (tests).
- `Precip(kind, level)`, `Wind(x, z, speed)` - passthroughs to CRPrecip (and Wind also to CRSplash).
- `BaseEnvironment()` - the captured `{fog, amb, sun}` table or nil.
- The TRN lookup (FogEnd, VisibilityRange, world kind for the lightning palette) is lazy.

### CRPrecip
`Set(kind, level)` for `rain|acid|snow|dust` (true while particles draw it), `SetWind(x, z, speed)`, `Available()`.
Added: `Update()` (apply last frame's requests so unrequested kinds fade) and `Stop()` (destroy the systems).

### CRSplash
`Set(kind, level)` for `rain|acid|dust`, `SetWind(x, z, speed)`, `WetLevel()`, `Update()`.
Added: `Stop()` (destroy the systems).

### CRGroundFX
`Event(kind, pos, scale)` (`lava|toxic|stepdust|stepwet|strike|radiation|print00..15`), `SetColour(kind, r, g, b, a, key)`,
`Capacity(kind)`, `Print(pos, normal, heading, r, g, b, a, fade)`, `Bolt(x, ground, z, r, g, b)`, `BoltStroke()`, `Update()`.
Added: `Stop()` (destroy all systems).

## Dropped from effects.lua, and why

- Footprints/bootprints, `bootprint`, soil table: pilot gameplay cosmetics, not weather. (CRGroundFX still offers `Print`/`stepdust`/`stepwet`; the textures and templates ship.)
- Radiation, RandomEarthquakes, RandomAmbientTones, BubblingLava, BubblingAcid: separate hazards/ambience, not weather.
- Wetglass: first dropped, then ported as `CRWetGlass` (see "Windshield rain and cockpit glass"); CRStormFX requires it optionally.
- The load-time globals (`filename`, `odf`, `texture_type0_solidA0`, `world_variable`) and bare global functions; replaced by a lazy local TRN lookup and module fields.

## Asset decisions

Stock was checked against `BZ_ASSETS`, `BZ_ASSETS_CORE`, `StockODFFiles` and the contents of `bzone.zfs`/`bzone_en.zfs`;
CR against `Assets`, `ODF`, `Materials`, `Shaders`, `Scripts`. None of the leaves below exist in either (no collisions, no renames beyond the `crwx` set).
Stock sprite materials `grndchar.tga` and `lightflare.tga` (BZ2Render.material) are reused; the ODFs' `spark2.tga` and `smokeb2.tga` need the copied materials.

| Leaf | Decision |
| --- | --- |
| `xbolt{w,y}{1-4}.odf`, `xbsky{w,y}.odf`, `xbgnd{w,y}.odf`, `xbgnd{w,y}l.odf` | (c) copied to `ODF/` |
| `xpuddle`, `xrain`, `xraindr`, `xrainsp`, `xraina`, `xraindra`, `xrainspa` `.odf` | (c) copied to `ODF/` |
| `xlitbl{1,2,4}h.odf` | (c) copied to `ODF/` (light twins for CRWeather's bolt lights; not used by CRStormFX itself) |
| `erain01.wav`, `erain02.wav`, `thunder.wav`, `thund02.wav`, `xlitblt1.wav`, `xlitblt2.wav`, `xlitblt3.wav`, `atlas.wav` | (c) copied to `Assets/Sounds/` |
| `lbolt.material` ... `lbolt4.material`, `lbolt*.dds` | (c) copied (textures of the xbolt* sprites) |
| `spark2.material`, `spark2.dds`, `smokeb2.material`, `smoke2.dds` | (c) copied (xbgnd* sprite fallback) |
| `xrain.material`, `acidrain.material` (programs renamed `CRWX_FF_*`), `xrain.dds`, `xrainmask.dds`, `raintoxc.dds`, `raintoxc_mask.dds` | (c) copied (rain sheet fallback) |
| `xraindr.material`, `xrainsp.material`, `xraindr.png`, `xrainsp.png` | (c) copied (splash fallback) |
| `wsplat.material` | (c) copied but repointed at `crwx_wsplat.dds` so the texture ships once |
| `wsplat.dds` | not in CR or stock: shipped as `crwx_wsplat.dds` |
| `sprites.material` | not copied: CR already has it (provides `BZSprite/AlphaBlend`, `BZSprite/Additive`) |

Open point: the copied ODF and material names are the same as ISDFC's (identical content except `wsplat.material`,
`xrain.material`, `acidrain.material`). Loading both mods defines those materials twice.

## Windshield rain and cockpit glass

Ported from ISDFC `wetglass.lua` and `tools/cockpitglass.py` / `tools/ogrebin.py` (same ISDFC commit as above).
Rain drives it: `CRStormFX.Rain` / the director call `CRWetGlass.Update(intensity)` every frame (largest request of
the frame wins), `CRStormFX.Shutdown` calls `CRWetGlass.Stop()`.

### Mapping

| ISDFC | CR |
| --- | --- |
| `wetglass.lua` (module `wetglass`) | `Scripts/CRWetGlass.lua` (module `CRWetGlass`, overlay `crwx_wetglass`, EXU found as `package.loaded["exu"]` / `require("exu")`, `isStub` rejected) |
| `isdfc_wetglass.material` (`ISDFC_Wet*_A1..16`, `ISDFC_Wind*_A1..16`) | `Materials/crwx_wetglass.material` (`CRWX_WetBeads/WetStreak/WetRivulet/WindCrack/WindDirt_A<n>`) |
| `isdfc_wetglass.program`, `isdfc_wetglass.hlsl` | `Shaders/crwx_wetglass.program` (`CRWX_WetGlass_{vertex,fragment}_{SM3,SM4}`), `Shaders/crwx_wetglass.hlsl` |
| `isdfc_cockpitglass.material` | `Materials/crwx_cockpitglass.material` (`CRWX_CockpitGlass`, `CRWX_CockpitGlass_W<a>C<b>`), written by `Tools/cockpitglass.py --materials` |
| `ISDFC_FF_{Lit1,Unlit1}_vertex`, `ISDFC_FF_Mod_NoFog_fragment` | added to `Shaders/crwx_fixedfunc.program` as `CRWX_FF_*` (the existing `-sm4.hlsl` already had every variant) |
| `isdfc_wet{beads,rivulet,streak}.png`, `isdfc_wind{crack,dirt}.png`, `isdfc_wetmask_open.png` | `Assets/Textures/crwx_*.png` |
| `isdfc_wetmask_ivmsl2.png` (ISDFC unit only) | not shipped; `MASKS` in CRWetGlass.lua is empty, so every craft uses the open mask |
| `tools/cockpitglass.py`, `tools/ogrebin.py` | `Tools/cockpitglass.py`, `Tools/ogrebin.py` (authoring only, `Tools/` is not shipped) |
| `tools/wetglassgen.py`, `wetmaskgen.py`, `windshieldgen.py` | not ported: the generated textures and the generated material were copied. `wetmaskgen.py` needs OgreXMLConverter and a submesh named "Cockpit" per craft, so no stock-craft masks were made |

### API (CRWetGlass)

`Update(intensity 0..1)`, `Stop()` (hide overlays, put the glass back on the no-op material, forget state; the next
`Update` rebuilds), `Mode()` (`"shell"` = cockpit glass submesh, `"overlay"` = screen), `SetCrack(level, x, y)`,
`Splat(amount, x, y, flip)`, `Weather(kind, level)`, `Busy()`, `ClearSplats()`, `ScreenToShell(x, y)`. The crack layer
is not called by CR yet; splats come from `CRStorm18` and the Mars director. Without EXU, with a stub EXU, or without overlay support it does nothing.

Two modes:
- Screen overlay (any craft, F1/F2/F3 views): bead, rivulet, streak, crack and dirt panels with the open mask.
- Cockpit glass (F1 only): needs EXU with `exu.animation.TargetCockpit`, `exu.animation.GetCapabilities().glass`,
  `SetSubEntityRenderQueueGroup`, `SetSubEntityMaterial`, `SetMaterialTextureWindow`, `SetMaterialTexture`,
  `SetMaterialPassColors` (all present in CR `Bin/exu.dll`). The `CRWX_CockpitGlass` sub-entity of the cockpit
  entity is moved to render queue group 90 and given `CRWX_CockpitGlass_W<a>C<b>` (one pass per visible layer).
  A craft whose cockpit mesh has no glass submesh falls back to the overlay.

### Weather layers: snow flakes and dust grit

Two more wrap families ride the same glass, driven by weather directors rather than rain:
`CRWetGlass.Weather("frost" | "snow" | "grit", level 0..1)` stores a level that stays until changed, and the director
then calls `CRWetGlass.Update(0)` every frame while `CRWetGlass.Busy()` (or its level is above 0). Rain wins the
pass budget: the weather layers are the last wrap layers.

| Layer | Texture / materials | Behaviour | Driver |
| --- | --- | --- | --- |
| `frost` (`CRWX_WinFrost`, `CRWX_WinIce`) | `crwx_winfrost.png` (1024 x 512, not tileable), `crwx_winice.png` (1024 square, tileable); `CRWX_WinFrost_A1..16`, `CRWX_WinIce_A1..16`; pass tint 0.92 | Frost: fern-like crystal growth from the borders and corners, clear over the centre 55%, mapped once across the view (u, v 0..1 screen edge to edge; on the cockpit glass the window is computed from the screen edges as view angles), peak 0.55 x smoothstep(0, 0.5, level). Ice: sparse fine grains, rimed pits and short scratches, tiled with a fixed random scale and offset, peak 0.45 x smoothstep(0.45, 1, level). The glass eases the level at 1/40 per s up and down (about 40 s to grow), nothing slides. | `CREuropaWeather` (misn12, misn13) |
| `snow` (`CRWX_WinSnow`, two layers) | `crwx_winsnow.png`; `CRWX_WinSnow_A1..16` in `crwx_glassweather.material`; pass tint 0.92 | Sparse soft-white crystals and specks. Each layer gathers over 5-12 s, sits 14-32 s, melts over 10-22 s, then returns elsewhere (new offset and scale); the second layer only above level 0.47; peak opacity 0.21-0.60 of an already sparse sheet; a 0.003 UV/s slide. No streaks. | none now (kept for other callers) |
| `grit` (`CRWX_WinGrit`, two layers) | `crwx_wingrit.png`; `CRWX_WinGrit_A1..16`; standard glass tint | Fine tan-brown specks, a few clumps, a faint dust film. Fixed position (no motion); layer 1 follows the level over 0..0.5, layer 2 over 0.45..1.0; peak 0.5 each. The caller shapes the build and clear. | `CRMarsWeather` (misn04, 05, 06) |
| `acid` (`CRWX_AcidBeads`, `CRWX_AcidRivulet`, `CRWX_AcidStreak`; `CRWX_WinEtch`) | `crwx_acidbeads/acidrivulet/acidstreak.png` (the rain textures' alpha, tinted yellow-green), `crwx_winetch.png`; `CRWX_Acid*_A1..16`, `CRWX_WinEtch_A1..16`; etch pass tint 0.70 | While the level is above 0.02 the rain layers use the acid textures (chosen when a layer is not showing, so no drop recolours); the level also builds an etch exposure (level x 1/180 per s up, 1/720 per s down) that fades in one very faint pitted film, opacity up to 0.30 x smoothstep(0.08, 1, exposure), fixed position, last wrap layer. `Weather("acid", rain)` + `Update(rain)`: the rain layers themselves are driven by the `Update` intensity as for any rain. On the screen overlay the four acid textures are loaded once at the start by showing each panel alone for two frames at its faintest step (`warmUp`; see the live-check lesson in `Docs/AGENT_KNOWLEDGE_BASE.md`). | `CRVenusWeather` (misn07, 08, 09) |

`Tools/Generate-GlassWeatherAssets.py` writes the frost, ice, snow, grit, acid-rain and etch textures and the material (deterministic; `--check` compares). The
large snow crystals are the ISDF Chronicles snowflake sprite `snowflak.dds` (the texture its `giplume.odf` uses; ISDFC has
no dedicated snow-on-glass texture), converted from luminance to alpha, scattered at random sizes and angles over a
tileable 1024 square with specks; the generator reads it from the ISDFC addon folder only when it rewrites the snow
texture. Host test: `Tools/Test-CRWetGlassWeather.lua` (overlay and cockpit-glass modes, fade rates, opacity caps, and that
every overlay material and texture ships).

### Regenerating the cockpit glass

    python Tools/cockpitglass.py                       # every craft ODF -> Assets/ModelFixes, writes Tools/cockpitglass_report.txt
    python Tools/cockpitglass.py avtank svfigh --dry-run --render <dir>   # fit + preview PNGs, no files written
    python Tools/cockpitglass.py --materials           # rewrite Materials/crwx_cockpitglass.material
    .\Manage-CampaignFiles.ps1 -bless                # then add the new meshes to the shipping lock

Inputs: meshes and skeletons from `Assets/**` (so the `Assets/ModelFixes` copies win) over
`<game>/BZ_ASSETS/common/models/**` (including `TRO/`); ODFs from `ODF/` over `<game>/StockODFFiles`; material scripts
from `Materials/` over `BZ_ASSETS/pc/materials/**` (only used to recognise modelled canopy glass). `--game` or
`BZR_GAME_DIR` overrides the install path. Needs numpy (and Pillow for `--render`). The first-person mesh is chosen as the
engine does (0x0067F480): the table `avwalk -> avwalk_c`, `avturr -> _c`, `avartl -> _c`, `bv/sv/cv` likewise;
else `<base>_cockpit.mesh`; else the craft's own mesh if its skeleton has a `2` bone. So the walker/turret/artillery
glass lives in the `_c` meshes, not in `avwalk.mesh`. Output keeps the source's leaf name and is written to
`Assets/ModelFixes/`; re-running replaces an existing glass submesh (the ModelFixes copy becomes the source), so
the result is stable. Edge lists are dropped from rebuilt meshes (Ogre rebuilds them); every other chunk is
byte-identical (verified on all 51 outputs).

### Result

51 meshes carry glass (45 new files, 6 existing CR fixes rebuilt in place: `avturr_c`, `bvturr_c`, `bvwalk_c`,
`cvwalk_c`, `svturr_c`, `svwalk_c`), 0 failed, 28 units skipped (no file shipped):

- Generated: avapc avartl(_c) avfigh avhaul avhraz avltnk avmine avrckt avscav avtank avturr(_c) avwalk(_c);
  bvapc bvartl(_c) bvhaul bvhraz bvltnk bvmine bvmru bvraz bvrckt bvrdev bvscav bvtank bvturr(_c) bvwalk(_c);
  cvapc cvartl cvfigh cvhaul cvhraz cvhtnk cvltnk cvmine cvrckt cvscav cvtnk cvturr cvwalk(_c);
  svapc svartl(_c) svfigh svhaul svhraz svltnk svmine svrckt svscav svtank svturr(_c) svwalk(_c).
- Skipped, no cockpit (no `2` bone, no `_c`/`_cockpit` mesh): the towers (abtowe*, bbtowe, cbtowe, cblasr, sbtowe),
  constructors (avcnst bvcnst cvcnst svcnst), factories and recyclers (avmuf avrecy bvmuf bvrecy cvmuf cvrecy svmuf
  svrecy), avland, avtest, hvsat, hvsav, svsav.
- Skipped, no mesh in CR or stock: avsav, nvghst, svltnka.
- Failed: none.

Payload added: 45 new meshes 21.6 MB; the 6 rebuilt CR meshes shrink by 1.85 MB net (their edge lists were dropped);
textures 0.54 MB; materials, shaders and script 0.37 MB; about 20.7 MB net. The glass submesh itself is about 30 to 50 KB per mesh.
`Shipping/shipping.lock.json` gains the 56 new paths (nothing removed).

Open points: the `CRWX_CockpitGlass` no-op material is also on the world meshes (avtank etc. carry the submesh);
it draws nothing (`colour_write off`, no depth), as in ISDFC. Overriding stock meshes at their leaf names means a
mod that ships its own `avtank.mesh` wins and loses the glass (the overlay then takes over).
